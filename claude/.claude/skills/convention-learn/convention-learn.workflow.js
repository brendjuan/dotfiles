export const meta = {
  name: 'convention-learn',
  description: 'Build/refresh (learn) and freshness-check (audit) the on-disk repo+ROS2 convention vault that convention-review consumes',
  phases: [
    { title: 'Learn', detail: 'agents mine the repo + ROS2 and write one-rule-per-note into the vault' },
    { title: 'Index', detail: 'write the per-repo _index.md dashboard' },
    { title: 'Audit', detail: 'grep-check each repo note\'s evidence still exists; flag drifted notes stale' },
  ],
}

const ARGS = (typeof args === 'string') ? JSON.parse(args) : (args || {})
const MODE = ARGS.mode || 'learn' // 'learn' | 'audit'
const VAULT = ARGS.vaultPath || '' // resolved by the skill (env var or default)
const REPO = ARGS.repo || 'repo' // basename of the repo root — the per-repo vault folder
const SHA = ARGS.sha || '' // short HEAD sha, stamped onto repo notes for staleness tracking

if (!VAULT) throw new Error('convention-learn: requires args.vaultPath')

const REPO_DIR = `${VAULT}/${REPO}`
const ROS_DIR = `${VAULT}/ros2-standards`

// NOTE: dimension keys are the shared contract with convention-review (they name the vault folders). Keep them in sync.
const DIMENSIONS = [
  {
    key: 'package-metadata',
    focus: `package.xml conventions: format version, <export><build_type>, depend ordering & kinds (build/exec/test), maintainer/license/version fields, test deps (ament_* / python3-pytest), version consistency across packages, changelog presence. Learn how sibling packages declare theirs.`,
  },
  {
    key: 'ros-interfaces',
    focus: `.action/.msg/.srv conventions: the repo's action/result error-handling convention (error code + message fields, a success sentinel, error-code numbering & priority ordering), field naming/types, CMakeLists rosidl_generate_interfaces wiring, constants-before-fields ordering, header/timestamp fields on state msgs. Fold in ROS2 REP-2004 / interface naming (CamelCase types, snake_case fields, CONSTANT_CASE constants) and builtin_interfaces usage.`,
  },
  {
    key: 'node-implementation',
    focus: `node code idioms: main() entrypoint + executor shutdown order, named QoS profiles (not bare depth ints), generate_parameter_library usage (static vs dynamic, cached params struct, post-set callback, no 'as' alias), on_ callback naming, leading-underscore rules, diagnostics REP-107 (hardware_id, colon-separated names, namespaced diagnostic prefixes), logging idioms, callback groups/executors, action-server lifecycle. Learn from sibling nodes across the repo's packages.`,
  },
  {
    key: 'launch-files',
    focus: `launch.py conventions: DeclareLaunchArgument + namespace handling (namespace inheritance through IncludeLaunchDescription), params_file override layering applied uniformly, composable vs standard nodes, LaunchConfiguration/substitution usage, event handlers, respawn. Learn from sibling launch files repo-wide.`,
  },
  {
    key: 'build-ci-docker',
    focus: `build/CI/Docker conventions: the repo's task-runner set & structure (build/test/lint/format/docker targets), the CI workflow shape (the repo's colcon build toolchain, build-before-test ordering, container/image-build jobs), Dockerfile conventions (STOPSIGNAL SIGINT for ROS containers, base images, package-manager usage), any image-bake/compose files, GitHub Actions step style. Learn from the sibling CI workflows and Dockerfiles.`,
  },
  {
    key: 'tests',
    focus: `test conventions: pytest-bdd layout (test/features/*.feature + steps/tests), given_/when_/then_ step naming, fixture scoping (session vs function), ament test wiring, unit-test placement & naming, Catch2 tag taxonomy for C++ scenarios. Learn how sibling packages structure and NAME their tests.`,
  },
  {
    key: 'python-style-structure',
    focus: `python-style + code-style + comment-style rules (top-level imports, no leading underscores except sanctioned, no section/separator comments, doc-comment style, avoid redundancy, on_ naming, prefer library APIs over hand-rolled), plus ament_python package structure (setup.py/setup.cfg/resource marker/__init__), file & directory naming.`,
  },
]

