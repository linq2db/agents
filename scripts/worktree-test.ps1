#!/usr/bin/env pwsh
<#
Build and run a test project inside a **worktree** and return a parsed pass/fail
summary, in one allowlisted pwsh call.

Why this script exists
----------------------
Running a PR's *own* new tests can't go through `/test` + `test-runner`: those
tests don't exist in the primary clone, and `test-runner` is Bash-only so it
can't `Set-Location` into the worktree (see `.claude/docs/worktree.md` ->
"Reviewing / verifying a PR's own new tests"). The hand-rolled alternative is a
`Set-Location <worktree>; dotnet test --project ... > <abs log>` one-liner that
has to be retyped per TFM / filter / provider, and gets three details wrong on a
regular basis:

  1. `Set-Location` and `dotnet` MUST be one invocation - the PowerShell tool's
     cwd does not survive between calls, so a separate `Set-Location` silently
     leaves the build running against the primary clone.
  2. The log redirect MUST be an absolute path - the run's cwd is the worktree,
     so a relative `>` lands in the wrong tree.
  3. MTP prints only *failed* / *skipped* tests per-test; the pass count exists
     only in the `Test run summary:` block, so "N passed" has to be parsed out
     rather than eyeballed.

This script does all three and returns the summary as JSON, so the caller never
has to grep the log to find out what happened.

Contract
--------

Input (named parameters):
  -RepoRoot      <path>    required; the worktree root (absolute)
  -Project       <path>    required; test project, relative to RepoRoot
  -Tfm           <string>  optional; e.g. net10.0 - omit to build every TFM
  -Filter        <string>  optional; passed through to --filter
  -Provider      <list>    optional; passed through to --provider (comma list)
  -Configuration <string>  optional; default Debug
  -LogPath       <path>    optional; absolute path for the captured output.
                           Default: <RepoRoot>/.build/.agents/worktree-test-<project>[-<tfm>]-<pid>-<HHmmssfff>.log.
                           The timestamp matters: several calls from one PowerShell
                           process share the PID, and a later run would overwrite an
                           earlier run's log - the evidence of a failure you still
                           have to read.
  -SerialBuild             optional; build first as its own step, with -m:1
                           -p:UseSharedCompilation=false, to <LogPath>-build.log.
                           Reach for it when a run is killed mid-flight leaving an
                           empty log: on a loaded box the implicit parallel build
                           dies repeatedly where the serial one does not, and
                           splitting the steps makes the next kill diagnosable -
                           which log is empty says which step died. Slower, so
                           it is opt-in.
  -SharedCompilation       optional; with -SerialBuild, builds with
                           -p:UseSharedCompilation=true instead of the default
                           false. Reach for it when the build is killed for LOW
                           MEMORY (as opposed to CS8032 / MSB4166 / a stale
                           server): forcing false spawns a fresh csc.exe that
                           must page in its own multi-GB working set, while the
                           resident VBCSCompiler already has one, so on a starved
                           box false is what gets killed. See
                           `.claude/docs/windows-dev-gotchas.md` -> "A build
                           killed for memory inverts the UseSharedCompilation
                           advice".
  -NoRestore               optional; adds `--no-restore` to the -SerialBuild
                           step. Safe once the worktree has restored at least
                           once, and skips a startup spike that is itself enough
                           to be killed on a starved box.
  -OutputDetailed          optional; adds `--output Detailed`. MTP routes a test's
                           stdout to the run output only when the test FAILS or is
                           skipped, so a passing probe's `TestContext.Out.WriteLine`
                           / `Console.WriteLine` is generated and then discarded.
                           Pass this whenever the point of the run is to READ
                           something the test printed (generated SQL, a row dump, a
                           caught exception). Without it the usual outcome is a green
                           run with an empty log and a second build to recover the
                           output. See `.claude/docs/testing.md` -> "Capturing a
                           passing test's exception / stack".
  -NoTestProgress          optional; suppress the `--test-progress` flag this script
                           passes by default.
  -NoBuild                 optional; adds `--no-build` and skips any build, reusing the
                           worktree's existing output. For a re-run with another
                           provider or filter after a build already succeeded — the
                           hand-run test exe it replaces loses this script's parsed
                           summary. Exclusive with -SerialBuild. A run against a stale
                           or missing build fails or tests old code; it does not rebuild.
  -ExpectTests   <list>    optional; test METHOD names (no class, no arguments) that
                           must have run. Implies -OutputDetailed, since MTP lists a
                           passed test only in that mode. Any name with no passed /
                           failed / skipped line lands in `missingTests` and fails the
                           run (exit 1). Use it when a broad filter carries a test you
                           just wrote: the summary counts alone cannot show that the
                           new test was among them. A comma-separated string is split,
                           since -File delivers `-ExpectTests A,B` as one element.
  -LinqToDBAsset <tfm>     optional; `netstandard2.0` only. Runs the tests against
                           linq2db's netstandard2.0 code paths: the asset a modern-
                           runtime app loads once its runtime's TFM is dropped, or
                           when it consumes linq2db through a netstandard2.0 library.
                           Requires -Tfm (a net8+ test TFM). Builds the test project
                           (unless -NoBuild), then builds Source/LinqToDB at -Tfm with
                           the ns2.0 define set (no NET8_0_OR_GREATER / SUPPORTS_* /
                           ADO_*, plus NETSTANDARD2_0). It overlays that linq2db.dll/.pdb
                           onto the test output, runs with --no-build, restores the
                           test output and rebuilds Source/LinqToDB normally.
                           A *simulation*, by necessity: the real ns2.0 binary can't
                           host tests compiled against net8+, whose `with` on a linq2db
                           record calls a covariant `<Clone>$` that ns2.0 lacks. It
                           reproduces every TFM gate. It does not reproduce ns2.0's
                           polyfilled-type identities (`Index`, `Range`, `IsExternalInit`
                           bind to the BCL types here). A test that calls an API the
                           asset lacks fails with MissingMethodException - a feature-
                           parity gap, not a break. CI has no such leg: this is the only
                           way to prove an ns2.0 fix red. See
                           `.claude/docs/code-design.md` -> "A TFM gate may withhold a
                           feature, never recognition of unchanged source".
  -PerProvider             optional; with a -Provider list, runs each provider as its own
                           invocation - its own log and summary - one after another, and
                           prints `{ ok, providers: [ { provider, result } ] }` with each
                           `result` the single-run JSON below. The first run builds (unless
                           -NoBuild); the rest pass -NoBuild. For a probe or sweep across
                           providers, where a combined run's failures cannot be told apart
                           by provider at a glance and one database is driven by one
                           process at a time. Exclusive with -LogPath.
  -GroupFailures           optional; adds `failureGroups`: every failure (not just the
                           first -MaxFailures) grouped by test METHOD, with a count and
                           the first message line. For triaging a broad sweep, where a
                           few hundred failures fall into a few dozen causes.

