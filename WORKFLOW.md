---
tracker:
  kind: linear
  api_key: $LINEAR_API_KEY
  project_slug: d9873e6beee9
  active_states: Backlog, Review, Prepare, Merge
  terminal_states: Done, Canceled, Duplicate

polling:
  interval_ms: 30000

workspace:
  root: ~/Projects/caclawphony/workspaces

hooks:
  after_create: |
    # Backlog enrichment is lightweight -- just needs gh CLI, no repo clone
    if [ "$SYMPHONY_ISSUE_STATE" = "Backlog" ]; then
      echo "Backlog enrichment -- skipping repo clone"
      exit 0
    fi
    git clone /Users/phaedrus/Projects/openclaw . 2>/dev/null || true
    # Copy skill files into workspace (resolving symlinks from maintainers repo)
    SKILLS_SRC="/Users/phaedrus/Projects/maintainers/.agents/skills"
    SKILLS_DST=".agents/skills"
    if [ -d "$SKILLS_SRC" ]; then
      mkdir -p "$SKILLS_DST"
      for skill in review-pr prepare-pr merge-pr pr-cluster; do
        if [ -d "$SKILLS_SRC/$skill" ]; then
          cp -RL "$SKILLS_SRC/$skill" "$SKILLS_DST/" 2>/dev/null || true
        fi
      done
      # Copy PR_WORKFLOW.md if present
      [ -f "$SKILLS_SRC/PR_WORKFLOW.md" ] && cp "$SKILLS_SRC/PR_WORKFLOW.md" "$SKILLS_DST/" 2>/dev/null || true
    fi
    # Extract PR number from issue title (format: "PR #1234: title" or "#1234")
    PR_NUM=$(echo "$SYMPHONY_ISSUE_TITLE" | grep -oE '#[0-9]+' | head -1 | tr -d '#')
    if [ -n "$PR_NUM" ]; then
      gh pr checkout "$PR_NUM" --force 2>/dev/null || git checkout main
    fi
  before_run: |
    # Backlog enrichment doesn't need repo operations
    [ "$SYMPHONY_ISSUE_STATE" = "Backlog" ] && exit 0
    # Ensure we're on the right branch and up to date
    PR_NUM=$(echo "$SYMPHONY_ISSUE_TITLE" | grep -oE '#[0-9]+' | head -1 | tr -d '#')
    if [ -n "$PR_NUM" ]; then
      gh pr checkout "$PR_NUM" --force 2>/dev/null || true
      git pull --rebase origin HEAD 2>/dev/null || true
    fi
  timeout_ms: 120000

agent:
  max_concurrent_agents: 4
  max_turns: 20
  max_retry_backoff_ms: 300000
  max_concurrent_agents_by_state:
    prepare: 1

codex:
  command: codex app-server
  approval_policy: never
  read_timeout_ms: 30000
  turn_timeout_ms: 1800000
  stall_timeout_ms: 300000
  thread_sandbox: danger-full-access
  turn_sandbox_policy:
    type: dangerFullAccess
---

# Caclawphony -- openclaw/openclaw PR Pipeline

You are a maintainer agent working on the openclaw/openclaw repository.

## Issue Context

- **Issue:** {{ issue.identifier }} -- {{ issue.title }}
- **Description:** {{ issue.description }}
- **State:** {{ issue.state }}
{% if attempt %}- **Attempt:** {{ attempt }}{% endif %}

Extract the PR number from the issue title (format: "PR #1234: title"). Use this PR number throughout.

## Your Task

{% if issue.state == "Backlog" %}
### Triage / Enrichment Phase

You are a PR triage agent for openclaw/openclaw. This issue contains a PR number or GitHub URL.
Your job is to enrich it into a structured assessment that helps a maintainer decide whether to
promote this PR to code review.

Extract the PR number from the issue title or description (formats: "PR #1234: ...", "#1234",
or a GitHub URL like "https://github.com/openclaw/openclaw/pull/1234").

Gather data using `gh` CLI, then produce an assessment with the following sections:

#### 1. Summary (2-3 sentences)
What does this PR do? Restate in plain language -- don't just copy the title.

#### 2. Vital Signs
- **Status:** Open / Draft / Closed / Merged
- **CI:** PASS Passing / FAIL Failing (list failed checks) / PENDING Pending
- **Mergeable:** Yes / Conflicts / Unknown
- **Age:** Created X days ago, last updated Y days ago
- **Author:** @username (association: member/contributor/first-timer, N total open PRs)

#### 3. Scope
- **Files changed:** N files, +X / -Y lines
- **Subsystems touched:** (e.g., browser, agents, config, gateway, CLI, channels)
- **Risk areas:** Flag if touching auth, migrations, core runtime, protocols

#### 4. Change Quality Signals
- Does the PR have tests?
- Does it have a clear description or is it title-only?
- Single focused change or multiple unrelated changes?
- Any obvious code smells from the diff summary?

#### 5. Related PRs
Search for open PRs touching the same primary files or by the same author.
Flag potential duplicates or conflicts.

#### 6. Recommendation & Metadata

Determine a recommendation and priority:

| Recommendation | When | Priority (Linear int) |
|---|---|---|
| **REVIEW** | Looks good, ready for code review | 2 (high) if <5 files and clean CI; 3 (medium) otherwise |
| **WAIT** | Has issues but worth watching | 3 (medium) |
| **SKIP** | Not worth reviewing right now | 4 (low) or 0 (none) for spam/stale |

Determine an **estimate** (Fibonacci complexity):
- **1** -- trivial (typo, one-liner, docs-only)
- **2** -- small (single-file fix, <50 lines)
- **3** -- medium (multi-file, focused change)
- **5** -- large (new feature, cross-cutting)
- **8** -- very large (architectural, multi-subsystem)

