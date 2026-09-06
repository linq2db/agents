<#
Azure Pipelines build *metadata* — which builds ran, what commit each built, and
what happened to the individual tasks inside one job.

Why this script exists
----------------------
The three existing azp-* scripts each answer a narrower question:

    azp-build-failures.ps1  which tests failed  (failures only)
    azp-step-log.ps1        one step's stdout   (needs the step name)
    azp-job-durations.ps1   how long jobs took  (timing / ordering)

None of them answers "which builds ran for this PR and at what commit" or "which
tasks inside this job actually ran versus got skipped". `agent-rules.md` warns
three separate times against hand-rolling `Invoke-RestMethod` against
`/_apis/build/builds` and `/timeline` — and it keeps happening, because the
absence of a script reads as permission. This is that script.

The task-list view matters more than it sounds. Azure reports a *build's*
startTime, which on a queued build can be many hours before a given job starts,
and every task after a failure shows `skipped`. Read a failure as
"netfx-specific" without the task list and you are wrong twice over: the later
TFMs never ran, and `Commit test baselines` never ran either, so the artifacts
you would use to diagnose it were never published. (Both misreadings happened on
#5740 / build 23411 before the timeline was pulled.)

Usage (via the PowerShell tool, not wrapped in Bash):

    # builds for a PR, newest first: result, queue/start/finish, built sha
    .claude\scripts\azp-build-info.ps1 -Pr 5740

    # same for a branch
    .claude\scripts\azp-build-info.ps1 -Branch refs/heads/master -Top 5

    # every task in the jobs matching a filter, with per-task result
    .claude\scripts\azp-build-info.ps1 -BuildId 23411 -JobFilter Access

    # just the jobs of a build and their results
    .claude\scripts\azp-build-info.ps1 -BuildId 23411

Output is JSON on stdout. Non-zero exit on an API failure.
#>

param(
    [int]$Pr,
    [string]$Branch,
    [int]$BuildId,
    [string]$JobFilter,
    [int]$Top = 10,
    [string]$Org = 'linq2db',
    [string]$Project = 'linq2db'
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

if (-not $Pr -and -not $Branch -and -not $BuildId) {
    throw 'Pass one of -Pr, -Branch or -BuildId.'
}

$base = "https://dev.azure.com/$Org/$Project/_apis/build"

function Invoke-Azp([string]$url) {
    try {
        return Invoke-RestMethod -Uri $url -Headers @{ Accept = 'application/json' }
    }
    catch {
        throw "Azure DevOps request failed: $url`n$($_.Exception.Message)"
    }
}

# The test-results API (/_apis/test/runs?buildUri=...) is NOT usable here: anonymously it
# returns an HTML sign-in page rather than JSON or a 401, so a naive call looks like a
# malformed response instead of an auth failure. Per-test data comes from the task logs -
# use azp-build-failures.ps1.

if ($BuildId) {
    $timeline = Invoke-Azp "$base/builds/$BuildId/timeline?api-version=7.0"
    $build    = Invoke-Azp "$base/builds/$BuildId`?api-version=7.0"

    $jobs = @($timeline.records | Where-Object { $_.type -eq 'Job' })
    if ($JobFilter) {
        $jobs = @($jobs | Where-Object { $_.name -like "*$JobFilter*" })
    }

    $result = [ordered]@{
        buildId       = $BuildId
        result        = $build.result
        sourceBranch  = $build.sourceBranch
        sourceVersion = $build.sourceVersion
        prSourceSha   = $build.triggerInfo.'pr.sourceSha'
        queueTime     = $build.queueTime
        jobs          = @()
    }

    foreach ($j in ($jobs | Sort-Object name)) {
        $row = [ordered]@{
            name       = $j.name
            result     = $j.result
            startTime  = $j.startTime
            finishTime = $j.finishTime
        }

        # Only expand tasks when a filter narrowed the set - a whole test-all build has
        # ~30 jobs x ~60 tasks, which is not something to spill into a caller's context.
        if ($JobFilter) {
            $row.tasks = @(
                $timeline.records |
                    Where-Object { $_.parentId -eq $j.id } |
                    Sort-Object order |
                    ForEach-Object {
                        [ordered]@{ order = $_.order; name = $_.name; result = $_.result; issues = @($_.issues).Count }
                    }
            )
        }

        $result.jobs += $row
    }

    $result | ConvertTo-Json -Depth 6
    exit 0
}

$branchName = if ($Pr) { "refs/pull/$Pr/merge" } else { $Branch }
$builds     = Invoke-Azp "$base/builds?branchName=$([uri]::EscapeDataString($branchName))&api-version=7.0&`$top=$Top"

@{
    branchName = $branchName
    builds     = @(
        $builds.value | ForEach-Object {
            [ordered]@{
                id            = $_.id
                definition    = $_.definition.name
                status        = $_.status
                result        = $_.result
                queueTime     = $_.queueTime
                startTime     = $_.startTime
                finishTime    = $_.finishTime
                sourceVersion = $_.sourceVersion
                prSourceSha   = $_.triggerInfo.'pr.sourceSha'
            }
        }
    )
} | ConvertTo-Json -Depth 4
