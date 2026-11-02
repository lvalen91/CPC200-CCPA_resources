/* SPDX-License-Identifier: GPL-3.0-or-later
 * ocbm-accessory: serve the Android-accessory-style device node `/dev/usb_accessory` that ocbmd
 * (ccpa/ocbmd) opens, on a mainline kernel that has no accessory gadget function, using FunctionFS.
 *
 * What ocbmd expects (ccpa/ocbmd/src/main.rs: ACC_DEV, the single read-write fd, O_NONBLOCK, poll
 * for POLLIN/POLLOUT, exit on EOF/EIO/POLLHUP): ONE bidirectional node that behaves like a stream of
 * OCBM frames. OCBM frames are self-delimiting (16-byte header with magic + length, ocbm-proto
 * `Reassembler` on both ends), so no transfer boundary has to survive the relay; what DOES matter on
 * the USB side is that every device->host transfer ends in a short packet, because the hosts read with
 * a fixed buffer and a bounded timeout and drop a transfer that times out (ocbm-host `recv`; the stock
 * firmware had to turn `accZLP=Y` on for the same reason, ccpa/rootfs/script/ocbm_boot.sh).
 *
 * How: a pseudo-terminal pair in raw mode. ocbmd opens the slave through the symlink
 * /dev/usb_accessory; this program owns the master and the two FunctionFS bulk endpoint files and
 * pumps bytes between them with two threads. The pty gives ocbmd real poll() semantics (readable only
 * with data, writable only with room), a hangup when the USB function is disabled (the stock
 * accessory fd's teardown behaviour, which ocbmd takes as "exit for respawn"), and a node that is
 * open(2)-able by path, which a socket is not. A FIFO is one-way; a CUSE device would need FUSE in
 * the kernel. The pty's line discipline is set raw (cfmakeraw, IXOFF off, VMIN 1, VTIME 0) before
 * ocbmd is started, so every byte value passes unchanged; the master side of a Unix98 pty is raw by
 * construction (drivers/tty/pty.c unix98_pty_init: iflag 0, oflag 0, lflag 0).
 *
 * The program also spawns and respawns ocbmd (CMD): a new pty per generation, so an exited or
 * hung-up ocbmd never reads another generation's bytes, like /script/run_ocbmd.sh on the stock
 * firmware. It serves ep0 (descriptors: one vendor interface 0xFF/0xFF/0x00 with bulk IN + bulk OUT,
 * the shape of the stock g_android_accessory interface; events; every SETUP addressed to the
 * interface or an endpoint is stalled).
 *
 * The gadget itself (idVendor/idProduct/strings/UDC) is configfs, done by common/shared/net-up ocbm:
 *   mkdir functions/ffs.ocbm; mount -t functionfs ocbm <dir>; start THIS (it writes the descriptors;
 *   <dir>/ep1 and <dir>/ep2 appear); link the function into the config; write the UDC.
 *
 * Host -> device reads are ONE wMaxPacketSize PACKET per FunctionFS read (512 at high speed). A UDC
 * completes an OUT request only on a short packet or when the request's buffer is full, and the OCBM
 * hosts send a frame as one bulk transfer with no ZLP: a 512-byte frame (496-byte payload) read with a
 * 16 KiB request therefore sits in the controller until something else arrives — ocbm-host's request/
 * response ECHO never gets its reply (seen on the IW416 unit 2026-10-30, `echo … 496`: 0 bytes). A
 * request of exactly one packet completes on every packet, full or short, whatever the host does; the
 * cost is one read per packet, which the Cortex-A7 sustains far above OCBM's host->device needs.
 * (The stock accessory driver queued min(read size, 16 KiB) and ocbmd reads 64 KiB, so the stock
 * firmware had the same hang for a lone full-packet frame; nothing in OCBM depends on it.)
 *
 * Test mode (-T SOCK): the FunctionFS files are replaced by a connected AF_UNIX SOCK_DGRAM pair; one
 * datagram = one USB PACKET host->device (the relay gathers packets into a read exactly as a UDC
 * completes a request: until a short packet or the request size) and one datagram = one USB transfer
 * device->host (a zero-length datagram = a ZLP); the function starts ENABLED, SIGUSR1 = DISABLE,
 * SIGUSR2 = ENABLE. common/tools/ocbm-accessory-test.py drives it (selftest.sh step 9).
 */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <pthread.h>
