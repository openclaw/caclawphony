---
tracker:
  kind: linear
  api_key: $LINEAR_API_KEY
  project_slug: d9873e6beee9
  active_states: Triage, Review, Prepare, Merge, Closure, Request Changes
  terminal_states: Done, Canceled, Duplicate

polling:
  interval_ms: 30000

workspace:
  root: ~/Projects/caclawphony/workspaces

hooks:
  after_create: |
    # Copy skill files into workspace (resolving symlinks from maintainers repo)
    # This runs for ALL states -- even lightweight ones need pr-cluster for triage
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
    # Triage enrichment is lightweight -- just needs gh CLI + skills, no repo clone
    if [ "$SYMPHONY_ISSUE_STATE" = "Triage" ]; then
      echo "Triage enrichment -- skipping repo clone"
      exit 0
    fi
    if [ "$SYMPHONY_ISSUE_STATE" = "Closure" ]; then
      echo "Closure agent -- just needs gh CLI, no repo clone"
      exit 0
    fi
    if [ "$SYMPHONY_ISSUE_STATE" = "Request Changes" ]; then
      echo "Request Changes agent -- just needs gh CLI, no repo clone"
      exit 0
    fi
    git clone /Users/phaedrus/Projects/openclaw . 2>/dev/null || true
    # Extract PR number from issue title (format: "PR #1234: title" or "#1234")
    PR_NUM=$(echo "$SYMPHONY_ISSUE_TITLE" | grep -oE '#[0-9]+' | head -1 | tr -d '#')
    if [ -n "$PR_NUM" ]; then
      gh pr checkout "$PR_NUM" --force 2>/dev/null || git checkout main
    fi
  before_run: |
    # Triage, Closure, and Request Changes phases don't need repo operations
    if [ "$SYMPHONY_ISSUE_STATE" = "Triage" ] || [ "$SYMPHONY_ISSUE_STATE" = "Closure" ] || [ "$SYMPHONY_ISSUE_STATE" = "Request Changes" ]; then
      exit 0
    fi
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
  retry_base_ms: 10000
  continuation_delay_ms: 1000
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

notifications:
  telegram:
    bot_token: $TELEGRAM_BOT_TOKEN
    chat_id: $TELEGRAM_CHAT_ID
  gate_states:
    - Review Complete
    - Prepare Complete
  template: "{{ issue.identifier }}: moved to {{ issue.state }}. Review results in workspace."

gates:
  review_complete:
    state_id: "4f363475-bf45-48a0-9466-c38eef79aded"
    assignee: "5bbd2a49-0fde-4fdd-b265-f6991c718e87"
    notify: true
  prepare_complete:
    state_id: "0671e7cc-46b5-424e-aed3-d9408c9d3eb9"
    assignee: "5bbd2a49-0fde-4fdd-b265-f6991c718e87"
    notify: true

states:
  backlog: "33710d02-89f4-4a7b-8b0c-075250c19b3e"
  triage: "0b100831-6a06-431d-848a-6d20980ec7e5"
  todo: "0772f6b2-85fa-4c21-ab14-6705687d475f"
  request_changes: "ca300fc0-0b39-496a-a969-fed20901996c"
  review: "2b76930f-a193-4b8f-ade5-97afed5414aa"
  review_complete: "4f363475-bf45-48a0-9466-c38eef79aded"
  prepare: "42036e0f-29e1-4ece-9ab7-6dd0de1783f8"
  prepare_complete: "0671e7cc-46b5-424e-aed3-d9408c9d3eb9"
  duplicate: "e0c34ba1-e3b3-4de1-b16b-51a7b1be6e4d"
  closure: "8279191b-e703-4d17-b5c0-16f17af7206f"
  done: "e085693d-8142-4671-9de5-20286fae8ec6"

