#!/bin/sh

audioCodec=none
i2cdetect -y -a 0 0x1a 0x1a | grep "1a" && audioCodec=wm8960
i2cdetect -y -a 0 0x15 0x15 | grep "15" && audioCodec=ac6966
echo "[init_audio_codec] audio codec: $audioCodec"
if [ "$audioCodec" = "wm8960" ]; then
	test -e /tmp/snd-soc-wm8960.ko && { insmod /tmp/snd-soc-wm8960.ko && echo "[init_audio_codec] insmod snd-soc-wm8960.ko ok" || echo "[init_audio_codec] insmod snd-soc-wm8960.ko FAILED"; }
	test -e /tmp/snd-soc-imx-wm8960.ko && { insmod /tmp/snd-soc-imx-wm8960.ko && echo "[init_audio_codec] insmod snd-soc-imx-wm8960.ko ok" || echo "[init_audio_codec] insmod snd-soc-imx-wm8960.ko FAILED"; }
	/script/set_wm8960_mix.sh
elif [ "$audioCodec" = "ac6966" ]; then
	test -e /tmp/snd-soc-bt-sco.ko && { insmod /tmp/snd-soc-bt-sco.ko && echo "[init_audio_codec] insmod snd-soc-bt-sco.ko ok" || echo "[init_audio_codec] insmod snd-soc-bt-sco.ko FAILED"; }
	test -e /tmp/snd-soc-imx-btsco.ko && { insmod /tmp/snd-soc-imx-btsco.ko && echo "[init_audio_codec] insmod snd-soc-imx-btsco.ko ok" || echo "[init_audio_codec] insmod snd-soc-imx-btsco.ko FAILED"; }
	# 1: open record, 0: close record
	i2cset -f -y 0 0x15 0x01 1
else
	echo "[init_audio_codec] Box No Mic!"
fi
