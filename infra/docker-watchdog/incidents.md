# 도커 컨테이너 다운 기록

24시간 가동 서버에서 컨테이너가 꺼질 때마다 자동으로 기록됩니다.
`docker-watchdog.sh` 가 1분마다 상태를 확인하고, 꺼진 컨테이너를 되살린 뒤 아래에 남깁니다.

---

## 2026-08-24 16:19:37 — <3ccd728199e9_zigbee2mqtt>

1. **꺼진 컨테이너**: `<3ccd728199e9_zigbee2mqtt>`
2. **꺼진 시각**: 2026-08-24 03:39:40
3. **종료 코드**: `0` (OOMKilled=false)
4. **꺼진 이유**:
   - Zigbee USB 동글(어댑터) 연결이 끊겨 z2m 이 스스로 종료함 — USB 분리/전원 문제
5. **조치 내용**: `docker start 3ccd728199e9_zigbee2mqtt` 실행 → 실패: 3ccd728199e9_zigbee2mqtt
6. **결과**: ❌ 자동 복구 실패 — 수동 점검 필요
7. **종료 직전 로그**:

   ```
   [2026-08-19 15:18:28] [31merror[39m: 	z2m: Adapter disconnected, stopping
   [2026-08-19 15:18:28] [32minfo[39m: 	z2m: Disconnecting from MQTT server
   [2026-08-24 12:23:20] [31merror[39m: 	z2m: Adapter disconnected, stopping
   [2026-08-24 12:23:20] [32minfo[39m: 	z2m: Disconnecting from MQTT server
   [2026-08-24 12:32:47] [32minfo[39m: 	z2m:mqtt: MQTT publish: topic 'homeassistant/select/1221051039810110150109113116116_0x00124b003929c324/log_level/config', payload '{"availability":[{"topic":"zigbee2mqtt/bridge/state","value_template":"{{ value_json.state }}"}],"availability_mode":"all","comman
   [2026-08-24 12:39:31] [32minfo[39m: 	z2m: Disconnecting from MQTT server
   ```

---

## 2026-08-24 16:19:45 — <zigbee2mqtt_mqtt_1>

1. **꺼진 컨테이너**: `<zigbee2mqtt_mqtt_1>`
2. **꺼진 시각**: 0001-01-01 00:00:00
3. **종료 코드**: `128` (OOMKilled=false)
4. **꺼진 이유**:
   - 종료 코드 128 로 종료 — 아래 로그 참고
5. **조치 내용**: `docker start zigbee2mqtt_mqtt_1` 으로 재기동 시도
6. **결과**: ⚠️ 재기동했으나 다시 꺼짐 (현재 상태: restarting) — 수동 점검 필요

---
