export const meta = {
  name: 'convention-review',
  description: 'Curate a repo+ROS2 convention vault on disk, then review a PR against it (adversarially verified)',
  phases: [
    { title: 'Learn', detail: 'agents mine the repo + ROS2 and write one-rule-per-note into the convention vault' },
    { title: 'Check', detail: 'per-dimension reviewers + a holistic Fable pass check the PR against the vault notes' },
    { title: 'Verify', detail: 'adversarial verifiers re-check each finding against the real code' },
    { title: 'Distill', detail: 'lead synthesizes confirmed findings into a report' },
    { title: 'Audit', detail: 'grep-check each repo note\'s evidence still exists; flag drifted notes stale' },
  ],
}

const ARGS = (typeof args === 'string') ? JSON.parse(args) : (args || {})
const MODE = ARGS.mode || 'review' // 'learn' | 'review' | 'audit'
const RANGE = ARGS.range || 'origin/main...HEAD'
const PRIOR = ARGS.priorReviewPath || ''
const SCOPE = ARGS.scope || RANGE
const VAULT = ARGS.vaultPath || '' // resolved by the skill (env var or default); the on-disk convention backbone
const REPO = ARGS.repo || 'repo' // basename of the repo root — the per-repo vault folder
const SHA = ARGS.sha || '' // short HEAD sha, stamped onto repo notes for staleness tracking

const DIFF_CMD = RANGE ? `git --no-pager diff ${RANGE}` : 'git --no-pager diff'
const FILES_CMD = RANGE ? `git --no-pager diff --name-only ${RANGE}` : 'git --no-pager diff --name-only'

const REPO_DIR = VAULT ? `${VAULT}/${REPO}` : ''
const ROS_DIR = VAULT ? `${VAULT}/ros2-standards` : ''

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

const FINDINGS_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['findings'],
  properties: {
    findings: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        required: ['title', 'severity', 'file', 'line', 'convention', 'convention_evidence', 'deviation', 'fix', 'overlaps_prior'],
        properties: {
          title: { type: 'string' },
          severity: { type: 'string', enum: ['high', 'medium', 'low', 'nit'] },
          file: { type: 'string' },
          line: { type: 'integer' },
          convention: { type: 'string', description: 'the vault note id it violates + a short restatement of the rule' },
          convention_evidence: { type: 'array', items: { type: 'string' }, description: 'file:line proof the convention is real & established elsewhere (from the note)' },
          deviation: { type: 'string', description: 'how the PR deviates, concretely' },
          fix: { type: 'string' },
          overlaps_prior: { type: 'boolean', description: 'true if this substantially overlaps a finding in the prior review' },
        },
      },
    },
  },
}

const VERDICT_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['verdict', 'reason'],
  properties: {
    verdict: { type: 'string', enum: ['confirmed', 'false-positive', 'uncertain'] },
    reason: { type: 'string' },
    corrected_severity: { type: 'string', enum: ['high', 'medium', 'low', 'nit'] },
    is_convention_not_style_opinion: { type: 'boolean', description: 'true only if this is a real established-convention deviation, not the reviewer\'s personal taste' },
  },
}

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

// ---- Shared note-format spec, embedded in learn prompts ----
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

const priorNote = PRIOR
  ? `\n\nA PRIOR review exists at ${PRIOR} — Read it. You may still report an overlapping convention deviation, but set overlaps_prior=true for those and PRIORITIZE new/unstated convention issues the prior review missed.`
  : ''

function vaultReadNote(dim) {
  return `AUTHORITATIVE CONVENTIONS live in the on-disk vault. Read them now (glob + read every file):
- ${REPO_DIR}/${dim}/*.md
- ${ROS_DIR}/${dim}/*.md
Treat these notes as the source of truth. SKIP any note whose frontmatter has 'status: rejected'. Do NOT re-mine the repo to rediscover conventions — only open a specific sibling file when you must confirm a suspected deviation. If both folders are empty or missing, say so in your reasoning and fall back to your own ROS2 + repo knowledge for this dimension.`
}

