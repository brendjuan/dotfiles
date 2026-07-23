---
name: convention-review
description: Convention-adherence tooling for ROS2 (ament/colcon) repositories, backed by an on-disk convention vault. `learn` mines the repo + ROS2 standards and writes one-rule-per-note markdown into the vault; `review` (default) checks a PR diff against those notes, adversarially verifies each finding, and distills a Markdown report; `audit` grep-checks that each note's evidence still exists. Use when the user asks whether a branch/diff/PR follows the repo's conventions or idioms, runs /convention-review, or wants to (re)learn/curate the convention vault. For general correctness/security review prefer /review-swarm or /code-review.
---

# Convention Review

A convention knowledge **vault** on disk is the backbone. Two thin operations hang off it, plus a freshness check — all run through the **Workflow** engine:

- **`learn`** — one agent per dimension mines the repo (+ ROS2 REPs/ament/rclpy) and **writes/reconciles one-rule-per-note** markdown files into the vault. Non-destructive: never clobbers a `verified`/`rejected` or hand-edited note.
- **`review`** (default) — per-dimension reviewers + a holistic **Fable** pass read the vault notes as the source of truth and flag PR deviations; findings are deduped, adversarially verified against the real code, and distilled into a Markdown report with a `## TL;DR`.
- **`audit`** — mechanical grep/git pass: for each repo note, checks its `evidence:` file:line still exists and marks drifted notes `status: stale`.

The vault is plain markdown (Obsidian-friendly, `[[links]]` between notes) — humans can read, correct, and veto rules. Nothing requires Obsidian.

Dimensions: `package-metadata`, `ros-interfaces`, `node-implementation`, `launch-files`, `build-ci-docker`, `tests`, `python-style-structure` (+ a holistic Fable pass in `review`).

Invoking this skill **authorizes the Workflow tool** for this run.

## Vault layout

```
$CLAUDE_OBSIDIAN_VAULT/conventions/   # env var → your Obsidian vault; default ~/.claude/obsidian_vault/conventions (untracked)
  ros2-standards/<dimension>/<slug>.md   # repo-INDEPENDENT — mined once, reused across every ROS2 repo; NO repo sha
  <repo>/<dimension>/<slug>.md           # this repo's conventions; frontmatter stamps updated_from_sha
  <repo>/_index.md                       # dashboard: notes by dimension/status
```

Note frontmatter (one rule per file):
```yaml
---
id: named-qos-profiles          # == filename stem, stable
dimension: node-implementation
status: proposed                # proposed | verified | rejected | stale  — review consumes ALL except 'rejected'
severity_default: low
source: repo-pattern            # repo-pattern | repo-rule-file | ros2-standard
evidence: [src/some_pkg/some_pkg/some_node.py:44, src/other_pkg/src/other_node.cpp:210]
updated_from_sha: 35fa8a8       # REPO notes ONLY (staleness tracking); OMITTED on ros2-standard notes
standard_ref: REP-2004          # ros2-standard notes ONLY
---
```
`status` has no gate — every note counts except `rejected` (the human kill-switch). `verified` is an optional "a human checked this" marker.

## Steps

### 0. Gate: confirm this is a ROS2 repo

```sh
ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "not a git repo"; exit 1; }
[ -n "$(find "$ROOT" -name package.xml -not -path '*/node_modules/*' -print -quit 2>/dev/null)" ] && echo "ros2-repo: yes" || echo "ros2-repo: no"
```
Only continue on `ros2-repo: yes`; otherwise point the user at `/review-swarm` or `/code-review`.

### 1. Resolve vault + repo identity (all modes)

The workflow JS sandbox can't read env vars or run git — resolve these in the shell and pass them as `args`:

```sh
VAULT="${CLAUDE_OBSIDIAN_VAULT:-$HOME/.claude/obsidian_vault}/conventions"
REPO=$(basename "$ROOT")
SHA=$(git rev-parse --short HEAD)
mkdir -p "$VAULT"
```

### 2. Pick the mode

- If the invocation args are exactly `learn`, `review`, or `audit`, use that as `mode` verbatim (default `review`).
- User asks to **learn / (re)build / curate conventions**, or the vault has no `<repo>/` folder yet → **`learn`** (do this before the first review of a new repo).
- User asks to **review a PR/branch/diff for conventions** → **`review`** (default). **NEVER run `learn` as part of a review** — a review only *reads* the existing vault notes for the repo. If `$VAULT/<repo>` is empty or missing, proceed with the checkers' own-knowledge fallback (they warn), and tell the user the vault is empty and that they can run `learn` separately to populate it. Do not kick off `learn` on their behalf during a review.
- User asks whether the **vault is stale / evidence still valid** → **`audit`**.