`--test-progress` is passed by default, per `.claude/docs/agent-rules.md` ->
"Every hand-run `dotnet test` / test-exe invocation carries `--test-progress`".
Without it there is no heartbeat at `.build/.agents/test-progress.<tfm>.<pid>.json`,
a long run is unobservable, and - worse - the ABSENCE of a heartbeat is the corpus's
own evidence that a run never started, so a flagless run is indistinguishable from a
dead one.

The exception is the DB-free analyzer-fixture projects (`Tests/Tests.Analyzers`,
`Tests/Tests.Analyzers.Internal`, and any future sibling): they host a bare NUnit MTP
runner that does not register the extension, so the option reaches the test
application, which prints its help and exits 5 - surfaced as `Zero tests ran`, which
is byte-identical to the symptom of a bad `--filter`. This script skips the flag
automatically when `-Project` matches `Tests.Analyzers`; `-NoTestProgress` forces it
off for anything else. The `testProgress` field in the JSON output reports what was
actually decided, so a `Zero tests ran` result can be checked against it rather than
guessed at.

Output (stdout, single JSON object):
  {
    "ok":        true,               // exitCode 0
    "exitCode":  0,
    "buildFailed": false,            // true when the run never reached the tests
    "repoRoot":  "C:/Worktrees/...",
    "project":   "Tests/.../X.csproj",
    "logPath":   "C:/.../worktree-test-X-net10.0-1234.log",
    "testProgress": true,            // whether --test-progress was actually passed
    "linqToDBAsset": "netstandard2.0", // only with -LinqToDBAsset; the asset the tests ran against
    "summary":   { "total": 186, "failed": 0, "succeeded": 168, "skipped": 18, "duration": "36s 628ms" },
    "failedTests": [ "SomeTest", ... ],
    "failures":  [ { "test": "SomeTest(\"SQLite.MS\")", "message": [ "Shouldly...", ... ] } ],
                                     // first -MaxFailures (20) distinct failures, each with up to
                                     // -FailureLines (8) message lines - stack frames and the
                                     // captured DataConnection trace dropped; read logPath for the SQL
    "missingTests": [ ... ],         // only with -ExpectTests; names that did not run
    "failureGroups": [ { "test": "TrimLeft", "count": 2, "message": "LinqToDB.LinqToDBException : ..." } ],
                                     // only with -GroupFailures; one entry per failed method
    "hint":      "..."               // only for a recognised environment failure (NuGet cache lock), or
                                     // failures in a Tests/Linq run whose filter lacks CreateData.CreateDatabase
  }

