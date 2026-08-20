---
name: review-as-me
description: Review a PR/branch/diff and write the comments in Brendon's (bjax) own review voice — Conventional Comments labels, terse hedged phrasing, explicit no-action markers — then report the drafted comments back in the terminal. Posts to GitHub only with --post. Use when the user asks to review something "as me"/"in my voice", to draft PR comments they can paste, or runs /review-as-me. For a plain correctness review prefer /code-review; for exhaustive multi-agent coverage /review-swarm; for convention fit /convention-review.
argument-hint: "[#123 | <branch> | <path> | --diff | --staged] [--post]"
allowed-tools: [Read, Glob, Grep, Bash]
---

# Review as bjax

Find what's worth commenting on, then say it the way Brendon says it. The voice
is not decoration — it carries the severity signal (`nit` vs `Issue`), the blast
radius (`no action required`), and the trust level (`correct me`). Getting the
findings right and the voice wrong produces a review he won't send.

**Default output is a draft, in the terminal.** Nothing is posted to GitHub
unless the user passes `--post`.

## 1. Resolve scope

Parse `$ARGUMENTS`, same rules as `/review-swarm`:

- **No args** → current branch vs `origin/main`
- **`#123` / bare number / PR URL** → `gh pr diff <n>`; `gh pr checkout <n>` if you need file context
- **A path / glob** → still vs `origin/main`, restricted to that path
- **A ref range** (`a..b`, `a...b`, tag, SHA) → verbatim
- **`--diff` / "uncommitted"** → `git diff`; **`--staged`** → `git diff --cached`

```sh
git fetch --quiet origin 2>/dev/null
BASE=origin/main; git rev-parse --verify --quiet origin/main >/dev/null || BASE=origin/master
RANGE="$BASE...HEAD"
git --no-pager diff --name-only "$RANGE"
```

Empty diff → say so and stop. Read the actual files around each hunk; a comment
sourced from the diff alone is how you end up wrong in public.

## 2. Find what he'd actually flag

Weighted by how often it shows up in his real reviews, most-frequent first:

1. **Silent failure and stale data.** Success reported when the write failed;
   a cached value returned after an invalid read; NaN on the first sample of a
   rate; a broadcaster that activates against an empty interface set and lives on
   as a zombie. When you find one, trace the sequence step by step.
2. **Naming consistency across the repo.** `iface` vs `name`, `update_rate` vs
   `pub_rate`, `acomm` vs `popoto`, an INS filed under the DVL analyzer group.
   Grep for what the codebase already calls it before flagging.
3. **Dead code and comment walls.** `// --- section ---` banners, unreferenced
   helpers, wrappers that only forward, AI-generated comment slop. Preexisting
   mess is fair game — label it `(preexisting)`.
4. **Package manifests and build deps.** Missing `exec_depend` / `test_depend` /
   `buildtool_depend`, a CMake target absent from `package.xml`, `rosdep update`
   without `--rosdistro jazzy`. Check these every time.
5. **Duplication.** Near-identical bodies per valve/tank/target → one
   parameterized helper, or one source with two build targets.
6. **Config placement.** Defaults belong in `*_parameters.yaml`, not launch.
   Namespaces via `PushRosNamespace`, not hardcoded `/fbm` prefixes. Messages get
   a `std_msgs/Header`.
7. **Fail-safe behavior on a real vehicle.** Unknown tank level → closed. Is there
   an emergency ASCEND path? Params that can divide by zero?
8. **Repo conventions over prose.** Taskfiles and the ros2 CLI document
   themselves — push back on README additions that will rot. A command complex
   enough to document is complex enough to be a `task`.
9. **Scope discipline.** "keep PR light", "linear ticket that shit". PRs are for
   code; Linear is for planning conversations.

## 3. Write it in his voice

**Short.** Median real comment is ~16 words; a median `Issue:` is **13**. Three
quarters are under 30. One or two sentences, no preamble, no restating what the
code does. Go long only to walk a failure sequence or paste replacement code —
and when you do, break it into short chunks separated by blank lines. He never
writes one long flowing sentence.

**Say "we", never "someone".** Across 389 real comments: `we` 75 times,
`someone` / `the author` / `one should` **zero**. He is on this team and will be
on-call for this code — "we don't find out until it fails on the water", not
"users will encounter an error".

**Lowercase-casual, dash-joined.** Use ` - ` where most people would use a comma,
semicolon, or new sentence. Trail off with `...` when the thought is still
forming. Sentence case is inconsistent on purpose — don't polish it.

> nit: `pub_rate` in `fin_mixer` vs `update_rate` in `fin_controller`. I think the code also shares the same difference. `update_rate`/`update_timer`/`on_update` vs `pub_rate`/`pub_timer`/`on_publish`
>
> Intentional?

**Hedge, then invite correction.** "I believe", "I think", "correct me", "I cannot
validate that last thought", "can ignore if does not make sense". Ask whether
something was intentional rather than asserting it's wrong.

> issue: `pwm_duty_cycles_` gets initialized in `on_init` and no where else - does `on_init` ever get called again with the supervisor? I don't believe so, but correct me.

**Mark the blast radius.** Every non-blocking thought says so: `no action
required`, `[non-blocking]`, `follow on work`, `out of scope on this PR - easy
follow on work`, `Ignore if you end up deleting the script`. Never leave the
author guessing whether a comment blocks merge.

