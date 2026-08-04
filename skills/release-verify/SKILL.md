---
name: release-verify
description: Final verification phase of release prep. Runs **one** Release build to validate that the cumulative state from all earlier release-prep tasks (deps + PublicAPI + milestone-check + test-matrix + release-notes + ad-hoc) compiles cleanly. Reactively walks any new analyzer-rule errors with the user (fix or disable per rule). When any analyzer package was bumped this release, runs `/profile-analyzers` **after** the build is clean to catch performance regressions in new *and* existing rules and surface disable candidates. Refreshes API baselines via `/api-baselines`. Commits the consequent fixes (rule disables, baseline updates, code patches) as a single "release prep verification" commit on the prep PR. Invoked by `/release` step 6 after every other release-prep task is `[x]` or `[-]`.
---

# /release-verify

## What this skill is (and isn't)

**Is:** the single verification gate at the end of release prep. Owns the **only** Release build of the release-prep cycle (every prior sub-skill is forbidden from running its own verification build). Combines four things into one pass so the build+fix loop happens once, not per-task:

1. Release build of `linq2db.slnx`.
2. Reactive analyzer-rule catch-up — for any new analyzer error the build surfaces, ask user fix-or-disable per rule (the equivalent of step 4a in the new `/release-deps` for analyzer rules that escaped the predictive audit).
3. (Conditional) `/profile-analyzers` perf check if analyzer packages were bumped this release — **run only once the build from step 2 is clean**, so the measurement reflects the shipping rule set rather than a half-fixed tree.
4. `/api-baselines` refresh — regenerate `CompatibilitySuppressions.xml` files.

All consequent edits (`.editorconfig` rule disables, `CompatibilitySuppressions.xml` regenerations, code fixes) batch into a single follow-up commit on the prep PR.

**Isn't:**

- Not a plain `dotnet build`. It's an orchestrated build → react → re-build → audit → baseline-refresh chain.
- Not a CI replacement. CI test-all still runs the full provider matrix on every commit.
- Not for ad-hoc verification mid-flow. It's gated to fire once, at orchestrator step 6, after every other prep task is closed.

## When to run

