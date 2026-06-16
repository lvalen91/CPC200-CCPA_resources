#!/bin/sh
########################
# Copyright(c) 2014-2016 DongGuan HeWei Communication Technologies Co. Ltd.
# file    set_wm8978_mix.sh
# brief
# author  Shi Kai
# version 1.0.0
# date    19Aug16
########################
echo "[set_wm8978_mix] applying wm8978 mixer settings"
#open mic mixer and set to max volume
tinymix 9 255 255
tinymix 48 63 63
#L2 R2 volume
#tinymix 45 7 7
#AUX volume
#tinymix 46 7 7
#left
#right
#L2
#tinymix 52 1
#R2
#tinymix 55 1
