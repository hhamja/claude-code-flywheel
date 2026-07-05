#!/bin/bash
# DO NOT EDIT — /flywheel:init 이 항상 덮어쓰는 engine 파일입니다.
# gate.sh — flywheel 결정적 계약 검사 (단일 소스, 토큰 0)
#
# 인터랙티브 Stop hook 과 무인 run.sh 가 같은 이 파일을 호출한다.
# 이 스크립트는 판단하지 않는다 — 검사하고, 거부 사유를 출력할 뿐이다.
#
# 사용:
#   gate.sh cycle          사이클 계약 검사 (C1~C4). 통과 시 베이스라인 전진.
#   gate.sh ticket <file>  티켓의 ## Verify 블록 실행.
#   gate.sh done           완료 주장 검증 (백로그 소진 + clean + VERIFY_CMD).
#
# 종료 코드: 0=통과, 1=위반(사유는 stdout), 2=사용법/환경 오류
#
# env:
#   FLYWHEEL_INTERACTIVE=1  cycle 모드에서 연속 3회 거부 시 fail-open (무한 차단 방지)

set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# 설치 위치는 <project>/.flywheel/bin/gate.sh — 두 단계 위가 프로젝트 루트.
# 플러그인 저장소 안(scripts/)에서 직접 실행될 때는 FLYWHEEL_ROOT 로 재정의한다.
PROJECT_ROOT="${FLYWHEEL_ROOT:-$(cd "$SELF_DIR/../.." && pwd)}"
FW="$PROJECT_ROOT/.flywheel"

cd "$PROJECT_ROOT" || exit 2

if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "GATE[ENV]: git 저장소가 아닙니다 — flywheel 은 git 이 필요합니다."
  exit 2
fi
if [[ ! -d "$FW" ]]; then
  echo "GATE[ENV]: .flywheel/ 이 없습니다 — 먼저 /flywheel:init 을 실행하세요."
  exit 2
fi

MODE="${1:-}"
BASELINE_FILE="$FW/local/gate-baseline"
REJECT_FILE="$FW/local/gate-rejections"
mkdir -p "$FW/local"

# ── 공용 헬퍼 ────────────────────────────────────────────────────────────────

# 베이스라인 커밋(직전 통과 사이클의 HEAD). 없거나 유실(rebase 등)이면 현재 HEAD 로 리셋.
baseline_head() {
  local base=""
  [[ -f "$BASELINE_FILE" ]] && base="$(cat "$BASELINE_FILE")"
  if [[ -z "$base" ]] || ! git cat-file -e "$base^{commit}" 2>/dev/null; then
    base="$(git rev-parse HEAD 2>/dev/null || echo "")"
  fi
  echo "$base"
}

advance_baseline() {
  git rev-parse HEAD > "$BASELINE_FILE" 2>/dev/null || true
  rm -f "$REJECT_FILE"
}

# ── cycle: 사이클 계약 검사 ──────────────────────────────────────────────────

