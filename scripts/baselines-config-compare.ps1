#!/usr/bin/env pwsh
<#
Cross-compare two provider configurations' baselines inside one `linq2db.baselines` ref, strip the
divergence categories the caller already expects, and report what is left.

Why this script exists
----------------------
"Does provider flavour L emit the same SQL as reference flavour R, except at the divergences we
named?" is the test obligation every new provider flavour carries (#5956 TO-2: LibRed against its
OLE DB twin). `baselines-reviewer` answers it by reading, which cannot prove a negative over ~8 000
files. This answers it mechanically: pair the two directories by file name, rewrite each line
through the caller's known categories, and list the files that still differ. An empty residual is
the claim; every residual file is either a new category to name or a finding.

Contract
--------

Input (named parameters):
  -Pair          <string[]> required; one or more `Left=Right` configuration directory names,
                            e.g. `Access.LibRed.Accdb=Access.Ace.OleDb`
  -Ref           <string>   git ref in the baselines clone; default `origin/baselines/pr_<Pr>`
  -Pr            <int>      PR number, used when -Ref is omitted
  -DropLine      <string[]> regexes; a matching line is removed on both sides before comparing.
                            Default `^-- ` (statement headers name the configuration and provider)
  -Rewrite       <string[]> `regex=>replacement` items applied to every remaining line, in order,
                            e.g. `@\w+=>@P` (parameter names) or `\[Database\\TestData\]\.=>`
  -BaselinesRepo <path>     default: the sibling `linq2db.baselines` clone (`Resolve-BaselinesClone`)
  -WriteDir      <path>     optional; full residual written to `<WriteDir>/residual.json`
  -MaxLines      <int>      residual lines per file in stdout; default 8

The configuration name is always replaced by a placeholder first, so it never counts as a
difference. Files are read through `git archive` (one process, not one `git show` per file).

Output (stdout, single JSON object):
  { "ref": "...", "pairs": [ { "left", "right", "paired", "identical", "onlyLeft", "onlyRight",
    "residualCount", "residual": [ { "file", "lines": [ "<= ...", "=> ..." ] } ] } ] }

`onlyLeft` / `onlyRight` are counts, not findings: the right side usually carries stale files from
master (renamed or re-parameterised tests that nothing deletes), and gated tests exist on one side.

Exit codes:
  0 = comparison completed
  1 = bad input (ref or configuration directory not found)
#>

param(
	[Parameter(Mandatory = $true)][string[]]$Pair,
	[string]$Ref,
	[int]$Pr,
	[string[]]$DropLine = @('^-- '),
	[string[]]$Rewrite = @(),
	[string]$BaselinesRepo,
	[string]$WriteDir,
	[int]$MaxLines = 8
)

$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/_shared.ps1"

function Fail([string]$message) {
	[Console]::Out.WriteLine((@{ error = $message } | ConvertTo-Json -Compress))
	exit 1
}

$BaselinesRepo = Resolve-BaselinesClone -Path $BaselinesRepo
if (-not (Test-Path -LiteralPath $BaselinesRepo)) { Fail "baselines repo not found: $BaselinesRepo" }
$repo = (Resolve-Path -LiteralPath $BaselinesRepo).Path

if (-not $Ref) {
	if (-not $Pr) { Fail 'pass -Ref or -Pr' }
	$Ref = "origin/baselines/pr_$Pr"
}
& git -C $repo rev-parse --verify --quiet "$Ref^{commit}" | Out-Null
if ($LASTEXITCODE -ne 0) { Fail "ref not found: $Ref (fetch it first)" }

$pairs = foreach ($p in $Pair) {
	$lr = $p -split '=', 2
	if ($lr.Count -ne 2 -or -not $lr[0] -or -not $lr[1]) { Fail "pair must be Left=Right: $p" }
	[pscustomobject]@{ L = $lr[0].Trim(); R = $lr[1].Trim() }
}

