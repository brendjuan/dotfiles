---
name: review-swarm
description: Heavyweight multi-agent code review. Fans out 10 dimension-specialist reviewers over a diff in parallel, then runs a second wave of 7-10 adversarial verifiers that validate every finding against the real code, then distills the survivors into a full Markdown report (TL;DR on top) and shows a terminal summary. Use when the user runs /review-swarm, or asks for a thorough/exhaustive/multi-agent review of a branch, diff, PR, or path. For a quick single-pass review prefer /code-review.
---

# Review Swarm

A three-stage, multi-agent review run through the **Workflow** engine:

1. **Survey** — 10 reviewers, each owning one dimension (correctness, security, error-handling, concurrency, performance, api-design, data-integrity, tests, maintainability, deps-config), scan the diff in parallel.
2. **Verify** — the findings are deduped and sharded across **7-10 adversarial verifiers** that re-read the actual code and mark each finding `confirmed` / `false-positive` / `uncertain` (default to skepticism). This kills hallucinated and false-positive findings.
3. **Distill** — a lead-reviewer agent synthesizes the confirmed findings into a full Markdown report with a `## TL;DR` at the top.

Invoking this skill **authorizes the Workflow tool** for this run — call it as described below.

## Steps

### 1. Determine the review scope

Default: **the current branch vs `origin/main`.** Interpret any argument the user passed:

- **No args** → branch vs origin/main (the default).
- **A path / glob** (e.g. `src/auth/`) → still diff vs origin/main, but restrict to that path.
- **A ref range** (`a..b`, `a...b`, a tag, a SHA) → use it verbatim as the range.
- **`#123` or a bare number / PR URL** → a PR: `gh pr checkout <n>` is optional; simplest is to set the range to `origin/main...HEAD` after checkout, or use `gh pr diff <n>` to identify changed files.
- **"uncommitted" / "working tree" / "staged"** → range `""` (plain `git diff`, optionally `--staged`).

Resolve it concretely with shell. Typical default path:

```sh
git fetch --quiet origin 2>/dev/null
BASE=origin/main; git rev-parse --verify --quiet origin/main >/dev/null || BASE=origin/master
RANGE="$BASE...HEAD"
git --no-pager diff --name-only "$RANGE"      # the changed-file list
git rev-parse --abbrev-ref HEAD               # current branch (for the report filename)
```

If the diff is empty, tell the user there's nothing to review and stop. If it's enormous (e.g. >150 changed files), say so and confirm scope before spending the agents.

### 2. Run the swarm

Call the **Workflow** tool with the bundled script and the resolved scope as `args`:

- `scriptPath`: `/home/bjax/.claude/skills/review-swarm/review-swarm.workflow.js`
- `args`: a JSON **object** (not a string):
  - `scope`  — human description, e.g. `"branch feat/x vs origin/main"`
  - `range`  — the git range, e.g. `"origin/main...HEAD"` (use `""` for plain working-tree diff)
  - `changed` — the array of changed file paths from step 1 (pass `[]` if you couldn't enumerate them; the agents will discover them)

Example invocation shape (Workflow tool input):

```json
{ "scriptPath": "/home/bjax/.claude/skills/review-swarm/review-swarm.workflow.js",
  "args": { "scope": "branch feat/login vs origin/main", "range": "origin/main...HEAD",
            "changed": ["src/auth/login.ts", "src/auth/session.ts"] } }
```

Workflow runs in the background; wait for the completion notification, then read its returned object. It contains: `tldr`, `summary_bullets`, `report_markdown`, `counts` (`found`, `confirmed`, `false_positive`, `uncertain`, `by_severity`), and `scope`.

### 3. Write the report and show the summary

1. **Write** `report_markdown` to a file under `~/claude-reviews/<date>/` using the Write tool. Create the directory first (`mkdir -p ~/claude-reviews/"$(date +%Y-%m-%d)"`) and name the file:
   ```
   ~/claude-reviews/<YYYY-MM-DD>/review-swarm-<branch>-<YYYYMMDD-HHMM>.md
   ```
   Sanitize `/` in the branch name to `-`. Get the day folder with `date +%Y-%m-%d` and the filename timestamp with `date +%Y%m%d-%H%M`.
2. **Show the user a concise terminal summary** — do NOT paste the whole report. Print:
   - the one-line severity tally from `counts.by_severity` and the confirmed/false-positive/uncertain counts,
   - the `tldr`,
   - the `summary_bullets` as a bullet list,
   - the saved report's path (clickable).
3. Offer next steps (e.g. "want me to fix the criticals?") but don't act without the user.

## Notes

- The verification wave is the point — it's what makes the output trustworthy. Never present raw survey findings as if confirmed; only `confirmed` findings belong in the Findings section, with the rest under "Filtered out".
- The finder count is fixed at 10 (one per dimension). The verifier count auto-scales to 7-10, dropping below 7 only when there are fewer than 7 findings total.
- This is token-heavy (≈20+ agents). For a light pass, point the user at `/code-review` instead.
- To tweak dimensions, severity rules, or counts, edit `review-swarm.workflow.js` next to this file and re-run — `scriptPath` always reads the latest version from disk.
