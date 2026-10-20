Pre-LIVI-Link backup, 2026-10-19. OCBM baseline adapter (NXP IW416, SDIO 0x9159), kernel 3.14.52 #12.
Source: dd of /dev/mtd0,1,2 (bs=64k) over ssh, each read twice with identical sha256 (rootfs mounted rw).
Layout (16 MiB SPI NOR, Macronix MX25L12835F): mtd0 uboot 0x000000-0x03FFFF, mtd1 kernel 0x040000-0x37FFFF, mtd2 rootfs 0x380000-0xFFFFFF.
full_16MB_for_programmer.bin = mtd0||mtd1||mtd2 = the whole chip, write at offset 0 with a SPI programmer (erase chip first).
unit_info.txt holds this unit's OCOTP CFG0/CFG1/MAC0/MAC1 (identity; they key this unit's kernel).
[2026-10-20, repo copy: this line said "Keep local, never publish". Owner decision 2026-10-20: the fuse words may stay in
 this repo, placed here with the rest of the backup. Flagged risk: these four words are the UpgKey of this unit's kernel
 staging (custom/kernel_rootfs/baseline/README.md §2.1); do not push this repo publicly without the owner's explicit go.]
[2026-10-20, repo copy: mtd0.bin and mtd1.bin were removed from this folder. They are byte-identical (sha256 and cmp) to
 ../../../../flash_dumps/CCPA_stripped/mtd0.bin  e62f62a9ef8f6f62d247902f64487c5436f1cc5c53418014867fe7fe1cec41f9
 ../../../../flash_dumps/CCPA_stripped/mtd1.bin  738af784df8c536026f6f834c5bb5fb8b747fc03bddc6c12839999411d84d128
 Same unit: identical per-chip DCP kernel head and DCP env block, IW416 (CCPA_stripped/manifest.txt sdio=0x9159).
 Use those two files wherever "this backup's mtd0.bin/mtd1.bin" is meant; SHA256SUMS points there and `shasum -a 256 -c`
 run in this folder checks them. full_16MB_for_programmer.bin = those two || mtd2.bin, re-verified (4abc6de1...).]