check_cycle() {
  local violations=""
  local base
  base="$(baseline_head)"
  if [[ -z "$base" ]]; then
    # 커밋이 하나도 없는 저장소 — 검사 불능. 통과시키되 안내.
    echo "GATE[WARN]: 커밋이 없는 저장소 — 첫 커밋 후 계약 검사가 활성화됩니다."
    return 0
  fi

  # 베이스라인 이후 변경 파일 (커밋분 + 워킹트리)
  # 루프 상태 파일은 계약 대상이 아니다 (seed 가 gitignore 하지만 방어적으로도 제외)
  local changed
  changed="$( { git diff --name-only "$base" HEAD 2>/dev/null; git status --porcelain=v1 | cut -c4-; } \
    | grep -v '^\.claude/flywheel\.local\.md$' | sort -u )"

  local non_fw journal_touched
  non_fw="$(echo "$changed" | grep -v '^\.flywheel/' | grep -v '^$' || true)"
  journal_touched="$(echo "$changed" | grep -E '^\.flywheel/(journal/|STATE\.md)' || true)"

  # C1 — 작업 흔적이 있는데 journal/STATE 미갱신
  if [[ -n "$non_fw" ]] && [[ -z "$journal_touched" ]]; then
    violations+="GATE[C1]: 파일을 변경했지만 .flywheel/journal/ 또는 STATE.md 를 갱신하지 않았습니다. 이번 사이클에서 한 일을 journal 에 1-3줄 append 하고 STATE.md 의 Now/Next 를 갱신하세요.
"
  fi

  # C3 — 사람 게이트: 목적함수(GOAL.md, policies.env)는 사람이 루프 밖에서 직접 커밋으로만
  local gate_files_dirty gate_files_committed
  gate_files_dirty="$(git status --porcelain=v1 -- .flywheel/GOAL.md .flywheel/policies.env | cut -c4- || true)"
  gate_files_committed="$(git diff --name-only "$base" HEAD -- .flywheel/GOAL.md .flywheel/policies.env 2>/dev/null || true)"
  if [[ -n "$gate_files_dirty" ]] || [[ -n "$gate_files_committed" ]]; then
    violations+="GATE[C3]: 사람 게이트 파일이 루프 사이클 중 변경되었습니다 ($(echo "$gate_files_dirty $gate_files_committed" | tr '\n' ' ')). GOAL.md 와 policies.env 는 목적함수이므로 루프가 수정할 수 없습니다. 변경을 되돌리세요 (git checkout -- <파일>).
"
  fi

  # C2 — 미커밋 잔류 (완료 = 커밋). local/ 은 gitignore 로 자동 제외됨.
  local dirty
  dirty="$(git status --porcelain=v1 | cut -c4- \
    | grep -v -E '^\.flywheel/(GOAL\.md|policies\.env)$|^\.claude/flywheel\.local\.md$' || true)"
  if [[ -n "$dirty" ]]; then
    violations+="GATE[C2]: 미커밋 변경이 남아 있습니다:
$(echo "$dirty" | head -10 | sed 's/^/  - /')
작업 단위가 끝났다면 커밋하세요. 완료는 커밋으로만 인정됩니다.
"
  fi

  # C4 — 게이밍 검사
  # (a) 테스트 파일 삭제
  local deleted_tests
  deleted_tests="$( { git diff --name-status "$base" HEAD 2>/dev/null | awk '$1=="D"{print $2}'; git status --porcelain=v1 | awk '$1=="D"{print $2}'; } \
    | grep -E '(^|/)(tests?|__tests__|spec)(/|$)|[._-](test|spec)\.[a-z]+$|(^|/)test_[^/]+$' || true)"
  if [[ -n "$deleted_tests" ]]; then
    violations+="GATE[C4]: 테스트 파일이 삭제되었습니다:
$(echo "$deleted_tests" | head -5 | sed 's/^/  - /')
테스트 삭제는 게이밍으로 간주됩니다. 복구하세요.
"
  fi

  # (b) 테스트 파일에 skip 마커 추가
  local skip_added
  skip_added="$(git diff "$base" -- ':(glob)**/*test*' ':(glob)**/*spec*' 2>/dev/null \
    | grep -E '^\+' | grep -vE '^\+\+\+' \
    | grep -E '\.skip\(|\bxit\(|\bxdescribe\(|\bxtest\(|@pytest\.mark\.skip|@unittest\.skip|#\[ignore\]|\bt\.Skip\(' || true)"
  if [[ -n "$skip_added" ]]; then
    violations+="GATE[C4]: 테스트에 skip 마커가 추가되었습니다:
$(echo "$skip_added" | head -3 | sed 's/^/  /')
테스트를 통과시키는 대신 건너뛰는 것은 게이밍입니다. 제거하세요.
"
  fi

  # (c) 티켓 Acceptance 체크박스 삭제/변조 (체크 토글 '- [ ]' → '- [x]' 는 허용)
  local ticket_diff removed_boxes added_boxes line norm
  ticket_diff="$(git diff "$base" -- .flywheel/backlog 2>/dev/null || true)"
  if [[ -n "$ticket_diff" ]]; then
    removed_boxes="$(echo "$ticket_diff" | grep -E '^-[[:space:]]*- \[[ xX]\]' | sed -E 's/^-[[:space:]]*- \[[ xX]\][[:space:]]*//' || true)"
    added_boxes="$(echo "$ticket_diff" | grep -E '^\+[[:space:]]*- \[[ xX]\]' | sed -E 's/^\+[[:space:]]*- \[[ xX]\][[:space:]]*//' || true)"
    local missing=""
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      if ! echo "$added_boxes" | grep -qxF "$line"; then
        missing+="  - $line
"
      fi
    done <<< "$removed_boxes"
    if [[ -n "$missing" ]]; then
      violations+="GATE[C4]: 티켓의 Acceptance 항목이 삭제·변조되었습니다:
${missing}기준을 바꾸는 대신 기준을 만족시키세요. 원복하세요.
"
    fi
  fi

  # ── 판정 ──
  if [[ -z "$violations" ]]; then
    advance_baseline
    return 0
  fi

  # fail-open: 인터랙티브 한정, 연속 3회 거부 시 무한 차단 방지
  if [[ "${FLYWHEEL_INTERACTIVE:-0}" == "1" ]]; then
    local rejects=0
    [[ -f "$REJECT_FILE" ]] && rejects="$(cat "$REJECT_FILE")"
    [[ "$rejects" =~ ^[0-9]+$ ]] || rejects=0
    rejects=$((rejects + 1))
    if (( rejects >= 3 )); then
      echo "GATE[WARN]: 연속 ${rejects}회 거부 — fail-open 으로 통과시킵니다 (무한 차단 방지). 미해결 위반:"
      printf '%s' "$violations"
      advance_baseline
      return 0
    fi
    echo "$rejects" > "$REJECT_FILE"
  fi

  printf '%s' "$violations"
  return 1
}