#include <signal.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/un.h>
#include <sys/wait.h>
#include <termios.h>
#include <time.h>
#include <unistd.h>

/* UAPI of FunctionFS (include/uapi/linux/usb/functionfs.h) and USB ch9, spelled out so this builds
 * against any libc's headers (zig/musl on the Mac, glibc in the chroot, musl in the recipe). */
#define FFS_DESCRIPTORS_MAGIC_V2 3u
#define FFS_STRINGS_MAGIC 2u
#define FFS_HAS_FS_DESC 1u
#define FFS_HAS_HS_DESC 2u
enum { FFS_EV_BIND, FFS_EV_UNBIND, FFS_EV_ENABLE, FFS_EV_DISABLE, FFS_EV_SETUP, FFS_EV_SUSPEND, FFS_EV_RESUME };
#define FFS_IOC_ENDPOINT_DESC _IOR('g', 130, struct usb_ep_desc)
#define USB_DIR_IN 0x80
#define USB_DT_INTERFACE 4
#define USB_DT_ENDPOINT 5
#define USB_CLASS_VENDOR 0xff

#pragma pack(push, 1)
struct usb_if_desc {
    uint8_t bLength, bDescriptorType, bInterfaceNumber, bAlternateSetting, bNumEndpoints;
    uint8_t bInterfaceClass, bInterfaceSubClass, bInterfaceProtocol, iInterface;
};
struct usb_ep_desc { /* usb_endpoint_descriptor_no_audio */
    uint8_t bLength, bDescriptorType, bEndpointAddress, bmAttributes;
    uint16_t wMaxPacketSize;
    uint8_t bInterval;
};
struct ffs_speed_descs {
    struct usb_if_desc intf;
    struct usb_ep_desc in, out; /* ep1 = bulk IN (device->host), ep2 = bulk OUT (host->device) */
};
struct ffs_descs {
    uint32_t magic, length, flags;
    uint32_t fs_count, hs_count;
    struct ffs_speed_descs fs, hs;
};
struct ffs_strings {
    uint32_t magic, length, str_count, lang_count;
};
struct usb_ctrlreq {
    uint8_t bRequestType, bRequest;
    uint16_t wValue, wIndex, wLength;
};
struct ffs_event {
    union {
        struct usb_ctrlreq setup;
    } u;
    uint8_t type;
    uint8_t pad[3];
};
#pragma pack(pop)

#ifndef SOCK_CLOEXEC
#define SOCK_CLOEXEC 0 /* BSD/macOS lint only: the target is Linux (test mode -T is Linux-only anyway) */
#endif
#ifndef MSG_NOSIGNAL
#define MSG_NOSIGNAL 0
#endif

#define XFER_MAX 16384 /* one USB transfer per write/read; the stock accessory driver's buffer size */
#define HS_MAXPACKET 512
#define FS_MAXPACKET 64

static const char *g_ffs = "/run/ocbm/ffs";
static const char *g_dev = "/dev/usb_accessory";
static const char *g_pidfile = NULL;
static const char *g_childlog = NULL;
static const char *g_test_sock = NULL;
static int g_keep = 0;    /* -k: do not hang ocbmd up on DISABLE */
static int g_verbose = 0;
static char **g_cmd = NULL;

static int g_ep0 = -1, g_ep_in = -1, g_ep_out = -1; /* test mode: ep_in == ep_out == the socket */
static int g_maxpacket = HS_MAXPACKET;
static int g_out_read = 0;  /* -r: bytes per host->device read; 0 = one packet (wMaxPacketSize) */

/* The current pty generation. Pump threads read the master through cur_master(); the main thread is
 * the only writer. A generation ends when the child exits, when the slave side closes, or on DISABLE. */
static pthread_mutex_t g_lock = PTHREAD_MUTEX_INITIALIZER;
static int g_master = -1;
static unsigned g_gen = 0;
static volatile int g_enabled = 0;     /* written by the main thread AFTER g_maxpacket (release/acquire) */
static volatile int g_slave_gone = 0;  /* set by a pump: EIO on the master -> the slave closed */
static pid_t g_child = -1;
static int g_slave = -1; /* our own slave fd, held for the generation: see pty_create() */
static char g_pts[64];

static volatile sig_atomic_t g_quit = 0, g_sig_disable = 0, g_sig_enable = 0;

