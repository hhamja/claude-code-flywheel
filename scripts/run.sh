#!/bin/bash
# DO NOT EDIT — /flywheel:init 이 항상 덮어쓰는 engine 파일입니다.
# run.sh — flywheel 무인 루프 오케스트레이터 (셸 상태머신)
#
# 이 스크립트는 판단하지 않는다 — 상태 전이·검사·기록·정지만 한다.
# 무엇을 어떻게 고칠지는 전부 워커(LLM CLI)의 몫이다.
#
# 사용: .flywheel/bin/run.sh [--max-cycles N] [--once] [--dry-run] [--worktree] [--worker CMD]
#
# 워커 계약: 단일 명령 문자열, stdin=프롬프트 전문, cwd=프로젝트 루트, exit 0=턴 완료.
#   우선순위: --worker > $FLYWHEEL_WORKER > policies.env WORKER_CMD > claude -p
#   교체 예:  FLYWHEEL_WORKER='codex exec --skip-git-repo-check -' .flywheel/bin/run.sh
#
# 종료 코드: 0=DONE(게이트 통과), 2=예산 상한, 3=BLOCKED(사람 개입), 4=DONE 주장 반증

set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${FLYWHEEL_ROOT:-$(cd "$SELF_DIR/../.." && pwd)}"
cd "$PROJECT_ROOT" || exit 2
FW=".flywheel"
GATE="$FW/bin/gate.sh"

[[ -d "$FW" ]] || { echo "ERROR: .flywheel/ 없음 — 먼저 /flywheel:init"; exit 2; }
[[ -x "$GATE" ]] || { echo "ERROR: $GATE 없음 — /flywheel:init 으로 engine 을 갱신하세요"; exit 2; }
git rev-parse --git-dir >/dev/null 2>&1 || { echo "ERROR: git 저장소가 아닙니다"; exit 2; }
git ls-files --error-unmatch "$FW/GOAL.md" >/dev/null 2>&1 \
  || { echo "ERROR: GOAL.md 미커밋 — 사람 게이트 미승인. 검토 후 커밋하세요."; exit 2; }

# ── 인자 파싱 ────────────────────────────────────────────────────────────────
MAX_CYCLES_ARG="" ONCE=0 DRY=0 WORKTREE=0 WORKER_ARG=""
PASS_ARGS=()
while (( $# > 0 )); do
  case "$1" in
    --max-cycles) MAX_CYCLES_ARG="${2:-}"; PASS_ARGS+=("$1" "${2:-}"); shift 2 ;;
    --once)       ONCE=1; PASS_ARGS+=("$1"); shift ;;
    --dry-run)    DRY=1; PASS_ARGS+=("$1"); shift ;;
    --worktree)   WORKTREE=1; shift ;;   # 재실행 인자에서 제외 (무한 재귀 방지)
    --worker)     WORKER_ARG="${2:-}"; PASS_ARGS+=("$1" "${2:-}"); shift 2 ;;
    *) shift ;;
  esac
done

# ── 정책 로드 (사람 게이트 파일) ─────────────────────────────────────────────
# policies.env 는 source 하지 않는다 — source 는 파일 전체를 셸로 실행하므로
# 신뢰할 수 없는 저장소를 클론해 루프를 돌리면 임의 코드 실행(RCE)이 된다.
# 아래 파서는 문자열 처리만 하며 값 안의 $(...)·백틱·${...} 를 절대 평가하지 않는다.
# (VERIFY_CMD/WORKER_CMD 값은 의도된 실행 지점에서만 bash -c 로 실행된다.)
read_policy() { # <파일> <KEY> — 스칼라 값만 안전 추출
  local file="$1" key="$2" line val
  [[ -f "$file" ]] || return 0
  line="$(grep -E "^[[:space:]]*${key}=" "$file" 2>/dev/null | head -1)"
  [[ -n "$line" ]] || return 0
  val="${line#*=}"
  val="${val#"${val%%[![:space:]]*}"}"              # 앞쪽 공백 제거
  case "$val" in
    '"'*) val="${val#\"}"; val="${val%%\"*}" ;;     # "..." 안쪽
    "'"*) val="${val#\'}"; val="${val%%\'*}" ;;     # '...' 안쪽
    *)    val="${val%%[[:space:]#]*}" ;;            # 첫 공백/주석 전까지
  esac
  printf '%s' "$val"
}

