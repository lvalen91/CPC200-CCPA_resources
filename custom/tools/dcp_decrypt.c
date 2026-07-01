/* dcp_decrypt.c
 * Drives the i.MX6ULL DCP crypto engine directly via /dev/mem to replicate
 * u-Boot's do_decrypt_decompress() kernel-decrypt path from Linux userspace.
 *
 * usage: dcp_decrypt <cfg0_hex> <cfg1_hex> <total_len> < ciphertext > plaintext
 *
 * Reads <total_len> bytes of ciphertext from stdin, decrypts via the DCP
 * AES-128-CBC engine (KEY_SELECT=0xfe = OTP unique key, IV = cfg0|cfg1|0|0),
 * writes plaintext to stdout. Diagnostics go to stderr.
 */
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/mman.h>
#include <errno.h>

#define DCP_BASE   0x02280000UL
#define DCP_MAPLEN 0x1000UL
#define OCRAM_BASE 0x00905000UL
#define OCRAM_LEN  0x1B000UL

#define DATA_BUF_OFF   0xB000UL   /* -> phys 0x00910000, 0x10000 bytes to end of OCRAM map */
#define DATA_BUF_PHYS  (OCRAM_BASE + DATA_BUF_OFF)
static uint32_t CHUNK_MAX = 0x10000UL;

/* regs, byte offsets from DCP_BASE */
#define REG_CTRL        0x00
#define REG_CTRL_SET    0x04   /* stmp "SCT" aliasing: base+4=SET, base+8=CLR, base+0xC=TOGGLE */
#define REG_CTRL_CLR    0x08
#define REG_STAT        0x10
#define REG_STAT_CLR    0x18
#define REG_CHANNELCTRL 0x20
#define REG_CONTEXT     0x50
#define REG_CH0CMDPTR   0x100
#define REG_CH0SEMA     0x110
#define REG_CH0STAT     0x120
#define REG_CH0STAT_CLR 0x128

#define STMP_SFTRST   0x80000000UL
#define STMP_CLKGATE  0x40000000UL

struct dcp_desc {
    uint32_t next;
    uint32_t control0;
    uint32_t control1;
    uint32_t source;
    uint32_t destination;
    uint32_t size;
    uint32_t payload;
    uint32_t status;
};

static volatile uint32_t *dcp_regs;
static volatile uint8_t  *ocram;

static inline void barrier_dsb(void) {
    __asm__ __volatile__ ("dsb" ::: "memory");
}

static uint32_t reg_read(unsigned off) {
    return *(volatile uint32_t *)((volatile uint8_t *)dcp_regs + off);
}
static void reg_write(unsigned off, uint32_t val) {
    *(volatile uint32_t *)((volatile uint8_t *)dcp_regs + off) = val;
}

/* exact port of lib/stmp_device.c stmp_reset_block(), the real recipe used
 * by every "mxs"-family Freescale/NXP peripheral driver (DCP included). */
static int stmp_clear_poll_bit(unsigned base_off, uint32_t mask) {
    int timeout = 0x400;
    reg_write(base_off + 0x8 /* CLR alias */, mask);
    usleep(1);
    while ((reg_read(base_off) & mask) && --timeout) { /* spin */ }
    return !timeout;
}

static int stmp_reset_block(unsigned base_off) {
    if (stmp_clear_poll_bit(base_off, STMP_SFTRST)) return -1;
    reg_write(base_off + 0x8, STMP_CLKGATE); /* clear CLKGATE */
    reg_write(base_off + 0x4, STMP_SFTRST);  /* SET alias: assert SFTRST */
    usleep(1);
    int timeout = 0x400;
    while (!(reg_read(base_off) & STMP_CLKGATE) && --timeout) { /* spin */ }
    if (!timeout) return -1;
    if (stmp_clear_poll_bit(base_off, STMP_SFTRST)) return -1;
    if (stmp_clear_poll_bit(base_off, STMP_CLKGATE)) return -1;
    return 0;
}