static void logmsg(const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    fputs("ocbm-accessory: ", stderr);
    vfprintf(stderr, fmt, ap);
    fputc('\n', stderr);
    va_end(ap);
}
#define dbg(...) do { if (g_verbose) logmsg(__VA_ARGS__); } while (0)
#define trace(...) do { if (g_verbose >= 2) logmsg(__VA_ARGS__); } while (0)

static void on_quit(int s) { (void)s; g_quit = 1; }
static void on_usr1(int s) { (void)s; g_sig_disable = 1; }
static void on_usr2(int s) { (void)s; g_sig_enable = 1; }

static void msleep(int ms) {
    struct timespec ts = { ms / 1000, (long)(ms % 1000) * 1000000L };
    nanosleep(&ts, NULL);
}

static int cur_master(unsigned *gen) {
    int fd;
    pthread_mutex_lock(&g_lock);
    fd = g_master;
    if (gen) *gen = g_gen;
    pthread_mutex_unlock(&g_lock);
    return fd;
}

/* --------------------------------------------------------------------------- FunctionFS side */
static void fill_speed(struct ffs_speed_descs *d, uint16_t mps) {
    d->intf = (struct usb_if_desc){ 9, USB_DT_INTERFACE, 0, 0, 2, USB_CLASS_VENDOR, USB_CLASS_VENDOR, 0, 0 };
    d->in = (struct usb_ep_desc){ 7, USB_DT_ENDPOINT, 1 | USB_DIR_IN, 2 /* bulk */, mps, 0 };
    d->out = (struct usb_ep_desc){ 7, USB_DT_ENDPOINT, 1, 2, mps, 0 };
}

static int ffs_open(void) {
    char p[512];
    struct ffs_descs d;
    struct ffs_strings s;
    snprintf(p, sizeof p, "%s/ep0", g_ffs);
    g_ep0 = open(p, O_RDWR | O_CLOEXEC);
    if (g_ep0 < 0) { logmsg("open %s: %s", p, strerror(errno)); return -1; }
    memset(&d, 0, sizeof d);
    d.magic = FFS_DESCRIPTORS_MAGIC_V2;
    d.length = sizeof d;
    d.flags = FFS_HAS_FS_DESC | FFS_HAS_HS_DESC;
    d.fs_count = 3;
    d.hs_count = 3;
    fill_speed(&d.fs, FS_MAXPACKET);
    fill_speed(&d.hs, HS_MAXPACKET);
    if (write(g_ep0, &d, sizeof d) != (ssize_t)sizeof d) { logmsg("ep0 descriptors: %s", strerror(errno)); return -1; }
    s = (struct ffs_strings){ FFS_STRINGS_MAGIC, sizeof s, 0, 0 };
    if (write(g_ep0, &s, sizeof s) != (ssize_t)sizeof s) { logmsg("ep0 strings: %s", strerror(errno)); return -1; }
    /* The endpoint files exist from here on (ffs state ACTIVE); the gadget may now be bound. */
    snprintf(p, sizeof p, "%s/ep1", g_ffs);
    g_ep_in = open(p, O_WRONLY | O_CLOEXEC);
    if (g_ep_in < 0) { logmsg("open %s: %s", p, strerror(errno)); return -1; }
    snprintf(p, sizeof p, "%s/ep2", g_ffs);
    /* O_NONBLOCK matters only while the endpoint is not enabled: a read then fails with EAGAIN instead of
     * waiting inside f_fs for the next ENABLE with a size chosen before it (ffs_epfile_wait_ep). Once the
     * endpoint is enabled, f_fs queues the request and waits for its completion whatever the flag
     * (ffs_epfile_io, 7.2.10), so the data path is unchanged. */
    g_ep_out = open(p, O_RDONLY | O_CLOEXEC | O_NONBLOCK);
    if (g_ep_out < 0) { logmsg("open %s: %s", p, strerror(errno)); return -1; }
    logmsg("functionfs %s: descriptors written, ep1 (bulk IN) and ep2 (bulk OUT) open", g_ffs);
    return 0;
}

