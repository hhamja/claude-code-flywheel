#!/bin/bash
# test-seed.sh — seed.sh 멱등성·engine/seed 분리 검사
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/proj"
cd "$TMP/proj"
git -c init.defaultBranch=main init -q
git config user.email "test@flywheel.local"
git config user.name "flywheel-test"

echo "[1회차 — 생성]"
out="$("$REPO_ROOT/scripts/seed.sh")"
assert_contains "GOAL 생성" "CREATED: .flywheel/GOAL.md" "$out"
assert_contains "엔진 갱신" "UPDATED: .flywheel/bin/gate.sh" "$out"
for d in backlog/todo backlog/doing backlog/done backlog/blocked journal/archive bin local; do
  if [[ -d ".flywheel/$d" ]]; then ok "디렉터리 $d"; else fail "디렉터리 $d"; fi
done
assert_file "policies.env" ".flywheel/policies.env"
if [[ -x ".flywheel/bin/gate.sh" ]]; then ok "gate.sh 실행권한"; else fail "gate.sh 실행권한"; fi
assert_contains ".gitignore 등록" ".flywheel/local/" "$(cat .gitignore)"

echo "[2회차 — 멱등성]"
echo "# 사용자 편집" >> .flywheel/GOAL.md
echo "훼손" > .flywheel/bin/gate.sh
out="$("$REPO_ROOT/scripts/seed.sh")"
assert_contains "GOAL 보존(KEPT)" "KEPT: .flywheel/GOAL.md" "$out"
assert_contains "사용자 편집 유지" "# 사용자 편집" "$(cat .flywheel/GOAL.md)"
if diff -q "$REPO_ROOT/scripts/gate.sh" .flywheel/bin/gate.sh > /dev/null; then
  ok "훼손된 engine 복구(덮어쓰기)"
else
  fail "훼손된 engine 복구(덮어쓰기)"
fi

echo "[3회차 — .gitignore 중복 방지]"
"$REPO_ROOT/scripts/seed.sh" > /dev/null
n="$(grep -cxF '.flywheel/local/' .gitignore)"
assert_rc ".gitignore 항목 1개 유지" 1 "$n"

summary
