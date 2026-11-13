# Work plan: feature-baselines-rebase-lease — the baselines-branch rebase must not delete commits pushed while it runs

**Tier:** M  ·  **Status:** approved  ·  **Approved-at:** 2026-10-31 (user, after critic round 1; real-CI gates G-CI-AZ / G-CI-GH authorized)  ·  **Branch:** feature/baselines-rebase-lease
**Schema:** `.claude/docs/work-plan.md`  ·  **Gates:** `.claude/docs/definition-of-done.md`

## P1 Problem

`Build/Azure/scripts/ensure-baselines-branch.ps1:100-116` (`-Rebase` path) clones the baselines repo, checks out `origin/baselines/pr_<n>`, rebases it onto its base and runs `git push -f origin HEAD:$Branch`. Every commit that another pusher lands on the branch between the clone and the force-push is silently deleted. One `/azp run test-all` comment starts both Azure (`create_baselines_branch`, `Build/Azure/pipelines/templates/test-jobs.yml:65-93`) and the GitHub legs (`.github/workflows/tests-comment.yml:141-150` → `tests.yml`). The GitHub legs do not wait for Azure's job, and push through `Build/CI/push-baselines.ps1:111-164`.

measured (2026-10-31, `git -C C:/GitHub/linq2db.baselines log --reverse --format="%h a=%aI c=%cI %an | %s" origin/master..origin/baselines/pr_5673`): Azure build 25040's create job (17:15:38–17:19:17Z) replayed 44 commits with committer dates 17:18:37–17:19:11Z. The latest replayed 2026-10-31 commit was authored 17:11:30Z. GitHub job 124581456027 (`Lin l_SqlServer2017_2019`) pushed inside that window. measured (its log, `gh api repos/linq2db/linq2db/actions/jobs/124581456027/logs --allow-escape-sequences`): the first push at 17:17:24Z was rejected (`! [rejected] HEAD -> baselines/pr_5673 (fetch first)`), and the second at 17:17:30Z exited 0 (the script then reached `Baselines PR already exists` at 17:17:32Z, `push-baselines.ps1:165-182`). measured census (`actions/runs/41214683477/jobs?filter=all`, completed 17:10–17:22Z): it is the only leg of that run that completed between 17:11:40Z and 17:21:41Z. No 2026-10-31 `[Linux / SQL Server 2017 + 2019] baselines` commit exists on the branch, and the next surviving commit is at 17:21:28Z. So PR #5673's SqlServer.2017/2019 baselines are 2026-10-28 content while CI reported green.

## P2 Success criteria

- SC-1 A commit pushed to the run branch after the rebase job read it, and before its push, is still on the branch after the job finishes, as a rebased copy. Unmet if no commit with the injected commit's subject and content is in `<base>..<branch>` at the end. (The rebase rewrites shas, so ancestry of the original sha is not the test.)  → TO-1
- SC-2 The rebase job still rebases a diverged branch onto its base and pushes it when nobody pushes concurrently. Unmet if the final tip does not descend from the base or loses any pre-existing branch commit.  → TO-2
- SC-3 When concurrent pushes keep beating it, the job fails loudly after a bounded number of attempts instead of looping or force-pushing blindly. Its message says to re-run and never to delete the branch. Unmet if it exits 0 without the concurrent commits, never terminates, or its message suggests deleting the branch.  → TO-3

## P3 Constraints & anti-goals (M/L)

- No change to `push-baselines.ps1`, `checkout-baselines.ps1` or the leg push protocol (fast-forward push, then on rejection fetch + `rebase -X theirs --onto FETCH_HEAD HEAD~1`).
- No change to job ordering in either CI, or to which CI runs the rebase. The comment path still has only Azure's `create_baselines_branch` rebasing.
- The no-rebase paths (`ahead` / `identical` / branch absent) keep their current behaviour and cost: no clone.
- No change to PR #5673's baselines branch. The requesting session already re-ran the lost leg, which the census in P1 shows was the only one.
- Script output contract unchanged: the `baselines_branch` task output and exit codes 0/1.

