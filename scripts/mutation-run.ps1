#!/usr/bin/env pwsh
<#
Run a filtered test set once unmutated and once per source mutation, restoring every file
byte-exact after each mutation, and report which runs went red.

Why this exists
---------------
A work plan's test obligations name mutations ("dropping X turns test Y red"), and
`work-plan.ps1 -Action validate -Done` fails until each named mutation has a recorded run.
Doing that by hand means editing a source file, building, running, reverting - per mutation -
and the revert is where it goes wrong: `[IO.File]::WriteAllText` without an encoding strips the
UTF-8 BOM, and a forgotten revert ships the mutant. This script applies each mutation as an
exact, unique string replacement, runs `worktree-test.ps1` as a child process, and restores the
file's original bytes in a `finally`, so the tree is identical before and after.

Contract
--------
Input (-ManifestFile <path>; JSON):
  {
    "worktree":      "C:/Worktrees/linq2db/5943-x",   // required; the tree to mutate and test
    "project":       "Tests/Linq/Tests.csproj",       // optional, this default
    "tfm":           "net10.0",                       // optional, this default
    "configuration": "Testing",                       // optional, this default
    "filter":        "FullyQualifiedName~CreateData.CreateDatabase|FullyQualifiedName~X",  // required
    "providers":     ["YDB", "YDB.LinqService"],      // optional
    "green":         true,                            // optional, default true: run the unmutated tree first
    "restartContainer": "ydb",                        // optional: `docker restart <name>` before every run
                                                      // (a degrading local container, e.g. ydb, otherwise times out)
    "mutations": [
      {
        "name":      "drop-precision-conjunct",       // required; names the log files
        "file":      "Source/.../YdbMemberTranslator.cs",  // required; relative to worktree
        "from":      "exact text",                    // required; must occur exactly once in the file
        "to":        "replacement text",              // required
        "expectRed": ["Round33"],                     // optional; test-name prefixes that must fail
        "prepare": {                                  // optional; a step the test run depends on, run after the
          "script": "Tests/Tests.Wasm/publish-wasm-bundles.ps1", // mutation is applied (e.g. republishing an artifact
          "args":   ["-Mode", "Debug"]                // the tests load) and again after the file is restored, so
        }                                             // the artifact never stays built from the mutant
      }
    ]
  }

A failed `prepare` on the mutant reports `prepareFailed` (and no red); a failed `prepare` after the
restore sets `restored: false`, because the artifact on disk may still hold the mutant. `prepare`
runs `pwsh -NoProfile -File <script> <args...>`, so a list-valued argument arrives as one string.

Use "\r\n" in `from` / `to` for multi-line anchors in CRLF files.

A mutation that drops a private member's only call, or orphans a guarded field, fails the build
(`IDE0051` / `CS0169` under `TreatWarningsAsErrors`) and reports `buildFailed`, not a red: mutate the
condition instead. See evidence-discipline.md -> *The same goes for a private method*.

Output (stdout, JSON):
  {
    "ok": true,                       // green (if run) had 0 failures, every mutation applied, every expectRed caught
    "restored": true,                 // every mutated file's bytes equal what they were before the run
    "runs": [
      { "name": "green", "mutated": false, "total": 24, "failed": 0, "succeeded": 20, "skipped": 4,
        "failedTests": [], "logPath": "..." },
      { "name": "drop-precision-conjunct", "mutated": true, "total": 24, "failed": 4, ...,
        "failedTests": ["Round33(\"YDB\",ToEven)", ...], "expectRed": ["Round33"], "caught": true }
    ]
  }

Logs go to <worktree>/.build/.agents/mutation-<name>.log. Invoke from the PowerShell tool:
    .claude/scripts/mutation-run.ps1 -ManifestFile .build/.agents/<id>-mutations.json
Runs are sequential (one build at a time); a run is long, so launch it in the background.
#>
[CmdletBinding()]
param([string]$ManifestFile)

. "$PSScriptRoot/_shared.ps1"
$global:ScriptBaseName = 'mutation-run'

$m = Read-ManifestFromFileOrStdin -ManifestFile $ManifestFile

if (-not $m.worktree) { Exit-WithError 'manifest has no "worktree"' -NextAction 'set "worktree" to the absolute tree path' }
if (-not $m.filter)   { Exit-WithError 'manifest has no "filter"'   -NextAction 'set "filter" to the dotnet test filter, CreateData.CreateDatabase prefix included' }
if (-not (Test-Path -LiteralPath $m.worktree)) { Exit-WithError "worktree not found: $($m.worktree)" }

$wt      = (Resolve-Path -LiteralPath $m.worktree).Path
$runner  = Join-Path $PSScriptRoot 'worktree-test.ps1'
$logDir  = Join-Path $wt '.build/.agents'
[void][System.IO.Directory]::CreateDirectory($logDir)

$project = if ($m.project)       { $m.project }       else { 'Tests/Linq/Tests.csproj' }
$tfm     = if ($m.tfm)           { $m.tfm }           else { 'net10.0' }
$config  = if ($m.configuration) { $m.configuration } else { 'Testing' }
$green   = if ($null -ne $m.green) { [bool]$m.green } else { $true }

