# Running tests on CI (Azure Pipelines)

linq2db's CI is Azure Pipelines, triggered from a PR via `/azp` comments posted on the PR itself. A CI run gives you two things a local run can't:

1. **Coverage across providers / platforms the developer doesn't have locally** — the CI matrix includes DB2, Informix, SAP HANA, SAP ASE, and other heavy providers most contributors can't stand up.
2. **Baselines regeneration in the remote `linq2db.baselines` repo** — successful CI runs commit regenerated baselines back to the upstream baselines repo, so later PRs diff against an up-to-date "before" state. A good reason to run CI even when the local run already passed.

## Commands

Posted as a plain comment on the PR (not a review comment):

| Comment | Effect |
|---|---|
| `/azp list` | Lists every pipeline registered on the repo (workflow names, status). Use first if you don't remember the exact `test-<name>` you want. |
| `/azp run test-all` | Runs the full provider matrix. Usually the right call after a PR first opens. |
| `/azp run test-<dbname>` | Runs a single-provider pipeline (e.g. `test-sqlite`, `test-sqlserver`, `test-firebird`). `/azp list` has the canonical names. |

The canonical `test-<name>` pipeline names are also enumerated in [`Build/Azure/pipelines/testing.yml`](../../Build/Azure/pipelines/testing.yml) — its `Build.DefinitionName` switch maps each to a `db_filter` (`test-access`, `test-db2`, `test-firebird`, `test-informix`, `test-mysql`, `test-oracle`, `test-postgresql`, `test-saphana`, `test-sqlce`, `test-sqlite`, `test-sqlserver`, `test-sqlserver-2019`, `test-sqlserver-2022`, `test-sybase`, `test-clickhouse`, `test-duckdb`, `test-ydb`, `test-metrics`). Read it to resolve a provider's pipeline name without spending a `/azp list` round-trip.