Determine **subsystem labels** from the files changed. Map to these label IDs:

| Subsystem | Label ID | Heuristic (file paths) |
|---|---|---|
| gateway | `dc7faf59-f14a-4f03-a549-c0f7fa68ae91` | `src/gateway/`, gateway config |
| channels | `69c1023d-c03f-41b6-a8ef-b4ec378c04d3` | `src/channels/`, telegram/discord/slack/etc |
| browser | `4d8f75c4-2db0-4873-b078-9eb0882c97df` | `src/browser/`, playwright |
| agents | `406758af-0b67-43d9-bb6a-a5440700f1ec` | `src/agents/`, agent config |
| config | `ac615836-9150-42d9-a95f-28ade5a02175` | config schemas, settings |
| cli | `904c5231-efcd-41c6-8b25-2cc54ec07154` | `src/cli/`, bin/ |
| runtime | `e2a2870b-306c-4058-b5f3-0ebf8d84b792` | core runtime, process management |
| auth | `34fc1c6d-e2e2-4ee9-8941-6e52ad1c6006` | auth, tokens, OAuth |
| providers | `74bb9b68-aa94-4898-916b-a6a358b921a3` | `src/providers/`, LLM integrations |
| docs | `49152b2e-2320-4a52-aa3e-902e08ac97bf` | `docs/`, README, markdown-only |

Recommendation labels (always apply exactly one):

| Label | Label ID |
|---|---|
| review | `884ba56a-fb80-4c83-a35e-90ab4dbff32a` |
| wait | `e2cfbdbb-4612-44dd-adb0-2a30b66657ef` |
| skip | `8488053c-40a3-460a-8ee1-b7f93de9ebb7` |

**Data gathering commands:**
```bash
gh pr view <PR> --repo openclaw/openclaw --json number,title,body,author,state,isDraft,createdAt,updatedAt,mergeable,files,additions,deletions,changedFiles,statusCheckRollup,reviews,authorAssociation,headRepository
gh pr diff <PR> --repo openclaw/openclaw --stat
gh pr checks <PR> --repo openclaw/openclaw
gh search prs --repo openclaw/openclaw --state open -- "<search terms from changed files>"
```

**When finished**, update this Linear issue in a single mutation with ALL of the following:

1. **Title** -> `[RECOMMENDATION] PR #XXXX: <original title>`
2. **State** -> Todo (`0772f6b2-85fa-4c21-ab14-6705687d475f`)
3. **Priority** -> integer from the table above
4. **Estimate** -> Fibonacci complexity from the table above
5. **Labels** -> one recommendation label + all matching subsystem labels (array of IDs)
6. **Assignee** -> `5bbd2a49-0fde-4fdd-b265-f6991c718e87` (maintainer -- for human review gate)

```graphql
mutation {
  issueUpdate(id: "{{ issue.id }}", input: {
    title: "[REVIEW] PR #1234: fix streaming response"
    stateId: "0772f6b2-85fa-4c21-ab14-6705687d475f"
    priority: 2
    estimate: 3
    labelIds: ["884ba56a-fb80-4c83-a35e-90ab4dbff32a", "dc7faf59-f14a-4f03-a549-c0f7fa68ae91"]
    assigneeId: "5bbd2a49-0fde-4fdd-b265-f6991c718e87"
  }) { success }
}
```

Also post your full assessment as a **comment** on this Linear issue.

{% elsif issue.state == "Review" %}
### Review Phase

Read the skill file at `.agents/skills/review-pr/SKILL.md` and follow its instructions exactly.

Do NOT comment on the PR on GitHub. Do NOT push any changes. This is a read-only review.

**When finished**, post a summary comment on this Linear issue with:
- The recommendation from `.local/review.json`
- A concise summary of findings (severity + title for each)
- Key concerns or blockers

Then transition this issue to **Review Complete** and assign to the maintainer for decision:
```
mutation { issueUpdate(id: "{{ issue.id }}", input: { stateId: "4f363475-bf45-48a0-9466-c38eef79aded", assigneeId: "5bbd2a49-0fde-4fdd-b265-f6991c718e87" }) { success } }
```

{% elsif issue.state == "Prepare" %}
### Prepare Phase

Read the skill file at `.agents/skills/prepare-pr/SKILL.md` and follow its instructions exactly.

The `.local/review.md` and `.local/review.json` from the review phase should already be in this workspace.

**When finished**, post a summary comment on this Linear issue with:
- What findings were fixed
- Gate results (pass/fail)
- Push status

Then transition this issue to **Prepare Complete** and assign to the maintainer for merge decision:
```
mutation { issueUpdate(id: "{{ issue.id }}", input: { stateId: "0671e7cc-46b5-424e-aed3-d9408c9d3eb9", assigneeId: "5bbd2a49-0fde-4fdd-b265-f6991c718e87" }) { success } }
```

{% elsif issue.state == "Merge" %}
### Merge Phase

Read the skill file at `.agents/skills/merge-pr/SKILL.md` and follow its instructions exactly.

**When finished**, post a summary comment on this Linear issue with:
- Merge commit SHA
- PR URL
- Any cleanup performed

Then transition this issue to **Done**:
```
mutation { issueUpdate(id: "{{ issue.id }}", input: { stateId: "e085693d-8142-4671-9de5-20286fae8ec6" }) { success } }
```

{% endif %}

## Rules

- **Never comment on the PR on GitHub** -- no PR comments, no review submissions
- **Never delete the worktree** -- it persists across pipeline stages
- If you encounter an error you can't resolve, leave a comment on the Linear issue explaining what went wrong
