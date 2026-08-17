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

To read a **specific step's log by name** — including a *succeeded* diagnostic step whose value is its stdout (a CI probe printing a summary block, a setup step's timing), which `azp-build-failures.ps1` never surfaces — use [`.claude/scripts/azp-step-log.ps1`](../scripts/azp-step-log.ps1) rather than hand-running the `curl …/timeline | python`-to-find-the-log-id-then-`curl …/logs/<id>` dance:

```
pwsh -NoProfile -File .claude/scripts/azp-step-log.ps1 -BuildId <n> -StepName '<name-substring>'
```

Output: JSON `{ buildId, stepName, logsDir, steps: [{ name, state, result, logPath }] }`; `-StepName` is a case-insensitive substring (matches all Task records containing it). A matched-but-pending step reports `logPath: null` (no log until it starts) rather than failing. `Read` / `Grep` the persisted `logPath`.

**Azure log ids are per *build* — never carry one across builds.** `/logs/1202` is a different step in every build, and fetching it against the wrong build returns *another job's* log with no error: same shape, plausible numbers, wrong provider. Resolve the log from that build's own `/timeline` every time — which is what `azp-step-log.ps1 -StepName` and `azp-job-durations.ps1 -WithTestCounts` both do. The symptom to watch for is an internal contradiction: a "test duration" that exceeds or undershoots the step's own wall time. (Surfaced while comparing DB2 timings across builds 22710 and 22726: log id 1202 was the DB2 step in 22726 but a different provider's in 22710, yielding `9871 tests / 4m 04s` for a step whose timeline duration was 7.21 min. The wrong figure was one step away from a public PR comment.)

**Per-job test counts: parse the step log, not the test-runs API.** `_apis/test/runs?buildUri=vstfs:///Build/Build/<id>` returns a single aggregate record with no usable per-job breakdown — don't re-attempt it. The runner's own summary block at the end of each test step's log carries `total:` / `skipped:` / `duration:`, and those lines are ANSI-colorized, so strip escape sequences before matching. `azp-job-durations.ps1 -WithTestCounts` does this.

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
