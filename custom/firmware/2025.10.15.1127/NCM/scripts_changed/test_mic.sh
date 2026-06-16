#!/bin/sh
########################
# Copyright(c) 2014-2017 DongGuan HeWei Communication Technologies Co. Ltd.
# file    test_mic.sh
# brief
# author  Shi Kai
# version 1.0.0
# date    03Jun17
########################
echo "[test_mic] running mic test (DTMF capture and decode)"
dtmf_file=/tmp/dtmf.pcm
tinycap -- -c 1 -r 16000 -b 16 -t 4 > "$dtmf_file"
result=$(dtmf_decode "$dtmf_file" | grep 14809414327 | wc -l)
if [ "$result" -eq 1 ]; then
	echo "[test_mic] mic test success"
	exit 0
fi
exit 1
