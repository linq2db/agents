<#
analyzer-profile-report.ps1 — parses a
`dotnet build -v:detailed -p:ReportAnalyzer=true` log produced by
`analyzer-profile-build.ps1` and reports the slowest Roslyn analyzers.

Scans the MSBuild log for `Total analyzer execution time` blocks,
attributes each block to the owning project, and produces three rankings:

  1. Top N slowest (analyzer x project) pairs - where one analyzer is
     particularly painful in one project.
  2. Top N busiest analyzers - sum of time across every project that ran them,
     so analyzers that are uniformly expensive rise to the top.
  3. Top N projects by total analyzer time - which projects dominate the build
     cost overall.

The log MUST be produced with detailed verbosity (`-v:detailed`). Normal
verbosity filters /reportanalyzer output (MessageImportance.Low) out of
the MSBuild log entirely and the report won't appear.

Project attribution strategy: for each report, scan preceding lines (no bound)
and accept the first match among, in priority order:
  1. `N:M>CoreCompile:`                                   (short target header)
  2. `N:M>Target "CoreCompile" in file ... from project "X.csproj"`  (long header)
  3. `/out:...\X.dll`                                     (csc command line)
  4. `Compilation request X`                              (build server line)
The unbounded scan is necessary because projects emit thousands of
diagnostic-info lines between the target header and the report.

`-Own` adds a fourth section: one row per **linq2db-authored** analyzer
(`CodeGenerators.*` internal rules, `LinqToDB.Analyzers.*` shipped rules) with
its time, its share of the scoped project's analyzer CPU, its rank among all
analyzers there, its delta against a committed baseline, and a verdict — plus
a TOTAL row across all of ours. This is the `rules` mode of
`/profile-analyzers`; see `.claude/docs/authoring-analyzers.md` -> "Measuring a
rule's build-time cost".

Verdict thresholds (all parameters; the defaults are judgement calls, recorded
here so a future run can argue with the number rather than rediscover it):
  -SharePct       5   a single rule taking >= 5% of one project's analyzer CPU
                      is disproportionate for a rule with one narrow trigger
  -TopRank       10   the rule is among the project's 10 most expensive
                      analyzers. Catches a genuinely costly *new* rule that the
                      share test misses because the cost is spread over
                      hundreds of analyzers; needs no baseline, so it is the
                      only arm that can fire on a rule's first measurement.
                      Suppressed below -TopRankMinAnalyzers (20) reported
                      analyzers, where a rank carries no information.
  -RegressionPct  50  >= +50% vs baseline, AND >= +0.5s absolute so sub-second
                      run-to-run noise does not read as a regression

Deliberately NOT a threshold: a multiple of the project's *median* analyzer
time. The first real run refuted it - on Source/LinqToDB the median across 565
analyzers is 0.058s, because most analyzers do nothing on any given project, so
LINQ2DB0001 came back 6.8x the median while costing 0.07% of the build. An arm
that fires on every rule which does any work at all is noise, and noise in a
verdict column trains the reader to ignore it. The median is still reported as
context.

Regression fixture — re-run it after changing any threshold or the -Own logic.
`testdata/analyzer-profile-report.fixture.log` is a hand-built two-project log
whose numbers are chosen so each arm fires alone; a change that makes every row
`ok` (or every row `investigate`) has broken the discrimination, not improved it.

  ./analyzer-profile-report.ps1 -LogPath testdata/analyzer-profile-report.fixture.log `
      -Own -Project Tests -Target Tests.Linq `
      -BaselinePath testdata/analyzer-profile-report.fixture-baseline.json

  expected: L2DB1003 investigate (rank 6/21 only - share 4.64% is under the 5%
            arm, so this row proves the rank arm in isolation), L2DB1001 ok
            (rank 14/21), L2DB1002 ok, TOTAL 10.000s / 6.62%, L2DB1099 listed
            as present-in-baseline-but-absent-from-run.

  ./analyzer-profile-report.ps1 -LogPath testdata/analyzer-profile-report.fixture.log -Own -Project LinqToDB

  expected: LINQ2DB0001 investigate on *share* (25.64%) and NOT on rank, though
            it is 3rd of 4 - the -TopRankMinAnalyzers guard suppresses ranking
            below 20 analyzers. Also exercises the no-baseline path.

  Regression arm: edit the fixture baseline's L2DB1002 entry to 0.400 (-> +150%
  / +0.600s, investigate) and to 0.650 (-> +54% / +0.350s, still ok because the
  +0.5s absolute floor holds). Restore it afterwards.