labels:
  recommendation:
    review: "884ba56a-fb80-4c83-a35e-90ab4dbff32a"
    wait: "e2cfbdbb-13e3-4ccc-adeb-5abd00e2b7f9"
    skip: "8488053c-9614-4fba-a84e-f2b8b8e65d32"
  subsystem:
    gateway: "dc7faf59-f14a-4f03-a549-c0f7fa68ae91"
    channels: "69c1023d-71ee-43b3-ab2c-c2dbb2a3b93a"
    browser: "4d8f75c4-96e0-4ba3-afe0-d47d36ffe48a"
    agents: "406758af-c1ca-490e-800e-b8fcaa199d07"
    config: "ac615836-f2a0-48b3-906c-fcf5f8e61c72"
    cli: "904c5231-c8b2-4f68-9db0-2d7ca16a5607"
    runtime: "e2a2870b-cd3e-4b9c-a2ec-6e116e2e1efc"
    auth: "34fc1c6d-e47a-4e3e-9a51-b9cdade2f5d9"
    providers: "74bb9b68-bd9b-4c88-b5c2-56ec3b0a4bde"
    docs: "49152b2e-0c39-470e-9b27-3f71e1f27da7"
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

{% if issue.state == "Triage" %}
### Triage / Enrichment Phase

You are a PR triage agent for openclaw/openclaw. This issue contains a PR number or GitHub URL.
Your job is to enrich it into a structured assessment that helps a maintainer decide whether to
promote this PR to code review.

Extract the PR number from the issue title or description (formats: "PR #1234: ...", "#1234",
or a GitHub URL like "https://github.com/openclaw/openclaw/pull/1234").

#### 0. Prior Review Check (Re-entry Detection)

Before gathering data, check if this PR has previously had changes requested:
```bash
gh pr reviews <PR> --repo openclaw/openclaw --json state,submittedAt,author
```

If there is a `CHANGES_REQUESTED` review, check whether new commits exist after that review's `submittedAt` timestamp:
```bash
gh pr view <PR> --repo openclaw/openclaw --json commits --jq '.commits[-1].committedDate'
```

If the latest commit is **after** the review timestamp: note "Author has pushed updates since changes were requested — prior findings may be addressed. Re-triage accordingly."

If the latest commit is **before** the review timestamp: note "Changes still outstanding from prior review — PR not ready for re-review." Set recommendation to WAIT unless the PR has been otherwise updated.

Include this finding in your assessment under a "Prior Review Status" line in Vital Signs.

---

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
| gateway | `{{ labels.subsystem.gateway }}` | `src/gateway/`, gateway config |
| channels | `{{ labels.subsystem.channels }}` | `src/channels/`, telegram/discord/slack/etc |
| browser | `{{ labels.subsystem.browser }}` | `src/browser/`, playwright |
| agents | `{{ labels.subsystem.agents }}` | `src/agents/`, agent config |
| config | `{{ labels.subsystem.config }}` | config schemas, settings |
| cli | `{{ labels.subsystem.cli }}` | `src/cli/`, bin/ |
| runtime | `{{ labels.subsystem.runtime }}` | core runtime, process management |
| auth | `{{ labels.subsystem.auth }}` | auth, tokens, OAuth |
| providers | `{{ labels.subsystem.providers }}` | `src/providers/`, LLM integrations |
| docs | `{{ labels.subsystem.docs }}` | `docs/`, README, markdown-only |

Recommendation labels (always apply exactly one):

| Label | Label ID |
|---|---|
| review | `{{ labels.recommendation.review }}` |
| wait | `{{ labels.recommendation.wait }}` |
| skip | `{{ labels.recommendation.skip }}` |

#### 7. Cluster Detection

**Step 1:** Refresh the local PR cache (incremental — fast if cache exists):
```bash
/Users/phaedrus/Projects/maintainers/scripts/pr-plan --live --out /Users/phaedrus/Projects/maintainers/.local/pr-plan
```

**Step 2:** Run the pr-cluster skill for this specific PR to find related/duplicate PRs:
Follow the instructions in `.agents/skills/pr-cluster/SKILL.md` to search for clusters around PR `<PR#>`.
The skill uses multi-signal GitHub API search (scope, keywords, files, linked issues) for precise per-PR clustering.

Combine results from both sources — the pr-plan clusters.json and the pr-cluster skill output — to build the full cluster picture.

If the PR is in a cluster with medium or high confidence:
1. For each cluster member, fetch metadata:
```bash
gh pr view <N> --repo openclaw/openclaw --json number,title,state,createdAt,updatedAt,additions,deletions,changedFiles,reviews,isDraft,mergeable
```
2. Pick the canonical PR -- the best candidate for merging. Prioritize:
   - Not draft and not closed
   - Clean CI with passing checks
   - Mergeable with no conflicts
   - Has tests or a meaningful description
   - Fresher (more recently updated)
   - Smaller and more focused
   - Has reviews or approvals
   - **Final tiebreaker: lowest PR number wins** (deterministic — every agent reaches the same answer)

