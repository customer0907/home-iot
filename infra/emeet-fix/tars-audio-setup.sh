#!/bin/bash
# TARS 오디오 준비. eMeet USB 재열거 후에도 안전하게 재적용되도록 작성.
SRC="alsa_input.usb-EMEET_OfficeCore_M0_Plus_EMEET_OfficeCore_M0_Plus_EM140c8d78cae29738-00.mono-fallback"
SNK="alsa_output.usb-EMEET_OfficeCore_M0_Plus_EMEET_OfficeCore_M0_Plus_EM140c8d78cae29738-00.analog-stereo"
LOG=/home/infrun42/TARS-AI/src/logs/audio-setup.log
mkdir -p "$(dirname "$LOG")"
log(){ echo "[$(date '+%F %T')] $*" >> "$LOG"; }

# 싱크와 소스가 '둘 다' 뜰 때까지 대기 (기존엔 싱크만 확인해서 소스 미준비 시 에코캔슬 실패)
for i in $(seq 1 30); do
  pactl list short sinks   2>/dev/null | grep -q "$SNK" && \
  pactl list short sources 2>/dev/null | grep -q "$SRC" && break
  sleep 1
done
if ! pactl list short sources 2>/dev/null | grep -q "$SRC"; then
  log "FAIL: eMeet 소스가 30초 내에 나타나지 않음. USB 미열거 상태."
  exit 1
fi

pactl set-source-mute   "$SRC" 0
pactl set-source-volume "$SRC" 90%
pactl set-sink-mute     "$SNK" 0
pactl set-sink-volume   "$SNK" 70%

# 이전 카드에 붙어있던 좀비 에코캔슬 모듈을 먼저 제거한 뒤 새로 적재.
# (기존엔 grep으로 존재만 확인해서, 죽은 마스터에 물린 모듈이 남아있으면 영영 재적재 안 됨)
for m in $(pactl list short modules 2>/dev/null | awk '/module-echo-cancel/{print $1}'); do
  pactl unload-module "$m" 2>/dev/null && log "좀비 echo-cancel 모듈 $m 제거"
done
if pactl load-module module-echo-cancel use_master_format=1 aec_method=webrtc \
     source_master="$SRC" sink_master="$SNK" \
     source_name=echocancel_source sink_name=echocancel_sink >/dev/null 2>&1; then
  pactl set-default-source echocancel_source
  pactl set-default-sink   echocancel_sink
  log "OK: echo-cancel 적재, 기본 장치 설정 완료"
else
  # 에코캔슬 실패해도 앱이 마이크를 쓸 수 있도록 원본 장치로 폴백
  pactl set-default-source "$SRC"
  pactl set-default-sink   "$SNK"
  log "WARN: echo-cancel 적재 실패. 원본 eMeet 장치로 폴백"
fi
