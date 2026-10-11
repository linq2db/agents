#!/usr/bin/env pwsh
<#
fsharp-scaffold-gates.ps1 — regenerate and verify the F# scaffolder output (#1553) in one call.

Runs, in order, against a linq2db checkout (usually a worktree):
  1. `Tests/FSharp.Scaffold/generate.ps1` (builds the CLI in Release, regenerates every F# golden);
     proves each golden was actually rewritten by this run (mtime) and reports which changed (hash),
     because generate.ps1 reports progress with Write-Host, which a redirected log does not capture.
  2. `git diff --stat` over `Tests/FSharp.Scaffold/`.
  3. Release builds of both compile gates (`Tests.FSharp.Scaffold.fsproj`, `Tests.FSharp.Scaffold.NoNrt.fsproj`).
  4. Optional: the C# CLI baseline subset via `release-test-cli-scaffold.ps1` + `git status` over `Tests/Tests.T4`.
  5. Optional: the CLI test project via `worktree-test.ps1`.

Needs the database containers generate.ps1 uses (SQLite file DB, PostgreSQL, SQL Server) and, for step 4,
the containers of the requested CLI rows. Processes run at BelowNormal priority.

Usage (PowerShell tool):
  & .claude/scripts/fsharp-scaffold-gates.ps1 -RepoRoot C:\Worktrees\linq2db\<wt>
  & .claude/scripts/fsharp-scaffold-gates.ps1 -RepoRoot <wt> -CSharpProviders 'SQLite,SqlServer2025' -CliTests

Output (stdout, JSON): { ok, goldens: { rewritten, total, changed[] }, goldenDiff, gates: { nrt, noNrt },
  csharp: { exitCode, status[] } | null, cliTests: { exitCode, summary } | null, logs: { ... } }.
`ok` is true only when every step that ran exited 0 and every golden was rewritten. A non-empty
`goldens.changed` / `goldenDiff` / `csharp.status` is reported, not judged — the caller decides
whether the diff is expected.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$RepoRoot,
    # comma-separated release-test-cli-scaffold.ps1 provider keys; empty = skip the C# step
    [string]$CSharpProviders = '',
    [switch]$CliTests
)

$ErrorActionPreference = 'Stop'
$global:ScriptBaseName = 'fsharp-scaffold-gates'
. "$PSScriptRoot/_shared.ps1"

(Get-Process -Id $PID).PriorityClass = 'BelowNormal'

$repo = (Resolve-Path $RepoRoot).Path
$scaffoldDir = Join-Path $repo 'Tests/FSharp.Scaffold'
if (-not (Test-Path (Join-Path $scaffoldDir 'generate.ps1'))) {
    Exit-WithError -Message "no Tests/FSharp.Scaffold/generate.ps1 under $repo" -NextAction 'pass -RepoRoot <linq2db checkout or worktree>'
}

$stamp  = Get-Date -Format 'yyyyMMdd-HHmmss'
$logDir = Join-Path (Split-Path $PSScriptRoot -Parent | Split-Path -Parent) '.build/.agents'
[void][System.IO.Directory]::CreateDirectory($logDir)
function LogPath([string]$name) { Join-Path $logDir "fsharp-scaffold-gates-$stamp-$name.log" }

function Get-Goldens {
    Get-ChildItem $scaffoldDir -Recurse -Filter 'TestDataDB.fs' | ForEach-Object {
        [pscustomobject]@{ Path = $_.FullName.Substring($repo.Length + 1); Hash = (Get-FileHash $_.FullName).Hash; Time = $_.LastWriteTime }
    }
}

$logs   = [ordered]@{}
$allOk  = $true
$start  = Get-Date
$before = @(Get-Goldens)

# 1. regenerate
$logs.generate = LogPath 'generate'
& pwsh -NoProfile -File (Join-Path $scaffoldDir 'generate.ps1') *> $logs.generate
$generateExit = $LASTEXITCODE
if ($generateExit -ne 0) { $allOk = $false }

$after     = @(Get-Goldens)
$rewritten = @($after | Where-Object { $_.Time -ge $start }).Count
if ($rewritten -ne $after.Count) { $allOk = $false }
$changed   = @($after | Where-Object { $p = $_.Path; $old = $before | Where-Object Path -eq $p; -not $old -or $old.Hash -ne $_.Hash } | ForEach-Object Path)

# 2. golden diff
$goldenDiff = @(& git -C $repo diff --stat -- Tests/FSharp.Scaffold)

# 3. compile gates
$gates = [ordered]@{}
foreach ($gate in @(@{ Key = 'nrt'; Project = 'Tests.FSharp.Scaffold.fsproj' }, @{ Key = 'noNrt'; Project = 'Tests.FSharp.Scaffold.NoNrt.fsproj' })) {
    $logs["gate-$($gate.Key)"] = LogPath "gate-$($gate.Key)"
    & dotnet build (Join-Path $scaffoldDir $gate.Project) -c Release -low *> $logs["gate-$($gate.Key)"]
    $gates[$gate.Key] = $LASTEXITCODE
    if ($LASTEXITCODE -ne 0) { $allOk = $false }
}

# 4. C# CLI baselines
$csharp = $null
if ($CSharpProviders) {
    $providers = $CSharpProviders.Split(',', [StringSplitOptions]::RemoveEmptyEntries) | ForEach-Object { $_.Trim() }
    $cliDll    = Join-Path $repo '.build/bin/LinqToDB.CLI/Release/net10.0/dotnet-linq2db.dll'
    $logs.csharp = LogPath 'csharp'
    # child -Command (not -File): -Providers is [string[]], which -File would bind as one comma-joined string
    $array   = '@(' + (($providers | ForEach-Object { "'$_'" }) -join ',') + ')'
    $command = "& '$(Join-Path $PSScriptRoot 'release-test-cli-scaffold.ps1')' -RepoRoot '$repo' -CliDll '$cliDll' -Providers $array"
    & pwsh -NoProfile -Command $command *> $logs.csharp
    $csharpExit = $LASTEXITCODE
    if ($csharpExit -ne 0) { $allOk = $false }
    $csharp = [ordered]@{ exitCode = $csharpExit; status = @(& git -C $repo status --short --untracked-files=all -- Tests/Tests.T4) }
}

# 5. CLI tests
$cli = $null
if ($CliTests) {
    $logs.cliTests    = LogPath 'cli-tests'
    $logs.cliTestsRun = LogPath 'cli-tests-run'
    & pwsh -NoProfile -File (Join-Path $PSScriptRoot 'worktree-test.ps1') -RepoRoot $repo -Project Tests/LinqToDB.CLI/Tests.LinqToDB.CLI.csproj -Tfm net10.0 -Configuration Testing -NoTestProgress -LogPath $logs.cliTestsRun *> $logs.cliTests
    $cliExit = $LASTEXITCODE
    if ($cliExit -ne 0) { $allOk = $false }
    $summary = $null
    try { $summary = (Get-Content $logs.cliTests -Raw | ConvertFrom-Json).summary } catch { }
    $cli = [ordered]@{ exitCode = $cliExit; summary = $summary }
}

Write-JsonOutput -InputObject ([ordered]@{
    ok         = $allOk
    generate   = $generateExit
    goldens    = [ordered]@{ rewritten = $rewritten; total = $after.Count; changed = $changed }
    goldenDiff = $goldenDiff
    gates      = $gates
    csharp     = $csharp
    cliTests   = $cli
    logs       = $logs
})