3. **If this issue's PR IS the canonical PR:**
   - For each non-canonical cluster member, check if a Linear issue already exists for it:
     ```bash
     # Search by PR number in issue titles
     ```
     ```graphql
     query {
       project(id: "07919ebc-e133-4c0c-82b9-ead654ec06a2") {
         issues(filter: { title: { contains: "#XXXX" } }) {
           nodes { id identifier title state { name } }
         }
       }
     }
     ```
   - If a Linear issue exists: create a `duplicates` relation between it and this issue.
   - If no Linear issue exists: create one in Duplicate state, then relate it.

   Create duplicate issues (only if no existing issue found):
   ```graphql
   mutation {
     issueCreate(input: {
       teamId: "2d3d9f55-ef35-47cc-a820-aeeb61399256"
       title: "[#XXXX] <title>"
       description: "**PR:** [openclaw/openclaw#XXXX](https://github.com/openclaw/openclaw/pull/XXXX)\n**Author:** @username (ASSOCIATION)\n\n<1-2 sentence summary>"
       stateId: "{{ states.duplicate }}"
       projectId: "07919ebc-e133-4c0c-82b9-ead654ec06a2"
     }) {
       success
       issue { id identifier }
     }
   }
   ```

   Then add a duplicate assessment comment on each created issue:
   ```graphql
   mutation {
     commentCreate(input: {
       issueId: "<duplicate_issue_id>"
       body: "## Duplicate Assessment\n\n**This PR (#XXXX)** — <1-sentence summary>. <N> files changed, +X/-Y.\n\n**Canonical PR: {{ issue.identifier }} [#YYYY](https://github.com/openclaw/openclaw/pull/YYYY)** — `<canonical title>`. Status: <MERGEABLE/CONFLICTING>.\n\n### Why #YYYY is preferred:\n\n- <concrete reasons>\n\n### What #XXXX has that #YYYY may not:\n\n- <unique fixes/edge cases, or 'Nothing — canonical PR fully subsumes this one.'>"
     }) { success }
   }
   ```

   Create relation (and verify it was persisted):
   ```graphql
   mutation {
     issueRelationCreate(input: {
       issueId: "<duplicate_issue_id>"
       relatedIssueId: "{{ issue.id }}"
       type: duplicates
     }) {
       success
       issueRelation { id }
     }
   }
   ```

   **Verify each relation was created** by querying back:
   ```graphql
   query {
     issue(id: "{{ issue.id }}") {
       relations { nodes { type relatedIssue { identifier } } }
     }
   }
   ```
   If any expected relations are missing, retry `issueRelationCreate`. Do not proceed until all duplicate relations are confirmed.

4. **If this issue's PR is NOT the canonical PR:**
   - Check if a Linear issue already exists for the canonical PR (search by PR number as above).
   - If yes: create a `duplicates` relation from this issue to the canonical issue, then move **this issue** to Duplicate state.
   - If no: create a new Linear issue for the canonical PR in Triage state (so it gets enriched immediately), relate this issue to it as a duplicate, then move **this issue** to Duplicate state.

   Create canonical PR issue in Triage:
   ```graphql
   mutation {
     issueCreate(input: {
       teamId: "2d3d9f55-ef35-47cc-a820-aeeb61399256"
       title: "[#XXXX] <canonical PR's title>"
       description: "**PR:** [openclaw/openclaw#XXXX](https://github.com/openclaw/openclaw/pull/XXXX)\n**Author:** @username (ASSOCIATION)\n\n<1-2 sentence summary>"
       stateId: "{{ states.triage }}"
       projectId: "07919ebc-e133-4c0c-82b9-ead654ec06a2"
     }) {
       success
       issue { id identifier }
     }
   }
   ```

   - **Before moving to Duplicate**, add a comment explaining the duplicate assessment:

   ```graphql
   mutation {
     commentCreate(input: {
       issueId: "{{ issue.id }}"
       body: "## Duplicate Assessment\n\n**This PR (#XXXX)** — <1-sentence summary>. <N> files changed, +X/-Y.\n\n**Canonical PR: [#YYYY](https://github.com/openclaw/openclaw/pull/YYYY)** — `<canonical title>` by @author. <N> files changed, +X/-Y. Status: <MERGEABLE/CONFLICTING>.\n\n### Why #YYYY is preferred over #XXXX:\n\n- <concrete reasons: mergeable vs conflicting, broader scope, fresher, better tests, etc.>\n\n### What #XXXX has that #YYYY may not:\n\n- <any unique fixes or edge cases worth checking during canonical PR review, or 'Nothing — canonical PR fully subsumes this one.'>"
     }) { success }
   }
   ```

   This assessment is critical — it preserves the reasoning for future review of the canonical PR and ensures unique fixes don't get lost.

   - **Then stop** — do not proceed to the final metadata update. The canonical PR's issue will handle enrichment.

   Move self to Duplicate:
   ```graphql
   mutation {
     issueUpdate(id: "{{ issue.id }}", input: {
       title: "[#XXXX] <this PR's title>"
       stateId: "{{ states.duplicate }}"
     }) { success }
   }
   ```

