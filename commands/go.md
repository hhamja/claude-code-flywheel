---
description: "flywheel 인터랙티브 루프 시작 — 턴 종료마다 Stop hook 이 다음 사이클을 재주입"
argument-hint: "[--max-cycles N (기본 25)] [--max-hours H (기본 4)]"
allowed-tools: ["Bash(${CLAUDE_PLUGIN_ROOT}/scripts/arm.sh:*)"]
hide-from-slash-command-tool: "true"
---

```!
"${CLAUDE_PLUGIN_ROOT}/scripts/arm.sh" $ARGUMENTS
```

위 출력이 ERROR 면 지시대로 해결을 안내하고 멈춰라.

ARMED 라면 지금부터 루프다. loop-protocol 스킬대로 사이클 1을 시작하라. 턴을 끝낼 때마다
Stop hook 이 계약을 검사하고 다음 사이클을 재주입한다.

CRITICAL RULE: `<promise>FLYWHEEL_COMPLETE</promise>` 와 `<promise>FLYWHEEL_BLOCKED</promise>` 는
그 내용이 완전히 진실일 때만 출력하라. 루프를 빠져나가려고 거짓 약속을 하지 마라 —
게이트가 재검증하며, 반증되면 루프는 계속된다.