## P4 Unknowns (M/L)

- U-1 Can the real script be exercised end to end without GitHub? — resolved-by probe (pending, see TO-1): run it with `PrId=''` (branch `baselines/default`, so `Get-BaselinesBase` makes no `gh` call, `baselines-base.ps1:36-38`). Shim `gh` with a harness function (functions take precedence over applications) that answers `diverged` for the compare and empty for the PR lookup. Map the GitHub URL to a local bare repo with `url.<file-url>.insteadOf` via `GIT_CONFIG_GLOBAL`. Inject the concurrent push from a `git` wrapper function that runs a second clone's push just before the script's first `push`. If any of these fail to take effect, TO-1 falls back to a harness that mirrors the loop, labelled as such. measured (2026-10-31 19:42, harness `.build/.agents/baselines-lease-probe.ps1`, master's script): with no injection the real script ran end to end against the local bare repo (exit 0; branch B1,B2 rebased onto master's M, tip descends master). So the insteadOf mapping and the `gh` shim work. The `git` wrapper's push counter first read 0 (a `$script:` scope bug, now `$global:`). Re-runs then failed before the script started, because git's local and file:// transports spawn `sh.exe`, which currently dies with the MSYS `add_item` error. A `git daemon` (git://) transport hung on push. Resolved: an ssh transport whose `GIT_SSH` is a `.bat` (spawned without a shell) running `git upload-pack`/`receive-pack` ran every mode; results in G-01.
- U-2 Does `--force-with-lease=<ref>:<sha>` reject when the remote ref moved but the local clone's remote-tracking ref did not? — resolved-by git docs (reasoned, unprobed until TO-1): with an explicit expected sha the lease compares the remote's current value against that sha, independent of the tracking ref. TO-1 measures it.
- U-3 Does the rebase on retry need the base re-fetched too? — resolved-by decision D-1: fetch both; refreshing the base can only move the rebase target forward, which is what the job is for.
- U-4 Does a GitHub leg that cloned the pre-rebase tip and pushes after the rebased force-push lose anything? — resolved-by scout: `push-baselines.ps1:113` pushes a plain (non-force) ref update, which is rejected as non-fast-forward. `:128-156` then fetches and replays only its own commit (`--onto FETCH_HEAD HEAD~1`). Unaffected by this change.
- U-5 Are there other force-pushes to baselines run branches in CI? — resolved-by scout: `git push -f|--force` across `Build/**` and `.github/**` has one hit, `ensure-baselines-branch.ps1:116`.

## P5 Decisions (M/L; rejected alternatives mandatory at L)

### D-1 — Lease the force-push on the sha the rebase started from, and redo fetch + rebase on rejection

- **chosen:** record `$leased = git rev-parse origin/$Branch` after checkout; `git push --force-with-lease=refs/heads/${Branch}:${leased} origin HEAD:refs/heads/$Branch`. On failure: `git fetch origin $Branch $base`, `git checkout --detach origin/$Branch`, re-record the lease, `git rebase origin/$base`, push again. Cap at 5 push attempts. Failure paths:
  - push output matching `\[rejected\]|stale info` is a lease or non-fast-forward rejection, so go straight to the refetch;
  - any other push failure (5xx, transport) waits 2, 4, 8, 16 s before the refetch, matching `push-baselines.ps1:83-109`'s reason for not retrying a struggling server in a tight loop;
  - a failing refetch or `checkout --detach` exits 1 with git's output;
  - a rebase failure on any attempt keeps the existing message and exit 1 (`:111-114`);
  - exhaustion exits 1 with the last push output and says the branch kept moving or the push kept failing, so re-run the job, and does not say to delete the branch. Deleting it would discard every provider's baselines on the PR.