static int test_open(void) {
    struct sockaddr_un me, peer;
    char mine[108];
    int fd = socket(AF_UNIX, SOCK_DGRAM | SOCK_CLOEXEC, 0);
    if (fd < 0) { logmsg("socket: %s", strerror(errno)); return -1; }
    snprintf(mine, sizeof mine, "%s.dev", g_test_sock);
    unlink(mine);
    memset(&me, 0, sizeof me);
    me.sun_family = AF_UNIX;
    snprintf(me.sun_path, sizeof me.sun_path, "%s", mine);
    if (bind(fd, (struct sockaddr *)&me, sizeof me) < 0) { logmsg("bind %s: %s", mine, strerror(errno)); return -1; }
    memset(&peer, 0, sizeof peer);
    peer.sun_family = AF_UNIX;
    snprintf(peer.sun_path, sizeof peer.sun_path, "%s", g_test_sock);
    if (connect(fd, (struct sockaddr *)&peer, sizeof peer) < 0) { logmsg("connect %s: %s", g_test_sock, strerror(errno)); return -1; }
    g_ep_in = g_ep_out = fd;
    g_enabled = 1;
    logmsg("test mode: datagram socket %s <-> %s, function ENABLED", mine, g_test_sock);
    return 0;
}

/* After ENABLE: the active speed's wMaxPacketSize decides when a transfer needs a ZLP. */
static void read_maxpacket(void) {
    struct usb_ep_desc ed;
    int mps;
    if (g_test_sock) return;
    if (ioctl(g_ep_in, FFS_IOC_ENDPOINT_DESC, &ed) == 0 && ed.wMaxPacketSize >= 8)
        mps = ed.wMaxPacketSize;
    else
        mps = HS_MAXPACKET;
    __atomic_store_n(&g_maxpacket, mps, __ATOMIC_RELAXED);
    dbg("bulk IN wMaxPacketSize %d, host->device reads of %d B", g_maxpacket, g_out_read ? g_out_read : g_maxpacket);
}

/* One host->device read. FunctionFS: a request of `n` bytes, complete on a short packet or when full.
 * Test mode: gather packet datagrams the same way (a datagram shorter than wMaxPacketSize is "short"). */
static ssize_t ep_out_read(uint8_t *buf, size_t n) {
    size_t got = 0;
    if (!g_test_sock) return read(g_ep_out, buf, n);
    while (got < n) {
        ssize_t r = recv(g_ep_out, buf + got, n - got, 0);
        if (r < 0) { if (errno == EINTR) continue; return got ? (ssize_t)got : r; }
        got += (size_t)r;
        if ((size_t)r < (size_t)g_maxpacket) break; /* short packet ends the transfer */
    }
    return (ssize_t)got;
}

/* One device->host transfer: the bytes, then a ZLP when their count is a multiple of wMaxPacketSize
 * (a FunctionFS write of 0 bytes queues a zero-length request: f_fs.c ffs_epfile_io, data_len 0).
 * Only when `terminate` is set: a chunk that was cut by XFER_MAX with more bytes already waiting
 * does not need one, the next chunk continues the transfer. */
static ssize_t xfer_write(const void *buf, size_t n) {
    return g_test_sock ? send(g_ep_in, buf, n, MSG_NOSIGNAL) : write(g_ep_in, buf, n);
}

static int ep_in_write(const uint8_t *buf, size_t n, int terminate) {
    size_t off = 0;
    while (off < n) {
        ssize_t w = xfer_write(buf + off, n - off);
        if (w < 0) {
            if (errno == EINTR) continue;
            return -1; /* ESHUTDOWN (disabled), ENODEV (unbound): the host is gone, drop */
        }
        off += (size_t)w;
    }
    if (terminate && n > 0 && n % (size_t)g_maxpacket == 0) {
        ssize_t w;
        do { w = xfer_write(buf, 0); } while (w < 0 && errno == EINTR);
        trace("IN %zu B + ZLP%s", n, w < 0 ? " (ZLP write FAILED)" : "");
        if (w < 0) return -1;
    } else {
        trace("IN %zu B%s", n, terminate ? "" : " (more pending)");
    }
    return 0;
}

