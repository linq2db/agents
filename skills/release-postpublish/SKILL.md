---
name: release-postpublish
description: Post-release-merge tasks. Verifies every expected linq2db nuget published to nuget.org at the release version, opens the docs PR in linq2db.docs (submodule sync to the release tag), creates the GitHub release with the .lpx artifact and auto-generated New Contributors section, then opens the next-version bump PR with the new milestone and the `linq2db.t4models` self-reference re-pinned to the just-released version. Each step is its own explicit user-confirmed action. Invoked by `/release` after the release PR merges to the `release` branch.
---

# /release-postpublish

## What this skill is (and isn't)

**Is:** the post-publish wrap-up. Runs after the release PR merges and CI tag-and-publishes nugets. Verifies the publish succeeded, propagates the release to docs + GitHub release page, then bootstraps the next development cycle (new milestone + version bump + `linq2db.t4models` re-pin).

**Isn't:**

- Not for the release-PR merge or the prerelease nuget team-test gate. Those live in [`/release-publish`](../release-publish/SKILL.md).
- Not for editing the release-notes content. That happened in `/release-notes-validate` during prep; this skill consumes the finalized notes for the GitHub release body.
- Doesn't republish nugets — that's CI's job. The skill only **verifies** what CI shipped.

## When to run

- Automatically by `/release` orchestrator when `/release-publish` confirms the release PR merged.
- Manually when resuming a release mid-postpublish phase.

## Required reading

- [`.claude/docs/release/external-repos.md`](../../docs/release/external-repos.md) — linq2db.docs path + GitHub release template anchor (`v6.0.0`).
- [`.claude/docs/release/first-run-todos.md`](../../docs/release/first-run-todos.md) — exact `gh release create` invocation, exact docs PR submodule sync command (first-run-confirmable).

## Phase state

Five ordered steps, recorded in `state.postpublish.steps.<key>` by **direct edit of `.build/.agents/release-<ver>.json`** (no `release-state.ps1` action writes these keys — see `/release` step 6):

| Step | Key | Status flow |
|------|-----|-------------|
| 1. NuGet publish verify | `nuget-verify` | open → done / partial |
| 2. Docs PR | `docs-pr` | open → opened → merged → done |
| 3. GitHub release | `gh-release` | open → done |
| 4. Next-version bump PR | `next-bump` | open → done |
| 5. Close release milestone | `milestone-close` | open → done / parked |

## Procedure

### 1. NuGet publish verification

CI builds and publishes nugets on the release-branch merge. Packages can take **minutes** to appear on nuget.org — re-run as needed; this skill doesn't poll-wait.

Action:
1. Run the verifier:
   ```
   pwsh -NoProfile -File .claude/scripts/release-nuget-verify.ps1 -Action verify -Version <ver>
   ```
   The script:
   - Discovers packable projects under `Source/` and `NuGet/` — every csproj that isn't `<IsPackable>false</IsPackable>`. Dedupes by `<PackageId>` (or filename fallback) — EF variants share an ID.
   - Parallel-queries `https://api.nuget.org/v3-flatcontainer/<id>/index.json` (listed versions only).
   - Reports per-package: `published` (target version found), `latestListed` (most recent listed version), `fetchStatus`.
2. Render results:
   ```
   #  Package                              Target   Status     Latest listed
   1  linq2db                              6.3.0    ✓ published 6.3.0
   2  linq2db.SqlServer                    6.3.0    ✓ published 6.3.0
   3  linq2db.t4models                     6.3.0    ✗ missing   6.2.0
   ...
   ```
