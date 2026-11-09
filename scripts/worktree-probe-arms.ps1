#!/usr/bin/env pwsh
<#
Run one test filter in a worktree against several versions of Source/, and report each arm.

Why this exists
---------------
A review or fix proves a regression by running the same probe on the head and on a control
(master, the reviewed head, or a mutated tree). Hand-written, that is a throwaway script per
round: check out a ref's Source/, run, copy the logs, restore. It went wrong in two ways on
#6197: a text round trip dropped a file's UTF-8 BOM, and a forgotten restore would leave the
tree on the control. This script keeps the file bytes and always restores through git.

Usage
-----
    worktree-probe-arms.ps1 -Worktree <abs> -Filter '<filter>' -Provider SQLite.MS,DuckDB
        -Arms head,83a7117d4 [-Mutate '<file>|||<old>|||<new>'] [-ProbeLog <abs>] [-OutDir <abs>]

  -Worktree   required; absolute worktree root. Source/ must be clean.
  -Filter     required; passed to worktree-test.ps1. Include the CreateData.CreateDatabase term.
  -Provider   required; comma list. `.LinqService` runs with its base provider.
  -Arms       comma list, default `head`. `head` is the current tree; anything else is a ref
              whose Source/ is checked out for that arm.
  -Mutate     optional; one more arm, `mutant`, on the current tree with the literal text replaced
              in <file> (relative to the worktree). <old> must occur exactly once.
  -ProbeLog   optional; a file the tests write. Removed before each arm and copied to OutDir.
  -OutDir     optional; default <Worktree>/.build/.agents/probe-arms.
  -Project / -Tfm / -Configuration   defaults Tests/Linq/Tests.csproj, net10.0, Testing.

Prints one JSON object: { ok, arms: [ { name, ok, failed, succeeded, skipped, total,
failedTests, runLog, probeLog } ] }. `ok` means every arm ran; a failed test is a result, not an
error, because a control is expected to go red.

Each arm builds, so allow several minutes per arm and run it in the background.
#>
param(
	[Parameter(Mandatory)][string]$Worktree,
	[Parameter(Mandatory)][string]$Filter,
	[Parameter(Mandatory)][string]$Provider,
	[string]$Arms          = 'head',
	[string]$Mutate,
	[string]$ProbeLog,
	[string]$OutDir,
	[string]$Project       = 'Tests/Linq/Tests.csproj',
	[string]$Tfm           = 'net10.0',
	[string]$Configuration = 'Testing'
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/_shared.ps1"

if (-not (Test-Path (Join-Path $Worktree '.git')))
{
	Exit-WithError "not a worktree root: $Worktree" -NextAction 'pass the absolute worktree root as -Worktree'
}

$dirty = @(git -C $Worktree status --porcelain -- Source)
if ($dirty.Count -gt 0)
{
	Exit-WithError "Source/ has uncommitted changes: restoring an arm would discard them" -NextAction 'commit or stash the Source/ changes first'
}

if (-not $OutDir) { $OutDir = Join-Path $Worktree '.build/.agents/probe-arms' }
New-Item -ItemType Directory -Force $OutDir | Out-Null

$armList = @($Arms.Split(',', [StringSplitOptions]::RemoveEmptyEntries) | ForEach-Object { $_.Trim() })

function Invoke-Arm([string] $name)
{
	if ($ProbeLog -and (Test-Path $ProbeLog)) { Remove-Item $ProbeLog }

	$safeName = $name -replace '[^\w.-]', '_'
	$runLog   = Join-Path $OutDir "$safeName-run.log"
	$output   = & pwsh -NoProfile -File "$PSScriptRoot/worktree-test.ps1" -RepoRoot $Worktree -Project $Project -Tfm $Tfm -Filter $Filter -Provider $Provider -Configuration $Configuration -LogPath $runLog
	$result   = ($output -join "`n") | ConvertFrom-Json

	$kept = $null
	if ($ProbeLog -and (Test-Path $ProbeLog))
	{
		$kept = Join-Path $OutDir "$safeName-probe.log"
		Copy-Item $ProbeLog $kept -Force
	}

	return [ordered]@{
		name        = $name
		ok          = [bool]$result.ok
		buildFailed = [bool]$result.buildFailed
		total       = $result.summary.total
		failed      = $result.summary.failed
		succeeded   = $result.summary.succeeded
		skipped     = $result.summary.skipped
		failedTests = @($result.failedTests)
		runLog      = $runLog
		probeLog    = $kept
	}
}

$results = [System.Collections.Generic.List[object]]::new()

try
{
	foreach ($arm in $armList)
	{
		if ($arm -ne 'head')
		{
			git -C $Worktree checkout $arm -- Source
			if ($LASTEXITCODE -ne 0) { Exit-WithError "cannot check out Source/ from $arm" -NextAction 'pass a ref the worktree can resolve' }
		}

		try { $results.Add((Invoke-Arm $arm)) }
		finally
		{
			if ($arm -ne 'head') { git -C $Worktree restore --source=HEAD --staged --worktree -- Source }
		}
	}

	if ($Mutate)
	{
		$parts = $Mutate -split '\|\|\|'
		if ($parts.Count -ne 3) { Exit-WithError 'Mutate must be <file>|||<old>|||<new>' -NextAction "pass -Mutate '<file>|||<old>|||<new>'" }

		$file = Join-Path $Worktree $parts[0]
		$text = [Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($file))

		$count = ([regex]::Matches($text, [regex]::Escape($parts[1]))).Count
		if ($count -ne 1) { Exit-WithError "Mutate text occurs $count times in $($parts[0])" -NextAction 'pass text that occurs exactly once' }

		# GetString keeps the BOM as U+FEFF, so GetBytes writes it back.
		[IO.File]::WriteAllBytes($file, [Text.Encoding]::UTF8.GetBytes($text.Replace($parts[1], $parts[2])))

		try { $results.Add((Invoke-Arm 'mutant')) }
		finally { git -C $Worktree checkout -- $parts[0] }
	}
}
finally
{
	$left = @(git -C $Worktree status --porcelain -- Source)
	if ($left.Count -gt 0) { [Console]::Error.WriteLine("worktree-probe-arms: Source/ not clean after restore: $($left -join '; ')") }
}

Write-JsonOutput ([ordered]@{ ok = $true; arms = $results.ToArray() })
