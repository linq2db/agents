# Work plan: feature-release-tests-github — Release-PR full test run on GitHub Actions

**Tier:** M  ·  **Status:** approved  ·  **Approved-at:** 2026-10-24 (user, after critic round 1 `weak`; fallback baselines option A = P10 L-7)  ·  **Branch:** feature/release-tests-github
**Schema:** `.claude/docs/work-plan.md`  ·  **Gates:** `.claude/docs/definition-of-done.md`

## P1 Problem

A PR into `release` runs the full provider matrix only on Azure: `Build/Azure/pipelines/default.yml:11-12` (`pr: release`) and `:42-47` (`test-matrix.yml`, `full_run: true`, `db_filter: '[all]'`, no offload). It runs on Azure's 10 slots of 2-vCPU agents and takes hours; 6.5.0's release PR ran ~18 h wall clock (`.claude/skills/release-publish/SKILL.md:204`). GitHub Actions already runs every linux leg and the docker-free windows legs on 4-vCPU runners (`.github/workflows/tests.yml`). The win-mssql containers were proven on GitHub windows runners by probe run 33410071655 (`plans/feature-migrate-ci-to-github-actions/plan.md:44`, U-6). Even so, `tests.yml` cannot run a release run, for three reasons:

- it has no trigger for PRs into `release`, only `workflow_dispatch` / `workflow_call` (`tests.yml:13-52`);
- its selector takes a windows leg only when the leg is flagged `gh_windows` (`tests.yml:165`), and no SQL Server entry carries that flag;
- the Windows DuckDB leg's `enable_os_windows` sits inside an Azure template conditional (`test-matrix.yml:531-534`), which the GitHub parser reads as absent.

The capability that is missing today: a PR into `release` gets the complete full-run matrix on GitHub automatically, and Azure `default` stops running it.

## P2 Success criteria

- SC-1 A same-repo PR into `release` starts the GitHub full run with no comment and no dispatch, and the run is listed in the PR's checks — unmet if no `tests-release` run appears on the PR after it is opened or pushed  → TO-7
- SC-2 That run selects exactly the legs Azure's `default` full run selects: 15 linux legs (b c h i j k l m n p q s t u w) and 15 windows legs (a d e f g l m n o r s v w x z), including all 8 win-mssql windows legs and Windows DuckDB, with `full_run` main-suite semantics — unmet if any listed leg is missing or extra in `prepare`'s output  → TO-1, TO-6
- SC-3 Comment-triggered (`/azp run test-*`) GitHub runs select exactly what they select on master for every surface, so the win-mssql legs stay on Azure in development — unmet if any surface's `linux`/`windows` JSON differs from master's  → TO-2
- SC-4 Azure `default` on a release PR runs no test legs and no `create_baselines_branch` (they show as skipped). A manual queue with `run_tests: true` compiles the full 15+15 matrix. Its baselines go to `baselines/default`, not `baselines/pr_<N>` (P10 L-7). Azure `testing.yml` definitions compile to an unchanged leg list — unmet if a release-PR `default` build runs a `Win`/`Lin` job, or `test-all` lists different legs  → TO-4, TO-5
- SC-5 The release run's baselines land on `baselines/pr_<N>`, rebased onto baselines master first when that branch already exists behind it — unmet if legs push to another branch or onto an unrebased stale branch  → TO-7, TO-8
- SC-6 Windows DuckDB stays full-run-only on both CIs — unmet if it is selected on a non-full run (GitHub `all_legs` without `full_run`, or Azure `testing.yml`)  → TO-3, TO-4

## P3 Constraints & anti-goals (M/L)

- No product, test or script code changes. The reused scripts are `ensure-baselines-branch.ps1`, `checkout-baselines.ps1`, `push-baselines.ps1`, `run-provider-tests.ps1/.sh`, `mssql-container.ps1` and `report-trx.ps1`.
- Comment-triggered GitHub runs keep their exact selection (user decision: win-mssql stays on Azure for development load balance).
- Azure `testing.yml` keeps its exact compiled leg list and its `create_baselines_branch` behaviour.
- Baselines branch naming stays `baselines/pr_<N>`, so `release-publish` step 6 (merge `baselines/pr_<release-pr>`) is unchanged.
- Azure `default` keeps build, nuget job, examples, analyzer tests, single-file smoke and `with_api_analyzers` on release PRs.
- **Merge ordering.** Do not merge this PR while a release PR is open. Its merge fires `synchronize` on the open release PR (head `master`), and from then on the Azure `default` check that `release-publish` (`SKILL.md:204-206`) reads as "the release run" goes green in ~30 min with every leg skipped. An operator following the not-yet-updated skill could merge a partial `baselines/pr_<release-pr>`. When this was written no PR into `release` was open: 6.5.1 merged as #6123 on 2026-10-23, and #6124, its baselines-trigger PR, is closed (`gh pr list --base release --state all`, user-confirmed). The `release-publish` follow-up (P10 L-5) must land before the next release PR opens.
- **User-visible deltas vs master:**
  - The release PR's provider-test checks move from Azure `default` jobs to the GitHub `tests-release` checks. Azure `default` on a release PR shows build and nugets only. Master's contract for this is stated in `Build/Azure/README.md:13-17` ("PR to `release` branch: runs all tests"), which gets E-7.
  - A fork PR into `release` no longer gets a provider run at all; master ran Azure `default` on it.
  - (A-2) On both CIs, the netfx main suite of the non-Access windows legs now runs as an x64 process instead of x86.

## P4 Unknowns (M/L)

