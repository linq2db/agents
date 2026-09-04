<#
Fetch the failed-test list (with first error per failure) from an Azure DevOps
build on the linq2db project. Used when reviewing PR CI failures: get from
"build N failed" to "exact failing test names + per-provider error messages"
without doing the timeline -> log-id -> Invoke-WebRequest -> Grep dance by hand.

The Azure DevOps `dev.azure.com/linq2db` build API is publicly readable
(no auth needed). The script hits:
  1. /timeline                            -> list failed Task records
  2. /logs/<id> for each failing test job -> raw log
  3. parse log for `Failed <name>... Error Message:` blocks

Invoke directly via the PowerShell tool (preferred), NOT wrapped in Bash:

    .claude\scripts\azp-build-failures.ps1 -BuildId 20250
    .claude\scripts\azp-build-failures.ps1 -BuildId 20250 -WriteDir .build/.agents/azp-20250

Output: single JSON document on stdout with per-task failures and on-disk
log paths. Logs are persisted under -WriteDir for follow-up Read / Grep.

Each task carries `reportedFailedTotal` (parsed from the runner's "failed: N"
summary line) and `truncated` (true when the captured failures[] were capped at
-MaxFailuresPerTask below the reported total). When `truncated` is true, the
failures[] list is a prefix — re-run with a higher -MaxFailuresPerTask, or Grep
the persisted log, before reporting a failure count as complete.

Re-run jobs keep their original failure in a SEPARATE timeline
---------------------------------------------------------------
Hitting "re-run failed jobs" does not overwrite the failed attempt: Azure keeps
it in its own timeline, reachable only through
`records[].previousAttempts[].timelineId`, while `/timeline` returns the *retry*.
So "the leg failed, I re-ran it, now tell me why it failed" reads as a build with
nothing wrong unless the earlier attempts are walked too — the failure the caller
is asking about is invisible in the default timeline.

Earlier attempts are therefore walked when `-IncludePreviousAttempts` is passed,
and also automatically when the current timeline yields no failures at all (that
is exactly the re-run case, where answering "no failures" is useless). Each entry
in `tasks` / `buildFailures` carries an `attempt` label — `current`, or `prior<n>`
oldest-first — and a prior attempt's log lands under a suffixed filename so it
cannot overwrite the retry's log for the same step name.

When the build failed for a non-test reason (e.g. a compile error in a
"Build …" step, or a "Command line" step wrapping dotnet build/publish), there
are no `Tests *` task failures to parse; the result then carries a
`buildFailures` array instead — each failed Task's name, its timeline error
`issues`, plus the downloaded `logPath` and a parsed `errors` list. For a
"Command line" wrapper the timeline `issues` only hold the generic shell exit
("Cmd.exe exited with code '1'"); the real CSxxxx / MAxxxx / MSBxxxx message
lives in the task log, which is why the log is fetched and `: error` /
`##[error]` lines are surfaced in `errors`.
#>

param(
    [Parameter(Mandatory)][int]$BuildId,
    [string]$WriteDir,
    [string]$Org = 'linq2db',
    [string]$Project = '0dcc414b-ea54-451e-a54f-d63f05367c4b',
    [int]$MaxFailuresPerTask = 20,
    [switch]$IncludePreviousAttempts
)

$global:ScriptBaseName = 'azp-build-failures'
. "$PSScriptRoot/_shared.ps1"

if (-not $WriteDir) {
    $WriteDir = ".build/.agents/azp-$BuildId"
}
New-Item -ItemType Directory -Force -Path $WriteDir | Out-Null

$baseUrl = "https://dev.azure.com/$Org/$Project/_apis/build/builds/$BuildId"

function ConvertTo-Slug {
    param([string]$Name)
    $s = $Name.ToLowerInvariant()
    $s = $s -replace '[^a-z0-9]+', '-'
    return $s.Trim('-')
}

# 1. Timeline(s) -> failed Task records that look like test jobs.
function Get-BuildTimeline([string]$timelineId) {
    $uri = if ($timelineId) { "$baseUrl/timeline/${timelineId}?api-version=7.1" } else { "$baseUrl/timeline?api-version=7.1" }
    try {
        return Invoke-RestMethod -Uri $uri
    }
    catch {
        Exit-WithError "failed to fetch timeline '${timelineId}' for build ${BuildId}: $_"
    }
}