Default mode: pretty tables on stdout for human consumption.
`-AsJson` mode: single JSON object to stdout (per script-authoring conventions).

Conventions: `.claude/docs/script-authoring.md`.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$LogPath,
    [int]    $Top = 10,
    [switch] $AsJson,

    # -- `rules` mode ---------------------------------------------------------
    [switch] $Own,
    [string] $OwnPattern = '^(CodeGenerators|LinqToDB\.Analyzers)\.',
    # Project report to scope the own-analyzer section to (csproj leaf name,
    # e.g. `LinqToDB`, `Tests`). Omit when the log holds exactly one report.
    [string] $Project,
    # Baseline key for this measurement (e.g. `LinqToDB`, `Tests.Linq`).
    # Defaults to the resolved project name.
    [string] $Target,
    [string] $BaselinePath,
    [switch] $UpdateBaseline,
    [string] $BuildCommand,
    [string] $MachineNote = 'captured on the maintainer Windows dev box; cross-machine deltas are directional only',
    [double] $SharePct      = 5.0,
    [int]    $TopRank       = 10,
    [int]    $TopRankMinAnalyzers = 20,
    [double] $RegressionPct = 50.0,
    [double] $RegressionFloorSeconds = 0.5
)

$global:ScriptBaseName = 'analyzer-profile-report'
. (Join-Path $PSScriptRoot '_shared.ps1')

if (-not (Test-Path -LiteralPath $LogPath)) { Exit-WithError "Log not found: $LogPath" }

# Normalise both paths against $PWD before any [System.IO.*] call. PowerShell's
# Test-Path / Get-Content resolve relative paths against $PWD, but the .NET file
# APIs resolve against Environment.CurrentDirectory, which `Push-Location` does
# not move. Mixing them means a relative -LogPath passes the check above and
# then throws on read - and, worse, a relative -BaselinePath is *read* from one
# directory and *written* to another. Same root cause as the git-cwd note by
# Invoke-Git below; see script-authoring.md -> Push-Location.
$LogPath = (Resolve-Path -LiteralPath $LogPath).Path
if ($BaselinePath -and -not [System.IO.Path]::IsPathRooted($BaselinePath)) {
    $BaselinePath = [System.IO.Path]::GetFullPath((Join-Path $PWD.Path $BaselinePath))
}

$lines = [System.IO.File]::ReadAllLines($LogPath)

# -- regexes -----------------------------------------------------------------

$reIsBuilding   = [regex]'is building "([^"]+\.csproj)" \((\d+:\d+)\)'
$reProjectStart = [regex]'Project "([^"]+\.csproj)" \((\d+:\d+)\)'
$reCoreShort    = [regex]'^\s*(\d+:\d+)>CoreCompile:'
$reCoreLong     = [regex]'^\s*(\d+:\d+)>Target "CoreCompile" in file ".*?" from project "([^"]+\.csproj)"'
$reRow          = [regex]'^\s+(<?\d+\.\d+|<0\.\d+)\s+(<?\d+)\s+(\S.*)$'
$reCompReq      = [regex]'Compilation request (\S+) \('
$reOutDll       = [regex]'/out:(?:[^ ]*\\)?([A-Za-z0-9_.]+)\.dll\b'
$reTotal        = [regex]'Total analyzer execution time: ([\d.]+) seconds'

# -- pass 1: PID -> project name --------------------------------------------