- U-1 Does `pull_request` fire for the release PR (base `release`, head `master`, same repo) with this repo's Actions policy? — resolved-by scout: `.github/workflows/build.yml:21-22` (`pull_request:` with no branch filter) already runs on every PR including release PRs; the branch filter `branches: [release]` matches the base branch per Actions semantics (reasoned, unprobed — TO-7 measures it)
- U-2 Does a same-repo `pull_request` caller pass `BASELINES_GH_PAT` / `DOCKERHUB_*` to the reusable `tests.yml` via `secrets: inherit`? — resolved-by scout: `tests-comment.yml:150` uses the same `secrets: inherit` pattern; `pull_request` from a same-repo head receives secrets, fork heads do not (reasoned, unprobed — TO-7 measures it; D-1's fork gate covers the fork case)
- U-3 Can GitHub windows-2025 runners host the win-mssql images? — resolved-by probe: run 33410071655, 6/6 containers up, `isolation=process`, ltsc2022 images on a 26100 host (`plans/feature-migrate-ci-to-github-actions/plan.md:44`); the 2025 image's base is unrecorded in `docker/mssql/build.ps1:32-39`, so TO-6 re-measures all 8 legs
- U-4 Disk on the two-image legs (l, m) — resolved-by probe: 34.4 GB free before, 26.2 GB after two multi-GB pulls (`plans/feature-migrate-ci-to-github-actions/plan.md:44`); test binaries are downloaded and deleted per TFM (`Build/CI/run-provider-tests.ps1:176-180`); TO-6 observes the actual legs
- U-5 Runner concurrency for ~30 legs — resolved-by probe: `gh api orgs/linq2db` → plan `free` (20 concurrent jobs for public repos), so legs queue; accepted in P10 L-1
- U-6 Can `ensure-baselines-branch.ps1` run on an ubuntu GitHub runner from the `test_scripts` artifact? — resolved-by scout: `tests.yml:289-290` stages `Build/Azure/scripts/*` and `Build/CI/*` flat, so `$PSScriptRoot/baselines-base.ps1` (`ensure-baselines-branch.ps1:56`) resolves. The script needs `GITHUB_TOKEN` = PAT (`:45`), and `gh` must not see a `GH_TOKEN` (gh prefers it). The rebase path needs `EMAIL`/`GIT_AUTHOR_NAME`/`GIT_COMMITTER_NAME` (`:111-116`). `-EmitOutputs` is `##vso`-only (`:133`), so it is dropped
- U-7 Does disabling the Azure test matrix in `default.yml` also stop Azure's `create_baselines_branch` force-push? — resolved-by scout: `test-jobs.yml:70` gates it on `parameters.enabled` and `with_baselines`, and E-5 wraps `enabled`
- U-8 What survives the release PR merging mid-run (GitHub deletes `refs/pull/<n>/merge`)? — resolved-by scout: only `prepare` (`tests.yml:83-87`), `build` (`:243-245`) and `build_x86` (`:375-377`) check out (the new `baselines_init` downloads `test_scripts` instead); the legs run from artifacts and scripts, and partial re-runs reuse attempt-1 artifacts (`plans/feature-migrate-ci-to-github-actions/plan.md:41`, U-3); those jobs finish long before the team-test gate allows a merge; residual in P10 L-3
- U-9 Are GitHub windows legs equivalent to Azure's for `full_run`, pre/post-test and retry? — resolved-by scout: `RUN_MAIN` at `tests.yml:725,751,776,803` mirrors `test-workflow-windows.yml:245-252`; pre/post-test via `run-provider-tests.ps1:145-172`; gaps are the Docker Hub login (`test-workflow-windows.yml:159-167`, absent from `windows-tests`) and the fixed 180-min timeout (`tests.yml:630` vs `test-jobs.yml:109-112`), both closed by E-2; Azure's idle-process kill (`test-workflow-windows.yml:93-132`) has no GitHub twin, adjudicated in P10 L-2
- U-10 Does `push-baselines.ps1` survive ~30 legs pushing to one branch? — resolved-by scout: 10 rejection retries with fetch + rebase (`push-baselines.ps1:92-93,111-163`), and lost PR-creation races count as success (`:194-196`); the comment path's `test-all` already pushes ~20 GitHub legs plus Azure legs to one branch

## P5 Decisions (M/L; rejected alternatives mandatory at L)

### D-1 — A separate caller workflow `tests-release.yml`

- **chosen:** new `.github/workflows/tests-release.yml`, `on: pull_request: branches: [release]` (default types opened/synchronize/reopened, matching Azure `pr: release`), job-level `if: github.event.pull_request.head.repo.full_name == github.repository`, one `uses: ./.github/workflows/tests.yml` job with `secrets: inherit`.
- **rejected:** adding `pull_request` to `tests.yml` itself — under that event every `inputs.*` is empty and `prepare` refuses an empty surface (`tests.yml:114-116`); the trigger-specific defaults would leak into a file two callers share.
- **why this:** mirrors the existing `tests-comment.yml` → `tests.yml` split; a `pull_request` run attaches to the PR head natively, so no commit-status relay is needed.
- **failure mode of the choice:** the run is invisible to scripts that hardcode the comment workflow (`.claude/scripts/gh-leg-history.ps1:59-60`, id 350529502) — a corpus follow-up, P7.

### D-2 — An `all_legs` input instead of flagging the win-mssql entries `gh_windows`

- **chosen:** `tests.yml` input `all_legs` (bool, default false); when true, `prepare` ignores `gh_linux` / `gh_windows` and selects every `enable_os_*` entry the surface matches.
- **rejected:** `gh_windows: 'true'` on the 8 win-mssql entries — `testing.yml:41` offloads every flagged leg, so `/azp run test-sqlserver` would leave Azure; the user rejected that to keep development load split across both CIs.
- **why this:** the release run's leg set becomes independent of the development split, so the split can be tuned without shrinking release coverage.
- **failure mode of the choice:** an entry whose `enable_os_*` is true but which deliberately runs nowhere on GitHub would be pulled into the release run anyway; none exists today (`y_Access_ACE_x64` is `enable_os_windows: false`, `test-matrix.yml:566`).

### D-3 — Rebase the baselines branch on GitHub only when the caller asks

- **chosen:** input `rebase_baselines` (bool, default false). When it is true, a `baselines_init` job (ubuntu, `needs: build`, downloads `test_scripts`) runs `ensure-baselines-branch.ps1 -PrId <pr> -BaselinesMaster master -Rebase`, with `GITHUB_TOKEN` = `BASELINES_GH_PAT` and the git identity env. Both test jobs `needs:` it, and their `if:` accepts `success` or `skipped`.
- **rejected:** always rebase on GitHub. Comment runs already get Azure's `create_baselines_branch` rebase, and two force-pushers on one branch race (`plans/feature-migrate-ci-to-github-actions/plan.md:46`, U-8).
- **rejected:** no rebase. A `baselines/pr_<release>` left by an earlier run stays behind baselines master once other baselines PRs merge, and every leg clones it (`checkout-baselines.ps1:65-66`). Superseded rationale, corrected by A-1: the rebase does *not* cover `release-publish`'s reset of master to an ancestor, because the branch then compares `ahead`.
- **why this:** it reuses the exact script and semantics Azure runs today, in one job ahead of every leg.
- **failure mode of the choice:** the rebase path does a full ~420 MB clone (`ensure-baselines-branch.ps1:87-100`), and it sits in the serial prefix only when a stale branch exists.

### D-4 — Replace `w_DB2InformixDuckDB`'s Azure conditional with a `win_full_run_only` field

- **chosen:**
  - `test-matrix.yml`: `enable_os_windows: true` plus `win_full_run_only: true`, documented in MISC.
  - `test-jobs.yml:124`: gains `not(and(eq(test_config.win_full_run_only, true), ne(parameters.full_run, true)))`.
  - `tests.yml` `prepare`: skips the windows half when `win_full_run_only` is set and `full_run` is off. The `azure_expr` guard (`:138-143`) keeps its current `gh_windows` form, and also fires for any `${{` key when `all_legs` is set. It is not made unconditional: a stacked PR's `refs/pull/<n>/merge` that predates this change still carries `w_`'s conditional, and every comment run on it would then fail at `prepare` (critic round 1).
- **rejected:** have `prepare` evaluate the two known conditional spellings. That means a second expression evaluator kept in step with Azure's, which is what #5848's "entry selection as data" removed.
- **why this:** both CIs read the same plain field, and the parser can no longer drop a leg silently.
- **failure mode of the choice:** Azure's boolean comparison of an unquoted `true` field must match the `win_tfms_always` precedent (`test-jobs.yml:143`, `eq(test_config.win_tfms_always, true)`). If it doesn't, Windows DuckDB runs on every `testing.yml` run (TO-4 catches it), or never on a full run (TO-5 catches it).

### D-5 — Azure fallback as a queue-time parameter

- **chosen:** `default.yml` gets `parameters: - name: run_tests, type: boolean, default: false`. It replaces the release-target test in both places: `with_tests: ${{ parameters.run_tests }}` and test-matrix `enabled: and(${{ parameters.run_tests }}, succeeded())`. `with_tests` is spliced into a runtime `condition: and(succeeded(), …)` (`templates/build-job.yml:114,178-230,326`), so `True`/`False` is valid there. `full_run: true`, `db_filter: '[all]'` and the release-target-keyed `with_api_analyzers` stay as they are.
- **rejected:** ANDing `run_tests` with the existing release-target condition. A manual queue has no `System.PullRequest.TargetBranch`, so the fallback could never fire.
- **rejected:** deleting the matrix include. The user chose to keep a manual Azure fallback for when GitHub is unavailable.
- **why this:** one queue-time switch gives a manual full matrix without a YAML change.
- **failure mode of the choice:** a PR-triggered build always takes the default `false`, so the fallback is a manual queue only. It runs on the branch rather than as the PR build, and its baselines go to `baselines/default`, not `baselines/pr_<N>` (`ensure-baselines-branch.ps1:48-52`). Separately, `master`/`release` push builds also get `run_tests: false`, which is what they already had: the old condition required a release-target PR.

### D-6 — Keep the release run's concurrency group apart from comment runs

- **chosen:**
  - E-1 carries its own `concurrency: tests-release-<pr>` with `cancel-in-progress`, so a push to the release PR cancels the previous release run whether or not GitHub honours the called workflow's group. That point is unmeasured (critic lead).
  - The `tests.yml` group also gets `-full` appended when `inputs.full_run`.
- **rejected:** relying on `tests.yml:57-60` alone. Whether a called workflow's top-level `concurrency` governs the caller's run is unmeasured here. If it does not, every master push while the release PR is open stacks another 30-leg run on a 20-job cap (U-5).
- **rejected:** an unchanged `tests.yml` group. A `/azp run test-all` comment on the release PR has the same ref and surface (`tests.yml:59`) and could cancel the release run.
- **why this:** the caller-level group holds under either reading, and it matches Azure's cancel-on-push PR behaviour.
- **failure mode of the choice:** a comment run and the release run then coexist and push to one baselines branch, and Azure's `create_baselines_branch` force-push from the comment run can land mid-release-run. Adjudicated in P10 L-4.

## P6 Edit-points

- E-1 `.github/workflows/tests-release.yml` — new caller per D-1, with the reusable-call job id `tests` so `ci-test-verdicts.ps1:158` strips the prefix. It passes surface `[all]`, `full_run: true`, `all_legs: true`, `rebase_baselines: true`, `ref: github.ref`, `baselines_branch: baselines/pr_<N>` and `pr: <N>`. It also carries the fork gate, `permissions: contents: read`, and its own top-level `concurrency: { group: tests-release-<N>, cancel-in-progress: true }` (D-6).
- E-2 `.github/workflows/tests.yml` — the changes, in order:
  - inputs `all_legs` and `rebase_baselines` in both the dispatch and call blocks (D-2, D-3);
  - the `prepare` Python honours `all_legs` and `win_full_run_only`, and errors on any `${{` key when `all_legs` is set (D-4);
  - a new `baselines_init` job, which downloads `test_scripts` and checks nothing out (D-3);
  - both test jobs' `needs:` gain `baselines_init`, and their `if:` is rewritten to `!cancelled() && needs.prepare.result == 'success' && needs.build.result == 'success' && (needs.baselines_init.result == 'success' || needs.baselines_init.result == 'skipped')` plus the existing output tests; `windows-tests` keeps its `build_x86` clause;
  - full-run timeouts of 300/180 on both test jobs;
  - a Docker Hub login step on `windows-tests`;
  - the concurrency `-full` suffix (D-6);
  - the header comment updated for the new caller.
- E-3 `Build/Azure/pipelines/templates/test-matrix.yml` — `w_DB2InformixDuckDB` gets plain `enable_os_windows: true` + `win_full_run_only: true`; MISC documents `win_full_run_only`; the `gh_linux` / `gh_windows` docs (`:114-121`) and the `db_filter` comment (`:6`) stop claiming the release run stays on Azure
- E-4 `Build/Azure/pipelines/templates/test-jobs.yml` — the `win_full_run_only` clause on `test_windows_job`'s matrix condition (`:124`); the offload comments (`:43-47`, `:121-123`, `:191-194`) restated without "default.yml keeps every leg on Azure"
- E-5 `Build/Azure/pipelines/default.yml` — the `run_tests` parameter (D-5) replaces the release-target test in `with_tests` and the test-matrix `enabled`, with a pointer comment to `tests-release.yml`; the `pr:` comment (`:8-10`) restated
- E-6 `Build/Azure/pipelines/testing.yml` — comment `:38-39` restates where the release run's legs now run (restates D-2)
- E-8 `Build/Azure/pipelines/templates/build-job.yml` — the main `Tests/Linq` net462 publish leaves the `FOR` loop and gets `-a x64`, with its comment corrected; the net8/9/10 loop is unchanged (A-2). The `tests.yml` twin of the same line, "Publish and stage netfx", is covered under E-2 by A-2.
- E-7 `Build/Azure/README.md` — `:13-17` (`default` on a PR to `release`) and `:69` (the `full_run`-conditional legend) restate D-4/D-5

## P7 Impact map (M/L)

- `.github/workflows/tests.yml:117-216` — the only full parser of `test_matrix`. Unknown keys are ignored, so `win_full_run_only` is inert until read; removing the `${{` key makes `w_` visible (`:163`) — searched `test-matrix\.yml` repo-wide — covered by E-2
- `.github/workflows/tests-comment.yml:94-96` — reads only `parameters.surfaces`, and passes neither `full_run` nor the new inputs (`:144-150`), so its selection keeps the defaults — searched `test-matrix\.yml` and `uses: ./.github/workflows/tests.yml` — out-of-scope
- `Build/Azure/pipelines/testing.yml:33-45` — includer with `full_run: false` and both offloads on; the `win_full_run_only` clause keeps `w_` windows out — searched `template: (templates/)?test-` — covered by E-4 (verified by TO-4)
- `Build/Azure/pipelines/default.yml:22-47` — the second includer, `full_run: true`, now gated by `run_tests` — searched `template: (templates/)?test-` — covered by E-5
- `Build/Azure/pipelines/templates/test-jobs.yml:65-93` — `create_baselines_branch` is gated on `enabled` and so disappears from release-PR `default` builds — searched `create_baselines_branch` — covered by E-5
- `Build/Azure/pipelines/templates/test-jobs.yml:124,143` — the only Azure readers of `enable_os_windows` / `win_tfms_always` — searched `full_run|enable_os_windows` in `Build/Azure/pipelines/**` — covered by E-4
- `Build/Azure/pipelines/templates/test-workflow-windows.yml:3,245-252` and `test-workflow-linux.yml:3,157` — `full_run` consumers, unchanged — searched `full_run` — out-of-scope
- `Build/Azure/README.md:13-17,69` — stale prose — searched `default\.yml|full_run`-conditional — covered by E-7
- `Build/Azure/pipelines/testing.yml:38-39`, `test-matrix.yml:6,114-121`, `test-jobs.yml:43-47,121-123,191-194` — stale "release keeps every leg on Azure" prose — searched `default\.yml` in `Build/` — covered by E-3, E-4, E-6
- `Build/Azure/scripts/ensure-baselines-branch.ps1:45,56,100-116,133` — called from a new host (ubuntu GitHub) without `-EmitOutputs` — searched script header and `$Env:` — covered by E-2
- `Build/Azure/scripts/mssql-container.ps1:67,82,144,201` — `##vso` error lines print as plain text on GitHub; exit codes still fail the step — searched `##vso` in `Build/Azure/scripts/` — out-of-scope
- `Build/Azure/scripts/enable_tls11.cmd`, `disable_tls11.cmd` — `reg import` into HKLM SCHANNEL needs elevation; GitHub runners are admin — searched `reg import` — out-of-scope (TO-6 observes o_SqlServer2005)
- `Build/CI/push-baselines.ps1:92-196` — 10-rejection retry under ~30 concurrent legs — searched `rejectedAttempts` — out-of-scope (see U-10)
- `.claude/skills/release-publish/SKILL.md:92,184-186,204-206,226,230,332-353,373` — describes the release run as the Azure `default` run, plus the throwaway-PR recovery and `azp-build-info.ps1 -Pr` — searched `default\.yml|'default'|release PR` in `.claude/` — deferred: corpus follow-up after the linq2db PR merges (user rule: defer `.claude` docs until merge)
- `.claude/skills/release-postpublish/SKILL.md:143` — "the release PR's still-running provider matrix" queueing Azure `build` — same search — deferred: corpus follow-up after merge
- `.claude/docs/ci-tests.md:41,46,134,136,182-199,253,338,358` — Azure-default release-run text, "GitHub test runs are invisible to PR-scoped queries", Windows DuckDB note — same search — deferred: corpus follow-up after merge
- `.claude/docs/github-actions.md:24,29,34,84` — `default` context and the quoted conditional — same search — deferred: corpus follow-up after merge
- `.claude/docs/review-rubric/rubric-ci-infra.md:15`, `.claude/docs/windows-dev-gotchas.md:544` — `default.yml` triggers / test-all leg prose — same search — deferred: corpus follow-up after merge
- `.claude/scripts/gh-leg-history.ps1:59-60,87-95` — hardcodes workflow id 350529502 and reads the PR from the `authorize` job, so release runs are invisible to it — searched `350529502|tests-comment` in `.claude/scripts/` — deferred: corpus follow-up after merge
- `.claude/scripts/wait-pr-checks.ps1:12-13,45-52` — gates only on the six `build.yml` legs; the `tests-release` legs show as informational — same search — deferred: corpus follow-up after merge (decide whether the release PR should wait on them)
- `.claude/scripts/ci-test-verdicts.ps1:158` — leg name from `^tests-` prefix of the job-log name; E-1's job id must be `tests` to keep it clean — searched `-replace '\^tests-'` — covered by E-1
- `.claude/scripts/azp-run.ps1:82-85,171-178` — comment-path only, unaffected — searched `tests-comment` — out-of-scope

## P8 Test obligations (M/L)

- TO-1 Selection, release shape: run `prepare`'s Python offline against the branch's `test-matrix.yml` with `SURFACE='[all]'`, `ALL_LEGS=true`, `FULL_RUN=true`; assert the `linux` names are exactly {b_ClickHouse, c_PostgreSQL2, h_SAPHANA2, i_PostgreSQL1, j_Oracle1819, k_Firebird, l_SqlServer2017_2019, m_SqlServer2022_2025, n_SqlServer2019Extras, p_MySQL, q_Oracle2123, s_SQLite, t_Oracle1112, u_YdbSybase, w_DB2InformixDuckDB} and the `windows` names are exactly {a_SqlServer2014, d_SqlServer2012, e_SqlServer2008, f_SqlServer2016, g_SqlCE, l_SqlServer2017_2019, m_SqlServer2022_2025, n_SqlServer2019Extras, o_SqlServer2005, r_Access_MDB_Odbc, s_SQLite, v_Access_ACE_Odbc, w_DB2InformixDuckDB, x_Access_ACE_OleDb, z_Access_MDB_OleDb}; master's script given the same surface lacks a d e f l m n o w on windows — providers: n/a (leg selection, no provider runs) — proof: red→green
- TO-2 Selection, comment shape: for every surface in `test-matrix.yml:16-34`, with `ALL_LEGS` unset and `FULL_RUN=false`, the branch's `linux`/`windows`/`any`/`windows_any`/`windows_x86` outputs are byte-identical to master's — providers: n/a — proof: characterization (proves no change, no new behaviour)
- TO-3 `win_full_run_only` control: `SURFACE='[duckdb.all]'`, `ALL_LEGS=true`; `FULL_RUN=false` → `windows` excludes w_DB2InformixDuckDB, `FULL_RUN=true` → includes it; mutation "drop the win_full_run_only test in prepare" turns the FULL_RUN=false arm red — providers: n/a — proof: control
- TO-9 `${{` guard scope control: feed master's `test-matrix.yml` (which still carries `w_`'s conditional) to the branch's `prepare` Python. With `ALL_LEGS=true` it exits 1 naming `w_DB2InformixDuckDB`. With `ALL_LEGS` unset it exits 0 with master's selection, which is the stacked-PR case of P10 L-8. Mutation "make the guard unconditional" turns the second arm red — providers: n/a — proof: control
- TO-10 (A-2) netfx main suite is x64: a local `dotnet publish Tests/Linq/Tests.csproj -f net462 -c Azure -a x64` yields an exe whose header is `AMD64` without `Requires32Bit`. On CI, the netfx main-suite run summary of every non-Access windows leg names `(net462|x64)`, on both the GitHub release run and an Azure `test-all`. The leg set is g_SqlCE, s_SQLite, a, d, e, f, l, m, n and o; the netfx main suite of s, l, m and n runs only on a full run, so their check comes from the GitHub release run. mutation "drop `-a x64`" is master's state, and it was measured as `(net462|x86)` in 40129849637 and in Azure 24621 — providers: SqlCE, SQLite, SQL Server 2005–2025 (windows netfx) — proof: control
- TO-4 Azure compile, development path: an Azure `test-all` (testing.yml) run on the branch lists exactly the windows legs a d e f l m n o (8 win-mssql, no w_DuckDB) and no linux legs, the same as the last master `test-all` — providers: Azure agents (compile only) — proof: characterization
- TO-5 Azure `default` gate control: on the scratch release PR (TO-7), the PR-triggered `default` build shows its `Win`/`Lin`/`Create Test Baselines Branch` jobs as **skipped**, with Build and Nugets Generation running. The true arm is compile-only: the Azure Pipelines run-preview API (`previewRun: true`, `templateParameters: {run_tests: true}`) on the branch yields a final YAML whose test jobs carry an enabled condition and whose matrix holds 15 windows legs (w_ included) and 15 linux legs. If the session cannot authenticate to that API, record `skipped — true arm unverified` rather than queueing a live run: Azure builds cannot be cancelled from here, and a live run pushes 30 legs to `baselines/default`. Mutation "restore the release-target condition in `enabled`" makes the PR build's test jobs run — providers: Azure agents (compile only) — proof: control
- TO-6 Full GitHub run by dispatch: `gh workflow run tests.yml --ref feature/release-tests-github -f surface='[all]' -f full_run=true -f all_legs=true` (no baselines branch) starts all 30 legs. Each of the 8 win-mssql windows legs logs `<container> is ready` from `mssql-container.ps1` and writes its `.trx` files. a d e f o write netfx + net8/9/10 main and EF.Core. l m n write netfx main and EF.Core only, because their net8+ runs on the linux leg (`tests.yml:169-175`, `test-jobs.yml:147-150`). Windows w_ writes net8/9/10 (`win_tfms_always`). Per-leg main + EF.Core test counts fall within noise of the last Azure release full run (6.5.1 build 24621) — providers: every CI provider — proof: characterization
- TO-7 Trigger: a scratch PR from the branch into `release` starts a `tests-release` run automatically, listed in the PR's checks. Proof that the secrets reached the called workflow: `baselines_init`'s `ls-remote` succeeds (`ensure-baselines-branch.ps1:63-67`), and every leg's `Checkout test baselines` step passes the `GITHUB_TOKEN is not set` guard (`checkout-baselines.ps1:49-52`). A baselines push is not the proof, since `push-baselines.ps1:63-67` exits 0 with no changes. A second push to the scratch PR cancels the first run, per the E-1 concurrency group. Before the branch there is no GitHub run on such a PR — providers: every CI provider — proof: red→green
- TO-8 Rebase path: on TO-7's second push (after baselines master has advanced, or after creating a deliberately stale `baselines/pr_<scratch>` one commit behind master), `baselines_init` logs `Baselines PR was rebased on HEAD` and the legs clone the rebased head; on a non-stale branch it logs `no rebase required` — providers: n/a (baselines repo) — proof: characterization

