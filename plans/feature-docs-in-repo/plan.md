# Work plan: feature-docs-in-repo — Move docs into linq2db and publish them on release

**Tier:** L  ·  **Status:** approved  ·  **Approved-at:** 2026-11-07 (user; after critic round 2 `weak`, objections folded)  ·  **Branch:** feature/docs-in-repo
**Schema:** `.claude/docs/work-plan.md`  ·  **Gates:** `.claude/docs/definition-of-done.md`

Base: `origin/master` @ `83a7117d4`. Worktree `C:\Worktrees\linq2db\docs-in-repo`. Session design source (approved by the user 2026-11-07): plain copy, GitHub Actions publish, prebuilt hash-pinned docfx from the `MaceWindu/docfx` fork, path-filtered PR check, docfx fork pushed and synced with upstream head, re-synced during release prep. Companion branch `feature/docs-warnings` (own plan) fixes the `Source/**`-side docfx warnings; this branch's `-WarningsAsErrors` gate depends on it merging first.

## P1 Problem

Docs live in a separate repo, `linq2db/docs` (local clone `../linq2db.docs`), that pulls linq2db in as a submodule tracking `release` plus a second submodule `LinqToDB.Identity` pinned at v6.0.0, and vendors a ~97 MB custom docfx binary under `docfx/` (610 tracked files) to work around dotnet/docfx#8966 (upstream fix PR dotnet/docfx#11090 still open). Every release needs a hand-made "Docs: linq2db <ver>" PR there (`.claude/skills/release-postpublish/SKILL.md:83-150`): bump the submodule, re-vendor docfx whenever linq2db's Roslyn moves (6.3.0, 6.4.0, 6.5.0 all needed it, `:121`), merge, then wait for its Azure pipeline (definition 2) to push `_site` to `linq2db/linq2db.github.io` — 6.5.1's deploy (build 24629) queued 19:08Z and only started 22:47Z. Identity has since moved into this repo (`Source/LinqToDB.Identity`, #5640, merged 2026-11-04) with a deliberately breaking API (`LinqToDB.Identity.csproj:17-22`), so the docs repo's second submodule documents a superseded v6.0.0 package. Observable today: docs cannot be changed in the same PR as the code they describe, nothing builds docs on a linq2db PR, and a release is not "done" until a separate manual PR + pipeline round-trip completes.

## P2 Success criteria

- SC-1 From a clean checkout of this branch, `Docs/build.ps1` produces `.build/docs/_site` containing every API set listed in `Docs/source/toc.yml` plus the articles, using only a docfx downloaded from the URL in `Docs/docfx-version.json` and verified against its SHA-256 — no global docfx tool, no Node, no submodule. → TO-1
- SC-2 Outside `api/linq2db.identity/`, the generated site is URL-compatible with production: a file-list diff against a `linq2db/linq2db.github.io` checkout (6.5.1 content) shows no removed page except ones explained by public-API removals since `v6.5.1`. → TO-2
- SC-3 `api/linq2db.identity/` documents the in-tree package's net10.0 surface: the v6.0.0-only types are gone and the new types (including the net10.0 passkey overlay) are present. → TO-3
- SC-4 The home page and the Contributing article render the repo-root `README.md` and `CONTRIBUTING.md`. → TO-4
- SC-5 A `docfx.zip` whose SHA-256 differs from the pin fails `Docs/build.ps1` before docfx runs. → TO-5
- SC-6 `.github/workflows/docs.yml` runs on a PR touching `Docs/**`, `README.md`, `CONTRIBUTING.md` or the workflow itself, passes on good content, and fails on a broken cross-reference (`-WarningsAsErrors`). → TO-6, TO-7
- SC-7 On a PR that touches none of those paths, `docs.yml`'s build job is skipped (reported as skipped, so it can be a required check without blocking unrelated PRs). → TO-8
- SC-8 A `workflow_dispatch` with `deploy=false` builds and uploads the site and pushes nothing; a non-prerelease `release: published` event, or a dispatch with `deploy=true` from a `v*` tag, pushes the built site to `linq2db/linq2db.github.io` `master`; a prerelease does not deploy. → TO-9, TO-10, TO-11
- SC-9 The fork workflow `linq2db-build.yml` on a `linq2db-*` tag publishes a release asset `docfx.zip` whose SHA-256 equals the pin, and the pinned asset is the upstream-synced build whose site differs from the exact-replica build only in recorded, explained ways. → TO-12, TO-13
- SC-10 The release corpus has no step that opens a PR in `linq2db/docs`: `/release-postpublish` has a docs-publish step after the GitHub-release step, `/release-deps` carries the docfx fork sync with the Roslyn rules moved from postpublish, `/release-verify` runs the docs build, and every remaining `linq2db.docs` mention describes it as retired. → TO-14
- SC-11 The Release solution build and the existing CI workflows are unaffected by the new `Docs/` folder. → TO-15

## P3 Constraints & anti-goals (M/L)

