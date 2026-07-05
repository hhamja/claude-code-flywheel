# flywheel

**루프 엔지니어링 하니스** — "에이전트를 프롬프트하는 사람"을 "에이전트를 프롬프트하는 시스템"으로.

Addy Osmani 의 [Loop Engineering](https://addyo.substack.com/p/loop-engineering) 6기둥
(Automations · Worktrees · Skills · Connectors · Sub-agents · Memory)을 어떤 프로젝트에든
한 줄 설치로 심을 수 있는 Claude Code 플러그인으로 구현했다.

## 설치

```sh
claude plugin marketplace add hhamja/flywheel   # private repo — GitHub 인증 필요
claude plugin install flywheel@flywheel
```

## 60초 퀵스타트 (신규 MVP)

```
cd my-mvp && git init && claude
> /flywheel:init "할일 공유 SaaS MVP"        # 씨앗 + GOAL 초안 + 첫 티켓 2~5개
> (GOAL.md·policies.env 검토) → git add .flywheel .gitignore && git commit -m "approve"
                                              # ← 사람 게이트: 커밋 = 승인
> /flywheel:go --max-cycles 10                # 인터랙티브 루프 (지켜보며 개입 가능)
```

밤에는 무인으로:

```
> /flywheel:stop
$ .flywheel/bin/run.sh --max-cycles 20        # 기본 워커: claude -p
```

아침에:

```
> /flywheel:status                            # BLOCKED 확인 → 해결 → 파일 삭제 → 재개
> /flywheel:triage                            # 신호 수집 → 새 티켓
```

## 핵심 설계

1. **판단은 LLM, 강제는 셸.** 정지·검증·상태 전이는 전부 결정적 스크립트(토큰 0).
   LLM 의 "완료"는 주장일 뿐 — `gate.sh done` 이 반증하면 루프는 계속된다.
2. **engine vs seed.** `.flywheel/bin/`(run.sh, gate.sh)만 플러그인이 소유하고 init 이 항상
   덮어쓴다. 나머지는 1회 복사 후 프로젝트 소유. 인터랙티브 Stop hook 과 무인 run.sh 가
   **같은 프로젝트 사본 gate.sh** 를 호출해 두 모드의 계약이 절대 어긋나지 않는다.
3. **컨텍스트에는 포인터만.** 재주입 프롬프트 ~80토큰. 상태는 전부 디스크(`.flywheel/`).

## 커맨드

| 커맨드 | 역할 |
|---|---|
| `/flywheel:init [골]` | 씨앗 심기 (멱등 — 재실행 시 engine 만 갱신) + GOAL/티켓 초안 |
| `/flywheel:go` | 인터랙티브 루프 (Stop hook 이 사이클 재주입) |
| `/flywheel:run` | 무인 백그라운드 루프 (`--worktree` 로 병렬 격리) |
| `/flywheel:status` | 루프·백로그·BLOCKED·최근 기록 요약 |
| `/flywheel:stop` | 루프 해제 + 무인 프로세스 종료 + doing 반납 |
| `/flywheel:triage` | 신호 수집(테스트 실패·TODO·이슈) → 티켓 제안 (`--auto` 무확인) |
| `/flywheel:distill` | journal → LEARNINGS.md 교훈 증류 (60줄 상한) |

## 6기둥 매핑

| 기둥 | flywheel 구현 |
|---|---|
| Automations | `/flywheel:triage` + cron 레시피(아래) + run.sh 의 exit code 규약 |
| Worktrees | `run.sh --worktree` — run 별 브랜치 `loop/<runid>`, 머지는 사람 몫 |
| Skills | loop-protocol · backlog-authoring (본문 최소, 상세는 references/ 온디맨드) |
| Connectors | 워커가 `gh` CLI 로 이슈/PR 연동 (MCP 미사용 — 상시 토큰 0) |
| Sub-agents | scout(haiku·읽기전용) / builder(inherit) / auditor(opus·읽기전용) |
| Memory | `.flywheel/` 디스크 상태 — STATE(≤30줄)·journal(append)·LEARNINGS(60줄 증류) |

## 무인 모드 상세

```sh
.flywheel/bin/run.sh [--max-cycles N] [--once] [--dry-run] [--worktree] [--worker CMD]
```

- **워커 교체**: `FLYWHEEL_WORKER='codex exec --skip-git-repo-check -' .flywheel/bin/run.sh`
  (우선순위: `--worker` > `FLYWHEEL_WORKER` > policies.env `WORKER_CMD` > `claude -p`)
- **종료 코드**: `0` 완료(게이트 통과) · `2` 예산 상한 · `3` BLOCKED(사람 개입) · `4` 완료 주장 반증
- **LLM 감사 추가**: policies.env 에서 `AUDIT=llm` — 티켓마다 독립 감사 워커(기본 opus)가 2차 채점
- **트레이스**: `.flywheel/local/trace/<runid>/run.jsonl` (사이클당 1줄) + 워커 원본 로그

### cron 야간 루프 레시피

```cron
0 22 * * *  cd ~/proj && .flywheel/bin/run.sh --max-cycles 20 >> /tmp/fw.log 2>&1
0 7  * * 1-5  cd ~/proj && echo "/flywheel:triage --auto" | claude -p --dangerously-skip-permissions
```

### 병렬 worktree 레시피

```sh
.flywheel/bin/run.sh --worktree --max-cycles 10 &   # run 1 — loop/r... 브랜치
.flywheel/bin/run.sh --worktree --max-cycles 10 &   # run 2 — 파일 충돌 없음
# 완료 후: 브랜치 리뷰 → PR/머지는 사람이
```

## 씨앗 구조 (`.flywheel/`)

```
GOAL.md           목적함수 — 사람 게이트 (루프 수정 금지, 게이트가 강제)
policies.env      한계값·정책 — 사람 게이트
STATE.md          작업기억 (≤30줄, Now/Next/Risks)
LEARNINGS.md      증류된 교훈 (60줄 상한)
backlog/          todo/ doing/ done/ blocked/ — mv 가 곧 상태 전이
journal/          append-only 사이클 일지 → 증류 후 archive/
bin/              run.sh · gate.sh (engine — init 이 덮어씀, 수정 금지)
local/            gitignored — trace/ · run.pid · 게이트 베이스라인
BLOCKED.md        (평시 없음) 존재 = 루프 정지 + 사람 에스컬레이션
```

## 계약 (gate.sh 가 기계 강제)

- **C1** 파일을 바꿨으면 journal/STATE 도 갱신해야 턴 종료 가능
- **C2** 미커밋 잔류 금지 — 완료는 커밋으로만
- **C3** GOAL.md·policies.env 는 루프가 못 바꿈 (reward hacking 방지 — 목적함수는 사람 커밋으로만)
- **C4** 게이밍 감지 — 테스트 삭제/skip 추가/티켓 Acceptance 변조 → 거부
- **done** 완료 주장 = todo·doing 소진 ∧ clean ∧ VERIFY_CMD 통과 — 거짓 약속은 반증되어 루프 지속

## 루프가 대신하지 못하는 것

- **검증 책임** — auditor 의 PASS 도 주장이다. 머지 전 코드는 사람이 읽어라.
- **이해 부채** — 루프가 빠를수록 안 읽은 코드가 쌓인다. 사람 리뷰 지점 4곳이 구조에 내장되어
  있다: ① GOAL/policies 커밋 승인 ② BLOCKED.md 해소 ③ worktree 브랜치 머지 ④ LEARNINGS 리뷰.
- 같은 프로젝트 체크아웃에서 인터랙티브 루프와 무인 루프를 **동시에** 돌리지 마라
  (세션 격리는 되지만 커밋이 섞인다 — 병렬은 `--worktree` 로).

## 개발

```sh
bash tests/run-all.sh    # 순수 bash 테스트 108개 (의존성: git, jq)
```