- Invoked by `/release` as task 6 once tasks 0-5 + any ad-hoc `7.x` that doesn't itself need a clean build are all `[x]` or `[-]`.
- Manually only if the user explicitly asks "verify the release prep" or similar — and only when the prep branch is in a state to merge (otherwise it's premature).

## Required reading

- [`.claude/skills/api-baselines/SKILL.md`](../api-baselines/SKILL.md) — invoked as a sub-step. Read its policy on `LinqToDB.Internal.*` vs other API surface.
- [`.claude/skills/profile-analyzers/SKILL.md`](../profile-analyzers/SKILL.md) — invoked conditionally.
- [`.claude/docs/release/nuget-package-notes.md`](../../docs/release/nuget-package-notes.md) — analyzer-package rules (consulted for the reactive rule walk).
- [`.claude/docs/agent-rules.md`](../../docs/agent-rules.md) → **Git commit rules**, **Push to remote rules**.

## Procedure

### 1. Determine whether an analyzer profiling pass is owed

The verification build is **always** plain `dotnet build linq2db.slnx -c Release` (3-8 min). Do **not** substitute `/profile-analyzers` for it — an instrumented rebuild over a tree that still has analyzer errors produces a partial report (projects that fail `CoreCompile` emit no analyzer rows), which is exactly the measurement you need to be trustworthy.

Read the deps state (`release-state.ps1 -Action load`). If `state.deps.applied[]` includes any analyzer package — id matches `*Analyzer`, `*Analyzers`, `BannedApi*`, `PublicApi*`, `AsyncFixer`, `Lindhart.Analyser.*`, or sits in the `Build: Analyzers and Tools` `<ItemGroup>` of `Directory.Packages.props` — then a **profiling pass is owed** and runs at step 3, after step 2's fix loop reaches clean. Record the bumped analyzer ids so step 3 can't be silently skipped; if `state.deps.applied[]` is unavailable, fall back to `git diff origin/master -- Directory.Packages.props` and read the analyzer rows.

Tell the user the plan and the total wall-clock estimate: 3-8 min for the verification build, plus 10-25 min for the profiling pass if one is owed. Wait for explicit go-ahead — never auto-launch a build inside `/release-verify`.

### 2. Run the build (loop until clean)

Run the chosen build. If it fails, classify the errors:

#### 2a. Analyzer-rule errors (`error MAxxxx`, `error CAxxxx`, `error NUnitxxxx`, etc.)

Group by rule code. For each distinct rule, ask the user: **fix the errors**, **disable the rule** (set `dotnet_diagnostic.<id>.severity = none` in `.editorconfig`), or **set as suggestion** (no build break, surface in IDE).

When disabling, queue a `.editorconfig` insert in numerical position under the appropriate analyzer family section (Meziantou under `###### Meziantou.Analyzers`, etc.) with a short reasoning suffix.

When fixing, walk the user through the affected sites. The fix may itself require multiple iterations.

Apply the queued `.editorconfig` edits + any code fixes in one batch, then **re-run the build**. Loop until clean.

This step is the reactive backstop for analyzer rules that escaped the predictive audit in `/release-deps` step 4a (e.g. rules that fire on patterns the changelog didn't enumerate).

#### 2b. Non-analyzer compile errors (`error CSxxxx`)

Common surprises:
- Direct API deprecations on test-helper types from analyzer packages (e.g. NUnit's `TestDelegate` obsoletion in 4.6 — caught only at compile time).
- Cross-package compile interactions (dropped overloads, removed extensions).
- Source-tree edits from a prior release-prep task (PublicAPI, test-matrix) that didn't compile-check.

Walk the user through each. Apply minimal fixes. Re-run the build. Loop until clean.

#### 2c. Other failures (NuGet restore, file lock, disk full)

Stop and surface to user. Do not improvise — disk-full / locked-file failures need the user's environment intervention.

### 3. (Conditional) Profile analyzers — owed whenever an analyzer package was bumped

**Precondition: step 2's build is clean.** A profiling run over a failing tree measures only the projects that compiled, so its rankings under-report and its deltas against the previous release are meaningless. Never run this before step 2 closes.

Invoke `Skill('profile-analyzers')` (it gates on its own user confirmation for the 10-25 min rebuild). This is a *second*, instrumented rebuild on top of step 2's verification build — the one sanctioned exception to the one-build rule, because the two builds answer different questions ("does it compile" vs "what does the shipping rule set cost").

The pass must answer three things, not just render rankings:

1. **New-rule cost.** For every rule newly enabled this release (from `/release-deps` step 4a's decisions), its measured cost. A rule enabled on changelog reasoning alone can turn out to be one of the most expensive in the build.
2. **Existing-rule regressions.** Compare per-analyzer totals against the previous release's saved report (`.claude/docs/release/analyzer-perf-baseline.json`, per [`/profile-analyzers`](../profile-analyzers/SKILL.md) step 5). An analyzer-package bump can make an already-enabled rule dramatically slower without adding any new rule — that regression is invisible without the baseline diff.
3. **Disable candidates.** Produce an explicit candidate list rather than leaving the user to read three tables. Each candidate needs: rule id, total seconds, delta vs baseline (or `new`), and a value judgement. Per `/profile-analyzers` Don'ts, only propose rules that are **both** disproportionately expensive **and** not pulling their weight — an expensive-but-valuable rule stays and is reported as accepted cost.

The user decides per candidate. Disables queue `.editorconfig` edits in the same numerical-position convention as step 2a.

After the pass, save the new report as the baseline for the next release (`/profile-analyzers` step 5) — otherwise the next release has nothing to diff against and this step degrades to eyeballing.

If the user disables anything, re-run the verification build (step 2) once more to confirm clean. Re-running the *profiling* build to measure the delta is optional and usually not worth another 10-25 min — note the expected saving from the report instead.

### 4. Refresh API baselines

Invoke `Skill('api-baselines')`, **passing the prep worktree as `repoRoot`** (`repoRoot <abs-worktree-path>`) whenever the prep branch lives in a worktree — which is the normal case. Without it the skill regenerates the primary clone's baselines, and since that clone is usually on `master` the diff comes back empty or plausible-but-wrong. That skill:

- Deletes existing `CompatibilitySuppressions.xml` files under `Source/`.
- Re-runs `dotnet pack -p:ApiCompatGenerateSuppressionFile=true` to regenerate them.
- Reviews the diff and flags any non-`LinqToDB.Internal.*` API changes for explicit user approval.

The user reviews the regenerated baselines per `/api-baselines` policy. Any approved changes accumulate on the prep branch's working tree.

### 5. Consolidated release-prep commit

This is the **single** commit of the release-prep cycle. Earlier tasks (deps / PublicAPI / milestone-check / test-matrix / release-notes / ad-hoc) leave their changes uncommitted on the worktree; this step stages all of them plus anything produced in steps 2-4 of this skill, and commits them together.

Stage all changes (audit `Tests/Tests.Playground/` for accidental scratch — see `agent-rules.md` → **Git commit rules** — and check that no `.claude` gitlink bump got staged: a corpus edit made during prep belongs in the submodule, not on `release-prep/<ver>`). Commit message structure:

```
Release <ver>: prep

Dependencies (per /release-deps):
- <Package> <old> -> <new>
- ...
- Skipped: <ids or "none">; Blocked by policy: <ids or "none">

PublicAPI reconciliation (per /release-publicapi):
- Promoted Unshipped -> Shipped across <N> projects.

Test-matrix follow-ups (per /release-test-matrix):
- <list of issues caught + fixes, or "all green">

Release-notes (per /release-notes-validate):
- <gaps closed + intentional omissions, or "complete coverage">

Ad-hoc tasks: <list>

Final verification (per /release-verify):
- analyzer rules disabled: <list>
- analyzer rules enabled (post-bump): <list>
- code fixes for new errors: <list>
- API baselines regenerated: <count> files
- profile-analyzers report: <link to .build/.agents/...>  (only if step 3 ran)
- iSeries drift check: <verdict, link to .build/.agents/...>
```

Per `agent-rules.md` → **Git commit rules**, only commit on explicit user request. The user reviews the full message + the proposed staged file list before the commit lands.

If multiple thematic commits are preferred (e.g. user wants deps separate from verification fixes), split into:
- `Release <ver>: dependency updates` — only the deps changes.
- `Release <ver>: prep verification` — the .editorconfig / baseline / code fixes from steps 2-4 of this skill.

Default is one consolidated commit; ask the user if they want a split.

### 6. Push + open PR + trigger CI

On explicit user confirmation:
1. Push the prep branch (creating it on the remote on first push).
2. If no prep PR exists yet, open one per [`branch-and-pr.md`](../../docs/release/branch-and-pr.md) (`Release prep <ver>`, draft, milestone, `--assignee @me`, body = checklist auto-synced from `release-state.ps1`).
3. Trigger `/azp run test-all` via `.claude/scripts/azp-run.ps1`. This is the first and only CI trigger for the release-prep cycle.

### 7. Hand back to `/release` orchestrator

The orchestrator marks task 6 `[x]` and proceeds to step 5 (prep-merge gate). The prep PR is now in CI's hands.

## Don'ts

- Do **not** run multiple verification builds. The whole point of this skill is one build per release prep — if step 2 needs to re-build after fixes, that's expected; step 3's instrumented profiling rebuild is the one sanctioned extra build (and only when an analyzer package was bumped); otherwise no extra builds.
- Do **not** use the profiling rebuild as the verification build, and do **not** profile before step 2 is clean. Projects that fail `CoreCompile` emit no analyzer rows, so the report silently under-reports and the baseline delta becomes garbage.
- Do **not** skip step 3 when an analyzer package was bumped, and do **not** reduce it to "here are three tables". It owes new-rule costs, existing-rule regression deltas, and an explicit disable-candidate list.
- Do **not** disable analyzer rules without explicit user approval per rule.
- Do **not** push without explicit user request (per `agent-rules.md` → **Push to remote rules**).
- Do **not** commit `TreatWarningsAsErrors=false` or any other temporary unblock flag.
- Do **not** dispatch `/release-verify` mid-prep just to "see if it works". Trust the predictive audits in earlier prep tasks; the orchestrator gates this skill to fire once at the end.

## Related

- [`/release`](../release/SKILL.md) — orchestrator, dispatches this skill at step 6.
- [`/release-deps`](../release-deps/SKILL.md) — deps phase. Step 4 (predictive audits) is meant to make `/release-verify`'s reactive walk in step 2a a no-op for the common case.
- [`/profile-analyzers`](../profile-analyzers/SKILL.md), [`/api-baselines`](../api-baselines/SKILL.md) — invoked as sub-steps.
