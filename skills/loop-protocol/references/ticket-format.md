# 티켓 형식

파일명: `NNN-slug.md` — NNN 은 3자리 실행 순서 (001, 002, …). 낮은 번호부터 처리된다.
위치: `.flywheel/backlog/{todo,doing,done,blocked}/` — 디렉터리 간 `mv` 가 곧 상태 전이.

```markdown
# NNN-slug

## Goal
<이 티켓이 끝나면 참이 되는 것 — 1~3줄>

## Acceptance
- [ ] <검증 가능한 기준 1>
- [ ] <검증 가능한 기준 2>

## Verify
​```sh
<이 블록의 명령이 전부 exit 0 이면 통과 — gate.sh ticket 이 그대로 실행한다>
​```

## Attempts
<append-only 실패 기록. 형식: "#### attempt N — 날짜" + 원인/증거. 삭제 금지.>
```

규칙:
- **티켓 1개 = 워커 1회 호출로 끝나는 분량.** 크면 쪼개라.
- Verify 명령은 프로젝트 루트 기준, 비대화형으로 실행 가능해야 한다.
- 체크박스 `- [ ]` → `- [x]` 토글은 허용. **항목 삭제·문구 변경은 게이밍으로 거부된다.**