/* ----------------------------------------------------------------------------- pty generation */
static int pty_create(void) {
    int m, s;
    struct termios t;
    m = posix_openpt(O_RDWR | O_NOCTTY | O_CLOEXEC);
    if (m < 0) { logmsg("posix_openpt: %s", strerror(errno)); return -1; }
    if (grantpt(m) < 0 || unlockpt(m) < 0 || ptsname_r(m, g_pts, sizeof g_pts) != 0) {
        logmsg("pty setup: %s", strerror(errno));
        close(m);
        return -1;
    }
    /* Raw line discipline on the slave BEFORE anyone opens it through the symlink. Set through a
     * slave fd of our own (O_NOCTTY: this process never takes it as its controlling terminal;
     * O_CLOEXEC: the child does not inherit it). The fd is HELD for the whole generation: closing the
     * last slave fd marks the master TTY_OTHER_CLOSED (drivers/tty/pty.c pty_close) and its reads
     * return EIO until a slave is opened again, which the pumps would take for "ocbmd exited" in the
     * window before ocbmd opens the link (seen in the host self-test). The child's exit is detected
     * with waitpid instead; closing the master in gen_stop() still hangs the slave up for everyone. */
    s = open(g_pts, O_RDWR | O_NOCTTY | O_CLOEXEC);
    if (s < 0) { logmsg("open %s: %s", g_pts, strerror(errno)); close(m); return -1; }
    if (tcgetattr(s, &t) < 0) { logmsg("tcgetattr: %s", strerror(errno)); close(s); close(m); return -1; }
    cfmakeraw(&t);
    t.c_iflag &= ~(tcflag_t)(IXON | IXOFF | IXANY);
    t.c_cflag |= CLOCAL | CREAD;
    t.c_cc[VMIN] = 1;
    t.c_cc[VTIME] = 0;
    if (tcsetattr(s, TCSANOW, &t) < 0) { logmsg("tcsetattr: %s", strerror(errno)); close(s); close(m); return -1; }
    g_slave = s;
    fcntl(m, F_SETFL, fcntl(m, F_GETFL) | O_NONBLOCK);
    return m;
}

/* /dev/usb_accessory -> /dev/pts/N, replaced atomically; never replaces a real node. */
static int dev_link(const char *target) {
    char tmp[512];
    struct stat st;
    if (lstat(g_dev, &st) == 0 && !S_ISLNK(st.st_mode)) {
        logmsg("%s exists and is not a symlink: refusing to replace it", g_dev);
        return -1;
    }
    snprintf(tmp, sizeof tmp, "%s.tmp.%d", g_dev, (int)getpid());
    unlink(tmp);
    if (symlink(target, tmp) < 0 || rename(tmp, g_dev) < 0) {
        logmsg("symlink %s -> %s: %s", g_dev, target, strerror(errno));
        unlink(tmp);
        return -1;
    }
    return 0;
}

static void dev_unlink(void) {
    char buf[128];
    ssize_t n = readlink(g_dev, buf, sizeof buf - 1);
    if (n > 0) {
        buf[n] = 0;
        if (strcmp(buf, g_pts) == 0) unlink(g_dev);
    }
}

static pid_t spawn_child(void) {
    pid_t pid;
    if (!g_cmd) return -1;
    pid = fork();
    if (pid < 0) { logmsg("fork: %s", strerror(errno)); return -1; }
    if (pid == 0) {
        /* Not a session leader: open() of the slave never makes it the child's controlling tty. */
        int fd = -1;
        signal(SIGPIPE, SIG_DFL);
        signal(SIGHUP, SIG_DFL);
        signal(SIGUSR1, SIG_DFL);
        signal(SIGUSR2, SIG_DFL);
        if (g_childlog) fd = open(g_childlog, O_WRONLY | O_CREAT | O_APPEND, 0644);
        if (fd >= 0) {
            dup2(fd, 1);
            dup2(fd, 2);
            if (fd > 2) close(fd);
        }
        execvp(g_cmd[0], g_cmd);
        fprintf(stderr, "ocbm-accessory: exec %s: %s\n", g_cmd[0], strerror(errno));
        _exit(127);
    }
    return pid;
}

static time_t g_last_spawn = 0;
static int g_fast_fails = 0;

static int gen_start(void) {
    int m = pty_create();
    if (m < 0) return -1;
    if (dev_link(g_pts) < 0) { close(m); return -1; }
    pthread_mutex_lock(&g_lock);
    g_master = m;
    g_gen++;
    g_slave_gone = 0;
    pthread_mutex_unlock(&g_lock);
    g_child = spawn_child();
    g_last_spawn = time(NULL);
    logmsg("generation %u: %s -> %s%s%s", g_gen, g_dev, g_pts, g_cmd ? ", started " : "", g_cmd ? g_cmd[0] : "");
    return 0;
}