- **rejected:** serializing the CIs — make GitHub legs wait for Azure's create job, or cancel GitHub runs before the rebase (the earlier design, `plans/feature-migrate-ci-to-github-actions/plan.md` D-7). This needs cross-CI signalling (polling Azure from GitHub, or the Actions API from Azure) and only narrows the window, which that plan accepted as a residual (`:251`). The lease closes it at the one place that can lose data.
- **rejected:** plain `--force-with-lease` with no explicit sha. It compares against the clone's remote-tracking ref, which is correct only while nothing refetches. The explicit sha states the invariant directly.
- **why this:** the leg protocol already resolves concurrent fast-forward pushes. The rebase is the only non-fast-forward writer, and a lease makes it one more participant that retries instead of overwriting.
- **rejected (optional critic suggestion):** on retry, replay only `<leased>..origin/$Branch` onto the already-rebased HEAD. That is cheaper, but it is wrong when the remote tip does not descend from the lease (another rebaser), and handling that case needs a second code path. A full re-rebase is one path and correct in both cases.
- **failure mode of the choice:** a burst of leg pushes during the job makes it retry, and each retry replays the whole branch. measured: 44 commits took 34 s (committer dates 17:18:37–17:19:11Z on #5673), so 5 attempts cost up to ~3 min plus up to 30 s of waits. Legs finish minutes apart, and the census found one push in a 10-minute span, so one retry is the realistic case. Exhaustion fails the create job and Azure's legs do not run: a loud failure, not lost baselines.

### D-2 — Keep earlier runs' commits on the branch

- **chosen:** no change. The branch keeps every earlier run's leg commits; the rebase only moves them onto the current base.
- **rejected:** resetting the branch to its base at the start of each run. A scoped run (`/azp run test-sqlite`) would then drop every other provider's baselines from the PR. `checkout-baselines.ps1:13-19` also relies on the run branch as base so that a reverted baseline is staged as a revert.
- **why this:** a provider is stale after a run only when its leg did not run or its push was lost. The first is by design for scoped runs; the second is what D-1 removes.
- **failure mode of the choice:** a leg that is skipped in a full run (its main tasks skipped, e.g. Azure Windows 2017+2019 under `gh_linux: 'true'`) keeps old content without a signal. That is a separate visibility issue, not a data-loss race; recorded in P10.

## P6 Edit-points

- E-1 `Build/Azure/scripts/ensure-baselines-branch.ps1:rebase block (:99-124)` — lease the force-push on the checked-out sha; retry loop of fetch + checkout + rebase + leased push, cap 5; header note on the race.
- E-2 `.github/workflows/tests.yml:baselines_init comment (:469-471)` — the stated reason "two force-pushers on one branch race" is no longer data loss after E-1; reword to say Azure already rebases on the comment path, so a second rebase only duplicates it.
- E-3 `.claude/docs/ci-tests.md:172` (corpus) — rewrite the paragraph's categorical "is a baselines rebase conflict" into two causes, each with its message and remedy: rebase conflict (message "Failed to rebase baselines PR on origin/...") → delete the branch and re-run; push exhausted (E-1's new message) → re-run only, never delete. Add a note: the create job and the GitHub legs share the PR's baselines branch from one comment. Before this fix, a leg push inside the create job's window was deleted. The tell is a leg log with a successful push and no commit for it on the branch; the remedy is to re-run that leg.

## P7 Impact map (M/L)

