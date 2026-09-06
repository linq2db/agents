<#
analyzer-profile-build.ps1 — full Release rebuild with Roslyn analyzer
performance reports enabled, used by `/profile-analyzers` (and optionally
chained from `/release-deps` after an analyzer-package bump).

Invokes `dotnet build -t:Rebuild` with the four flags required to make
`/reportanalyzer` output reach the MSBuild log:

  -p:RunAnalyzersDuringBuild=true   # opt in to analyzer execution
  -p:ReportAnalyzer=true            # ask csc.exe to print the report
  -p:UseSharedCompilation=false     # bypass VBCSCompiler so report reaches stdout
  -v:detailed                        # MSBuild filters MessageImportance.Low at -v:normal

`-t:Rebuild` (instead of plain `Build`) is mandatory: incremental build
skips `CoreCompile` for up-to-date projects and emits no analyzer report
for them, leaving the ranking lopsided.

This script does NOT run `dotnet build-server shutdown`, and must not be
changed to. That command is machine-global - other people's builds, other
worktrees and the user's IDE share the same node pool - and it is prohibited
outright (`agent-rules.md`; global CLAUDE.md "Shared build server"). It is
also unnecessary: `-p:UseSharedCompilation=false` means MSBuild spawns
`csc.exe` directly rather than talking to VBCSCompiler, so a resident
compiler server cannot swallow the report, and `-t:Rebuild` already forces a
fresh `CoreCompile`. Measured: three runs with a 1.9 GB VBCSCompiler resident
throughout each emitted a complete analyzer table. The historical worry that
the server "swallows the report" applies to builds that actually use it.

`-c Release` is the default for the same reason: Release is where
`Directory.Build.props` gates `RunAnalyzersDuringBuild=true` +
`EnforceCodeStyleInBuild=true`. Without it, code-style analyzers (IDE0039
etc.) don't fire and any errors they would have surfaced ship to CI
unnoticed. `-Configuration` exists for the rare caller that needs another
one; it must then force `-p:RunAnalyzersDuringBuild=true` itself (this
script already passes it).

`-SolutionPath` also accepts a single `.csproj` — that is how
`/profile-analyzers`'s `rules` mode measures one target project
(`Source/LinqToDB/LinqToDB.csproj`, `Tests/Linq/Tests.csproj`) instead of
the whole solution.

Wall-clock cost on linq2db.slnx: 10-25 minutes. A *single project* is not
cheap either - Source/LinqToDB alone, one TFM, measured 20 minutes cold: the
build gives up the compiler server and Release loads the whole analyzer set
(565 analyzers on that project). Tests/Linq is larger again and can be
OOM-killed from cold on a busy box; build its dependencies first, then pass
`--no-dependencies` so only the target is instrumented.
The skill's contract is explicit user-confirmation before invoking; do not
auto-launch.

Output (single JSON object on stdout):
  { ok, logPath, exitCode, elapsedMs }

Conventions: `.claude/docs/script-authoring.md`.
#>

[CmdletBinding()]
param(
    [Alias('ProjectPath')]
    [string]   $SolutionPath = 'linq2db.slnx',
    [Parameter(Mandatory)][string] $LogPath,
    [string]   $Target = 'Rebuild',
    [string]   $Configuration = 'Release',
    [string[]] $ExtraArgs = @()
)

$global:ScriptBaseName = 'analyzer-profile-build'
. (Join-Path $PSScriptRoot '_shared.ps1')

if (-not (Test-Path -LiteralPath $SolutionPath)) {
    Exit-WithError "Build target not found: $SolutionPath (CWD: $(Get-Location))" `
        -NextAction 'pass -SolutionPath (alias -ProjectPath) as a path to an existing .slnx / .slnf / .csproj, relative to the CWD'
}

$logDir = Split-Path -Parent $LogPath
if ($logDir -and -not (Test-Path -LiteralPath $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

$buildArgs = @(
    'build', $SolutionPath,
    "-t:$Target",
    '-c', $Configuration,
    '-p:RunAnalyzersDuringBuild=true',
    '-p:ReportAnalyzer=true',
    '-p:UseSharedCompilation=false',
    '-v:detailed'
) + $ExtraArgs

[Console]::Error.WriteLine("Starting build: dotnet $($buildArgs -join ' ')")
[Console]::Error.WriteLine("Log file:       $LogPath")
$isSolution = $SolutionPath -match '\.slnx?$|\.slnf$'
[Console]::Error.WriteLine($(if ($isSolution) {
    "Expected wall-clock: 10-25 minutes on a full solution"
} else {
    "Expected wall-clock: 20+ minutes for a single project (no compiler server, full Release analyzer set)"
}))

$sw = [System.Diagnostics.Stopwatch]::StartNew()
& dotnet @buildArgs *> $LogPath
$exit = $LASTEXITCODE
$sw.Stop()

$status = if ($exit -eq 0) { 'succeeded' } else { "FAILED (exit $exit)" }
[Console]::Error.WriteLine(("Build {0} in {1}. Log: {2}" -f $status, $sw.Elapsed.ToString('hh\:mm\:ss'), $LogPath))

Write-JsonOutput @{
    ok        = ($exit -eq 0)
    action    = 'build'
    logPath   = (Resolve-Path -LiteralPath $LogPath).Path
    exitCode  = $exit
    elapsedMs = [int64]$sw.Elapsed.TotalMilliseconds
}
