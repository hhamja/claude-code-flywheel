#!/bin/bash
# test-gate.sh — gate.sh 3모드 (cycle/ticket/done) + fail-open 검사
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
make_fixture "$TMP/proj"
GATE=".flywheel/bin/gate.sh"

echo "[cycle 모드]"

# 1. 깨끗한 상태 → 통과 (베이스라인 생성)
out="$("$GATE" cycle 2>&1)"; rc=$?
assert_rc "깨끗한 상태 통과" 0 "$rc"
assert_file "베이스라인 생성됨" ".flywheel/local/gate-baseline"

# 2. C2 — 미커밋 잔류
echo "dirty" > newfile.txt
out="$("$GATE" cycle 2>&1)"; rc=$?
assert_rc "미커밋 잔류 거부" 1 "$rc"
assert_contains "C2 메시지" "GATE[C2]" "$out"
rm newfile.txt

# 3. C1 — 소스 변경 커밋했는데 journal 미갱신
echo "change" >> src.txt
git add -A && git commit -qm "feat: journal 없이 변경"
out="$("$GATE" cycle 2>&1)"; rc=$?
assert_rc "journal 미갱신 거부" 1 "$rc"
assert_contains "C1 메시지" "GATE[C1]" "$out"
# journal 갱신 + 커밋으로 해소
touch_journal
git add -A && git commit -qm "loop: journal 기록"
out="$("$GATE" cycle 2>&1)"; rc=$?
assert_rc "journal 갱신 후 통과" 0 "$rc"

# 4. C3 — 사람 게이트 (미커밋 수정)
echo "# 몰래 수정" >> .flywheel/GOAL.md
out="$("$GATE" cycle 2>&1)"; rc=$?
assert_rc "GOAL.md 미커밋 수정 거부" 1 "$rc"
assert_contains "C3 메시지" "GATE[C3]" "$out"
git checkout -- .flywheel/GOAL.md

# 4b. C3 — 사람 게이트 (커밋된 수정도 거부)
echo "# 몰래 커밋" >> .flywheel/policies.env
touch_journal
git add -A && git commit -qm "hack: 정책 변조"
out="$("$GATE" cycle 2>&1)"; rc=$?
assert_rc "policies.env 커밋 변조 거부" 1 "$rc"
assert_contains "C3 메시지(커밋)" "GATE[C3]" "$out"
git reset -q --hard HEAD~1

# 5. C4a — 테스트 파일 삭제
mkdir -p tests_dir
echo "assert true" > tests_dir/foo.test.sh
touch_journal
git add -A && git commit -qm "test: 테스트 추가"
"$GATE" cycle > /dev/null 2>&1   # 베이스라인 전진
git rm -q tests_dir/foo.test.sh
touch_journal
git add -A && git commit -qm "chore: 테스트 삭제"
out="$("$GATE" cycle 2>&1)"; rc=$?
assert_rc "테스트 삭제 거부" 1 "$rc"
assert_contains "C4 삭제 메시지" "테스트 파일이 삭제" "$out"
git reset -q --hard HEAD~1
"$GATE" cycle > /dev/null 2>&1   # 베이스라인 재정렬

# 6. C4b — skip 마커 추가
echo 'it.skip("건너뛰기")' >> tests_dir/foo.test.sh
touch_journal
git add -A && git commit -qm "test: skip 추가"
out="$("$GATE" cycle 2>&1)"; rc=$?
assert_rc "skip 마커 거부" 1 "$rc"
assert_contains "C4 skip 메시지" "skip 마커" "$out"
git reset -q --hard HEAD~1
"$GATE" cycle > /dev/null 2>&1

# 7. C4c — 티켓 Acceptance 삭제 vs 토글
cat > .flywheel/backlog/todo/001-sample.md <<'EOF'
# 001-sample
## Goal
샘플
## Acceptance
- [ ] 기준 A
- [ ] 기준 B
## Verify
```sh
true
```
## Attempts
EOF
git add -A && git commit -qm "loop: 티켓 추가"
"$GATE" cycle > /dev/null 2>&1
# 삭제 → 거부
sed '/기준 B/d' .flywheel/backlog/todo/001-sample.md > t.md && mv t.md .flywheel/backlog/todo/001-sample.md
git add -A && git commit -qm "hack: AC 삭제"
out="$("$GATE" cycle 2>&1)"; rc=$?
assert_rc "Acceptance 삭제 거부" 1 "$rc"
assert_contains "C4 AC 메시지" "Acceptance" "$out"
git reset -q --hard HEAD~1
"$GATE" cycle > /dev/null 2>&1
# 토글([ ]→[x]) → 허용
sed 's/- \[ \] 기준 A/- [x] 기준 A/' .flywheel/backlog/todo/001-sample.md > t.md && mv t.md .flywheel/backlog/todo/001-sample.md
git add -A && git commit -qm "loop: AC 체크"
out="$("$GATE" cycle 2>&1)"; rc=$?
assert_rc "체크박스 토글 허용" 0 "$rc"

