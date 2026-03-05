# Caclawphony — Production Readiness Plan

## What Is Caclawphony?

A fork of [Symphony](https://github.com/openai/symphony) (Elixir) wired to Linear and Codex for automated PR review/prepare/merge on `openclaw/openclaw`.

**Current state:** Proof of concept working end-to-end. MAR-45 (test issue) completed the full Review cycle — Codex picked up the issue, cloned the repo, ran review-pr, produced `.local/review.md` + `.local/review.json`, transitioned the issue to "Review Complete", and Symphony detected the state change and stopped the agent.

## Architecture

```
Linear (issue tracker)
  ↕ polling (30s)
Symphony/Caclawphony (Elixir orchestrator)
  ↕ JSON-RPC over stdio
Codex app-server (agent runtime)
  ↕ shell + file I/O
openclaw/openclaw repo (PR workspace)
```

### Linear Workflow States

| State | Type | Description |
|-------|------|-------------|
| Triage | manual | New PRs land here |
| **Review** | active | Codex runs review-pr |
| Review Complete | gate | Human evaluates review |
| **Prepare** | active | Codex runs prepare-pr |
| Prepare Complete | gate | Human evaluates preparation |
| **Merge** | active | Codex runs merge-pr |
| Done | terminal | Merged successfully |
| Canceled | terminal | Abandoned |
| Duplicate | terminal | Superseded by another PR |

Active states trigger agent dispatch. Gate states require human intervention.

### Key Files

| File | Purpose |
|------|---------|
| `WORKFLOW.md` | Symphony config: tracker, hooks, codex settings, prompt template |
| `elixir/lib/symphony_elixir/` | Elixir source (orchestrator, agent_runner, tracker, workspace) |
| `elixir/lib/symphony_elixir/workspace.ex` | Modified: passes issue env vars to hooks |
| `SPEC.md` | Original Symphony spec (reference) |

## What Works

- [x] Linear polling picks up issues in active states
- [x] Workspace creation with git clone + PR checkout hooks
- [x] Codex app-server handshake (initialize → thread/start → turn/start)
- [x] State-aware prompt template (Review/Prepare/Merge conditional sections)
- [x] Agent executes review-pr skill, produces artifacts
- [x] Agent transitions issue state via Linear GraphQL
- [x] Symphony detects state change and stops agent (continuation check)
- [x] Issue env vars passed to hooks (SYMPHONY_ISSUE_ID, _IDENTIFIER, _TITLE, _STATE)

## What Needs Work

### P0 — Must Have for Production

1. **Codex sandbox networking** — Codex `workspace-write` sandbox blocks network access. `pnpm install`, `gh pr`, `npm test` all fail. Review worked because it fell back to local git analysis, but prepare-pr and merge-pr need network. Options:
   - Switch to `danger-full-access` sandbox (works but no safety net)
   - Use Symphony hooks for network-dependent setup (pre-install deps, fetch PR data)
   - Contribute upstream Codex sandbox network allowlist

2. **Workspace reuse across pipeline stages** — Currently each dispatch creates a fresh workspace. Review → Prepare should reuse the same workspace so prepare-pr can read `.local/review.md`. Options:
   - Key workspaces by issue ID, skip `after_create` if dir exists
   - Workspace.ex `create_workspace` already does `File.mkdir_p` — just need to skip hooks on re-entry

3. **Log file creation** — `LogFile` module fails silently because log dir doesn't exist. Need to ensure `log/` directory is created.

4. **Stale rollout path errors** — Codex spews ~50 "state db missing rollout path" errors on startup from old sessions. Harmless but noisy. Clean up `~/.codex/` state DB or suppress in log config.

### P1 — Important for Usability

5. **PR intake pipeline** — Need a way to feed PRs into Linear. Options:
   - CLI command: `caclawphony review 34511` → creates Linear issue in Review state
   - Batch import: read from `pb list` or `gh pr list` and create issues
   - GitHub webhook → Linear issue creation (future)

6. **Marie Clawndo integration** — Marie should be able to create Linear issues when Josh says "review PR #X", monitor Symphony status, and report completions. Replace maniple worker spawning with Linear issue creation for the review→prepare→merge pipeline.

7. **Workspace cleanup** — After merge (terminal state), workspaces should be deleted. `after_run` hook or orchestrator cleanup on terminal state detection.

8. **Dashboard improvements** — Symphony's TUI dashboard works but could show more: current turn number, last activity timestamp, Codex token usage.

### P2 — Nice to Have

9. **PR-to-issue metadata** — Store PR number, author, URL in Linear issue description so agents have full context without parsing titles.

10. **Notification on completion** — When an issue reaches a gate state, notify via Telegram (Marie Clawndo bot).

11. **Multi-turn prepare-pr** — Prepare phase may need multiple Codex turns (fix code → run tests → iterate). Symphony supports `max_turns: 20` but we haven't tested multi-turn with state persistence.

12. **Metrics & reporting** — Track review quality, time-to-merge, agent success rate. Symphony has `StatusDashboard` with session totals — extend to persist.

## Configuration Reference

### WORKFLOW.md Codex Section

```yaml
codex:
  command: codex app-server
  approval_policy: on-failure    # valid: untrusted, on-failure, on-request, never
  read_timeout_ms: 30000         # handshake timeout (default 5000 too tight)
  turn_timeout_ms: 1800000       # 30 min per turn
  stall_timeout_ms: 300000       # 5 min stall detection
  # thread_sandbox: workspace-write  # default, valid: read-only, workspace-write, danger-full-access
```

### Linear State IDs (MAR team)

| State | ID |
|-------|----|
| Review | 2b76930f-a193-4b8f-ade5-97afed5414aa |
| Review Complete | 4f363475-bf45-48a0-9466-c38eef79aded |
| Prepare | 42036e0f-ab10-480b-9fe3-28d7cf2a6ef2 |
| Prepare Complete | 0671e7cc-46b5-424e-aed3-d9408c9d3eb9 |
| Merge | a976450a-2b6f-4fd1-90b4-f9f2eac30c92 |
