---
name: convention-learn
description: Build/refresh the on-disk repo+ROS2 convention vault that convention-review consumes (mode learn, default), and freshness-check it (mode audit). learn mines the whole repo + ROS2 standards per dimension and writes one-rule-per-note markdown, reconciled non-destructively; audit greps each note's evidence and flags drifted notes stale. Use for ROS2 (ament/colcon) repos when the user wants to (re)learn/curate conventions or check whether the vault is stale. To review a PR against the vault, use convention-review instead.
---

# Convention Learn

Curates the on-disk **convention vault** — the backbone `convention-review` reads. Two modes, run through the **Workflow** engine:

- **`learn`** (default) — one agent per dimension mines the repo (+ ROS2 REPs/ament/rclpy) and writes/reconciles **one-rule-per-note** markdown into the vault, then refreshes `_index.md`. Non-destructive: never clobbers a `verified`/`rejected` or hand-edited note; marks conventions whose evidence vanished `stale`.
- **`audit`** — mechanical grep/git pass: for each repo note, checks its `evidence:` file:line still exists and marks drifted notes `status: stale`.

Dimensions: `package-metadata`, `ros-interfaces`, `node-implementation`, `launch-files`, `build-ci-docker`, `tests`, `python-style-structure`. Invoking this skill **authorizes the Workflow tool**.

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
`verified` is an optional human "I checked this" marker; `rejected` is the human kill-switch (never re-touched, and excluded by review).

## Steps

### 0. Gate: confirm this is a ROS2 repo

```sh
ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "not a git repo"; exit 1; }
[ -n "$(find "$ROOT" -name package.xml -not -path '*/node_modules/*' -print -quit 2>/dev/null)" ] && echo "ros2-repo: yes" || echo "ros2-repo: no"
```
Only continue on `ros2-repo: yes`.

### 1. Resolve vault + repo identity

The workflow JS sandbox can't read env vars or run git — resolve these in the shell and pass them as `args`:

```sh
VAULT="${CLAUDE_OBSIDIAN_VAULT:-$HOME/.claude/obsidian_vault}/conventions"
# Repo identity comes from the git remote name, NOT the checkout directory (they often differ).
REPO=$(basename -s .git "$(git -C "$ROOT" config --get remote.origin.url 2>/dev/null)")
[ -z "$REPO" ] && REPO=$(basename "$ROOT")   # fallback: no remote → directory name
SHA=$(git rev-parse --short HEAD)
mkdir -p "$VAULT"
```

### 2. Pick the mode

- **`learn`** (default) — user wants to build/rebuild/refresh/curate conventions, or the vault has no `<repo>/` folder yet. If the args are exactly `learn`, use it verbatim.
- **`audit`** — user wants to check the vault is fresh / evidence still valid. If the args are exactly `audit`, use it verbatim.

### 3. Run the workflow

- `scriptPath`: `/home/bjax/.claude/skills/convention-learn/convention-learn.workflow.js`
- `args` (JSON **object**):
  - always `vaultPath`, `repo`, `sha`;
  - add `mode: "audit"` for an audit (omit for learn);
  - optional `model` (`sonnet` | `opus` | `haiku` | `fable`) — the model the worker agents (mining/index/audit) run on. Omit to inherit the session model. The orchestrator (this main loop) is unaffected — it always runs on the session model. If the user names a worker model (e.g. "mine with sonnet"), pass it here; do **not** edit the script.

```json
{ "scriptPath": ".../convention-learn.workflow.js",
  "args": { "vaultPath": "/home/bjax/Documents/Base/Claude/conventions", "repo": "myrepo", "sha": "35fa8a8", "model": "sonnet" } }
```

Runs in the background; on the completion notification read the returned object:
- `learn` → `counts` (created/updated/stale/notes).
- `audit` → `counts` (checked/rotted/marked_stale) + `details`.

Report the counts and the vault path; the vault files are the deliverable. Point the user at `convention-review` to review a PR against what was learned.

## Notes

- **Env var.** Conventions live under `$CLAUDE_OBSIDIAN_VAULT/conventions` (your Obsidian vault — already exported in your rc as `$OBSIDIAN_VAULT/Claude`), or `~/.claude/obsidian_vault/conventions` when unset (untracked). Always a `conventions/` subfolder.
- **Non-destructive.** Re-running `learn` adds new `proposed` notes, refreshes evidence, bumps `updated_from_sha`, and marks vanished conventions `stale` — never overwriting a `verified`/`rejected` or hand-edited note.
- **`learn` runs only on explicit request** — never automatically as part of a review. `convention-review` reads the vault; it does not build it.
- **Dimension keys are a shared contract** with `convention-review` (they name the vault folders). If you change them here, change them there too.
- **Model routing.** All worker agents share one model, set by `args.model` (default: inherit the session model). There is no per-dimension override — mining is uniform work, so a single knob is the right granularity. The orchestrator stays on the session model regardless.
