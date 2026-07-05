#!/bin/bash
# test-stop-hook.sh — Stop hook 종료 조건 매트릭스
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
make_fixture "$TMP/proj"
mkdir -p .claude

HOOK="$REPO_ROOT/hooks/stop-loop.sh"
STATE=".claude/flywheel.local.md"
TRANS="$TMP/transcript.jsonl"
STDIN_JSON="{\"session_id\":\"sess-1\",\"transcript_path\":\"$TRANS\"}"

write_state() { # <session> <cycle> <max_cycles> <started_epoch> <max_hours> <distill_every>
  cat > "$STATE" <<EOF
---
session_id: $1
cycle: $2
max_cycles: $3
started_epoch: $4
max_hours: $5
distill_every: $6
---
loop-protocol 스킬대로 정확히 1사이클을 수행하라.
EOF
}

write_transcript() { # <assistant 텍스트>
  printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"%s"}]}}\n' "$1" > "$TRANS"
}

run_hook() { echo "$STDIN_JSON" | bash "$HOOK" 2>&1; }

NOW="$(date +%s)"
write_transcript "사이클 작업을 계속한다"

echo "[비활성/격리]"

out="$(run_hook)"; rc=$?
assert_rc "상태 파일 없음 → 통과" 0 "$rc"
assert_not_contains "블록 없음" "block" "$out"

write_state "sess-OTHER" 1 25 "$NOW" 4 5
out="$(run_hook)"; rc=$?
assert_rc "세션 불일치 → 통과" 0 "$rc"
assert_file "다른 세션 상태 파일 보존" "$STATE"
rm "$STATE"

write_state "pending" 1 25 "$NOW" 4 5
out="$(run_hook)"; rc=$?
assert_contains "pending 세션 → 계속(블록)" '"decision"' "$out"
assert_contains "세션 입양됨" "session_id: sess-1" "$(cat "$STATE")"
rm "$STATE"

echo "[예산·에스컬레이션 정지]"

write_state "sess-1" 25 25 "$NOW" 4 5
out="$(run_hook)"; rc=$?
assert_rc "사이클 상한 → 정지" 0 "$rc"
assert_contains "상한 메시지" "사이클 상한" "$out"
assert_no_file "상태 파일 제거됨" "$STATE"

write_state "sess-1" 1 25 "$((NOW - 100000))" 4 5
out="$(run_hook)"; rc=$?
assert_rc "시간 상한 → 정지" 0 "$rc"
assert_contains "시간 상한 메시지" "시간 상한" "$out"

write_state "sess-1" 1 25 "$NOW" 4 5
echo "# BLOCKED" > .flywheel/BLOCKED.md
out="$(run_hook)"; rc=$?
assert_rc "BLOCKED.md → 정지" 0 "$rc"
assert_contains "에스컬레이션 메시지" "사람 개입" "$out"
rm .flywheel/BLOCKED.md

write_state "sess-1" abc 25 "$NOW" 4 5
out="$(run_hook)"; rc=$?
assert_rc "손상된 필드 → 정지" 0 "$rc"
assert_no_file "손상 시 상태 파일 제거" "$STATE"

echo "[완료 주장의 게이트 승격]"

# 거짓 COMPLETE — todo 에 티켓이 남아 있음
cat > .flywheel/backlog/todo/001-t.md <<'EOF'
# 001-t
## Goal
남은 일
## Acceptance
- [ ] 기준
## Verify
```sh
true
```
## Attempts
EOF
git add -A && git commit -qm "loop: 티켓 추가"
write_state "sess-1" 3 25 "$NOW" 4 5
write_transcript "다 했다 <promise>FLYWHEEL_COMPLETE</promise>"
out="$(run_hook)"; rc=$?
assert_contains "거짓 완료 → 블록" '"decision"' "$out"
assert_contains "반증 사유 포함" "반증" "$out"
assert_contains "게이트 사유 포함" "todo/" "$out"

# 진짜 COMPLETE — 백로그 소진 + clean
mv .flywheel/backlog/todo/001-t.md .flywheel/backlog/done/
git add -A && git commit -qm "loop: 티켓 완료"
out="$(run_hook)"; rc=$?
assert_rc "진짜 완료 → 정지" 0 "$rc"
assert_contains "완료 메시지" "게이트 검증을 통과" "$out"
assert_no_file "완료 시 상태 파일 제거" "$STATE"

# BLOCKED 약속인데 BLOCKED.md 없음
write_state "sess-1" 3 25 "$NOW" 4 5
write_transcript "막혔다 <promise>FLYWHEEL_BLOCKED</promise>"
out="$(run_hook)"; rc=$?
assert_contains "파일 없는 BLOCKED 약속 → 블록" '"decision"' "$out"
assert_contains "BLOCKED.md 작성 지시" "BLOCKED.md" "$out"
rm "$STATE"

echo "[사이클 계속·계약 위반]"

# 정상 계속 — 사이클 증가 + 본문 재주입
write_state "sess-1" 1 25 "$NOW" 4 5
write_transcript "사이클 작업 완료, 다음으로"
out="$(run_hook)"; rc=$?
assert_contains "계속 → 블록" '"decision"' "$out"
assert_contains "본문 재주입" "1사이클" "$out"
assert_contains "사이클 증가" "cycle: 2" "$(cat "$STATE")"
assert_contains "systemMessage 카운트" "cycle 2/25" "$out"
rm "$STATE"

# 계약 위반 — 위반 메시지만 재주입, 사이클 미증가
write_state "sess-1" 1 25 "$NOW" 4 5
echo "dirty" > uncommitted.txt
out="$(run_hook)"; rc=$?
assert_contains "위반 → 블록" '"decision"' "$out"
assert_contains "위반 사유 재주입" "GATE[C2]" "$out"
assert_contains "사이클 미증가" "cycle: 1" "$(cat "$STATE")"
rm -f uncommitted.txt "$STATE" .flywheel/local/gate-rejections

# 증류 사이클 — next 가 distill_every 배수면 증류 지시 선행
write_state "sess-1" 4 25 "$NOW" 4 5
write_transcript "사이클 작업 완료"
out="$(run_hook)"; rc=$?
assert_contains "증류 지시 포함" "증류" "$out"
rm -f "$STATE"

summary