- No docfx binaries, Node modules or generated `_site` / `api/` output committed to linq2db.
- Published URLs outside `api/linq2db.identity/` must not change: keep `metadata[].output` folder names, `assemblyUids` (minus Compat, D-5) and the four EF `assemblyUidOverride` values exactly as in `C:\GitHub\linq2db.docs\source\docfx.json`; Identity stays out of `assemblyUids`.
- Plain copy of content (user decision): no reformatting of the moved markdown/yml; only the two `[!include]` paths (E-11, E-12), docfx.json (E-2) and — named exception — any line that TO-1's census attributes a content-sourced docfx warning to (E-13) change.
- Sequencing: the corpus edits E-20…E-33 describe `Docs/build.ps1` and `docs.yml`, which exist only once this PR merges; they land as one agents-repo commit after the merge (corpus edits never go on a linq2db branch), and TO-14 runs then.
- No change to `Source/**` product code on this branch (warning fixes live on `feature/docs-warnings`).
- No change to Azure pipelines or existing GitHub workflows; nugets stay on Azure.
- Only GitHub-owned actions, SHA-pinned (`build.yml:17-18`; repo `allowed_actions: selected` + `github_owned_allowed`).
- The old `linq2db/docs` repo and its Azure pipeline are retired by the user after the first successful deploy, not by this branch.
- User-visible deltas vs master/production: (1) a new top-level `Docs/` folder and `docs.yml` workflow; (2) the site is rebuilt from the release tag instead of `release` branch head; (3) every v6.0.0 `api/linq2db.identity/*` URL (38 pages, measured from `linq2db.docs/source/api/linq2db.identity/`) is removed and replaced by the in-tree package's net10.0 surface — a consequence of #5640's breaking API, recorded in P10; (4) the `linq2db.Compat` metadata entry is dropped (toc line already commented out; it emits "No .NET API detected"), so no published page changes from it; (5) a prerelease no longer changes the site (the old pipeline never deployed per-release anyway).

## P4 Unknowns (M/L)

