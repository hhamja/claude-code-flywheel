---
description: "신호 수집(테스트 실패·TODO·이슈·blocked) → flywheel 티켓 제안"
argument-hint: "[--auto (확인 없이 티켓 작성·커밋)]"
---

triage 를 수행하라 — 루프의 자동 작업 발견 단계다.

1. **scout 서브에이전트**에 다음 정찰을 위임하라 (수정 금지, ≤30줄, 포인터 필수):
   - `.flywheel/policies.env` 의 VERIFY_CMD 실행 결과 (실패하는 테스트)
   - `git log --oneline -20` 에서 후속 작업 흔적 (WIP, revert, fixme)
   - 소스의 TODO/FIXME 상위 10건 (경로:줄)
   - `gh` CLI 사용 가능하면 `gh issue list --limit 10`
   - `.flywheel/backlog/blocked/` 의 잔류 티켓

2. 보고를 받으면 backlog-authoring 스킬 기준으로 **티켓 초안 최대 5개**를 만들어라.
   우선순위: 빌드/테스트를 깨는 것 최우선.

3. 처리 분기:
   - "$ARGUMENTS" 에 `--auto` 가 있으면: 티켓을 `.flywheel/backlog/todo/` 에 바로 작성하고 커밋하라.
   - 없으면: 초안을 사용자에게 보여주고, 승인받은 것만 작성하라.

4. **티켓화 금지 대상** — 보안 취약점, 인프라/배포 변경, 제품 방향 결정은 티켓으로 만들지 말고
   사람에게 보고만 하라.
