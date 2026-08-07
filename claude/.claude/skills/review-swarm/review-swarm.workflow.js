export const meta = {
  name: 'review-swarm',
  description: 'Fan-out multi-dimension code review with an adversarial verification wave, distilled into a report',
  phases: [
    { title: 'Survey', detail: '15 dimension reviewers scan the diff in parallel' },
    { title: 'Verify', detail: '7-10 skeptics validate findings against the real code' },
    { title: 'Distill', detail: 'synthesize confirmed findings into a markdown report' },
  ],
}

// ---- scope injected by the caller via `args` ----
//   args.scope   : human description of what is being reviewed
//   args.range   : git diff range, e.g. "origin/main...HEAD" (or "" for none)
//   args.changed : array of changed file paths (may be empty -> agents discover)
// args may arrive as an object or a JSON-encoded string depending on the caller.
const ARGS = (typeof args === 'string') ? JSON.parse(args) : (args || {})
const SCOPE = ARGS.scope || 'the current changes'
const RANGE = ARGS.range || ''
const CHANGED = ARGS.changed || []
// per-phase models: survey (reviewers) defaults to opus; verify (skeptics) and
// distill to sonnet. Override via args.models, e.g. { survey: 'sonnet' };
// pass null for a phase to fall back to the session model.
const MODELS = { survey: 'opus', verify: 'sonnet', distill: 'sonnet', ...(ARGS.models || {}) }

// Never go bare `git diff` (a clean tree would silently widen scope to a stale
// local main). Default to origin/main so branch staleness can't inflate scope.
const DIFF_CMD = RANGE ? `git diff ${RANGE}` : 'git diff origin/main...HEAD'
if (!RANGE && !CHANGED.length) log('⚠️ no range or changed-file list supplied; defaulting to origin/main...HEAD')

const FILE_BOUNDARY = CHANGED.length
  ? `Review ONLY these files — findings outside this set are out of scope and must be dropped.\n`
  : ''
const DIFF_HINT =
  `Review scope: ${SCOPE}\n` +
  `Primary diff command: \`${DIFF_CMD}\`\n` +
  FILE_BOUNDARY +
  `Changed files:\n${CHANGED.length ? CHANGED.map(f => '  - ' + f).join('\n') : '  (run the diff command to discover them)'}\n\n` +
  `Inspect the diff AND read enough surrounding code (whole functions, callers, tests) to judge correctly. ` +
  `Cite an exact file:line for every finding. Only report issues that the actual code supports — do not speculate.`