$projects = @{}
foreach ($line in $lines) {
    $m = $reIsBuilding.Match($line)
    if ($m.Success) {
        $leaf = [IO.Path]::GetFileNameWithoutExtension($m.Groups[1].Value)
        $projects[$m.Groups[2].Value] = $leaf
        continue
    }
    $m = $reProjectStart.Match($line)
    if ($m.Success -and -not $projects.ContainsKey($m.Groups[2].Value)) {
        $leaf = [IO.Path]::GetFileNameWithoutExtension($m.Groups[1].Value)
        $projects[$m.Groups[2].Value] = $leaf
    }
}

# -- attribution helper ------------------------------------------------------

function Resolve-Project([int]$fromIndex) {
    for ($j = $fromIndex; $j -ge 0; $j--) {
        $line = $lines[$j]
        $m = $reCoreShort.Match($line)
        if ($m.Success) {
            $id = $m.Groups[1].Value
            if ($projects.ContainsKey($id)) { return $projects[$id] }
        }
        $m = $reCoreLong.Match($line)
        if ($m.Success) { return [IO.Path]::GetFileNameWithoutExtension($m.Groups[2].Value) }
        $m = $reOutDll.Match($line)
        if ($m.Success) { return $m.Groups[1].Value }
        $m = $reCompReq.Match($line)
        if ($m.Success) { return $m.Groups[1].Value }
    }
    return 'unknown'
}

# -- pass 2: collect reports -------------------------------------------------

$pairs         = [System.Collections.Generic.List[psobject]]::new()
$projectTotals = [System.Collections.Generic.List[psobject]]::new()
$analyzerSums  = @{}
$analyzerHits  = @{}

$i = 0
while ($i -lt $lines.Length) {
    if ($lines[$i].Contains('Total analyzer execution time')) {
        $mt = $reTotal.Match($lines[$i])
        $totalS = if ($mt.Success) { [double]$mt.Groups[1].Value } else { 0.0 }
        $projectName = Resolve-Project $i
        $projectTotals.Add([pscustomobject]@{ Time = $totalS; Project = $projectName })

        # skip to first data row (after the "Time (s)" header line)
        $j = $i + 1
        while ($j -lt $lines.Length -and -not $lines[$j].Contains('Time (s)')) { $j++ }
        $j++

        $blank = 0
        while ($j -lt $lines.Length) {
            $row = $lines[$j].TrimEnd()
            if ($row.Trim() -eq '') {
                $blank++
                if ($blank -ge 3) { break }
                $j++; continue
            }
            if ($row -match '^\s*\d+:\d+>' -or $row -match 'Build (succeeded|FAILED)') { break }
            $mm = $reRow.Match($row)
            if (-not $mm.Success) { break }
            $blank = 0
            $timeStr = $mm.Groups[1].Value
            $name    = $mm.Groups[3].Value.Trim()
            $tVal = if ($timeStr.StartsWith('<')) { 0.0005 } else { [double]$timeStr }

            # Skip the assembly-level aggregate row (e.g. "Microsoft.CodeAnalysis.CSharp.CodeStyle, Version=...")
            if ($name -like '*, Version=*') { $j++; continue }

            $pairs.Add([pscustomobject]@{ Time = $tVal; Project = $projectName; Analyzer = $name })
            if (-not $analyzerSums.ContainsKey($name)) {
                $analyzerSums[$name] = 0.0
                $analyzerHits[$name] = 0
            }
            $analyzerSums[$name] += $tVal
            $analyzerHits[$name] += 1
            $j++
        }
        $i = $j
    } else {
        $i++
    }
}

# -- formatting helper -------------------------------------------------------

function Split-Analyzer([string]$n) {
    $idx = $n.IndexOf('(')
    if ($idx -ge 0) {
        $head = $n.Substring(0, $idx).Trim()
        $rules = $n.Substring($idx)
    } else {
        $head = $n.Trim()
        $rules = ''
    }
    $parts = $head -split '\.'
    [pscustomobject]@{ Short = $parts[-1]; Rules = $rules }
}

# -- rankings ----------------------------------------------------------------

