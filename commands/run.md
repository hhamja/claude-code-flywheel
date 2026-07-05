---
description: "flywheel 무인 백그라운드 루프 시작 (기본 워커: claude -p)"
argument-hint: "[--max-cycles N] [--worker CMD] [--worktree] [--once]"
allowed-tools: ["Bash"]
---

무인 루프를 시작하라:

1. `.flywheel/bin/run.sh` 가 없으면 `/flywheel:init` 을 먼저 하라고 안내하고 멈춰라.
2. `.flywheel/local/run.pid` 의 프로세스가 살아 있으면 이미 실행 중이다 — 중복 실행하지 말고
   `/flywheel:status` 를 안내하라.
3. 실행 (Bash 의 run_in_background 사용):
   ```
   .flywheel/bin/run.sh $ARGUMENTS
   ```
4. 사용자에게 안내하라:
   - 로그 확인: `tail -f .flywheel/local/trace/<runid>/run.log`
   - 상태 확인: `/flywheel:status`
   - 정지: `/flywheel:stop`
   - 종료 코드: 0=완료(게이트 통과) · 2=예산 상한 · 3=BLOCKED(사람 개입) · 4=완료 주장 반증