const ALL_DIMENSIONS = [
  { key: 'correctness',     focus: 'Logic & correctness bugs: off-by-one, inverted/incorrect conditionals, broken control flow, violated invariants, misused APIs, wrong return values or types.' },
  { key: 'security',        focus: 'Security: injection (SQL/shell/template), authz/authn gaps, secret/credential leakage, unsafe deserialization, path traversal, SSRF, unvalidated/untrusted input, crypto misuse.' },
  { key: 'error-handling',  focus: 'Error handling & edge cases: unhandled or swallowed errors, missing null/undefined guards, empty collections, boundary values, partial-failure and rollback paths.' },
  { key: 'concurrency',     focus: 'Concurrency & async: race conditions, deadlocks, unawaited/forgotten promises, shared mutable state, ordering assumptions, missing cancellation/timeouts.' },
  { key: 'performance',     focus: 'Performance & resources: N+1 queries, needless allocations/copies, O(n^2) hot paths, unbounded growth, leaked handles/connections/listeners, blocking I/O on hot paths.' },
  { key: 'api-design',      focus: 'API/interface design & compatibility: breaking changes, inconsistent or surprising signatures, leaky abstractions, backwards-compat hazards, growth of the public surface.' },
  { key: 'data-integrity',  focus: 'Data integrity & state: persistence correctness, schema/migration safety, transaction boundaries, serialization round-trips, idempotency, data-loss or corruption risk.' },
  { key: 'tests',           focus: 'Tests: missing coverage for new/changed logic, weak or tautological assertions, flaky patterns, untested edge cases, tests that do not actually exercise the change.' },
  { key: 'maintainability', focus: 'Maintainability & clarity: confusing names, dead code, duplication, needless complexity, over-engineering, missing/incorrect or misleading comments, tangled responsibilities. (Repo-wide convention conformance is owned by the repo-conventions dimension — focus here on local clarity.)' },
  { key: 'deps-config',     focus: 'Dependencies, config & build: risky version bumps, misconfiguration, build/CI breakage, env/secret handling, feature-flag gaps, deployment/runtime concerns.' },
  { key: 'repo-conventions', focus: 'Repo-wide convention conformance, judged against the WHOLE codebase and not just the touched lines: the project style rules (e.g. CLAUDE.md / .claude/rules, linters, formatters, editorconfig), directory & module layout, file/naming schemes, import ordering, logging/diagnostic and error-message formats, and any documented interface formats. Flag code that reinvents a pattern the repo already standardizes or violates a stated project rule. When unsure of a convention, grep the wider repo for prior art before reporting.' },
  { key: 'dependency-idioms', focus: 'Idiomatic use of frameworks & dependencies: does the code use each third-party library / framework the way it is normally used and intended? e.g. ROS 2 node lifecycle, parameters, QoS, executors/callback groups, message & action patterns; web frameworks; ORMs; async runtimes. Flag reinvented wheels, ecosystem anti-patterns, deprecated or non-idiomatic API usage, and hand-rolled code where a well-known library primitive should be used. Read how the rest of the repo uses the same dependency to calibrate.' },
  { key: 'consistency',     focus: 'Internal consistency: the same concept should be named, ordered, structured, and handled the same way across the change and its siblings — symmetric/parallel code paths done in parallel ways, consistent units, consistent return/error conventions, consistent parameter ordering and naming, patterns matching sibling files. Flag divergence where two comparable things are done two different ways for no reason.' },
  { key: 'dev-ux',          focus: 'Developer usability (DX) of anything developers consume — CLIs and code APIs. CLI ergonomics: clear --help, sensible subcommand/flag names and defaults, actionable error messages, correct exit codes, sane stdin/stdout/quiet/verbose behaviour. API ergonomics: discoverable, hard-to-misuse signatures, sensible defaults, clear failure modes, docstrings where behaviour is non-obvious. Flag confusing invocations, silent failures, and foot-guns. Calibrate to a developer audience: devs can absorb the occasional error or rough edge when running dev/build/test commands by hand — do NOT demand defensive gating, guard scripts, wrappers, or fail-safe scaffolding around a command just because it could error; a raw error that a dev can read and act on is fine. Reserve findings for genuine ergonomic foot-guns, not hand-holding. If the diff exposes no CLI or developer-facing API, return an empty findings array.' },
  { key: 'frontend-ux',     focus: 'End-user usability of frontend/UI code (JS/TS, HTML/CSS, React/Vue/Svelte/etc.): accessibility (semantic markup, labels, keyboard & focus handling, ARIA, colour contrast), loading/error/empty states, form validation and feedback, responsive layout, avoiding layout shift/jank, and clear affordances. Flag states that leave the user stuck or confused. If the diff contains no frontend/UI code, return an empty findings array.' },
]

// Optionally scale the finder fleet: pass args.dimensions (array of keys) to run a subset.
const DIMENSIONS = Array.isArray(ARGS.dimensions) && ARGS.dimensions.length
  ? ALL_DIMENSIONS.filter(d => ARGS.dimensions.includes(d.key))
  : ALL_DIMENSIONS

const FINDING_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['findings'],
  properties: {
    findings: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        required: ['title', 'severity', 'file', 'line', 'description', 'suggestion'],
        properties: {
          title:       { type: 'string', description: 'one-line summary of the issue' },
          severity:    { type: 'string', enum: ['critical', 'high', 'medium', 'low', 'nit'] },
          file:        { type: 'string', description: 'path to the file' },
          line:        { type: 'string', description: 'line number or range, or "n/a"' },
          description: { type: 'string', description: 'what is wrong and why it matters' },
          evidence:    { type: 'string', description: 'the relevant code snippet or concrete reason' },
          suggestion:  { type: 'string', description: 'a concrete fix' },
        },
      },
    },
  },
}