5. Include cluster info in your assessment comment: members, canonical PR, and canonical selection rationale.

If the PR is not in any cluster, or confidence is low/unknown, skip this section and continue normal enrichment.

**Data gathering commands:**
```bash
gh pr view <PR> --repo openclaw/openclaw --json number,title,body,author,state,isDraft,createdAt,updatedAt,mergeable,files,additions,deletions,changedFiles,statusCheckRollup,reviews,authorAssociation,headRepository
gh pr diff <PR> --repo openclaw/openclaw --stat
gh pr checks <PR> --repo openclaw/openclaw
gh search prs --repo openclaw/openclaw --state open -- "<search terms from changed files>"
```

**When finished**, do these steps IN THIS ORDER (comment first, mutation last):

**Step 1: Post your full assessment as a comment on this Linear issue.**

```graphql
mutation {
  commentCreate(input: {
    issueId: "{{ issue.id }}"
    body: "<your full assessment markdown>"
  }) { success }
}
```

**Step 2: Update the issue metadata in a single mutation (this MUST be last -- it triggers a state transition that ends your session):**

1. **Title** -> `[#XXXX] <PR title>` (stable format — PR number is the identity, recommendation lives in labels)
2. **Description** -> A short description block with PR link, author, and summary (see format below)
3. **State** -> Todo (`{{ states.todo }}`)
4. **Priority** -> integer from the table above
5. **Estimate** -> Fibonacci complexity from the table above
6. **Labels** -> one recommendation label + all matching subsystem labels (array of IDs)
7. **Assignee** -> `{{ gates.review_complete.assignee }}` (maintainer -- for human review gate)

Description format (markdown):
```
**PR:** [openclaw/openclaw#1234](https://github.com/openclaw/openclaw/pull/1234)
**Author:** @username (FIRST_TIME_CONTRIBUTOR | CONTRIBUTOR | MEMBER | etc.)

<1-2 sentence summary of what the PR does>
```

```graphql
mutation {
  issueUpdate(id: "{{ issue.id }}", input: {
    title: "[#1234] fix streaming response"
    description: "**PR:** [openclaw/openclaw#1234](https://github.com/openclaw/openclaw/pull/1234)\n**Author:** @username (CONTRIBUTOR)\n\nFixes streaming response handling by adding proper buffer flushing on connection close."
    stateId: "{{ states.todo }}"
    priority: 2
    estimate: 3
    labelIds: ["{{ labels.recommendation.review }}", "{{ labels.subsystem.gateway }}"]
    assigneeId: "{{ gates.review_complete.assignee }}"
  }) { success }
}
```

{% elsif issue.state == "Review" %}
### Review Phase

**Before starting work**, check this Linear issue for maintainer comments that may contain context, focus areas, or known issues. Query:
```graphql
query { issue(id: "{{ issue.id }}") { comments { nodes { body createdAt user { name } } } } }
```
If any comments contain review guidance from the maintainer, factor them into your analysis.

Read the skill file at `.agents/skills/review-pr/SKILL.md` and follow its instructions exactly.

Do NOT comment on the PR on GitHub. Do NOT push any changes. This is a read-only review.

**When finished**, do these steps IN THIS ORDER (comment first, state transition last):

1. **Post a summary comment** on this Linear issue with:
   - The recommendation from `.local/review.json`
   - A concise summary of findings (severity + title for each)
   - Key concerns or blockers