**Every one of these needs a PR to hang the trigger on — a bare branch push runs nothing.** `testing.yml` and `build.yml` are `trigger: none` with `pr: branches: include: ['*']`, and `default.yml` triggers only on `master` / `release`. So pushing a branch — a throwaway instrumentation probe, a bisect candidate, an experiment — produces no build at all, and `/azp run` is a *PR comment*, so there is nowhere to post it. Open a draft PR for the branch (confirm title/body per `AGENTS.md` → *Pull requests*), trigger the narrowest pipeline that covers the question, and close the PR plus its CI-created `linq2db.baselines` tracking PR when done. Reach for a single-provider pipeline here rather than `test-all`: it is the difference between one leg and the whole matrix. (Surfaced on #5737, where a `VisitConditional` probe had to run on the Linux SQLite leg — `test-sqlite` took ~35 minutes against `test-all`'s hour-plus.)

**Reading a job log through `gh api` needs `--allow-escape-sequences`.** The Azure log endpoints return terminal colour codes, and without the flag `gh` refuses the whole response with *"the response contains terminal escape sequences"* — an empty output file and an exit 1 that reads like an auth or URL error. `gh api "https://dev.azure.com/linq2db/linq2db/_apis/build/builds/<id>/logs/<logId>?api-version=7.0" --allow-escape-sequences`, then `Grep` the file.

**`testing.yml` lists *intended* pipeline names; it does not prove a pipeline is *registered*.** A `Build.DefinitionName` arm in that file only says "if a definition with this name runs me, do X" — the Azure DevOps definition itself is created out-of-repo. To check which definitions actually exist, read the **public** REST API (no write access, no `/azp list` PR comment, no round-trip through a maintainer):

```
Invoke-RestMethod -Uri "https://dev.azure.com/linq2db/linq2db/_apis/build/definitions?api-version=7.0"
```

`.value[].name` / `.value[].id` is the registered set. **Never conclude "pipeline `<name>` isn't registered" from repo contents alone** — that claim is one cheap read away from being settled, and getting it wrong produces a confidently-wrong review finding. (Surfaced on PR #5678: a review pass asserted the newly-documented `/azp run test-cli` had no matching definition and would not resolve; the API showed `test-cli` registered as id 29, so the observation was dropped as false.)

Posting the comment requires write access to the repo; for contributors without write access, a maintainer posts on their behalf.

## Which pipeline runs when

`Build/Azure/pipelines/*.yml` are the pipeline definitions; `templates/*.yml` are the job bodies they include. The trigger topology matters whenever you reason about "does CI actually cover this?":

| Pipeline | Trigger | Jobs it includes | Packs nugets? |
|---|---|---|---|
| `build.yml` | `pr:` every branch (`'*'`) — auto-runs on **every PR**; `trigger: none`, so no branch pushes | `build-job.yml` only | Yes (`with_nugets: true`) |
| `default.yml` | pushes to `master` / `release`, plus PRs targeting `release` | `build-job.yml` + `nuget-job.yml` + `test-matrix.yml` | Yes |
| `testing.yml` | `/azp run test-<name>` comment only | `build-job.yml` + the provider matrix | No |

Consequences worth remembering:

- **A `master`-targeting PR runs `build.yml` and nothing else** until an `/azp run …` comment adds a run. `gh pr checks` on such a PR reports `default` as *skipping* — that's the configured behaviour, not a misconfiguration to investigate.
- **`nuget-job.yml` never runs on a `master`-targeting PR.** Any gate placed there (nupkg size limits, package-content verification) is pre-publish only. To cover PRs too, the step has to also live in `build-job.yml` — which is exactly where a pre-merge regression gate belongs. The review-side rule for this is `code-reviewer.md` rubric rule 16 (*CI-check reachability*).
- **Pack output is `.build/package/release`.** `build-job.yml` packs there and publishes it as the `$(artifact_nugets)` pipeline artifact; `nuget-job.yml` downloads that artifact into `.build/nugets` and works from the copy. A script that scans for produced packages needs whichever of the two paths matches the job it runs in.

## When to propose a CI run

- **After `gh pr create` (new PR)** — propose once, default to `/azp run test-all`. Skip if the PR is draft and the user has said they want more local iteration before inviting CI attention.
- **After pushing new commits that move SQL emission on an active PR** — the prior CI baselines are stale; offer a follow-up run (`/azp run test-<affected-provider>` is usually enough). **Note that baseline updates land incrementally per provider config** — a recent commit on `baselines/pr_<n>` doesn't mean every file is current. To check whether a specific baseline file reflects the latest fix, `git -C ../linq2db.baselines log -1 --format='%H %ai %s' -- <path-to-baseline>`; if the timestamp predates the fix push, that file is stale and the corresponding CI provider job hasn't run yet.
- **When the user asks "does this pass on X?"** for a provider that isn't set up locally — propose `/azp run test-<X>` instead of spinning the provider up.

One `/azp run` per meaningful change. Do not spam — each run consumes CI capacity.

**Sync the branch with `origin/master` before running tests or triggering CI.** A PR must be in sync with master to be merged, so results from a stale branch don't reflect the state that will actually be validated. `git fetch origin master`, then merge or rebase per the branch policy in [`agent-rules.md`](agent-rules.md) → *Creating a new branch* (merge on long-lived / already-merged branches, rebase on short linear ones), **then** run.

### Scoped pipeline vs `test-all` — the mechanical rule

Match the pipeline to the change's blast radius, but note the genuinely scoped case is narrower than it looks: it is a change whose blast radius maps to **one database** — a provider's SQL builder, dialect, or schema provider. Everything else is `test-all`.

**Any change under `Tests/` gets `test-all`, unless the edited file is a provider-specific test whose fixture only runs for that one database.** This is deliberately mechanical, because the judgment-call version of it was overridden four times:

| Change | Recommended | Actual answer |
|---|---|---|
| `Source/LinqToDB.EntityFrameworkCore/` cache key (#5780) | `test-sqlite` + `test-sqlserver` | *"all"* |
| `Source/LinqToDB.FSharp` + one core comment (#5701) | scoped | *"run test-all"* |
| `Tests/Base/` lane classification + guard (#5614) | — | `test-all` asked for directly |
| One `[NonParallelizable]` attribute on `Tests/Linq/Common/DefaultValueTests.cs` (#5614) | `test-mysql` (CI caught it there) | *"trigger all tests, not mysql only"* |

The mechanism behind all four: a test surface living inside the main `Tests.Linq` assembly — the EF fixtures, `FSharpTests`, anything in `Tests/Base/` — **runs in every provider leg by construction**. So "the failure only showed up on MySQL" is evidence of one interleaving, not of scope. Offer the scoped option once with the reasoning, then take the answer without re-arguing it; the pipeline choice is the maintainer's.

**The mirror trap when reading a red build: a leg's name is where a test ran, not what it depends on.** The paragraph above says a `Tests.Linq` surface runs in every provider leg — true for the common `[DataSources]` case, and it makes a failure confined to two named legs read as *provider-specific*. But a fixture gated to a **data source** rather than a provider family runs only where that source is configured, so its failures land on exactly those legs and nowhere else. Read the failing test's attribute before attributing the failure to the databases in the job names. (2026-09-05, #5833: `test-all` came back red on `Lin s_SQLite` and `Lin l_SqlServer2017_2019` only, which was reported as "the SQLite failure". All four failing cases were one `[NorthwindDataContext]` test — `Northwind.SQLite`, `Northwind.SQLite.MS`, `SqlServer.Northwind`, `SqlServer.Northwind.MS` — i.e. every Northwind configuration there is, and the cause was a provider-agnostic expression-builder bug. The two legs are simply the two places Northwind exists.)

### An unreleased provider version's own enablement PR is expected to be red

When a **new provider version's** enablement PR has failing CI for that unreleased version, treat the red job as work-in-progress: don't fix it and don't mass-`[ActiveIssue]`-gate its tests. Maintainer: *"there is no sense to fix something that is not released yet."* Gating dozens of tests is a large diff that buries real signal, and fixing a hard provider limitation burns cycles on work that can wait for the release.

Fix only regressions on **released** versions — those have users. On #5485 the released Firebird 2.5/3/4/5 regression was fixed while Firebird 6's ~130 failures were neither fixed nor gated. This scopes out the *keep digging to the root, gating is a fallback* rule in [`AGENTS.md`](../AGENTS.md), which governs released code.

### CI connection strings come from the tracked `DataProviders.json`

The Azure pipelines resolve connection strings from the **tracked `DataProviders.json`** at repo root — never from the gitignored `UserDataProviders.json` or its `.template`, which are local-dev only. Wiring a new provider version into CI therefore needs **three** additions to `DataProviders.json`, alongside the `Build/Azure/**` config: `CommonConnectionStrings.Connections` (local-style port, e.g. `5419`), `AzureConnectionStrings.Connections` (port **5432** — the CI container maps the provider there), and the bare provider-name list further down. Those lines are column-aligned: clone the latest sibling version's line and change only the version and port, keeping the width equal.

Updating only `UserDataProviders.json.template` plus the `Build/Azure/**/pgsqlNN.json` lists is the failure mode — `test-postgresql` could not find the `PostgreSQL.19` connection string because `DataProviders.json` had no entry.

### Validate pipeline YAML before pushing

Run every changed `Build/Azure/pipelines/**` file through a parser before pushing (`python -c "import yaml; yaml.safe_load(open(f))"`). Two traps make this worth the step:

- **A line-deletion edit can merge adjacent lines.** Removing a line by matching `"\n<line>"` → `""` can consume the trailing newline too, collapsing the next line onto the previous one (`x86: true          ${{ if ... }}:`). Match the line *with* surrounding context so the following line keeps its leading newline, and re-grep for merge signatures (`}}            `, `true          ${{`) after any bulk removal.
- **The failure surfaces as a YAML-compile error, not a test failure.** A bad template fails at pipeline initialization, so `azp-build-failures.ps1` reports `failedTaskCount: 0` **and an empty timeline**. The real message is in the build's `validationResults`: `Invoke-RestMethod ".../build/builds/<id>?api-version=7.0"` → `.validationResults` (e.g. *"Mapping values are not allowed in this context"* with file:line:col).

## Posting the comment

`/azp` trigger lines start with `/`, which Git Bash silently path-mangles when passed via `gh … --body "/…"` — the comment posts successfully with a `C:/Program Files/Git/azp …` body and no error from `gh`. See [`agent-rules.md`](agent-rules.md) → **Windows Git Bash gotchas** for the full gotcha. Use `--body-file -` with a stdin heredoc so the leading slash survives:

```
gh pr comment <N> --repo linq2db/linq2db --body-file - <<'BODY'
/azp run test-all
BODY
```

Keep the body to the `/azp …` line alone — Azure Pipelines only parses that line, and extra text can suppress the trigger. After posting, verify with `gh api repos/linq2db/linq2db/issues/comments/<id> --jq '.body'` — the mangling is invisible from `gh pr comment`'s stdout, so the verify is the only way to catch it.

Posting is publicly visible and incurs CI cost, so follow the standard confirmation rules in [`agent-rules.md`](agent-rules.md): propose the comment, wait for explicit user approval, then post. For new PRs, the approval can come bundled with the `gh pr create` approval — e.g. "create the PR and run test-all".

## Reading failed CI test runs

**Find *which* pipeline failed with `gh pr checks <n>`, not `gh api commits/<headSha>/check-runs`.** The auto-triggered `build` pipeline (and any pipeline Azure runs against the PR *merge* commit) attaches its check to that merge SHA — a different commit than the PR head — so `gh api repos/linq2db/linq2db/commits/<headSha>/check-runs` can silently omit it. Seen on #5703: the head's `check-runs` listed only `test-all` (all green) while `gh pr checks 5703` showed `build	fail` (buildId 22173, sourceVersion = the Azure merge commit). Treat `gh pr checks <n>` as the authoritative "is CI failing?" list; use the `check-runs` API only to resolve a *specific* named check's `buildId`.

When a CI build fails, the per-task error messages aren't in the GitHub check-runs annotations — they're inside the Azure DevOps build logs. The `dev.azure.com/linq2db` build API is publicly readable (no auth), but the hand-flow is fiddly: hit `/timeline?api-version=7.0` for the JSON list of failed `Task` records, then `/logs/<id>` for each one's raw log, then regex for `Failed <TestName>... Error Message:` blocks.

Use [`.claude/scripts/azp-build-failures.ps1`](../scripts/azp-build-failures.ps1) instead — it does the timeline + parallel log fetch + per-failure parse in one call:

```
pwsh -NoProfile -File .claude/scripts/azp-build-failures.ps1 -BuildId <n>
```

Output: JSON with `{ buildId, logsDir, failedTaskCount, tasks: [{ name, logUrl, logPath, failures: [{ test, errorMessage }] }] }`. Logs persist under `.build/.agents/azp-<n>/` for follow-up `Read` / `Grep`. **On a `test-all` build, launch it in the background.** That definition's timeline carries ~200 records and the script fetches a log per failed task, which overruns the 600 s tool timeout and gets moved to the background anyway (measured on build 22792, 19 failed tasks). Start it with `run_in_background` and wait for the completion notification — don't poll the output file, per [`agent-rules.md`](agent-rules.md) → *After launching a background task*. A single-provider definition is small enough to run inline. **Prefer the script's parsed `failures[]` over hand-grepping those raw logs** — a bare `TestName("Provider…")` grep also matches the log's diagnostic / progress lines (lane diagnostics, timing, retry echoes), inflating the failing set (once turned PG failures on 9.2–10 into a false "all 9.2–12 fail"). If you must grep the raw log, anchor on the runner's `failed` marker (`failed.*TestName`) and dedupe. When the build is red for a **non-test** reason (compile error in a `Build …` step, restore failure, or a `Command line` step wrapping `dotnet build`/`publish`), `failedTaskCount` is `0` and a `buildFailures: [{ name, issues, logPath, errors }]` array carries the failure — don't read `failedTaskCount: 0` as "nothing failed". Note the timeline `issues` are often only a generic wrapper (`Cmd.exe exited with code '1'`) for `Command line` steps; the real `CSxxxx`/`MAxxxx`/`MSBxxxx` message is in the fetched task log (`logPath`) and parsed into `errors[]`, so read those, not just `issues`. One recurring non-test red is the **`Publish to Azure Artifacts feed`** step failing with HTTP **402 (Payment Required — artifact quota / billing)**: it's pure infra, unrelated to the code, and shows up in `buildFailures[]` — don't read a build that's red *only* for this as broken tests (it bit a green master build at build 21987).

**On a leg that retries, `reportedFailedTotal` and `failures[]` sum across attempts.** A test that failed once and passed on retry appears in `failures[]` indistinguishable from a hard failure, and the total counts it once per attempt — build 22978's Oracle leg reported `reportedFailedTotal: 49, truncated: true` for a real persistent set of **4**. The tell is more than one `Test run summary:` block in the same log, plus a `Retry summary: Failed! after N/N attempts` line. Dedupe `failures[].test` first, then confirm each survivor against the **last** attempt's summary before reporting a count. This is the one case where the paragraph above ("prefer the script's parsed `failures[]` over hand-grepping") does not hold on its own — the parse is faithful to the log, but the log contains every attempt.

To read a **specific step's log by name** — including a *succeeded* diagnostic step whose value is its stdout (a CI probe printing a summary block, a setup step's timing), which `azp-build-failures.ps1` never surfaces — use [`.claude/scripts/azp-step-log.ps1`](../scripts/azp-step-log.ps1) rather than hand-running the `curl …/timeline | python`-to-find-the-log-id-then-`curl …/logs/<id>` dance:

```
pwsh -NoProfile -File .claude/scripts/azp-step-log.ps1 -BuildId <n> -StepName '<name-substring>'
```

Output: JSON `{ buildId, stepName, logsDir, steps: [{ name, state, result, logPath }] }`; `-StepName` is a case-insensitive substring (matches all Task records containing it). A matched-but-pending step reports `logPath: null` (no log until it starts) rather than failing. `Read` / `Grep` the persisted `logPath`.

**Azure log ids are per *build* — never carry one across builds.** `/logs/1202` is a different step in every build, and fetching it against the wrong build returns *another job's* log with no error: same shape, plausible numbers, wrong provider. Resolve the log from that build's own `/timeline` every time — which is what `azp-step-log.ps1 -StepName` and `azp-job-durations.ps1 -WithTestCounts` both do. The symptom to watch for is an internal contradiction: a "test duration" that exceeds or undershoots the step's own wall time. (Surfaced while comparing DB2 timings across builds 22710 and 22726: log id 1202 was the DB2 step in 22726 but a different provider's in 22710, yielding `9871 tests / 4m 04s` for a step whose timeline duration was 7.21 min. The wrong figure was one step away from a public PR comment.)

**Per-job test counts: parse the step log, not the test-runs API.** `_apis/test/runs?buildUri=vstfs:///Build/Build/<id>` returns a single aggregate record with no usable per-job breakdown — don't re-attempt it. The runner's own summary block at the end of each test step's log carries `total:` / `skipped:` / `duration:`, and those lines are ANSI-colorized, so strip escape sequences before matching. `azp-job-durations.ps1 -WithTestCounts` does this.

Anonymously that endpoint does not fail either — it answers with an **HTML sign-in page**, which parses as a plausible empty result (`count: 1`, from the string's length; `value` empty). So the reading is "this build has no test runs" rather than "you are not authenticated", and the next instinct is to doubt the build instead of the call.

**"Did test X run?" is answered by the same step log, by absence.** Only skipped and failed tests are printed by name; a passing test appears nowhere, so grepping for its name proves nothing on its own. The proof is the summary block showing a full suite — `total: 26975, failed: 0` for build 23338's ClickHouse leg — plus X missing from the `skipped` / `failed` lines, plus the leg's main step filtering on nothing but `TestCategory != SkipCI` (`test-matrix.yml` gives a leg providers, never fixtures). **A baselines commit is not evidence here in either direction**: a leg commits only what differs from its clone's base, so a test that ran and reproduced the base content leaves no trace — see [`baselines-repo-layout.md`](baselines-repo-layout.md). (Surfaced on #5725, where four ClickHouse baselines looked stale-or-never-run and only the step log separated the two.)

### A job that "hung" with no test failures — read the abandonment marker first

A failed task whose `reportedFailedTotal` is `0`, on a job that ran far past its usual duration, is usually
**not** a hang in whatever step it stopped on. Check the head of that step's log for:

```
##[section]This job was abandoned. We have detected that logs from the agent may have not finished
uploading. We have included our in-memory record of all log lines uploaded before we lost contact with
the agent:
```

That is **agent loss**, not a task hang: the log you're reading is a partial in-memory record, the step
that appears "stuck" is simply the one in flight when the agent died, and every later task shows
`abandoned`. Diagnose what killed the agent, not the step. On #5614 this presented as 14 Windows jobs all
"hanging" on `Extract test scripts` (a `DownloadPipelineArtifact` task) — the actual cause was a
memory-freeing step killing `WindowsTerminal`, which is what the hosted image runs the pipeline agent
inside, so the kill took the agent's own process tree with it.

Per-task results tell you how far a job got — `/timeline` filtered to the job's children gives each task's
`result` (`succeeded` / `failed` / `abandoned`) and duration, which separates "the first two TFM steps
passed normally, the third sat for 316 minutes" from "the job was slow throughout".

To attribute an agent death to one action in a multi-step script, announce each action *before* performing
it, flush, and pause either side: the last line the agent uploads names the culprit with one-action
resolution, in a single run. Use the cheapest job that exercises the path (see *When to propose a CI run*),
and remember a leg may be gated — the Windows DuckDB leg is `full_run`-only, so a scoped `test-duckdb` run
spawns no Windows job at all until that gate is temporarily lifted.

**Before concluding anything from a `[slow]` line's `|x86` / `|x64` tag, read
[`testing.md`](testing.md) → *The runner's `[slow]` line reports assembly arch, not process arch*.** That tag
is the assembly's PE machine type, not the process architecture, and it has now produced a wrong
bitness-based analysis on #5614 twice. The step's own invocation (`net462\main\x64\linq2db.Tests.exe …`) is
authoritative.

### Did a change make CI faster or slower?

To evaluate a performance claim — a PR asserting a speedup, or a suspicion that something regressed — compare the same job/task across recent builds with [`.claude/scripts/azp-job-durations.ps1`](../scripts/azp-job-durations.ps1) rather than hand-rolling `/definitions` → `/builds` → `/timeline` → `/logs`. Add `-WithTestCounts` whenever the claim is about *speed*, because duration alone can't be read without the count beside it:

```
pwsh -NoProfile -File .claude/scripts/azp-job-durations.ps1 -Definition test-all -JobFilter 'Tests (.NET 10): DB2 LUW' -WithTestCounts
```

Reading the result:

- **Pair builds with matching test counts.** The suite's size drifts between runs, so a duration delta across different counts proves nothing. Filter to a `JobFilter` that resolves to the narrow **Task** record, not the enclosing Job — the Job includes agent acquisition and container setup.
- **Establish the pre-change band before judging a single post-change run.** Variance on this matrix runs ±0.5 min on a 7-minute step; one faster run is not a speedup.
- **`test-all` runs only on `/azp run test-all`**, so the series is sparse and interleaved across different PRs' merge commits — check `branch` / `sha` before treating two builds as comparable.
- Dropping `-WithTestCounts` and widening `-JobFilter` to `Tests:` answers "which legs are actually slow?" — worth doing before accepting any claim about a provider's relative cost. (On #5754 that ranked the DB2 leg 35th of 54 jobs, against a PR body calling it "by far the slowest provider".)

#### When the claim is about *ordering*, not duration — `-Offsets`

A CI-shape PR mostly claims things a duration column cannot express: *"the long legs were starting last and finishing alone"*, *"job A finishes before job B, so its dependents are not delayed"*, *"leg X started N minutes in and became the tail on its own"*. Those are **start offsets within one build**. Pass `-BuildId <n>[,<n>]` with `-Offsets` and a broad `-JobFilter`:

```
pwsh -NoProfile -File .claude/scripts/azp-job-durations.ps1 -BuildId 23050 -Offsets
pwsh -NoProfile -File .claude/scripts/azp-job-durations.ps1 -BuildId 23024,23068 -JobFilter x86 -Offsets
```

Each record gains `startOffset` / `endOffset` in minutes, and `builds[]` reports the build's `origin`, `span` and `partialRerun`. Two traps the mode exists to encode, both of which otherwise yield confident nonsense:

- **The origin is `min(job startTime)`, never the build's own `startTime`.** A build that was partially re-run carries a `startTime` *later* than its surviving job records, so build-relative offsets come out **negative**. Build 23063 measured a 305.9-minute span and a `Build` job finishing 218 minutes "before" the build began, against a real 148.4-minute end to end — `partialRerun: true` is the tell, and a flagged build's span is not comparable with an unflagged one's.
- **A job's `displayName` can be renamed mid-branch**, and an exact-name filter then reports the job as *absent* from the earlier builds rather than renamed. Filter on the stable fragment (`x86`, not `Build (win-x86)`). On #5819 the job was `Build (win-x86 test artifacts)` until a later commit shortened it, and an exact filter made two builds look like they predated the job entirely — which would have turned a correct comment in the PR into a bogus finding.

`azp-build-failures.ps1` cannot substitute here: it is failures-only and has nothing to say about a green build, which is the normal state of a build whose *timing* you are checking.

## Is a CI failure PR-introduced or pre-existing?

**Check the PR's own earlier `test-all` runs first.** When the PR has been CI'd before, a previous green run on the same branch is the strongest and cheapest baseline available — same base, same matrix, so any new failure belongs to the commits added since, with none of the like-for-like reasoning the cross-PR comparison below needs. The `check-runs` recipe further down resolves only the *latest* build, so list the definition's history and filter by branch instead:

```
gh api "https://dev.azure.com/linq2db/linq2db/_apis/build/builds?definitions=4&\$top=25&api-version=7.1" --jq '.value[] | select(.sourceBranch == "refs/pull/<n>/merge") | "\(.id) \(.result) \(.finishTime)"'
```

`definitions=4` is `test-all` (`3` = `default`, `5` = `build`; `/_apis/build/definitions` lists them all). Map each build back to a commit through its `sourceVersion` — that is the PR *merge* commit, not a branch SHA, so line the builds up against `gh pr view <n> --json commits` timestamps rather than expecting the head SHA to appear. (On #5780 this took one call: build 22771 green at the pre-retention head, 22792 red after the three commits that followed.)

To attribute a PR's failing jobs without a local build, compare the **master** Azure build whose `sourceVersion` equals the PR's merge-base. Get the merge-base with `git merge-base origin/master origin/<branch>`, list recent master builds (`…/_apis/build/builds?branchName=refs/heads/master&$top=8`), find the build whose `sourceVersion` matches, and run `azp-build-failures.ps1` on it. If master-at-merge-base is test-green, every failure on the PR is PR-introduced. This is the CI-side analogue of the local-worktree merge-base comparison in [`bug-investigation.md`](bug-investigation.md) → *Behavior-preserving refactor* — cheaper (no checkout/build, just two parsed build results), and it settled that all of PR #5485's Firebird failures were the PR's own (master build 21987 at the merge-base was clean).

**Caveat — confirm the comparison build actually ran the test matrix, and compare like-for-like.** Master-*push* builds run the `build`+publish pipeline only, **not** the provider test matrix (`azp-build-failures.ps1` reports `failedTaskCount: 0`, `tasks: []`, red only on the `Publish to Azure Artifacts feed` 402 step). Such a build carries **no** test signal — you cannot read master's test health from it, and a red master push build is usually just the 402, not broken tests. `test-all` runs only when triggered by `/azp run test-all` (a PR comment). So: to attribute a PR's `test-all` failure, compare against **another PR's `test-all` run whose merge commit shares the same master base** (check the `refs/pull/<n>/merge` parent SHA — `git log --format=%p -1 <mergeSha>`), not against a master push build and **never** against a PR that only ran `build` (its `gh pr checks` shows no `Tests:` legs — a build-only run says nothing about tests). Comparing a `test-all` failure to a build-only run is invalid. (Corrected after a session mis-attributed #5704's all-provider cache failures to a master commit by diffing against #5708, which had run build-only; the real cause was in #5704 itself.)

Resolve `<n>` (the Azure DevOps build ID) from the PR's check-runs:

```
gh api repos/linq2db/linq2db/commits/<headSha>/check-runs --jq '.check_runs[] | select(.name == "test-all") | .details_url'
```

The `details_url` ends in `buildId=<n>`.

**These `gh api … --jq` recipes are the build-metadata interface — don't hand-roll `Invoke-RestMethod` against the Azure builds API.** The `azp-*.ps1` scripts each answer a narrower question (`azp-build-failures` = per-test failures, `azp-job-durations` = timing/ordering, `azp-step-log` = one step's log, `azp-run` = trigger), so "which commit did build N build?", "what has this branch run lately?" and "is this definition red across other PRs too?" have no script — but they *are* covered here, by the two recipes above plus `/_apis/build/builds/<id>`'s `sourceVersion` + `triggerInfo`. (Surfaced on #5828: three hand-rolled `Invoke-RestMethod` calls re-derived exactly these, because the recipes live under a heading about failure *attribution* and don't read as the general build-query entry point.)

## A build failure with no code cause — check restore before the diff

A red `build` leg is not always about the code. The repo sets `TreatWarningsAsErrors`, and NuGet restore warnings are warnings, so an infrastructure hiccup during restore becomes a hard build break that names your project files and looks like a compile failure.

The recurring shape is **`NU1900`**, reported once per project:

```
Source\LinqToDB\LinqToDB.csproj(0,0): Error NU1900: Warning As Error: Error occurred while getting
package vulnerability data: Unable to load the service index for source <feed url>.
```

Two things make this hard to read correctly:

- **A source that nothing restores from is still consulted.** NuGet's vulnerability audit enumerates **every** source in `nuget.config`, independent of `packageSourceMapping`. So a feed with no mapped package pattern — one that cannot supply anything — still fails the build when it is unreachable. Grep the mapping before assuming a listed source is load-bearing.
- **It is repo-wide, not yours.** Every project fails identically and every open PR fails together. Before touching the branch, check whether sibling PRs' `build` legs went red in the same window (`…/builds?definitions=5&$top=25`, per the recipes above) and whether the same PR passed earlier that day with no code change in between.

The feed being reachable from your machine does not clear it — the agents are on different egress. (Surfaced 2026-08-31: `pomelo-nightly` had its `packageSourceMapping` entry commented out while the source stayed configured; when it stopped answering the agents, #5737, #5828 and #5834 all went red within the hour while the feed answered 200 locally. Fixed by commenting the source out alongside its mapping — [#5835](https://github.com/linq2db/linq2db/pull/5835).)
