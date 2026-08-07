export const meta = {
  name: 'convention-review',
  description: 'Review a PR against the on-disk convention vault (built by convention-learn); adversarially verified',
  phases: [
    { title: 'Check', detail: 'per-dimension reviewers + a holistic Fable pass check the PR against the vault notes' },
    { title: 'Verify', detail: 'adversarial verifiers re-check each finding against the real code' },
    { title: 'Distill', detail: 'lead synthesizes confirmed findings into a report' },
  ],
}

const ARGS = (typeof args === 'string') ? JSON.parse(args) : (args || {})
const RANGE = ARGS.range || 'origin/main...HEAD'
const PRIOR = ARGS.priorReviewPath || ''
const SCOPE = ARGS.scope || RANGE
const VAULT = ARGS.vaultPath || '' // resolved by the skill; the on-disk convention backbone (built by convention-learn)
const REPO = ARGS.repo || 'repo' // canonical repo name (from the git remote, not the checkout dir) — the per-repo vault folder
const SHA = ARGS.sha || '' // short HEAD sha the vault was last learned against (for the report header)

const DIFF_CMD = RANGE ? `git --no-pager diff ${RANGE}` : 'git --no-pager diff'
const FILES_CMD = RANGE ? `git --no-pager diff --name-only ${RANGE}` : 'git --no-pager diff --name-only'

const REPO_DIR = VAULT ? `${VAULT}/${REPO}` : ''
const ROS_DIR = VAULT ? `${VAULT}/ros2-standards` : ''

