---
description: "flywheel 루프 정지 (인터랙티브 해제 + 무인 프로세스 종료 + doing 반납)"
allowed-tools: ["Bash(${CLAUDE_PLUGIN_ROOT}/scripts/arm.sh:*)"]
---

```!
"${CLAUDE_PLUGIN_ROOT}/scripts/arm.sh" --disarm
```

위 출력을 사용자에게 전달하라. 진행 상태는 `.flywheel/` 에 보존되어 있고
`/flywheel:go` 또는 `/flywheel:run` 으로 언제든 재개할 수 있다고 안내하라.