$slowestPairs = $pairs |
    Sort-Object Time -Descending |
    Select-Object -First $Top |
    ForEach-Object -Begin { $rank = 0 } -Process {
        $rank++
        $sa = Split-Analyzer $_.Analyzer
        [pscustomobject]@{
            Rank     = $rank
            Time_s   = [Math]::Round($_.Time, 3)
            Project  = $_.Project
            Analyzer = $sa.Short
            Rules    = $sa.Rules
        }
    }

$busiest = $analyzerSums.Keys |
    Sort-Object { - $analyzerSums[$_] } |
    Select-Object -First $Top |
    ForEach-Object -Begin { $rank = 0 } -Process {
        $rank++
        $name  = $_
        $hits  = $analyzerHits[$name]
        $total = $analyzerSums[$name]
        $sa    = Split-Analyzer $name
        [pscustomobject]@{
            Rank     = $rank
            Total_s  = [Math]::Round($total, 3)
            Projects = $hits
            Avg_s    = [Math]::Round($total / [Math]::Max(1, $hits), 3)
            Analyzer = $sa.Short
            Rules    = $sa.Rules
        }
    }

$projectRanking = $projectTotals |
    Sort-Object Time -Descending |
    Select-Object -First $Top |
    ForEach-Object -Begin { $rank = 0 } -Process {
        $rank++
        [pscustomobject]@{
            Rank    = $rank
            Time_s  = [Math]::Round($_.Time, 3)
            Project = $_.Project
        }
    }

# -- own-analyzer section (`rules` mode) -------------------------------------

$ownReport = $null

