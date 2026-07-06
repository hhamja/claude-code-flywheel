# flywheel — a Loop Engineering harness for Claude Code

> Turn *"a human prompting the agent"* into *"a system that prompts the agent."*

[![version](https://img.shields.io/badge/version-0.1.2-blue.svg)](https://github.com/hhamja/claude-code-flywheel/releases)
[![license](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![tests](https://img.shields.io/badge/tests-113%20passing-brightgreen.svg)](tests/)
[![Claude Code](https://img.shields.io/badge/Claude%20Code-plugin-8A2BE2.svg)](https://docs.claude.com/en/docs/claude-code)

**flywheel** is a [Claude Code](https://docs.claude.com/en/docs/claude-code) plugin that plants a **self-correcting agent loop** into any project with a single `/flywheel:init`. It implements the six pillars of Addy Osmani's [Loop Engineering](https://addyo.substack.com/p/loop-engineering) — Automations · Worktrees · Skills · Connectors · Sub-agents · Memory — as a hybrid of an **interactive loop** (a `Stop` hook that re-injects the next cycle) and an **unattended loop** (a background `run.sh` state machine).

The core idea: **the LLM decides, the shell enforces.** Stopping, verification, and state transitions are all deterministic scripts (zero tokens). A model's claim of "done" is just a claim — `gate.sh done` tries to disprove it, and if it can, the loop keeps going.

---

## Install

```sh
claude plugin marketplace add hhamja/claude-code-flywheel
claude plugin install flywheel@flywheel
```

Requirements: `git`, `jq`, and the Claude Code CLI. Works on macOS and Linux.

## 60-second quickstart (new MVP)

```
cd my-mvp && git init && claude
> /flywheel:init "todo-sharing SaaS MVP"     # seed + GOAL draft + first 2–5 tickets
> (review GOAL.md · policies.env) → git add .flywheel .gitignore && git commit -m "approve"
                                              # ← human gate: commit = approval
> /flywheel:go --max-cycles 10                # interactive loop (watch & intervene)
```

Run it unattended overnight:

```
> /flywheel:stop
$ .flywheel/bin/run.sh --max-cycles 20        # default worker: claude -p
```

In the morning:

```
> /flywheel:status                            # check BLOCKED → resolve → delete file → resume
> /flywheel:triage                            # collect signals → new tickets
```

## Core design

1. **The LLM judges, the shell enforces.** Stopping, verification, and state transitions are all deterministic scripts (zero tokens). The model's "done" is a claim — if `gate.sh done` disproves it, the loop continues.
2. **engine vs. seed.** Only `.flywheel/bin/` (`run.sh`, `gate.sh`) is owned by the plugin and always overwritten by `init`. Everything else is copied once and then owned by your project. Both the interactive `Stop` hook and the unattended `run.sh` call the **same project-local `gate.sh`**, so the two modes can never drift apart on what "valid" means.
3. **Only pointers in context.** The re-injected prompt is ~80 tokens. All state lives on disk in `.flywheel/`.

## Commands

| Command | Role |
|---|---|
| `/flywheel:init [goal]` | Plant the seed (idempotent — re-runs only refresh the engine) + draft GOAL/tickets |
| `/flywheel:go` | Interactive loop (the `Stop` hook re-injects each cycle) |
| `/flywheel:run` | Unattended background loop (`--worktree` for parallel isolation) |
| `/flywheel:status` | Summary of loop · backlog · BLOCKED · recent activity |
| `/flywheel:stop` | Disarm the loop + kill the unattended process + return `doing` tickets |
| `/flywheel:triage` | Collect signals (failing tests · TODOs · issues) → propose tickets (`--auto` skips confirmation) |
| `/flywheel:distill` | Distill `journal` → `LEARNINGS.md` (capped at 60 lines) |

## The six pillars, mapped

| Pillar | flywheel implementation |
|---|---|
| Automations | `/flywheel:triage` + cron recipes (below) + `run.sh` exit-code contract |
| Worktrees | `run.sh --worktree` — a per-run branch `loop/<runid>`; merging is the human's job |
| Skills | `loop-protocol` · `backlog-authoring` (minimal body, details in `references/` on demand) |
| Connectors | The worker integrates issues/PRs via the `gh` CLI (no MCP — zero standing tokens) |
| Sub-agents | scout (haiku · read-only) / builder (inherit) / auditor (opus · read-only) |
| Memory | On-disk state in `.flywheel/` — STATE (≤30 lines) · journal (append) · LEARNINGS (60-line distill) |

## Unattended mode

```sh
.flywheel/bin/run.sh [--max-cycles N] [--once] [--dry-run] [--worktree] [--worker CMD]
```

- **Swap the worker**: `FLYWHEEL_WORKER='codex exec --skip-git-repo-check -' .flywheel/bin/run.sh`
  (precedence: `--worker` > `FLYWHEEL_WORKER` > `policies.env WORKER_CMD` > `claude -p`)
- **Exit codes**: `0` done (gate passed) · `2` budget cap · `3` BLOCKED (needs a human) · `4` completion claim disproven
- **Add an LLM audit**: set `AUDIT=llm` in `policies.env` — an independent auditor (opus by default) second-grades every ticket
- **Traces**: `.flywheel/local/trace/<runid>/run.jsonl` (one line per cycle) + raw worker logs

### Nightly cron recipe

```cron
0 22 * * *    cd ~/proj && .flywheel/bin/run.sh --max-cycles 20 >> /tmp/fw.log 2>&1
0 7  * * 1-5  cd ~/proj && echo "/flywheel:triage --auto" | claude -p --dangerously-skip-permissions
```

### Parallel worktree recipe

```sh
.flywheel/bin/run.sh --worktree --max-cycles 10 &   # run 1 — branch loop/r...
.flywheel/bin/run.sh --worktree --max-cycles 10 &   # run 2 — no file conflicts
# then: review branches → the human opens the PR / merges
```

## Seed layout (`.flywheel/`)

```
GOAL.md           objective function — human gate (loop can't touch it; the gate enforces this)
policies.env      limits & policy — human gate
STATE.md          working memory (≤30 lines: Now/Next/Risks)
LEARNINGS.md      distilled lessons (capped at 60 lines)
backlog/          todo/ doing/ done/ blocked/ — an mv IS the state transition
journal/          append-only cycle log → archived after distillation
bin/              run.sh · gate.sh (engine — overwritten by init, do not edit)
local/            gitignored — trace/ · run.pid · gate baseline
BLOCKED.md        (absent in normal operation) present = loop halts + human escalation
```

## Contracts (machine-enforced by `gate.sh`)

- **C1** If you changed files, you must also update `journal`/`STATE` before the turn can end
- **C2** No uncommitted leftovers — done means committed
- **C3** `GOAL.md` and `policies.env` can't be changed by the loop (anti reward-hacking — the objective function changes only through a human commit)
- **C4** Gaming detection — deleting tests / adding skip markers / tampering with ticket Acceptance → rejected
- **done** A completion claim requires `todo`/`doing` empty ∧ clean tree ∧ `VERIFY_CMD` passing — false promises are disproven and the loop continues

## Security

flywheel is, by design, an **autonomous code-execution harness**: the default worker runs `claude -p --dangerously-skip-permissions`, and ticket `## Verify` blocks and `VERIFY_CMD` are executed as shell. Treat any repository you point it at as something you trust to run.

Hardening that is in place:

- **`policies.env` is never `source`d.** It is parsed with a string-only whitelist reader (`read_policy`) that never evaluates `$(...)`, backticks, or `${...}`. Cloning an untrusted repo and starting a loop cannot execute arbitrary code hidden in that file. (`VERIFY_CMD`/`WORKER_CMD` values still run at their intended execution point — that is their purpose.)
- **Numeric/enum policy values are format-validated** and fall back to safe defaults if corrupted.
- **The `Stop` hook validates the session id** before using it, and exits immediately (zero cost) when no loop is armed, so it coexists safely with other plugins.
- **Session isolation**: a loop armed in one session is never touched by another.

Human review is built into the structure at four points: ① approving the GOAL/policies commit, ② resolving `BLOCKED.md`, ③ merging worktree branches, ④ reviewing `LEARNINGS`. The auditor's `PASS` is also a claim — read the code before you merge.

## What the loop can't do for you

- **Verification ownership** — the auditor's `PASS` is a claim too. A human reads the code before merging.
- **Comprehension debt** — the faster the loop runs, the more unread code piles up. That's why the four human review points above are structural, not optional.
- Don't run the interactive loop and the unattended loop on the **same checkout** at once (sessions are isolated, but commits interleave — use `--worktree` for parallelism).

## Development

```sh
bash tests/run-all.sh    # 113 pure-bash tests (deps: git, jq)
```

## License

[MIT](LICENSE) © hhamja