# ── ticket: ## Verify 블록 실행 ──────────────────────────────────────────────

check_ticket() {
  local ticket="${1:-}"
  if [[ -z "$ticket" ]] || [[ ! -f "$ticket" ]]; then
    echo "GATE[ENV]: 티켓 파일을 찾을 수 없습니다: '$ticket'"
    return 2
  fi
  local cmds
  cmds="$(awk '/^## Verify/{f=1;next} /^## /{f=0} f' "$ticket" | awk '/^```/{c=!c;next} c')"
  if [[ -z "$cmds" ]]; then
    echo "GATE[TICKET]: '$ticket' 에 실행 가능한 ## Verify 블록이 없습니다. Verify 없는 티켓은 완료 판정이 불가능합니다."
    return 1
  fi
  local out rc
  out="$(bash -e -c "$cmds" 2>&1)"
  rc=$?
  if (( rc != 0 )); then
    echo "GATE[TICKET]: Verify 실패 (exit $rc) — $ticket"
    echo "$out" | tail -20 | sed 's/^/  /'
    return 1
  fi
  return 0
}

# ── done: 완료 주장 검증 ─────────────────────────────────────────────────────

check_done() {
  local violations=""
  if [[ -f "$FW/BLOCKED.md" ]]; then
    violations+="GATE[DONE]: BLOCKED.md 가 존재합니다 — 막힌 상태에서는 완료가 아닙니다.
"
  fi
  local todo_count doing_count
  todo_count="$(find "$FW/backlog/todo" -name '*.md' -type f 2>/dev/null | wc -l | tr -d ' ')"
  doing_count="$(find "$FW/backlog/doing" -name '*.md' -type f 2>/dev/null | wc -l | tr -d ' ')"
  (( todo_count > 0 )) && violations+="GATE[DONE]: todo/ 에 티켓 ${todo_count}개가 남아 있습니다.
"
  (( doing_count > 0 )) && violations+="GATE[DONE]: doing/ 에 진행 중 티켓 ${doing_count}개가 남아 있습니다.
"
  local dirty
  dirty="$(git status --porcelain=v1 || true)"
  [[ -n "$dirty" ]] && violations+="GATE[DONE]: 미커밋 변경이 남아 있습니다 — 완료는 커밋으로만 인정됩니다.
"
  # 전역 품질 게이트 — policies.env 는 셸 env 파일이므로 서브셸에서 source 해 정확히 읽는다
  local verify_cmd=""
  if [[ -f "$FW/policies.env" ]]; then
    verify_cmd="$(bash -c "source '$FW/policies.env' 2>/dev/null; printf '%s' \"\${VERIFY_CMD:-}\"")"
  fi
  if [[ -n "$verify_cmd" ]]; then
    local out rc
    out="$(bash -c "$verify_cmd" 2>&1)"
    rc=$?
    if (( rc != 0 )); then
      violations+="GATE[DONE]: 전역 검증 실패 (VERIFY_CMD: $verify_cmd, exit $rc)
$(echo "$out" | tail -10 | sed 's/^/  /')
"
    fi
  fi
  if [[ -n "$violations" ]]; then
    printf '%s' "$violations"
    return 1
  fi
  return 0
}

# ── 진입점 ───────────────────────────────────────────────────────────────────

case "$MODE" in
  cycle)  check_cycle ;;
  ticket) check_ticket "${2:-}" ;;
  done)   check_done ;;
  *)      echo "사용법: gate.sh cycle | ticket <file> | done"; exit 2 ;;
esac