if ($Own) {
    if ($UpdateBaseline -and -not $BaselinePath) {
        Exit-WithError '-UpdateBaseline requires -BaselinePath' `
            -NextAction 'pass -BaselinePath .claude/docs/analyzer-own-perf-baseline.json'
    }

    # Scope to one project report. The whole point of `rules` mode is "what does
    # this rule cost on the corpus it actually runs over", so an unscoped sum
    # across a multi-project log would mix targets and make the share figure
    # meaningless.
    $reportedProjects = @($projectTotals | Select-Object -ExpandProperty Project -Unique)
    $scopeProject = $Project
    if (-not $scopeProject) {
        if ($reportedProjects.Count -eq 1) {
            $scopeProject = $reportedProjects[0]
        } else {
            Exit-WithError ("log holds {0} project reports ({1}); -Own needs one" -f `
                    $reportedProjects.Count, (($reportedProjects | Select-Object -First 8) -join ', ')) `
                -NextAction 'pass -Project <csproj leaf name> to select the target project report'
        }
    }
    if ($reportedProjects -notcontains $scopeProject) {
        Exit-WithError ("no analyzer report for project '{0}' in the log (have: {1})" -f `
                $scopeProject, (($reportedProjects | Select-Object -First 8) -join ', ')) `
            -NextAction 'check the -Project name against the csproj leaf name, or rebuild with -t:Rebuild so CoreCompile runs for it'
    }
    if (-not $Target) { $Target = $scopeProject }

    $scopeRows = @($pairs | Where-Object { $_.Project -eq $scopeProject } | Sort-Object Time -Descending)
    $scopeTotal = ($projectTotals | Where-Object { $_.Project -eq $scopeProject } |
        Measure-Object -Property Time -Sum).Sum
    if (-not $scopeTotal) { $scopeTotal = 0.0 }

    # Median per-analyzer time in this project — the second yardstick, for a
    # project whose total is small enough that the share test stays quiet.
    $median = 0.0
    if ($scopeRows.Count -gt 0) {
        $sorted = @($scopeRows | Sort-Object Time | Select-Object -ExpandProperty Time)
        $mid = [int][Math]::Floor($sorted.Count / 2)
        $median = if ($sorted.Count % 2 -eq 1) { $sorted[$mid] } else { ($sorted[$mid - 1] + $sorted[$mid]) / 2 }
    }

    # -- baseline ------------------------------------------------------------
    $baseline      = $null
    $baselineEntry = $null
    if ($BaselinePath -and (Test-Path -LiteralPath $BaselinePath)) {
        try {
            $baseline = (Get-Content -Raw -LiteralPath $BaselinePath) | ConvertFrom-Json -Depth 20
        } catch {
            Exit-WithError "invalid JSON in ${BaselinePath}: $($_.Exception.Message)" `
                -NextAction "fix the JSON in $BaselinePath, or delete it to re-capture from scratch"
        }
        if ($baseline.targets -and $baseline.targets.PSObject.Properties.Name -contains $Target) {
            $baselineEntry = $baseline.targets.$Target
        }
    }
    $baselineTimes = @{}
    if ($baselineEntry) {
        foreach ($a in @($baselineEntry.analyzers)) { $baselineTimes[$a.analyzer] = [double]$a.totalSeconds }
    }

    # -- rows ----------------------------------------------------------------
    $ownRows = [System.Collections.Generic.List[psobject]]::new()
    for ($r = 0; $r -lt $scopeRows.Count; $r++) {
        $row = $scopeRows[$r]
        if ($row.Analyzer -cnotmatch $OwnPattern) { continue }

        $sa    = Split-Analyzer $row.Analyzer
        $share = if ($scopeTotal -gt 0) { 100.0 * $row.Time / $scopeTotal } else { 0.0 }

        $was      = $null
        $delta    = $null
        $deltaPct = $null
        if ($baselineEntry) {
            if ($baselineTimes.ContainsKey($row.Analyzer)) {
                $was   = $baselineTimes[$row.Analyzer]
                $delta = $row.Time - $was
                if ($was -gt 0) { $deltaPct = 100.0 * $delta / $was }
            }
        }

        $reasons = @()
        if ($share -ge $SharePct) { $reasons += ("share {0:N1}% >= {1:N1}%" -f $share, $SharePct) }
        if ($scopeRows.Count -ge $TopRankMinAnalyzers -and ($r + 1) -le $TopRank) {
            $reasons += ("rank {0} of {1} analyzers on this project" -f ($r + 1), $scopeRows.Count)
        }
        if ($null -ne $deltaPct -and $deltaPct -ge $RegressionPct -and $delta -ge $RegressionFloorSeconds) {
            $reasons += ("+{0:N0}% vs baseline (+{1:N3}s)" -f $deltaPct, $delta)
        }

        $ownRows.Add([pscustomobject]@{
            analyzer     = $row.Analyzer
            short        = $sa.Short
            rules        = $sa.Rules
            seconds      = [Math]::Round($row.Time, 3)
            sharePct     = [Math]::Round($share, 2)
            rank         = $r + 1
            baseline     = if ($null -ne $was)   { [Math]::Round($was, 3) }   else { $null }
            deltaSeconds = if ($null -ne $delta) { [Math]::Round($delta, 3) } else { $null }
            deltaPct     = if ($null -ne $deltaPct) { [Math]::Round($deltaPct, 1) } else { $null }
            verdict      = if ($reasons.Count -gt 0) { 'investigate' } else { 'ok' }
            reasons      = @($reasons)
        })
    }

    # Rules present in the baseline but absent from this run: removed, renamed,
    # or simply not loaded — say so rather than silently dropping them.
    $missing = @()
    if ($baselineEntry) {
        $seen = @($ownRows | Select-Object -ExpandProperty analyzer)
        foreach ($k in $baselineTimes.Keys) { if ($seen -notcontains $k) { $missing += $k } }
    }

    $ownTotal = 0.0
    foreach ($o in $ownRows) { $ownTotal += $o.seconds }

    $context = @($scopeRows |
        Where-Object { $_.Analyzer -cnotmatch $OwnPattern } |
        Select-Object -First 3 |
        ForEach-Object { [pscustomobject]@{ analyzer = (Split-Analyzer $_.Analyzer).Short; seconds = [Math]::Round($_.Time, 3) } })

    $ownReport = [pscustomobject]@{
        target              = $Target
        project             = $scopeProject
        analyzers           = @($ownRows)
        totalSeconds        = [Math]::Round($ownTotal, 3)
        totalSharePct       = if ($scopeTotal -gt 0) { [Math]::Round(100.0 * $ownTotal / $scopeTotal, 2) } else { 0.0 }
        projectTotalSeconds = [Math]::Round($scopeTotal, 3)
        projectAnalyzers    = $scopeRows.Count
        medianSeconds       = [Math]::Round($median, 3)
        baselineFound       = [bool]$baselineEntry
        baselineCapturedOn  = if ($baselineEntry) { $baselineEntry.capturedOn } else { $null }
        missingFromRun      = @($missing)
        topOtherAnalyzers   = @($context)
        thresholds          = @{ sharePct = $SharePct; topRank = $TopRank; topRankMinAnalyzers = $TopRankMinAnalyzers; regressionPct = $RegressionPct; regressionFloorSeconds = $RegressionFloorSeconds }
        baselineUpdated     = $false
    }

    # -- write-back ----------------------------------------------------------
    if ($UpdateBaseline) {
        # Resolve the commit against $PWD explicitly. Invoke-Process leaves
        # WorkingDirectory unset, so the child git inherits the *process*
        # Environment.CurrentDirectory - which `Push-Location` does not move.
        # Measuring a worktree from a host whose location was pushed there then
        # stamps the baseline with the primary clone's HEAD, i.e. a commit the
        # numbers were never taken on. (Hit on the first real capture.)
        $commit = $null
        $g = Invoke-Git @('rev-parse', '--short', 'HEAD') -WorkingDirectory $PWD.Path
        if ($g.ok) { $commit = $g.stdout.Trim() }

        if (-not $baseline) { $baseline = [pscustomobject]@{ schema = 1; machineNote = $MachineNote; targets = [pscustomobject]@{} } }
        if (-not $baseline.PSObject.Properties.Name.Contains('targets')) {
            $baseline | Add-Member -NotePropertyName targets -NotePropertyValue ([pscustomobject]@{})
        }

        $entry = [pscustomobject]@{
            capturedOn          = (Get-Date).ToString('yyyy-MM-dd')
            commit              = $commit
            buildCommand        = $BuildCommand
            project             = $scopeProject
            projectTotalSeconds = [Math]::Round($scopeTotal, 3)
            analyzers           = @($ownRows | ForEach-Object {
                    [pscustomobject]@{ analyzer = $_.analyzer; rules = $_.rules; totalSeconds = $_.seconds }
                })
        }
        if ($baseline.targets.PSObject.Properties.Name -contains $Target) {
            $baseline.targets.$Target = $entry
        } else {
            $baseline.targets | Add-Member -NotePropertyName $Target -NotePropertyValue $entry
        }

        $dir = Split-Path -Parent $BaselinePath
        if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        [System.IO.File]::WriteAllText(
            $BaselinePath,
            (($baseline | ConvertTo-Json -Depth 20) + "`n"),
            (New-Object System.Text.UTF8Encoding $false))
        $ownReport.baselineUpdated = $true
    }
}