const LEARN_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['dimension', 'created', 'updated', 'stale', 'notes'],
  properties: {
    dimension: { type: 'string' },
    created: { type: 'integer' },
    updated: { type: 'integer' },
    stale: { type: 'integer' },
    notes: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        required: ['id', 'path', 'scope', 'status'],
        properties: {
          id: { type: 'string' },
          path: { type: 'string' },
          scope: { type: 'string', enum: ['repo', 'ros2-standard'] },
          status: { type: 'string' },
        },
      },
    },
  },
}

const AUDIT_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['dimension', 'checked', 'rotted', 'marked_stale'],
  properties: {
    dimension: { type: 'string' },
    checked: { type: 'integer' },
    rotted: { type: 'integer' },
    marked_stale: { type: 'integer' },
    details: { type: 'array', items: { type: 'string' } },
  },
}

const NOTE_FORMAT = `Note file format (YAML frontmatter + one paragraph of prose):
---
id: <slug>                      # MUST equal the filename stem; kebab-case; stable across runs
dimension: <dimension>
status: proposed                # proposed | verified | rejected | stale
severity_default: low           # high|medium|low|nit — the weight a deviation from this rule usually deserves
source: repo-pattern            # repo-pattern | repo-rule-file | ros2-standard
evidence:                       # >=2 entries
  - <file:line>                 # repo notes: real file:line proving the pattern
  - <file:line>
updated_from_sha: <SHA>         # REPO notes ONLY (source repo-pattern|repo-rule-file). OMIT for ros2-standard notes.
standard_ref: <REP-xxxx|rclpy>  # ros2-standard notes ONLY. OMIT for repo notes.
---
<One paragraph stating the rule so a human can read and verify it. Optionally a short example. Link related notes with [[other-id]].>`

function learnPrompt(d) {
  return `You are an expert in ROS2 (ament, rclpy, REP standards) AND in THIS repository's conventions. You are CURATING an on-disk convention vault — NOT reviewing a PR.

Dimension: "${d.key}"
Focus:
${d.focus}

VAULT — write plain-markdown notes, ONE RULE PER FILE, into these folders (create with \`mkdir -p\` if missing):
- Repo-specific conventions            -> ${REPO_DIR}/${d.key}/<slug>.md   (stamp updated_from_sha=${SHA})
- ROS2 / dependency-idiom conventions  -> ${ROS_DIR}/${d.key}/<slug>.md    (repo-independent — NO sha)

STEP 1 — READ FIRST. Glob and read every existing note in BOTH folders above so you never duplicate or clobber prior work.

STEP 2 — MINE conventions for this dimension:
- Read the authoritative repo rules in .claude/rules/*.md.
- Grep/read MANY sibling packages to capture DE-FACTO patterns, including unstated "everyone here just does it this way" ones (that is the whole point). Sample widely.
- Fold in real ROS2 standards (REPs, ament, rclpy/rosidl idioms) for this dimension.
- Each convention must be a CHECKABLE rule backed by >=2 concrete file:line citations (repo) OR a REP/ament reference (standard). Skip anything you cannot evidence.

STEP 3 — WRITE / RECONCILE one note per rule.
${NOTE_FORMAT}

RECONCILIATION (STRICTLY non-destructive — humans read and hand-edit these):
- Match existing notes by id (== filename stem).
- If an existing note has status 'verified' or 'rejected', or its body looks hand-edited: DO NOT change its body or status. You MAY refresh its 'evidence:' list and (repo notes only) bump 'updated_from_sha' to ${SHA} if the pattern still holds.
- If status is 'proposed': you may update evidence, prose, and bump updated_from_sha.
- Never delete a note. If a previously-recorded convention no longer has any supporting evidence in the repo, set its status to 'stale' (leave 'rejected' notes untouched).
- Repo notes: source repo-pattern|repo-rule-file, updated_from_sha=${SHA}, NO standard_ref.
- ros2-standard notes: source ros2-standard, standard_ref set, NO updated_from_sha.
- Pick slugs that read well (e.g. named-qos-profiles, error-codes-from-10000, stopsignal-sigint).

Do NOT review any PR. Return the counts and the list of notes you created/updated/marked-stale.`
}

