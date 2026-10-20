# SPDX-License-Identifier: GPL-3.0-or-later
# i.MX6ULL hooks for common/rootfs/etc/init.d/rcS. LEDs as the DT sets them: red on and blue on the
# heartbeat trigger from kernel start; the recovery initramfs blinks red (timer); a rootfs whose ways
# in are up turns red off, leaving the blue heartbeat. No radio, no MFi daemon: the MFi coprocessor
# is just /dev/i2c-1, address 0x11 (the &i2c2 controller on the UART5 pads, numbered 1 by the
# imx6ul.dtsi i2c aliases).
board_early() {
    :
}

board_late() {
    # $1 = 1 when NCM and SSH are up; otherwise red stays on.
    [ "$1" = 1 ] || return 0
    [ -e "$LED_RED/trigger" ] && echo none > "$LED_RED/trigger" && echo 0 > "$LED_RED/brightness"
}
