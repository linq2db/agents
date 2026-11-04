#!/usr/bin/env pwsh
<#
.SYNOPSIS
Compare a local baselines capture tree with linq2db.baselines' master and a PR's baselines branch.

.DESCRIPTION
A local test run writes its SQL baselines under `BaselinesPath` (UserDataProviders.json). This script
classifies every captured `.sql` file against two refs in the baselines clone:

  - `-MasterRef`  (default origin/master) — what master renders;
  - `-PrRef`      (e.g. origin/baselines/pr_5673) — what the PR under change renders on CI.

Each file is one of:
  equal-both      unchanged against both refs;
  to-master       differs from the PR ref and equals master (a move back to master);
  pr-only         equals the PR ref but not master (an existing PR change this run keeps);
  elsewhere       differs from both refs (the case to inspect file by file);
  new             absent from both refs (a baseline the run added);
  new-on-pr       absent from master, present on the PR ref.

Captures under `a_CreateData` are skipped. Line endings are normalised; a trailing newline difference
is ignored.

Fetch the refs first (spell both refspec sides):
  git -C <baselines> fetch origin +refs/heads/master:refs/remotes/origin/master
  git -C <baselines> fetch origin +refs/heads/baselines/pr_<n>:refs/remotes/origin/baselines/pr_<n>

.EXAMPLE
& .claude/scripts/compare-baselines-capture.ps1 -Captures C:\Worktrees\linq2db\<wt>\.build\.agents\bls -PrRef origin/baselines/pr_5673

.OUTPUTS
JSON: { total, counts: { <class>: n }, files: [ { file, class } ] } — `files` lists every file not in
equal-both (pass -All to list those too). Exit 0 always; 1 on bad arguments.
#>
[CmdletBinding()]
param(
	[Parameter(Mandatory)][string]$Captures,
	[Parameter(Mandatory)][string]$PrRef,
	[string]$MasterRef     = 'origin/master',
	[string]$BaselinesRepo = 'C:\GitHub\linq2db.baselines',
	[string]$Filter        = '*',
	[switch]$All
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $Captures))      { [Console]::Error.WriteLine("compare-baselines-capture: no capture tree at $Captures"); exit 1 }
if (-not (Test-Path $BaselinesRepo)) { [Console]::Error.WriteLine("compare-baselines-capture: no baselines clone at $BaselinesRepo"); exit 1 }

# One `git ls-tree` per ref instead of a `git show` per missing file.
function Get-RefFiles([string]$ref)
{
	$set = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
	foreach ($line in (& git -C $BaselinesRepo ls-tree -r --name-only $ref))
	{
		[void]$set.Add($line)
	}
	if ($LASTEXITCODE -ne 0) { [Console]::Error.WriteLine("compare-baselines-capture: cannot list $ref (fetch it first)"); exit 1 }
	return $set
}

function Get-Blob([string]$ref, [string]$path)
{
	$text = & git -C $BaselinesRepo show "${ref}:$path" 2>$null
	return (($text -join "`n") -replace "`r", '').TrimEnd()
}

$masterFiles = Get-RefFiles $MasterRef
$prFiles     = Get-RefFiles $PrRef
$root        = (Resolve-Path $Captures).Path.TrimEnd('\')

$rows = foreach ($file in Get-ChildItem $root -Recurse -File -Filter "$Filter.sql")
{
	$rel = $file.FullName.Substring($root.Length + 1).Replace('\', '/')
	if ($rel -like '*a_CreateData*') { continue }

	$inMaster = $masterFiles.Contains($rel)
	$inPr     = $prFiles.Contains($rel)

	$class = if (-not $inMaster -and -not $inPr) { 'new' }
	else
	{
		$local = ((Get-Content $file.FullName -Raw) -replace "`r", '').TrimEnd()
		$eqM   = $inMaster -and ($local -ceq (Get-Blob $MasterRef $rel))
		$eqP   = $inPr     -and ($local -ceq (Get-Blob $PrRef     $rel))

		if     (-not $inMaster) { if ($eqP) { 'new-on-pr' } else { 'elsewhere' } }
		elseif ($eqM -and $eqP) { 'equal-both' }
		elseif ($eqM)           { 'to-master' }
		elseif ($eqP)           { 'pr-only' }
		else                    { 'elsewhere' }
	}

	[pscustomobject]@{ file = $rel; class = $class }
}

$rows   = @($rows)
$counts = [ordered]@{}
foreach ($g in ($rows | Group-Object class | Sort-Object Name)) { $counts[$g.Name] = $g.Count }

[pscustomobject]@{
	total  = $rows.Count
	counts = $counts
	files  = @($rows | Where-Object { $All -or $_.class -ne 'equal-both' })
} | ConvertTo-Json -Depth 4