/* Close the master (the slave hangs up: ocbmd sees POLLHUP/EIO and exits), wait for the child. */
static void gen_stop(const char *why) {
    int m;
    pthread_mutex_lock(&g_lock);
    m = g_master;
    g_master = -1;
    pthread_mutex_unlock(&g_lock);
    dev_unlink();
    if (m >= 0) { msleep(300); close(m); } /* see cur_master(): no pump can still use the number */
    if (g_slave >= 0) { close(g_slave); g_slave = -1; }
    if (g_child > 0) {
        int st, i;
        for (i = 0; i < 20 && waitpid(g_child, &st, WNOHANG) == 0; i++) msleep(100);
        if (i == 20) {
            kill(g_child, SIGTERM);
            for (i = 0; i < 20 && waitpid(g_child, &st, WNOHANG) == 0; i++) msleep(100);
            if (i == 20) { kill(g_child, SIGKILL); waitpid(g_child, &st, 0); }
        }
        g_child = -1;
    }
    logmsg("generation %u ended (%s)", g_gen, why);
}

/* ------------------------------------------------------------------------------------ pumps */
/* host -> ocbmd: one request per read (one packet unless -r), written to the current master.
 * FunctionFS: no read is issued before the main thread has handled ENABLE (revision 8). The request size is
 * fixed when the read is issued, and before revision 8 the first read was issued at start, sized from the
 * compiled-in high-speed 512 and parked in f_fs until ENABLE: on a full-speed host (64-byte packets) a first
 * frame of 64*n <= 448 B would then wait for the next transfer (README §7.0d). Now the size is always the
 * active speed's wMaxPacketSize. ep2 is O_NONBLOCK, so a read racing a DISABLE fails with EAGAIN/ESHUTDOWN
 * instead of waiting for the next ENABLE with the old size; both are retried after a short sleep. Test mode
 * (-T) keeps reading while "disabled", as before: there is no speed to learn there. */
static void *pump_out(void *arg) {
    static uint8_t buf[XFER_MAX];
    (void)arg;
    for (;;) {
        size_t want;
        ssize_t n;
        if (!g_test_sock && !__atomic_load_n(&g_enabled, __ATOMIC_ACQUIRE)) {
            if (g_quit) return NULL;
            msleep(10);
            continue;
        }
        want = g_out_read ? (size_t)g_out_read : (size_t)__atomic_load_n(&g_maxpacket, __ATOMIC_RELAXED);
        if (want > sizeof buf) want = sizeof buf;
        n = ep_out_read(buf, want);
        if (n > 0) trace("OUT %zd B", n);
        size_t off = 0;
        unsigned gen;
        if (n < 0) {
            if (errno == EAGAIN || errno == ESHUTDOWN) { if (g_quit) return NULL; msleep(10); continue; }
            if (errno == EINTR) { if (g_quit) return NULL; continue; }
            logmsg("bulk OUT read: %s", strerror(errno));
            g_quit = 1;
            return NULL;
        }
        if (n == 0) continue;
        while (off < (size_t)n) {
            int fd = cur_master(&gen);
            ssize_t w;
            if (fd < 0) { dbg("no pty: %zd host bytes dropped", n - (ssize_t)off); break; }
            w = write(fd, buf + off, (size_t)n - off);
            if (w > 0) { off += (size_t)w; continue; }
            if (w < 0 && errno == EAGAIN) {
                struct pollfd p = { fd, POLLOUT, 0 };
                unsigned g2;
                poll(&p, 1, 200);
                if (cur_master(&g2) != fd || g2 != gen) break; /* generation changed: drop the rest */
                continue;
            }
            if (w < 0 && errno == EINTR) continue;
            if (w < 0 && errno == EIO) g_slave_gone = 1;
            else dbg("master write: %s", w < 0 ? strerror(errno) : "0");
            break;
        }
    }
}

/* ocbmd -> host: coalesce what the pty has (up to XFER_MAX), one USB transfer per chunk. Dropped
 * while the function is not enabled (the stock accessory write fails with ENODEV offline). */