// ---- Phase 1: survey ----
phase('Survey')
const surveys = await parallel(DIMENSIONS.map(d => () =>
  agent(
    `You are a senior code reviewer assigned to ONE dimension only:\n${d.focus}\n\n${DIFF_HINT}\n\n` +
    `Report ONLY real, specific issues within your dimension. If the diff is clean for your dimension, return an empty findings array. ` +
    `Quality over quantity — a precise finding with correct file:line beats a vague one.`,
    { label: `survey:${d.key}`, phase: 'Survey', schema: FINDING_SCHEMA, ...(MODELS.survey && { model: MODELS.survey }) }
  ).then(r => (r && r.findings ? r.findings : []).map(f => ({ ...f, dimension: d.key })))
))

// flatten + dedupe by file:line:title
const rawFindings = surveys.filter(Boolean).flat()
const seen = new Set()
const findings = []
for (const f of rawFindings) {
  const k = `${f.file}:${f.line}:${String(f.title || '').toLowerCase().slice(0, 60)}`
  if (seen.has(k)) continue
  seen.add(k)
  findings.push(f)
}
findings.forEach((f, i) => { f.id = i + 1 })
log(`Survey: ${findings.length} unique findings across ${DIMENSIONS.length} dimensions`)

if (findings.length === 0) {
  const clean =
    `# Review Swarm Report\n\n## TL;DR\n\n` +
    `**No issues found.** All ${DIMENSIONS.length} dimension reviewers reported a clean diff for ${SCOPE}.\n`
  return {
    scope: SCOPE,
    range: RANGE,
    diff_cmd: DIFF_CMD,
    counts: { found: 0, confirmed: 0, false_positive: 0, uncertain: 0, by_severity: {} },
    tldr: `No issues found — all ${DIMENSIONS.length} reviewers reported a clean diff.`,
    summary_bullets: [`All ${DIMENSIONS.length} dimension reviewers reported a clean diff for ${SCOPE}.`],
    report_markdown: clean,
  }
}

// ---- Phase 2: adversarial verification ----
const VERDICT_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['verdicts'],
  properties: {
    verdicts: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        required: ['id', 'verdict', 'confidence', 'severity', 'reasoning'],
        properties: {
          id:         { type: 'number', description: 'the finding id being judged' },
          verdict:    { type: 'string', enum: ['confirmed', 'false-positive', 'uncertain'] },
          confidence: { type: 'number', description: '0.0 to 1.0' },
          severity:   { type: 'string', enum: ['critical', 'high', 'medium', 'low', 'nit'], description: 'your corrected severity' },
          reasoning:  { type: 'string', description: 'why — cite the actual code you read' },
        },
      },
    },
  },
}

// shard findings across 7..10 verifiers (fewer only if there are fewer findings).
// args.verifiers overrides the target shard count for a lighter/heavier wave.
const target = Number(ARGS.verifiers) > 0
  ? Math.floor(Number(ARGS.verifiers))
  : Math.min(10, Math.max(7, findings.length))
const VCOUNT = Math.min(target, findings.length)
const batches = Array.from({ length: VCOUNT }, () => [])
findings.forEach((f, i) => { batches[i % VCOUNT].push(f) })

phase('Verify')
const verdictGroups = await parallel(batches.map((batch, bi) => () =>
  agent(
    `You are an ADVERSARIAL verifier. For EACH finding below, independently check it against the ACTUAL code: read the cited file:line and its surrounding context, and run \`${DIFF_CMD}\` as needed. ` +
    `Decide whether the issue is REAL and correctly described, or a false positive / hallucination / something already handled elsewhere. ` +
    `Default to skepticism: if you cannot confirm it from the real code, mark it 'uncertain' or 'false-positive'. Correct the severity if the original over- or under-stated it.\n\n` +
    `Scope being reviewed: ${SCOPE}\n\nFindings to verify (return one verdict per id):\n` +
    JSON.stringify(batch.map(f => ({ id: f.id, title: f.title, severity: f.severity, file: f.file, line: f.line, description: f.description, evidence: f.evidence, suggestion: f.suggestion })), null, 2),
    { label: `verify:batch-${bi + 1}`, phase: 'Verify', schema: VERDICT_SCHEMA, ...(MODELS.verify && { model: MODELS.verify }) }
  ).then(r => (r && r.verdicts ? r.verdicts : []))
))

