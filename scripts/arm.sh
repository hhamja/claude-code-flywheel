#!/bin/bash
# arm.sh — 인터랙티브 루프 무장/해제 (결정적)
#
# 사용:
#   arm.sh [--max-cycles N] [--max-hours H]   루프 무장 (상태 파일 생성)
#   arm.sh --disarm                            루프 해제 + 무인 프로세스 종료 + doing 반납

set -euo pipefail

PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$PROJECT_ROOT"
STATE=".claude/flywheel.local.md"
FW=".flywheel"

# policies.env 는 source 하지 않는다 — source 는 파일 전체를 실행하므로 신뢰할 수 없는
# 저장소에서 임의 코드 실행(RCE) 위험이 있다. 이 파서는 문자열 처리만 한다.
read_policy() { # <파일> <KEY> — 스칼라 값만 안전 추출
  local file="$1" key="$2" line val
  [[ -f "$file" ]] || return 0
  line="$(grep -E "^[[:space:]]*${key}=" "$file" 2>/dev/null | head -1)"
  [[ -n "$line" ]] || return 0
  val="${line#*=}"
  val="${val#"${val%%[![:space:]]*}"}"
  case "$val" in
    '"'*) val="${val#\"}"; val="${val%%\"*}" ;;
    "'"*) val="${val#\'}"; val="${val%%\'*}" ;;
    *)    val="${val%%[[:space:]#]*}" ;;
  esac
  printf '%s' "$val"
}

# ── 해제 ─────────────────────────────────────────────────────────────────────
if [[ "${1:-}" == "--disarm" ]]; then
  if [[ -f "$STATE" ]]; then
    rm "$STATE"
    echo "DISARMED: 인터랙티브 루프를 해제했습니다."
  else
    echo "INFO: 활성 인터랙티브 루프가 없습니다."
  fi
  if [[ -f "$FW/local/run.pid" ]]; then
    pid="$(cat "$FW/local/run.pid")"
    if [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null || true
      echo "KILLED: 무인 루프 프로세스 (pid $pid)"
    fi
    rm -f "$FW/local/run.pid"
  fi
  for t in "$FW/backlog/doing"/*.md; do
    [[ -f "$t" ]] || continue
    mv "$t" "$FW/backlog/todo/"
    echo "RETURNED: $(basename "$t") → todo/"
  done
  exit 0
fi

# ── 무장 사전조건 (사람 게이트 승인 = 커밋) ──────────────────────────────────
if [[ ! -d "$FW" ]]; then
  echo "ERROR: .flywheel/ 이 없습니다 — 먼저 /flywheel:init 을 실행하세요."
  exit 1
fi
if ! git ls-files --error-unmatch "$FW/GOAL.md" >/dev/null 2>&1; then
  echo "ERROR: GOAL.md 가 커밋되지 않았습니다 — 사람 게이트 미승인 상태입니다."
  echo "       검토 후 'git add .flywheel && git commit' 으로 승인하세요."
  exit 1
fi
if ! git diff --quiet HEAD -- "$FW/GOAL.md" "$FW/policies.env" 2>/dev/null; then
  echo "ERROR: GOAL.md 또는 policies.env 에 미커밋 변경이 있습니다 — 검토 후 커밋(=승인)하세요."
  exit 1
fi
todo_n="$(find "$FW/backlog/todo" -name '*.md' -type f 2>/dev/null | wc -l | tr -d ' ')"
doing_n="$(find "$FW/backlog/doing" -name '*.md' -type f 2>/dev/null | wc -l | tr -d ' ')"
if (( todo_n == 0 && doing_n == 0 )); then
  echo "ERROR: 백로그가 비어 있습니다 — 티켓을 작성하거나 /flywheel:triage 를 먼저 실행하세요."
  exit 1
fi
if [[ -f "$FW/BLOCKED.md" ]]; then
  echo "ERROR: BLOCKED.md 가 존재합니다 — 해결 후 파일을 삭제해야 루프를 시작할 수 있습니다."
  exit 1
fi

# ── 인자 파싱 ────────────────────────────────────────────────────────────────
MAX_CYCLES=25
MAX_HOURS=4
while (( $# > 0 )); do
  case "$1" in
    --max-cycles) MAX_CYCLES="${2:-25}"; shift 2 ;;
    --max-hours)  MAX_HOURS="${2:-4}"; shift 2 ;;
    *) shift ;;
  esac
done
[[ "$MAX_CYCLES" =~ ^[0-9]+$ ]] || { echo "ERROR: --max-cycles 는 정수여야 합니다"; exit 1; }
[[ "$MAX_HOURS" =~ ^[0-9]+$ ]] || { echo "ERROR: --max-hours 는 정수여야 합니다"; exit 1; }

DISTILL_EVERY="$(read_policy "$FW/policies.env" DISTILL_EVERY)"
[[ "$DISTILL_EVERY" =~ ^[0-9]+$ ]] || DISTILL_EVERY=5

# ── 상태 파일 생성 ───────────────────────────────────────────────────────────
mkdir -p .claude
cat > "$STATE" <<EOF
---
session_id: ${CLAUDE_CODE_SESSION_ID:-pending}
cycle: 1
max_cycles: $MAX_CYCLES
started_epoch: $(date +%s)
max_hours: $MAX_HOURS
distill_every: $DISTILL_EVERY
---
.flywheel/STATE.md 를 읽고 loop-protocol 스킬대로 정확히 1사이클을 수행하라
(티켓 claim → builder → auditor → 기록 → 커밋). 백로그가 비었고 GOAL 이 충족되면
<promise>FLYWHEEL_COMPLETE</promise> 를, 막혔으면 .flywheel/BLOCKED.md 작성 후
<promise>FLYWHEEL_BLOCKED</promise> 를 출력하라. 약속은 진실일 때만 — 게이트가 재검증한다.
EOF

echo "ARMED: 인터랙티브 루프 무장 완료 — cycle 1/$MAX_CYCLES, 최대 ${MAX_HOURS}시간, 백로그 todo ${todo_n}개"