- U-1 Which TFM docfx metadata compiles for a multi-TFM csproj — Roslyn's MSBuildWorkspace loads the first `TargetFrameworks` entry (critic: no selection logic in the fork's `src/Docfx.Dotnet`; corroborated by Compat's "No .NET API detected", whose types exist only off net462, `Source/LinqToDB/Configuration/LinqToDBSection.cs:1-3`); for every non-Identity entry the csproj and TFM list are those of the 6.5.1 build, so output is unchanged; Identity changes (D-10) — resolved-by scout
- U-2 Identity page set — old: 38 yml in `linq2db.docs/source/api/linq2db.identity/` (`IConnectionFactory`, `IClameConverter`, `IConcurrency-1`, `IdentityUser{,-1,-4}`, `IdentityRole{,-1,-3}`, `IdentityDataConnection{,-1,-3,-8}`, `UserStore-{1,2,3,7}`, `…IdentityLinqToDbBuilderExtensions`, …); new: `Source/LinqToDB.Identity/PublicAPI*.txt` (+ `PublicAPI/net10.0/PublicAPI.Unshipped.txt` overlay) — `IdentityDataConnection-6/-9`, `IdentityDataContext-6/-9`, `UserOnlyStore-7`, `UserStore-10`, `…IdentityLinqToDBBuilderExtensions` (`DB` casing); namespaces `LinqToDB.Identity` / `Microsoft.Extensions.DependencyInjection` unchanged, so docfx.json's no-collision comment holds — resolved-by scout (critic file listing)
- U-3 Are the docs repo's three `NuGetAuditSuppress` entries needed — that `Directory.Build.props` never applied to linq2db projects (linq2db's own is nearer and imports no parent, `Directory.Build.props`), only to the external Identity submodule; dropped — resolved-by scout
- U-4 Can the deploy job push to another repo under the Actions policy — `actions/checkout` with `repository:` + `ssh-key:` then a shell `git push`; no third-party action — resolved-by scout
- U-5 Does `release: published` fire for a release a person publishes after Azure created it as a draft with `RELEASES_GH_PAT` (`build-job.yml:289-305`) — `publish-mcp.yml` relies on the same trigger for the same release — resolved-by scout
- U-6 What happens for a release whose tag predates `Docs/` — a `release`-triggered workflow is read from the tag's tree, so there is no run at all (`.claude/skills/release-postpublish/SKILL.md:188-190`, same rule for `publish-mcp.yml`); the first release cut after this merges is the first with a run — resolved-by scout
- U-7 Does a framework-dependent `dotnet publish` of docfx run on the runner — the vendored build is already framework-dependent net10.0, `rollForward: Major` (`linq2db.docs/docfx/docfx.runtimeconfig.json`) — resolved-by scout
- U-8 Can a fork workflow create a fork release — needs Actions enabled on the fork and `permissions: contents: write`; TO-12 proves it — resolved-by user answer (enabled in the setup walkthrough)
- U-9 `workflow_dispatch` needs the workflow file on the default branch before it can be dispatched — so the dispatch obligations run post-merge, and the pre-merge build evidence is the PR run (TO-6) — resolved-by scout (GitHub workflow_dispatch rule; obligations ordered so it holds either way)
- U-10 Environment deployment-branch/tag rules are evaluated against the run's `github.ref` — so the workflow has no `ref` input; a re-deploy is `gh workflow run docs.yml --ref v<ver> -f deploy=true`, and the `docs` environment allows tags `v*` only — resolved-by scout (critic; D-4)
- U-11 The docs-repo IDE0390/IDE0391 workaround flags on the F# pre-build — kept verbatim with their comment — resolved-by scout
- U-12 Does a new top-level folder leak into solution builds — `linq2db.slnx` lists every project explicitly; `.slnf` files list Source/Tests projects only — resolved-by scout
- U-13 Are `_site` / `source/api` ignored — root `.gitignore:29` ignores `.build/` (dest moves there); copied `Docs/source/.gitignore` has `api`, `obj` — resolved-by scout
- U-14 Fork base for the first asset — `92e58c252` (GitHub head of dotnet/docfx#11090) is not in the local clone (`git cat-file -t` fails); the vendored `docfx.dll` carries the stamp `1.0.0+a2baf77d569b…` and `docfx.deps.json` lists `Microsoft.CodeAnalysis.CSharp/5.9.0`, and `git diff --stat a2baf77d5 cd2bf10a0` touches `Directory.Packages.props` only, so `custom/linq2db-assembly-uids` @ `cd2bf10a0` reproduces the vendored build; `upstream/main` pins Roslyn 5.6.0, so the 5.9.0 pin must be re-applied after any upstream merge — resolved-by scout (critic round 2, binary stamp)
- U-16 How a path-filtered check interacts with branch protection — a workflow-level `paths:` filter leaves a required check pending forever on unrelated PRs, while a job skipped by `if:` reports skipped, which satisfies a required check; branch-protection settings are the user's and not readable here — resolved-by scout (D-12 makes the workflow valid either way)
- U-17 The fork's inherited `.github/workflows/release.yml` triggers on `release: published` and would run `dotnet pack` + a `nuget.org` environment on a fork release created by hand — resolved-by scout (critic round 2, `git show cd2bf10a0:.github/workflows/release.yml`; E-9 disables it on the custom branch)
- U-15 Does docfx report a missing `[!include]` target as a warning — not needed: E-11/E-12 fix the paths and TO-4 asserts the content is rendered — resolved-by scout

## P5 Decisions (M/L; rejected alternatives mandatory at L)

### D-1 — Publish from a GitHub Actions workflow on non-prerelease `release: published`

- **chosen:** `.github/workflows/docs.yml`, triggers `release: [published]` (build + deploy the tag; skipped when `github.event.release.prerelease`, mirroring `publish-mcp.yml:38`), `workflow_dispatch` with one input `deploy` (bool, default false; the ref is the dispatch ref), `pull_request` (all PRs; the build job is gated by D-12's change detection on `Docs/**`, `README.md`, `CONTRIBUTING.md`, `.github/workflows/docs.yml`).
- **rejected:** an Azure job in `default.yml` after `build_nugets_job` — adds a PAT variable to the main pipeline and keeps the Azure queue latency (6.5.1: 3.5 h); user chose Actions. Push-to-`release` trigger — fires before the GitHub release exists. Deploying prereleases — would overwrite the stable site with prerelease API.
- **why this:** docs go public with the GitHub release, from the exact tag, with an artifact per run; same event semantics as `publish-mcp.yml`.
- **failure mode of the choice:** a release from a tag without `Docs/` has no run at all (U-6) — the postpublish step must treat that as expected, not as a failure; and a docs fix between releases cannot be published without a release (or a dispatch from a later `v*` tag).

### D-2 — Prebuilt docfx asset from the fork, pinned by URL + SHA-256

- **chosen:** the fork carries `.github/workflows/linq2db-build.yml` (reusing the fork's `.github/actions/build` Node 24 / `npm ci` / `npm run build` steps) which, on a `linq2db-*` tag, runs `dotnet publish src/docfx -c Release -f net10.0`, zips the output and attaches `docfx.zip` to a fork release. linq2db pins `{ tag, url, sha256, sourceCommit }` in `Docs/docfx-version.json`; `Docs/build.ps1` downloads, verifies, extracts into `.build/docfx/<sha256>/`.
- **rejected:** fork as a submodule built from source per docs build — Node + npm + net10 build locally and in CI, 311 MB clone, linq2db's `global.json` / `.editorconfig` over a nested tree; user chose prebuilt. Vendored binaries — user does not want binaries in linq2db. Actions artifact link — expires, needs auth.
- **why this:** no Node, fast local builds, binary produced by a workflow with source provenance via the fork tag, integrity by hash.
- **failure mode of the choice:** the fork release asset deleted or the fork renamed → every docs build fails until re-pinned; a compromised fork can publish a new asset but cannot change the pinned hash without a linq2db PR.

### D-3 — Layout `Docs/source/**` + tooling at `Docs/`

- **chosen:** `Docs/source/` is a copy of `linq2db.docs/source/**`; `Docs/build.ps1`, `Docs/docfx-version.json`, `Docs/README.md`, `Docs/Docs.csproj` beside it.
- **rejected:** content directly in `Docs/` — docfx.json's `build.content` glob `"*.md"` would pick up `Docs/README.md`, and every relative path would need rewriting. Tooling under `Build/` — splits one feature over two roots.
- **why this:** mirrors the docs repo, so changes are limited to docfx.json and the two includes.
- **failure mode of the choice:** `Docs/README.md` (tooling) sits beside `Docs/source/index.md` (site home) — two readmes of different purpose one level apart.

### D-4 — Deploy with an SSH deploy key in a tag-restricted `docs` environment

- **chosen:** secret `DOCS_DEPLOY_KEY` on environment `docs` in linq2db/linq2db, deployment refs restricted to tags `v*`; public key as a write deploy key on linq2db.github.io; deploy job `ubuntu-24.04`, `actions/checkout` with `repository: linq2db/linq2db.github.io` + `ssh-key`, `rsync -a --delete --exclude .git`, commit "Docs: linq2db <tag>", `git push`.
- **rejected:** a PAT (old `linq2db.github.pat`) — person-scoped, broader, expires; `actions/deploy-pages` from linq2db/linq2db — an org root site is served only from the `linq2db.github.io` repo, so the site would move to `/linq2db/`. Unrestricted environment — any branch dispatch with `deploy=true` could overwrite the site with unreleased API.
- **why this:** narrowest credential, not tied to a person, and only a release tag can deploy (U-10).
- **failure mode of the choice:** until the user creates the key and environment (setup walkthrough) the deploy job fails at checkout — build and artifact unaffected; a hotfix to docs alone cannot deploy from `master`.

### D-5 — Drop the `linq2db.Compat` metadata entry

- **chosen:** remove it and its `assemblyUids` line from `Docs/source/docfx.json` (toc line already commented out).
- **rejected:** document it with `properties: { TargetFramework: net8.0 }` — publishes new pages (scope growth) and needs a duplicate-UID check against linq2db's net462 copy of the same types; offered to the user as a follow-up.
- **why this:** removes a warning and a wasted metadata pass with no published-page change.
- **failure mode of the choice:** Compat stays undocumented, as today.

### D-6 — `-WarningsAsErrors` in CI, `Source/**` warning fixes on a separate branch merged first

- **chosen:** `build.ps1 -WarningsAsErrors` → docfx `--warningsAsErrors`; `docs.yml` passes it. TO-1 records the full warning list of a master build on the **final pin** and assigns each entry to one of four buckets: `feature/docs-warnings` (Source-side), D-5 (Compat), this branch's include paths (E-11/E-12), or this branch's content (articles/toc/root README/CONTRIBUTING — fixed here under E-13, the named P3 exception); `feature/docs-warnings` is scoped from that list, not from build 24629's (which documented the 6.5.1 tree with the external Identity). TO-13 diffs the tag-1 and tag-2 warning lists as well, so a warning introduced by the upstream sync is owned before it can turn the PR check red.
- **rejected:** fix the `Source/**` warnings here — product-code change with standalone effect (P3); no warnings-as-errors — the 67 warnings accumulated because nothing failed on them.
- **why this:** a zero-warning baseline enforced on every docs-touching PR.
- **failure mode of the choice:** merge order — this branch's PR check stays red until `feature/docs-warnings` lands; and a `Source/**` doc-comment regression is not caught on the PR that makes it (path filter), only at the next docs PR or the release-verify docs build.

### D-7 — Docfx fork sync is a step of `/release-deps`, not a new prep task

- **chosen:** add a step after 1b in `.claude/skills/release-deps/SKILL.md`: merge `upstream/main` into the fork branch; re-apply / bump the `Microsoft.CodeAnalysis*` pins so docfx's Roslyn ≥ the pin `CodeGenerators` actually uses (netstandard2.0 → `Directory.Packages.props:109`, not `:108`); push + tag (user-confirmed); record the fork run id; update `Docs/docfx-version.json`; run `Docs/build.ps1 -WarningsAsErrors`. Carries the CS8795 / "No .NET API detected" symptom (postpublish `:112-121`), the conditional-pin rule (`:123`) and the latent-patch-bug note (`:141`). Removed when upstream ships `assemblyUids`.
- **rejected:** a new standard prep task — task ids 0–6 are hard-coded in `release-state.ps1:124-183` and cited by number across the corpus. The session design said "new `release-docfx` task"; this narrowing is flagged to the user at approval.
- **why this:** a Roslyn bump, the trigger for a docfx refresh, is made in release-deps.
- **failure mode of the choice:** a release that skips `/release-deps` skips the sync; the release-verify docs build (E-24) then catches a Roslyn mismatch.

### D-8 — Postpublish reorder: GitHub release before docs publish

- **chosen:** postpublish steps become 1 nuget-verify, 2 gh-release, 3 docs-publish (key `docs-publish`: find the `docs.yml` run for the tag and report its id; "no run" is expected only for a tag without `Docs/`; verify a page of a type new in this release; on failure `gh workflow run docs.yml --ref <tag> -f deploy=true`), 4 next-bump, 5 milestone-close; every cross-file "postpublish step N" citation updated.
- **rejected:** keep step 2 and say "run after step 3" — an out-of-order checklist.
- **why this:** publishing the GitHub release triggers the deploy.
- **failure mode of the choice:** a missed step-number citation; TO-14's grep enumerates them.

### D-9 — Runners and SDK setup follow existing workflow conventions

- **chosen:** build job `windows-2025`, deploy job `ubuntu-24.04`; `actions/setup-dotnet` `dotnet-version: 10.x` with SDK selection by `global.json` (as `build.yml:33-38`); the `build.yml` SHA pins; `actions/cache` (GitHub-owned, new pin) for `.build/docfx`, keyed on the pin's sha256.
- **rejected:** `windows-2022` (old Azure label, unused by this repo's Actions); a Linux build — net462 metadata of Remote.Wcf unproven there, and the copied include paths' case must then match exactly.
- **why this:** consistency with `build.yml`.
- **failure mode of the choice:** the `actions/cache` pin is chosen fresh; `/release-deps` 1b keeps it current afterwards.

### D-10 — Identity metadata compiles the net10.0 surface

- **chosen:** the Identity entry sets `"properties": { "TargetFramework": "net10.0" }`, so the passkey API (net10.0-only overlay, `LinqToDB.Identity.csproj:38-40`) is documented.
- **rejected:** the default first TFM (`net462`, `Directory.Build.props:217`) — omits the passkey types, the newest part of the package; netstandard2.0 as the old submodule used — same omission.
- **why this:** the published pages describe the full current package.
- **failure mode of the choice:** pages show net10.0-only members without a TFM marker, so a net8/net9 reader sees passkey APIs they cannot use; the package readme carries the TFM note.

### D-11 — First asset is an exact replica of the vendored build; the pinned asset is the upstream-synced build

- **chosen:** tag 1 `linq2db-<date>-cd2bf10` from `custom/linq2db-assembly-uids` @ `cd2bf10a0` (the source of today's vendored binaries); then sync the branch with `upstream/main` (re-applying the 5.9.0 Roslyn pin, U-14) and tag 2. TO-2/TO-3/TO-4 run on tag 1 (move-induced drift only); TO-13 diffs tag 1's site vs tag 2's; `Docs/docfx-version.json` pins tag 2 when every difference is explained, else tag 1 with the unexplained diff recorded in P11.
- **rejected:** pin only the synced build — the parity diff could not tell move-induced drift from upstream template/UID changes; pin only the replica — contradicts the user's "push and sync with docfx head".
- **why this:** honours the user's sync request while keeping the parity evidence clean.
- **failure mode of the choice:** two fork releases and one extra docs build of work; upstream drift may block tag 2.

### D-12 — Change detection inside the workflow, not a workflow-level `paths:` filter

- **chosen:** `docs.yml` runs on every `pull_request`; a small `changes` job (`ubuntu-24.04`, `actions/checkout` with `fetch-depth: 0`, `git diff --name-only <base>...<head>` against the filtered paths) sets an output; the `build` job has `if: needs.changes.outputs.docs == 'true' || github.event_name != 'pull_request'`. Whether the `build` check is made required is the user's branch-protection call; the workflow is valid either way.
- **rejected:** workflow-level `paths:` — a required check then stays pending forever on unrelated PRs (U-16), so it could never be made required; a third-party paths-filter action — refused by the Actions policy (P3); GitHub's documented no-op twin workflow — two files that must be kept in lockstep.
- **why this:** keeps the docs check eligible for branch protection without blocking unrelated PRs, using only GitHub-owned actions.
- **failure mode of the choice:** every PR pays one short `changes` job; a bug in the diff command (wrong base) skips the build silently — TO-6 (runs) and TO-8 (skips) are the two arms that catch it.

## P6 Edit-points

- E-1 `Docs/source/*` — copy of `linq2db/docs` `source/**` at `0543c1145` (fetch the docs clone first; content equals local `d697902` + submodule pointer): articles, toc.yml, index.md, images, templates/custom, filter.yml, .gitignore, .nojekyll, cli-help.txt — bytes unchanged except E-2, E-11, E-12.
- E-2 `Docs/source/docfx.json` — `src: ../submodules` → `../..`; `linq2db/Source/...` → `Source/...`; Identity entry → `Source/LinqToDB.Identity/LinqToDB.Identity.csproj` with `properties.TargetFramework = net10.0` (D-10); F# DLL/reference paths → `.build/bin/LinqToDB.FSharp/Release/{netstandard2.0,net462}/...`; drop the Compat entry and its `assemblyUids` line (D-5); `dest` → `../../.build/docs/_site`; docfx comment points at `Docs/README.md`.
- E-3 `Docs/build.ps1` — new: params `-WarningsAsErrors`, `-Clean`; sets the working directory to the repo root (the fork spawns `dotnet restore` with the process cwd, `DotnetApiCatalog.Compile.cs:155`, so `global.json` resolution must not depend on the caller's cwd); reads `docfx-version.json`; download + SHA-256 verify + extract into `.build/docfx/<sha256>/` (mismatch → throw before docfx); F# pre-build with the docs-repo workaround flags and comment verbatim; `dotnet <docfx.dll> Docs/source/docfx.json [--warningsAsErrors]`; throws on non-zero exit; no deploy logic.
- E-4 `Docs/docfx-version.json` — new: `tag`, `url`, `sha256`, `sourceCommit` (D-11); `sha256` transcribed from the fork run's `docfx.zip.sha256` asset, never computed from the downloaded zip.
- E-5 `Docs/README.md` — new: local build, how the pin is produced/updated, when it can go away (from `linq2db.docs/docfx/README.md`), deploy flow and re-deploy command.
- E-6 `Docs/Docs.csproj` — new NoTargets visibility project (shape of `.github/.github.csproj`) with `DefaultItemExcludes` for `source/api/**` and `source/obj/**`.
- E-7 `linq2db.slnx` — add `Docs/Docs.csproj` beside the `.github` / `.claude` visibility projects.
- E-8 `.github/workflows/docs.yml` — new per D-1/D-4/D-9/D-12: `permissions: contents: read`; `changes` job; build `concurrency` per ref (cancel), deploy `docs-deploy` (no cancel); `timeout-minutes` on every job; build job uploads `.build/docs/_site` (`if-no-files-found: error`); deploy job `environment: docs`, `if: github.event_name == 'release' || inputs.deploy`, sets `git config user.name/user.email` before committing; prerelease `release` events skipped (`publish-mcp.yml:38` guard).
- E-9 `docfx fork: .github/workflows/linq2db-build.yml` — new, on `MaceWindu/docfx` branch `custom/linq2db-assembly-uids` only (external, user-confirmed push/tag), per D-2; uploads `docfx.zip` and `docfx.zip.sha256` (computed in the run) and prints the hash; the same commit disables the inherited `.github/workflows/release.yml` on that branch (U-17).
- E-10 `docfx fork: custom/linq2db-assembly-uids` — tag 1 at `cd2bf10a0` + E-9; then merge `upstream/main`, re-apply the Roslyn 5.9.0 pins, tag 2 (D-11; external).
- E-11 `Docs/source/index.md` — include path → `../../README.md` (root file is `README.md`; old path used `readme.md`).
- E-12 `Docs/source/articles/project/contrib.md` — include path → `../../../../CONTRIBUTING.md`.
- E-13 `Docs/source/articles/*` — only lines TO-1's census attributes a content-sourced warning to (fourth bucket of D-6); empty if the bucket is empty.
- E-20 `.claude/skills/release-postpublish/SKILL.md` — D-8: replace step 2 (`:83-150`) with docs-publish as step 3 (incl. the no-run-for-pre-Docs-tag rule and the `--ref <tag>` re-deploy), renumber the step table (`:28-38`) and in-file citations (`:30`, `:194`, `:262`, `:294`, `:301`), move the vendored-docfx subsection's facts to E-21, update `:3` and `:25-26`.
- E-21 `.claude/skills/release-deps/SKILL.md` — D-7 step after 1b, carrying postpublish `:112-121` (CS8795 / "No .NET API detected" symptom), `:123` (pin read for `CodeGenerators`' TFM, `Directory.Packages.props:109`), `:141` (a Roslyn bump exposes latent bugs in the custom patch).
- E-22 `.claude/skills/release-publish/SKILL.md` — `:14`, `:43`, `:225` "docs PR" → "docs publish".
- E-23 `.claude/skills/release/SKILL.md` — `:32` external-repos description.
- E-24 `.claude/skills/release-verify/SKILL.md` — step 4b `Docs/build.ps1 -WarningsAsErrors` between 4a and 5; intro `:10-15`, commit template `:156-162`, `:169`, and the "one sanctioned extra build" wording `:80` / `:205`.
- E-25 `.claude/docs/release/external-repos.md` — `:12` linq2db/docs retired, linq2db.github.io as deploy target; `:13` fork branch, tag scheme, asset; `:66` step-number citation.
- E-26 `.claude/docs/release/overview.md` — postpublish column per D-8 (adds the missing milestone-close row), `:41` description.
- E-27 `.claude/docs/release/first-run-todos.md` — `:31-35` docs-PR entry → retired; step-number citations.
- E-28 `.claude/docs/release/nuget-package-notes.md` — `:331` downstream obligation → `/release-deps` docfx sync.
- E-29 `.claude/docs/msbuild-override.md` — `:3`, `:10`, `:12` docs now in-repo (`Docs/source/docfx.json`, `Docs/build.ps1`).
- E-30 `.claude/docs/pr-and-push.md` — `:237` drop `../linq2db.docs` / `commit --only -- docfx`.
- E-31 `.claude/docs/agent-rules.md` — `:219` drop `../linq2db.docs`.
- E-32 `.claude/docs/maintaining-the-corpus.md` — `:22` drop `../linq2db.docs`.
- E-33 `.claude/skills/release-notes/SKILL.md` — `:105` postpublish step-number citation.

## P7 Impact map (M/L)

- `.github/**`, `Build/**`, `Directory.Build.props`, `Source/**/*.csproj`, `Source/**/README.md`, `Tests/**/*.md`, root `*.md` — searched `linq2db/docs|linq2db\.docs|docfx` (case-insensitive) excluding `.claude/` — no hit; only `linq2db.github.io` site URLs (README.md, Source/*/readme.md, Directory.Build.props:105, LinqToDB.CLI.csproj:43, LinqToDBTab.xaml, SqlServerTools.cs) — out-of-scope
- In-repo links in the old flat API shape `api/LinqToDB.X.html` (README.md:62, Source/LinqToDB/readme.md:78, Source/LinqToDB/Sql/Readme.md:7, LinqToDBTab.xaml:21) — pre-existing dead links — deferred: follow-up issue (link-check), raised to the user
- Docs-repo `source/**` (excluding `api/`) — searched `submodules|CONTRIBUTING|\[!include`: 18 docfx.json `src` hits — covered by E-2
- `source/index.md:1` `[!include](../submodules/linq2db/readme.md)` — covered by E-11
- `source/articles/project/contrib.md:4` `[!include](../../../submodules/linq2db/CONTRIBUTING.md)` — covered by E-12
- Root `README.md` / `CONTRIBUTING.md` become site content — their edits must trigger the docs check — covered by E-8
- `plans/feature-migrate-ci-to-github-actions/plan.md:207` ("CONTRIBUTING.md … republished on linq2db.github.io") — still true after the move — out-of-scope
- Docs-repo `docfx.json` metadata entries (scout table) vs worktree — all csprojs exist under `Source/`, EF3–EF10 under `Source/LinqToDB.EntityFrameworkCore/`, Identity at `Source/LinqToDB.Identity/LinqToDB.Identity.csproj`, F# output matches `Directory.Build.props:88-89` — covered by E-2
- Identity API page set (U-2) — 38 old pages removed, new set from PublicAPI files — covered by E-2
- Docs-repo `Directory.Build.props` (ArtifactsPath + 3 NuGetAuditSuppress) — searched `NuGetAuditSuppress|GHSA|<Import ` in worktree; never applied to linq2db projects (U-3) — covered by E-2
- Docs-repo `build.ps1` / `local.cmd` / `submodules.cmd` / `azure-pipelines*.yml` — replaced; workaround comments (dotnet/docfx PR 8375, issue 9775, IDE0390/IDE0391) kept — covered by E-3
- `linq2db.slnx` / `*.slnf` — searched for folder wildcards: none; visibility pattern `.github/.github.csproj` (slnx:9) — covered by E-6
- NoTargets default `None` glob over generated `Docs/source/api/**`, `Docs/source/obj/**` — covered by E-6
- Root `.gitignore` / `.editorconfig` / `.gitattributes` — `.build/` ignored (:29); copied files are `i/lf w/crlf` (critic `git ls-files --eol`), blobs unchanged under `* text=auto` — covered by E-1
- Existing workflows `build.yml`, `tests*.yml`, `publish-mcp.yml` and Azure `Build/Azure/pipelines/*.yml` — searched `paths|exclude|include|uses:|permissions:|concurrency:|runs-on:|environment:`; none path-filtered, so a docs-only PR also runs all `build.yml` jobs and Azure `build` — deferred: accepted CI cost, P10
- `publish-mcp.yml:38` prerelease guard — mirrored — covered by E-8
- `gh-action-pins.ps1` default globs `.github/workflows/*.yml` — new workflow picked up by `/release-deps` 1b — covered by E-8
- Release corpus hits for `linq2db\.docs|linq2db/docs|docs PR|docs-pr|docfx|github\.io|submodules/linq2db|Docs: linq2db|definitionId=2|linq2db\.github\.pat`: release-postpublish (`:3,:25,:26,:35,:83-150,:262,:301`) — covered by E-20
- release-postpublish `:112-121`, `:123`, `:141` (Roslyn facts) — covered by E-21
- release-publish `:14,:43,:225` — covered by E-22
- release `:32` — covered by E-23
- external-repos.md `:12,:13` — covered by E-25
- overview.md `:12` — covered by E-26
- first-run-todos.md `:31,:33` — covered by E-27
- nuget-package-notes.md `:331` — covered by E-28
- msbuild-override.md `:3,:10,:12` — covered by E-29
- pr-and-push.md `:237` — covered by E-30
- agent-rules.md `:219` — covered by E-31
- maintaining-the-corpus.md `:22` — covered by E-32
- code-reviewer.md `:308` ("docfx / API-site output") — still true — out-of-scope
- Postpublish step-number citations: external-repos.md:66 — covered by E-25
- first-run-todos.md:35 — covered by E-27
- release-notes/SKILL.md:105 — covered by E-33
- nuget-package-notes.md:29, branch-and-pr.md:8, release-deps/SKILL.md:16,245 (step 4 unchanged), release-publish/SKILL.md:347 (step 5 unchanged) — out-of-scope
- `release-state.ps1:178` `postpublish = [ordered]@{}` — searched `nuget-verify|docs-pr|gh-release|next-bump|milestone-close` in `.claude/scripts/`: no script writes the keys — covered by E-20
- KB `areas/AGENTS-INFRA/INDEX.md:173`, `areas/T4-TEMPLATES/INDEX.md:151` — deferred: `/kb-refresh`
- `plans/issue-5862-source-hana-from-nuget/plan.md:240,358` — historical records — out-of-scope
- External surfaces a repo grep cannot reach: Azure definition 2 + its PR build, `linq2db.github.pat`, `linq2db/docs` archive state, GitHub environment/secret, fork Actions settings — deferred: user actions in the setup walkthrough

## P8 Test obligations (M/L)

- TO-1 SC-1: in the worktree with `.build/docfx` absent, run `Docs/build.ps1` on the **final pin** (and once from a cwd other than the repo root); assert exit 0, `.build/docs/_site/index.html` exists, one `api/<id>/` folder per `Docs/source/toc.yml` API entry (16, no `linq2db.compat`), the log shows the download + hash-verify line and no `dotnet tool` / `npm`; record the full warning list with each entry assigned to one of D-6's four buckets, none unassigned — providers: n/a (windows docs build) — proof: characterization
- TO-2 SC-2: `git clone --depth 1` linq2db.github.io into `.build/.agents/`; on the tag-1 build, diff relative file lists of every `api/<id>/` except `linq2db.identity`, plus `articles/**`; each removed/added API page maps to a `-`/`+` line of `git diff v6.5.1..HEAD -- "Source/**/PublicAPI*.txt"`, or for `api/linq2db.fsharp/` (no PublicAPI file) to `git diff v6.5.1..HEAD -- Source/LinqToDB.FSharp/`; separates: a wrong `output` or a dropped `assemblyUids` entry renames a whole folder (hundreds of unexplained paths) — providers: n/a — proof: characterization
- TO-3 SC-3: assert in `_site/api/linq2db.identity/`: `LinqToDB.Identity.IConnectionFactory.html` and `LinqToDB.Identity.IClameConverter.html` absent; `LinqToDB.Identity.UserOnlyStore-6.html` (shared surface) present; `LinqToDB.Identity.UserOnlyStore-7.html` (net10.0 overlay) present; `Microsoft.Extensions.DependencyInjection.IdentityLinqToDBBuilderExtensions.html` present; separates: without D-10's `TargetFramework` (mutation "remove properties from the Identity entry") `UserOnlyStore-7` is absent while `UserOnlyStore-6` stays — providers: n/a — proof: control
- TO-4 SC-4: assert `_site/index.html` contains a sentence unique to root `README.md` and `_site/articles/project/contrib.html` contains one unique to `CONTRIBUTING.md`; separates: mutation "swap the two include targets" builds green and puts each string on the other page, so the string assertions — not a build failure — go red; mutation "restore ../submodules include paths" additionally shows what docfx does with a missing include — providers: n/a — proof: control
- TO-5 SC-5: control — on the final pin, mutation "flip last hex digit of sha256" in `docfx-version.json` with the cache cleared; assert `Docs/build.ps1` throws the mismatch message and no docfx line is logged; unmutated run passes (TO-1) — providers: n/a — proof: control
- TO-6 SC-6: the PR for this branch triggers `docs.yml`; build job green with `-WarningsAsErrors` after `feature/docs-warnings` merged and this branch synced; artifact present — providers: CI windows-2025 — proof: characterization
- TO-7 SC-6: control — throwaway commit (mutation "add `<xref:LinqToDB.DoesNotExist>` to Docs/source/articles/general/Managing-data-connection.md"); assert the `docs.yml` build job red on the xref warning; revert — providers: CI windows-2025 — proof: control
- TO-8 SC-7: an open PR touching no filtered path (e.g. the next unrelated PR) shows `docs.yml` `changes` green and `build` skipped; arms: TO-6 builds, this skips; separates: a wrong diff base (mutation "diff against HEAD~0") skips the build on this PR too, which TO-6 catches — providers: CI — proof: control
- TO-9 SC-8: post-merge `gh workflow run docs.yml --ref master -f deploy=false`; assert artifact uploaded, deploy job skipped, linq2db.github.io `master` head unchanged — providers: CI — proof: control
- TO-10 SC-8: first live deploy — the next non-prerelease release, or `gh workflow run docs.yml --ref v<ver> -f deploy=true` once a `v*` tag contains `Docs/` and `DOCS_DEPLOY_KEY` exists; assert a new linq2db.github.io commit and that a type page new in that release resolves at `https://linq2db.github.io/api/<asm>/<asm>--<Type>.html`; also assert a `deploy=true` dispatch from `master` is refused by the `docs` environment — providers: CI — proof: control; blocked until the user creates the environment + key
- TO-11 SC-8: prerelease arm — the workflow's job conditions are `publish-mcp.yml:38`'s guard verbatim; no live prerelease is available to test, so this is checked by an independent reader against `publish-mcp.yml` — providers: n/a — proof: characterization (unproven live, P10)
- TO-12 SC-9: push tag 1 and tag 2 on the fork; assert each fork run creates a release with `docfx.zip` and `docfx.zip.sha256`, that the SHA-256 of the downloaded zip equals the `.sha256` asset produced inside the run, and that E-4's `sha256` equals that asset; no fork `release.yml` run is triggered — providers: n/a — proof: characterization
- TO-13 SC-9: build the site with tag 1 and tag 2; diff the two `_site` trees **and** the two warning lists; record every difference with its upstream cause (commit) — pin tag 2 only if none is unexplained — providers: n/a — proof: characterization
- TO-14 SC-10: after the linq2db PR merges and the corpus commit lands (P3 sequencing), `Grep` `.claude/` (excluding `knowledge-base/**`, `plans/**`) for `linq2db\.docs|linq2db/docs|docs PR|docs-pr|submodules/linq2db|definitionId=2|linq2db\.github\.pat`; every hit is a retired/history statement; every `postpublish … step N` citation matches the new table; `release-deps` contains the three moved Roslyn facts; an independent reader (different model) walks postpublish steps 2–3 and the new release-deps step against the new flow — providers: n/a — proof: characterization
- TO-15 SC-11: `dotnet build linq2db.slnx -c Release` green locally; the PR's `build.yml` legs green — providers: CI + local — proof: characterization

## P9 Verification gates

- G-01: — (pending)
- G-02: n/a — no SQL-emitting code changes (the gate keys on `Source/...` tokens inside E-2's docfx path text)
- G-03: n/a — no public API surface; `Source/...` appears in P6 only as docfx.json paths
- G-04: n/a — same as G-03
- G-05: n/a — no product code compiled differently; TO-15 covers the Release solution build
- G-06: — (pending)
- G-07: — (pending)
- G-09: — (pending)

## P10 Adjudicated (M/L)

- Moved markdown/yml keep the docs repo's formatting (tabs where root `.editorconfig` asks for spaces) — plain copy was the user's decision.
- The flat `api/LinqToDB.X.html` links in READMEs / LINQPad XAML are pre-existing dead links (P7) — follow-up, not a finding here.
- `Source/**` doc-comment regressions are not caught on the PR that introduces them (path filter) — accepted per D-6.
- A release from a tag without `Docs/` has no docs run (U-6) — expected; such a release cannot publish docs.
- Every v6.0.0 `api/linq2db.identity/*` URL is removed (38 pages, U-2) — consequence of #5640's deliberately breaking Identity API, not of the move.
- Identity pages document the net10.0 surface without TFM markers (D-10) — accepted by the user 2026-11-07: net8/net9 are to be dropped with the .NET 11 migration.
- D-7 (docfx sync as a `/release-deps` step instead of a new prep task) — accepted by the user 2026-11-07.
- The prerelease guard is not exercised live (TO-11) — it is `publish-mcp.yml:38`'s guard, already in production use.
- A docs-only PR also runs every `build.yml` job and the Azure `build` pipeline (no path filters there, P3 forbids touching them) — accepted CI cost.
- Environment setup (user action, setup walkthrough): `docs` environment rule type *Selected branches and tags* with a **tag** pattern `v*` and no required reviewer — "Protected branches only" or a *branch* pattern would refuse the release-event deploy (`github.ref` = `refs/tags/v…`), a required reviewer would park it. TO-10's refusal arm checks the restriction.

## P11 Amendments (M/L)

_None._

## P12 Critic verdict (M/L)

- Round 1 (fable, 2026-11-07): **refuted**. Objections: (1) refuted — two `[!include]` paths into the submodule (`index.md:1`, `articles/project/contrib.md:4`) missing → E-11, E-12, TO-4, paths filter; (2) refuted — TO-2 asserted unchanged Identity names, but the in-tree package removes all 38 v6.0.0 pages and docfx compiles the first TFM → SC-3, U-1/U-2 rewritten, D-10, TO-3, P3 delta (3), P10; (3) weak — pre-`Docs/` tags have no run (not a failing run) → D-1, U-6, D-8; (4) weak — no prerelease arm → D-1, TO-11; (5) weak — environment restriction vs `inputs.ref` → `ref` input dropped, U-10, D-4; (6) weak — warning census from the 6.5.1 tree → D-6, TO-1 records and assigns master's list; (7) weak — E-10 base unverified, upstream merge confounds parity → U-14, D-11, TO-13; (8) weak — E-21 lost three Roslyn facts → E-21 names `:112-121`, `:123`, `:141`; (9) minor — CI cost → P10; (10) minor — NoTargets glob over generated output → E-6; (11) note — copy source commit → E-1; lead — dispatch of a branch-only workflow → U-9, TO-9 post-merge. Searched: docs-repo `source/**` for `submodules|CONTRIBUTING|[!include`; `git ls-files --eol`; Identity old yml vs new PublicAPI; corpus-wide docs-repo and `postpublish step N` greps; workflows/pipelines path filters; fork refs (`cat-file 92e58c252`, `upstream/main` Roslyn pins, `VisitorHelper.cs` guard).
- Round 2 (fable, 2026-11-07): **weak** — all round-1 objections answered (critic cited the answering rows). New objections, folded in by the author without a third round (the skill caps re-critique at one revision; these are carried visibly): (1) warning census on tag 1 while tag 2 is pinned → TO-1/TO-5 run on the final pin, TO-13 diffs warning lists; (2) no bucket for content-sourced warnings → D-6 fourth bucket, E-13, P3 named exception; (3) TO-12 compared the asset against a pin transcribed from it → fork run emits `docfx.zip.sha256`, E-4 transcribed from it; (4) corpus edits cannot sit on a linq2db branch → P3 sequencing line, TO-14 post-merge; (5) required-check semantics undecided → D-12 in-workflow change detection, U-16, TO-8 rewritten; (6) environment rule type → P10 setup line; nits → TO-3 full file names and a shared-vs-overlay separation, U-14 binary-stamp evidence, E-3 cwd, TO-4 green-build mutant, TO-2 F# source, E-8 git identity + timeouts, E-9 disables the fork's inherited `release.yml` (U-17). Critic confirmed by source: the fork's `Compile.cs:42` passes `properties` to `MSBuildWorkspace` (D-10), and the vendored binary's `1.0.0+a2baf77d5…` stamp proves D-11's replica provenance. Residual, unprobed: GitHub `workflow_dispatch` default-branch rule and environment tag-rule evaluation (U-9/U-10; ordered so the plan holds either way), branch-protection state.
