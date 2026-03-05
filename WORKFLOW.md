---
tracker:
  kind: linear
  api_key: $LINEAR_API_KEY
  project_slug: d9873e6beee9
  active_states: Review, Prepare, Merge
  terminal_states: Done, Canceled, Duplicate

polling:
  interval_ms: 30000

workspace:
  root: ~/Projects/caclawphony/workspaces

hooks:
  after_create: |
    git clone /Users/phaedrus/Projects/openclaw . 2>/dev/null || true
    # Extract PR number from issue title (format: "PR #1234: title" or "#1234")
    PR_NUM=$(echo "$SYMPHONY_ISSUE_TITLE" | grep -oE '#[0-9]+' | head -1 | tr -d '#')
    if [ -n "$PR_NUM" ]; then
      gh pr checkout "$PR_NUM" --force 2>/dev/null || git checkout main
    fi
  before_run: |
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
---

# Caclawphony — openclaw/openclaw PR Pipeline

You are a maintainer agent working on the openclaw/openclaw repository.

## Issue Context

- **Issue:** {{ issue.identifier }} — {{ issue.title }}
- **Description:** {{ issue.description }}
- **State:** {{ issue.state }}
{% if attempt %}- **Attempt:** {{ attempt }}{% endif %}

Extract the PR number from the issue title (format: "PR #1234: title"). Use this PR number throughout.

## Your Task

{% if issue.state == "Review" %}
### Review Phase — Read-Only PR Analysis

Perform a read-only review and produce both human and machine-readable outputs.

**Safety:** Never push, merge, or modify code. Work only in the PR worktree.

**Steps:**

1. **Setup and metadata**
```sh
scripts/pr-review <PR>
ls -la .local/pr-meta.json .local/pr-meta.env .local/review-context.env .local/review-mode.env
```

2. **Check existing implementation on main**
```sh
scripts/pr review-checkout-main <PR>
# Search for relevant patterns in the codebase
rg -n "<keyword>" -S src extensions apps || true
```

3. **Read PR description and diff**
```sh
scripts/pr review-checkout-pr <PR>
gh pr diff <PR>
source .local/review-context.env
git diff --stat "$MERGE_BASE"..pr-<PR>
git diff "$MERGE_BASE"..pr-<PR>
```

4. **Optional: run targeted tests**
```sh
scripts/pr review-tests <PR> <test-file> [<test-file> ...]
```

5. **Initialize review artifact templates**
```sh
scripts/pr review-artifacts-init <PR>
```

6. **Produce review outputs**

Fill `.local/review.md` with sections A through J:
- A) TL;DR recommendation
- B) What changed and what is good
- C) Security findings
- D) PR intent and optimality assessment
- E) Concerns or questions (actionable)
- F) Tests (ran, gaps, results)
- G) Docs status
- H) Changelog status
- I) Follow-ups (optional)
- J) Suggested PR comment (optional)

Fill `.local/review.json` with this minimum shape:
```json
{
  "recommendation": "READY FOR /prepare-pr",
  "findings": [
    { "id": "F1", "severity": "IMPORTANT", "title": "...", "area": "path/or/component", "fix": "Actionable fix" }
  ],
  "tests": { "ran": [], "gaps": [], "result": "pass" },
  "docs": "up_to_date|missing|not_applicable",
  "changelog": "required"
}
```

7. **Guard + validate**
```sh
scripts/pr review-guard <PR>
scripts/pr review-validate-artifacts <PR>
```

**When finished**, transition this issue to **Review Complete**:
```
mutation { issueUpdate(id: "{{ issue.id }}", input: { stateId: "4f363475-bf45-48a0-9466-c38eef79aded" }) { success } }
```

{% elsif issue.state == "Prepare" %}
### Prepare Phase — Fix Findings, Gate, Push

Prepare the PR head branch for merge after review. The `.local/review.md` and `.local/review.json` from the review phase should be in this workspace.

**Safety:** Never push to `main`. Only push to PR head with `--force-with-lease`. Never run `git clean -fdx`.

**Steps:**

1. **Setup and verify artifacts**
```sh
scripts/pr-prepare init <PR>
ls -la .local/review.md .local/review.json .local/pr-meta.env .local/prep-context.env
jq . .local/review.json >/dev/null
```

2. **Resolve required findings**
```sh
jq -r '.findings[] | select(.severity=="BLOCKER" or .severity=="IMPORTANT") | "- [\(.severity)] \(.id): \(.title) => \(.fix)"' .local/review.json
```
Fix all BLOCKER and IMPORTANT findings. Keep scope tight.

3. **Update changelog/docs**
- `CHANGELOG.md` must include a newly added entry
- When PR author metadata is available, the entry must include `(#<PR>) thanks @<pr-author>`

4. **Commit scoped changes** (concise subjects, no PR numbers — those go in the final squash commit)
```sh
scripts/committer "fix: <summary>" <file1> <file2> ...
```

5. **Run gates**
```sh
scripts/pr-prepare gates <PR>
```

6. **Push safely to PR head**
```sh
scripts/pr-prepare push <PR>
```

7. **Verify handoff artifacts**
```sh
ls -la .local/prep.md .local/prep.env
```

**When finished**, transition this issue to **Prepare Complete**:
```
mutation { issueUpdate(id: "{{ issue.id }}", input: { stateId: "0671e7cc-46b5-424e-aed3-d9408c9d3eb9" }) { success } }
```

{% elsif issue.state == "Merge" %}
### Merge Phase — Deterministic Squash Merge

Merge a prepared PR after deterministic validation.

**Safety:** Never use `gh pr merge --auto`. Never run `git push` directly. Always use `--match-head-commit`.

**Steps:**

1. **Validate artifacts exist**
```sh
for f in .local/review.md .local/review.json .local/prep.md .local/prep.env; do
  [ -s "$f" ] || { echo "Missing artifact: $f"; exit 1; }
done
```

2. **Validate checks and branch status**
```sh
scripts/pr-merge verify <PR>
source .local/prep.env
```

3. **Merge deterministically**
```sh
scripts/pr-merge run <PR>
```

This performs: squash merge pinned to `PREP_HEAD_SHA`, reviewer merge author email, co-author trailers for PR author and reviewer, post-merge verification, PR comment with merge details, cleanup after confirmed MERGED.

4. **Report these values** in a human-readable summary:
- Merge commit SHA
- Merge author email
- Merge completion comment URL
- PR URL

**When finished**, transition this issue to **Done**:
```
mutation { issueUpdate(id: "{{ issue.id }}", input: { stateId: "e085693d-8142-4671-9de5-20286fae8ec6" }) { success } }
```

{% endif %}

## Rules

- **Never comment on the PR on GitHub** — no PR comments, no review submissions
- **Never delete the worktree** — it persists across pipeline stages
- If you encounter an error you can't resolve, leave a comment on the Linear issue explaining what went wrong
- Use merge-base scoped diffs for local context to avoid stale branch drift