# validate every mutation before any build, so a bad anchor fails in seconds, not after a run
$mutations = @($m.mutations)
foreach ($mu in $mutations) {
    if (-not $mu.name -or -not $mu.file -or $null -eq $mu.from -or $null -eq $mu.to) {
        Exit-WithError "mutation entry needs name, file, from and to: $($mu | ConvertTo-Json -Compress)"
    }
    $path = Join-Path $wt $mu.file
    if (-not (Test-Path -LiteralPath $path)) { Exit-WithError "mutation '$($mu.name)': file not found: $($mu.file)" }
    $text  = [System.IO.File]::ReadAllText($path)
    $first = $text.IndexOf([string]$mu.from, [System.StringComparison]::Ordinal)
    if ($first -lt 0) { Exit-WithError "mutation '$($mu.name)': 'from' not found in $($mu.file)" -NextAction 'copy the anchor from the file; use \r\n for line breaks in a CRLF file' }
    if ($text.IndexOf([string]$mu.from, $first + 1, [System.StringComparison]::Ordinal) -ge 0) {
        Exit-WithError "mutation '$($mu.name)': 'from' occurs more than once in $($mu.file)" -NextAction 'extend the anchor with surrounding text until it is unique'
    }
    if ($mu.prepare -and -not (Test-Path -LiteralPath (Join-Path $wt ([string]$mu.prepare.script)))) {
        Exit-WithError "mutation '$($mu.name)': prepare script not found: $($mu.prepare.script)"
    }
}

function Invoke-Prepare($mu, [string]$phase) {
    if (-not $mu.prepare) { return $true }

    $script = Join-Path $wt ([string]$mu.prepare.script)
    $plog   = Join-Path $logDir "mutation-$($mu.name)-prepare-$phase.log"
    $pargs  = @(@($mu.prepare.args) | Where-Object { $null -ne $_ } | ForEach-Object { [string]$_ })

    & pwsh -NoProfile -File $script @pargs *> $plog
    return ($LASTEXITCODE -eq 0)
}

function Invoke-Run([string]$name) {
    if ($m.restartContainer) { & docker restart $m.restartContainer *> $null }

    $log  = Join-Path $logDir "mutation-$name.log"
    $runArgs = @('-NoProfile', '-File', $runner, '-RepoRoot', $wt, '-Project', $project, '-Tfm', $tfm,
        '-Configuration', $config, '-Filter', $m.filter, '-MaxFailures', '200', '-FailureLines', '4', '-LogPath', $log)
    if ($m.providers) { $runArgs += @('-Provider', ((@($m.providers)) -join ',')) }

    $raw = & pwsh @runArgs 2>$null
    $res = $null
    try { $res = ($raw -join "`n") | ConvertFrom-Json -Depth 50 } catch { }

    $s = if ($res) { $res.summary } else { $null }
    [ordered]@{
        name        = $name
        total       = if ($s) { $s.total }     else { $null }
        failed      = if ($s) { $s.failed }    else { $null }
        succeeded   = if ($s) { $s.succeeded } else { $null }
        skipped     = if ($s) { $s.skipped }   else { $null }
        buildFailed = if ($res) { [bool]$res.buildFailed } else { $true }
        failedTests = if ($res) { @($res.failedTests) } else { @() }
        logPath     = $log
    }
}

$runs     = [System.Collections.Generic.List[object]]::new()
$ok       = $true
$restored = $true

if ($green) {
    $r = Invoke-Run 'green'
    $r['mutated'] = $false
    if ($r.buildFailed -or $r.failed -ne 0) { $ok = $false }
    $runs.Add($r)
}

foreach ($mu in $mutations) {
    $path  = Join-Path $wt $mu.file
    $bytes = [System.IO.File]::ReadAllBytes($path)
    $bom   = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    $text  = [System.IO.File]::ReadAllText($path)

    try {
        [System.IO.File]::WriteAllText($path, $text.Replace([string]$mu.from, [string]$mu.to), [System.Text.UTF8Encoding]::new($bom))

        if (Invoke-Prepare $mu 'mutated') {
            $r = Invoke-Run $mu.name
        }
        else {
            $r = [ordered]@{ name = $mu.name; prepareFailed = $true; buildFailed = $true; failedTests = @()
                             logPath = (Join-Path $logDir "mutation-$($mu.name)-prepare-mutated.log") }
        }
    }
    finally {
        [System.IO.File]::WriteAllBytes($path, $bytes)
    }

    $after = [System.IO.File]::ReadAllBytes($path)
    if (-not [System.Linq.Enumerable]::SequenceEqual([byte[]]$bytes, [byte[]]$after)) { $restored = $false; $ok = $false }

    if (-not (Invoke-Prepare $mu 'restored')) { $restored = $false; $ok = $false }

    $r['mutated'] = $true
    if ($mu.expectRed) {
        $expect = @($mu.expectRed)
        $caught = $true
        foreach ($e in $expect) {
            if (-not (@($r.failedTests) | Where-Object { $_.StartsWith($e, [System.StringComparison]::Ordinal) })) { $caught = $false }
        }
        $r['expectRed'] = $expect
        $r['caught']    = $caught
        if (-not $caught) { $ok = $false }
    }
    if ($r.buildFailed) { $ok = $false }
    $runs.Add($r)
}

Write-JsonOutput ([ordered]@{ ok = $ok; restored = $restored; runs = $runs })
