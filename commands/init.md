---
description: "프로젝트에 flywheel 루프 씨앗 심기 (멱등 — 재실행 시 engine 만 갱신)"
argument-hint: "[한 줄 골 설명 (선택)]"
allowed-tools: ["Bash(${CLAUDE_PLUGIN_ROOT}/scripts/seed.sh:*)", "Read", "Write", "Edit", "Glob", "Grep"]
---

씨앗을 심는다:

```!
"${CLAUDE_PLUGIN_ROOT}/scripts/seed.sh"
```

위 출력의 CREATED / KEPT / UPDATED 를 확인하라. 이어서:

1. `.flywheel/GOAL.md` 가 방금 생성(CREATED)됐다면: 인자("$ARGUMENTS")와 프로젝트 단서
   (README, 패키지 매니페스트, 기존 코드)로 GOAL.md 초안을 작성하라 — 북극성 1-3줄,
   검증 명령이 달린 Acceptance, 범위 밖 목록. 인자도 단서도 없으면 사용자에게 골을 물어라.
   KEPT 라면 건드리지 마라.
2. `.flywheel/policies.env` 의 `VERIFY_CMD` 를 이 프로젝트의 실제 테스트 명령으로
   제안하라 (직접 수정하지 말고 사용자에게 제안만 — 사람 게이트 파일이다).
3. backlog-authoring 스킬을 따라 첫 티켓 2~5개를 `.flywheel/backlog/todo/` 에 작성하라.
4. 마지막으로 안내하라: "**사람 게이트**: `.flywheel/GOAL.md` 와 `policies.env` 를 검토·수정한 뒤
   직접 커밋하세요 (커밋 = 승인). 그다음 `/flywheel:go` (인터랙티브) 또는 `/flywheel:run` (무인)으로
   루프를 시작합니다."