2. **Then transition this issue** to Review Complete (this MUST be last -- it ends your session):
```
mutation { issueUpdate(id: "{{ issue.id }}", input: { stateId: "4f363475-bf45-48a0-9466-c38eef79aded", assigneeId: "5bbd2a49-0fde-4fdd-b265-f6991c718e87" }) { success } }
```

{% elsif issue.state == "Prepare" %}
### Prepare Phase

**Before starting work**, check this Linear issue for maintainer comments that may contain guidance, fix directions, or constraints. Query:
```graphql
query { issue(id: "{{ issue.id }}") { comments { nodes { body createdAt user { name } } } } }
```
If any comments contain fix guidance or specific instructions from the maintainer, incorporate them into your approach. Maintainer direction takes priority over review findings when they conflict.

Read the skill file at `.agents/skills/prepare-pr/SKILL.md` and follow its instructions exactly.

The `.local/review.md` and `.local/review.json` from the review phase should already be in this workspace.

#### Generate Live Test Plan

After fixes and gates pass, generate a test plan in `.local/test-plan.md` that a maintainer agent can execute on a live OpenClaw instance to validate the PR before merge.

**Analyze the PR diff** and produce the following sections:

```markdown
# Test Plan: PR #XXXX — <title>

## Risk Tier

Classify as one of:
- **GREEN** — Safe to test on production instance. Config changes, new tool params, error messages, docs, logging, non-breaking additions.
- **YELLOW** — Test with caution. Auth changes, model routing, compaction, session management. Have rollback ready.
- **RED** — Needs isolated instance or manual testing. Breaking changes, data migrations, protocol changes, core runtime rewrites.

## What Changed (test-relevant summary)
- <bullet list of functional changes that have observable behavior>

## Test Steps

For each testable change, provide a concrete verification step. Use commands available to an OpenClaw agent:

### Test 1: <description>
**What:** <what behavior to verify>
**How:**
```bash
<exact command to run — openclaw CLI, exec, gateway config.patch, curl, etc.>
```
**Expected:** <what success looks like>
**Rollback:** <how to undo if something breaks>

### Test 2: ...

## Untestable Changes
- <list anything that can't be verified on a live instance and why>
  - Channel-specific (requires Feishu/Slack/etc. configured)
  - UI/TUI only (requires interactive terminal)
  - Race condition / timing dependent
  - Requires specific provider account

## Pre-test Checklist
- [ ] Current instance is on main (clean baseline)
- [ ] Build PR branch: `cd ~/Projects/clawdbot && git fetch origin pull/XXXX/head:test-XXXX && git checkout test-XXXX && pnpm build`
- [ ] Restart gateway on PR branch
- [ ] Run test steps above
- [ ] After testing: `git checkout main && pnpm build` + restart gateway

## Rollback
If anything goes wrong during testing:
```bash
cd ~/Projects/clawdbot && git checkout main && pnpm build
openclaw gateway restart
```
```

**Guidelines for test steps:**
- Prefer `openclaw` CLI commands and `gateway config.patch` over manual file edits
- For tool changes: construct a message that would trigger the tool, verify the response
- For error handling: trigger the error condition, verify the new behavior
- For config changes: patch the config, verify the setting takes effect
- Be specific — "verify it works" is not a test step; "run `openclaw status` and confirm X field shows Y" is
- Each test should be independently executable (no ordering dependencies where possible)
- Include `gateway restart` after config changes that require it

#### Generate Test Kit (if applicable)

If the PR has **API-observable behavioral changes** (gateway methods, config effects, session behavior, CLI output, tool responses), also generate executable test scripts in `.local/test-kit/`.

**Skip this section** for PRs that are pure refactors, docs-only, UI/TUI-only, or provider-specific with no local testability.

**Structure:**

```
.local/test-kit/
├── README.md              # What these scripts test, how to run them
├── common.sh              # Shared helpers (see template below)
├── 01-test-<scenario>.sh  # One script per test scenario
├── 02-test-<scenario>.sh
└── 90-cleanup.sh          # Teardown / restore
```

**common.sh template** — source test-gateway.sh from caclawphony and provide helpers:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PORT="${TEST_GW_PORT:-18790}"
BASE_URL="http://127.0.0.1:$PORT"

# Call a gateway API method
gw_call() {
  local method="$1"
  local params="${2:-{\}}"
  curl -sf "$BASE_URL/api" \
    -H 'Content-Type: application/json' \
    -d "{\"method\": \"$method\", \"params\": $params}"
}

