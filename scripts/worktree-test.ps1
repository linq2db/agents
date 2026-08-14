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
                           Default: <cwd>/.build/.agents/worktree-test-<project>[-<tfm>].log

Output (stdout, single JSON object):
  {
    "ok":        true,               // exitCode 0
    "exitCode":  0,
    "buildFailed": false,            // true when the run never reached the tests
    "repoRoot":  "C:/Worktrees/...",
    "project":   "Tests/.../X.csproj",
    "logPath":   "C:/.../worktree-test-X-net10.0.log",
    "summary":   { "total": 186, "failed": 0, "succeeded": 168, "skipped": 18, "duration": "36s 628ms" },
    "failedTests": [ "SomeTest", ... ]
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
    [string]$LogPath
)

. "$PSScriptRoot/_shared.ps1"

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $RepoRoot -PathType Container)) {
    Exit-WithError -Message "RepoRoot not found: $RepoRoot" -NextAction 'pass -RepoRoot <absolute worktree path>'
}

$repoFull    = (Resolve-Path -LiteralPath $RepoRoot).Path
$projectFull = Join-Path $repoFull $Project

if (-not (Test-Path -LiteralPath $projectFull -PathType Leaf)) {
    Exit-WithError -Message "Project not found under RepoRoot: $projectFull" -NextAction 'pass -Project <path relative to RepoRoot>'
}

if (-not $LogPath) {
    $logDir = Join-Path (Get-Location).Path '.build/.agents'
    if (-not (Test-Path -LiteralPath $logDir)) { New-Item -ItemType Directory -Force -Path $logDir | Out-Null }
    $stem    = [System.IO.Path]::GetFileNameWithoutExtension($Project)
    $suffix  = if ($Tfm) { "-$Tfm" } else { '' }
    $LogPath = Join-Path $logDir "worktree-test-$stem$suffix.log"
}

if (-not [System.IO.Path]::IsPathRooted($LogPath)) {
    Exit-WithError -Message "LogPath must be absolute (the run's cwd is the worktree): $LogPath" -NextAction 'pass -LogPath <absolute path>'
}

$dotnetArgs = @('test', '--project', $projectFull, '-c', $Configuration)
if ($Tfm)      { $dotnetArgs += @('-f', $Tfm) }
if ($Filter)   { $dotnetArgs += @('--filter', $Filter) }
if ($Provider) { $dotnetArgs += @('--provider', ($Provider -join ',')) }

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
}

$summary     = $null
$failedTests = @()
$buildFailed = $false

if (Test-Path -LiteralPath $LogPath) {
    $lines = [System.IO.File]::ReadAllLines($LogPath)

    if ($lines | Where-Object { $_ -match '^Build failed' }) { $buildFailed = $true }

    foreach ($line in $lines) {
        if ($line -match '^failed\s+(\S+)') { $failedTests += $Matches[1] }
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

[ordered]@{
    ok          = ($exitCode -eq 0)
    exitCode    = $exitCode
    buildFailed = $buildFailed
    repoRoot    = $repoFull
    project     = $Project
    logPath     = $LogPath
    summary     = $summary
    failedTests = @($failedTests | Select-Object -Unique)
} | ConvertTo-Json -Depth 5

if ($exitCode -ne 0) { exit 1 }
