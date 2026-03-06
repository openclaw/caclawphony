# Caclawphony

Caclawphony is an automated PR triage, review, and merge pipeline for [openclaw/openclaw](https://github.com/openclaw/openclaw). It connects a Linear project board to coding agents (Codex) via [Symphony](https://github.com/openai/symphony), turning each PR into a tracked issue that flows through a multi-stage pipeline with human gates between stages.

[📺 Demo video](https://drive.google.com/file/d/1QsTwj9oLY9FlceI3TT_AEVBXFvy31dtd/view)

> [!WARNING]
> This is a maintainer tool for openclaw/openclaw — not a general-purpose framework.

## How It Works

PRs are imported into Linear via `mix caclawphony.review <PR#>`, which creates an issue in the **Triage** state. Symphony polls Linear for issues in active states and dispatches Codex agents to handle each stage. Human gates between stages let the maintainer review agent output before advancing.

### Pipeline States

```
Triage → Todo → Review → Review Complete → Prepare → Prepare Complete → Merge → Done
                              ↓                                           
                       Request Changes → Backlog → (re-entry via Triage)
                              
                           Closure → Done/Duplicate
```

| State | Type | What Happens |
|-------|------|-------------|
| **Triage** | Agent | Enrichment, cluster detection, duplicate identification, vital signs. Lightweight — no repo clone needed. |
| **Todo** | Human gate | Maintainer reviews triage output, decides next step. |
| **Review** | Agent | Full PR review using `review-pr` skill. Produces structured findings. |
| **Review Complete** | Human gate | Maintainer reviews findings. Routes to Prepare, Request Changes, or Closure. |
| **Prepare** | Agent | Rebases, fixes BLOCKER/IMPORTANT findings, runs gates, pushes. Max 1 at a time (resource constraint). |
| **Prepare Complete** | Human gate | Maintainer verifies prepare output. |
| **Merge** | Agent | Deterministic squash merge with attribution and co-author trailers. |
| **Request Changes** | Agent | Posts `gh pr review --request-changes` on GitHub, moves issue to Backlog to wait for author. |
| **Closure** | Agent | Closes PR on GitHub with appropriate comment (duplicate, superseded, stale, or not useful). |
| **Done** | Terminal | PR merged or closed. |
| **Duplicate** | Terminal | PR identified as duplicate of a canonical PR. Includes structured assessment comment. |

### Key Design Decisions

- **GitHub is source of truth for review status.** Triage agents check `gh pr reviews` for prior CHANGES_REQUESTED reviews and whether the author has pushed new commits since.
- **Human gates are explicit.** Moving an issue to Request Changes IS the approval to comment on the PR. Agents never comment on GitHub without being in an authorized state.
- **Duplicates get assessments.** When a PR is marked as duplicate, a structured comment explains why the canonical PR is preferred and what unique fixes might be lost.
- **Cluster detection uses multi-signal search.** Triage runs `pr-plan --live` to refresh the PR cache, then `pr-cluster` for per-PR search across scope, keywords, files, and linked issues.

## Setup

### Requirements

- Elixir + Mix
- Linear workspace with a project board
- GitHub CLI (`gh`) authenticated
- Codex CLI
- `LINEAR_API_KEY` environment variable

### Import PRs

```bash
cd elixir
LINEAR_API_KEY=<key> mix caclawphony.review <PR#> [<PR#> ...]
```

This creates Linear issues in **Triage** state. Use `--direct` to skip enrichment and go straight to **Review**.

### Run Symphony

```bash
cd elixir
LINEAR_API_KEY=<key> mix run --no-halt
```

Symphony polls Linear every 30 seconds, picks up issues in active states, and dispatches Codex agents.

## Architecture

Caclawphony is built on [Symphony](https://github.com/openai/symphony) — a framework for turning project management boards into autonomous agent dispatch systems. The workflow configuration lives in [`WORKFLOW.md`](elixir/WORKFLOW.md), which defines:

- **Active and terminal states** — which Linear states trigger agent dispatch
- **Hooks** — `after_create` (workspace setup, skill copy, repo clone) and `before_run` (branch checkout)
- **Gates** — human checkpoints that assign the issue back to the maintainer and notify
- **Templates** — Jinja-style prompts per state, with access to issue metadata and state IDs
- **Rules** — global constraints (e.g., never comment on GitHub except in Request Changes state)

See [`SPEC.md`](SPEC.md) for the full Symphony specification and [`elixir/README.md`](elixir/README.md) for Elixir-specific setup.

## License

This project is licensed under the [Apache License 2.0](LICENSE).