function checkPrompt(d) {
  return `You are reviewing a PR for adherence to ESTABLISHED conventions for the dimension "${d.key}".

${vaultReadNote(d.key)}

Task:
- List the PR's changed files: \`${FILES_CMD}\`; inspect the diff: \`${DIFF_CMD}\`.
- For files relevant to "${d.key}", find DEVIATIONS from the vault conventions (and standard ROS2 idioms).
- Report ONLY real deviations from an established convention — not personal taste. For each finding, put the violated vault note's id (plus a short restatement) in 'convention', its evidence in 'convention_evidence', and the exact PR 'file'/'line'.
- Prefer NEW/unstated issues; still valid to report known ones (mark overlaps_prior).${priorNote}

Read the actual files to confirm line numbers. Be precise and skeptical — a weak finding hurts the review.`
}

function holisticPrompt() {
  return `You are a senior ROS2 engineer doing a HOLISTIC convention-adherence review of a PR. Your edge is cross-cutting, unstated, "everyone here just does it this way" conventions that per-dimension reviewers miss — naming parallelism, structural symmetry, idiomatic consistency between analogous files.

The on-disk convention vault is your reference. Read across ALL dimensions for this repo (glob + read):
- ${REPO_DIR}/*/*.md   and   ${ROS_DIR}/*/*.md
SKIP notes with 'status: rejected'. Do NOT re-mine the repo to rediscover conventions the vault already records — only open a sibling file to confirm a specific suspected deviation, or to establish a genuinely cross-cutting norm the vault is missing.

Method:
- Enumerate changed files: \`${FILES_CMD}\`; read the diff: \`${DIFF_CMD}\`.
- Flag where the PR diverges from a vault note (cite its id) OR from a cross-cutting norm you can evidence in 2+ sibling files. No personal taste.${priorNote}

Put the vault note id (or "unstated" for a new cross-cutting norm) in 'convention', evidence in 'convention_evidence', and the exact PR file:line. Be precise.`
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

// ============================ LEARN ============================
if (MODE === 'learn') {
  if (!VAULT) throw new Error('convention-review: learn mode requires args.vaultPath')
  log(`LEARN → vault ${REPO_DIR} (+ ${ROS_DIR}) @ ${SHA || 'no-sha'}`)
  phase('Learn')
  const results = (await parallel(
    DIMENSIONS.map((d) => () => agent(learnPrompt(d), { label: `learn:${d.key}`, phase: 'Learn', schema: LEARN_SCHEMA }))
  )).filter(Boolean)

  const created = results.reduce((n, r) => n + (r.created || 0), 0)
  const updated = results.reduce((n, r) => n + (r.updated || 0), 0)
  const stale = results.reduce((n, r) => n + (r.stale || 0), 0)
  const allNotes = results.flatMap((r) => r.notes || [])

  phase('Distill')
  await agent(
    `Write/refresh the vault index at ${REPO_DIR}/_index.md — a human dashboard for this repo's conventions.
Glob ${REPO_DIR}/*/*.md and ${ROS_DIR}/*/*.md, read each note's frontmatter, and write a Markdown table grouped by dimension listing: id, status, severity_default, source, and (repo notes) updated_from_sha. Add a top line with total counts by status. Overwrite _index.md. Return the word "done".`,
    { label: 'index', phase: 'Distill' }
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
}

// ============================ AUDIT ============================
if (MODE === 'audit') {
  if (!VAULT) throw new Error('convention-review: audit mode requires args.vaultPath')
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

// ============================ REVIEW (default) ============================
if (!VAULT) {
  log('WARNING: no vaultPath provided — checkers will fall back to mining their own knowledge (no vault backbone).')
}
phase('Check')
const checkThunks = DIMENSIONS.map((d) => () =>
  agent(checkPrompt(d), { label: `check:${d.key}`, phase: 'Check', schema: FINDINGS_SCHEMA })
)
checkThunks.push(() =>
  agent(holisticPrompt(), { label: 'check:holistic-fable', phase: 'Check', schema: FINDINGS_SCHEMA, model: 'fable' })
)
const rawFindings = (await parallel(checkThunks)).filter(Boolean).flatMap((r) => r.findings || [])

const norm = (s) => (s || '').toLowerCase().replace(/[^a-z0-9]+/g, ' ').trim().slice(0, 50)
const byKey = new Map()
for (const f of rawFindings) {
  const k = `${f.file}::${norm(f.title)}`
  if (!byKey.has(k)) byKey.set(k, { ...f, dupes: 1 })
  else byKey.get(k).dupes++
}
const deduped = [...byKey.values()]
log(`${rawFindings.length} raw findings -> ${deduped.length} after dedup`)

phase('Verify')
const verified = await parallel(
  deduped.map((f) => () =>
    agent(
      `Adversarially VERIFY this convention-deviation finding against the real code. Default to skepticism — reject unless you can independently confirm BOTH halves.

Finding:
- title: ${f.title}
- severity(claimed): ${f.severity}
- PR location: ${f.file}:${f.line}
- claimed convention (vault note id + rule): ${f.convention}
- convention evidence (elsewhere): ${JSON.stringify(f.convention_evidence)}
- deviation: ${f.deviation}
- fix: ${f.fix}

Checks:
1. Is the convention REAL and ESTABLISHED? Read the cited evidence file:line (and, if given, the vault note). Is it a genuine repo-wide pattern / rule / ROS2 standard — or one example / the reviewer's taste? If taste, set is_convention_not_style_opinion=false and verdict=false-positive.
2. Does the PR ACTUALLY deviate at ${f.file}:${f.line}? Read it. If the PR actually follows the convention, or the claim/line is wrong, verdict=false-positive.
3. Correct the severity if over/under-stated (convention deviations are rarely above medium unless they break the build or a contract).

Return confirmed only if BOTH the convention and the deviation hold up.`,
      { label: `verify:${f.file.split('/').pop()}:${f.line}`, phase: 'Verify', schema: VERDICT_SCHEMA }
    ).then((v) => ({ ...f, verdict: v }))
  )
)

const confirmed = verified.filter(Boolean).filter((f) => f.verdict?.verdict === 'confirmed' && f.verdict?.is_convention_not_style_opinion !== false)
const rejected = verified.filter(Boolean).filter((f) => !(f.verdict?.verdict === 'confirmed' && f.verdict?.is_convention_not_style_opinion !== false))
for (const f of confirmed) { if (f.verdict?.corrected_severity) f.severity = f.verdict.corrected_severity }

const sevRank = { high: 0, medium: 1, low: 2, nit: 3 }
confirmed.sort((a, b) => (sevRank[a.severity] - sevRank[b.severity]))

phase('Distill')
const report = await agent(
  `You are the lead reviewer. Write a Markdown convention-adherence review report for this PR.

Scope: ${SCOPE}
Reviewed against the on-disk convention vault: ${VAULT || '(none — reviewers used their own knowledge)'} (repo folder: ${REPO}, learned @ ${SHA || 'unknown'}).
This is a CONVENTIONS-focused review: does the PR adhere to the repo's established (including unstated) conventions and ROS2 idioms?

CONFIRMED findings (JSON):
${JSON.stringify(confirmed.map((f) => ({ title: f.title, severity: f.severity, file: f.file, line: f.line, convention: f.convention, convention_evidence: f.convention_evidence, deviation: f.deviation, fix: f.fix, overlaps_prior: f.overlaps_prior, verifier_reason: f.verdict?.reason })), null, 2)}

REJECTED (for the "Filtered out" section, brief):
${JSON.stringify(rejected.map((f) => ({ title: f.title, file: f.file, line: f.line, why: f.verdict?.reason })), null, 2)}

Write the report with:
- "# Convention Review Report"
- "## TL;DR" — 4-8 sentences: overall convention health, the most important deviations, and whether they are NEW vs overlapping the prior review. End with a one-line severity tally.
- "## Findings" grouped by severity (High/Medium/Low/Nits). For each: bold title, then \`file:line\`, then a paragraph stating the established convention, how the PR deviates, and the fix. When 'convention' names a vault note id, link it as [[id]] so a human can jump to the rule. Mark "(overlaps prior review)" where overlaps_prior is true, else "(NEW)".
- "## Filtered out" — the rejected findings, one line each with why.
Be precise and cite file:line throughout. Return ONLY the markdown.`,
  { label: 'distill', phase: 'Distill' }
)

const by_severity = { high: 0, medium: 0, low: 0, nit: 0 }
for (const f of confirmed) by_severity[f.severity]++

return {
  mode: 'review',
  scope: SCOPE,
  range: RANGE,
  vault: VAULT,
  counts: { raw: rawFindings.length, deduped: deduped.length, confirmed: confirmed.length, rejected: rejected.length, by_severity },
  report_markdown: report,
  confirmed_titles: confirmed.map((f) => `[${f.severity}] ${f.file}:${f.line} — ${f.title}${f.overlaps_prior ? ' (overlaps prior)' : ' (NEW)'}`),
}