POL="$FW/policies.env"
MAX_CYCLES="${MAX_CYCLES_ARG:-$(read_policy "$POL" MAX_CYCLES)}"
MAX_HOURS="$(read_policy "$POL" MAX_HOURS)"
MAX_RETRIES="$(read_policy "$POL" MAX_RETRIES)"
TIMEOUT_S="$(read_policy "$POL" TIMEOUT_S)"
AUTO_COMMIT="$(read_policy "$POL" AUTO_COMMIT)"
DISTILL_EVERY="$(read_policy "$POL" DISTILL_EVERY)"
AUDIT="$(read_policy "$POL" AUDIT)"
POL_WORKER="$(read_policy "$POL" WORKER_CMD)"
WORKER="${WORKER_ARG:-${FLYWHEEL_WORKER:-${POL_WORKER:-claude -p --dangerously-skip-permissions}}}"
AUDITOR="${FLYWHEEL_AUDITOR:-claude -p --dangerously-skip-permissions --model opus}"

# 형식 검증 — 숫자 정책은 정수만, 열거형은 허용값만 (손상·주입 시 기본값으로 복구)
[[ "$MAX_CYCLES"    =~ ^[0-9]+$ ]] || MAX_CYCLES=25
[[ "$MAX_HOURS"     =~ ^[0-9]+$ ]] || MAX_HOURS=12
[[ "$MAX_RETRIES"   =~ ^[0-9]+$ ]] || MAX_RETRIES=2
[[ "$TIMEOUT_S"     =~ ^[0-9]+$ ]] || TIMEOUT_S=900
[[ "$DISTILL_EVERY" =~ ^[0-9]+$ ]] || DISTILL_EVERY=5
[[ "$AUTO_COMMIT" == "true" || "$AUTO_COMMIT" == "false" ]] || AUTO_COMMIT=true
[[ "$AUDIT" == "deterministic" || "$AUDIT" == "llm" ]] || AUDIT=deterministic

# ── worktree 격리 모드: 격리 사본에서 재실행 ─────────────────────────────────
RUNID="r$(date +%s)-$$"
if (( WORKTREE )); then
  WT="$(dirname "$PROJECT_ROOT")/$(basename "$PROJECT_ROOT")-loop-$RUNID"
  git worktree add "$WT" -b "loop/$RUNID" >/dev/null 2>&1 \
    || { echo "ERROR: git worktree 생성 실패"; exit 2; }
  [[ -x "$WT/$FW/bin/run.sh" ]] \
    || { echo "ERROR: .flywheel 이 커밋되어 있지 않아 worktree 에 없습니다 — 커밋 후 다시"; exit 2; }
  echo "WORKTREE: $WT (브랜치 loop/$RUNID) — 머지는 사람 몫입니다"
  exec "$WT/$FW/bin/run.sh" ${PASS_ARGS[@]+"${PASS_ARGS[@]}"}
fi

# ── 트레이스·로그·pid ───────────────────────────────────────────────────────
TRACE_DIR="$FW/local/trace/$RUNID"
mkdir -p "$TRACE_DIR" "$FW/local"
LOG="$TRACE_DIR/run.log"
log()   { echo "[$(date '+%F %T')] $*" | tee -a "$LOG"; }
trace() { echo "$1" >> "$TRACE_DIR/run.jsonl"; }
echo $$ > "$FW/local/run.pid"
trap 'rm -f "'"$FW"'/local/run.pid"' EXIT

# ── 헬퍼 ─────────────────────────────────────────────────────────────────────
run_with_timeout() { # <초> <stdin파일> <명령...> — macOS(기본 timeout 없음)/Linux 겸용
  local t="$1" sf="$2"; shift 2
  if command -v timeout >/dev/null 2>&1; then
    timeout "$t" "$@" < "$sf"; return $?
  fi
  # 폴백: 백그라운드 프로세스는 stdin 이 /dev/null 로 리셋되므로 파일로 명시 리다이렉트
  "$@" < "$sf" & local pid=$!
  ( sleep "$t" && kill -TERM "$pid" 2>/dev/null ) & local watcher=$!
  local rc=0
  wait "$pid" 2>/dev/null || rc=$?
  kill "$watcher" 2>/dev/null; wait "$watcher" 2>/dev/null
  return $rc
}

worker_call() { # <프롬프트> <로그파일>
  local pf="$TRACE_DIR/.prompt.$$"
  printf '%s\n' "$1" > "$pf"
  local rc=0
  run_with_timeout "$TIMEOUT_S" "$pf" bash -c "$WORKER" > "$2" 2>&1 || rc=$?
  rm -f "$pf"
  return $rc
}

auto_commit() { # <메시지>
  if [[ "$AUTO_COMMIT" == "true" ]] && [[ -n "$(git status --porcelain=v1)" ]]; then
    git add -A >/dev/null 2>&1
    git commit -qm "$1" >/dev/null 2>&1 || true
  fi
}

count_md() { find "$1" -name '*.md' -type f 2>/dev/null | wc -l | tr -d ' '; }

# ── 메인 상태머신 ────────────────────────────────────────────────────────────
STARTED="$(date +%s)"
cycle=1
done_count=0
log "flywheel run $RUNID 시작 — max_cycles=$MAX_CYCLES retries=$MAX_RETRIES timeout=${TIMEOUT_S}s audit=$AUDIT"
log "worker: $WORKER"