function Select-FailedTestTasks($records) {
    return @(@($records) | Where-Object {
        $null -ne $_ -and
        $_.type -eq 'Task' -and $_.result -eq 'failed' -and
        ($_.name -like 'Tests *' -or $_.name -like 'EF.Core Tests *') -and $_.log })
}

# Tags each record with the attempt it came from, so the caller can tell a retry's failure from the
# original one and the log filenames below stay distinct.
#
# foreach over @($records) rather than a pipeline: an empty result passed positionally arrives as
# $null, and `$null | ForEach-Object` runs one iteration with $_ = $null, which Add-Member rejects
# with "Cannot bind argument to parameter 'InputObject' because it is null".
function Add-AttemptLabel($records, [string]$label) {
    $labelled = @()

    foreach ($rec in @($records)) {
        if ($null -eq $rec) { continue }
        $labelled += ($rec | Add-Member -NotePropertyName attempt -NotePropertyValue $label -PassThru -Force)
    }

    return $labelled
}

$current   = Get-BuildTimeline $null
$timelines = @([pscustomobject]@{ attempt = 'current'; records = $current.records })

# Oldest first, so the earliest attempt's failures are reported before the retry's.
$priorTimelineIds = @($current.records |
    Where-Object { $_.previousAttempts } |
    ForEach-Object  { $_.previousAttempts } |
    ForEach-Object  { $_.timelineId } |
    Where-Object    { $_ } |
    Select-Object -Unique)

$failedTasks = @(Add-AttemptLabel (Select-FailedTestTasks $current.records) 'current')

# Walk earlier attempts on request, and unconditionally when the current timeline is clean: a build
# whose failed jobs were re-run has its failure only there, so "no failures" would be a wrong answer.
if ($priorTimelineIds.Count -gt 0 -and ($IncludePreviousAttempts -or $failedTasks.Count -eq 0)) {
    $priorIndex = 0
    foreach ($timelineId in $priorTimelineIds) {
        $priorIndex++
        $label = "prior$priorIndex"
        $prior = Get-BuildTimeline $timelineId

        $timelines  += [pscustomobject]@{ attempt = $label; records = $prior.records }
        $failedTasks = @($failedTasks) + @(Add-AttemptLabel (Select-FailedTestTasks $prior.records) $label)
    }

    $failedTasks = @($failedTasks)
}

# A prior attempt's step shares its name with the retry's, so the slug must carry the attempt or the
# second download silently overwrites the first.
function Get-LogFileName($record) {
    $slug = ConvertTo-Slug -Name $record.name
    if ($record.attempt -and $record.attempt -ne 'current') {
        $slug = "$slug-$($record.attempt)"
    }
    return "$slug.log"
}

if ($failedTasks.Count -eq 0) {
    # No failed *test* tasks. A build can still be red for a non-test reason (a
    # compile error in a "Build …" step, a restore failure, or a "Command line"
    # step wrapping dotnet build/publish). For a "Command line" wrapper the
    # timeline `issues` only carry the generic shell exit ("Cmd.exe exited with
    # code '1'") — the real CSxxxx / MAxxxx / MSBxxxx error is in the task's own
    # log, not the timeline. So download + parse each failed non-test task's log
    # too, not just its timeline issues, and return logPath + parsed errors[].
    $buildFailures = @($timelines |
        ForEach-Object { Add-AttemptLabel $_.records $_.attempt } |
        Where-Object { $_.type -eq 'Task' -and $_.result -eq 'failed' -and ($_.issues -or $_.log) } |
        ForEach-Object {
            $rec    = $_
            $issues = @($rec.issues | Where-Object { $_.type -eq 'error' } | ForEach-Object { $_.message })

            $logPath = $null
            $errors  = @()
            if ($rec.log -and $rec.log.url) {
                $logPath = Join-Path $WriteDir (Get-LogFileName $rec)
                try {
                    Invoke-WebRequest -Uri $rec.log.url -OutFile $logPath -UseBasicParsing | Out-Null
                    $errors = @(Get-Content -LiteralPath $logPath |
                        ForEach-Object { [regex]::Replace($_, "\x1b\[[0-9;]*m", "") } |
                        Where-Object { $_ -match ': error ' -or $_ -match '##\[error\]' } |
                        ForEach-Object { ($_ -replace '^\s*\S+Z\s+', '').Trim() } |
                        Select-Object -Unique -First $MaxFailuresPerTask)
                }
                catch {
                    [Console]::Error.WriteLine("azp-build-failures: log fetch failed for '$($rec.name)': $_")
                }
            }

            [pscustomobject]@{
                name    = $rec.name
                attempt = $rec.attempt
                issues  = $issues
                logPath = $logPath
                errors  = $errors
            }
        })

    @{
        buildId         = $BuildId
        logsDir         = $WriteDir
        attemptsScanned = @($timelines.attempt)
        failedTaskCount = 0
        buildFailures   = $buildFailures
        tasks           = @()
    } | ConvertTo-Json -Depth 6 -Compress:$false
    exit 0
}

