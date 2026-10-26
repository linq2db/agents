<#
Block until a GitHub Actions run reaches a terminal state, then report its jobs.

Why this script exists
----------------------
The provider legs of an `/azp run` live in a dispatched `tests (comment)` run
(azp-run.ps1 prints its id). Neither existing wait fits it:

  * `gh run watch <id> --exit-status` dies at the Bash tool's 600 s ceiling, and
    the death reads exactly like a failed run (ci-tests.md -> "Two limits on that
    blocking form").
  * `wait-pr-checks.ps1 -Gate '<leg>'` polls the PR's statusCheckRollup, and a
    dispatched run's jobs are not in it - the run is attributed to master's
    commit. On #6161 it reported `Lin l_SqlServer2017_2019` "missing" for its
    whole 45-minute timeout while the run had already succeeded.

This polls `gh run view <id>` on a wide cadence and returns one summary.

Usage (via the PowerShell tool, with run_in_background):

    .claude\scripts\gh-run-wait.ps1 -RunId 40371438419
    .claude\scripts\gh-run-wait.ps1 -RunId 40371438419 -JobFilter SqlServer -TimeoutMinutes 45

Output is a single JSON document: the run's final status/conclusion plus one entry
per job (filtered by -JobFilter, a regex on the job name). Exit codes: 0 = terminal
state reached, 3 = timed out still running, 1 = gh failed on every poll.

-TimeoutMinutes is capped at 50: the session's prompt cache expires after 1 hour.
On exit 3, re-arm the wait (turn-conduct.md -> "Cap a background wait at 50 minutes").
#>

param(
    [Parameter(Mandatory)][long]$RunId,
    [string]$Repo = 'linq2db/linq2db',
    [ValidateRange(1, 50)][int]$TimeoutMinutes = 50,
    [int]$IntervalSeconds = 60,
    [string]$JobFilter = ''
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

function Get-Run {
    $json = gh run view $RunId --repo $Repo --json status,conclusion,createdAt,updatedAt,url,jobs 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $json) { return $null }
    try { return $json | ConvertFrom-Json } catch { return $null }
}

$deadline = (Get-Date).AddMinutes($TimeoutMinutes)
$run      = $null
$seen     = $false
$timedOut = $false

while ($true) {
    # A transient gh failure is retried rather than ending a long wait.
    $current = Get-Run
    if ($current) {
        $run  = $current
        $seen = $true
        if ($run.status -eq 'completed') { break }
    }

    if ((Get-Date) -ge $deadline) { $timedOut = $true; break }
    Start-Sleep -Seconds $IntervalSeconds
}

if (-not $seen) {
    Write-Error "gh-run-wait: could not read run $RunId after $TimeoutMinutes minute(s) of retries"
    exit 1
}

$jobs = @($run.jobs |
    Where-Object { -not $JobFilter -or $_.name -match $JobFilter } |
    Sort-Object name |
    ForEach-Object { [ordered]@{ name = $_.name; status = $_.status; conclusion = $_.conclusion } })

[ordered]@{
    runId      = $RunId
    url        = $run.url
    status     = $run.status
    conclusion = $run.conclusion
    createdAt  = $run.createdAt
    updatedAt  = $run.updatedAt
    timedOut   = $timedOut
    jobs       = $jobs
} | ConvertTo-Json -Depth 5

if ($timedOut) { exit 3 }
exit 0
