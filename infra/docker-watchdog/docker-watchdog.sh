#!/usr/bin/env bash
#
# docker-watchdog.sh
#
# 24시간 가동 서버용 도커 컨테이너 감시기.
#   - 감시 대상 컨테이너가 꺼지면 감지한다
#   - 종료 코드와 로그를 분석해 꺼진 이유를 추정한다
#   - 자동으로 다시 살린다
#   - 무엇이 꺼졌고 왜 꺼졌고 어떻게 살렸는지를 incidents.md 에 기록한다
#
# cron 에서 1분마다 실행되는 것을 전제로 한다.
#
set -uo pipefail

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

BASE_DIR="/home/infrun42/docker-watchdog"
INCIDENT_FILE="$BASE_DIR/incidents.md"
STATE_FILE="$BASE_DIR/state.json"
RUN_LOG="$BASE_DIR/watchdog.log"
LOCK_FILE="$BASE_DIR/.lock"

# 컨테이너 로그에서 원인 추정에 사용할 마지막 줄 수
LOG_TAIL=200
# 기록에 남길 에러 로그 줄 수
LOG_KEEP=12

mkdir -p "$BASE_DIR"

# ── 중복 실행 방지 ────────────────────────────────────────────────
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
    exit 0
fi

log() {
    printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >>"$RUN_LOG"
}

# ── 감시 대상 결정 ────────────────────────────────────────────────
# restart 정책이 always / unless-stopped 인 컨테이너 = "항시 떠 있어야 하는 것"
# 사용자가 의도적으로 docker stop 한 컨테이너는 되살리지 않는다.
targets() {
    docker ps -a --format '{{.Names}}' | while read -r name; do
        [ -z "$name" ] && continue
        policy=$(docker inspect "$name" --format '{{.HostConfig.RestartPolicy.Name}}' 2>/dev/null)
        case "$policy" in
            always | unless-stopped) echo "$name" ;;
        esac
    done
}

# ── 원인 추정 ─────────────────────────────────────────────────────
# 종료 코드 + OOM 플래그 + 로그 패턴을 조합해 사람이 읽을 문장을 만든다.
diagnose() {
    local name="$1" exit_code="$2" oom="$3" logs="$4"
    local reasons=()

    if [ "$oom" = "true" ]; then
        reasons+=("컨테이너가 메모리 한도를 초과해 커널 OOM killer 에 의해 강제 종료됨 (OOMKilled=true)")
    fi

    # 로그 기반 패턴 매칭 (구체적인 것부터)
    if grep -qiE 'Adapter disconnected' <<<"$logs"; then
        reasons+=("Zigbee USB 동글(어댑터) 연결이 끊겨 z2m 이 스스로 종료함 — USB 분리/전원 문제")
    fi
    if grep -qiE 'port is already allocated|address already in use|bind: address already in use' <<<"$logs"; then
        reasons+=("포트 충돌 — 다른 프로세스가 같은 포트를 이미 점유 중")
    fi
    if grep -qiE 'no space left on device' <<<"$logs"; then
        reasons+=("디스크 공간 부족 (no space left on device)")
    fi
    if grep -qiE 'permission denied' <<<"$logs"; then
        reasons+=("권한 문제 — 볼륨/장치 접근 거부 (permission denied)")
    fi
    if grep -qiE 'connection refused|ECONNREFUSED' <<<"$logs"; then
        reasons+=("의존 서비스 접속 실패 (connection refused) — MQTT/DB 등 연동 대상이 죽어 있었을 가능성")
    fi
    if grep -qiE 'FATAL|panic:|Segmentation fault' <<<"$logs"; then
        reasons+=("애플리케이션이 치명적 오류(FATAL/panic)로 비정상 종료")
    fi
    if grep -qiE 'no such file or directory' <<<"$logs"; then
        reasons+=("필요한 파일/장치 경로가 존재하지 않음 (no such file or directory)")
    fi

    # 종료 코드 기반 보조 설명
    if [ ${#reasons[@]} -eq 0 ]; then
        case "$exit_code" in
            0)   reasons+=("정상 종료(exit 0) — 프로세스가 스스로 작업을 마치고 끝남") ;;
            1)   reasons+=("일반 오류로 종료 (exit 1) — 아래 로그 참고") ;;
            2)   reasons+=("설정 오류 또는 애플리케이션 자체 판단에 의한 종료 (exit 2)") ;;
            125) reasons+=("도커 데몬 레벨 오류 (exit 125) — 잘못된 실행 옵션") ;;
            126) reasons+=("컨테이너 명령을 실행할 수 없음 (exit 126)") ;;
            127) reasons+=("컨테이너 명령을 찾을 수 없음 (exit 127)") ;;
            137) reasons+=("SIGKILL 로 강제 종료 (exit 137) — OOM 또는 외부에서 kill") ;;
            139) reasons+=("Segmentation fault (exit 139)") ;;
            143) reasons+=("SIGTERM 으로 종료 (exit 143) — 호스트 재부팅/도커 재시작 등 정상 신호") ;;
            *)   reasons+=("종료 코드 $exit_code 로 종료 — 아래 로그 참고") ;;
        esac
    fi

    printf '%s\n' "${reasons[@]}"
}