$rewrites = foreach ($r in $Rewrite) {
	$parts = $r -split '=>', 2
	if ($parts.Count -ne 2) { Fail "rewrite must be regex=>replacement: $r" }
	[pscustomobject]@{ Pattern = $parts[0]; Replacement = $parts[1] }
}

$dirs = @($pairs | ForEach-Object { $_.L; $_.R } | Sort-Object -Unique)
foreach ($d in $dirs) {
	$hit = & git -C $repo ls-tree --name-only $Ref -- $d
	if (-not $hit) { Fail "configuration directory not in ${Ref}: $d" }
}

$scratch = Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../.build/.agents'))) ("baselines-config-compare-" + [Guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force $scratch | Out-Null

try {
	$tarFile = Join-Path $scratch 'tree.tar'
	& git -C $repo archive --format=tar -o $tarFile $Ref -- @dirs
	if ($LASTEXITCODE -ne 0) { Fail "git archive failed for $Ref" }
	& tar -xf $tarFile -C $scratch
	if ($LASTEXITCODE -ne 0) { Fail 'tar extraction failed' }

	function Get-Normalized([string]$path, [string]$config) {
		foreach ($line in [IO.File]::ReadAllLines($path)) {
			$s = $line.TrimStart([char]0xFEFF).Replace($config, '<CFG>')
			$drop = $false
			foreach ($d in $DropLine) { if ($s -match $d) { $drop = $true; break } }
			if ($drop) { continue }
			foreach ($rw in $rewrites) { $s = $s -replace $rw.Pattern, $rw.Replacement }
			$s
		}
	}

	function Get-Index([string]$root, [string]$config) {
		$map = @{}
		$len = $root.Length
		foreach ($f in Get-ChildItem -LiteralPath $root -Recurse -File) {
			$map[$f.FullName.Substring($len).Replace($config, '<CFG>')] = $f.FullName
		}
		return $map
	}

	$results = foreach ($p in $pairs) {
		$left  = Get-Index (Join-Path $scratch $p.L) $p.L
		$right = Get-Index (Join-Path $scratch $p.R) $p.R

		$paired = 0; $identical = 0; $residual = @()
		foreach ($key in ($left.Keys | Sort-Object)) {
			if (-not $right.ContainsKey($key)) { continue }
			$paired++
			$a = @(Get-Normalized $right[$key] $p.R)
			$b = @(Get-Normalized $left[$key] $p.L)
			if (($a -join "`n") -ceq ($b -join "`n")) { $identical++; continue }
			$diff = @(Compare-Object $a $b -SyncWindow ([Math]::Max($a.Count, $b.Count)) -CaseSensitive |
				ForEach-Object { "$($_.SideIndicator) $($_.InputObject)" })
			if ($diff.Count -eq 0) { $diff = @('(same lines, different order)') }
			$residual += [pscustomobject]@{ file = $key.TrimStart('\', '/').Replace('\', '/'); lines = $diff }
		}

		[pscustomobject]@{
			left          = $p.L
			right         = $p.R
			paired        = $paired
			identical     = $identical
			onlyLeft      = @($left.Keys | Where-Object { -not $right.ContainsKey($_) }).Count
			onlyRight     = @($right.Keys | Where-Object { -not $left.ContainsKey($_) }).Count
			residualCount = $residual.Count
			residual      = $residual
		}
	}

	if ($WriteDir) {
		New-Item -ItemType Directory -Force $WriteDir | Out-Null
		$results | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $WriteDir 'residual.json') -Encoding utf8
	}

	$out = [ordered]@{
		ref   = $Ref
		pairs = @($results | ForEach-Object {
			[ordered]@{
				left          = $_.left
				right         = $_.right
				paired        = $_.paired
				identical     = $_.identical
				onlyLeft      = $_.onlyLeft
				onlyRight     = $_.onlyRight
				residualCount = $_.residualCount
				residual      = @($_.residual | ForEach-Object { [ordered]@{ file = $_.file; lines = @($_.lines | Select-Object -First $MaxLines) } })
			}
		})
	}
	[Console]::Out.WriteLine(($out | ConvertTo-Json -Depth 6))
}
finally {
	Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue
}