static void *pump_in(void *arg) {
    static uint8_t buf[XFER_MAX];
    (void)arg;
    for (;;) {
        unsigned gen;
        int fd = cur_master(&gen);
        struct pollfd p;
        size_t total = 0;
        int more = 0;
        if (g_quit) return NULL;
        if (fd < 0) { msleep(50); continue; }
        p.fd = fd;
        p.events = POLLIN;
        p.revents = 0;
        if (poll(&p, 1, 250) <= 0) continue;
        {
            unsigned g2;
            if (cur_master(&g2) != fd || g2 != gen) continue;
        }
        while (total < sizeof buf) {
            ssize_t n = read(fd, buf + total, sizeof buf - total);
            if (n > 0) { total += (size_t)n; continue; }
            if (n == 0 || (n < 0 && errno == EIO)) {
                /* every slave fd closed (cannot happen while gen_stop() has not closed ours; kept
                 * as a guard): the main thread ends this generation */
                if (g_gen == gen) g_slave_gone = 1;
                break;
            }
            if (n < 0 && errno == EINTR) continue;
            break; /* EAGAIN: drained */
        }
        if (total == sizeof buf) {
            struct pollfd q = { fd, POLLIN, 0 };
            more = poll(&q, 1, 0) > 0 && (q.revents & POLLIN);
        }
        if (total == 0) continue;
        if (!g_enabled) { dbg("not enabled: %zu bytes from %s dropped", total, g_pts); continue; }
        if (ep_in_write(buf, total, !more) < 0) dbg("bulk IN write failed: %s", strerror(errno));
    }
}

/* ---------------------------------------------------------------------------------- events */
static void handle_setup(const struct usb_ctrlreq *s) {
    /* Nothing is expected here (the OCBM hosts send no class/vendor control requests to the
     * interface); stall: read for an IN request, write for an OUT request (f_fs.c ep0 semantics). */
    uint8_t b = 0;
    dbg("SETUP %02x %02x %04x %04x %u: stall", s->bRequestType, s->bRequest, s->wValue, s->wIndex, s->wLength);
    if (s->bRequestType & USB_DIR_IN) (void)!read(g_ep0, &b, 1);
    else (void)!write(g_ep0, &b, 1);
}

static void handle_event(const struct ffs_event *ev) {
    switch (ev->type) {
    case FFS_EV_BIND: logmsg("BIND"); break;
    case FFS_EV_UNBIND: logmsg("UNBIND"); g_enabled = 0; break;
    case FFS_EV_ENABLE:
        read_maxpacket();
        __atomic_store_n(&g_enabled, 1, __ATOMIC_RELEASE); /* after g_maxpacket: pump_out sizes reads from it */
        logmsg("ENABLE (host configured the device, wMaxPacketSize %d)", g_maxpacket);
        break;
    case FFS_EV_DISABLE:
        g_enabled = 0;
        logmsg("DISABLE (host gone)%s", g_keep ? "" : ": hanging up " );
        if (!g_keep && g_master >= 0) { gen_stop("USB disable"); gen_start(); }
        break;
    case FFS_EV_SETUP: handle_setup(&ev->u.setup); break;
    case FFS_EV_SUSPEND: dbg("SUSPEND"); break;
    case FFS_EV_RESUME: dbg("RESUME"); break;
    default: dbg("event %u", ev->type);
    }
}

static void usage(void) {
    fputs("usage: ocbm-accessory [-f FFSDIR] [-d DEVLINK] [-p PIDFILE] [-l CHILDLOG] [-k] [-v] [-T SOCK] [-- CMD [ARG...]]\n"
          "  -f  FunctionFS mount (ep0, ep1 = bulk IN, ep2 = bulk OUT)   default /run/ocbm/ffs\n"
          "  -d  device node to provide (symlink to the pty slave)       default /dev/usb_accessory\n"
          "  -l  append CMD's stdout/stderr to this file\n"
          "  -k  keep CMD running across a USB DISABLE (default: hang it up, it exits, respawn)\n"
          "  -r  bytes per host->device read (default: one wMaxPacketSize packet; 16384 = the stock-like\n"
          "      request that loses a lone full-size packet until the next transfer)  -v -v traces transfers\n"
          "  -T  test mode: AF_UNIX datagram socket instead of FunctionFS (SIGUSR1/2 = DISABLE/ENABLE)\n"
          "  CMD is started once per pty generation (ocbmd) and respawned when it exits\n", stderr);
}

