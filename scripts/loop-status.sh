#!/bin/bash
# loop-status.sh — flywheel 상태 요약 (토큰 0 — LLM 은 이 출력을 릴레이만 한다)
set -uo pipefail

PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$PROJECT_ROOT"
FW=".flywheel"
STATE=".claude/flywheel.local.md"

[[ -d "$FW" ]] || { echo "flywheel 미설치 — /flywheel:init 을 먼저 실행하세요."; exit 0; }

count_md() { find "$1" -name '*.md' -type f 2>/dev/null | wc -l | tr -d ' '; }

echo "── flywheel 상태 ($(basename "$PROJECT_ROOT")) ──"

# 인터랙티브 루프
if [[ -f "$STATE" ]]; then
  c="$(grep '^cycle:' "$STATE" | head -1 | sed 's/cycle: *//')"
  m="$(grep '^max_cycles:' "$STATE" | head -1 | sed 's/max_cycles: *//')"
  echo "인터랙티브 루프: 활성 (cycle $c/$m)"
else
  echo "인터랙티브 루프: 비활성"
fi

# 무인 루프
if [[ -f "$FW/local/run.pid" ]]; then
  pid="$(cat "$FW/local/run.pid")"
  if [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then
    echo "무인 루프: 실행 중 (pid $pid)"
  else
    echo "무인 루프: 중단됨 (stale pid $pid)"
  fi
else
  echo "무인 루프: 비활성"
fi

# 백로그
echo "백로그: todo $(count_md "$FW/backlog/todo") · doing $(count_md "$FW/backlog/doing") · done $(count_md "$FW/backlog/done") · blocked $(count_md "$FW/backlog/blocked")"

# 에스컬레이션
if [[ -f "$FW/BLOCKED.md" ]]; then
  echo ""
  echo "⚠️ BLOCKED — 사람 개입 필요:"
  head -8 "$FW/BLOCKED.md" | sed 's/^/  /'
fi

# 최근 journal
latest_journal="$(ls -t "$FW/journal"/*.md 2>/dev/null | head -1 || true)"
if [[ -n "$latest_journal" ]]; then
  echo ""
  echo "최근 journal ($(basename "$latest_journal")):"
  tail -3 "$latest_journal" | sed 's/^/  /'
fi

# 최근 trace
latest_trace="$(ls -t "$FW"/local/trace/*/run.jsonl 2>/dev/null | head -1 || true)"
if [[ -n "$latest_trace" ]]; then
  echo ""
  echo "최근 무인 run ($(basename "$(dirname "$latest_trace")")):"
  tail -3 "$latest_trace" | sed 's/^/  /'
fi
