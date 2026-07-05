---
name: loop-protocol
description: flywheel 루프 사이클 실행 프로토콜. flywheel 루프 사이클을 수행하거나 .flywheel/ 백로그의 티켓을 처리할 때 사용.
---

# flywheel 1사이클 프로토콜

메인 스레드는 얇은 오케스트레이터다 — 구현·검증은 서브에이전트에게, 전달은 **포인터(경로)만**.

1. **CLAIM** — `.flywheel/backlog/doing/` 에 티켓이 있으면 그것을 재개(크래시 복구).
   없으면 `todo/` 에서 번호가 가장 낮은 티켓을 `doing/` 으로 `mv`.
   지금 `git rev-parse HEAD` 를 기록해 둔다 (사이클 시작 해시).
2. **BUILD** — builder 서브에이전트에 **티켓 경로만** 전달한다. 내용 재서술 금지.
3. **AUDIT** — auditor 서브에이전트에 티켓 경로 + 시작 해시를 전달한다.
4. **RECORD**
   - VERDICT: PASS → 티켓을 `done/` 으로 mv → `.flywheel/journal/YYYY-MM-DD.md` 에
     1-3줄 append → `.flywheel/STATE.md` 의 Now/Next 갱신(30줄 이내 유지) → 전부 커밋.
   - VERDICT: FAIL → auditor 의 `fix_hints:` 를 티켓 `## Attempts` 에 append → 2로
     돌아가 재시도. 같은 사이클에서 최대 2회까지만.
5. **CHECK** — `.flywheel/bin/gate.sh cycle` 을 실행한다. 실패 메시지가 곧 남은 할 일이다.

종료 신호 (약속은 진실일 때만 — 게이트가 재검증하고, 거짓이면 반증되어 루프가 계속된다):
- 막혔으면: `references/escalation.md` 를 읽고 `.flywheel/BLOCKED.md` 작성 후
  `<promise>FLYWHEEL_BLOCKED</promise>` 출력.
- 백로그가 비었고 GOAL.md Acceptance 가 전부 충족이면: `<promise>FLYWHEEL_COMPLETE</promise>` 출력.

제약:
- `GOAL.md`·`policies.env` 수정 금지 (사람 게이트 — 게이트가 거부한다).
- 티켓 형식이 필요하면 `references/ticket-format.md` 를 그때 읽어라.
