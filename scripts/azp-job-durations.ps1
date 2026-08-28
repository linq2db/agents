<#
Compare Azure DevOps job / task **durations** across recent builds on the linq2db
project — the "did this actually make CI faster?" question.

Complements the other azp scripts, none of which report timing:
  azp-build-failures.ps1  -> per-test failures of a failed build
  azp-step-log.ps1        -> one named step's raw log
  azp-run.ps1             -> trigger a pipeline

Answers questions of the shape "the PR claims provider X's tests got N% faster —
did they?" by pulling each build's /timeline and computing finishTime-startTime
for every record whose name matches -JobFilter. Without this the sequence is a
hand-rolled definitions -> builds -> per-build timeline -> filter -> subtract
chain (4+ prompt-prone calls, and the obvious pwsh one-liner form trips the
"empty pipe element" parser error).

The `dev.azure.com/linq2db` build API is publicly readable (no auth).

Resolving -Definition: pass the pipeline **name** as shown by `gh pr checks`
(`test-all`, `build`, `test-ydb`, `default`, ...) or its numeric id. Names are
matched case-insensitively and exactly; the script lists the available names when
no match is found. Note that a provider's tests often run inside `test-all`
rather than its own `test-<provider>` pipeline, and the per-provider pipeline may
hold only a handful of manually-triggered runs — for a before/after comparison
`test-all` is usually the definition with a usable run history.

Duration caveats. Job-level records include agent acquisition and workspace
setup, so the narrower **Task** record is the better signal for "did the tests
themselves get faster"; the output carries `type` so you can filter. Records
still running have no finishTime and report a null duration. Queue delay is not
included (startTime is when the record began, not when the build was queued).
A single build is one sample on shared hosted agents — read a band across
several builds, never a single pair.

-WithTestCounts adds the other half of a valid comparison: the **test count** of
each matched Task, parsed from the runner's summary block in that task's own log.
The suite's size drifts between runs, so a duration delta between builds with
different counts is not evidence — pair builds whose `tests` match before drawing
any conclusion. Costs one log download per matched Task, so combine it with a
narrow -JobFilter. Logs land under -WriteDir for follow-up Read / Grep.

Note the log is always resolved from that build's own timeline: Azure log ids are
**per build**, so a log id carried across builds silently returns a different
job's output (see ci-tests.md).

-Offsets answers the other timing question, *within* one build: when did each job
start and finish relative to the run, rather than how long did it take. That is
what every dispatch-order / slot-packing claim turns on — "the long legs start
last and finish alone", "job A finishes before job B so its dependents are not
delayed", "leg X started N minutes in and became the tail" — and a duration
column cannot answer any of them. Pair it with -BuildId and a broad -JobFilter.

Two traps it exists to encode, both of which produce confidently wrong numbers:

  * The origin is **min(job startTime)**, never the build's own `startTime`. A
    build that was partially re-run ("rerun failed jobs") carries a much later
    `startTime` than its surviving job records, so build-relative offsets come
    out **negative** and the span is nonsense — build 23063 measured a 305.9 min
    span and a `Build` that finished 218 min "before" the build began, against a
    real 148.4 min end to end.
  * A job's `displayName` can be **renamed mid-branch**, so an exact-name filter
    silently reports the job as absent from the earlier builds rather than
    renamed. -JobFilter is a case-insensitive substring for this reason: filter
    on the stable fragment ('x86', not 'Build (win-x86)'). Reading "no match" as
    "the job did not exist yet" is the failure mode — on PR #5819 the job was
    `Build (win-x86 test artifacts)` until a rename, and an exact filter made two
    builds look like they predated the job entirely.

The `dev.azure.com/linq2db` build API is publicly readable, so -BuildId works for
any build in the project, including green ones (azp-build-failures.ps1 is
failures-only and has nothing to say about a build that passed).

Invoke directly via the PowerShell tool (preferred), NOT wrapped in Bash:

    .claude\scripts\azp-job-durations.ps1 -Definition test-all -JobFilter YDB
    .claude\scripts\azp-job-durations.ps1 -Definition test-all -JobFilter YDB -Top 20
    .claude\scripts\azp-job-durations.ps1 -Definition 4 -JobFilter 'Firebird' -Branch refs/heads/master
    .claude\scripts\azp-job-durations.ps1 -Definition test-all -JobFilter 'Tests (.NET 10): DB2' -WithTestCounts
    .claude\scripts\azp-job-durations.ps1 -BuildId 23050 -Offsets
    .claude\scripts\azp-job-durations.ps1 -BuildId 23050,23068 -JobFilter x86 -Offsets