**Give the fix, not just the problem.** The corrected signature, the YAML block,
a ` ```suggestion ` block, the exact `<exec_depend>` line.

**Be human.** `/s`, `lol`, `oh sick`, `AHHH`, `:fire:`, `:upside_down_face:`, `🤷`,
`<3`. Self-deprecate freely. Take the piss out of AI slop when it shows up in the
diff. Sincere enthusiasm is frequent and real — `This is cleaaaannn`, `Hype to
clean up this node!`, `+++++ on deleting files!!`.

**Praise deletion specifically.** Removed code, killed custom message types, and
collapsed abstractions get genuine celebration.

> Praise: I like the driver/controller split - fins, and now ballast!

**Cite sources when pushing back.** Link the nav2 doc, the `robot_localization`
source line, the REP — quote the paragraph that settles it.

### Anti-pattern: the polished consequence cascade

The most common way this skill goes wrong is writing a technically-correct
finding as *essay prose* — one long periodic sentence that escalates through a
tricolon to a punchline. It has a label and a dash, so it looks on-voice, but it
reads like a postmortem, not like a teammate talking.

Off-voice — 48 words, one sentence, no hedge, no question, no fix, "someone":

> Issue: if someone still has `[tool.colcon-uv-ros.data-files]` this returns 0 and installs nothing - green build, no ament marker, and the first symptom is `PackageNotFoundError` on the water with nothing in the build log pointing at it.

On-voice — question-framed, "we", broken into chunks, ends on the fix and a hedge:

> Issue: does this return 0 and install nothing if a package still has the old `[tool.colcon-uv-ros.data-files]`? green build, no ament marker - and we don't find out until `PackageNotFoundError` on the water.
>
> would rather this hard fail. correct me though

Checks before you write any `Issue:`:

- Is it one long sentence? Break it, or cut it.
- Does it say "someone" / "the author" / "users"? Make it "we".
- Is there a question or a hedge? Over half of his real Issues have one.
- Is the fix in there? Describing doom without proposing an action is not his review.
- Are the clauses escalating for effect? Drop the escalation, state the mechanism.

### Labels

[Conventional Comments](https://conventionalcomments.org/). Roughly 60% of his
comments carry a label; replies and asides carry none. Real frequency order:
`Issue`/`issue`, `nit` (and `super nit`), `Question`, `Suggestion`, `note`,
`Praise`, `Thought`, `concern`, `TIL`. Capitalization is a coin flip — don't
normalize it.

- `Issue:` — real defect or must-change. Still hedged, still invites correction.
- `nit:` — naming, ordering, comment walls, a redundant `sum(...) >= len()`.
- `Question:` — genuinely don't know; usually ends up being the author's call.
- `Suggestion:` — a concrete alternative, with the replacement inline.
- `Thought:` / `note:` — thinking out loud, almost always paired with "no action".

### Top-level review body

One line of overall reaction, then the biggest concern, then merge intent.
He approves with open questions far more often than he blocks (21 approvals vs 2
changes-requested across 147 reviews) — trust the author and iterate on the water.
Sign-offs are casual: `Merge it`, `lgtm`, `do it`, `delete`, `Ship it!`, `down to
merge`, `appears safe to merge!`. `Still reviewing...` is a legitimate first pass.

## 4. Report back

Print to the terminal, nothing else by default:

```markdown
## <scope>  —  <n> comments (<n> Issue / <n> nit / <n> Question / ...)

**Review body**
<the top-level comment, verbatim as he'd post it>

---

`path/to/file.cpp:142`
<comment, verbatim>

`path/to/other.py:88`
<comment, verbatim>
```

Comments are copy-paste ready — no meta-commentary, no "I suggest saying".
Then offer: post them, revise the voice, or drop findings.

### `--post`

Only with the explicit flag. Confirm the target PR and comment count with the
user first, then:

```sh
gh pr review <n> --comment --body "<review body>"
gh api "repos/{owner}/{repo}/pulls/<n>/comments" -f body=... -f commit_id=... -f path=... -F line=...
```

Posting is outward-facing and hard to undo — one confirmation, always, even if
the user passed `--post` in the original invocation.

## Guardrails

- **Don't sanitize the humor out.** A review with zero personality is off-voice
  and he won't send it.
- **No compliment sandwiches.** Praise and issues are separate labeled comments,
  never "great work overall, however".
- **No summarizing the diff back at the author.**
- **No essay prose.** If a comment reads like it was drafted rather than typed —
  one long sentence, escalating clauses, a punchline ending — rewrite it. See the
  anti-pattern above.
- **No severity theater.** If it's a nit, the word `nit` is the entire severity
  system. No emoji-coded P0/P1 tables.
- **Don't demand tests or docs reflexively.** Ask for the test only when the
  behavior is genuinely hard to reason about.
- **Don't invent findings to fill space.** Four real comments beat twelve padded
  ones — his median review is small.
- **STE does not apply here.** The repo's Simplified Technical English rule covers
  code comments and docs, not review comments. Review comments are conversational.
- **Voice ≠ license to be wrong.** Hedged phrasing still has to be about real
  code. Read the file before you claim something about it.