# ── 기록 ──────────────────────────────────────────────────────────
write_incident() {
    local name="$1" exit_code="$2" oom="$3" finished="$4"
    local reason_text="$5" action_text="$6" result_text="$7" errlog="$8"

    # 파일이 없으면 헤더를 만든다
    if [ ! -f "$INCIDENT_FILE" ]; then
        cat >"$INCIDENT_FILE" <<'HDR'
# 도커 컨테이너 다운 기록

24시간 가동 서버에서 컨테이너가 꺼질 때마다 자동으로 기록됩니다.
`docker-watchdog.sh` 가 1분마다 상태를 확인하고, 꺼진 컨테이너를 되살린 뒤 아래에 남깁니다.

---
HDR
    fi

    {
        echo ""
        echo "## $(date '+%Y-%m-%d %H:%M:%S') — <$name>"
        echo ""
        echo "1. **꺼진 컨테이너**: \`<$name>\`"
        echo "2. **꺼진 시각**: ${finished:-불명}"
        echo "3. **종료 코드**: \`$exit_code\`${oom:+ (OOMKilled=$oom)}"
        echo "4. **꺼진 이유**:"
        # 추정 원인이 여러 개면 각각 하위 항목으로
        while IFS= read -r line; do
            [ -z "$line" ] && continue
            echo "   - $line"
        done <<<"$reason_text"
        echo "5. **조치 내용**: $action_text"
        echo "6. **결과**: $result_text"
        if [ -n "$errlog" ]; then
            echo "7. **종료 직전 로그**:"
            echo ""
            echo '   ```'
            while IFS= read -r line; do
                echo "   $line"
            done <<<"$errlog"
            echo '   ```'
        fi
        echo ""
        echo "---"
    } >>"$INCIDENT_FILE"
}

# ── 본체 ──────────────────────────────────────────────────────────
if ! docker info >/dev/null 2>&1; then
    log "docker 데몬에 접근할 수 없음 — 건너뜀"
    exit 0
fi

now_state="{"
first=1

while read -r name; do
    [ -z "$name" ] && continue

    status=$(docker inspect "$name" --format '{{.State.Status}}' 2>/dev/null) || continue

    [ $first -eq 1 ] && first=0 || now_state+=","
    now_state+="\"$name\":\"$status\""

    # running / restarting 이면 정상
    case "$status" in
        running | restarting | paused) continue ;;
    esac

    # 여기부터는 꺼져 있는 컨테이너
    exit_code=$(docker inspect "$name" --format '{{.State.ExitCode}}' 2>/dev/null)
    oom=$(docker inspect "$name" --format '{{.State.OOMKilled}}' 2>/dev/null)
    finished=$(docker inspect "$name" --format '{{.State.FinishedAt}}' 2>/dev/null | cut -c1-19 | tr 'T' ' ')

    # 같은 다운을 중복 기록하지 않기 위해 종료 시각을 키로 사용
    marker="$BASE_DIR/.seen_${name//\//_}"
    if [ -f "$marker" ] && [ "$(cat "$marker" 2>/dev/null)" = "$finished" ]; then
        # 이미 기록했고, 아직 못 살린 상태 → 재기동만 한 번 더 시도
        docker start "$name" >/dev/null 2>&1
        continue
    fi

    log "다운 감지: $name (status=$status exit=$exit_code oom=$oom)"

    logs=$(docker logs --tail "$LOG_TAIL" "$name" 2>&1)
    reason_text=$(diagnose "$name" "$exit_code" "$oom" "$logs")

    # 기록에 남길 에러성 로그만 추린다
    errlog=$(grep -iE 'error|fatal|panic|denied|refused|disconnect|no space|exception' <<<"$logs" \
        | tail -n "$LOG_KEEP" | cut -c1-300)
    [ -z "$errlog" ] && errlog=$(tail -n 5 <<<"$logs" | cut -c1-300)

    # 복구 시도 (start 는 한 번만 호출하고 그 출력을 그대로 쓴다)
    start_out=$(docker start "$name" 2>&1)
    start_rc=$?
    if [ $start_rc -eq 0 ]; then
        action_text="\`docker start $name\` 으로 재기동 시도"
        sleep 8
        new_status=$(docker inspect "$name" --format '{{.State.Status}}' 2>/dev/null)
        if [ "$new_status" = "running" ]; then
            result_text="✅ 복구 성공 — 현재 정상 실행 중"
            log "복구 성공: $name"
        else
            result_text="⚠️ 재기동했으나 다시 꺼짐 (현재 상태: $new_status) — 수동 점검 필요"
            log "복구 실패(재종료): $name status=$new_status"
        fi
    else
        action_text="\`docker start $name\` 실행 → 실패: $(tail -2 <<<"$start_out")"
        result_text="❌ 자동 복구 실패 — 수동 점검 필요"
        log "복구 실패(start 불가): $name"
    fi

    write_incident "$name" "$exit_code" "$oom" "$finished" \
        "$reason_text" "$action_text" "$result_text" "$errlog"

    echo "$finished" >"$marker"

done < <(targets)

now_state+="}"
echo "$now_state" >"$STATE_FILE"

exit 0