Output: single JSON document on stdout — the resolved definition, then one
`records[]` entry per matched timeline record (build id, source branch/sha, the
record's name / type / result, and minutes), newest build first. With
-WithTestCounts, matched Task records also carry `tests` / `skipped` /
`testDuration` / `logPath`. With -Offsets, each record also carries
`startOffset` / `endOffset` in minutes from its build's origin, and a `builds[]`
array reports each build's `origin` / `span` / `partialRerun`.
#>

param(
    [string]$Definition,
    [string]$JobFilter = '',
    [int[]]$BuildId,
    [switch]$Offsets,
    [int]$Top = 10,
    [string]$Branch,
    [switch]$WithTestCounts,
    [string]$WriteDir,
    [string]$Org = 'linq2db',
    [string]$Project = '0dcc414b-ea54-451e-a54f-d63f05367c4b'
)

$global:ScriptBaseName = 'azp-job-durations'
. "$PSScriptRoot/_shared.ps1"

$apiBase = "https://dev.azure.com/$Org/$Project/_apis/build"

if (-not $Definition -and -not $BuildId) {
    Exit-WithError "neither -Definition nor -BuildId was supplied" `
        -NextAction "pass -Definition <name|id> to scan a pipeline's recent builds, or -BuildId <n>[,<n>] to target specific builds"
}

if ($WithTestCounts) {
    if (-not $WriteDir) { $WriteDir = '.build/.agents/azp-durations' }
    New-Item -ItemType Directory -Force -Path $WriteDir | Out-Null
}

# Parse the runner's end-of-run summary out of a task log. The count lines are
# ANSI-colorized, so strip escape sequences before matching; the last summary in
# the log wins (a task can host more than one assembly run).
function Get-TestSummary {
    param([string]$LogPath)
    $summary = [ordered]@{}
    foreach ($raw in (Get-Content -LiteralPath $LogPath)) {
        $line = $raw -replace "`e\[[0-9;]*[a-zA-Z]", ''
        if     ($line -match 'total:\s*(\d+)\s*$')   { $summary['tests']        = [int]$Matches[1] }
        elseif ($line -match 'skipped:\s*(\d+)\s*$') { $summary['skipped']      = [int]$Matches[1] }
        elseif ($line -match '\bduration:\s*(\S.*)$'){ $summary['testDuration'] = $Matches[1].Trim() }
    }
    return $summary
}

# --- resolve the definition (numeric id passes through, name is looked up) ----
# Skipped entirely when -BuildId names the builds outright.
$defId   = 0
$defName = $Definition
if ($BuildId) {
    $defId   = 0
    $defName = $null
}
elseif ([int]::TryParse($Definition, [ref]$defId) -and $defId -gt 0) {
    $defName = $null
}
else {
    try {
        $defs = Invoke-RestMethod -Uri "$apiBase/definitions?api-version=7.0"
    }
    catch {
        Exit-WithError "failed to list build definitions: $_"
    }
    $match = @($defs.value | Where-Object { $_.name -ieq $Definition })
    if ($match.Count -eq 0) {
        $known = (($defs.value | Sort-Object name | ForEach-Object { $_.name }) -join ', ')
        Exit-WithError "no build definition named '$Definition'; known definitions: $known" `
            -NextAction "re-invoke with -Definition set to one of the listed names, or its numeric id"
    }
    $defId   = [int]$match[0].id
    $defName = $match[0].name
}

# --- collect the builds to scan -----------------------------------------------
$buildList = @()

if ($BuildId) {
    foreach ($id in $BuildId) {
        try {
            $buildList += Invoke-RestMethod -Uri "$apiBase/builds/${id}?api-version=7.0"
        }
        catch {
            Exit-WithError "failed to fetch build ${id}: $_" `
                -NextAction "check the build id against the pipeline's run list; ids are project-wide, not per definition"
        }
    }
}
else {
    $buildsUri = "$apiBase/builds?definitions=$defId&`$top=$Top&api-version=7.0"
    if ($Branch) { $buildsUri += "&branchName=$([uri]::EscapeDataString($Branch))" }

    try {
        $builds = Invoke-RestMethod -Uri $buildsUri
    }
    catch {
        Exit-WithError "failed to list builds for definition ${defId}: $_"
    }

    if (-not $builds.value -or @($builds.value).Count -eq 0) {
        Exit-WithError "definition '$Definition' (id $defId) has no builds$(if ($Branch) { " on branch $Branch" })" `
            -NextAction "drop -Branch, raise -Top, or pick a definition with run history (test-all usually has one)"
    }
    $buildList = @($builds.value)
}

# --- per build: fetch the timeline and match records --------------------------
$needle    = $JobFilter.ToLowerInvariant()
$records   = @()
$buildInfo = @()

foreach ($b in $buildList) {
    try {
        $timeline = Invoke-RestMethod -Uri "$apiBase/builds/$($b.id)/timeline?api-version=7.0"
    }
    catch {
        # A build can be too old to retain a timeline, or purged. Skip it rather
        # than failing the whole comparison — the remaining builds still answer
        # the question.
        continue
    }

    # Origin for -Offsets: the earliest job start in this build's own timeline.
    # Deliberately not $b.startTime — see the header's note on partially re-run
    # builds, where the build's startTime postdates its surviving job records and
    # every build-relative offset comes out negative.
    $origin = $null
    $span   = $null
    if ($Offsets) {
        $jobStarts = @($timeline.records |
            Where-Object { $_.type -eq 'Job' -and $_.startTime } |
            ForEach-Object { [datetime]$_.startTime })
        if (-not $jobStarts) {
            # A canceled build can carry records with no times at all; fall back to
            # any timed record so the mode degrades rather than throwing.
            $jobStarts = @($timeline.records | Where-Object { $_.startTime } | ForEach-Object { [datetime]$_.startTime })
        }
        if ($jobStarts) {
            $origin  = ($jobStarts | Sort-Object)[0]
            $jobEnds = @($timeline.records |
                Where-Object { $_.type -eq 'Job' -and $_.finishTime } |
                ForEach-Object { [datetime]$_.finishTime } | Sort-Object)
            if ($jobEnds) { $span = [math]::Round(($jobEnds[-1] - $origin).TotalMinutes, 1) }
        }
        $buildInfo += [pscustomobject][ordered]@{
            buildId      = $b.id
            result       = $b.result
            origin       = $origin
            span         = $span
            # The tell for a partially re-run build: the build claims to have begun
            # after its own jobs did, so anything measured from $b.startTime is junk.
            partialRerun = if ($origin -and $b.startTime) { ([datetime]$b.startTime) -gt $origin } else { $null }
            jobsTimed    = @($timeline.records | Where-Object { $_.type -eq 'Job' -and $_.startTime }).Count
        }
    }

    foreach ($r in $timeline.records) {
        if (-not $r.name) { continue }
        if (-not $r.name.ToLowerInvariant().Contains($needle)) { continue }

        $minutes = $null
        if ($r.startTime -and $r.finishTime) {
            $minutes = [math]::Round((([datetime]$r.finishTime) - ([datetime]$r.startTime)).TotalMinutes, 1)
        }

        $entry = [ordered]@{
            buildId = $b.id
            branch  = $b.sourceBranch
            sha     = if ($b.sourceVersion) { $b.sourceVersion.Substring(0, [math]::Min(8, $b.sourceVersion.Length)) } else { $null }
            started = $b.startTime
            name    = $r.name
            type    = $r.type
            result  = $r.result
            minutes = $minutes
        }

        if ($Offsets -and $origin) {
            $entry['startOffset'] = if ($r.startTime)  { [math]::Round((([datetime]$r.startTime)  - $origin).TotalMinutes, 2) } else { $null }
            $entry['endOffset']   = if ($r.finishTime) { [math]::Round((([datetime]$r.finishTime) - $origin).TotalMinutes, 2) } else { $null }
        }

        if ($WithTestCounts -and $r.type -eq 'Task' -and $r.result -eq 'succeeded' -and $r.log -and $r.log.url) {
            $slug    = ($r.name.ToLowerInvariant() -replace '[^a-z0-9]+', '-').Trim('-')
            $logPath = Join-Path $WriteDir "$($b.id)-$slug.log"
            try {
                Invoke-WebRequest -Uri $r.log.url -OutFile $logPath -UseBasicParsing | Out-Null
                foreach ($kv in (Get-TestSummary -LogPath $logPath).GetEnumerator()) { $entry[$kv.Key] = $kv.Value }
                $entry['logPath'] = $logPath
            }
            catch {
                # One unreadable log must not sink the whole comparison.
                $entry['note'] = "log fetch failed: $_"
            }
        }

        $records += [pscustomobject]$entry
    }
}

if ($records.Count -eq 0) {
    $scanned = if ($BuildId) { "build(s) $($BuildId -join ', ')" } else { "the last $Top build(s) of '$Definition'" }
    Exit-WithError "no timeline record in $scanned matches '$JobFilter'" `
        -NextAction "widen -JobFilter to a stable substring of the record name — a job's displayName may have been renamed between the builds you are comparing, which reads as the job being absent; or raise -Top / pick a different -Definition"
}

$output = [ordered]@{
    definition    = [pscustomobject]@{ id = $defId; name = $defName }
    jobFilter     = $JobFilter
    branch        = $Branch
    buildsScanned = @($buildList).Count
}
if ($Offsets) { $output['builds'] = @($buildInfo) }
$output['records'] = @($records)

Write-JsonOutput ([pscustomobject]$output)