- `Build/Azure/pipelines/templates/test-jobs.yml:84-85` — Azure caller, `-Rebase -EmitOutputs` — searched `ensure-baselines-branch` across `Build/**`, `.github/**` — covered by E-1 (contract unchanged)
- `.github/workflows/tests.yml:496` — GitHub caller (`baselines_init`, `rebase_baselines` input, used by `tests-release.yml`), `-Rebase` without `-EmitOutputs` — same search — covered by E-1 (gets the fix too)
- `.github/workflows/tests.yml:469-471` — comment justifying `rebase_baselines` off on the comment path by the race — searched `force-push|race` in `.github/workflows/tests.yml` — covered by E-2
- `.github/workflows/tests-comment.yml:106-107`, `tests-release.yml:35-36` — comments naming the shared branch; no race claim — same search — out-of-scope
- `Build/CI/push-baselines.ps1:111-164` — the leg push loop, the other writer — searched `git push` across `Build/**` — out-of-scope (P3; interacts correctly, U-4)
- `Build/CI/checkout-baselines.ps1:59-74` — leg clone base selection — searched `ls-remote` across `Build/**` — out-of-scope (unchanged reader)
- `.claude/docs/ci-tests.md:172` — documents only the rebase-conflict failure of this job, with a delete-the-branch remedy that would be destructive for E-1's new exhaustion failure — searched `ensure-baselines|create_baselines|rebase.*baselines` across `.claude/docs/**` (critic) — covered by E-3
- `.claude/docs/review-rubric/rubric-tests.md:56` — names this job's NTFS case-collision exit 1 — same search — out-of-scope (cause and message unchanged)
- consumers of the job's messages — searched `was rebased on HEAD|Failed to rebase baselines PR|Failed to push rebased` across the worktree (critic) — none parse them; out-of-scope
- `.claude/plans/feature-migrate-ci-to-github-actions/plan.md:46,121-125,251`, `.claude/plans/feature-release-tests-github/plan.md:70,210` — earlier plans recording the race as accepted — searched `ensure-baselines|force-push` across `.claude/plans/` — out-of-scope (historical records, not edited)

## P8 Test obligations (M/L)

All three run the real `ensure-baselines-branch.ps1` (from the worktree) against a local bare repo, per U-1. Harness: `.build/.agents/baselines-lease-probe.ps1`, scratch, not committed. Fixture: bare repo with `master` advanced by one commit past the run branch's fork point (so the compare is genuinely diverged), run branch `baselines/default` carrying 2 commits.

- TO-1 Discriminating input: the `git` wrapper pushes a third commit to `baselines/default` from a second clone just before the script's first `push`. Assert the injected commit's subject is in `git log master..baselines/default` after the script exits 0. Red against `origin/master`'s script (`-f`, commit absent); green on the branch. — providers: none (CI script) — proof: red→green
- TO-2 No injection. Assert exit 0, the final tip descends from `master`, and both original commits' subjects are present. Run against both scripts; must pass on both. — providers: none — proof: characterization
- TO-3 The wrapper injects a fresh commit before every `push`. Assert the script exits 1 after exactly 5 push attempts (counted by the wrapper), the bare repo's branch tip is the last injected commit (nothing overwritten), and the log contains "re-run" and not "Delete branch". — providers: none — proof: red→green (the old script exits 0 and drops the injected commit)

## P9 Verification gates

- G-01: pass — `.build/.agents/baselines-lease-probe.ps1` running the real script against a local bare repo (2026-10-31 ~20:38). Transport: ssh via a `.bat` `GIT_SSH` that runs `git upload-pack`/`receive-pack` directly, because file:// spawns the crashing `sh.exe`. `/test` does not apply: no test project covers CI scripts. Results:
  - TO-1: master's script exits 0 with `INJ1` missing (red); the branch's exits 0 with `INJ1` on the rebased branch, 2 push attempts, tip descends master (green).
  - TO-2: both scripts exit 0, B1 and B2 rebased onto master.
  - TO-3: master's script exits 0 with `INJ1` lost (red); the branch's exits 1 after exactly 5 push attempts, with all 5 injected commits kept and tip `INJ5`. The log shows 4 "moved since <sha>, fetching and rebasing again" lines, then "Re-run this job", and no "Delete branch" (green).
  - Unexercised: the non-rejection backoff branch (5xx/transport); no probe injects a server failure.
