#!/usr/bin/env pwsh
<#
Compare per-cell verdicts that a recording test wrote into the baselines of two
`linq2db.baselines` refs, cell by cell, for every provider.

Why this script exists
----------------------
A recording test (a fixture with `RecordVerdicts = true`, e.g.
`OperatorPrecedenceTests.Matrix`) passes by design and writes one line per case,
`-- cell <id>: green|red|error|skipped`, into each provider's baseline file. Two CI
runs push those files to a baselines branch, so "did any case that was green on
master turn red here" is a diff of two refs. Done by hand that is ls-tree, one
`git show` per file (~1000), and a compare loop, repeated after every CI round.
This script does it in one call, reading each ref through one `git cat-file --batch`.

    pwsh -NoProfile -File .claude/scripts/matrix-verdicts-diff.ps1 -MasterRef <sha> -HeadRef <sha>

Parameters
----------
  -MasterRef      baselines ref holding the control run (e.g. a run on master code)   required
  -HeadRef        baselines ref holding the run under test                            required
  -BaselinesRepo  path of the linq2db.baselines clone        default: ../linq2db.baselines next to the repo root
  -FilePattern    regex on the repo-relative path of the files to read
                  default: 'OperatorPrecedenceTests\.Matrix'
  -Fetch          run `git fetch origin` in the baselines clone first

The provider is the first path segment (`<Provider>/Tests/...`). A cell is keyed by
provider and id; a cell present in only one ref is not compared.

Output (stdout, one JSON object)
--------------------------------
  {
    "masterRef": "...", "headRef": "...",
    "files":     { "master": 994, "head": 994 },
    "compared":  53676,
    "fixed":     2268,                       // red / error on master, green on head
    "regressions": [ "YDB|Predicate/IsNull(Or(a,n)) (green -> red)" ],
    "stillRed":  { "YDB": 8 },               // red / error on both, per provider
    "stillRedCells": [ "YDB|Concat/Join(s,Add(b,c),c) (error)" ]
  }

Exit codes: 0 = no regressions; 1 = at least one regression; 2 = bad input / git failure.
#>

[CmdletBinding()]
param(
	[Parameter(Mandatory)][string] $MasterRef,
	[Parameter(Mandatory)][string] $HeadRef,
	[string] $BaselinesRepo,
	[string] $FilePattern = 'OperatorPrecedenceTests\.Matrix',
	[switch] $Fetch
)

. "$PSScriptRoot/_shared.ps1"
$global:ScriptBaseName = 'matrix-verdicts-diff'

if (-not $BaselinesRepo) {
	$repoRoot      = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
	$BaselinesRepo = Join-Path (Split-Path $repoRoot -Parent) 'linq2db.baselines'
}

if (-not (Test-Path (Join-Path $BaselinesRepo '.git'))) {
	Exit-WithError "not a git clone: $BaselinesRepo" 2
}

if ($Fetch) {
	git -C $BaselinesRepo fetch origin --quiet 2>&1 | Out-Null
}

function Read-Verdicts([string] $ref)
{
	$paths = @(git -C $BaselinesRepo ls-tree -r --name-only $ref 2>$null | Where-Object { $_ -match $FilePattern })
	if ($LASTEXITCODE -ne 0) { Exit-WithError "git ls-tree failed for ref '$ref'" 2 }

	$map = @{}

	if ($paths.Count -eq 0) { return @{ Map = $map; Files = 0 } }

	# one cat-file process per ref; it answers each object with a "<sha> blob <size>" header line, in input order
	$output = $paths | ForEach-Object { "${ref}:$_" } | git -C $BaselinesRepo cat-file --batch
	if ($LASTEXITCODE -ne 0) { Exit-WithError "git cat-file failed for ref '$ref'" 2 }

	$index    = -1
	$provider = $null

	foreach ($line in $output)
	{
		if ($line -match '^[0-9a-f]{40} blob \d+$')
		{
			$index++
			$provider = ($paths[$index] -split '/')[0]
		}
		elseif ($provider -and $line -match '^﻿?-- cell (\S+): (\w+)\s*$')
		{
			$map["$provider|$($Matches[1])"] = $Matches[2]
		}
	}

	return @{ Map = $map; Files = $paths.Count }
}

$master = Read-Verdicts $MasterRef
$head   = Read-Verdicts $HeadRef

$compared     = 0
$fixed        = 0
$regressions  = [System.Collections.Generic.List[string]]::new()
$stillRedList = [System.Collections.Generic.List[string]]::new()
$stillRed     = @{}

foreach ($key in $head.Map.Keys)
{
	if (-not $master.Map.ContainsKey($key)) { continue }

	$compared++

	$before = $master.Map[$key]
	$after  = $head.Map[$key]
	$badBefore = $before -in 'red', 'error'
	$badAfter  = $after  -in 'red', 'error'

	if ($before -eq 'green' -and $badAfter) { $regressions.Add("$key ($before -> $after)") }
	elseif ($badBefore -and $after -eq 'green') { $fixed++ }
	elseif ($badBefore -and $badAfter)
	{
		$stillRedList.Add("$key ($after)")
		$provider = ($key -split '\|')[0]
		$stillRed[$provider] = 1 + ($stillRed[$provider] ?? 0)
	}
}

[pscustomobject]@{
	masterRef     = $MasterRef
	headRef       = $HeadRef
	files         = [pscustomobject]@{ master = $master.Files; head = $head.Files }
	compared      = $compared
	fixed         = $fixed
	regressions   = @($regressions | Sort-Object)
	stillRed      = $stillRed
	stillRedCells = @($stillRedList | Sort-Object)
} | ConvertTo-Json -Depth 4

exit ($regressions.Count -gt 0 ? 1 : 0)
