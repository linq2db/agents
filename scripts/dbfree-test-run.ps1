<#
.SYNOPSIS
    Run a DB-free test project (analyzer fixtures, tooling tests) and return a compact JSON summary.

.DESCRIPTION
    Collapses the run-then-grep-the-log pair into one call. Emits the pass/fail
    tally, the names of the failed tests, and — separately — any compiler errors
    the run produced.

    That last field is the point. A test failure and a build failure are both
    non-zero, so matching on "non-zero" records a red that never executed a
    single test. This is the shape a mutation proof needs: it has to distinguish
    "the fixture reddened for its mechanism" from "the snippet did not compile".

    Do NOT pass --test-progress to these projects. They host a bare NUnit MTP
    runner that does not register the extension, so the option reaches the test
    application, which prints its help and exits 5 - surfaced as `Zero tests
    ran`, byte-identical to a bad --filter. This script never adds it.

.EXAMPLE
    pwsh -NoProfile -File .claude/scripts/dbfree-test-run.ps1 -Project Tests/Tests.Analyzers.Internal/Tests.Analyzers.Internal.csproj
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Project,
    [string]$Configuration = 'Release',
    [string]$RepoRoot,
    [string]$LogPath,
    [switch]$NoBuild
)

$global:ScriptBaseName = 'dbfree-test-run'
. "$PSScriptRoot/_shared.ps1"

if (-not $RepoRoot) { $RepoRoot = (Resolve-Path "$PSScriptRoot/../..").Path }

if (-not (Test-Path $RepoRoot)) {
    Exit-WithError -Message "repo root '$RepoRoot' does not exist" -Code 2 -NextAction 'pass -RepoRoot <path to the linq2db checkout>'
}

$projectPath = if ([System.IO.Path]::IsPathRooted($Project)) { $Project } else { Join-Path $RepoRoot $Project }

if (-not (Test-Path $projectPath)) {
    Exit-WithError -Message "project '$projectPath' not found" -Code 2 -NextAction 'pass -Project <path to the .csproj>, relative to the repo root or absolute'
}

if (-not $LogPath) {
    $agents = Join-Path $RepoRoot '.build/.agents'
    if (-not (Test-Path $agents)) { New-Item -ItemType Directory -Force -Path $agents | Out-Null }
    $stem   = [System.IO.Path]::GetFileNameWithoutExtension($projectPath)
    $LogPath = Join-Path $agents "dbfree-test-$stem-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
}

$arguments = @('test', '--project', $projectPath, '-c', $Configuration)
if ($NoBuild) { $arguments += '--no-build' }

$result = Invoke-Process -FilePath 'dotnet' -ArgumentList $arguments -WorkingDirectory $RepoRoot

$output = @($result.stdout, $result.stderr) -join "`n"
[System.IO.File]::WriteAllText($LogPath, $output, (New-Object System.Text.UTF8Encoding $false))

$lines = $output -split "`r?`n"

function Get-Tally([string]$label) {
    foreach ($line in $lines) {
        if ($line -match "^\s*$label\s*:\s*(\d+)\s*$") { return [int]$Matches[1] }
    }
    return $null
}

$failedTests = @()
foreach ($line in $lines) {
    if ($line -match '^\s*failed\s+(\S+)') { $failedTests += $Matches[1] }
}

# Distinct only - the runner echoes each compiler error once per expectation block.
$compilerErrors = @($lines | Where-Object { $_ -match '\berror\s+CS\d+\b' } | ForEach-Object { $_.Trim() } | Select-Object -Unique)

$total     = Get-Tally 'total'
$failed    = Get-Tally 'failed'
$succeeded = Get-Tally 'succeeded'

# A run too short to have compiled anything did not build. Callers reading only
# the tally cannot see that, so say it here.
$ranTests = $null -ne $total

Write-JsonOutput ([ordered]@{
    project        = $projectPath
    configuration  = $Configuration
    exitCode       = $result.code
    ranTests       = $ranTests
    total          = $total
    failed         = $failed
    succeeded      = $succeeded
    failedTests    = @($failedTests | Select-Object -Unique)
    compilerErrors = $compilerErrors
    verdict        = if (-not $ranTests) { 'no-tests-ran' }
                     elseif ($compilerErrors.Count -gt 0) { 'failed-to-compile' }
                     elseif ($failed -gt 0) { 'tests-failed' }
                     else { 'green' }
    log            = $LogPath
})
