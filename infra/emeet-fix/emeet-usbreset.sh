#!/bin/bash
# eMeet USB 하드 리셋. 기기 내부 배터리 때문에 전원은 안 꺼지지만 USB 스택은 재초기화됨.
DEV=$(lsusb | awk '/328f:0109/{gsub(":","",$4); printf "/dev/bus/usb/%s/%s\n",$2,$4}')
[ -z "$DEV" ] && { echo "eMeet 미발견"; exit 1; }
/usr/bin/usbreset 328f:0109
