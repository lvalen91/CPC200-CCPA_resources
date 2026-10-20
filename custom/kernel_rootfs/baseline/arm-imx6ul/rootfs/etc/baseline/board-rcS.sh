# SPDX-License-Identifier: GPL-3.0-or-later
# i.MX6ULL hooks for common/rootfs/etc/init.d/rcS. LEDs (gpio-leds, pins and polarity from LIVI's DTS;
# on hardware UNVERIFIED for the baseline), as `led` documents them:
#   blue  heartbeat trigger from kernel start (DT linux,default-trigger): the kernel is alive
#   red   on from kernel start (DT default-state); recovery blinks it 500/500 ms (100/100 ms while a
#         flash helper writes, solid on after a write that failed once started); a rootfs whose ways
#         in (NCM + SSH) are up turns it off; a rootfs where one is not up leaves it on (reason on the
#         console and in /run/baseline/rcS.log)
# No radio, no MFi daemon at boot: radio-up brings the Wi-Fi/BT module up on demand, mfi-probe reads the
# MFi coprocessor (/dev/i2c-1, address 0x11: the &i2c2 controller on the UART5 pads, numbered 1 by the
# imx6ul.dtsi i2c aliases).
board_early() {
    :
}

board_late() {
    # $1 = 1 when NCM and SSH are up; otherwise red stays on.
    [ "$1" = 1 ] || return 0
    [ -e "$LED_RED/trigger" ] && echo none > "$LED_RED/trigger" && echo 0 > "$LED_RED/brightness"
}