### 3. Scope (review mode)

Same rules as `/review-swarm`:
- No args → `origin/main...HEAD`. Path/glob → still vs origin/main, note the path. Ref range → verbatim. `#123`/PR → `gh pr checkout`, then `origin/main...HEAD`. "uncommitted/staged" → `""`.
```sh
git fetch --quiet origin 2>/dev/null
BASE=origin/main; git rev-parse --verify --quiet origin/main >/dev/null || BASE=origin/master
RANGE="$BASE...HEAD"
git --no-pager diff --name-only "$RANGE"   # sanity-check non-empty
git rev-parse --abbrev-ref HEAD            # branch, for the report filename
```
Empty diff → nothing to review; stop.

### 4. Run the workflow

- `scriptPath`: `/home/bjax/.claude/skills/convention-review/convention-review.workflow.js`
- `args` (JSON **object**): always pass `vaultPath`, `repo`, `sha`. Add `mode` (omit for review), `range`, `scope`, `priorReviewPath` as relevant.

Learn:
```json
{ "scriptPath": ".../convention-review.workflow.js",
  "args": { "mode": "learn", "vaultPath": "/home/bjax/Documents/Base/Claude/conventions", "repo": "myrepo", "sha": "35fa8a8" } }
```
Review (default), optionally chained after a `/review-swarm` report:
```json
{ "scriptPath": ".../convention-review.workflow.js",
  "args": { "vaultPath": "/home/bjax/Documents/Base/Claude/conventions", "repo": "myrepo", "sha": "35fa8a8",
            "range": "origin/main...HEAD", "scope": "branch feat/x vs origin/main",
            "priorReviewPath": "~/claude-reviews/2026-07-22/review-swarm-feat-x-....md" } }
```
Audit:
```json
{ "scriptPath": ".../convention-review.workflow.js",
  "args": { "mode": "audit", "vaultPath": "/home/bjax/Documents/Base/Claude/conventions", "repo": "myrepo" } }
```

Runs in the background; wait for the completion notification, then read the returned object.
- `learn` / `audit` → `counts` (created/updated/stale, or checked/rotted/marked_stale). Report the counts and the vault path; the vault files are the deliverable.
- `review` → `scope`, `range`, `counts` (`raw`/`deduped`/`confirmed`/`rejected`/`by_severity`), `report_markdown`, `confirmed_titles`.

### 5. Report (review mode)

1. **Write** `report_markdown` to `~/claude-reviews/<YYYY-MM-DD>/convention-review-<branch>-<YYYYMMDD-HHMM>.md` (create the day folder; sanitize `/`→`-` in the branch).
2. **Concise terminal summary** — severity tally, confirmed/rejected counts, the TL;DR, `confirmed_titles`, and the saved path. Don't paste the whole report.
3. Offer next steps (apply fixes, promote/reject vault notes) but don't act without the user.

## Notes

- **Vault > re-mining.** `review` and the holistic pass consume vault notes and are told NOT to re-mine the repo — only to open a sibling file to confirm a specific deviation. **A review never runs `learn`.** Refreshing the vault via `learn` is always a separate, explicit action the user requests — do it when conventions drift or when `audit` flags many stale notes, never automatically as part of a review.
- **Env var.** Conventions live under `$CLAUDE_OBSIDIAN_VAULT/conventions` (your Obsidian vault — already exported in your rc as `$OBSIDIAN_VAULT/Claude`), or `~/.claude/obsidian_vault/conventions` when the var is unset (untracked). Always a `conventions/` subfolder so it doesn't clutter the vault root.
- **Non-destructive learn.** Re-running `learn` adds new `proposed` notes, refreshes evidence, bumps `updated_from_sha`, and marks vanished conventions `stale` — it never overwrites a `verified`/`rejected` or hand-edited note.
- **Conventions/fit, not bugs.** Pair with `/review-swarm` (correctness/security). Chaining works well: `/review-swarm` first, then pass its report as `priorReviewPath`.
- To change dimensions, the note schema, or the holistic model, edit `convention-review.workflow.js` next to this file and re-run — `scriptPath` always reads the latest from disk.