3. **Missing rows:** ask user: `re-run` (after waiting, packages may now be live) / `wait` (postpublish stays open) / `escalate` (something's broken — CI may have failed publishing; investigate before continuing).
4. Mark `done` only when **every** expected package is `✓ published`. Don't tick step 1 with missing rows.

**If the discovery list looks wrong** (a package the user expects is missing from the table, or an unpackable project is included): the script's heuristic (csproj `<IsPackable>` + `<PackageId>` element) can be off for niche cases. Add the missing id via `-ExtraIds linq2db.foo` and re-run; or fix the csproj heuristic detection in the script if the case is general.

### 2. Docs PR (linq2db.docs)

The docs site is built from a separate repo (not `linq2db.github.io` — that's the published site, CI-updated from this one).

**The GitHub repo is `linq2db/docs`, even though the local clone is conventionally `../linq2db.docs`.** Every `gh` call needs `--repo linq2db/docs`; `linq2db/linq2db.docs` does not exist and fails with *"Could not resolve to a Repository"*. Confirm with `git -C <docs-path> remote -v` rather than inferring the slug from the directory name.

Action:
1. Verify clone exists at the path recorded in `external-repos.md` (default `../linq2db.docs`). If missing, ask user for the correct path; record + session-reload.
2. **Sync only the linq2db submodule.** The repo has two (`git -C <docs-path> submodule status`): `submodules/linq2db`, which tracks branch **`release`** (so `--remote` lands exactly on the release-branch head), and `submodules/LinqToDB.Identity`, which tracks `master` and must **not** be bumped by a release sync. Name the path explicitly:
   ```
   git -C <docs-path> submodule update --remote submodules/linq2db
   ```
   A bare `--remote` moves both.
3. Create branch + sync + commit:
   ```
   git -C <docs-path> fetch origin
   git -C <docs-path> switch -c docs/release-<ver> origin/master
   git -C <docs-path> submodule update --remote submodules/linq2db
   git -C <docs-path> diff --submodule=short        # expect exactly one pointer change
   git -C <docs-path> add submodules/linq2db        # explicit pathspec, not `add .`
   git -C <docs-path> commit -m "Sync to linq2db <ver>"
   git -C <docs-path> push -u origin docs/release-<ver>
   ```
   Each git mutation is confirmed before run (per `agent-rules.md` → Git commit rules / Push to remote rules). The expected diff is one line — `-Subproject commit <old>` / `+Subproject commit <new>` — matching the release merge commit on `release`.
4. Create the PR (target: `master` on the docs repo). Title: `Docs: linq2db <ver>`. Body: bullet list of new public-API doc URLs that should be live post-merge.
5. Wait for CI to pass. Ask user to merge (or do `gh pr merge --squash --delete-branch` themselves — all three merge modes are enabled but the history is linear `(#NN)` squashes, and `delete_branch_on_merge` is **false**, so pass `--delete-branch` explicitly).

#### The vendored `docfx/` must track linq2db's Roslyn version

The docs repo vendors a **custom docfx build** (`<docs-path>/docfx/`, from `MaceWindu/docfx` branch `custom/linq2db`) rather than using the published tool. Its bundled `Microsoft.CodeAnalysis` has to be **>= the `Microsoft.CodeAnalysis.CSharp` version in linq2db's `Directory.Packages.props`**, because linq2db's `CodeGenerators` source generator is built against it. When docfx's Roslyn is older, the generator refuses to load and the build fails in a way that does not name the real cause:

```
warning: FailedToLoadAnalyzer: ... AnalyzerName: CodeGenerators,
         ErrorCode: ReferencesNewerCompiler, ReferencedCompilerVersion: <x>
error: ExpressionBuilder.cs(38,44): error CS8795: Partial method
       'ExpressionBuilder.FindBuilderImpl' must have an implementation part
```

The generated half of the partial never exists, so metadata extraction yields nothing and the run ends with `warning: No .NET API detected for .`. **This recurs on every linq2db Roslyn bump** — 6.3.0 needed 5.0 → 5.3, 6.4.0 needed 5.3 → 5.6. Check it up front: compare `Microsoft.CodeAnalysis.CSharp` in linq2db's `Directory.Packages.props` against `(Get-Item <docs-path>/docfx/Microsoft.CodeAnalysis.CSharp.dll).VersionInfo.ProductVersion`.

To refresh (needs the `MaceWindu/docfx` clone, default `c:/GitHub/docfx`, branch `custom/linq2db`):

1. Bump all eight `Microsoft.CodeAnalysis*` pins in its `Directory.Packages.props` to linq2db's version.
2. `dotnet publish src/docfx/docfx.csproj -c Release -f <tfm> -o <staging>` — take `<tfm>` from the vendored `docfx/docfx.runtimeconfig.json` (`net9.0` as of 6.4.0), not from the csproj's `TargetFrameworks`.
3. **Overlay** the staging output onto `<docs-path>/docfx/`; do **not** delete the directory first.
4. Rebuild the docs locally to verify *before* committing either repo.

> **Overlay, never replace.** `dotnet publish` emits ~487 files; the vendored directory holds ~875. The difference is a `templates/` tree (388 files) that publish never produces — docfx packs templates in its `PackTool` target — plus a committed `.playwright/` folder. Wiping and copying silently destroys them; docs PR **#62 ("Restore docfx/templates…")** exists because that already happened once. After copying, assert the count: `templates/` must still hold 388 files, and `git status` should show **zero deletions**.

Expect the refresh to add files as well as modify them (Roslyn 5.6 brought 15 new `Microsoft.Extensions.*` / `System.*` dependencies). A commit of ~79 changed files with 0 deletions is the healthy shape.

**A Roslyn bump can expose latent bugs in the custom patch.** The custom `VisitorHelper.GetGlobalId` had a null-dereference on symbols whose `ContainingAssembly` is null (reached via `XmlComment.ResolveCrefLink`) that had never fired, because the build always died at CS8795 first. Fixed in `MaceWindu/docfx` `591d070e7`. If the refreshed build fails somewhere inside `Docfx.Dotnet`, check the custom patch (`git show <custom-commit>`) before assuming an upstream docfx bug.
6. After merge, verify a known new API doc URL resolves on the published site. **First run:** ask the user for a known-good URL pattern (e.g. `https://linq2db.github.io/api/LinqToDB.<new-type>.html`); record in `external-repos.md` → docs-site verification.
7. Mark step `done`.

### 3. GitHub release

Use the v6.0.0 template anchor (from `external-repos.md`). The `--generate-notes` flag is critical for the "New Contributors" auto-section — releases without it are missing that section.

Action:
1. Pull the `.lpx` artifact from the release-build pipeline.
   - **First run:** ask the user for the exact artifact path / download command (CI build URL → Artifacts → linq2db.LINQPad.lpx). Record in `first-run-todos.md` → resolved section under **GitHub release artifact path**.
   - Download to `.build/.agents/release-<ver>-artifacts/linq2db.LINQPad.lpx`.
2. Draft the release body. Short terse version of the wiki release notes (the wiki has the full version). On first run, look at the v6.0.0 release page (`gh release view v6.0.0 --repo linq2db/linq2db`) to see the body template, then craft a parallel body for the current release. Surface the draft to user for review.
3. Create the release as a **draft** — **after** user confirms title + body + artifact list:
   ```
   gh release create <tag> --repo linq2db/linq2db --title "<ver>" --notes-file <body-md> --draft --generate-notes <lpx-path>
   ```
   - `<tag>` is the same as `<ver>` unless the project uses `v`-prefix tags — confirm on first run (`gh release list --repo linq2db/linq2db --limit 5` shows existing tag conventions).
   - Attach **only** the `.lpx`. Do **not** attach `.lpx6` or `.nupkg` (per user rule — those aren't useful as release attachments).
   - `--generate-notes` ensures the auto-generated "New Contributors" + "Full Changelog" sections appear underneath the user-authored body.
   - `--draft` lets the user tune the text on GitHub before publishing. **Tell the user** at this point: _"Release draft created at `<url>`. You can adjust the body / title / tag / attachments directly on GitHub before publishing. The `--generate-notes`-produced contributors + changelog sections are appended to your body; edit there too if needed."_ The publish step (4 below) is when the release goes live.
4. Wait for the user's explicit `publish` to make the draft live:
   ```
   gh release edit <tag> --repo linq2db/linq2db --draft=false
   ```
   Or the user clicks "Publish release" on GitHub manually.
5. Mark step `done`. Record release URL in `state.postpublish.steps.gh-release.url`.

**The pipeline already created a draft — fill it, don't create a second one.** The release build's *Create Release Draft* step (`build-job.yml`) opens the draft as soon as the release branch builds, with only a one-line body (`[Release notes](…) [Nugets](…)`) plus `--generate-notes` output. This step's job is to replace that body with the authored one, so the flow is a **PATCH of the existing draft**, not a `gh release create`.

**Keep *New Contributors*, drop *What's Changed*.** `--generate-notes` emits all three of `What's Changed`, `New Contributors` and `Full Changelog` in a single API call — there is no flag to select among them, which is why the pipeline keeps the flag (the contributor credit is wanted) and the *body* is trimmed by hand here. Cut everything from `## What's Changed` up to `## New Contributors`; on 6.4.0 that took the body from 21 KB of 126 PR titles down to 5.1 KB. Compose it by slicing the fetched body at the `## New Contributors` anchor and prepending the authored preamble.

**Source the preamble from the release-notes harvest, not from PR titles.** Task 5 of the prep phase already produced curated per-PR blurbs at `.build/.agents/release-<ver>-notes-harvest.json`; read `items[]` where `includeBrief && !omit` (36 entries on 6.4.0). Structure follows the previous release's body: `Highlights of this release:` → `Provider-specific highlights:` → per-tool sections → `[Full release notes](<wiki-anchor>)` + `[Nugets](…)`.

> **`tag_name` is stripped by a PATCH that omits it.** Sending only `body` to `PATCH /repos/{o}/{r}/releases/{id}` on a **draft** release silently resets the tag to `untagged-<hash>`. Always include `tag_name`, `target_commitish` and `name` in the payload, then re-fetch and verify all of them plus the body (`github-authoring.md` → *draft-release `tag_name` strip on PATCH*). Hit on 6.4.0 despite being documented.

> ### ⚠ The release tag must land on `master`, never on the release-branch merge commit
>
> Whatever path creates the tag, it has to point at a commit **reachable from `master`** — i.e. the `master`-side (second) parent of the `master` → `release` merge, not the merge commit itself.
>
> **Why it matters.** `gh release create --fail-on-no-commits` (used by the release pipeline's *Create Release Draft* step) calls `isNewRelease`, which compares `{latest-release-tag}...HEAD` — where `HEAD` is the **default branch** — and accepts **only** `status == "ahead"`. A tag on the release-branch merge commit is unreachable from `master`, so the comparison returns `"diverged"` and gh reports *"no new commits since the last release"* even when there are hundreds. It ignores `--target` entirely: only the *previous* release's tag position matters.
>
> **The damage is deferred by exactly one release**, which is what makes this so easy to reintroduce: mis-tagging release *N* breaks release *N+1*'s build, not its own. On 6.4.0, `Create Release Draft` failed this way, and because it runs inside `build_job` — which `build_nugets_job` gates on via `dependsOn: build_job` + `condition: succeeded()` — the entire **nuget.org publish was skipped**. A cosmetic notes step blocked the actual release.
>
> **Content is identical either way**, so there is no reason to prefer the merge commit: the release merge brings `master` into `release`, so the merge commit's tree equals the `master`-side parent's tree (verified on 6.4.0 — both `841dc683d5`; and on 6.3.0 — both `51c6c066a1`).
>
> Get the right SHA from the merge commit, then verify before relying on it:
> ```
> gh api repos/linq2db/linq2db/git/commits/<release-merge-sha> --jq '.parents[1].sha'
> gh api "repos/linq2db/linq2db/compare/<that-sha>...HEAD?per_page=1" --jq '{status, behind_by}'
> ```
> Require `status == "ahead"` and `behind_by == 0`.
>
> **If a past release was mis-tagged**, move the tag rather than editing the release (the stored `target_commitish` is only consulted when the tag is *created*, so editing it changes nothing once the tag exists):
> ```
> gh api -X PATCH repos/linq2db/linq2db/git/refs/tags/<tag> -f sha=<master-side-sha> -F force=true
> ```
> Only safe while the release is not immutable — check `gh release view <tag> --json isImmutable`. (Done for `v6.3.0` on 2026-08-07: `b8263fd60` → `24d6a8e05`, identical trees, which unblocked the 6.4.0 release build.)

**Optional early draft:** During release prep (`/release-deps`/`/release-test-matrix` phase), the user may draft the GH release body early — and it's a strict win to do so, since `gh release create --draft` is cheap and lets the user iterate on body text incrementally without skill round-trips. If they did the early draft, this step (1) re-targets the draft via `gh release edit <tag> --target <sha>` to the **`master`-side parent of the release merge** — *not* the release-branch HEAD, per the warning above — (2) attaches the `.lpx` (early draft has no artifact), (3) surfaces the URL again with the "you can tune text on GitHub" reminder, (4) waits for user `publish`.

### 4. Next-version bump PR (+ new milestone + `linq2db.t4models` re-pin) [R2-H]

Bootstrap the next development cycle.

Action:
1. **Compute next version.** Default: increment minor, reset patch (`6.3.0` → `6.4.0`). Show user:
   > _"Next version: `6.4.0` (default minor bump). Confirm or override: `6.4.0` / `6.3.1` / `7.0.0` / custom."_
2. **Milestone check.** Read open milestones; if `<next-ver>` isn't there:
   > _"Milestone `<next-ver>` doesn't exist. Create it? (`gh api repos/linq2db/linq2db/milestones --method POST -f title=<next-ver>`)"_
   On `yes`, create. Don't auto-create — explicit confirmation.
3. **Dispatch `/version-bump`.** The existing skill edits `Directory.Build.props` (Version + EFxVersion). Per its contract it creates branch `infra/bump-versions` from `origin/master` and stops at "ready for user to confirm + commit + push + PR".
4. **Additionally re-pin `linq2db.t4models`.** Open `Directory.Packages.props`, find the `<PackageVersion Include="linq2db.t4models">` entry, update its `Version=` to the **just-released** version (the `<ver>` we just published, e.g. `6.3.0` — not the new `<next-ver>`). Show diff. This goes on the same `infra/bump-versions` branch as the version edits.
   - Grep for any other linq2db-published self-references (`<PackageVersion Include="linq2db..." />`) and flag for the user — there should only be `linq2db.t4models` today, but surface anything else found.
5. **User-driven commit + push + PR.** Per `/version-bump`'s contract, the skill does not commit / push / open PR automatically. Surface the full diff for confirmation. On user `go`:
   - `git add Directory.Build.props Directory.Packages.props`
   - `git commit -m "Bump versions for <next-ver>; pin linq2db.t4models to <ver>"`
   - `git push -u origin infra/bump-versions`
   - `gh pr create --base master --head infra/bump-versions --title "Bump versions for <next-ver>" --body-file <body> --milestone <next-ver> --assignee @me --draft`
6. Mark step `done`. Record bump PR number in `state.postpublish.steps.next-bump.pr`.

**Parked-merge if a published-this-release nuget is deferred.** If `state.postpublish.steps.nuget-verify.status == 'partial'` (per /release-publish's recovery flow — at least one package's publish to nuget.org was deferred due to size / transient failure / etc.), check whether the deferred package is referenced by `Directory.Packages.props` on the bump branch. The most common case is `linq2db.t4models` — if it's the deferred one, the bump PR's CI will fail to restore `>= <ver>` until t4models actually lands on nuget.org. Flag this to the user explicitly:

> _"Bump PR #<n> references `<deferred-package> <ver>` which is **not yet on nuget.org** (per nuget-verify partial status). CI will fail with NU1102 until the package is published. PR is parked — user merges manually after the deferred publish lands."_

Don't auto-retrigger CI repeatedly while parked; one retrigger after the deferred package lands is enough.

### 5. Close release milestone

Closes the milestone tracking issues + PRs that landed in this release.

**Preconditions are only these two:** the release has shipped (packages live on nuget.org, GitHub release published) **and** the milestone has no open issues or PRs. It does **not** wait on the docs PR merging or the bump PR existing — neither is tracked by the release milestone, so gating on them just leaves a finished, empty milestone open for no reason. Numbered last because that is usually when it becomes clean, not because the other steps block it: close it the moment both preconditions hold, which is often right after step 3. (Closed this way on 6.4.0 — 175 closed / 0 open, with the docs PR still open and no bump PR yet.)

**Don't let it slip.** This is the step most easily dropped, because by now the visible work is done and attention has moved to the next cycle. When reporting remaining postpublish work, list it explicitly rather than summarising the tail as "docs + bump" — an empty milestone left open is invisible until someone goes looking for it. (On 6.4.0 the user had to ask.)

Action:
1. Verify the milestone has no open issues/PRs left:
   ```
   gh issue list --repo linq2db/linq2db --milestone <ver> --state open --limit 50 --json number,title,state,url
   gh pr list    --repo linq2db/linq2db --milestone <ver> --state open --limit 50 --json number,title,state,url
   ```
2. **Open items must clear or move first.** Two valid outcomes per item:
   - **Clear** — issue/PR is done but accidentally still open. Close it (issue: `gh issue close`; PR: only if it should have been merged or is no longer relevant).
   - **Move to next milestone** — work continues on `<next-ver>`. `gh issue edit <n> --milestone <next-ver>` / `gh pr edit <n> --milestone <next-ver>`.

   Surface the list to the user; **don't auto-move or auto-close** — the routing decision is per-item.
3. **Park if any item can't clear or move yet.** Common case: a deferred-publish package's follow-up fix issue (e.g. 6.3.0's `linq2db.cli` size issue #5535 + the related parked bump PR) is still being worked, and closing the milestone would mask the outstanding work. In that case:
   - Mark step status `parked` with an annotation pointing at the blocking item(s).
   - Don't close the milestone until those items resolve.
   - Periodically (next release prep / when user asks) re-check.
4. **Close once clean:**
   ```
   gh api repos/linq2db/linq2db/milestones/<number> --method PATCH -f state=closed
   ```
   (`<number>` is the milestone's numeric id, not the title — `gh api repos/linq2db/linq2db/milestones?state=open --jq '.[] | select(.title=="<ver>") | .number'`).
5. Mark step status `done`. Record close timestamp + items moved/closed counts in the annotation.

### Wrap-up

After all 5 steps `done` (step 5 may be `parked` if deferred items keep the milestone open):
1. Print a summary: "Release `<ver>` complete. Bump PR `#<n>` is open for `<next-ver>`. Milestone <closed | parked: <reason>>."
2. Suggest the user runs `/session-reflect` to capture any first-run learnings into the long-term docs.
3. Suggest archiving the release state file (`.build/.agents/release-<ver>.json`) — gitignored; can stay as historical record.

## Don'ts

- Do **not** auto-merge the docs PR or auto-publish the GH release. Both are user-driven mutations on shared / public surface.
- Do **not** skip `--generate-notes` on `gh release create`. The "New Contributors" auto-section is the user-visible artefact that gets missed when the flag is absent.
- Do **not** attach `.lpx6` or `.nupkg` to the GitHub release. Per user rule — those aren't useful and the practice is being dropped.
- Do **not** tick step 1 (nuget verify) with missing rows. Re-run after waiting; if persistently missing, treat as a CI publish failure and escalate.
- Do **not** bump `linq2db.t4models` to anything other than the **just-released** version. The point of this re-pin is to have the next release cycle's T4 tests consume the freshly-published nuget; bumping to the next-version-being-prepped would re-introduce the chicken-and-egg cycle the re-pin was designed to break.
- Do **not** include unrelated changes in the next-version bump PR. It's a single-purpose commit: Version + EFxVersion + `linq2db.t4models` re-pin.
