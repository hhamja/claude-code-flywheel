#!/bin/bash
# stop-loop.sh — flywheel 인터랙티브 루프 엔진 (Stop hook)
#
# Claude 가 턴을 끝내려 할 때마다 실행된다.
# 활성 루프가 없으면 즉시 통과(비용 0). 있으면 종료 조건을 검사하고,
# 미충족 시 {"decision":"block","reason":<다음 사이클 프롬프트>} 로 되먹임한다.
#
# 완료 주장(<promise>FLYWHEEL_COMPLETE</promise>)은 gate.sh done 이 반증할 수 있다 —
# 주장을 증명으로 승격하는 지점.

set -uo pipefail

STATE=".claude/flywheel.local.md"
FW=".flywheel"
GATE="$FW/bin/gate.sh"

# 1. 비활성 → 즉시 통과 (다른 플러그인 Stop hook 과의 공존 기본값)
[[ -f "$STATE" ]] || exit 0

stop_loop() { # <메시지> — 루프 정리 후 정상 종료 허용
  rm -f "$STATE"
  [[ -n "${1:-}" ]] && echo "$1"
  exit 0
}

command -v jq >/dev/null 2>&1 || stop_loop "⚠️ flywheel: jq 가 필요합니다 — 루프를 정지합니다 (brew install jq)"
[[ -x "$GATE" ]] || stop_loop "⚠️ flywheel: $GATE 가 없습니다 — /flywheel:init 후 다시 시작하세요. 루프를 정지합니다."

HOOK_INPUT="$(cat)"

# ── 상태 파일 파싱 ───────────────────────────────────────────────────────────
FRONT="$(sed -n '/^---$/,/^---$/{ /^---$/d; p; }' "$STATE")"
fm() { echo "$FRONT" | grep "^$1:" | head -1 | sed "s/^$1: *//"; }

STATE_SESSION="$(fm session_id)"
CYCLE="$(fm cycle)"
MAX_CYCLES="$(fm max_cycles)"
STARTED="$(fm started_epoch)"
MAX_HOURS="$(fm max_hours)"
DISTILL_EVERY="$(fm distill_every)"

# 2. 세션 격리 — 다른 세션의 루프는 건드리지 않는다
HOOK_SESSION="$(echo "$HOOK_INPUT" | jq -r '.session_id // ""')"
# 안전 문자만 허용 — 아래 sed 치환에 삽입되므로 인젝션을 차단한다 (세션 ID 는 UUID 형식)
[[ "$HOOK_SESSION" =~ ^[A-Za-z0-9_-]+$ ]] || HOOK_SESSION=""
if [[ "$STATE_SESSION" == "pending" ]] && [[ -n "$HOOK_SESSION" ]]; then
  # adopt-on-first-stop: 커맨드 실행 시점에 세션 ID 를 못 얻었을 때의 폴백
  TMP="$STATE.tmp.$$"
  sed "s/^session_id: .*/session_id: $HOOK_SESSION/" "$STATE" > "$TMP" && mv "$TMP" "$STATE"
  STATE_SESSION="$HOOK_SESSION"
fi
if [[ -n "$STATE_SESSION" ]] && [[ "$STATE_SESSION" != "pending" ]] && [[ "$STATE_SESSION" != "$HOOK_SESSION" ]]; then
  exit 0
fi

# 3. 필드 손상 → 안전 정지
for v in "$CYCLE" "$MAX_CYCLES" "$STARTED" "$MAX_HOURS" "$DISTILL_EVERY"; do
  [[ "$v" =~ ^[0-9]+$ ]] || stop_loop "⚠️ flywheel: 상태 파일이 손상되었습니다 — 루프를 정지합니다. /flywheel:go 로 새로 시작하세요."
done

# 4. 예산 상한
if (( CYCLE >= MAX_CYCLES )); then
  stop_loop "🛑 flywheel: 사이클 상한($MAX_CYCLES) 도달 — 진행 상태는 .flywheel/ 에 보존됨. 재개: /flywheel:go"
fi
NOW="$(date +%s)"
if (( NOW - STARTED > MAX_HOURS * 3600 )); then
  stop_loop "🛑 flywheel: 시간 상한(${MAX_HOURS}h) 도달 — 진행 상태는 .flywheel/ 에 보존됨. 재개: /flywheel:go"
