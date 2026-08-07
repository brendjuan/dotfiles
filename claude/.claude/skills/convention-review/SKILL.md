---
name: convention-review
description: Review a PR/branch/diff for adherence to a ROS2 repo's established conventions, checked against the on-disk convention vault built by convention-learn. Per-dimension reviewers + a holistic Fable pass flag deviations, adversarial verifiers reject personal-taste/false-positive findings, and a lead distills a Markdown report. NEVER mines/learns conventions itself — it only reads the vault. Use when the user asks whether a branch/diff/PR follows the repo's conventions or idioms, or runs /convention-review. For correctness/security review prefer /review-swarm or /code-review; to build/refresh the vault use convention-learn.
---

# Convention Review

Checks a PR against the on-disk **convention vault** (built by `convention-learn`) — a *fit* review, not a bug hunt. Three stages through the **Workflow** engine:

1. **Check** — per-dimension reviewers + a holistic **Fable** pass read the vault notes as the source of truth and flag PR deviations. **They never re-mine the repo to (re)learn conventions** — only read a sibling file to confirm a specific deviation.
2. **Verify** — findings are deduped and each is adversarially re-checked against the real code, rejecting personal taste / false positives.
3. **Distill** — a lead synthesizes confirmed findings into a Markdown report with a `## TL;DR`.

Invoking this skill **authorizes the Workflow tool**.

## Steps

### 0. Gate: confirm this is a ROS2 repo

```sh
ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "not a git repo"; exit 1; }
[ -n "$(find "$ROOT" -name package.xml -not -path '*/node_modules/*' -print -quit 2>/dev/null)" ] && echo "ros2-repo: yes" || echo "ros2-repo: no"
```
Only continue on `ros2-repo: yes`; otherwise point the user at `/review-swarm` or `/code-review`.

### 1. Resolve vault, repo identity, and scope

```sh
VAULT="${CLAUDE_OBSIDIAN_VAULT:-$HOME/.claude/obsidian_vault}/conventions"
ROOT=$(git rev-parse --show-toplevel); SHA=$(git rev-parse --short HEAD)
# Repo identity comes from the git remote name, NOT the checkout directory (they often differ) — must match convention-learn.
REPO=$(basename -s .git "$(git -C "$ROOT" config --get remote.origin.url 2>/dev/null)")
[ -z "$REPO" ] && REPO=$(basename "$ROOT")   # fallback: no remote → directory name
git fetch --quiet origin 2>/dev/null
BASE=origin/main; git rev-parse --verify --quiet origin/main >/dev/null || BASE=origin/master
RANGE="$BASE...HEAD"
git rev-parse --abbrev-ref HEAD                                   # branch, for the report filename
FILES=$(git --no-pager diff --name-only "$RANGE" | grep -c .)     # changed-file count
LINES=$(git --no-pager diff "$RANGE" | grep -cE '^[+-]')          # +/- line count
```
Scope rules (like `/review-swarm`): no args → `origin/main...HEAD`; path/glob → still vs origin/main, note the path; ref range → verbatim; `#123`/PR → `gh pr checkout`, then `origin/main...HEAD`; "uncommitted/staged" → `""`. Empty diff (`FILES` = 0) → nothing to review; stop.

**Never run `convention-learn` from here.** If `$VAULT/<repo>` is empty/missing, proceed with the checkers' own-knowledge fallback (they warn) and tell the user to run `convention-learn` separately to populate it — do not build the vault on their behalf.

### 2. Run the workflow

- `scriptPath`: `/home/bjax/.claude/skills/convention-review/convention-review.workflow.js`
- `args` (JSON **object**): `vaultPath`, `repo`, `sha`, `range`, `scope`, `changedFiles` (=FILES), `diffLines` (=LINES); optional `priorReviewPath`, `checkAgents`.

```json
{ "scriptPath": ".../convention-review.workflow.js",
  "args": { "vaultPath": "/home/bjax/Documents/Base/Claude/conventions", "repo": "myrepo", "sha": "35fa8a8",
            "range": "origin/main...HEAD", "scope": "branch feat/x vs origin/main",
            "changedFiles": 4, "diffLines": 210,
            "priorReviewPath": "~/claude-reviews/2026-07-22/review-swarm-feat-x-....md" } }
```

- **Fan-out scales with diff size** (pass `changedFiles`/`diffLines`): tiny (≤2 files & ≤60 lines) → 1 agent over all dimensions, holistic folded in; small (≤6 & ≤250) → 3; medium (≤15 & ≤800) → 5; large → full 7 per-dimension + a separate holistic Fable pass. Omit the counts → full fan-out.
- **Honor the user's fan-out request** over the auto-scaling, via `checkAgents` (wins over the buckets):
  - "full" / "thorough" / "per-dimension" → `checkAgents: 7`.
  - "quick" / "single-agent" / "one pass" / "cheap" → `checkAgents: 1`.
  - "N agents" / "split into N" → `checkAgents: N` (clamped 1–7).
  - No depth mentioned → omit it and let the size counts auto-scale.

Runs in the background; on the completion notification read the returned object: `scope`, `range`, `counts` (`raw`/`deduped`/`confirmed`/`rejected`/`by_severity`), `report_markdown`, `confirmed_titles`.

### 3. Report

1. **Write** `report_markdown` to `~/claude-reviews/<YYYY-MM-DD>/convention-review-<branch>-<YYYYMMDD-HHMM>.md` (create the day folder; sanitize `/`→`-` in the branch).
2. **Concise terminal summary** — severity tally, confirmed/rejected counts, the TL;DR, `confirmed_titles`, and the saved path. Don't paste the whole report.
3. Offer next steps (apply fixes; promote/reject vault notes via editing the vault) but don't act without the user.

## Notes

- **Reads the vault, never builds it.** A review never runs `convention-learn`. Refreshing the vault is always a separate, explicit action — do it when conventions drift or `convention-learn audit` flags many stale notes.
- **Env var.** Vault at `$CLAUDE_OBSIDIAN_VAULT/conventions` (default `~/.claude/obsidian_vault/conventions`) — same resolution as `convention-learn`.
- **Conventions/fit, not bugs.** Pair with `/review-swarm` (correctness/security). Chaining works well: `/review-swarm` first, then pass its report as `priorReviewPath`.
- **Dimension keys are a shared contract** with `convention-learn` (they name the vault folders). If you change them here, change them there too.
