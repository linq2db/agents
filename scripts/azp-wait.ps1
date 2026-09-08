<#
Block until an Azure Pipelines build reaches a terminal state, then report its jobs.

Why this script exists
----------------------
GitHub Actions has a blocking wait — `gh run watch <id> --exit-status` — and
`agent-rules.md` tells agents to use it instead of polling. Azure DevOps has no
equivalent, so an agent waiting on a `test-all` falls back to calling
`azp-build-info.ps1 -BuildId <n>` over and over. On #5880 that cost roughly ten
round-trips across four builds, every one of them asking the same question:
"has it started yet". This script asks it in one call.

It also encodes the two things that make that polling loop wrong more often than
it looks:

  * A queued build reports `notStarted` with **no jobs in its timeline**, which
    reads identically to a build whose jobs all vanished. Azure's hosted pool is
    routinely hours deep — build 23453 waited 1h38m, 23500 over two — so
    "2 jobs and no results" is the normal state for a long time, not a fault.
  * The test-leg jobs do not exist in the timeline until their phase starts, so
    the job list *grows*. A leg count read too early is not a small count, it is
    an absent one, and the leg list is the thing every split / selection claim
    turns on (see `test-matrix.yml`'s note on reading names, never verdicts).

Usage (via the PowerShell tool, not wrapped in Bash):

    # wait up to 3h, checking every 5 min, then print the job list
    .claude\scripts\azp-wait.ps1 -BuildId 23500

    # tighter loop for a short build
    .claude\scripts\azp-wait.ps1 -BuildId 23499 -IntervalSeconds 60 -TimeoutMinutes 45

    # return as soon as the leg jobs appear, without waiting for them to finish
    .claude\scripts\azp-wait.ps1 -BuildId 23500 -UntilJobsAppear

Output is a single JSON document: the build's final state plus one entry per Job
timeline record. Exit codes are distinct so a caller can tell the cases apart
without parsing: 0 = terminal state reached, 3 = timed out still waiting,
1 = API failure.
#>

param(
    [Parameter(Mandatory)][int]$BuildId,
    [int]$TimeoutMinutes = 180,
    [int]$IntervalSeconds = 300,
    [switch]$UntilJobsAppear,
    [string]$Org = 'linq2db',
    [string]$Project = 'linq2db'
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

$base = "https://dev.azure.com/$Org/$Project/_apis/build"

function Invoke-Azp([string]$url) {
    try {
        return Invoke-RestMethod -Uri $url -Headers @{ Accept = 'application/json' }
    }
    catch {
        # A single transient failure is normal on a long wait (one hit on #5880), so the
        # caller gets $null and the loop retries rather than dying two hours in.
        return $null
    }
}

$deadline = (Get-Date).AddMinutes($TimeoutMinutes)
$build    = $null
$timeline = $null
$timedOut = $false

while ($true) {
    $build = Invoke-Azp "$base/builds/$BuildId`?api-version=7.0"

    if ($build) {
        $timeline = Invoke-Azp "$base/builds/$BuildId/timeline?api-version=7.0"
        $jobCount = @($timeline.records | Where-Object { $_.type -eq 'Job' }).Count

        if ($build.status -eq 'completed') { break }
        if ($UntilJobsAppear -and $jobCount -gt 0 -and $build.status -eq 'inProgress') { break }
    }

    if ((Get-Date) -ge $deadline) { $timedOut = $true; break }
    Start-Sleep -Seconds $IntervalSeconds
}

if (-not $build) {
    Write-Error "azp-wait: could not read build $BuildId after $TimeoutMinutes minute(s) of retries"
    exit 1
}

$jobs = @($timeline.records | Where-Object { $_.type -eq 'Job' } | Sort-Object name |
    ForEach-Object { [ordered]@{ name = $_.name; result = $_.result; state = $_.state } })

[ordered]@{
    buildId       = $BuildId
    definition    = $build.definition.name
    status        = $build.status
    result        = $build.result
    sourceBranch  = $build.sourceBranch
    sourceVersion = $build.sourceVersion
    queueTime     = $build.queueTime
    startTime     = $build.startTime
    finishTime    = $build.finishTime
    timedOut      = $timedOut
    jobs          = $jobs
} | ConvertTo-Json -Depth 5

if ($timedOut) { exit 3 }
exit 0