int main(int argc, char **argv) {
    int i, rc;
    pthread_t t_in, t_out;
    struct sigaction sa;
    for (i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--") == 0) { if (i + 1 < argc) g_cmd = &argv[i + 1]; break; }
        else if (strcmp(argv[i], "-f") == 0 && i + 1 < argc) g_ffs = argv[++i];
        else if (strcmp(argv[i], "-d") == 0 && i + 1 < argc) g_dev = argv[++i];
        else if (strcmp(argv[i], "-p") == 0 && i + 1 < argc) g_pidfile = argv[++i];
        else if (strcmp(argv[i], "-l") == 0 && i + 1 < argc) g_childlog = argv[++i];
        else if (strcmp(argv[i], "-T") == 0 && i + 1 < argc) g_test_sock = argv[++i];
        else if (strcmp(argv[i], "-r") == 0 && i + 1 < argc) g_out_read = atoi(argv[++i]);
        else if (strcmp(argv[i], "-k") == 0) g_keep = 1;
        else if (strcmp(argv[i], "-v") == 0) g_verbose++;
        else { usage(); return 2; }
    }
    memset(&sa, 0, sizeof sa);
    sa.sa_handler = on_quit;
    sigaction(SIGTERM, &sa, NULL);
    sigaction(SIGINT, &sa, NULL);
    sa.sa_handler = on_usr1;
    sigaction(SIGUSR1, &sa, NULL);
    sa.sa_handler = on_usr2;
    sigaction(SIGUSR2, &sa, NULL);
    signal(SIGPIPE, SIG_IGN);
    signal(SIGHUP, SIG_IGN);
    setsid(); /* own session: a UART login that started us may end; EPERM if already a leader */

    rc = g_test_sock ? test_open() : ffs_open();
    if (rc < 0) return 1;
    if (g_pidfile) {
        FILE *f = fopen(g_pidfile, "w");
        if (f) { fprintf(f, "%d\n", (int)getpid()); fclose(f); }
    }
    if (gen_start() < 0) return 1;
    if (pthread_create(&t_out, NULL, pump_out, NULL) != 0 || pthread_create(&t_in, NULL, pump_in, NULL) != 0) {
        logmsg("pthread_create: %s", strerror(errno));
        return 1;
    }

    while (!g_quit) {
        int st;
        if (g_ep0 >= 0) {
            struct pollfd p = { g_ep0, POLLIN, 0 };
            if (poll(&p, 1, 200) > 0 && (p.revents & POLLIN)) {
                struct ffs_event ev[4];
                ssize_t n = read(g_ep0, ev, sizeof ev);
                if (n < 0 && errno != EINTR && errno != EAGAIN) { logmsg("ep0 read: %s", strerror(errno)); break; }
                for (i = 0; i < (int)(n / (ssize_t)sizeof ev[0]); i++) handle_event(&ev[i]);
            }
        } else {
            msleep(200);
        }
        if (g_sig_disable) { g_sig_disable = 0; handle_event(&(struct ffs_event){ .type = FFS_EV_DISABLE }); }
        if (g_sig_enable) { g_sig_enable = 0; handle_event(&(struct ffs_event){ .type = FFS_EV_ENABLE }); }
        if (g_child > 0 && waitpid(g_child, &st, WNOHANG) == g_child) {
            char why[64];
            if (WIFEXITED(st)) snprintf(why, sizeof why, "%s exited %d", g_cmd[0], WEXITSTATUS(st));
            else snprintf(why, sizeof why, "%s killed by signal %d", g_cmd[0], WTERMSIG(st));
            g_child = -1;
            if (time(NULL) - g_last_spawn < 2) g_fast_fails++; else g_fast_fails = 0;
            gen_stop(why);
            if (g_fast_fails >= 3) { logmsg("%s keeps exiting at once; retry in 10 s", g_cmd[0]); msleep(10000); }
            else if (g_fast_fails) msleep(1000);
            if (!g_quit && gen_start() < 0) break;
        } else if (g_slave_gone && g_master >= 0) {
            gen_stop("the slave side closed");
            if (!g_quit && gen_start() < 0) break;
        }
    }
    g_quit = 1;
    gen_stop("exit");
    if (g_pidfile) unlink(g_pidfile);
    if (g_test_sock) { char mine[108]; snprintf(mine, sizeof mine, "%s.dev", g_test_sock); unlink(mine); }
    return 0;
}
