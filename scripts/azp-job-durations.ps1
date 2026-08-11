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

Invoke directly via the PowerShell tool (preferred), NOT wrapped in Bash:

    .claude\scripts\azp-job-durations.ps1 -Definition test-all -JobFilter YDB
    .claude\scripts\azp-job-durations.ps1 -Definition test-all -JobFilter YDB -Top 20
    .claude\scripts\azp-job-durations.ps1 -Definition 4 -JobFilter 'Firebird' -Branch refs/heads/master

Output: single JSON document on stdout — the resolved definition, then one
`records[]` entry per matched timeline record (build id, source branch/sha, the
record's name / type / result, and minutes), newest build first.
#>

param(
    [Parameter(Mandatory)][string]$Definition,
    [Parameter(Mandatory)][string]$JobFilter,
    [int]$Top = 10,
    [string]$Branch,
    [string]$Org = 'linq2db',
    [string]$Project = '0dcc414b-ea54-451e-a54f-d63f05367c4b'
)

$global:ScriptBaseName = 'azp-job-durations'
. "$PSScriptRoot/_shared.ps1"

$apiBase = "https://dev.azure.com/$Org/$Project/_apis/build"

# --- resolve the definition (numeric id passes through, name is looked up) ----
$defId   = 0
$defName = $Definition
if ([int]::TryParse($Definition, [ref]$defId) -and $defId -gt 0) {
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

# --- list recent builds -------------------------------------------------------
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

# --- per build: fetch the timeline and match records --------------------------
$needle  = $JobFilter.ToLowerInvariant()
$records = @()

foreach ($b in $builds.value) {
    try {
        $timeline = Invoke-RestMethod -Uri "$apiBase/builds/$($b.id)/timeline?api-version=7.0"
    }
    catch {
        # A build can be too old to retain a timeline, or purged. Skip it rather
        # than failing the whole comparison — the remaining builds still answer
        # the question.
        continue
    }

    foreach ($r in $timeline.records) {
        if (-not $r.name) { continue }
        if (-not $r.name.ToLowerInvariant().Contains($needle)) { continue }

        $minutes = $null
        if ($r.startTime -and $r.finishTime) {
            $minutes = [math]::Round((([datetime]$r.finishTime) - ([datetime]$r.startTime)).TotalMinutes, 1)
        }

        $records += [pscustomobject]@{
            buildId = $b.id
            branch  = $b.sourceBranch
            sha     = if ($b.sourceVersion) { $b.sourceVersion.Substring(0, [math]::Min(8, $b.sourceVersion.Length)) } else { $null }
            started = $b.startTime
            name    = $r.name
            type    = $r.type
            result  = $r.result
            minutes = $minutes
        }
    }
}

if ($records.Count -eq 0) {
    Exit-WithError "no timeline record in the last $Top build(s) of '$Definition' matches '$JobFilter'" `
        -NextAction "widen -JobFilter (it is a case-insensitive substring of the record name), raise -Top, or try a different -Definition"
}

Write-JsonOutput ([pscustomobject]@{
    definition = [pscustomobject]@{ id = $defId; name = $defName }
    jobFilter  = $JobFilter
    branch     = $Branch
    buildsScanned = @($builds.value).Count
    records    = @($records)
})
