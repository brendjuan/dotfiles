---
name: nasa-review
description: Review a codebase (or a scoped path / pending diff) against NASA JPL's "Power of Ten" rules for safety-critical code. Produces a per-rule report of violations with file:line citations and severity.
argument-hint: [path | --diff | --staged]  (default: whole repo)
allowed-tools: [Read, Glob, Grep, Bash]
---

# NASA / JPL "Power of Ten" Code Review

Review the target code against Gerard J. Holzmann's *Power of Ten: Rules for Developing Safety-Critical Code* (JPL, 2006). Produce a structured report. Do not rewrite code unless the user explicitly asks.

## Scope resolution

Parse `$ARGUMENTS`:

- `--diff`            → review `git diff` (unstaged changes only)
- `--staged`          → review `git diff --cached`
- `<path>`            → review files under that path (file or directory)
- (empty)             → review the whole repo, excluding `.git`, vendored deps, build artifacts, and generated code

For large scopes, first enumerate candidate source files with Glob (by language extension), then read only what you need. Skip binaries, lockfiles, minified JS, and generated protobuf/flatbuffer/OpenAPI output.

## Language adaptation

The rules were written for C. Adapt them to the codebase's primary language(s) — keep the *spirit* of each rule, not the literal C wording:

| Rule | C original | Adaptation for other languages |
|------|-----------|-------------------------------|
| 8 (preprocessor) | `#define`, `#ifdef` abuse | Macros / metaprogramming / reflection / monkey-patching abuse |
| 9 (pointers) | `**` dereference, function pointers | Deep attribute chains, dynamic dispatch via strings (`getattr`, reflection), callback soup |
| 3 (no heap after init) | `malloc` after startup | Hot-path allocations in real-time loops; unbounded collections |
| 10 (all warnings) | `-Wall -Wextra -Werror` | Linter / type-checker configured to strict, zero warnings |

If a rule genuinely does not apply to the language (e.g. rule 9 in pure Python with no `ctypes`), state that explicitly in the report rather than forcing a finding.

## The ten rules

1. **Simple control flow.** No `goto`, `setjmp`/`longjmp`, or recursion (direct or indirect). Use iteration with bounded loops.
2. **All loops have a fixed upper bound.** A statically verifiable iteration cap that a checker could prove. `while (true)` event loops at the top level are the documented exception.
3. **No dynamic memory allocation after initialization.** Heap use is confined to startup; steady-state code uses pre-allocated buffers / arenas / pools.
4. **Short functions.** ≤ ~60 lines (one printed page), one logical unit of work per function.
5. **Assertion density ≥ 2 per function, on average.** Assertions must be side-effect-free and check anomalous conditions that "should never happen." Assertion failures must trigger a defined recovery action, not just be silently compiled out.
6. **Smallest possible data scope.** Declare every variable at the tightest scope that works. No gratuitous globals or module-level mutable state.
7. **Check every return value; validate every parameter.** Non-void return values must be used or explicitly discarded. Parameters must be validated at the callee before use.
8. **Limit the preprocessor.** Only file inclusion and simple conditional compilation. No token-pasting, no variadic macros, no macro-as-control-flow. (Language-adapted: no clever metaprogramming where a function would do.)
9. **Restrict pointer use.** At most one level of dereference per expression. No function pointers (→ forbids indirect dispatch that defeats static analysis). (Language-adapted: limit deep chains and dynamic dispatch.)
10. **Compile cleanly at the strictest warning level, every day.** All warnings are errors. Static analysis runs in CI.

## Review procedure

For each rule, in order:

1. **Decide applicability** to the codebase's language(s). State it.
2. **Search** for likely violations using Grep/Glob — e.g. for rule 1: `goto`, recursion (functions that call themselves or form cycles); rule 4: files with long functions; rule 5: assertion count vs function count; rule 7: unused-result patterns; rule 10: project lint config.
3. **Read** the suspicious sites to confirm — don't report a violation from grep alone; check context.
4. **Record findings** with `path:line` citations, a one-line description of the violation, and severity:
   - **blocker** — clear violation of the rule's intent with real risk (e.g. unbounded recursion in a control loop)
   - **major** — violation with meaningful risk but a defensible reason might exist
   - **minor** — technical violation, low practical risk (e.g. a 65-line function)
   - **info** — pattern worth noting, not necessarily wrong

For rules that are structural (4, 5, 10), also report aggregate statistics: "X of Y functions over 60 lines", "mean assertions per function: N", "strict lint configured: yes/no".

## Report format

Output one Markdown document with this shape:

```markdown
# NASA Power of Ten Review — <scope>

**Primary language(s):** <langs>
**Files reviewed:** <n>
**Summary:** <blockers>/<major>/<minor>/<info> findings

## Rule 1 — Simple control flow
- **Applicability:** <applies | partially | n/a — reason>
- **Findings:**
  - `src/foo.c:142` **[blocker]** direct recursion in `process_frame()` inside real-time loop
  - ...
- **Aggregate:** (if applicable)

## Rule 2 — Bounded loops
...

(repeat for all 10 rules)

## Top recommendations
1. Most impactful fix
2. ...
```

Order findings within a rule by severity (blocker → info), then by path.

## Guardrails

- Be specific. Every finding cites `path:line`. "The codebase has long functions" is not a finding.
- Be honest about language fit. Don't invent rule-8 violations in Python just to fill the section.
- Don't fix anything. This skill produces a report. If the user wants fixes, they'll ask in a follow-up.
- Don't read generated or vendored code. Exclude `node_modules/`, `vendor/`, `build/`, `dist/`, `target/`, `__pycache__/`, `.venv/`, `install/`, `log/`, `*.pb.go`, `*_pb2.py`, minified JS, etc.
- For large repos, sample intelligently for structural rules (4, 5) — document the sampling method in the report.
- Cite Holzmann's paper once in the header if helpful, but keep the report focused on this codebase.
