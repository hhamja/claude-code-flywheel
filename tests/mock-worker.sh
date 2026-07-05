#!/bin/bash
# mock-worker.sh — run.sh 테스트용 가짜 워커
# stdin 으로 프롬프트를 받고 MOCK_MODE 에 따라 행동한다:
#   success  티켓의 Verify(test -f X)가 요구하는 파일을 만들고 journal 갱신 후 커밋
#   fail     아무것도 하지 않음 (verify 실패 유도)
#   timeout  TIMEOUT_S 를 넘겨 잠듦
set -uo pipefail

PROMPT="$(cat)"
MODE="${MOCK_MODE:-success}"

case "$MODE" in
  timeout)
    sleep 30
    exit 0
    ;;
  fail)
    echo "mock: 의도적으로 아무것도 하지 않음"
    exit 0
    ;;
  success)
    ticket="$(echo "$PROMPT" | grep -oE '\.flywheel/backlog/doing/[^[:space:]]+\.md' | head -1)"
    [[ -f "$ticket" ]] || { echo "mock: 티켓을 찾지 못함: '$ticket'"; exit 1; }
    # Verify 블록의 'test -f X' 가 요구하는 파일 생성
    files="$(awk '/^## Verify/{f=1;next} /^## /{f=0} f' "$ticket" | awk '/^```/{c=!c;next} c' \
      | grep -oE 'test -f [^[:space:]]+' | awk '{print $3}')"
    for f in $files; do
      echo "mock output" > "$f"
    done
    echo "- $(date '+%T') mock: $(basename "$ticket") 처리" >> ".flywheel/journal/$(date '+%F').md"
    git add -A >/dev/null 2>&1
    git commit -qm "loop: mock 작업 ($(basename "$ticket"))" >/dev/null 2>&1 || true
    echo "mock: $ticket 완료"
    ;;
  *)
    echo "mock: 알 수 없는 MOCK_MODE=$MODE"; exit 1 ;;
esac
