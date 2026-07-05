#!/bin/bash
# run-all.sh — 전체 테스트 실행
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

total_fail=0
for t in test-*.sh; do
  echo "═══ $t ═══"
  if bash "$t"; then :; else total_fail=$((total_fail+1)); fi
  echo
done

if (( total_fail > 0 )); then
  echo "✗ 실패한 테스트 파일: $total_fail"
  exit 1
fi
echo "✓ 전체 테스트 통과"
