---
name: release-publish
description: Post-prep-merge release publishing flow. Opens the release PR (master → release), resets the linq2db.baselines repo HEAD to the documented anchor commit so CI regenerates clean baselines on the release PR, walks the user through merging the CI-generated baselines PR + copying-and-tagging fresh baselines on the releases branch in linq2db.baselines, then blocks at the prerelease-nuget team-test gate before authorizing the release PR merge. Every step is explicitly user-gated — no implicit chains across destructive or shared-state actions. Invoked by `/release` after the prep PR merges to master.
---

# /release-publish

## What this skill is (and isn't)

**Is:** the publish phase of release. Seven gated steps from prep-PR-merged → release-PR-merged. Every step is its own user-confirmed action — destructive ops on shared repos (force-reset baselines), PR merges, tagging, and nuget publish triggers all require explicit go-aheads.

**Isn't:**

- Not the post-tag work (nuget publish verify, docs PR, GitHub release, next-version bump). That's [`/release-postpublish`](../release-postpublish/SKILL.md).
- Not for cherry-picking late fixes onto `release`. If a regression surfaces in step 5 (team-test gate), the skill records the pause and stops — re-opening the prep flow for fixes is the user's call.
- Doesn't run docker / build / test commands. CI does that on the release PR.

## When to run

- Automatically by `/release` orchestrator when the prep PR is detected as merged and `state.currentPhase` transitions to `publish`.
- Manually when resuming a release mid-publish phase.

## Required reading

- [`.claude/docs/release/external-repos.md`](../../docs/release/external-repos.md) — linq2db.baselines path + GitHub release template anchor.
- [`.claude/docs/agent-rules.md`](../../docs/agent-rules.md) → **Push to remote rules**, **Pull request rules**, **Git commit rules**.
- [`.claude/docs/release/first-run-todos.md`](../../docs/release/first-run-todos.md) → the baselines anchor commit + exact gh release invocation are first-run-confirmable.

## Phase state

The publish phase has 7 ordered steps with no implicit transitions. Each step records into `state.publish.steps.<key>` by **direct edit of `.build/.agents/release-<ver>.json`** — `release-state.ps1 -Action update` cannot write these keys (it addresses `state.tasks` via `-TaskId` only, and its `-Status` ValidateSet has no `green`/`paused`). See `/release` step 6:

| Step | Key | Status flow |
|------|-----|-------------|
| 1. Open release PR | `release-pr-opened` | open → done |
| 2. Triage stale baselines PRs | `baselines-prs-triaged` | open → done |
| 3. Reset baselines master | `baselines-master-reset` | open → done |
| 4. Prerelease-nuget team-test gate | `team-test` | open → green / paused |
| 5. Merge release PR | `release-pr-merged` | open → done |
| 6. Merge CI-generated baselines PR | `baselines-pr-merged` | open → done |
| 7. Copy + tag baselines on releases branch | `baselines-releases-tagged` | open → done |

**Note on ordering.** Steps 6 + 7 (baselines flow) run **after** step 5 (release PR merge) so the baselines work proceeds in parallel with `/release-postpublish` (nuget publish, docs PR, GitHub release). Earlier versions of this skill put baselines merge + tag between the master reset and the team-test gate, which serialized the publish unnecessarily — the CI-generated baselines PR doesn't gate prerelease nugets or the release merge.

Skill never auto-advances. Each step prints the next action + waits.

## Procedure

### 0. Phase transition cleanup (prep → publish)

Runs once when the orchestrator transitions `state.currentPhase` from `prep` to `publish` (i.e. after the prep PR merges). Reclaims disk + removes the prep worktree before the publish work starts.