- G-CI-AZ: — (pending) an `/azp run test-<x>` on this branch's PR, after a stale scratch run branch exists for it, so the Azure caller (`test-jobs.yml:84`) takes the rebase path and exits 0. Outward-facing: needs the user's go-ahead.
- G-CI-GH: — (pending) `gh workflow run tests.yml --ref feature/baselines-rebase-lease -f surface=<x> -f baselines_branch=<scratch> -f rebase_baselines=true` against a scratch stale baselines branch (as `plans/feature-release-tests-github/plan.md` TO-8 did), so the GitHub caller (`tests.yml:496`) takes the rebase path. Outward-facing: needs the user's go-ahead.
- G-06: pass — `git diff --stat`: only `ensure-baselines-branch.ps1` (rebase block) and `tests.yml` (one comment line), both P6 rows.
- G-07: n/a — nothing under `Tests/Tests.Playground/` changed.
- G-09: pass — a fresh reviewer (sonnet) read the diff and `push-baselines.ps1`. It found no path that overwrites remote commits, loops, or exits 0 without pushing, and confirmed the lease form, `$LASTEXITCODE`, the opportunistic fetch update and convergence of two concurrent rebasers. Two minor findings were declined, see P10 L-3 and L-4.

## P10 Adjudicated (M/L)

- L-1 A full-run leg whose main tasks are skipped (Azure Windows SQL Server 2017+2019 under `gh_linux: 'true'`, `test-matrix.yml`) leaves that provider's earlier baselines untouched with no signal. Not a race and not data loss; out of scope here (D-2).
- L-2 The concurrent case (TO-1, TO-3) is verified on a local bare repo with the real script, not on GitHub, because the window cannot be scheduled on real CI. The real-host runs in P9 (G-CI-AZ, G-CI-GH) show only that the non-concurrent rebase still works on each caller. If the local transport stays blocked by `sh.exe`, TO-1/TO-3 are recorded as unproven on the real script, not passed through a mirror harness.

- L-3 A failing refetch exits 1 at once, even right after a transient push failure (`push-baselines.ps1:130-139` retries that case). Kept as D-1 chose: two consecutive failures against the server end in a loud red job and lose nothing, and a retryable-fetch path would be an extra branch no probe can exercise.
- L-4 The rebase-conflict message still says "Delete branch and re-run tests". The line is unchanged, and that is the documented remedy for a genuine rebase conflict (`ci-tests.md:172`). A leg commit replayed on retry is the same kind of commit the first rebase already replays.
- L-5 The `ci-tests.md` edit (E-3) is deferred until this PR merges, per the user's standing rule that corpus docs describe merged state only. The diff is parked in the PR body.

## P11 Amendments (M/L)

_None._

## P12 Critic verdict (M/L)

- Round 1 (2026-10-31, plan-critic on `fable`): **weak**. The critic searched every writer to baselines refs in `Build/**`, `.github/**` and `.claude/scripts/**` (two: `push-baselines.ps1:113`, plain; `ensure-baselines-branch.ps1:116`, force), every caller of the three baselines scripts, `race|force-push` claims, the `baselines_init`/`rebase_baselines` gating, and git's push/fetch docs for the lease form. It could not run git, because `sh.exe` crashes on this machine. Objections and responses:
  - E-3 left `ci-tests.md:172`'s delete-the-branch remedy standing for the new exhaustion failure. → E-3 now rewrites :172 into two causes, and SC-3/TO-3 forbid "delete" in E-1's message.
  - SC-1's ancestry test could never pass after a rebase. → reworded to subject and content.
  - D-1 treated every push failure as the race, and fetch/checkout failure paths were unstated. → D-1 now lists the failure paths and the measured retry cost.
  - TO-1/TO-3 were undischarged, and a mirror harness cannot discharge them. → L-2: real script only, or recorded unproven.
  - The GitHub caller had no gate. → G-CI-GH added.
  - Lead: P3 assumed a single lost leg. → measured census in P1: one leg in the window, and its 17:17:30 push exited 0.
  - Minor: the "seconds" claim. → measured 34 s per replay.
  - Optional incremental replay. → rejected in D-1.
