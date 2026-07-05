#!/bin/bash
# seed.sh — flywheel 씨앗 심기 (결정적·멱등)
#
# engine 층(.flywheel/bin/)은 항상 덮어쓰고, seed 층(템플릿)은 없을 때만 복사한다.
# 재실행 = engine 업데이트. 사용자 편집은 절대 건드리지 않는다.
#
# 출력: CREATED:/KEPT:/UPDATED: 목록 (LLM 이 결과를 읽고 다음 단계를 안내)

set -euo pipefail

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
FW="$PROJECT_ROOT/.flywheel"

mkdir -p "$FW/backlog/todo" "$FW/backlog/doing" "$FW/backlog/done" "$FW/backlog/blocked" \
         "$FW/journal/archive" "$FW/bin" "$FW/local"

# seed 층: 없을 때만 복사 (프로젝트 소유)
for t in GOAL.md STATE.md LEARNINGS.md policies.env; do
  if [[ -f "$FW/$t" ]]; then
    echo "KEPT: .flywheel/$t"
  else
    cp "$PLUGIN_ROOT/templates/$t" "$FW/$t"
    echo "CREATED: .flywheel/$t"
  fi
done

# engine 층: 항상 덮어씀 (플러그인 소유)
for e in run.sh gate.sh; do
  cp "$PLUGIN_ROOT/scripts/$e" "$FW/bin/$e"
  chmod +x "$FW/bin/$e"
  echo "UPDATED: .flywheel/bin/$e"
done

# .gitignore 에 local/ 과 루프 상태 파일 등록 (중복 방지)
GI="$PROJECT_ROOT/.gitignore"
for ig in '.flywheel/local/' '.claude/flywheel.local.md'; do
  if ! grep -qxF "$ig" "$GI" 2>/dev/null; then
    echo "$ig" >> "$GI"
    echo "UPDATED: .gitignore (+$ig)"
  fi
done

if ! git -C "$PROJECT_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  echo "WARN: git 저장소가 아닙니다 — flywheel 은 git 이 필요합니다. git init 후 다시 실행하세요."
fi

echo "SEEDED: $FW"