Action:
1. Remove the prep worktree (the branch is now squash-merged to master, the worktree is no longer needed):
   ```
   git -C <main-checkout> worktree remove --force <prep-worktree-path>
   ```
   This deletes the whole worktree directory including any leftover `.build/`, scratch files, and the worktree's `.git` administrative entry.

   **`--force` is mandatory, not a dirty-tree escape hatch.** Since the corpus became a submodule at `.claude/` ([#5735](https://github.com/linq2db/linq2db/pull/5735)), every linq2db worktree contains a submodule, and plain `git worktree remove` refuses outright:

   ```
   fatal: working trees containing submodules cannot be moved or removed
   ```

   The message says nothing about submodules being *dirty* — it fires on a pristine tree too, so don't go hunting for uncommitted changes. Still check `git -C <prep-worktree-path> status --short` first (and `git -C <prep-worktree-path>/.claude status`) so `--force` isn't masking real work; confirm the removal with `git worktree list`.
2. (Optional) Clean the main checkout's build artifacts to reclaim space — Release pack of all family scaffold packages typically leaves 1 GB+ in `.build/bin` + `.build/obj`:
   ```
   dotnet build-server shutdown    # release file locks first
   Remove-Item -Recurse -Force <main-checkout>/.build/bin
   Remove-Item -Recurse -Force <main-checkout>/.build/obj
   ```
3. Leave `<main-checkout>/.build/.agents/` intact — it holds the release state file, the cli-scaffold-run logs, and any scratch the orchestrator needs to resume.

Update phase status to mark this complete before step 1 starts. Worktree-still-present is the common signal that cleanup was skipped; surface a "prep worktree at <path> wasn't removed — remove now? [y/N]" prompt before opening the release PR.

### 1. Open release PR (`master` → `release`)

Preconditions:
- Prep PR merged to `master`.
- `state.currentPhase = 'publish'`.

Action:
1. Verify the release branch exists on origin: `gh api repos/linq2db/linq2db/branches/release` (404 → tell user to ensure `release` branch is set up, stop).
2. Confirm with user the title + body draft:
   - **Title:** `Release <version>` (e.g. `Release 6.3.0`)
   - **Body:** include a publish checklist of steps 1-7 (all steps except step 0). Step 0 (phase-transition cleanup — local worktree + `.build/` cleanup) is **local-user workflow** with no cross-repo artifact and does not belong in the PR body. Steps 2-7 all leave externally-visible artifacts (closed/deleted baselines PRs, force-pushed baselines master, baselines PR merge + tag, team-test gate state, release-PR merge) and belong on the checklist for anyone reviewing this PR's context. Use the same `<!-- release-state:checklist:start -->` / `:end` markers around the listed steps; `release-state.ps1 -Action render` could optionally extend to publish phase.
   - **Milestone:** the release milestone.
   - **Assignee:** `@me`.
   - **Draft:** **no** — the release PR is **an exception to the always-draft rule** in `agent-rules.md` → *Pull request rules*. Create it as ready-for-review immediately so CI runs against it and the team can observe the publish-flow checklist. Default draft state would just hide the work in the PR list and block the auto-trigger of test-all on the merged-PR base.
3. On user confirmation, create:
   ```
   gh pr create --repo linq2db/linq2db --base release --head master --title "Release <version>" --body-file <path> --milestone <ver> --assignee @me
   ```
   (note: no `--draft`)
4. Record PR number in `state.releasePR`. Update step status to `done`.

### 2. Triage stale baselines PRs

The next step force-resets `linq2db.baselines/master` to the anchor — that invalidates every currently-open baselines PR (their diffs target a master that no longer exists). Triage them **before** the reset so the stale state doesn't linger after CI re-opens fresh baselines PRs against the reset master.

Use `.claude/scripts/baselines-triage.ps1` — it owns the whole step (list → resolve every parent's state + milestone in **one** GraphQL round-trip → classify → comment + close in parallel). Hand-rolling it costs 2 + 2N `gh` calls and walks into two traps: `gh --body` is banned repo-wide, and the comment text contains backticks, which a shell reads as command substitution. The script passes `--body-file` for exactly that reason.

Action:
1. Dry-run to get the plan (no mutations):
   ```
   pwsh -NoProfile -File .claude/scripts/baselines-triage.ps1 -Version <ver>
   ```
   Returns `{ total, keep[], close[] }`. Classification:
   - **`keep[]`** — parent is on the release milestone. These are the ones we WANT regenerated, so they're never auto-closed. Tell the user to re-run CI on those parent PRs after the reset.
   - **`close[]`** — everything else: another milestone, no milestone, a closed/merged parent, or a title with no parseable `/pull/<n>`. All are stale the moment master moves.
2. Surface the plan as a table (baselines PR → parent → parent milestone) and get explicit confirmation. **Call out when a `close[]` parent is still open** — each one costs its author a CI re-run, and a release can legitimately land with every open baselines PR belonging to the *next* milestone (6.4.0: all 12 were open parents, 10 on 6.5.0). That's the norm, not an anomaly, but the user decides.
3. On confirmation, apply:
   ```
   pwsh -NoProfile -File .claude/scripts/baselines-triage.ps1 -Version <ver> -Apply
   ```
   Per-PR rows come back in `results[]` with independent `comment` / `close` status, so a partial failure is visible per item rather than collapsing into one exit code.
4. **Verify against the repo, not the script's own summary** (`agent-rules.md` → *a reported result is a claim, not evidence*): `gh pr list --repo linq2db/linq2db.baselines --state open` should be empty of the closed set, and `gh api repos/linq2db/linq2db.baselines/git/matching-refs/heads/baselines --jq 'length'` should drop by the number closed.
5. Surface counts: "N closed, M for current-milestone (told user to re-run CI on parent PRs)." Update step status `done`.

**A leftover `baselines/pr_<n>` branch with no open PR is not yours to delete.** The ref-count check in step 4 can show a residue branch whose PR was closed in an earlier release's triage without `--delete-branch`. Leave it: per `agent-rules.md` → *never delete a user-owned artifact*, and CI force-pushes over that head ref on the parent's next run anyway. Note it and move on. (6.4.0: `baselines/pr_5376` survived, parent open on 6.5.0.)

### 3. Reset baselines repo HEAD

This is a destructive operation on a shared repo. **Two-tier confirmation: describe + confirm + execute.**

Read the baselines anchor commit from [`first-run-todos.md`](../../docs/release/first-run-todos.md) (or its successor doc once stable). Current documented value: `f6b4f6278e5e53f38b6a26350f80b0609b37e86e` ("update gitattributes"). Surface to user on every release for confirmation — anchor may shift over time.

**Reset the *remote ref*, not a working tree.** The goal is `origin/master == anchor`; a local checkout is only a means to that end, and reaching for one drags in problems that have nothing to do with the release. Inspect the clone's state first and pick the cheapest path.

Action:
1. In `linq2db.baselines` clone (path from `external-repos.md`):
   ```
   git -C <baselines-path> fetch origin --prune
   git -C <baselines-path> branch -vv --list
   git -C <baselines-path> rev-list --count <anchor-sha>..origin/master
   ```
   `branch -vv` is the load-bearing one: it shows where local `master` points and whether it is checked out in **another worktree** (a `+` prefix and a path in parentheses). `--prune` also confirms the step-2 branch deletions landed.

2. **Confirm the discarded commits are all regenerable baselines** before proposing the reset:
   ```
   git -C <baselines-path> log --format=%s <anchor-sha>..origin/master --invert-grep --grep='^Baselines for'
   ```
   Everything this prints should still be a baselines commit under a different title (per-CI-leg PRs land as `[Linux / DuckDB] baselines (#NNNN)`). Anything that looks like a real config change (`.gitattributes`, `.gitignore`, tooling) means the anchor is stale — stop and ask rather than discarding it.

3. Surface to user:
   > _"About to **force-reset** `linq2db.baselines` master to commit `<anchor-sha>` ("update gitattributes") and force-push. This discards N commits of baselines on top — they'll be regenerated cleanly by CI on the release PR. Confirm to proceed."_

4. On explicit `yes`, push the ref. **Prefer the no-checkout form**, which needs no branch switch and touches no working tree:
   ```
   git -C <baselines-path> push origin <anchor-sha>:refs/heads/master --force-with-lease
   ```
   When local `master` is already at the anchor (common — it stays parked there between releases), `push origin master:master --force-with-lease` is equivalent and reads more obviously.

   Fall back to `switch master` + `reset --hard <anchor-sha>` + `push origin master --force-with-lease` only when you actually want the local branch moved. Two ways that bites:
   - **`master` may be checked out in another worktree**, so `git switch master` fails with `fatal: 'master' is already used by worktree at …` — including when that worktree's directory has been deleted and only a stale registration remains (`git worktree prune` clears it, but you don't need to).
   - **The main checkout may be parked on a stale `baselines/pr_<n>` branch with a huge dirty tree** (6.4.0: 281 399 pending deletions). A branch switch there is a long, risky operation that the reset does not require.

   `--force-with-lease` (not bare `--force`) protects against races — if someone else pushed to master after our fetch, the push fails and we re-verify.

   **Misleading remote line:** GitHub may print `remote: - Cannot force-push to this branch` followed by a successful `+ <oldSha>...<newSha> master -> master (forced update)` line. The "Cannot force-push" line is a non-blocking server-side warning hook; the push actually succeeded. Verify with `git -C <baselines-path> ls-remote origin master` — if it returns the anchor SHA, you're done.
4. Update step status `done`.

### 4. Prerelease-nuget team-test gate [R2-A in plan]

CI produces prerelease nugets to pipeline artifacts. This step blocks until the user confirms team tests passed.

**Testing should already be under way.** [`/release-verify`](../release-verify/SKILL.md) step 6a hands the team nugets from the **prep PR**, because `build.yml` (`with_nugets: true`, triggers on every PR) publishes a `nugets` artifact on each prep push. Treat this step as *confirmation plus delta-check*, not the first ask — if `state.publish.steps.team-test.note` records an earlier handover, name the build the team already tested and ask only about what changed since.

**The delta matters.** Fixes routinely land between the prep-PR build and the release PR — on 6.4.0 both #5743 and #5744 merged after the prep merge, so the release PR's bits were not what the team first received. Compare the artifact the team tested against the current release-PR build and say plainly which commits are new.

Action:
1. Get the build run and its artifact URL: `gh pr checks <release-pr> --json name,link` — the `link` is the pipeline URL to surface to the user.
   `azp-build-failures.ps1 -BuildId <buildId>` is for *diagnosing failures*, not for links: it emits `{buildId, logsDir, failedTaskCount, tasks[]}` and carries no pipeline/build web URL (only per-task API `logUrl`s), so it has nothing to surface on a green build.

   **Confirm the artifact exists rather than inferring it from the check colour.** A release PR's aggregated checks can be red for reasons that have nothing to do with packaging, so query the artifacts directly:
   ```
   (Invoke-RestMethod "https://dev.azure.com/linq2db/<project-guid>/_apis/build/builds/<id>/artifacts?api-version=7.0").value
   ```
   Expect `nugets` (~1.2 GB) and `linq2db_linqpad_lpx` (~75 MB).

   **A red `default` check does not necessarily block this step.** Two traps, both hit on 6.4.0:
   - The release PR's head **is** `master`, so `master` *push* builds alias onto the PR's check list. A failure there may belong to a master build, not the PR's own build — always resolve the `buildId` behind a failing check and read its `sourceBranch` before treating it as a release blocker.
   - `Publish to Azure Artifacts feed` and `Publish to Nuget.org` are **skipped on PR builds** and run only on master pushes. An `HTTP 402 (Payment Required — max quantity has been exceeded)` from the Artifacts feed therefore fails master builds while leaving the release PR's packaging entirely intact. It is a real infrastructure problem, but not a gate on this step.
2. Print:
   > _"Prerelease nugets ready at `<CI artifact URL>`. Notify the team for their custom testing (whatever validation they own outside CI test-all). Reply `tests green, proceed` when ready, or `regression found, paused: <description>` to pause the release."_

   When the team already tested a prep-PR build, use instead:
   > _"The team tested build `<prep build id>` from the prep PR. The release PR's build `<id>` adds: `<commits merged since>`. Confirm the team is happy with the delta — `tests green, proceed`, or `regression found, paused: <description>`."_
3. Block. Two valid replies:
   - **`tests green, proceed`** → update step status `green`. Continue to step 5.
   - **`regression found, paused: <reason>`** → update step status `paused` with reason in `state.publish.steps.team-test.note`. Skill stops. On resume:
     1. Ask: "regression fixed? `fixed` to re-test; `still investigating` to wait; `abort release` to abandon."
     2. On `fixed`: ask "where was the fix landed — back on `release-prep/<ver>` (extends prep), or directly on `release`?" — depends on user judgement and project conventions. The skill records the answer; the actual fix is user-driven.
     3. After fix, return to step 4.1 (re-fetch nugets, re-notify team).

### 5. Merge release PR

Preconditions:
- Steps 1, 2, 3 `done` and step 4 `green`.
- User explicitly typed `tests green, proceed`.

Action:
1. Verify mergeability:
   ```
   gh pr view <release-pr> --repo linq2db/linq2db --json mergeable,mergeStateStatus,headRefOid,baseRefOid
   ```
2. Print the merge command — **do not run it**:
   ```
   gh pr merge <release-pr> --repo linq2db/linq2db --merge
   ```
   (`--merge`, not squash — `release` branch should reflect the linear `master` history that's been validated.)
3. Ask user to run the merge themselves and confirm done. Skill detects via:
   ```
   gh pr view <release-pr> --repo linq2db/linq2db --json state,mergedAt
   ```
4. On `state == "MERGED"`:
   - Update step status `done`.
   - Update `state.currentPhase = 'postpublish'`.
   - Dispatch to `Skill('release-postpublish')` to start the publish flow (official nuget upload, docs PR, GitHub release).
   - Steps 6 + 7 (baselines) remain `open` in the publish-phase state; the orchestrator tracks them as parallel work alongside postpublish. They don't block postpublish progress.

### 6. Merge CI-generated baselines PR

CI runs on the release PR, regenerates baselines, opens a PR against `linq2db.baselines` master (head ref `baselines/pr_<release-pr-#>`). This step runs **in parallel with `/release-postpublish`** — it's not on the release-merge critical path.

Action:
1. Print: "wait for CI to open the baselines PR on `linq2db.baselines`. Notify me when it's open (or when CI completes — I can detect via `gh pr list --repo linq2db/linq2db.baselines`)."
2. Poll on demand:
   ```
   gh pr list --repo linq2db/linq2db.baselines --state open --search "baselines/pr_<n>"
   ```
3. When PR exists, surface its number + URL + diff stats. Ask the user:
   > _"Merge the baselines PR? (review the diff first — if it has unexpected non-test-change drift, pause and investigate.)"_
4. The baselines PR is opened as **draft** by CI. Mark ready first, then squash-merge with branch delete:
   ```
   gh pr ready <baselines-pr> --repo linq2db/linq2db.baselines
   gh pr merge <baselines-pr> --repo linq2db/linq2db.baselines --squash --delete-branch
   ```
   **Merge mode:** `linq2db.baselines` repo only permits **squash** merges — `--merge` is rejected with `GraphQL: Merge commits are not allowed on this repository`, and `--rebase` with `Rebase merges are not allowed on this repository`. Squash is the only option; the baselines workflow tolerates the squashed history.

   **502 quirk:** the GraphQL `mergePullRequest` mutation often returns `502 Bad Gateway` while actually succeeding. After a 502, **always** re-fetch the PR state (`gh pr view <n> --repo linq2db/linq2db.baselines --json state,mergedAt,mergeCommit`) before retrying — duplicate merge attempts on an already-merged PR error out differently and complicate diagnosis.

   **Empty-diff display bug:** very large baselines PRs sometimes render as `0 additions / 0 deletions / 0 changedFiles` in the GitHub UI and `gh pr view`. The diff is real — the renderer gives up past some threshold. Don't interpret zero as "nothing changed and the PR can be closed"; merge it anyway.
5. Update step status `done`. Capture the merge commit SHA in `state.publish.baselinesMergeSha`.

### 7. Copy + tag baselines on releases branch

The `releases` branch in `linq2db.baselines` holds **one squashed commit per release** ("Baselines v6.2.0", "Baselines v6.2.1", "Baselines v6.3.0", …) where each commit's tree is the full baselines for that version. `releases` is **a parallel history to `master`** — common ancestor is the initial commit, so `merge --ff-only origin/master` will not work and is not the intended convention. The actual procedure: snapshot master's current tree onto a new commit on releases, tag, push. Like step 6, runs in parallel with `/release-postpublish`.

**A tagged baselines release is a *snapshot of master*, nothing more.** The new commit's tree must equal `origin/master`'s tree exactly. Files left over from previous releases are not carried forward — baselines are keyed by fully-qualified test name and never auto-prune, so `releases` otherwise accumulates orphans from renamed or no-longer-capturing tests indefinitely.

> **Do not use `git checkout origin/master -- .` for this.** It *overlays* master onto the existing `releases` tree: it adds and overwrites, but never deletes paths that exist on `releases` and not on master. The result is a union, not a snapshot. On 6.4.0 that would have carried **2,078** stale files (master 309,352 files, releases 281,409, of which 2,078 were releases-only) — and earlier tags produced this way already carry theirs.

**No checkout is required.** Build the commit from master's tree directly, which also sidesteps the state this clone is usually in (main checkout parked on a stale `baselines/pr_<n>` branch with a huge dirty tree, `master` possibly claimed by another — sometimes stale — worktree) and avoids materialising ~300 k small files on disk.

Action:
1. Fetch, then resolve master's tree and the current `releases` head:
   ```
   git -C <baselines-path> fetch origin --prune
   git -C <baselines-path> rev-parse 'origin/master^{tree}'
   git -C <baselines-path> rev-parse origin/releases
   ```
2. Create the snapshot commit with master's tree, parented on `releases` (no body — the tag is the navigation handle):
   ```
   git -C <baselines-path> commit-tree <master-tree-sha> -p <releases-head-sha> -m "Baselines v<version>"
   ```
3. Move the branch and tag the new commit. Pass the expected old value to `update-ref` so a concurrent change fails the call instead of being clobbered:
   ```
   git -C <baselines-path> update-ref refs/heads/releases <new-commit-sha> <releases-head-sha>
   git -C <baselines-path> tag v<version> <new-commit-sha>
   ```
   Tag convention is `v<ver>` (confirmed via `git tag -l`: v6.0.0, v6.1.0, v6.2.0, v6.2.1, v6.3.0, …). Verify on first run for a new repo.
4. **Verify it is a true snapshot before pushing** — this is the whole point of the step:
   ```
   git -C <baselines-path> rev-parse 'v<version>^{tree}'          # must equal <master-tree-sha>
   git -C <baselines-path> ls-tree -r --name-only v<version> | wc -l   # must equal master's file count
   ```
   A `git diff --shortstat v<prev> v<version>` is useful context for the user (6.4.0: 272 585 files changed, 1 478 404 insertions, 1 082 475 deletions) but is *not* the check — only the tree equality is.
5. Push branch + tag separately (don't use `--tags` — that pushes every local tag including junk):
   ```
   git -C <baselines-path> push origin releases
   git -C <baselines-path> push origin v<version>
   ```
6. Update step status `done`. Capture the new releases-branch HEAD SHA in `state.publish.baselinesReleasesSha`.

## Recovery procedures

### One package blocks the CI publish job mid-batch

Symptoms: AzDO `default (Nugets Generation)` job fails with `HTTP 413 (The package file exceeds the size limit)` or another nuget-push error on a specific package. Earlier packages in the batch were already pushed to nuget.org (visible via `release-nuget-verify.ps1`); later packages weren't. **The publish job is atomic-fail at the job level but per-package at the push level**; recovery is to push the missing ones manually.

Procedure (verified on 6.3.0 — `linq2db.cli` at 416 MB exceeded 250 MB ceiling, blocking the rest of the publish job):

1. **Identify the failing package** from the AzDO log — fetch the timeline + the `Publish to Nuget.org` task log via:
   ```
   curl -s 'https://dev.azure.com/linq2db/0dcc414b-ea54-451e-a54f-d63f05367c4b/_apis/build/builds/<id>/timeline?api-version=7.0' > timeline.json
   ```
   Walk `records[]` for `result == 'failed' && type == 'Task'`, fetch `log.url`, grep for `Pushing` + `error`. The last `Pushing <name>` before the error names the failing package.

2. **Download the `nugets` artifact** from the same AzDO build:
   ```
   gh api 'repos/linq2db/linq2db/commits/<release-merge-sha>/check-runs' \
       --jq '.check_runs[] | select(.name=="default") | .details_url'
   # extract build id, then:
   curl -s '<artifact-download-url>?format=zip' -o release-<ver>-nugets.zip
   ```
   The `downloadUrl` field of the `nugets` artifact in the build's `_apis/build/builds/<id>/artifacts` endpoint is the canonical URL.

3. **Push remaining packages**, skipping the failing one + already-published ones via `--skip-duplicate`:
   ```
   $key = '<nuget-org-api-key>'
   $pkgs = Get-ChildItem '<extract-dir>' -Recurse -Filter '*.nupkg' | Where-Object { $_.Name -notlike '<failing-name>.*' }
   $pkgs | ForEach-Object -Parallel { dotnet nuget push $_.FullName --source 'https://api.nuget.org/v3/index.json' --api-key $using:key --skip-duplicate --timeout 600 } -ThrottleLimit 4
   ```
   `--skip-duplicate` handles already-published packages without erroring. Confirm via `release-nuget-verify.ps1` afterward.

4. **Add a "delayed" note** to the GH release body (top, blockquote style):
   > **Note:** `<failing-package> <ver>` publish is **delayed** — <one-line reason, e.g. "package exceeds nuget.org's 250 MB upload limit (HTTP 413)">. Tracked separately; will be published once <fix>. All other <N> packages in the release line are live.

5. **File an issue** for the root cause; link from the GH release note.

6. **Mark `state.postpublish.steps.nuget-verify.status = 'partial'`** (not `done`) with annotation pointing to the issue + the count of published-vs-deferred packages.

7. **Flag downstream impact** to the user: if any deferred package is referenced by `Directory.Packages.props` in the next-version-bump PR (e.g. `linq2db.t4models` re-pin), that PR's CI will fail until the deferred package finally publishes. User merges the bump PR manually after.

## Don'ts

- Do **not** auto-run `git reset --hard` or `git push --force` in step 3. Always two-tier confirm (describe + confirm + execute), and always with `--force-with-lease`, never bare `--force`.
- Do **not** auto-merge the release PR in step 5 or the baselines PR in step 6. The skill prepares + verifies + asks; the user runs the merge.
- Do **not** skip step 4 (team-test gate). CI test-all passing is necessary but not sufficient — the project ships consumed by external testers, and their feedback is the last release-blocking signal.
- Do **not** transition `state.currentPhase` from `publish` to `postpublish` before step 5 confirms `MERGED`. Premature transition strands the publish phase mid-flow on session resume. Steps 6 + 7 (baselines) intentionally remain `open` after the phase transition — they run alongside postpublish.
- Do **not** treat a paused team-test as a release failure to retry automatically. It's a deliberate human-driven decision — wait for explicit user direction on resume.
- Do **not** silently use a different baselines anchor SHA than the one documented. If the anchor needs to change, the user updates `first-run-todos.md` (or a successor doc) and confirms the new value.