const verdicts = verdictGroups.filter(Boolean).flat()
const byId = new Map(verdicts.map(v => [v.id, v]))
const validated = findings.map(f => {
  const v = byId.get(f.id)
  return {
    ...f,
    verdict: v ? v.verdict : 'uncertain',
    confidence: v ? v.confidence : 0,
    severity: v ? v.severity : f.severity,
    verify_reasoning: v ? v.reasoning : 'no verdict returned',
  }
})
const confirmed = validated.filter(f => f.verdict === 'confirmed')
const dropped = validated.filter(f => f.verdict !== 'confirmed')
log(`Verify: ${confirmed.length} confirmed, ${validated.filter(f => f.verdict === 'false-positive').length} false-positive, ${validated.filter(f => f.verdict === 'uncertain').length} uncertain`)

// ---- Phase 3: distill ----
phase('Distill')
const report = await agent(
  `You are the lead reviewer. Synthesize the verified findings into a polished Markdown review report for: ${SCOPE}.\n\n` +
  `Structure, exactly:\n` +
  `1. A top-level "# Review Swarm Report" title.\n` +
  `2. "## TL;DR" — 2-5 sentences: the overall verdict (ship it, or blockers?), plus a one-line severity tally (e.g. "1 critical, 3 high, 2 medium, 4 low, 1 nit").\n` +
  `3. "## Findings" — grouped under "### Critical / High / Medium / Low / Nits" (omit empty groups). Each finding: a **bold one-line title**, the \`file:line\`, what's wrong, why it matters, and the suggested fix. Merge genuine duplicates.\n` +
  `4. "## Filtered out" — a brief list of what the verification wave rejected (false positives / unverified) and the one-line reason, so the reader trusts the filtering.\n\n` +
  `Be concrete and cite file:line. Do not pad or invent. If there are no confirmed issues, say so plainly in the TL;DR.\n\n` +
  `CONFIRMED findings (JSON):\n${JSON.stringify(confirmed, null, 2)}\n\n` +
  `FILTERED-OUT findings (JSON):\n${JSON.stringify(dropped.map(f => ({ title: f.title, file: f.file, line: f.line, verdict: f.verdict, why: f.verify_reasoning })), null, 2)}`,
  {
    label: 'distill',
    phase: 'Distill',
    ...(MODELS.distill && { model: MODELS.distill }),
    schema: {
      type: 'object',
      additionalProperties: false,
      required: ['tldr', 'report_markdown', 'summary_bullets'],
      properties: {
        tldr:            { type: 'string', description: 'the TL;DR paragraph, plain text' },
        report_markdown: { type: 'string', description: 'the FULL report as markdown' },
        summary_bullets: { type: 'array', items: { type: 'string' }, description: '3-7 terse bullets for a terminal summary' },
      },
    },
  }
)

const bySeverity = ['critical', 'high', 'medium', 'low', 'nit'].reduce((acc, s) => {
  acc[s] = confirmed.filter(f => f.severity === s).length
  return acc
}, {})

return {
  scope: SCOPE,
  range: RANGE,
  diff_cmd: DIFF_CMD,
  counts: {
    found: findings.length,
    confirmed: confirmed.length,
    false_positive: validated.filter(f => f.verdict === 'false-positive').length,
    uncertain: validated.filter(f => f.verdict === 'uncertain').length,
    by_severity: bySeverity,
  },
  tldr: report.tldr,
  summary_bullets: report.summary_bullets,
  report_markdown: report.report_markdown,
}
