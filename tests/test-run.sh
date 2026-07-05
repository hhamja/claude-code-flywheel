#!/bin/bash
# test-run.sh — run.sh 무인 오케스트레이터 상태머신 검사 (mock 워커)
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
MOCK="$REPO_ROOT/tests/mock-worker.sh"

add_ticket() { # <NNN-slug> <verify파일>
  cat > ".flywheel/backlog/todo/$1.md" <<EOF
# $1
## Goal
$2 파일을 만든다
## Acceptance
- [ ] $2 존재
## Verify
\`\`\`sh
test -f $2
\`\`\`
## Attempts
EOF
}

set_policy() { # <KEY> <VALUE> — policies.env 수정 후 커밋(사람 게이트 승인 시뮬레이션)
  sed "s|^$1=.*|$1=$2|" .flywheel/policies.env > p.tmp && mv p.tmp .flywheel/policies.env
  git add -A && git commit -qm "config: $1=$2"
}

echo "[성공 시나리오 — 티켓 2개 완주 후 DONE]"
make_fixture "$TMP/ok"
add_ticket 001-a a.txt
add_ticket 002-b b.txt
git add -A && git commit -qm "loop: 티켓 2개"
out="$(MOCK_MODE=success FLYWHEEL_WORKER="$MOCK" .flywheel/bin/run.sh --max-cycles 5 2>&1)"; rc=$?
assert_rc "완주 후 DONE(exit 0)" 0 "$rc"
assert_file "산출물 a.txt" "a.txt"
assert_file "산출물 b.txt" "b.txt"
assert_file "티켓1 done/ 이동" ".flywheel/backlog/done/001-a.md"
assert_file "티켓2 done/ 이동" ".flywheel/backlog/done/002-b.md"
assert_rc "워킹트리 clean" 0 "$(git status --porcelain | wc -l | tr -d ' ')"
jsonl="$(cat .flywheel/local/trace/*/run.jsonl)"
assert_contains "trace pass 기록" '"result":"pass"' "$jsonl"
assert_rc "trace 2건" 2 "$(echo "$jsonl" | wc -l | tr -d ' ')"
assert_no_file "run.pid 정리됨" ".flywheel/local/run.pid"

echo "[실패 시나리오 — 재시도 소진 후 BLOCKED]"
make_fixture "$TMP/fail"
add_ticket 001-x x.txt
git add -A && git commit -qm "loop: 티켓 1개"
set_policy MAX_RETRIES 1
out="$(MOCK_MODE=fail FLYWHEEL_WORKER="$MOCK" .flywheel/bin/run.sh --max-cycles 5 2>&1)"; rc=$?
assert_rc "에스컬레이션(exit 3)" 3 "$rc"
assert_file "BLOCKED.md 생성" ".flywheel/BLOCKED.md"
assert_file "티켓 blocked/ 이동" ".flywheel/backlog/blocked/001-x.md"
assert_rc "attempt 2회 기록" 2 "$(grep -c '^#### attempt' .flywheel/backlog/blocked/001-x.md)"
assert_contains "질문 필드 존재" "사람에게 묻는 질문" "$(cat .flywheel/BLOCKED.md)"
# BLOCKED 상태에서 재실행 → 즉시 정지
out="$(MOCK_MODE=fail FLYWHEEL_WORKER="$MOCK" .flywheel/bin/run.sh 2>&1)"; rc=$?
assert_rc "BLOCKED 존재 시 즉시 정지(exit 3)" 3 "$rc"

echo "[예산 시나리오 — 사이클 상한]"
make_fixture "$TMP/budget"
add_ticket 001-a a.txt
add_ticket 002-b b.txt
git add -A && git commit -qm "loop: 티켓 2개"
out="$(MOCK_MODE=success FLYWHEEL_WORKER="$MOCK" .flywheel/bin/run.sh --max-cycles 1 2>&1)"; rc=$?
assert_rc "예산 도달(exit 2)" 2 "$rc"
assert_file "1개만 완료" ".flywheel/backlog/done/001-a.md"
assert_file "2번째는 잔류" ".flywheel/backlog/todo/002-b.md"

echo "[--once — 1사이클 후 일시정지]"
make_fixture "$TMP/once"
add_ticket 001-a a.txt
add_ticket 002-b b.txt
git add -A && git commit -qm "loop: 티켓 2개"
out="$(MOCK_MODE=success FLYWHEEL_WORKER="$MOCK" .flywheel/bin/run.sh --once 2>&1)"; rc=$?
assert_rc "--once 정지(exit 0)" 0 "$rc"
assert_file "1개 완료" ".flywheel/backlog/done/001-a.md"
assert_file "나머지 잔류" ".flywheel/backlog/todo/002-b.md"

echo "[타임아웃 — 워커가 멈추면 실패 처리 후 에스컬레이션]"
make_fixture "$TMP/timeout"
add_ticket 001-t t.txt
git add -A && git commit -qm "loop: 티켓 1개"
set_policy MAX_RETRIES 0
set_policy TIMEOUT_S 2
out="$(MOCK_MODE=timeout FLYWHEEL_WORKER="$MOCK" .flywheel/bin/run.sh 2>&1)"; rc=$?
assert_rc "타임아웃 → 에스컬레이션(exit 3)" 3 "$rc"
assert_contains "타임아웃 흔적" "타임아웃" "$(cat .flywheel/backlog/blocked/001-t.md)"

echo "[--dry-run — 상태 전이 없이 계획만]"
make_fixture "$TMP/dry"
add_ticket 001-a a.txt
git add -A && git commit -qm "loop: 티켓 1개"
out="$(FLYWHEEL_WORKER="$MOCK" .flywheel/bin/run.sh --dry-run 2>&1)"; rc=$?
assert_rc "dry-run 정지(exit 0)" 0 "$rc"
assert_contains "계획 출력" "dry-run" "$out"
assert_no_file "산출물 없음" "a.txt"

summary
