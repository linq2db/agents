# Work plan: feature-migrate-ci-to-github-actions — Migrate test CI from Azure DevOps to GitHub Actions

**Tier:** L  ·  **Status:** approved  ·  **Approved-at:** 2026-08-31, E-1..E-34  ·  **Branch:** feature/migrate-ci-to-github-actions
**Schema:** `.claude/docs/work-plan.md`  ·  **Gates:** `.claude/docs/definition-of-done.md`

Programme-level plan. Phase 1 is committed on this branch (PR #5834); phases 2–5 land as their own PRs and amend `P6` here rather than starting fresh plans, so the design stays in one place.

## P1 Problem

A `test-all` PR run is **30 jobs against 10 parallel slots** on 2 vCPU / 7 GB Azure DevOps agents (`build_job`, `build_x86_job`, `create_baselines_branch`, 12 Windows legs, 15 Linux legs — counted from `Build/Azure/pipelines/templates/test-matrix.yml` @ 639d6aaf8). Three-times oversubscribed.

That ceiling is what #5819 spent a dozen builds packing around: `test-jobs.yml:7-25` records a `linux_max_parallel` experiment that measured *worse* than uncapped (23059 at 164.4 min against 23028 at 156.7 on equal work) precisely because "capped at six, windows is confined to four slots and its 501 agent-minutes need 125 min there, so the floor is 10 min worse before a single leg runs". The constraint is slot count, and no amount of packing removes it.

GitHub Free gives **20 parallel jobs on 4 vCPU / 16 GB**, free for public repositories, and the runner images are the same artifact on both platforms (`actions/runner-images`).

## P2 Success criteria

- SC-1 A `test-all` run executes the same leg set and per-leg provider set as the pre-migration run, with equal test counts per leg → TO-1
- SC-2 Baselines land on one `baselines/pr_<n>` branch with one draft PR, whichever CI's leg pushes first, with both CIs contributing commits → TO-2
- SC-3 One trigger (`/azp run test-<surface>`) starts both CIs, and the GitHub result is visible on the PR head SHA → TO-3
- SC-4 `all_in_azure` runs the complete matrix on Azure DevOps with no GitHub dispatch → TO-4
- SC-5 A GitHub-run leg resolves the `*.Azure` provider configuration and writes baselines, i.e. the `AZURE` symbol and the `BaselinesPath` relative depth both survive → TO-5
- SC-6 Wall-clock for `test-all` does not regress against the pre-migration baseline → TO-6
- SC-7 A PR targeting `release` runs the same complete, all-TFM leg set it does today → TO-8

## P3 Constraints & anti-goals

- **No change to what is tested.** Same providers, same TFMs, same `--filter "TestCategory != SkipCI"`. The only intended coverage change is phase 1's Windows-TFM trim, argued coverage-neutral in `P10`.
- **Publishing stays on Azure DevOps.** `nuget-job.yml:35` gates the push on `Build.SourceBranchName`, so the publish half genuinely is push-only. **The test half is not:** `default.yml:11-12` triggers on PRs to `release` and `:42-47` includes the full matrix with `full_run: true`. That path is in scope — see D-6.
- **The release-PR full run must stay complete.** `release-publish` resets `linq2db.baselines` to the anchor and regenerates baselines *on the release PR*, which is a `default.yml` run. A release full run covering only the AzDO legs would thin the regenerated baseline set with nothing red anywhere.
- **`/azp run test-*` stays the trigger.** Contributor muscle memory and the existing AzDO GitHub App.
- **The `all_in_azure` fallback must keep working**, so AzDO retains a complete matrix definition.
- **No third-party actions.** First-party `actions/*` only, pinned by SHA; the repo policy now enforces it.
- **Do not lose #5819's measured tuning** — leg ordering by duration, the shallow sparse baselines clone, `rebase -X theirs --onto FETCH_HEAD HEAD~1`, `pr_main`, the x86 artifact split.
- **Baselines semantics unchanged** — per-leg clone + push with rebase retry, first pusher opens the PR.

## P4 Unknowns

- U-1 Lane width doubles silently: `Tests/Linq/TestsInitialization.cs:214` is `maxLanes = configuredLanes ?? (2 * Environment.ProcessorCount)`, so 2 vCPU gives 4 and 4 vCPU gives 8; five legs exceed 4 providers (`pgsql2` 7, `sqlite` 7, `pgsql1` 6, `sqlserver.fts.2017_2019` 6, `mysql` 5) — resolved-by critic + code read, pinned to 4 in D-5
- U-2 Whether the ~4 min per-leg win-mssql image pull makes SQL Server the wrong leg set to park on the slower agents — resolved-by user answer, parked in P10 until a full run exists
- U-3 Whether artifacts survive a partial re-run so a re-run leg can download `build`'s output from attempt 1 — resolved-by probe deferred to the first real re-run, recorded in P10
- U-4 Whether AzDO's 8 legs fetch GitHub's artifacts or keep a trimmed local build — resolved-by user answer, deferred to phase 4 pending phase-1/3 measurements
- U-5 Whether `allowed_actions: local_only` blocks first-party actions — resolved-by probe run 33417912200, yes; policy changed to `selected` + `github_owned_allowed`, all four actions verified green
- U-6 Whether GitHub Windows runners can host the `win-mssql-*` containers — resolved-by probe run 33410071655, yes, 6/6, `isolation=process`, ltsc2022 images on a 26100 host, 34.4 GB free before and 26.2 GB after two multi-GB pulls
- U-7 `default.yml:42-47` is a second includer of `test-matrix.yml` with `full_run: true` on PRs to `release`, which the first draft never mapped — resolved-by critic round 1, D-6
- U-8 `ensure-baselines-branch.ps1:106` force-pushes, and the `dependsOn` ordering that keeps it ahead of every leg does not span two CIs — resolved-by critic rounds 1 and 2, D-7
- U-9 A personal access token cannot create check runs, the Checks API being GitHub-App-only, so AzDO can only post commit statuses — resolved-by critic round 1, D-8

## P5 Decisions

### D-1 — Azure DevOps stays the trigger and dispatches GitHub

- **chosen:** `/azp run test-*` starts an AzDO run whose `dispatch_github` job calls the GitHub `workflow_dispatch` API, passing the surface, the **PR number**, the baselines branch, `$(Build.BuildId)` and `$(System.PullRequest.SourceCommitId)`. Fire-and-forget: AzDO holds no slot waiting. The PR number is an explicit input, not recovered by parsing `baselines/pr_<n>`.
- **rejected:** GitHub `issue_comment` as the entry point — needs no AzDO PAT and reads the comment natively, but duplicates the trigger vocabulary and abandons the AzDO GitHub App the project already runs.
- **rejected:** GitHub PR labels — runs appear natively in PR checks with no plumbing, but labels leave residue and cannot carry a surface plus a CI selector cleanly.
- **why this:** one command, unchanged for contributors; one outbound secret; the fallback path is the same pipeline with the dispatch switched off.
- **failure mode of the choice:** a dispatched run does not appear in the PR's checks by default, so the reporting chain in D-8 is load-bearing — if it breaks, a red matrix reads as green.

### D-2 — Keep the 8 SQL Server Windows legs on Azure DevOps

- **chosen:** static split — GitHub takes 20 legs, AzDO keeps the win-mssql ones, expressed per leg by a `ci` flag in the matrix.
- **rejected:** all tests on GitHub. The probe proved this works, so it is available; rejected by the user to spread load across both CIs.
- **rejected:** a dynamic split (a pre-job computing the assignment, legs gated on a `contains(...)` condition). Implementable — skipped legs consume no agent — but a second scheduler for ~25–35% more throughput.
- **why this:** AzDO's 10 slots stop being the constraint either way; the static split keeps both CIs useful with zero runtime logic, and the probe makes rebalancing a flag edit rather than a port.
- **failure mode of the choice:** SQL Server may be the wrong 8 legs to park on the slower agents — they pull ~4 min of image before running a test, overhead better paid on a 4-vCPU runner. Unmeasured, and the split will look settled once written down (U-2).

### D-3 — One matrix file, with selection expressed as data (revised by A-2)

- **chosen:** `test-matrix.yml` stays the single matrix and becomes plain data: each entry carries a
  concatenated `filters: '[all][sqlserver.all]'` string, and `test-jobs.yml` selects with
  `contains(test_config.filters, parameters.db_filter)`. Azure reads it natively; the GitHub side reads
  the same file with a stock YAML parser. No JSON, no generator, no drift check, nothing to synchronise
  — and 75 fewer lines, since 25 paired `${{ if }}` / `${{ if not }}` blocks collapse to one line each.
- **rejected:** a canonical JSON plus a generator emitting the AzDO YAML, guarded by a drift check —
  the original D-3. Certain to work, but it is ~200 lines of generator that must also reproduce ~137
  lines of load-bearing prose comments, plus a permanent second representation to keep in step.
- **rejected, empirically:** `filters` as a YAML **list** selected by `containsValue`. It compiles —
  build 23192 initialised with zero `validationResults` — and matches nothing, so the matrix expanded
  to no configurations, each test job ran once with no matrix variables, every `and(variables.title, …)`
  guard was false, and **the build reported `succeeded` having run no tests**. The step names rendered
  the literal `$(title)`.
- **rejected:** two hand-maintained matrices — guaranteed drift across 25 entries.
- **why this:** `contains()` over a string is what the removed blocks already used against the same
  parameter, so it is proven in this exact position rather than inferred from documentation, which is
  where `containsValue` failed. AzDO still cannot build a matrix at runtime (`test-matrix.yml:32-34`),
  but it does not need to — the data is compile-time either way.
- **failure mode of the choice:** the selection is a substring test, so the `[]` brackets are
  load-bearing — drop them and `[sqlserver.2019]` matches inside another tag. Both directions of
  mis-selection are silent, and each was hit once: too few legs is a green run with zero tests (23192,
  `containsValue` matching nothing), and too many is a green run of the entire matrix (23199,
  `parameters.db_filter` undefined in `test-jobs.yml` so `contains(x, '')` was always true). Neither
  produces an error. **Verification is the leg list — names and count — read from the timeline, never
  the build's verdict**: `db_filter: '[sqlite.all]'` must give exactly `Win s_SQLite` and `Lin s_SQLite`.

### D-4 — Build with `--configuration Azure` on GitHub too

- **chosen:** keep `-c Azure` verbatim; do not rename the configuration or the `Build/Azure` directory.
- **rejected:** renaming to a CI-neutral `-c CI` — reads better, and breaks five things at once (see `P7`), including baseline capture, silently.
- **why this:** the configuration name is load-bearing three levels deep and the coupling is invisible at the call site.
- **failure mode of the choice:** the name now lies — a GitHub leg builds "Azure" — so the next reader reasonably assumes it can be renamed. Mitigated by a comment at the definition, not by the name.

### D-5 — Pin `MaxParallelLanes` to 4 for the migration

- **chosen:** add `"MaxParallelLanes": 4` to `AzureConnectionStrings` in `DataProviders.json`. One key covers all four TFM roots on both CIs, and it is behaviour-identical on AzDO today (2 vCPU × 2 = 4).
- **rejected:** default to `2 × ProcessorCount` and absorb 8 lanes. The width change would land inside the runs TO-1/TO-6 use as the parity gate, confounding both, and `pgsql2` at 7 providers means seven postgres containers sharing 16 GB against the dispatcher's recorded OOM history.
- **rejected:** set it per leg in the five affected configs — 20 files for what one inherited key does.
- **rejected:** an `L2DB_MAX_LANES` env override — no such channel exists, and adding one is a product change in service of a CI migration.
- **why this:** makes the runner move a pure hardware change with identical concurrency, so any regression is attributable to the migration rather than to a silent width change.
- **failure mode of the choice:** it leaves throughput on the table indefinitely, and a pin reading `4` will look like a considered value long after nobody remembers it was chosen to hold a variable still.

### D-6 — The release-PR full run stays whole on Azure DevOps

- **chosen:** `default.yml` passes `all_in_azure: true`. The parameter is declared in `test-matrix.yml` and forwarded to `test-jobs.yml`, exactly as `linux_max_parallel` is (declared `test-matrix.yml:5`, forwarded `:84`) — `default.yml` includes `test-matrix.yml`, not `test-jobs.yml`, so the hop is mandatory and is a generator requirement per D-3.
- **rejected:** teach `tests.yml` a full-run mode with a `full_run` dispatch input. More faithful to the migration's spirit, but it puts the release-baselines regeneration — the run whose completeness the release process depends on — on the newest, least-exercised path.
- **rejected:** leaving `default.yml` untouched. That is the round-1 refutation: the migrated legs vanish from the release full run, silently.
- **why this:** reuses the fallback machinery SC-4 already requires, so the release path costs one parameter rather than a new mode, and keeps the highest-stakes run on the path with years of history.
- **failure mode of the choice:** the release run stays on 10 AzDO slots, so it stays slow — the migration's speed win does not reach the run that most needs it.

### D-7 — Cancel GitHub runs before the force-push, and key concurrency per surface

- **chosen:** a step in `create_baselines_branch`, **before** `ensure-baselines-branch.ps1`, lists in-progress `tests.yml` runs for this PR via the Actions API, cancels them, and waits for termination; only then does the rebase clone run. The GitHub workflow additionally uses `concurrency: tests-<pr>-<surface>` with `cancel-in-progress`, which keys per surface so two concurrent `/azp run test-<x>` surfaces coexist as they do today.
- **rejected:** relying on `concurrency: tests-<pr>` alone. Round 2 refuted it on the plan's own ordering: `dispatch_github` depends on `create_baselines_branch`, so the run that would trigger cancellation is created only *after* the force-push completes, and GitHub evaluates concurrency at run creation. The mechanism fires after the window it claims to close.
- **rejected:** treating the window as negligible. It is the clone→rebase→force-push span, and `ensure-baselines-branch.ps1:77-79` measures the clone alone at 2.3 minutes.
- **rejected:** making the force-push non-forcing — it exists to rebase a stale run branch onto baselines master, so a non-force push would simply fail.
- **why this:** the leg-level push loop is already cross-CI-safe by construction (ref-CAS: push, on reject fetch and `rebase -X theirs --onto FETCH_HEAD HEAD~1`, retry ×10 — no clock, no shared graph, so a competitor on another CI is indistinguishable from one on the same CI). The only unsafe writer is the force-push, and it must be ordered against *previous* runs' legs, which only an explicit pre-push cancel can do.
- **failure mode of the choice:** the cancel-and-wait sits on the critical path of every AzDO run, so an Actions API outage or a slow-terminating leg delays every leg behind it; and cancellation is not instantaneous, so a genuinely mid-push leg can still land — a residual sliver, recoverable by re-running that leg.

### D-8 — AzDO posts a commit status; the workflow creates the check run and concludes both

- **chosen:** after the dispatch returns 204, the AzDO job posts a **pending commit status** on `$(System.PullRequest.SourceCommitId)`. The workflow's `prepare` creates a check run with an explicit `head_sha`; `report`, under `if: always()`, concludes **both** the check run and the commit status by re-POSTing the same context. The status context is deliberately *not* added to branch protection's required checks until TO-3 has proven the chain end to end.
- **rejected:** posting the pending status and concluding only the check run. Round 2 refuted it: statuses and check runs are distinct entities, and a status stays pending until another POST on the same context — so the **success** path would leave every tested head permanently yellow, a hard merge block if the context were ever required, and would make the healthy state indistinguishable from "the workflow died at startup", which is the one failure D-8 exists to surface.
- **rejected:** AzDO creating the check run. It cannot — Checks is GitHub-App-only and the dispatch PAT can write only commit statuses (U-9).
- **rejected:** relying on the workflow's native check suite. A `workflow_dispatch` run attaches its suite to the dispatched ref's tip (master), not the PR head, so nothing appears on the PR.
- **why this:** the commit status covers the window *before* `prepare` runs — a dispatch accepted and then never started still leaves a visible marker instead of silence — and giving it a concluding POST makes its steady state meaningful.
- **failure mode of the choice:** two mechanisms report one thing and can still disagree if `report` never runs at all (a cancelled run, a runner outage); the residual signal is then a stale pending status, which is the correct-but-ambiguous reading rather than a false green.

## P6 Edit-points

- E-1 (phase 1, done) `Build/Azure/pipelines/templates/test-workflow-macos.yml` — deleted
- E-2 (phase 1, done) `Build/Azure/pipelines/templates/test-jobs.yml:test_macos_job` — job and `mac_enabled` parameter removed
- E-3 (phase 1, done) `Build/Azure/pipelines/templates/test-jobs.yml:test_windows_job.strategy.matrix` — net8/9/10 enabled only when the leg has no Linux job, with a `win_tfms_always` opt-out
- E-4 (phase 1, done) `Build/Azure/pipelines/templates/test-matrix.yml` — macOS fields dropped from 25 entries, `win_tfms_always` documented and set on `w_DB2InformixDuckDB`
- E-5 (phase 1, done) `Build/Azure/pipelines/default.yml` and `testing.yml` — `mac_enabled` removed
- E-6 (phase 1, done) `Build/Azure/scripts/mac.db2.provider.sh` and the four sibling `mac.*.sh` — deleted
- E-7 (phase 1, done) `linq2db.slnx` — the six deleted files removed from the solution listing
- E-8 (phase 1, done) `Build/Azure/scripts/db2informixduckdb.sh` — macOS wait-bound comment removed
- E-9 (phase 1, done) `Build/Azure/README.md` — macOS column and legend removed, `:arrow_right:` legend added, nine cells marked, SQL Server 2017's Linux cell corrected
- E-10 (phase 2) `.github/workflows/build.yml` — new: build+pack, package verification, Examples, `Tests.Analyzers`, SingleFile smoke, CLI tests; builds `-c Azure` per D-4 and passes `-NoAzdoLogs` to the two `verify-*.ps1`
- E-11 (phase 2) `Build/Azure/pipelines/build.yml` — `pr: none`, sequenced after E-10 is live and green on `pull_request` and after branch protection's required-check list is swapped, since flipping it first stalls every PR if that check is required
- E-12 (phase 2) `.github/CODEOWNERS` — add `/.github/workflows/` and `/Build/` entries
- E-13 (phase 2) `.gitattributes` — add an explicit `*.yml text eol=lf` rule
- E-14 (phase 3) `Build/CI/test-matrix.json` — **withdrawn by A-2**; there is no separate JSON matrix
- E-15 (phase 3) `Build/CI/generate-azdo-matrix.ps1` — **withdrawn by A-2**; there is no generator
- E-36 (phase 3, added by A-2) `Build/Azure/pipelines/templates/test-matrix.yml` and `test-jobs.yml` — replace each entry's paired `${{ if }}` / `${{ if not }}` `enabled` blocks with a `filters` string, selected by `contains(test_config.filters, parameters.db_filter)`, so one file serves both CIs
- E-37 (phase 3, added by A-2) `Build/Azure/pipelines/templates/test-jobs.yml:parameters` — typed list form declaring `db_filter` with no default, so a caller that fails to forward it is a compile error rather than a silently unfiltered run; `test-matrix.yml` forwards it
- E-16 (phase 3) `Build/CI/free-disk-space.sh` — extracted from `test-workflow-linux.yml`'s inline block
- E-17 (phase 3) `Build/CI/push-baselines.ps1` — extracted from the two inline `Commit test baselines` blocks, including their `##vso[task.logissue]` calls
- E-18 (phase 3) `Build/CI/report-trx.ps1` — new, replaces `PublishTestResults@2`
- E-19 (phase 3) `Build/CI/dispatch-github-tests.ps1` — new, AzDO to GitHub dispatch, passing `pr` explicitly per D-1
- E-20 (phase 3) `.github/workflows/tests.yml` — new, `workflow_dispatch`, `concurrency: tests-<pr>-<surface>`, carrying `--filter "TestCategory != SkipCI"`
- E-21 (phase 3) `Build/Azure/pipelines/templates/test-jobs.yml` — `dispatch_github` with `dependsOn: create_baselines_branch` and the pending commit status of D-8, the pre-push GitHub-run cancel of D-7 in `create_baselines_branch`, and the `all_in_azure` parameter
- E-22 (phase 3) `Build/Azure/pipelines/templates/test-matrix.yml` — declare `all_in_azure` and forward it to `test-jobs.yml`, the hop D-6 requires and the generator must emit
- E-23 (phase 3) `Build/Azure/pipelines/default.yml` — pass `all_in_azure: true` per D-6
- E-24 (phase 3) `DataProviders.json:AzureConnectionStrings` — add `"MaxParallelLanes": 4` per D-5
- E-25 (phase 3) `Build/Azure/scripts/oracle1112.sh:3` and the two sibling Oracle scripts — CI-agnostic `TZ=CET`
- E-26 (phase 3) `Build/Azure/scripts/db2.provider.sh:32-33` — CI-agnostic `PATH` and `LD_LIBRARY_PATH`
- E-27 (phase 3) `Build/Azure/scripts/ensure-baselines-branch.ps1:121` — add a `-GitHubOutput` switch
- E-28 (phase 4) `.github/workflows/tests.yml` — add the `windows-tests` matrix job
- E-29 (phase 4) `Build/Azure/pipelines/templates/build-job.yml:build_x86_job` — deleted
- E-30 (phase 4) `Build/Azure/pipelines/templates/test-jobs.yml:72` — drop the `dependsOn: build_x86_job` that E-29 orphans
- E-31 (phase 4) `Build/Azure/pipelines/templates/build-job.yml` — artifact fetch or trim, whichever U-4 resolves to
- E-32 (phase 5) `README.md:6` — replace or remove the two AzDO build badges
- E-33 (phase 5) `CONTRIBUTING.md:89,310-325` — CI section, `AZURE` symbol attribution, trigger semantics
- E-34 (phase 5) `Build/Azure/pipelines/templates/test-jobs.yml:linux_max_parallel` — retire it or re-point its comment, since the AzDO Linux job becomes empty
- E-35 (phase 2, added by A-1) `global.json:sdk` — `rollForward: latestFeature` from a 10.0.100 floor, so the newest installed 10.0.x SDK is selected rather than the highest patch of the 10.0.2xx band

## P7 Impact map

- `Build/Azure/pipelines/default.yml:42-47` — the second includer of `test-matrix.yml`, `full_run: true` on PRs to `release` per `:11-12`; found by sweeping includers of the template, which the first draft never searched — covered by E-22, E-23
- `Build/Azure/pipelines/templates/test-matrix.yml:5,84` — `linux_max_parallel` shows the declare-and-forward pattern `all_in_azure` must follow, since `default.yml` includes this file and not `test-jobs.yml` — covered by E-22
- `Build/Azure/pipelines/templates/test-jobs.yml:70-73` — `test_windows_job.dependsOn` names `build_x86_job`, which E-29 deletes; searched `dependsOn` across `Build/Azure/pipelines/` — covered by E-30
- `Build/Azure/pipelines/templates/test-workflow-linux.yml:284` and `test-workflow-windows.yml:380` — `##vso[task.logissue]` inside the baselines-push blocks; benign but shows the first draft's `##vso` census scope of `Build/Azure/scripts/` was too narrow, the correct scope being all of `Build/` — covered by E-17
- `Build/Azure/scripts/ensure-baselines-branch.ps1:90-106` — the clone, rebase and `git push -f`, ordered ahead of legs only by AzDO's `dependsOn`, with the clone alone measured at 2.3 min at `:77-79` — covered by E-21 via D-7
- `Tests/Base/TestConfiguration.cs:62-65` — `#if AZURE` appends `.Azure` to the config name, selecting `NET100.Azure` and siblings from `DataProviders.json`, which supply `AzureConnectionStrings` and `BaselinesPath`; a leg built `-c Release` silently gets local connection strings and no baseline capture, which D-4 rejects — covered by E-10
- `Tests/Directory.Build.props:17-21` — `'$(Configuration)' == 'Azure'` is what defines `AZURE`; searched `Configuration.*Azure` across `*.props` and `*.csproj`, and D-4 keeps the configuration name — covered by E-10
- `Tests/Linq/Update/InsertTests.cs:27,69` and four sibling sites — six `#if AZURE` gates carving out Firebird, DB2 and Informix issues plus a netfx GAC redirect; losing the symbol un-gates all six, which is why D-4 holds the configuration name — covered by E-10
- `Tests/Linq/TestsInitialization.cs:214` — the lane cap from `Environment.ProcessorCount`; searched `ProcessorCount` across the worktree, the only hit in test or product code — covered by E-24 via D-5
- `DataProviders.json:44-66,169` and `Tests/Base/Tools/SettingsReader.cs:56,67-73` — the four `*.Azure` roots are `BasedOn: AzureConnectionStrings` and the merge propagates `MaxParallelLanes`, with zero `BasedOn` or `MaxParallelLanes` hits anywhere in `Build/Azure/**/*.json`, so no per-leg config can shadow the pin — covered by E-24
- `Build/Azure/scripts/oracle1112.sh:3`, `oracle1819.sh:3`, `oracle2123.sh:3` — `##vso[task.setvariable variable=TZ]CET`, inert on GitHub, so the Oracle legs would run in the runner's default timezone and surface as flaky datetime assertions rather than a setup error — covered by E-25
- `Build/Azure/scripts/db2.provider.sh:32-33` — `##vso[task.setvariable]` for `PATH` and `LD_LIBRARY_PATH`, inert on GitHub, so the DB2 native driver is not found at test time — covered by E-26
- `Build/Azure/scripts/ensure-baselines-branch.ps1:121` — `##vso[task.setvariable ... isOutput=true]`, the script's entire output contract — covered by E-27
- `Build/Azure/scripts/verify-nuget-sizes.ps1`, `verify-analyzer-delivery.ps1`, `publish-azure-artifacts.ps1` — also emit `##vso[task.logissue]`, but all three carry a `-NoAzdoLogs` switch and their exit codes carry the verdict — covered by E-10
- `Tests/Base/TestBase.cs:37-39` — trace echo suppressed when `TF_BUILD` or `CI` is set, and GitHub sets `CI=true`; searched `TF_BUILD` and `GetEnvironmentVariable` across `Tests/` and `Source/`, the only CI detection in the tree — out-of-scope
- `Tests/Base/Attributes/SkipCIAttribute.cs` — a plain category with no runtime check, the exclusion being the YAML `--filter`, repeated ~30 times — covered by E-20
- `.gitattributes:6` — `*.sh text eol=lf` keeps the setup scripts LF-normalized on Windows checkouts, and no rule exists for `*.yml` — covered by E-13
- `linq2db.slnx` — ~232 literal `Build/Azure/...` `<File Path>` entries across nine solution folders, a second argument against renaming the directory — covered by E-7, and D-4 rejects the rename
- `README.md:6` — two `shields.io/azure-devops` badges on AzDO definition 5, which after the split go green off a pipeline that no longer runs the tests — covered by E-32
- `CONTRIBUTING.md:89,310-325` — the CI section attributes the whole matrix to one AzDO definition and `:89` attributes the `AZURE` symbol to Azure Pipelines when the configuration sets it; the file carries `uid: contributing` and is republished on linq2db.github.io — covered by E-33
- `.github/CODEOWNERS` — two `/Source/**` lines only, so new workflow files would land with no required-owner review — covered by E-12
- `Build/Azure/pipelines/templates/test-jobs.yml:39-41` and the two `test-workflow-*.yml` push steps — baselines commit identity `azp@linq2db.com` and "Azure Pipelines Bot", which GitHub legs need an equivalent of — covered by E-17
- `Build/Azure/netfx/*.json` and the `*.Azure` keys in `DataProviders.json` — reused verbatim, and the `Build/Azure` directory name doubles as `$(test_configuration)` at `build-job.yml:169,173` — out-of-scope
- `Source/LinqToDB/Internal/DataProvider/SqlServer/SqlServerSchemaProvider.cs:IsAzure` — Azure SQL Database detection, unrelated to Azure DevOps; searched `Azure` across `Source/` — out-of-scope
- Branch protection's required-check list, the AzDO pipeline definition registrations and the org secret inventory — deferred: not checkable from the repo, named so they are not mistaken for searched and clean

## P8 Test obligations

- TO-1 Leg-set and test-count parity against the last pre-migration `test-all`, per leg, also capturing the `[parallel] installed ResourceLaneDispatcher (maxLanes=... cpus=... nunitWorkers=...)` line from `TestsInitialization.cs:231` on both sides before the first GitHub run — proof: characterization
- TO-2 A scratch PR whose SQL moves, with legs on both CIs, produces exactly one `baselines/pr_<n>` branch and one draft PR carrying commits from both — proof: red-green, since before the dispatch exists the GitHub legs contribute nothing
- TO-3 `gh pr checks <n>` lists the GitHub result on the PR head SHA, a deliberately failed leg shows red there, and the commit status reaches a concluded state on the success path — proof: control, green leg versus forced-failing leg
- TO-4 `all_in_azure` on a scratch PR runs every leg on AzDO and dispatches nothing — proof: control, same pipeline with the flag on and off
- TO-5 A GitHub leg's log shows "Azure configuration detected." from `TestConfiguration.cs:63` and the run produces a baselines commit — proof: red-green, since a `-c Release` leg produces neither
- TO-6 `test-all` end-to-end wall clock against the pre-migration band per `ci-tests.md` — proof: characterization
- TO-7 The 8 AzDO legs keep producing identical baselines after `dispatch_github` and `all_in_azure` are added, a symmetry guard on the untouched path — proof: characterization
- TO-8 A scratch PR targeting `release` runs `default.yml` and produces the complete all-TFM leg set a pre-migration release PR produced — proof: red-green, since before D-6 the migrated legs are absent
- TO-9 A leg log shows `maxLanes=4 [from config]` rather than `[default 2xCPU]` on both a GitHub and an AzDO leg — proof: control, GitHub 4-vCPU leg with the pin versus without

## P9 Verification gates

Out-of-repo prerequisites, each blocking the obligation beside it: `BASELINES_GH_PAT` as a GitHub Actions repository secret, without which TO-2 and TO-5 hard-fail; a GitHub PAT with `actions: write` as an AzDO secret variable, without which E-19 cannot dispatch; branch protection's required-check list swapped before E-11; and the Actions policy, which is done and verified.

- G-01: blocked — a full `test-all` on both CIs is the equivalent of `/test` here, and it cannot run until phase 3 exists (TO-1)
- G-02: blocked — baselines review depends on the same run (TO-2)
- G-03: n/a — no public API surface
- G-04: n/a — no public API surface
- G-05: blocked — phase 2's GitHub build must cover the portable TFMs, not just `net10.0`, and that workflow does not exist yet
- G-06: pass — phase 1 touched only lines the change owns; the README table rewrite is the change itself
- G-07: n/a — no playground scratch
- G-08: n/a — no cross-cutting core change, `SqlQuery/` and `Translation/` untouched

## P10 Adjudicated

- **Phase 1's release-run coverage narrowing is intended.** The Windows TFM trim also drops the `full_run` main suite for net8/9/10 on the four dual-OS legs. The Linux leg runs the same TFMs on the same providers — three of the four share one config file between OSes, and `sqlserver.fts.2017_2019.json` is a superset of `sqlserver.2017_2019.json`. Stated in the PR body.
- **The Windows DuckDB leg keeps net8/9/10 via `win_tfms_always`**, against the general rule, because it exercises the windows-native DuckDB binary no Linux leg can reach. Without the opt-out the leg would have had no TFM enabled and failed on a missing `.trx`.
- **SQL Server on the slower agents is unmeasured** (U-2). D-2's split is by capability, not duration. Do not flag it as a load-balancing defect before a full run exists; do flag it after.
- **`--configuration Azure` on GitHub is deliberate** despite reading oddly — see D-4 and the `P7` rows it covers.
- **The D-7 residual window is accepted.** Cancellation is not instantaneous, so a leg already mid-push can still land inside the force-push window. The loss is one leg's baselines on a re-run, recoverable by re-running that leg.
- **U-3 is unresolved by design.** Whether artifacts survive a partial re-run is documented behaviour, to be confirmed on the first real re-run rather than probed speculatively.

## P11 Amendments

- A-3 (2026-09-02) Adds **E-37**. Moving the filter test into `test-jobs.yml` left it reading a `parameters.db_filter` that file neither declared nor received, and an undefined parameter in a template expression is empty rather than an error — so `contains(x, '')` was always true and build 23199 ran all 29 legs for a `test-sqlite` request. This is precisely the shape the critic raised against D-6 in round 2, accepted and written into the plan, then reproduced two commits later with a new parameter. The fix forwards it and converts the block to the typed list form with `db_filter` required, because a default of `'[all]'` would have concealed it identically: the hazard is a *plausible* value, not a missing one.
- A-2 (2026-09-02) Revises **D-3** and withdraws **E-14** and **E-15** in favour of **E-36**. The generator was traded for expressing selection as data in the one existing matrix file, which removes the JSON, the generator and the drift check, and takes 75 lines out. The user chose this over the approved D-3 knowing it rested on an unverified Azure expression. It then took two attempts: `containsValue` over a YAML list compiled and matched nothing, producing an empty matrix and a build that reported `succeeded` with zero tests executed (23192) — caught because the step names rendered the literal `$(title)`. The shipped form is a concatenated string with `contains()`, the function the removed blocks already used against the same parameter. **This voids approval for the phase-3 matrix surface**, and the D-3 failure-mode line now carries the verification rule the episode earned: check leg names in the timeline, never the build verdict.
- A-1 (2026-09-01) Adds **E-35**, `global.json`, which no phase authorized. The phase-2 workflow failed every job with CS9057: CodeGenerators is built against Roslyn 5.6, so it needs a 10.0.4xx SDK, but `rollForward: minor` from a 10.0.200 floor prefers the highest patch of the 10.0.2xx band over rolling forward, and the runner image carries both. The first fix isolated the SDK install in the workflow (`DOTNET_INSTALL_DIR`), reproducing what Azure's `UseDotNet@2` does implicitly — a workaround in CI for a resolution bug in the repo. On the user's direction the root fix replaced it and the workaround was removed. Worth recording that this was never CI-specific: any contributor whose highest SDK is a 10.0.2xx hits the same CS9057 today, and Azure masked it only because `UseDotNet@2` installs into an isolated tool directory where the resolver never sees an older band. **This voids approval for the phase-2 surface**, which now touches a product file rather than only CI definitions.

## P12 Critic verdict

Provenance note for `P7`: the impact map was searched by five concurrent `Explore` scouts, then re-verified against the worktree at `origin/master` — four of the five were pointed at the primary clone, which was 43 commits stale, so their file names and two of their negative results were from the pre-#5819 tree. Every row above is confirmed current.

**Round 1 — `refuted`** (fable, per `.claude/plans/config.json`).

The refutation was earned by the objection the dispatch brief ranked last. The critic swept **includers of `test-matrix.yml`** — a search the author's census never ran, having looked at consumers of the scripts and of the configs but not of the template itself — and found `default.yml:42-47`, which includes the full matrix with `full_run: true` on PRs to `release`. `P3` had asserted the opposite against the file. As designed, a release-prep PR's full run would have silently lost the ~20 migrated legs, thinning the baseline set `release-publish` regenerates on exactly that run.

Objections and dispositions: (1) the `default.yml` includer — accepted, `P3` corrected, U-7, D-6, E-22, E-23, TO-8, `P7` rows; (2) U-1 should close before approval and the pin is one key not five legs — accepted after verifying the `BasedOn` chain, D-5, E-24, TO-9; (3) the leg push loop is cross-CI-safe but `ensure-baselines-branch.ps1`'s force-push is not — accepted, U-8, D-7; (4) a PAT cannot create check runs and a dispatched run's suite attaches to master not the PR head — accepted, U-9, D-8; (5) secrets provisioning appears in no phase — accepted, `P9`; (6) E-11 has no required-check sequencing story — accepted; (7) E-29 orphans a `dependsOn`, and the README matrix is a third uncheck-drifted copy — accepted as E-30, README noted and deliberately left hand-maintained; (8) D-2's split is by capability not measurement but correctly parked — agreed, no change.

**Round 2 — `refuted`.** Four objections, all against the round-1 fixes, which is what round 2 was aimed at. The author judged all four correct and applied every remedy.

- **A — D-7's mechanism fired after the window it claimed to close.** `dispatch_github` depends on `create_baselines_branch`, so the GitHub run that would trigger cancellation is created only after the force-push completes, and GitHub evaluates `concurrency` at run creation. The window is the clone-to-force-push span, with the clone alone measured at 2.3 min, not a mid-push sliver. Fixed: D-7 now cancels from inside `create_baselines_branch` *before* the rebase clone.
- **B — `tests-<pr>` over-cancelled.** Two different-surface runs on one PR share the group, so a second dispatch would kill the first's legs, which coexist today as separate AzDO definitions. Fixed: `tests-<pr>-<surface>`. The related gap — the PR number recoverable only by parsing `baselines/pr_<n>` — is fixed by naming `pr` an explicit dispatch input in D-1.
- **C — D-8 never concluded the commit status.** Statuses and check runs are distinct entities and a status stays pending until another POST on the same context, so the success path would have left every tested head permanently yellow, blocking merges if the context were ever required and making the healthy state indistinguishable from a workflow that died at startup. Fixed: `report` concludes both under `if: always()`, and the context stays out of required checks until TO-3 proves the chain.
- **D — D-6's parameter did not thread.** `default.yml` includes `test-matrix.yml`, not `test-jobs.yml`, and nothing declared or forwarded `all_in_azure` through the intermediate template. Fixed: E-22 adds the hop and D-3 records it as a generator requirement.

What round 2 re-checked and could not break: **D-5 end to end** — `AzureConnectionStrings`, the four `BasedOn` roots, the user-file key merge at `SettingsReader.cs:56,67-73`, zero shadowing hits across `Build/Azure/**/*.json`, and a log line that names its own source. It found no way the pin applies partially that TO-9 would miss. It also confirmed the include chain and the E-30 dangling `dependsOn`.

Left `reasoned, unprobed` and gated by TO-3: check-run creation from a dispatched run's `GITHUB_TOKEN` with an explicit `head_sha`, GitHub's concurrency evaluation timing, and merge-box dedup between a status and a check run of the same name.

**No round 3**, per the one-round cap and the user's direction: the round-2 remedies are the critic's own prescriptions, applied verbatim.
