#!/usr/bin/env pwsh
<#
Download a GitHub Actions run's job logs to disk and report where they landed.
The GitHub counterpart to `azp-build-failures.ps1`, and the fetch half of
`ci-test-verdicts.ps1`.

Why this script exists
----------------------
Triaging a red `tests [all]` round means getting from "run N failed" to a set of
log files on disk that `ci-test-verdicts.ps1 -Dir` can parse. `gh run view
--log-failed` stream-errors on a run this size, so the working recipe is a
two-step `gh api` dance - list jobs, then fetch each job's log - which was
documented as prose in two places (this script's sibling header, and
`ci-tests.md` -> *Reading failed CI test runs*) and hand-rolled per session.
Documenting a multi-step sequence is the evidence it keeps being retyped, so it
is codified here: one allowlisted call, no per-job `>` redirect to miss the
allowlist, and JSON out that names every file written.

Note the asymmetry with Azure: `azp-build-failures.ps1` *parses* failures out of
the log, because Azure's log ids need a timeline walk to reach. Here the parsing
belongs to `ci-test-verdicts.ps1`, which reads both CI systems' logs with one
grammar - this script only fetches.

Invoke directly via the PowerShell tool (preferred), NOT wrapped in Bash:

    .claude\scripts\gh-run-logs.ps1 -RunId 35018401682
    .claude\scripts\gh-run-logs.ps1 -RunId 35018401682 -Conclusion all
    .claude\scripts\gh-run-logs.ps1 -RunId 35018401682 -JobFilter SQLite

Then:

    .claude\scripts\ci-test-verdicts.ps1 -Dir .build/.agents/gh-35018401682 -Format table

Contract
--------
  -RunId       <long>    required; the Actions run id (the number in /actions/runs/<id>)
  -Repo        <string>  default 'linq2db/linq2db'
  -Conclusion  <string>  'failure' (default) | 'all' | any job conclusion GitHub reports
                         ('success', 'cancelled', 'skipped', ...). A green job's log is the
                         only place a HOLDING gate quotes the failure it holds against, so
                         `-Conclusion all` is what you want when harvesting declarations
                         rather than triaging failures (see ci-test-verdicts.ps1 ->
                         "Harvesting what a holding gate hides").
  -JobFilter   <string>  optional case-insensitive substring on the job name
  -WriteDir    <path>    default '.build/.agents/gh-<RunId>'

Output: one JSON object on stdout. Logs persist under WriteDir for Read / Grep.

  {
    "runId": 35018401682,
    "repo": "linq2db/linq2db",
    "logsDir": ".build/.agents/gh-35018401682",
    "jobsMatched": 6,
    "jobsFetched": 6,
    "jobs": [ { "id": 104551977299, "name": "tests / Win g_SqlCE",
                "conclusion": "failure", "path": "...", "bytes": 4499584 } ],
    "failed": [ { "id": ..., "name": ..., "error": "..." } ]
  }

A job whose log GitHub has already expired (they age out) lands in `failed` with
the API error rather than aborting the run - a partial fetch is still useful.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)][long] $RunId,
    [string] $Repo       = 'linq2db/linq2db',
    [string] $Conclusion = 'failure',
    [string] $JobFilter,
    [string] $WriteDir
)

$ErrorActionPreference = 'Stop'

$global:ScriptBaseName = 'gh-run-logs'
. "$PSScriptRoot/_shared.ps1"

if (-not $WriteDir) { $WriteDir = Join-Path '.build/.agents' "gh-$RunId" }
if (-not (Test-Path $WriteDir)) { New-Item -ItemType Directory -Path $WriteDir -Force | Out-Null }

$WriteDir = (Resolve-Path $WriteDir).Path

# --allow-escape-sequences keeps the runner's ANSI colouring, which ci-test-verdicts.ps1 strips
# itself - stripping here instead would lose the failed/skipped markers it keys on.
$listed = Invoke-GhJson -ArgumentList @(
    'api', "repos/$Repo/actions/runs/$RunId/jobs?per_page=100", '--paginate',
    '--jq', '[.jobs[] | {id, name, conclusion}]'
)

if (-not $listed.ok) { Exit-WithError "gh api jobs failed: $($listed.error)" }

$jobs = @($listed.data)

if ($Conclusion -ne 'all') {
    $jobs = @($jobs | Where-Object { $_.conclusion -eq $Conclusion })
}

if ($JobFilter) {
    $jobs = @($jobs | Where-Object { $_.name -match [regex]::Escape($JobFilter) })
}

$fetched = [System.Collections.Generic.List[object]]::new()
$failed  = [System.Collections.Generic.List[object]]::new()

foreach ($job in $jobs) {
    # The job name carries '/' and spaces ("tests / Lin p_MySQL"); collapse to a filename that
    # survives both filesystems and stays recognisable in a Grep result.
    $safe = (($job.name -replace '[^A-Za-z0-9_-]', '-') -replace '-+', '-').Trim('-')
    $path = Join-Path $WriteDir "$safe.log"

    $log = Invoke-Gh -ArgumentList @(
        'api', "repos/$Repo/actions/jobs/$($job.id)/logs", '--allow-escape-sequences'
    )

    if (-not $log.ok) {
        $failed.Add([pscustomobject]@{ id = $job.id; name = $job.name; error = $log.error })
        continue
    }

    [System.IO.File]::WriteAllText($path, $log.stdout, [System.Text.UTF8Encoding]::new($false))

    $fetched.Add([pscustomobject]@{
        id         = $job.id
        name       = $job.name
        conclusion = $job.conclusion
        path       = $path
        bytes      = (Get-Item $path).Length
    })
}

Write-JsonOutput ([ordered]@{
    runId       = $RunId
    repo        = $Repo
    conclusion  = $Conclusion
    logsDir     = $WriteDir
    jobsMatched = $jobs.Count
    jobsFetched = $fetched.Count
    jobs        = $fetched
    failed      = $failed
})
