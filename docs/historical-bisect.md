# Bisecting a test across linq2db's history

Bisecting *the current* code is ordinary work. Bisecting a test across a **long** range — a year or more,
as when checking whether an `[ActiveIssue]` gate's issue was ever really fixed — crosses infrastructure
migrations, and every one of them makes a step measure something other than what it claims. This doc is
the list of those traps, each paid for on a real run.

Read it with [`bug-investigation.md`](bug-investigation.md) → *Enabling a gated test after issue close* and
[`../skills/enable-disabled-test/SKILL.md`](../skills/enable-disabled-test/SKILL.md), which own the
narrower "issue just closed, enable one test" flow.

## The invariant that matters more than speed

**A bisect step must produce a positive observation, and the search must be able to say "I could not
tell".** Every wrong answer in a bisect comes from inferring a result from something that did *not*
happen: an empty commit range, a checkout that silently failed, a build that produced no tests, a parser
that cannot see a pass. Those all look exactly like a clean verdict.

Two guards, both cheap, both mandatory:

- **Measure the endpoints first and require them to disagree.** If the oldest commit does not fail and the
  newest does not pass, there is no transition to find and the search must refuse to run. Without this a
  binary search happily converges on an arbitrary midpoint. On the run that prompted this doc the
  unguarded version named a *progress-heartbeat* commit as the fix for two data-mapping bugs.
- **Report a bracket, never a bound.** Claim a first-passing commit only when the search converged on an
  **adjacent** pair (`rev-list --count <lo>..<hi>` = 1). If it stalled, print last-known-fail and
  first-known-pass instead. A stalled search that prints `$commits[$hi]` is presenting an untested commit
  as an answer.

## Era detection: one invocation does not span the range

| Change | Landed | Consequence for a step |
|---|---|---|
| VSTest → Microsoft.Testing.Platform | `4745e15c2` (2026-06-14, #5612) | Before: `dotnet test <csproj>`. After: build, then run the **built exe** |
| EF test project split into `EF3`/`EF8`/`EF9`/`EF10` | after the range start | Early commits have only `Tests.EntityFrameworkCore.csproj`; glob rather than hardcode |
| `--provider` / `--test-progress` added | `3c345be327` (#5621) | Neither flag exists before it; passing them fails the run |

Detect the era per commit (`EnableNUnitRunner` in `Tests/linq2db.BasicTestProjects.props` is the MTP tell),
never once up front.

**`dotnet test --project` does NOT force `RunState.Explicit` tests to run, even when the filter names
them** — the tests come back absent. Invoking the **built executable** with the same `--filter` does. This
matters because it means a gated test needs **no source edit** during a bisect: name it in the filter and
it runs, so nothing can accidentally be committed. (`testing.md` records the general "naming a test forces
an Explicit test to run" behaviour; the `dotnet test` exception to it is this line.)

**Never switch invocation style mid-search.** If the range crosses the MTP boundary, split it: bisect the
MTP era first, and only if the endpoints there both pass does the transition lie earlier. A single search
across the boundary correlates its result with *your invocation*, not with the product — the tell is that
every pre-boundary sample fails and every post-boundary sample passes.

## Old commits do not build in a current environment

- **F# nullness.** Code from before F# 9 fails as `error FS3261: Nullness warning` under a current
  compiler. Add `-p:TreatWarningsAsErrors=false` to every step.
- **SDK pin.** `global.json` at old commits pins an older SDK with `rollForward: major`, so a newer
  installed SDK satisfies it — but the selected SDK differs per commit, which is part of why `dotnet test`
  semantics change under you.
- **Stale build output across a version bump.** This is the one that silently removes whole stretches of
  the range from the search. Artifacts from a previously-tested commit survive a checkout, and once a step
  crosses a `<Version>` change the build dies with:

  ```
  CSC : error CS1705: Assembly 'linq2db.FSharp' ... Version=6.2.0.0 ... uses 'linq2db, Version=6.2.0.0'
        which has a higher version than referenced assembly 'linq2db, Version=6.0.0.0'
  ```

  That reads as "this commit does not build" — nine consecutive commits were written off this way. Either
  clean `.build` when a run produces no summary and retry once, or better: **find the bump
  (`git log -G "<Version>6\." -- Directory.Build.props`) and bisect within one version**, where every
  build stays incremental. A clean build per commit also costs far more memory (see below).

## The worktree fights back

- **Verify the checkout.** `git checkout --quiet --detach $sha 2>&1 | Out-Null` hides failures, and the
  step before it ran a test exe in the same worktree and can still hold a file lock. An unmoved `HEAD`
  makes the driver measure the *previous* commit's tree while logging the requested SHA. Always compare
  `git rev-parse HEAD` against the request, retry once after a pause, and log the **verified** head.
- **`.claude/` collides on checkout.** The corpus was tracked *inside* linq2db before it became a
  submodule, so checking out a pre-migration commit materialises those files and moving forward again
  finds them untracked and in the way (*"untracked working tree files would be overwritten"*). Run
  `git clean -fdq .claude` before each checkout, and `checkout -f`. Scope the clean to `.claude` — a bare
  `git clean -fdx` deletes the `UserDataProviders.json` you seeded at the worktree root, after which every
  step resolves zero providers and reports a vacuous pass.
- **Seed `UserDataProviders.json`.** A non-nested worktree finds no config by ancestor walk, so copy one
  in. Restrict it to the providers that actually exercise the failure: fewer databases means less memory
  and shorter steps.

## Budget

A clean full build is ~15–25 minutes and a warm one ~2–4. With provider containers resident, clean builds
per commit exhausted host memory and had runs killed three times. Levers, in the order worth trying:
bisect within one `<Version>`; `-m:1`; `-p:BuildInParallel=false`; `-p:UseSharedCompilation=false` (a
per-invocation setting that bypasses the shared `VBCSCompiler` without disturbing anyone else's build —
never recycle that process, see [`agent-rules.md`](agent-rules.md)); stop containers the step does not
need. Isolating the single unavoidable cold build and running it alone is what finally got a 55-commit
range moving.

Parse verdicts from the **run summary**, one test per run — MTP prints a per-test line only for
non-passing tests, so "no line for this test" is indistinguishable from a pass. `total: 0` is absent,
`failed > 0` is a fail, and anything else is a pass only because the summary said so.