echo "[ticket 모드]"

out="$("$GATE" ticket .flywheel/backlog/todo/001-sample.md 2>&1)"; rc=$?
assert_rc "Verify true 통과" 0 "$rc"

cat > .flywheel/backlog/todo/002-fail.md <<'EOF'
# 002-fail
## Goal
실패 샘플
## Acceptance
- [ ] 불가능
## Verify
```sh
echo "의도된 실패"; false
```
## Attempts
EOF
out="$("$GATE" ticket .flywheel/backlog/todo/002-fail.md 2>&1)"; rc=$?
assert_rc "Verify false 실패" 1 "$rc"
assert_contains "실패 출력 포함" "의도된 실패" "$out"

cat > .flywheel/backlog/todo/003-noverify.md <<'EOF'
# 003-noverify
## Goal
Verify 없음
## Attempts
EOF
out="$("$GATE" ticket .flywheel/backlog/todo/003-noverify.md 2>&1)"; rc=$?
assert_rc "Verify 블록 없음 실패" 1 "$rc"

out="$("$GATE" ticket 없는파일.md 2>&1)"; rc=$?
assert_rc "티켓 파일 없음 rc=2" 2 "$rc"

rm .flywheel/backlog/todo/002-fail.md .flywheel/backlog/todo/003-noverify.md

echo "[done 모드]"

out="$("$GATE" done 2>&1)"; rc=$?
assert_rc "todo 잔여 시 done 실패" 1 "$rc"
assert_contains "todo 잔여 메시지" "todo/" "$out"

mv .flywheel/backlog/todo/001-sample.md .flywheel/backlog/done/
git add -A && git commit -qm "loop: 티켓 완료"
out="$("$GATE" done 2>&1)"; rc=$?
assert_rc "백로그 소진+clean 시 done 통과" 0 "$rc"

# VERIFY_CMD 실패 반영
sed 's/^VERIFY_CMD=.*/VERIFY_CMD="false"/' .flywheel/policies.env > t.env && mv t.env .flywheel/policies.env
git add -A && git commit -qm "config: VERIFY_CMD=false"
out="$("$GATE" done 2>&1)"; rc=$?
assert_rc "VERIFY_CMD 실패 시 done 실패" 1 "$rc"
assert_contains "전역 검증 메시지" "전역 검증 실패" "$out"
git reset -q --hard HEAD~1

# BLOCKED.md 존재 시 done 실패
echo "# BLOCKED" > .flywheel/BLOCKED.md
out="$("$GATE" done 2>&1)"; rc=$?
assert_rc "BLOCKED 존재 시 done 실패" 1 "$rc"
rm .flywheel/BLOCKED.md

echo "[fail-open (인터랙티브 한정)]"

"$GATE" cycle > /dev/null 2>&1   # 베이스라인·카운터 정리
echo "dirty" > stuck.txt          # 지속되는 C2 위반
out="$(FLYWHEEL_INTERACTIVE=1 "$GATE" cycle 2>&1)"; rc=$?
assert_rc "1회차 거부" 1 "$rc"
out="$(FLYWHEEL_INTERACTIVE=1 "$GATE" cycle 2>&1)"; rc=$?
assert_rc "2회차 거부" 1 "$rc"
out="$(FLYWHEEL_INTERACTIVE=1 "$GATE" cycle 2>&1)"; rc=$?
assert_rc "3회차 fail-open 통과" 0 "$rc"
assert_contains "fail-open 경고" "fail-open" "$out"
out="$(FLYWHEEL_INTERACTIVE=1 "$GATE" cycle 2>&1)"; rc=$?
assert_rc "카운터 리셋 후 다시 거부" 1 "$rc"
# 비인터랙티브는 fail-open 없음
"$GATE" cycle > /dev/null 2>&1; rc1=$?
"$GATE" cycle > /dev/null 2>&1; rc2=$?
"$GATE" cycle > /dev/null 2>&1; rc3=$?
assert_rc "비인터랙티브 3회째도 거부" 1 "$rc3"
rm stuck.txt

summary