int main(int argc, char **argv) {
    if (argc < 4) {
        fprintf(stderr, "usage: %s <cfg0_hex> <cfg1_hex> <total_len> [chunk_size]\n", argv[0]);
        return 2;
    }
    uint32_t cfg0 = (uint32_t)strtoul(argv[1], NULL, 16);
    uint32_t cfg1 = (uint32_t)strtoul(argv[2], NULL, 16);
    long total = strtol(argv[3], NULL, 10);
    if (total <= 0) { fprintf(stderr, "bad total_len\n"); return 2; }
    if (argc >= 5) CHUNK_MAX = (uint32_t)strtoul(argv[4], NULL, 10);
    /* data_buf lives at OCRAM_BASE+DATA_BUF_OFF inside a fixed-size /dev/mem
     * mmap of only OCRAM_LEN bytes -- a chunk that doesn't fit writes past
     * the mapped region into unmapped memory and segfaults. Clamp instead
     * of trusting the caller (this exact mistake was made once already:
     * passing chunk_size == total_len to try a single u-Boot-style
     * whole-file descriptor crashed the tool on the device). */
    uint32_t max_chunk = (uint32_t)(OCRAM_LEN - DATA_BUF_OFF);
    if (CHUNK_MAX > max_chunk) {
        fprintf(stderr, "chunk_size %u exceeds OCRAM data buffer capacity %u, clamping\n",
                CHUNK_MAX, max_chunk);
        CHUNK_MAX = max_chunk;
    }

    uint8_t *ct = malloc(total);
    uint8_t *pt = malloc(total);
    if (!ct || !pt) { fprintf(stderr, "malloc fail\n"); return 1; }

    long got = 0;
    while (got < total) {
        ssize_t n = read(0, ct + got, total - got);
        if (n <= 0) { fprintf(stderr, "short read at %ld/%ld (n=%zd errno=%d)\n", got, total, n, errno); return 1; }
        got += n;
    }

    int fd = open("/dev/mem", O_RDWR | O_SYNC);
    if (fd < 0) { perror("open /dev/mem"); return 1; }

    void *m1 = mmap(NULL, DCP_MAPLEN, PROT_READ | PROT_WRITE, MAP_SHARED, fd, DCP_BASE);
    if (m1 == MAP_FAILED) { perror("mmap dcp"); return 1; }
    dcp_regs = (volatile uint32_t *)m1;

    void *m2 = mmap(NULL, OCRAM_LEN, PROT_READ | PROT_WRITE, MAP_SHARED, fd, OCRAM_BASE);
    if (m2 == MAP_FAILED) { perror("mmap ocram"); return 1; }
    ocram = (volatile uint8_t *)m2;

    volatile uint32_t *payload_buf = (volatile uint32_t *)(ocram + 0x00);
    volatile struct dcp_desc *desc = (volatile struct dcp_desc *)(ocram + 0x20);
    volatile uint8_t *data_buf = ocram + DATA_BUF_OFF;

    payload_buf[0] = cfg0;
    payload_buf[1] = cfg1;
    payload_buf[2] = 0;
    payload_buf[3] = 0;

    fprintf(stderr, "pre-reset: CTRL=0x%08x STAT=0x%08x CHANNELCTRL=0x%08x\n",
            reg_read(REG_CTRL), reg_read(REG_STAT), reg_read(REG_CHANNELCTRL));

    /* exact port of the real mxs-dcp.c probe() init sequence, run twice as
     * a bounded "warm up" (2 attempts max, not an open-ended retry storm). */
    for (int i = 0; i < 2; i++) {
        if (stmp_reset_block(REG_CTRL)) {
            fprintf(stderr, "stmp_reset_block TIMED OUT -- aborting, not touching hardware further\n");
            return 4;
        }
        barrier_dsb();
        usleep(2000);
    }

    reg_write(REG_CTRL, 0x00C0000FUL); /* GATHER_RESIDUAL_WRITES|ENABLE_CONTEXT_CACHING|0xf */
    reg_write(REG_CHANNELCTRL, 0xFFUL);
    reg_write(REG_CONTEXT, 0xFFFF0000UL);
    reg_write(REG_CH0STAT_CLR, 0xFFFFFFFFUL);
    reg_write(REG_STAT_CLR, 0xFFFFFFFFUL);
    barrier_dsb();

    fprintf(stderr, "post-reset: CTRL=0x%08x STAT=0x%08x CHANNELCTRL=0x%08x CH0SEMA=0x%08x\n",
            reg_read(REG_CTRL), reg_read(REG_STAT), reg_read(REG_CHANNELCTRL), reg_read(REG_CH0SEMA));

    /* NOTE: deliberately NO per-chunk soft-reset retry loop here. Repeatedly
     * cycling SFTRST/CLKGATE on failure is what wedged the board last time
     * (shared reset domain, single-core CPU starved by the busy-poll spun
     * the watchdog past its limit). One clean reset at startup (above), one
     * attempt per chunk, yield the CPU while polling, bail out immediately
     * and cleanly on any failure -- no hardware-touching retries. */
    long off = 0;
    int chunk_no = 0;
    while (off < total) {
        uint32_t clen = (total - off > (long)CHUNK_MAX) ? CHUNK_MAX : (uint32_t)(total - off);

        memcpy((void *)data_buf, ct + off, clen);

        desc->next         = 0;
        desc->control0      = (chunk_no == 0) ? 0x723UL : 0x523UL;
        desc->control1       = 0xfe10UL;
        desc->source         = (uint32_t)DATA_BUF_PHYS;
        desc->destination    = (uint32_t)DATA_BUF_PHYS;
        desc->size           = clen;
        desc->payload        = (uint32_t)OCRAM_BASE; /* payload_buf phys addr */
        desc->status         = 0;

        barrier_dsb();
        usleep(200);

        /* the actual bug found via the real mxs-dcp.c driver source: clear
         * the PER-CHANNEL status register before every submission, not just
         * the global one. */
        reg_write(REG_CH0STAT_CLR, 0xFFFFFFFFUL);
        barrier_dsb();

        reg_write(REG_CH0CMDPTR, (uint32_t)(OCRAM_BASE + 0x20));
        barrier_dsb();
        usleep(200);
        reg_write(REG_CH0SEMA, 1);
        barrier_dsb();

        /* bounded poll, yielding the CPU periodically so we never starve
         * other processes (this single-core board has a watchdog). */
        uint32_t stat = 0;
        long spins;
        int timed_out = 1;
        for (spins = 0; spins < 2000; spins++) {
            stat = reg_read(REG_STAT);
            if ((stat & 0xF) != 0) { timed_out = 0; break; }
            usleep(500); /* ~2000 * 500us = 1s max wait per chunk */
        }

        if (timed_out) {
            fprintf(stderr, "chunk %d: TIMEOUT (stat=0x%08x) off=%ld len=%u -- aborting, no reset/retry\n",
                    chunk_no, stat, off, clen);
            return 3;
        }

        reg_write(REG_STAT_CLR, stat);
        barrier_dsb();
        uint32_t stat_after = reg_read(REG_STAT);
        uint32_t chstat = reg_read(REG_CH0STAT);
        uint32_t err = desc->status;
        fprintf(stderr, "chunk %d: off=%ld len=%u spins=%ld stat=0x%08x stat_after_clr=0x%08x ch0stat=0x%08x desc.status=0x%08x%s\n",
                chunk_no, off, clen, spins, stat, stat_after, chstat, err,
                (chstat & 0xff) ? "  <-- REAL ERROR (CH0STAT&0xff != 0)" : "");

        memcpy(pt + off, (void *)data_buf, clen);

        off += clen;
        chunk_no++;
    }

    ssize_t wrote = 0;
    while (wrote < total) {
        ssize_t n = write(1, pt + wrote, total - wrote);
        if (n <= 0) { perror("write stdout"); return 1; }
        wrote += n;
    }

    fprintf(stderr, "done: %ld bytes, %d chunks\n", total, chunk_no);
    return 0;
}