// NOTE: dimension keys are the shared contract with convention-learn (they name the vault folders). Keep them in sync.
const DIMENSIONS = [
  {
    key: 'package-metadata',
    focus: `package.xml: format version, build_type, depend ordering/kinds, maintainer/license/version, test deps, version consistency, changelog.`,
  },
  {
    key: 'ros-interfaces',
    focus: `.action/.msg/.srv: error-handling convention (code+message, success sentinel, numbering/ordering), field & constant naming, rosidl wiring, header/timestamp fields, REP-2004 naming.`,
  },
  {
    key: 'node-implementation',
    focus: `node code idioms: main()/executor shutdown, named QoS, generate_parameter_library usage, on_ callback naming, leading-underscore rules, diagnostics REP-107, callback groups/executors, action-server lifecycle.`,
  },
  {
    key: 'launch-files',
    focus: `launch.py: DeclareLaunchArgument, namespace inheritance, params_file layering, composable vs standard nodes, substitutions, event handlers, respawn.`,
  },
  {
    key: 'build-ci-docker',
    focus: `Taskfile/CI/Docker: task-runner set & structure, CI job shape (build-before-test, image-build jobs), Dockerfile conventions (STOPSIGNAL SIGINT), bake/compose files, Actions step style.`,
  },
  {
    key: 'tests',
    focus: `tests: pytest-bdd layout, given_/when_/then_ step naming, fixture scoping, ament test wiring, unit-test placement/naming, Catch2 tag taxonomy.`,
  },
  {
    key: 'python-style-structure',
    focus: `python/code/comment style (top-level imports, leading-underscore rules, no section comments, doc-comment style, prefer library APIs), ament_python package structure, file/dir naming.`,
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

const priorNote = PRIOR
  ? `\n\nA PRIOR review exists at ${PRIOR} — Read it. You may still report an overlapping convention deviation, but set overlaps_prior=true for those and PRIORITIZE new/unstated convention issues the prior review missed.`
  : ''

function vaultReadNotesFor(dims) {
  const folders = dims
    .map((d) => `- ${REPO_DIR}/${d.key}/*.md  and  ${ROS_DIR}/${d.key}/*.md   (dimension: ${d.key})`)
    .join('\n')
  return `AUTHORITATIVE CONVENTIONS live in the on-disk vault (built by convention-learn). Read the notes for the dimension(s) you own (glob + read every file):
${folders}
Treat these notes as the source of truth. SKIP any note whose frontmatter has 'status: rejected'. Do NOT re-mine the repo to rediscover conventions — only open a specific sibling file when you must confirm a suspected deviation. If a dimension's folders are empty or missing, say so and fall back to your own ROS2 + repo knowledge for that dimension.`
}

function checkPromptFor(dims, foldHolistic) {
  const focusList = dims.map((d) => `### ${d.key}\n${d.focus}`).join('\n\n')
  const holistic = foldHolistic
    ? `\n\nAlso apply a HOLISTIC lens: catch cross-cutting, unstated "everyone here just does it this way" conventions (naming parallelism, structural symmetry, idiomatic consistency between analogous files) even where they span dimensions.`
    : ''
  return `You are reviewing a PR for adherence to ESTABLISHED conventions for the following dimension(s):

${focusList}

${vaultReadNotesFor(dims)}

Task:
- List the PR's changed files: \`${FILES_CMD}\`; inspect the diff: \`${DIFF_CMD}\`.
- For files relevant to the dimension(s) above, find DEVIATIONS from the vault conventions (and standard ROS2 idioms).
- Report ONLY real deviations from an established convention — not personal taste. For each finding, put the violated vault note's id (plus a short restatement) in 'convention', its evidence in 'convention_evidence', and the exact PR 'file'/'line'.
- Prefer NEW/unstated issues; still valid to report known ones (mark overlaps_prior).${holistic}${priorNote}

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

// Split the dimension list into contiguous groups so a single agent can own several dimensions on a small diff.
function chunkContiguous(arr, n) {
  const groups = Math.max(1, Math.min(n, arr.length))
  const size = Math.ceil(arr.length / groups)
  const out = []
  for (let i = 0; i < arr.length; i += size) out.push(arr.slice(i, i + size))
  return out
}

// How many check agents to fan out, scaled by diff size. args.checkAgents forces it; unknown size -> full per-dimension.
function pickGroupCount() {
  if (Number.isFinite(ARGS.checkAgents) && ARGS.checkAgents > 0) return Math.min(ARGS.checkAgents, DIMENSIONS.length)
  const files = Number.isFinite(ARGS.changedFiles) ? ARGS.changedFiles : null
  const lines = Number.isFinite(ARGS.diffLines) ? ARGS.diffLines : null
  if (files == null && lines == null) return DIMENSIONS.length // unknown -> be thorough
  const f = files == null ? 9999 : files
  const l = lines == null ? 999999 : lines
  if (f <= 2 && l <= 60) return 1 // tiny: one agent covers all dimensions
  if (f <= 6 && l <= 250) return 3 // small
  if (f <= 15 && l <= 800) return 5 // medium
  return DIMENSIONS.length // large: full per-dimension
}

if (!VAULT) {
  log('WARNING: no vaultPath provided — checkers will fall back to mining their own knowledge (run convention-learn to build the vault).')
}

phase('Check')
const nGroups = pickGroupCount()
const groups = chunkContiguous(DIMENSIONS, nGroups)
// A single all-dimensions group (tiny diff) folds the holistic lens in; otherwise the holistic pass runs separately on Fable.
const soloGroup = groups.length === 1
log(`Check fan-out: ${groups.length} group(s) over ${DIMENSIONS.length} dimensions${soloGroup ? ' (holistic folded in)' : ' + holistic(fable)'} — files=${Number.isFinite(ARGS.changedFiles) ? ARGS.changedFiles : '?'} lines=${Number.isFinite(ARGS.diffLines) ? ARGS.diffLines : '?'}`)
const checkThunks = groups.map((dims) => () =>
  agent(checkPromptFor(dims, soloGroup), { label: `check:${dims.map((d) => d.key).join('+')}`, phase: 'Check', schema: FINDINGS_SCHEMA })
)
if (!soloGroup) {
  checkThunks.push(() =>
    agent(holisticPrompt(), { label: 'check:holistic-fable', phase: 'Check', schema: FINDINGS_SCHEMA, model: 'fable' })
  )
}
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
  scope: SCOPE,
  range: RANGE,
  vault: VAULT,
  counts: { raw: rawFindings.length, deduped: deduped.length, confirmed: confirmed.length, rejected: rejected.length, by_severity },
  report_markdown: report,
  confirmed_titles: confirmed.map((f) => `[${f.severity}] ${f.file}:${f.line} — ${f.title}${f.overlaps_prior ? ' (overlaps prior)' : ' (NEW)'}`),
}
