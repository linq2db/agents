#!/usr/bin/env pwsh
<#
Find where a test, or an error message, failed across recent GitHub test runs on any PR — without
downloading a single job log.

Why this script exists
----------------------
"Is this failure a known flake — did the same test, or the same error, fail on other PRs?" used to mean
downloading every failed leg's log (7–12 MB each) and grepping it. A failed job's check-run annotations
already carry what the question needs: one `failure` annotation per failing test, whose `title` is the
test case (`CountAsync("ClickHouse.Octonica.LinqService")`) and whose `message` is the start of its
error. Reading annotations costs one small API call per failed job, so hundreds of jobs scan in minutes.
(#6074: 140 failed runs / 467 failed jobs scanned; the same Octonica cancellation had failed 5 different
ClickHouse tests — #6327.)

By default only runs whose conclusion is `failure` are listed. Every PR comment starts a
`tests-comment.yml` run and most of those stop at `authorize`, so 25 completed runs span about a day,
while 100 failed runs reach back about two months. A flake that a rerun turned green leaves its run
`success`, so `-IncludeGreenRuns` lists every completed run instead. That reaches those flakes but covers
a far shorter window. Jobs are always read with `filter=all`, so a failed earlier attempt of a listed
run is included either way.

`gh-leg-history.ps1` answers a different question (one leg's result per run). To read a hit in full,
fetch its log: `.claude\scripts\gh-run-logs.ps1 -RunId <runId> -JobFilter <leg>`.

Invoke directly via the PowerShell tool (preferred), NOT wrapped in Bash:

    .claude\scripts\gh-flake-history.ps1 -TitleRegex 'MultipleConnectionsTest'
    .claude\scripts\gh-flake-history.ps1 -JobRegex ClickHouse -MessageRegex 'OperationCanceled|Timeout' -Count 150

Contract
--------
  -TitleRegex   <string>   regex over the annotation title (the test case); default '.'
  -MessageRegex <string>   regex over the annotation message (error start, ~200 chars); default '.'
  -JobRegex     <string>   regex over the job name ("tests / Lin b_ClickHouse"); default '.'
  -Count        <int>      runs to scan per workflow, newest first; default 100
  -IncludeGreenRuns        list completed runs of any conclusion, not only failed ones
  -Workflow     <string[]> workflow files; default tests-comment.yml, tests.yml
  -Repo         <string>   default 'linq2db/linq2db'

At least one of the three regexes should be narrower than '.', or every failed test is returned.

Output: one JSON object on stdout.

  {
    "runsScanned": 200, "failedJobsScanned": 467, "oldestRun": "2026-09-04T13:31:38Z",
    "hits": [ { "createdAt": "...", "runId": 43248591019, "attempt": 1, "runTitle": "<PR title>",
                "job": "tests / Lin b_ClickHouse", "jobId": 131295050430,
                "test": "CountAsync(\"ClickHouse.Octonica.LinqService\")", "message": "[Failed] ..." } ],
    "errors": [ "run 43424502835: ... TLS handshake timeout" ]
  }

A failed API call for one run or job is recorded in `errors` and skipped, so a non-empty `errors` means
the scan is incomplete by those entries.

`runTitle` is the run's display title, which for a comment-triggered run is the PR title; resolve the
PR number with gh-leg-history.ps1 when needed.
#>

[CmdletBinding()]
param(
    [string]   $TitleRegex   = '.',
    [string]   $MessageRegex = '.',
    [string]   $JobRegex     = '.',
    [int]      $Count        = 100,
    [switch]   $IncludeGreenRuns,
    [string[]] $Workflow     = @('tests-comment.yml', 'tests.yml'),
    [string]   $Repo         = 'linq2db/linq2db'
)

$ErrorActionPreference = 'Stop'

$global:ScriptBaseName = 'gh-flake-history'
. "$PSScriptRoot/_shared.ps1"

$runs   = [System.Collections.Generic.List[object]]::new()
$status = if ($IncludeGreenRuns) { 'completed' } else { 'failure' }

foreach ($wf in $Workflow) {
    $res = Invoke-GhJson -ArgumentList @(
        'api', "repos/$Repo/actions/workflows/$wf/runs?status=$status&per_page=$Count",
        '--jq', '[.workflow_runs[] | {id, created_at, display_title}]'
    )

    if (-not $res.ok) { Exit-WithError "gh api runs for $wf failed: $($res.error)" }

    foreach ($r in @($res.data)) { $runs.Add($r) }
}

$hits    = [System.Collections.Generic.List[object]]::new()
$errors  = [System.Collections.Generic.List[string]]::new()
$scanned = 0

foreach ($run in $runs) {
    $jobs = Invoke-GhJson -ArgumentList @(
        'api', "repos/$Repo/actions/runs/$($run.id)/jobs?filter=all&per_page=100", '--paginate',
        '--jq', '[.jobs[] | select(.conclusion == "failure") | {id, name, run_attempt}]'
    )

    # One flaky API call must not lose a multi-minute scan: record it and move on.
    if (-not $jobs.ok) { $errors.Add("run $($run.id): $($jobs.error)"); continue }

    foreach ($job in @($jobs.data) | Where-Object { $_.name -match $JobRegex }) {
        $scanned++

        $ann = Invoke-GhJson -ArgumentList @(
            'api', "repos/$Repo/check-runs/$($job.id)/annotations?per_page=100",
            '--jq', '[.[] | select(.annotation_level == "failure" and .title != "") | {title, message}]'
        )

        if (-not $ann.ok) { $errors.Add("job $($job.id): $($ann.error)"); continue }

        foreach ($a in @($ann.data) | Where-Object { $_.title -match $TitleRegex -and $_.message -match $MessageRegex }) {
            $hits.Add([pscustomobject][ordered]@{
                createdAt = $run.created_at
                runId     = $run.id
                attempt   = $job.run_attempt
                runTitle  = $run.display_title
                job       = $job.name
                jobId     = $job.id
                test      = $a.title
                message   = $a.message
            })
        }
    }
}

Write-JsonOutput ([ordered]@{
    runsScanned       = $runs.Count
    failedJobsScanned = $scanned
    oldestRun         = ($runs | Sort-Object created_at | Select-Object -First 1).created_at
    hits              = @($hits | Sort-Object createdAt -Descending)
    errors            = $errors
})
