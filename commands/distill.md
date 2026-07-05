---
description: "journal → LEARNINGS.md 교훈 증류 (60줄 상한, 처리분은 archive 로)"
---

메모리 증류를 수행하라:

1. `.flywheel/local/last-distill` 마커가 있으면 그 이후, 없으면 처음부터
   `.flywheel/journal/*.md` (archive/ 제외) 의 항목을 읽어라.
2. 각 항목을 **"실패 → 원인 → 검증 → 일반화"** 기준으로 걸러라 — 재발 조건이 있는
   일반화 가능한 교훈만 남긴다. 일회성 사실은 버려라.
3. 통과분을 `.flywheel/LEARNINGS.md` 에 병합하라 — 형식 `- [영역] 규칙 한 줄 (근거: 날짜)`,
   중복 제거, **60줄 상한** — 초과 시 오래되고 덜 일반적인 항목부터 퇴출.
4. 처리한 journal 파일을 `.flywheel/journal/archive/` 로 mv 하라.
5. `date +%s > .flywheel/local/last-distill` 로 마커를 갱신하고 전부 커밋하라.