`summary` is null when no `Test run summary:` block was produced (typically a
build failure - check `buildFailed` and read `logPath`).

Exit codes:
  0 = the run completed AND every test passed
  1 = bad input (missing RepoRoot / Project), or the run failed (build break or
      test failures) - inspect the JSON + log
#>

param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$Project,
    [string]$Tfm,
    [string]$Filter,
    [string[]]$Provider,
    [string]$Configuration = 'Debug',
    [string]$LogPath,
    [switch]$SerialBuild,
    [switch]$OutputDetailed,
    [switch]$SharedCompilation,
    [switch]$NoRestore,
    [switch]$NoTestProgress,
    [switch]$NoBuild,
    [string[]]$ExpectTests,
    [string]$LinqToDBAsset,
    [switch]$GroupFailures,
    [int]$FailureLines = 8,
    [int]$MaxFailures  = 20,
    [switch]$PerProvider
)

. "$PSScriptRoot/_shared.ps1"

$ErrorActionPreference = 'Stop'

# -File passes `-ExpectTests A,B` as the single string "A,B".
$ExpectTests = @($ExpectTests | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })

# -PerProvider: one run, log and summary per provider, sequentially - a failure is attributed to its provider and each
# provider's database is driven by one process at a time. The first run may build; the rest reuse its output.
$Provider = @($Provider | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
if ($PerProvider) {
    if ($Provider.Count -lt 1) { Exit-WithError -Message '-PerProvider needs -Provider' -NextAction 'pass -Provider a,b,c' }
    if ($LogPath)             { Exit-WithError -Message '-PerProvider writes one log per provider; drop -LogPath' -NextAction 'omit -LogPath' }

    $passThrough = @()
    foreach ($kv in $PSBoundParameters.GetEnumerator()) {
        if ($kv.Key -in 'Provider', 'PerProvider', 'NoBuild', 'SerialBuild', 'SharedCompilation', 'NoRestore') { continue }
        if ($kv.Value -is [System.Management.Automation.SwitchParameter]) { if ($kv.Value) { $passThrough += "-$($kv.Key)" } }
        elseif ($kv.Value -is [array]) { $passThrough += "-$($kv.Key)"; $passThrough += ($kv.Value -join ',') }
        else { $passThrough += "-$($kv.Key)"; $passThrough += [string]$kv.Value }
    }

    $runs = @()
    for ($i = 0; $i -lt $Provider.Count; $i++) {
        # @() around the whole if: a one-element result unrolls to a string, and splatting a string into a native
        # command passes it character by character.
        $buildArgs = @(if ($i -gt 0 -or $NoBuild) { '-NoBuild' }
                       else { if ($SerialBuild) { '-SerialBuild' }; if ($SharedCompilation) { '-SharedCompilation' }; if ($NoRestore) { '-NoRestore' } })
        $out  = & pwsh -NoProfile -File $PSCommandPath @passThrough -Provider $Provider[$i] @buildArgs
        $code = $LASTEXITCODE
        $json = ($out | Out-String).Trim()
        $run  = $null
        if ($json) { try { $run = $json | ConvertFrom-Json } catch { $run = $null } }
        if ($null -eq $run) { $run = [pscustomobject]@{ ok = $false; exitCode = $code; error = $(if ($json) { $json } else { 'no JSON output - see the error on stderr above' }) } }
        $runs += [pscustomobject]@{ provider = $Provider[$i]; result = $run }
        if ($i -eq 0 -and $run.buildFailed) { break }
    }

    Write-JsonOutput ([ordered]@{
        ok        = -not ($runs | Where-Object { -not $_.result.ok })
        providers = $runs
    })
    exit ($(if ($runs | Where-Object { -not $_.result.ok }) { 1 } else { 0 }))
}

if (-not (Test-Path -LiteralPath $RepoRoot -PathType Container)) {
    Exit-WithError -Message "RepoRoot not found: $RepoRoot" -NextAction 'pass -RepoRoot <absolute worktree path>'
}

$repoFull    = (Resolve-Path -LiteralPath $RepoRoot).Path
$projectFull = Join-Path $repoFull $Project

if (-not (Test-Path -LiteralPath $projectFull -PathType Leaf)) {
    Exit-WithError -Message "Project not found under RepoRoot: $projectFull" -NextAction 'pass -Project <path relative to RepoRoot>'
}

if (-not $LogPath) {
    $logDir = Join-Path $repoFull '.build/.agents'
    if (-not (Test-Path -LiteralPath $logDir)) { New-Item -ItemType Directory -Force -Path $logDir | Out-Null }
    $stem    = [System.IO.Path]::GetFileNameWithoutExtension($Project)
    $suffix  = if ($Tfm) { "-$Tfm" } else { '' }
    $LogPath = Join-Path $logDir "worktree-test-$stem$suffix-$PID-$(Get-Date -Format 'HHmmssfff').log"
}

if (-not [System.IO.Path]::IsPathRooted($LogPath)) {
    Exit-WithError -Message "LogPath must be absolute (the run's cwd is the worktree): $LogPath" -NextAction 'pass -LogPath <absolute path>'
}

$logParent = Split-Path -Parent $LogPath
if (-not (Test-Path -LiteralPath $logParent)) { New-Item -ItemType Directory -Force -Path $logParent | Out-Null }

$buildLogPath = $null

if ($NoBuild -and $SerialBuild) {
    Exit-WithError -Message '-NoBuild and -SerialBuild are mutually exclusive' -NextAction 'drop one of them'
}

if ($LinqToDBAsset -and -not $Tfm) {
    Exit-WithError -Message '-LinqToDBAsset needs -Tfm: the overlay replaces linq2db.dll in one TFM output folder' -NextAction 'pass -Tfm net10.0'
}

if ($LinqToDBAsset -and $LinqToDBAsset -ne 'netstandard2.0') {
    Exit-WithError -Message "-LinqToDBAsset supports netstandard2.0 only, not $LinqToDBAsset" -NextAction 'pass -LinqToDBAsset netstandard2.0'
}

# On by default (see the header). Skipped for the analyzer-fixture projects, whose bare MTP
# runner does not register the extension and answers the flag with its help text + exit 5.
$useTestProgress = (-not $NoTestProgress) -and ($Project -notmatch 'Tests\.Analyzers')

if ($SerialBuild) {
    $buildLogPath = $LogPath -replace '\.log$', '-build.log'
    # UseSharedCompilation=false is the default because a stale VBCSCompiler is the usual cause of a
    # killed build. Under MEMORY pressure it is backwards - a fresh csc.exe needs its own multi-GB
    # working set while the resident server already has one - hence -SharedCompilation.
    $sharedFlag   = if ($SharedCompilation) { '-p:UseSharedCompilation=true' } else { '-p:UseSharedCompilation=false' }
    $buildArgs    = @('build', $projectFull, '-c', $Configuration, '-m:1', $sharedFlag)
    if ($NoRestore) { $buildArgs += '--no-restore' }
    if ($Tfm) { $buildArgs += @('-f', $Tfm) }

    Push-Location -LiteralPath $repoFull
    try {
        & dotnet @buildArgs *> $buildLogPath
        $buildExit = $LASTEXITCODE
    }
    finally {
        Pop-Location
    }

    if ($buildExit -ne 0) {
        [ordered]@{
            ok           = $false
            exitCode     = $buildExit
            buildFailed  = $true
            repoRoot     = $repoFull
            project      = $Project
            logPath      = $buildLogPath
            buildLogPath = $buildLogPath
            testProgress = $useTestProgress
            summary      = $null
            failedTests  = @()
        } | ConvertTo-Json -Depth 5

        exit 1
    }
}

function Get-MSBuildProperty([string]$ProjectPath, [string]$Property, [string]$TargetFramework) {
    $value = & dotnet msbuild $ProjectPath "-getProperty:$Property" "-p:Configuration=$Configuration" "-p:TargetFramework=$TargetFramework"
    if ($LASTEXITCODE -ne 0 -or -not $value) {
        Exit-WithError -Message "could not evaluate $Property of $ProjectPath ($TargetFramework)" -NextAction 'check that the project restores'
    }
    return ($value | Select-Object -Last 1).Trim()
}

# The overlay: the test host runs linq2db compiled at the test TFM with the asset TFM's define set (see
# -LinqToDBAsset in the header). The real ns2.0 binary can't be overlaid: tests compiled against net8+ call
# records' covariant `<Clone>$`, which the ns2.0 build doesn't have.
$overlay = $null
if ($LinqToDBAsset) {
    $assetProject = Join-Path $repoFull 'Source/LinqToDB/LinqToDB.csproj'
    if (-not $buildLogPath) { $buildLogPath = $LogPath -replace '\.log$', '-build.log' }

    $assetDefines  = @((Get-MSBuildProperty $assetProject 'DefineConstants' $LinqToDBAsset) -split ';' | Where-Object { $_ })
    # The SDK adds these in a target, after evaluation, so -getProperty doesn't report them.
    $assetDefines += 'NETSTANDARD', 'NETSTANDARD2_0', 'NETSTANDARD1_0_OR_GREATER', 'NETSTANDARD1_1_OR_GREATER', 'NETSTANDARD1_2_OR_GREATER',
                     'NETSTANDARD1_3_OR_GREATER', 'NETSTANDARD1_4_OR_GREATER', 'NETSTANDARD1_5_OR_GREATER', 'NETSTANDARD1_6_OR_GREATER', 'NETSTANDARD2_0_OR_GREATER'

    # Warnings off: the asset's code compiled against the net BCL warns where the real asset doesn't (CS0114 on
    # BulkCopyReader.DisposeAsync - a new slot, which is the asset's actual semantics - and nullable flow).
    $simulateArgs = @('build', $assetProject, '-c', $Configuration, '-f', $Tfm, '-p:BuildProjectReferences=false',
        '-p:TreatWarningsAsErrors=false', '-p:DisableImplicitFrameworkDefines=true', "-p:DefineConstants=$($assetDefines -join '%3B')")
    $restoreArgs  = @('build', $assetProject, '-c', $Configuration, '-f', $Tfm, '-p:BuildProjectReferences=false')

    Push-Location -LiteralPath $repoFull
    try {
        $steps = @(, $simulateArgs)
        if (-not $NoBuild -and -not $SerialBuild) {
            $steps = @(, @('build', $projectFull, '-c', $Configuration, '-f', $Tfm)) + $steps
        }
        foreach ($step in $steps) {
            & dotnet @step *>> $buildLogPath
            if ($LASTEXITCODE -ne 0) {
                [ordered]@{
                    ok            = $false
                    exitCode      = $LASTEXITCODE
                    buildFailed   = $true
                    repoRoot      = $repoFull
                    project       = $Project
                    logPath       = $buildLogPath
                    buildLogPath  = $buildLogPath
                    linqToDBAsset = $LinqToDBAsset
                    summary       = $null
                    failedTests   = @()
                } | ConvertTo-Json -Depth 5
                exit 1
            }
        }

        $assetDll = Get-MSBuildProperty $assetProject 'TargetPath' $Tfm
        $outDir   = Get-MSBuildProperty $projectFull  'TargetDir'  $Tfm
    }
    finally {
        Pop-Location
    }

    $targetDll = Join-Path $outDir (Split-Path -Leaf $assetDll)
    if (-not (Test-Path -LiteralPath $assetDll) -or -not (Test-Path -LiteralPath $targetDll)) {
        Exit-WithError -Message "overlay source or target missing: $assetDll -> $targetDll" -NextAction 'build both projects once without -NoBuild'
    }

    $backupDir = Join-Path (Split-Path -Parent $LogPath) "linqtodb-asset-backup-$PID"
    New-Item -ItemType Directory -Force -Path $backupDir | Out-Null

    $overlay = foreach ($ext in '.dll', '.pdb') {
        $from = [System.IO.Path]::ChangeExtension($assetDll,  $ext)
        $to   = [System.IO.Path]::ChangeExtension($targetDll, $ext)
        if (-not (Test-Path -LiteralPath $from)) { continue }
        $backup = $null
        if (Test-Path -LiteralPath $to) {
            $backup = Join-Path $backupDir (Split-Path -Leaf $to)
            Copy-Item -LiteralPath $to -Destination $backup -Force
        }
        Copy-Item -LiteralPath $from -Destination $to -Force
        [pscustomobject]@{ Target = $to; Backup = $backup }
    }

    $NoBuild = $true
}

$dotnetArgs = @('test', '--project', $projectFull, '-c', $Configuration)
if ($Tfm)      { $dotnetArgs += @('-f', $Tfm) }
if ($Filter)   { $dotnetArgs += @('--filter', $Filter) }
if ($Provider.Count -gt 0) { $dotnetArgs += @('--provider', ($Provider -join ',')) }
if ($OutputDetailed -or $ExpectTests) { $dotnetArgs += @('--output', 'Detailed') }
if ($useTestProgress) { $dotnetArgs += '--test-progress' }
if ($NoBuild) { $dotnetArgs += '--no-build' }

# .runsettings is resolved relative to the run's cwd, so it must be looked up in the worktree.
$runSettings = Join-Path $repoFull '.runsettings'
if (Test-Path -LiteralPath $runSettings) { $dotnetArgs += @('--settings', $runSettings) }

Push-Location -LiteralPath $repoFull
try {
    & dotnet @dotnetArgs *> $LogPath
    $exitCode = $LASTEXITCODE
}
finally {
    Pop-Location

    # Put the original asset back, timestamps included, and rebuild Source/LinqToDB's own output, which the
    # simulated build replaced: a later `--no-build` run must not pick the simulation up.
    foreach ($o in @($overlay)) {
        if (-not $o) { continue }
        if ($o.Backup) { Copy-Item -LiteralPath $o.Backup -Destination $o.Target -Force }
        else           { Remove-Item -LiteralPath $o.Target -Force }
    }
    if ($LinqToDBAsset) {
        if ($overlay) { Remove-Item -LiteralPath $backupDir -Recurse -Force }
        Push-Location -LiteralPath $repoFull
        try     { & dotnet @restoreArgs *>> $buildLogPath }
        finally { Pop-Location }
    }
}

$summary     = $null
$failedTests = @()
$failures    = @()
$buildFailed = $false
$hint        = $null
$ranTests    = [System.Collections.Generic.HashSet[string]]::new()

if (Test-Path -LiteralPath $LogPath) {
    $lines = [System.IO.File]::ReadAllLines($LogPath)

    if ($lines | Where-Object { $_ -match '^Build failed' }) { $buildFailed = $true }

    # Retrying cannot clear it: the broken package is re-extracted onto a DLL a shared build node holds.
    if ($lines | Where-Object { $_ -match 'NuGet\.targets.*error : Access to the path' }) {
        $hint = 'NuGet cache entry half-extracted and locked by a shared build node; do not retry. Restore into a private cache: .claude/docs/windows-dev-gotchas.md -> "A half-deleted package in the NuGet cache".'
    }

    $seenFailures  = [System.Collections.Generic.HashSet[string]]::new()
    $failureGroups = [ordered]@{}

    for ($li = 0; $li -lt $lines.Length; $li++) {
        $line = $lines[$li]
        if ($line -match '^failed\s+(\S+)') {
            $failedTests += $Matches[1]
            $method       = $Matches[1] -replace '\(.*$', ''

            if ($GroupFailures) {
                if (-not $failureGroups.Contains($method)) {
                    $first = $null
                    for ($j = $li + 1; $j -lt $lines.Length; $j++) {
                        $m = $lines[$j] -replace '\x1b\[[0-9;]*m', ''
                        if ($m -match '^\S' -or $m -match '^\s+DataConnection:') { break }
                        if ($m -match '^\s+(at |from |--- End of|\d+\)\s+at )' -or $m.Trim() -eq '') { continue }
                        $first = $m.Trim()
                        break
                    }
                    $failureGroups[$method] = [ordered]@{ test = $method; count = 0; message = $first }
                }
                $failureGroups[$method].count++
            }

            # The message block under the failed line, minus stack frames, so the caller need not dig the log.
            $head = ($line -replace '\s+\(\d.*?\)$', '').Substring(7)
            if ($failures.Count -lt $MaxFailures -and $seenFailures.Add($head)) {
                $message = @()
                for ($j = $li + 1; $j -lt $lines.Length -and $message.Count -lt $FailureLines; $j++) {
                    $m = $lines[$j] -replace '\x1b\[[0-9;]*m', ''
                    if ($m -match '^\S' -or $m -match '^\s+DataConnection:') { break }
                    if ($m -match '^\s+(at |from |--- End of|\d+\)\s+at )' -or $m.Trim() -eq '') { continue }
                    $message += $m.Trim()
                }
                $failures += [ordered]@{ test = $head; message = @($message) }
            }
        }
        if ($line -match '^\s*(passed|failed|skipped)\s+([^\s(]+)') { [void]$ranTests.Add($Matches[2]) }
    }

    $idx = [array]::FindIndex($lines, [Predicate[string]] { param($l) $l -match '^Test run summary:' })
    if ($idx -ge 0) {
        $fields = @{}
        for ($i = $idx + 1; $i -lt [Math]::Min($idx + 8, $lines.Length); $i++) {
            if ($lines[$i] -match '^\s+(total|failed|succeeded|skipped|duration):\s*(.+?)\s*$') {
                $fields[$Matches[1]] = $Matches[2]
            }
        }
        if ($fields.Count -gt 0) {
            $summary = [ordered]@{
                total     = [int]($fields['total']     ?? 0)
                failed    = [int]($fields['failed']    ?? 0)
                succeeded = [int]($fields['succeeded'] ?? 0)
                skipped   = [int]($fields['skipped']   ?? 0)
                duration  = $fields['duration']
            }
        }
    }
}

if (-not $hint -and $failedTests.Count -gt 0 -and $Project -match 'Tests[\\/]Linq[\\/]' -and $Filter -notmatch 'CreateData\.CreateDatabase') {
    $hint = 'Filter has no CreateData.CreateDatabase: a data-dependent failure may be a stale or unseeded test database. Rerun with it before reading the failure as a defect.'
}

if (-not $hint -and $NoBuild -and -not $summary) {
    $hint = '-NoBuild found no runnable build output for this project/TFM/configuration; run once without -NoBuild.'
}

$missingTests = @($ExpectTests | Where-Object { $_ -and -not $ranTests.Contains($_) })

$result = [ordered]@{
    ok          = ($exitCode -eq 0) -and $missingTests.Count -eq 0
    exitCode    = $exitCode
    buildFailed = $buildFailed
    repoRoot     = $repoFull
    project      = $Project
    logPath      = $LogPath
    buildLogPath = $buildLogPath
    testProgress = $useTestProgress
    summary      = $summary
    failedTests  = @($failedTests | Select-Object -Unique)
    failures     = @($failures)
}
if ($ExpectTests) { $result['missingTests'] = $missingTests }
if ($GroupFailures) { $result['failureGroups'] = @($failureGroups.Values) }
if ($LinqToDBAsset) { $result['linqToDBAsset'] = $LinqToDBAsset }
if ($hint)        { $result['hint']         = $hint }

$result | ConvertTo-Json -Depth 5

if ($exitCode -ne 0 -or $missingTests.Count -gt 0) { exit 1 }