function auditPrompt(d) {
  return `You are auditing the FRESHNESS of the convention vault for dimension "${d.key}". This is mechanical — use Bash/git, not judgement calls.

Scope: repo notes only -> ${REPO_DIR}/${d.key}/*.md (ros2-standard notes are repo-independent; skip them).

For each note:
1. Read its frontmatter 'evidence:' entries. For each 'file:line', check the file still exists and has at least that many lines (\`git show HEAD:<file>\` / wc -l, or test -f + sed -n).
2. If NONE of a note's evidence entries resolve anymore, the convention has likely drifted: set that note's 'status: stale' (edit frontmatter only; never touch the body). Skip notes already 'rejected' or 'stale'.
3. Report how far behind HEAD each note's 'updated_from_sha' is if easily available (informational only; do not edit for that alone).

Return counts: notes checked, notes with rotted evidence, notes you marked stale, plus a short details list.`
}

// ============================ AUDIT ============================
if (MODE === 'audit') {
  log(`AUDIT → ${REPO_DIR}`)
  phase('Audit')
  const results = (await parallel(
    DIMENSIONS.map((d) => () => agent(auditPrompt(d), { label: `audit:${d.key}`, phase: 'Audit', schema: AUDIT_SCHEMA }))
  )).filter(Boolean)

  const checked = results.reduce((n, r) => n + (r.checked || 0), 0)
  const rotted = results.reduce((n, r) => n + (r.rotted || 0), 0)
  const marked = results.reduce((n, r) => n + (r.marked_stale || 0), 0)
  log(`AUDIT done: ${checked} notes checked, ${rotted} with rotted evidence, ${marked} marked stale`)
  return {
    mode: 'audit',
    vault: VAULT,
    repo: REPO,
    counts: { checked, rotted, marked_stale: marked },
    details: results.flatMap((r) => r.details || []),
  }
}

// ============================ LEARN (default) ============================
log(`LEARN → vault ${REPO_DIR} (+ ${ROS_DIR}) @ ${SHA || 'no-sha'}`)
phase('Learn')
const results = (await parallel(
  DIMENSIONS.map((d) => () => agent(learnPrompt(d), { label: `learn:${d.key}`, phase: 'Learn', schema: LEARN_SCHEMA }))
)).filter(Boolean)

const created = results.reduce((n, r) => n + (r.created || 0), 0)
const updated = results.reduce((n, r) => n + (r.updated || 0), 0)
const stale = results.reduce((n, r) => n + (r.stale || 0), 0)
const allNotes = results.flatMap((r) => r.notes || [])

phase('Index')
await agent(
  `Write/refresh the vault index at ${REPO_DIR}/_index.md — a human dashboard for this repo's conventions.
Glob ${REPO_DIR}/*/*.md and ${ROS_DIR}/*/*.md, read each note's frontmatter, and write a Markdown table grouped by dimension listing: id, status, severity_default, source, and (repo notes) updated_from_sha. Add a top line with total counts by status. Overwrite _index.md. Return the word "done".`,
  { label: 'index', phase: 'Index' }
)

log(`LEARN done: +${created} new, ~${updated} updated, ${stale} marked stale across ${results.length}/${DIMENSIONS.length} dimensions`)
return {
  mode: 'learn',
  vault: VAULT,
  repo: REPO,
  sha: SHA,
  counts: { created, updated, stale, notes: allNotes.length },
  notes: allNotes,
}