# Assert a jq expression against JSON input
assert_jq() {
  local desc="$1" filter="$2" input="$3"
  if echo "$input" | jq -e "$filter" >/dev/null 2>&1; then
    echo "  ✓ $desc"
  else
    echo "  ✗ $desc"
    echo "    Filter: $filter"
    echo "    Input: $(echo "$input" | jq -c . 2>/dev/null || echo "$input")"
    FAILURES=$((FAILURES + 1))
  fi
}

FAILURES=0
trap 'if (( FAILURES > 0 )); then echo ""; echo "$FAILURES assertion(s) failed"; exit 1; fi' EXIT
```

**Each numbered test script should:**
1. Source `common.sh`
2. Set up preconditions (config patches, session creation)
3. Run the behavior under test
4. Assert expected outcomes with `assert_jq`
5. Clean up its own state (restore config, delete test sessions)
6. Use disposable session keys like `agent:main:test-<pr>-<scenario>`

**Guidelines:**
- Use `jq -e '...'` for assertions — never compare against jq's `empty` generator (use `== null` or `== 0`)
- Each script must be independently runnable (no ordering dependencies)
- Scripts target whatever gateway is on `$TEST_GW_PORT` — they don't manage the gateway lifecycle
- Include a brief description comment at the top of each script explaining what it validates
- Test the **new** behavior, not the old behavior (don't write tests that pass on main)

**When finished**, do these steps IN THIS ORDER (comment first, state transition last):

1. **Post a summary comment** on this Linear issue with:
   - What findings were fixed
   - Gate results (pass/fail)
   - Push status
   - **Full test plan** — include the complete `.local/test-plan.md` content in the comment (risk tier, what changed, all test steps with exact commands, rollback). Do NOT summarize it to a one-liner — the maintainer reads this comment to decide whether to test and merge.
   - **Test kit location** (if generated) — include the worktree path, e.g.:
     ```
     ## Test Kit
     Executable test scripts are at:
       <worktree-path>/.local/test-kit/
     
     To run:
       test-gateway.sh start <worktree-path>
       cd <worktree-path>/.local/test-kit && bash 01-test-*.sh
       test-gateway.sh stop
     ```

2. **Then transition this issue** to Prepare Complete (this MUST be last -- it ends your session):
```
mutation { issueUpdate(id: "{{ issue.id }}", input: { stateId: "0671e7cc-46b5-424e-aed3-d9408c9d3eb9", assigneeId: "5bbd2a49-0fde-4fdd-b265-f6991c718e87" }) { success } }
```

{% elsif issue.state == "Merge" %}
### Merge Phase

Read the skill file at `.agents/skills/merge-pr/SKILL.md` and follow its instructions exactly.

**If merge-verify or merge-run fails** (conflicts, mainline drift, head mismatch, CI failure, etc.):

1. **Post a comment** on this Linear issue explaining what failed and why (include the error output).
2. **Move the issue back to Prepare** so the PR gets rebased and re-gated:
```graphql
mutation { issueUpdate(id: "{{ issue.id }}", input: { stateId: "42036e0f-29e1-4ece-9ab7-6dd0de1783f8" }) { success } }
```
Do NOT retry the merge yourself. Stop after the state transition.

**When merge succeeds**, do these steps IN THIS ORDER (comment first, state transition last):

1. **Post a summary comment** on this Linear issue with:
   - Merge commit SHA
   - PR URL
   - Any cleanup performed
   - Duplicate review summary (for each related Duplicate issue): whether duplicate has unique value, recommended action (CLOSE or REOPEN), and a draft closing comment

Before the state transition, query issue relations to find Duplicate issues:
```graphql
query {
  issue(id: "{{ issue.id }}") {
    relations {
      nodes {
        relatedIssue {
          id
          identifier
          title
          state {
            name
          }
        }
        type
      }
    }
  }
}
```

For each related Duplicate issue, extract the duplicate PR number and check whether it contains uncaptured value not covered by the canonical merge. Post a comment on the Duplicate Linear issue including merge confirmation, unique-value determination, recommended action (CLOSE or REOPEN), and a draft closing comment.

Then **move each Duplicate issue to Closure** so the closure agent can process it:
```graphql
mutation {
  issueUpdate(id: "<duplicate_issue_id>", input: { stateId: "{{ states.closure }}" }) { success }
}
```

2. **Then transition this issue** to Done (this MUST be last -- it ends your session):
```
mutation { issueUpdate(id: "{{ issue.id }}", input: { stateId: "e085693d-8142-4671-9de5-20286fae8ec6" }) { success } }
```

{% elsif issue.state == "Closure" %}
### Closure Phase

Close a PR on GitHub. The reason may vary — duplicate, superseded, stale, or not useful.

#### Step 1: Gather context

1. Extract the PR number from this issue title.
2. Read **all comments on this Linear issue** to understand why it's being closed.
3. Check for **related Linear issues** (duplicates, canonical PRs):
```graphql
query {
  issue(id: "{{ issue.id }}") {
    relations { nodes { type relatedIssue { id identifier title state { name } } } }
  }
}
```
4. Check the PR status on GitHub:
```bash
gh pr view <PR> --repo openclaw/openclaw --json state,mergedBy,mergeCommit,title
```

#### Step 2: Determine closure reason

From the context gathered, classify the closure:

| Reason | Signal | Comment tone |
|--------|--------|-------------|
| **Duplicate** | Related Linear issue with canonical PR | "This is addressed by #CANONICAL (merged as COMMIT / still open)" |
| **Superseded** | Review comments mention a merged PR or upstream commit that covers this | "This has been addressed upstream via #PR / commit SHA" |
| **Stale** | PR is old, conflicting, author inactive | "Closing as stale — feel free to reopen against current main" |
| **Not useful** | Review recommends SKIP/CLOSE, no redeeming value | "Closing — [brief reason from review]. Thank you for the contribution" |

Always be respectful. Thank the contributor.

#### Step 3: Close the PR

1. Post the closing comment:
```bash
gh pr comment <PR> --repo openclaw/openclaw --body "<closing comment>"
```
2. Close the PR:
```bash
gh pr close <PR> --repo openclaw/openclaw
```

#### Step 4: Wrap up

1. Post a confirmation comment on this Linear issue summarizing what was done.
2. Then transition this issue to Done (this MUST be last — it ends your session):
```graphql
mutation {
  issueUpdate(id: "{{ issue.id }}", input: { stateId: "{{ states.done }}" }) {
    success
  }
}
```

{% elsif issue.state == "Request Changes" %}
### Request Changes Phase

Post a GitHub code review requesting changes from the PR author, based on findings from the review phase.

#### Step 1: Gather review findings

1. Extract the PR number from this issue title.
2. Read **all comments on this Linear issue** — especially the review phase comment that contains findings.
3. Identify findings classified as **author-required** — these are issues the maintainer decided can't be fixed mechanically by prepare-pr:
   - Fundamental design/approach problems
   - Changes that need to be split into separate PRs
   - Domain knowledge the author has but we don't
   - Bundled unrelated changes

#### Step 2: Draft the review comment

Write a clear, actionable, respectful GitHub review comment. Structure:

```
## Changes Requested

