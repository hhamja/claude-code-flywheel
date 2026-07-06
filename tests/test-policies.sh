#!/bin/bash
# test-policies.sh — policies.env 안전 파싱 검사 (source RCE 회귀 방지)
#
# 신뢰할 수 없는 저장소를 클론해 루프를 돌려도 policies.env 안의 임의 코드가
# 실행되면 안 된다. gate.sh 는 값만 문자열로 추출하고 실행하지 않아야 한다.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
make_fixture "$TMP/proj"
GATE=".flywheel/bin/gate.sh"
CANARY="$TMP/PWNED"

echo "[악성 policies.env — 코드 실행 차단]"

# 공격자가 커밋해 둔 policies.env: source 되면 canary 파일이 생긴다
cat > .flywheel/policies.env <<EOF
MAX_CYCLES=25          # 정상 주석
VERIFY_CMD="true"
AUTO_COMMIT=true
DISTILL_EVERY=5
EVIL=\$(touch "$CANARY")
\$(touch "$CANARY")
\`touch "$CANARY"\`
EOF
git add -A && git commit -qm "attacker: 악성 policies.env"

out="$("$GATE" done 2>&1)"; rc=$?
assert_no_file "source RCE 차단 — canary 미생성" "$CANARY"
assert_rc "정상 VERIFY_CMD(true) done 통과" 0 "$rc"

echo "[VERIFY_CMD 값 정확 추출]"

# 주석·따옴표가 붙어도 값만 정확히 읽어 실패를 반영해야 한다
sed 's/^VERIFY_CMD=.*/VERIFY_CMD="false"   # 실패 유도/' .flywheel/policies.env > t.env && mv t.env .flywheel/policies.env
git add -A && git commit -qm "config: VERIFY_CMD=false"
out="$("$GATE" done 2>&1)"; rc=$?
assert_rc "VERIFY_CMD(false) done 실패" 1 "$rc"
assert_contains "전역 검증 실패 메시지" "전역 검증 실패" "$out"
assert_no_file "재실행에도 canary 미생성" "$CANARY"

summary