# -- output ------------------------------------------------------------------

if ($AsJson) {
    $payload = @{
        ok               = $true
        action           = 'report'
        slowestPairs     = @($slowestPairs)
        busiestAnalyzers = @($busiest)
        projectTotals    = @($projectRanking)
        diagnostics      = @{
            pairRows       = $pairs.Count
            projectReports = $projectTotals.Count
            analyzers      = $analyzerSums.Count
        }
    }
    if ($ownReport) { $payload['own'] = $ownReport }
    Write-JsonOutput $payload
    return
}

# Pretty mode: tables to stdout for human reading.
Write-Host ("Per-analyzer rows: {0}   Project reports: {1}   Distinct analyzers: {2}" -f `
    $pairs.Count, $projectTotals.Count, $analyzerSums.Count)

# The `rules`-mode answer goes first: it is what the caller invoked for, and the
# three whole-log rankings below are context for it. Emitted as markdown so it
# can be pasted verbatim into the PR body that records the measurement. ASCII
# only — captured stdout decodes via the console code page, not UTF-8.
if ($ownReport) {
    Write-Host ''
    Write-Host ("### Analyzer build-time cost - {0} (project '{1}')" -f $ownReport.target, $ownReport.project)
    Write-Host ''
    if ($ownReport.analyzers.Count -eq 0) {
        Write-Host ("No linq2db-authored analyzer ran on '{0}'. Pattern: {1}" -f $ownReport.project, $OwnPattern)
        Write-Host 'If a rule was expected here, the analyzer is not attached to that project - see authoring-analyzers.md -> Measuring a rule''s build-time cost.'
    } else {
        Write-Host '| Analyzer | Rules | Time(s) | % of proj | Rank | Delta vs base | Verdict |'
        Write-Host '|---|---|--:|--:|--:|--:|---|'
        foreach ($o in $ownReport.analyzers) {
            $deltaCell =
                if (-not $ownReport.baselineFound)   { 'n/a' }
                elseif ($null -eq $o.baseline) { 'new' }
                else { '{0}{1:N3}s ({2}{3:N0}%)' -f $(if ($o.deltaSeconds -ge 0) { '+' } else { '' }), $o.deltaSeconds, $(if ($o.deltaPct -ge 0) { '+' } else { '' }), $o.deltaPct }
            Write-Host ('| {0} | {1} | {2:N3} | {3:N2}% | {4}/{5} | {6} | {7} |' -f `
                $o.short, $o.rules, $o.seconds, $o.sharePct, $o.rank, $ownReport.projectAnalyzers, $deltaCell, $o.verdict)
        }
        Write-Host ('| **TOTAL (ours)** | | **{0:N3}** | **{1:N2}%** | | | |' -f $ownReport.totalSeconds, $ownReport.totalSharePct)
        Write-Host ''
        foreach ($o in $ownReport.analyzers) {
            if ($o.verdict -eq 'investigate') { Write-Host ("  investigate {0}: {1}" -f $o.short, ($o.reasons -join '; ')) }
        }
    }
    Write-Host ''
    $ctx = ($ownReport.topOtherAnalyzers | ForEach-Object { '{0} {1:N3}s' -f $_.analyzer, $_.seconds }) -join ', '
    Write-Host ("{0} total analyzer CPU {1:N1}s across {2} analyzers (median {3:N3}s); top third-party: {4}" -f `
        $ownReport.project, $ownReport.projectTotalSeconds, $ownReport.projectAnalyzers, $ownReport.medianSeconds, $ctx)
    if (-not $ownReport.baselineFound) {
        Write-Host ("No baseline entry for target '{0}' - this run is the initial capture, not a delta." -f $ownReport.target)
    } else {
        Write-Host ("Baseline captured {0}." -f $ownReport.baselineCapturedOn)
        if ($ownReport.missingFromRun.Count -gt 0) {
            Write-Host ("In baseline but absent from this run (removed / renamed / not loaded): {0}" -f ($ownReport.missingFromRun -join ', '))
        }
    }
    if ($ownReport.baselineUpdated) { Write-Host ("Baseline updated: {0}" -f $BaselinePath) }
    Write-Host ''
}

Write-Host ''
Write-Host ('=' * 120)
Write-Host ("TOP {0} SLOWEST  (analyzer x project)  by per-analyzer time" -f $Top)
Write-Host ('=' * 120)
$slowestPairs | Format-Table Rank, @{Name='Time(s)'; Expression='Time_s'; Alignment='right'}, Project, Analyzer, Rules -AutoSize | Out-Host

Write-Host ('=' * 120)
Write-Host ("TOP {0} BUSIEST analyzers (sum across measured projects)" -f $Top)
Write-Host ('=' * 120)
$busiest | Format-Table Rank, @{Name='Total(s)'; Expression='Total_s'; Alignment='right'}, Projects, @{Name='Avg(s)'; Expression='Avg_s'; Alignment='right'}, Analyzer, Rules -AutoSize | Out-Host

Write-Host ('=' * 120)
Write-Host ("TOP {0} projects by total analyzer time" -f $Top)
Write-Host ('=' * 120)
$projectRanking | Format-Table Rank, @{Name='Time(s)'; Expression='Time_s'; Alignment='right'}, Project -AutoSize | Out-Host