Thank you for this contribution! We've reviewed this PR and have some feedback before it can move forward.

### [Finding 1 title]
[Clear explanation of what needs to change and why]

### [Finding 2 title]
[Clear explanation]

---

Once these are addressed, we'll re-review. Feel free to ask questions if anything is unclear.
```

Guidelines:
- Be specific about what needs to change
- Explain *why*, not just *what*
- Suggest concrete approaches where possible
- Thank the contributor
- Keep it concise — no need to repeat the full review

#### Step 3: Post the review on GitHub

```bash
gh pr review <PR> --repo openclaw/openclaw --request-changes --body "<review comment>"
```

#### Step 4: Move to Backlog

1. Post a confirmation comment on this Linear issue summarizing what was posted.
2. Then move the issue to Backlog (this MUST be last — it ends your session):
```graphql
mutation {
  issueUpdate(id: "{{ issue.id }}", input: {
    stateId: "{{ states.backlog }}"
  }) { success }
}
```

{% endif %}

## Rules

{% if issue.state != "Closure" and issue.state != "Request Changes" %}
- **Never comment on the PR on GitHub** -- no PR comments, no review submissions
{% endif %}
- **Never delete the worktree** -- it persists across pipeline stages
- If you encounter an error you can't resolve, leave a comment on the Linear issue explaining what went wrong
