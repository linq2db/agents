#!/usr/bin/env pwsh
<#
List one GitHub test leg's result across recent `tests (comment)` runs, with the PR each run tested.
The GitHub-side answer to "is this leg's failure PR-introduced or pre-existing?".

Why this script exists
----------------------
A `tests (comment)` run starts from an `issue_comment` event, so its `head_sha` is master's commit and
nothing in the run object names the PR. Telling whether a leg's failure is new took a hand-rolled loop:
list the workflow's runs, list each run's jobs across attempts and filter by leg name, then open a job
log to learn which PR the run tested. This script does all of that in one call. The PR number is read
from the small `authorize` job log, which prints the `NUMBER:` env var. The multi-MB test-leg log is
never fetched.

Invoke directly via the PowerShell tool (preferred), NOT wrapped in Bash:

    .claude\scripts\gh-leg-history.ps1 -Leg PostgreSQL1
    .claude\scripts\gh-leg-history.ps1 -Leg i_PostgreSQL1 -Count 60 -AllPrs

Then fetch a failed run's leg log and compare the first failing test and its message:

    .claude\scripts\gh-run-logs.ps1 -RunId <id> -JobFilter <leg>

Contract
--------
  -Leg     <string>  required; case-insensitive substring of the job name ("PostgreSQL1", "Lin c_PostgreSQL2")
  -Count   <int>     workflow runs to scan, default 40 (newest first)
  -AllPrs            resolve the PR for every row; by default only for rows that are not 'success'
                     (one small log fetch per resolved row)
  -Repo    <string>  default 'linq2db/linq2db'

Output: one JSON object on stdout.

  {
    "leg": "PostgreSQL1",
    "runsScanned": 40,
    "rows": [ { "runId": 37042673412, "createdAt": "...", "attempt": 2,
                "job": "tests / Lin i_PostgreSQL1", "conclusion": "failure", "pr": 5978 } ]
  }

One row per (run, attempt) that ran the leg. A run whose attempt 1 stopped at `authorize` (tests
skipped) has no leg job in that attempt, so only the attempt that actually ran tests shows up.
`pr` is null when not resolved, or when the authorize log has expired.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $Leg,
    [int]    $Count = 40,
    [switch] $AllPrs,
    [string] $Repo  = 'linq2db/linq2db'
)

$ErrorActionPreference = 'Stop'

$global:ScriptBaseName = 'gh-leg-history'
. "$PSScriptRoot/_shared.ps1"

# tests-comment.yml; its id is stable, and ci-tests.md cites it too.
$workflowId = 350529502

$runs = Invoke-GhJson -ArgumentList @(
    'api', "repos/$Repo/actions/workflows/$workflowId/runs?per_page=$Count",
    '--jq', '[.workflow_runs[] | {id, created_at}]'
)

if (-not $runs.ok) { Exit-WithError "gh api workflow runs failed: $($runs.error)" }

$rows = [System.Collections.Generic.List[object]]::new()

foreach ($run in @($runs.data)) {
    $jobs = Invoke-GhJson -ArgumentList @(
        'api', "repos/$Repo/actions/runs/$($run.id)/jobs?filter=all&per_page=100", '--paginate',
        '--jq', '[.jobs[] | {id, name, conclusion, run_attempt}]'
    )

    if (-not $jobs.ok) { Exit-WithError "gh api jobs for run $($run.id) failed: $($jobs.error)" }

    $all     = @($jobs.data)
    $matched = @($all | Where-Object { $_.name -match [regex]::Escape($Leg) })

    if ($matched.Count -eq 0) { continue }

    $pr = $null

    if ($AllPrs -or @($matched | Where-Object { $_.conclusion -ne 'success' }).Count -gt 0) {
        $auth = $all | Where-Object { $_.name -eq 'authorize' } | Select-Object -First 1

        if ($auth) {
            # Without --allow-escape-sequences gh refuses the whole log (the runner colours it).
            $log = Invoke-Gh -ArgumentList @('api', "repos/$Repo/actions/jobs/$($auth.id)/logs", '--allow-escape-sequences')

            if ($log.ok -and (($log.stdout -join "`n") -replace "`e\[[0-9;]*m", '') -match '(?m)^\S+\s+NUMBER:\s*(\d+)\s*$') {
                $pr = [int]$Matches[1]
            }
        }
    }

    foreach ($job in $matched | Sort-Object run_attempt) {
        $rows.Add([pscustomobject][ordered]@{
            runId      = $run.id
            createdAt  = $run.created_at
            attempt    = $job.run_attempt
            job        = $job.name
            conclusion = $job.conclusion
            pr         = $pr
        })
    }
}

Write-JsonOutput ([ordered]@{
    leg         = $Leg
    runsScanned = @($runs.data).Count
    rows        = $rows
})
