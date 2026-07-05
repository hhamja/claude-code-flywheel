# 티켓 예시 — 좋은 것과 나쁜 것

## 좋은 예 1 — Verify 가 결정적

```markdown
# 010-healthcheck-endpoint

## Goal
GET /health 가 200 과 {"status":"ok"} 를 반환한다.

## Acceptance
- [ ] GET /health 응답 코드 200
- [ ] 응답 본문에 "ok" 포함
- [ ] 기존 테스트 전부 통과

## Verify
​```sh
npm test -- --run health
​```
```

## 좋은 예 2 — 작게 쪼갠 스키마 작업

```markdown
# 020-user-table-migration

## Goal
users 테이블 마이그레이션 파일이 존재하고 up/down 이 왕복 가능하다.

## Verify
​```sh
npm run migrate:up && npm run migrate:down && npm run migrate:up
​```
```

## 나쁜 예 1 — 너무 크고 검증 불가

```markdown
# 001-build-mvp
## Goal
MVP 전체를 만든다        ← 사이클 하나로 불가능. 기능 단위로 쪼개라.
## Verify
(없음)                   ← Verify 없는 티켓은 완료 판정 자체가 불가능.
```

## 나쁜 예 2 — 사람 판단이 필요한 일

```markdown
# 002-choose-pricing
## Goal
요금제를 결정한다         ← 셸로 검증 불가 + 제품 방향 결정. 티켓이 아니라
                           사람에게 보고할 일이다.
```