fi

# 5. 에스컬레이션 — BLOCKED.md 존재는 promise 와 무관한 결정적 정지 신호
if [[ -f "$FW/BLOCKED.md" ]]; then
  stop_loop "🙋 flywheel: BLOCKED.md 발견 — 사람 개입이 필요합니다. 해결 후 파일을 삭제하고 /flywheel:go 로 재개하세요."
fi

# 6. 마지막 assistant 텍스트 추출 (promise 검사용)
TRANSCRIPT="$(echo "$HOOK_INPUT" | jq -r '.transcript_path // ""')"
LAST_OUTPUT=""
if [[ -f "$TRANSCRIPT" ]]; then
  LAST_LINES="$(grep '"role":"assistant"' "$TRANSCRIPT" | tail -n 100 || true)"
  if [[ -n "$LAST_LINES" ]]; then
    LAST_OUTPUT="$(echo "$LAST_LINES" | jq -rs 'map(.message.content[]? | select(.type == "text") | .text) | last // ""' 2>/dev/null || echo "")"
  fi
fi

block() { # <reason> <systemMessage>
  jq -n --arg reason "$1" --arg msg "$2" '{"decision":"block","reason":$reason,"systemMessage":$msg}'
  exit 0
}

# 7. 완료 주장 → 게이트로 승격 검증
if echo "$LAST_OUTPUT" | grep -qF '<promise>FLYWHEEL_COMPLETE</promise>'; then
  GATE_OUT="$("$GATE" done 2>&1)"
  if [[ $? -eq 0 ]]; then
    stop_loop "✅ flywheel: 완료 주장이 게이트 검증을 통과했습니다 — 루프 종료."
  fi
  block "완료 주장이 게이트에서 반증되었습니다:
$GATE_OUT

미충족 항목을 해결하고 사이클을 계속하라. 거짓 약속으로는 루프를 빠져나갈 수 없다." "⛔ flywheel: 완료 주장 반증 (cycle $CYCLE/$MAX_CYCLES)"
fi

if echo "$LAST_OUTPUT" | grep -qF '<promise>FLYWHEEL_BLOCKED</promise>'; then
  # 5번에서 BLOCKED.md 부재가 확인된 상태 — 약속만 있고 파일이 없다
  block ".flywheel/BLOCKED.md 없이 FLYWHEEL_BLOCKED 를 약속했다. loop-protocol 스킬의 references/escalation.md 규칙대로 BLOCKED.md 를 작성한 뒤 다시 종료하라. 막히지 않았다면 사이클을 계속하라." "⛔ flywheel: BLOCKED 약속에 BLOCKED.md 없음"
fi

# 8. 사이클 계약 검사 → 위반 시 교정 지시만 재주입 (사이클 미증가)
GATE_OUT="$(FLYWHEEL_INTERACTIVE=1 "$GATE" cycle 2>&1)"
if [[ $? -ne 0 ]]; then
  block "사이클 계약 위반:
$GATE_OUT

위 위반을 해결하라. 해결 후 턴을 끝내면 다음 사이클로 진행된다." "⛔ flywheel: 계약 위반 (cycle $CYCLE/$MAX_CYCLES)"
fi

# 통과 → 다음 사이클 재주입
NEXT=$((CYCLE + 1))
TMP="$STATE.tmp.$$"
sed "s/^cycle: .*/cycle: $NEXT/" "$STATE" > "$TMP" && mv "$TMP" "$STATE"

BODY="$(awk '/^---$/{i++; next} i>=2' "$STATE")"
if (( DISTILL_EVERY > 0 )) && (( NEXT % DISTILL_EVERY == 0 )); then
  BODY="이번 사이클은 티켓 작업 전에 증류를 먼저 수행하라: .flywheel/journal/ 의 미처리 항목을 '실패→원인→일반화' 기준으로 걸러 LEARNINGS.md 에 병합(60줄 상한, 중복 제거)하고, 처리분은 journal/archive/ 로 옮긴 뒤 커밋하라. 그 다음:
$BODY"
fi

block "$BODY" "🔁 flywheel cycle $NEXT/$MAX_CYCLES"