while true; do
  # STOP-CHECK ---------------------------------------------------------------
  if [[ -f "$FW/BLOCKED.md" ]]; then
    log "BLOCKED.md 발견 — 사람 개입 필요. 정지 (exit 3)"
    exit 3
  fi
  todo_n="$(count_md "$FW/backlog/todo")"
  doing_n="$(count_md "$FW/backlog/doing")"
  if (( todo_n == 0 && doing_n == 0 )); then
    if out="$("$GATE" done 2>&1)"; then
      log "백로그 소진 + done 게이트 통과 — 완료 (exit 0)"
      exit 0
    fi
    log "백로그는 소진했으나 done 게이트 실패 (exit 4):"
    printf '%s\n' "$out" | tee -a "$LOG"
    exit 4
  fi
  if (( cycle > MAX_CYCLES )); then
    log "사이클 상한($MAX_CYCLES) 도달 — 정지 (exit 2). 재개: run.sh 재실행"
    exit 2
  fi
  if (( $(date +%s) - STARTED > MAX_HOURS * 3600 )); then
    log "시간 상한(${MAX_HOURS}h) 도달 — 정지 (exit 2)"
    exit 2
  fi

  # CLAIM (mv = 원자적 상태 전이; doing/ 잔류 = 크래시 복구 우선) --------------
  ticket=""
  for t in "$FW/backlog/doing"/*.md; do
    [[ -f "$t" ]] && ticket="$t" && break
  done
  if [[ -z "$ticket" ]]; then
    t="$(ls "$FW/backlog/todo"/*.md 2>/dev/null | sort | head -1)"
    mv "$t" "$FW/backlog/doing/"
    ticket="$FW/backlog/doing/$(basename "$t")"
  fi
  tname="$(basename "$ticket")"
  attempt="$(grep -c '^#### attempt' "$ticket" 2>/dev/null || true)"
  [[ "$attempt" =~ ^[0-9]+$ ]] || attempt=0
  attempt=$((attempt + 1))

  if (( DRY )); then
    log "[dry-run] cycle $cycle: $tname (attempt $attempt) 을 처리할 것 — 워커 미실행, 정지"
    exit 0
  fi

  # EXECUTE (판단은 워커에게 — 프롬프트는 포인터만) ----------------------------
  PROMPT="너는 flywheel 무인 루프의 워커다. 티켓 $ticket 을 구현하라.
순서:
1) .flywheel/LEARNINGS.md 와 티켓의 ## Attempts(이전 실패 기록)를 읽어라 — 같은 실패를 반복하지 마라.
2) 티켓 ## Goal 을 ## Acceptance 기준으로 구현하라. 티켓 범위 밖 작업 금지.
3) 티켓 ## Verify 의 명령을 직접 실행해 통과시켜라.
4) .flywheel/journal/$(date '+%F').md 에 이번 작업 요약 1-3줄을 append 하고 .flywheel/STATE.md 의 Now/Next 를 갱신하라.
5) 모든 변경을 커밋하라.
금지: 테스트 삭제·스킵·기대값 하드코딩, 티켓 Acceptance 수정, GOAL.md·policies.env 수정 — 게이트가 diff 로 감지해 FAIL 처리한다."

  log "cycle $cycle: $tname (attempt $attempt) 워커 실행"
  t0="$(date +%s)"
  wrc=0
  worker_call "$PROMPT" "$TRACE_DIR/cycle-$cycle.log" || wrc=$?
  dur=$(( $(date +%s) - t0 ))

  auto_commit "loop($RUNID): cycle $cycle 워커 산출물 자동 커밋"

  # VERIFY (결정적 게이트가 진실 — 워커의 exit code 는 참고 정보) --------------
  vrc=0
  fail_out=""
  if ! out="$("$GATE" ticket "$ticket" 2>&1)"; then
    vrc=1; fail_out+="$out"$'\n'
  fi
  if ! out="$("$GATE" cycle 2>&1)"; then
    vrc=1; fail_out+="$out"$'\n'
  fi
  if (( vrc == 0 )) && [[ "$AUDIT" == "llm" ]]; then
    AUDIT_PROMPT="너는 flywheel 의 독립 감사자다. 파일을 수정하지 마라. 워커의 주장을 믿지 마라.
티켓 $ticket 의 ## Acceptance 각 항목을 직접 명령 실행으로 검증하고 증거를 인용하라.
git diff 에서 테스트 삭제/skip 추가/기대값 하드코딩/Acceptance 변조가 보이면 즉시 FAIL.
애매하면 FAIL 이 기본값이다. 첫 줄에 반드시 'VERDICT: PASS' 또는 'VERDICT: FAIL' 을 출력하라.
FAIL 이면 'fix_hints:' 로 구체적 교정 힌트를 덧붙여라. 15줄 이내."
    printf '%s\n' "$AUDIT_PROMPT" > "$TRACE_DIR/.audit-prompt.$$"
    run_with_timeout "$TIMEOUT_S" "$TRACE_DIR/.audit-prompt.$$" bash -c "$AUDITOR" \
      > "$TRACE_DIR/audit-$cycle.log" 2>&1 || true
    rm -f "$TRACE_DIR/.audit-prompt.$$"
    if ! grep -q 'VERDICT: PASS' "$TRACE_DIR/audit-$cycle.log"; then
      vrc=1
      fail_out+="LLM 감사 FAIL:"$'\n'"$(tail -15 "$TRACE_DIR/audit-$cycle.log")"$'\n'
    fi
  fi
  if (( vrc != 0 )) && (( wrc != 0 )); then
    fail_out+="(워커 비정상 종료 exit $wrc — 타임아웃 ${TIMEOUT_S}s 가능성)"$'\n'
  fi

  # RECORD ---------------------------------------------------------------------
  ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  if (( vrc == 0 )); then
    mv "$ticket" "$FW/backlog/done/"
    git add -A >/dev/null 2>&1
    git commit -qm "loop($RUNID): $tname 완료 (cycle $cycle)" >/dev/null 2>&1 || true
    "$GATE" cycle >/dev/null 2>&1 || true   # 완료 커밋 반영해 베이스라인 전진
    trace "{\"cycle\":$cycle,\"ticket\":\"$tname\",\"result\":\"pass\",\"attempt\":$attempt,\"worker_exit\":$wrc,\"dur_s\":$dur,\"ts\":\"$ts\"}"
    log "cycle $cycle: $tname PASS (${dur}s)"
    done_count=$((done_count + 1))

    # DISTILL — N티켓 완료마다 증류 턴 (journal → LEARNINGS)
    if (( DISTILL_EVERY > 0 )) && (( done_count % DISTILL_EVERY == 0 )); then
      DISTILL_PROMPT="너는 flywheel 무인 루프의 워커다. 이번 턴은 증류만 수행하라:
.flywheel/journal/ 의 파일들을 읽고 '실패→원인→일반화' 를 통과하는 일반화 가능한 교훈만
.flywheel/LEARNINGS.md 에 병합하라 (중복 제거, 60줄 상한 — 초과 시 오래되고 덜 일반적인 항목 퇴출).
처리한 journal 파일은 .flywheel/journal/archive/ 로 mv 하고 전부 커밋하라. 코드 수정 금지."
      log "cycle $cycle: 증류 턴 실행 (완료 ${done_count}건)"
      worker_call "$DISTILL_PROMPT" "$TRACE_DIR/distill-$cycle.log" || true
      auto_commit "loop($RUNID): 증류 자동 커밋"
    fi
  else
    {
      echo ""
      echo "#### attempt $attempt — $(date '+%F %T') (run $RUNID cycle $cycle)"
      echo '```'
      printf '%s\n' "$fail_out" | tail -20
      echo '```'
    } >> "$ticket"
    git add "$ticket" >/dev/null 2>&1
    git commit -qm "loop($RUNID): $tname attempt $attempt 실패 기록" >/dev/null 2>&1 || true
    trace "{\"cycle\":$cycle,\"ticket\":\"$tname\",\"result\":\"fail\",\"attempt\":$attempt,\"worker_exit\":$wrc,\"dur_s\":$dur,\"ts\":\"$ts\"}"
    log "cycle $cycle: $tname FAIL (attempt $attempt)"

    if (( attempt > MAX_RETRIES )); then
      mv "$ticket" "$FW/backlog/blocked/"
      cat > "$FW/BLOCKED.md" <<EOF
# BLOCKED

## 막힌 티켓
.flywheel/backlog/blocked/$tname

## 시도한 접근과 결과
${attempt}회 실패 — 티켓의 ## Attempts 기록 참조. 마지막 실패:
$(printf '%s\n' "$fail_out" | tail -10)

## 사람에게 묻는 질문
run.sh 자동 에스컬레이션입니다. Attempts 기록을 검토하고 접근 방향을 지시해 주세요.
해결 후 이 파일을 삭제하면 루프를 재개할 수 있습니다.
EOF
      git add -A >/dev/null 2>&1
      git commit -qm "loop($RUNID): $tname 에스컬레이션 (${attempt}회 실패)" >/dev/null 2>&1 || true
      log "$tname: 재시도 상한 초과 — blocked/ 이동 + BLOCKED.md 생성. 정지 (exit 3)"
      exit 3
    fi
  fi

  if (( ONCE )); then
    log "--once — 1사이클 후 정지 (exit 0)"
    exit 0
  fi
  cycle=$((cycle + 1))
done
