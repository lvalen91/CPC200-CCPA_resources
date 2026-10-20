Pre-LIVI-Link backup, 2026-10-19. OCBM baseline adapter (NXP IW416, SDIO 0x9159), kernel 3.14.52 #12.
Source: dd of /dev/mtd0,1,2 (bs=64k) over ssh, each read twice with identical sha256 (rootfs mounted rw).
Layout (16 MiB SPI NOR, Macronix MX25L12835F): mtd0 uboot 0x000000-0x03FFFF, mtd1 kernel 0x040000-0x37FFFF, mtd2 rootfs 0x380000-0xFFFFFF.
full_16MB_for_programmer.bin = mtd0||mtd1||mtd2 = the whole chip, write at offset 0 with a SPI programmer (erase chip first).
unit_info.txt holds this unit's OCOTP CFG0/CFG1/MAC0/MAC1 (identity; they key this unit's kernel). Keep local, never publish.
[2026-10-20, repo copy: placed in this repo with the rest of the backup by owner decision; the original rule above is
 kept as written. These four words are the UpgKey of this unit's kernel staging (custom/kernel_rootfs/baseline/README.md §2.1).]