# 2. Download each failing task's raw log to disk + parse for failures.
$tasks = foreach ($t in $failedTasks) {
    $logUrl  = $t.log.url
    $logPath = Join-Path $WriteDir (Get-LogFileName $t)

    try {
        Invoke-WebRequest -Uri $logUrl -OutFile $logPath -UseBasicParsing | Out-Null
    }
    catch {
        [Console]::Error.WriteLine("azp-build-failures: log fetch failed for '$($t.name)' ($($t.attempt)): $_")
        [pscustomobject]@{
            name     = $t.name
            attempt  = $t.attempt
            logUrl   = $logUrl
            logPath  = $null
            failures = @()
            error    = "$_"
        }
        continue
    }

    # Parse failures in both runner formats:
    #   VSTest adapter : "<ts>  Failed <Test>(...) [123 ms]"  then an "Error Message:" header
    #   MS.Testing.Pf  : "<ts> failed <Test>(...) (1m 23s 456ms)" (ANSI-colored) then the message
    #                     on the immediately-following lines (no "Error Message:" header)
    $lines = Get-Content -LiteralPath $logPath
    $failures = @()
    for ($i = 0; $i -lt $lines.Count -and $failures.Count -lt $MaxFailuresPerTask; $i++) {
        # MTP colorizes output - strip ANSI SGR codes before matching.
        $clean = [regex]::Replace($lines[$i], "\x1b\[[0-9;]*m", "")

        $m = [regex]::Match($clean, '^\s*\S+\s+Failed\s+(?<test>\S.*?)\s+\[\d+(\.\d+)?\s*m?s\]\s*$')
        if (-not $m.Success) {
            $m = [regex]::Match($clean, '^\s*\S+\s+failed\s+(?<test>\S.*?)\s+\([\dhms\s\.]+\)\s*$')
        }
        if (-not $m.Success) { continue }

        $testName = $m.Groups['test'].Value.Trim()
        $errMessage = $null

        # Headline error: skip the optional "Error Message:" header (VSTest) and take the
        # first non-empty following line (works for MTP, which has no header).
        for ($j = $i + 1; $j -lt [Math]::Min($i + 8, $lines.Count); $j++) {
            $candidate = ([regex]::Replace($lines[$j], "\x1b\[[0-9;]*m", "") -replace '^\s*\S+Z\s+', '').Trim()
            if (-not $candidate)                     { continue }
            if ($candidate -match '^Error Message:$') { continue }
            $errMessage = $candidate
            break
        }

        $failures += [pscustomobject]@{
            test         = $testName
            errorMessage = $errMessage
        }
    }

    # The runner prints a per-dll "Test run summary" block with a "failed: N" line.
    # Parse it so the caller can tell a full list from one truncated at MaxFailuresPerTask
    # (the failures[] loop stops at the cap; a bare count of 20 is otherwise indistinguishable
    # from a genuine 20). Sum across dlls in case a task runs more than one.
    $reportedFailed = 0
    foreach ($line in $lines) {
        $clean = [regex]::Replace($line, "\x1b\[[0-9;]*m", "") -replace '^\s*\S+Z\s+', ''
        $fm = [regex]::Match($clean, '^\s*failed:\s*(?<n>\d+)\s*$')
        if ($fm.Success) { $reportedFailed += [int]$fm.Groups['n'].Value }
    }

    [pscustomobject]@{
        name                = $t.name
        attempt             = $t.attempt
        logUrl              = $logUrl
        logPath             = $logPath
        reportedFailedTotal = $reportedFailed
        truncated           = ($reportedFailed -gt $failures.Count)
        failures            = $failures
    }
}

# 3. Emit one JSON result.
$result = [ordered]@{
    buildId         = $BuildId
    logsDir         = $WriteDir
    attemptsScanned = @($timelines.attempt)
    failedTaskCount = $failedTasks.Count
    tasks           = @($tasks)
}

$result | ConvertTo-Json -Depth 6