## P9 Verification gates

One row per obligation follows. All results are dated 2026-10-24, measured on the working tree over `9516c1cb8`, which was then committed unchanged in its selector logic as `dc7935f47`. Only the comment and README wording changed after the G-09 review. The harness is `.build/.agents/release-tests-selection.ps1`, which extracts `prepare`'s Python from each `tests.yml` and runs it locally (Python 3.8.2, PyYAML 6.0.3); mutations are in `release-tests-selection-mutations.ps1`, run on scratch copies.

- G-01 TO-1: pass — branch `[all]` + `all_legs` + `full_run` selects exactly the 15 linux and 15 windows names in TO-1, exit 0. Master's script with the same env selects 15 linux and only g r s v x z windows. That is the red half: a d e f l m n o w are absent.
- G-01 TO-2: pass — all 18 surfaces at `full_run=false`: `linux` / `windows` / `any` / `windows_any` / `windows_x86` / `matched` and the exit code are identical to master. At `full_run=true` (hand dispatch, no `all_legs`) the selection is still identical. Only `matched` is +1 on `[all]`, `[db2.all]`, `[duckdb.all]` and `[informix.all]`, because Windows DuckDB is now visible but stays unselected. `matched` feeds only the "no leg matches" guard (`tests.yml` step after `select`), which is non-zero either way.
- G-01 TO-3: pass — `[duckdb.all]` + `all_legs`: `full_run=false` selects no windows legs and `full_run=true` selects `w_DB2InformixDuckDB`. mutation "drop the win_full_run_only test in prepare" → the false arm selects `w_DB2InformixDuckDB` (red).
- G-01 TO-9: pass — the branch script on master's matrix: `all_legs` exits 1, and without `all_legs` it exits 0 with `linux` / `windows` / `matched` identical to master. mutation "make the guard unconditional" → the no-`all_legs` arm exits 1 (red).
- G-01 TO-10: pass.
  - Local: on 2026-10-25, `dotnet publish Tests/Linq/Tests.csproj -f net462 -c Azure -a x64` exited 0. `linq2db.Tests.exe` has header `Amd64, ILOnly, StrongNameSigned` with no `Requires32Bit`, and the root `e_sqlite3.dll` and `SqlServerSpatial170.dll` are `Amd64` (`.build/.agents/release-tests-corflags.ps1`). The red half is master's state: a Debug net462 MTP exe reads `I386, Requires32Bit`, and the CI summaries in 40129849637 and 24621 show `(net462|x86)`.
  - CI, GitHub: release run [40146065334](https://github.com/linq2db/linq2db/actions/runs/40146065334) on `bd7455b77`. The netfx main-suite summary of all 10 non-Access windows legs (g s a d e f l m n o) reads `net462\main\x64\linq2db.Tests.exe (net462|x64)`, all `Passed!`. That includes l, m and n, which lost their netfx run to the x86 `OutOfMemoryException` in 40129849637. The 4 Access legs stay `(net462|x86)`.
  - CI, Azure: `test-sqlserver` [24695](https://dev.azure.com/linq2db/0dcc414b-ea54-451e-a54f-d63f05367c4b/_build/results?buildId=24695) on `bd7455b77` succeeded. Its netfx main runs on a d e f o read `(net462|x64)`, all `Passed!`. On a non-full run l m n skip their netfx main, and g s are not Azure legs in development, so the GitHub run covers those.
- G-01 TO-4: pass — Azure `test-all` [24648](https://dev.azure.com/linq2db/0dcc414b-ea54-451e-a54f-d63f05367c4b/_build/results?buildId=24648) on #6128 (`dc7935f47`) compiled a bare `Lin` job and the windows legs `a d e f l m n o`, with no `w_DB2InformixDuckDB`. That is the same job set as the previous completed `test-all` 24634.
- G-01 TO-5: PR arm pass. The true arm is skipped, so the `run_tests: true` compile is unverified.
  - PR arm: Azure `default` [24644](https://dev.azure.com/linq2db/0dcc414b-ea54-451e-a54f-d63f05367c4b/_build/results?buildId=24644) on the scratch release PR #6129 ran only `Build` and `Nugets Generation`. The test jobs were absent from the timeline rather than shown as skipped, `Build (win-x86)` included, because `with_tests` is false.
  - True arm: `POST _apis/pipelines/3/preview` returned an empty body to this unauthenticated session.
  - mutation "restore the release-target condition in `enabled`": its effect is master's behaviour, already on record — the 6.5.1 release PR's `default` build 24621 ran the provider legs (`release-publish/SKILL.md:204`). No separate mutant run.
- G-01 TO-6: pass, 30 of 30 legs after one job re-run. Measured on the PR-triggered release run [40146065334](https://github.com/linq2db/linq2db/actions/runs/40146065334) instead of a hand dispatch, because it passes the same inputs (E-1).
  - Legs: all 15 linux and 15 windows legs ran, along with `Select legs`, both builds and `baselines_init`. The GitHub-side expressions held.
  - SQL Server containers: each of the 8 win-mssql legs logs `is ready`, once per container (twice on l and m).
  - Suites: a d e f o wrote netfx and net8/9/10 main plus EF.Core; l m n wrote netfx main plus EF.Core only; Windows w_ wrote net8/9/10.
  - Failure: `Lin j_Oracle1819` failed before any test ran. Database creation inside the Oracle 19c container died with `[INS-08101] Unexpected error … at state: 'NetworkConfig'`, so `report-trx` found no `TestResults`. The same leg on the same image passed in 40129849637, and `bd7455b77` touches only the windows netfx publish. Re-running only that job (attempt 2, job 121171016859) passed, with net8/9/10 main totals 21723 / 21767 / 21803 and EF.Core 7, equal to 24621. That made the run `success`.
  - Counts against Azure 24621 (`.build/.agents/release-tests-counts.ps1`):
    - Linux main and EF.Core totals are equal per leg, except ClickHouse at −3 (28947 vs 28950), from the master merge.
    - Windows net8/9/10 main and EF.Core totals are equal per leg. netfx main is equal per leg except m (−2) and s (−1), the two legs 24621 failed, which #6126 fixed.
    - netfx EF.Core is equal on every leg 24621 reached.
  - Wall clock: 4 h 46 min (00:16 → 05:02), against ~18 h for 6.5.0's Azure release run. The run queued under the 20-job cap (L-1).
- G-01 TO-7: pass — the scratch PR [#6129](https://github.com/linq2db/linq2db/pull/6129) into `release` started `tests-release` runs 40112928250, 40129849637 and 40146065334 with event `pull_request`, with no comment and no dispatch, and they are listed in the PR's checks.
  - Secrets reached the called workflow: `baselines_init`'s `ls-remote` succeeded in every run, and every leg passed `Checkout test baselines`.
  - Cancel on push: 40112928250 was cancelled about 90 s after the `d81ebc467` push started 40129849637, and 40129849637 was cancelled when `bd7455b77` started 40146065334 (D-6).
  - Red half: on `origin/master` the only `pull_request` workflow is `build.yml`, which runs no provider tests, so before the branch such a PR got no GitHub test run.
- G-01 TO-8: pass — in 40129849637, `baselines_init` logged `Baselines branch is 'diverged' relative to master`, rebased onto master and force-pushed. In 40146065334 it logged `Baselines branch is 'ahead' relative to master` / `no rebase required`.
- G-06: pass — `git diff` touches only E-1..E-7: 6 tracked files, 131+/48-, plus the new `tests-release.yml`; no unrelated reformatting.
- G-07: pass — no `Tests/Tests.Playground/` change.
- G-09: pass — 2026-10-24, a read-only `fable` review of the uncommitted diff found no high-severity defect. Disposition of its findings:
  - 1, medium, unverified: the win-mssql setup step has never run on GitHub. Covered by the TO-6 dispatch.
  - 2: wrong rationale. Fixed by A-1 and the comment rewording.
  - 3: the fallback's baselines branch was undocumented. Fixed in the README.
  - 4 and 5: P10 L-10.
  - 6: wording. Fixed in the README and the `tests-release.yml` header.
  - Corpus follow-ups: already in P7 as `deferred:`.

## P10 Adjudicated (M/L)

- L-1 GitHub Free caps the org at 20 concurrent jobs (U-5), so ~30 legs plus the build jobs queue. Accepted: even queued, 4-vCPU runners beat Azure's 10 slots of 2-vCPU agents. TO-6 measures the wall clock.
- L-2 There is no GitHub twin of Azure's Windows idle-process kill (`test-workflow-windows.yml:93-132`). Accepted: GitHub windows runners carry 16 GB against Azure's 7 GB, and the x86 Access legs, which are the memory-bound ones, already run green on GitHub (`plans/feature-migrate-ci-to-github-actions/plan.md:41`).
- L-3 Re-running `prepare` / `build` / `baselines_init` after the release PR merges fails, because `refs/pull/<n>/merge` is gone. Accepted: the legs re-run from artifacts, and the corpus recovery (throwaway PR into `release`) still triggers E-1.
- L-4 A `/azp run test-*` comment on the release PR now races. Azure's `create_baselines_branch` may force-push `baselines/pr_<release>` while GitHub release legs are pushing. Accepted: nobody needs a comment run on the release PR. The `release-publish` follow-up says not to post one.
- L-5 Corpus docs and scripts that describe the release run as Azure `default` (P7 rows marked `deferred:`) are updated after the linq2db PR merges, per the user's standing rule.
- L-7 (D-5) The Azure fallback is a manual queue of `default` on **`master`, never `release`**. Queued on `release`, it would also fire `Create Release Draft` (`build-job.yml:299`) and `Publish to Nuget.org` (`nuget-job.yml:52`). Its baselines land on `baselines/default` (`ensure-baselines-branch.ps1:48-52`), and the release then merges that branch by hand in place of `baselines/pr_<release-pr>`. Accepted over a `pr_id` queue parameter threaded through `test-matrix.yml` → `test-jobs.yml:72,116,181`, because the fallback exists for a GitHub outage, which is rare. The `release-publish` follow-up documents the procedure.
- L-8 (D-4) A comment run with `all_legs` unset, on a stacked PR whose merge ref predates this change, still reads `w_`'s old conditional and drops the Windows DuckDB leg silently, as it does today. Only `all_legs` runs refuse a `${{` key.
- L-9 (A-1) A `baselines/pr_<release-pr>` created before `release-publish` step 3 resets baselines master keeps the pre-reset history, and the rebase cannot fix it because the branch compares `ahead`. This is pre-existing: Azure ran the same script. Deferred to the `release-publish` follow-up, which should close or delete that branch in step 3, or reset before opening the release PR.
- L-10 Two accepted edge cases from the pre-PR review (findings 4 and 5):
  - A hand dispatch with `rebase_baselines` and a `pr` that doesn't match `baselines_branch` rebases a different branch than the one the legs push to. Both callers pass matching values.
  - A fork PR into `release` gets a green `tests (release)` with no legs run. Nothing requires that check, and release PRs come from `master`.
- L-6 `ensure-baselines-branch.ps1` has no empty-token guard (unlike `checkout-baselines.ps1:49-52`). Accepted: E-1's fork gate means the job runs only where the PAT exists, and a missing PAT fails loudly at `ls-remote` anyway.

## P11 Amendments (M/L)

- A-1 (2026-10-24, pre-PR diff review on `fable`, finding 2) — D-3's second `rejected:` reason was wrong.
  - `release-publish` resets baselines master back to the anchor, an ancestor of every `baselines/pr_*` branch. After the reset the branch compares `ahead`, and `ensure-baselines-branch.ps1:90-97` does not rebase it, so the rebase never covers the reset case.
  - What the rebase does cover is baselines master moving forward between two runs of the release PR, which is exactly Azure's `create_baselines_branch` behaviour. D-3's choice stands on that parity.
  - The `tests-release.yml` comment was reworded to match. The pre-reset-history gap is pre-existing on Azure too and is recorded as P10 L-9.
  - No edit-point added; the approval stands.
  re-derives: P5 (D-3 rationale), P10 (L-9, L-10), P9 (G-09)
- A-2 (2026-10-25, user-directed, added to this PR) — the main net462 suite on the non-Access windows legs is published `-a x64` on both CIs.
  - **What failed:** release run 40129849637 (sync merge `d81ebc467`) lost `Win l_SqlServer2017_2019`, `Win m_SqlServer2022_2025` and `Win n_SqlServer2019Extras` to the NUnit result-serialization `OutOfMemoryException`. All three are the netfx main suite, which runs only on full runs.
  - **Measured cause:** each leg's run summary names `net462\main\x64\linq2db.Tests.exe (net462|x86)`, and Azure 24621 logged the same.
    - A locally built net462 MTP test exe (`Tests.Playground`, Debug) has header `Machine: I386, CorFlags: ILOnly, Requires32Bit` (`.build/.agents/release-tests-corflags.ps1`).
    - The SDK defaults a .NET Framework exe published with no RID to win-x86. The publish comment "net462 is AnyCPU and runs as x64" was true only of the EF3 suite, which already passed `-a x64`.
  - **Fix:** `-a x64` on the main net462 publish in `build-job.yml` (E-8) and in `tests.yml` "Publish and stage netfx" (under E-2).
  - **Not affected:** Access keeps its own `-a x86` artifacts from `build_x86` / `build_x86_job`.
  - **x64 natives the suite needs:**
    - SqlCE: the installer is `SSCERuntime_x64-ENU.msi` (`sqlce.ps1:2`).
    - SQL Server Types: both `x86\` and `x64\` `SqlServerSpatial170.dll` (`linq2db.Providers.props:87-95`).
    - SQLite: an x64 `e_sqlite3` comes with the RID, as for EF3.
    - IBM: the x64 DB2/Informix references are chosen when `PlatformTarget != 'x86'` (`linq2db.Providers.props:28-33,70-75`). DB2/Informix do not run on windows legs.
  - **Coverage change:** the netfx main suite of g_SqlCE, s_SQLite and the 8 SQL Server windows legs moves from x86 to x64. That is a user-visible CI delta.
  - Approval for E-8 was given by the user this turn ("b"). No critic round: Tier M, and the change is one RID flag on a publish step whose x86 twin already works.
  re-derives: P6 (E-2, E-8), P8 (TO-10), P3 (user-visible deltas)

## P12 Critic verdict (M/L)

**Round 1 — `weak`** (`fable`, on the plan as first authored, branch at `9516c1cb8`).

**Objections:**

- **A. TO-6 could not pass for l m n.** Their windows half is netfx-only (`tests.yml:169-175`).
- **B. `lead:` called-workflow `concurrency`.** Whether it governs the caller's run is unmeasured, and D-6 rested on it.
- **C. TO-5's true arm said "cancel after compile".** Azure builds cannot be cancelled from this session, and a live run pushes 30 legs to `baselines/default`.
- **D. D-5's fallback doesn't produce `baselines/pr_<N>`.** SC-4 overclaimed, and nothing said which branch to queue the fallback on (`release` would also fire the release draft and the nuget.org push).
- **E. An unconditional `${{` guard breaks stacked PRs.** It would fail comment runs on stacked PRs whose merge ref predates the change.
- **F. Merge ordering against the open release PR #6114 was unstated.** That ordering is what keeps a quick-green Azure `default` from being read as a finished release run.
- **G. TO-7's PAT proof could be vacuous.** A push with no changes exits 0.
- **H. Precision.** Jobs disabled by condition show as *skipped*. `baselines_init` downloads `test_scripts` rather than checking out. The `linux-tests` `if:` needs explicit prepare/build result clauses once `baselines_init` joins `needs`.

**What the critic searched:**

- the includers and readers of `full_run`, `enable_os_windows` and `win_tfms_always` across `Build/`;
- every parser of `test-matrix.yml` repo-wide;
- Azure-specific env in `Build/Azure/scripts/*.cmd`;
- `nuget-job.yml` and `build-job.yml:114,178-230,326`, which confirmed D-5's splice;
- `baselines-base.ps1`, where the release PR resolves to master;
- the 15+15 entry count, which confirmed SC-2 / TO-1;
- the `prepare` TFM derivation against `test-jobs.yml:143-150`;
- `.claude/scripts` for workflow-id hardcodes.

**Changed in response (folded in before presentation; no `A-n` because the plan is not yet approved):**

| Objection | Change |
|---|---|
| A | TO-6 restated per leg |
| B | E-1 gets its own `concurrency: tests-release-<pr>`, and D-6 is rewritten |
| C | TO-5's true arm becomes compile-only through the run-preview API, else `skipped` |
| D | SC-4 is narrowed; P10 L-7 adds "queue on `master`, never `release`, then merge `baselines/default` by hand"; a `pr_id` parameter is rejected there with its reason |
| E | D-4 guard scoped to `all_legs`; P10 L-8; new TO-9 control |
| F | P3 merge-ordering constraint |
| G | TO-7 now pinned on `ls-remote` and the `checkout-baselines.ps1:49-52` guard |
| H | TO-5 says "skipped", U-8 is corrected, and E-2 spells out the new `if:` |

All eight objections are answered by these changes. The design itself (D-1..D-5) is unchanged. No round-2 delta was run: the fold-ins narrow claims and add one concurrency block, and they introduce no new mechanism.
