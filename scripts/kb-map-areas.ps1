<#
.SYNOPSIS
  Map a git delta's changed files to KB areas (the /kb-refresh `code` source, step 4).

.DESCRIPTION
  Parses the area table in .claude/docs/kb-areas.md (column 1 = area code, column 2 =
  backticked path globs) plus its "Excluded paths" list, runs
  `git diff --name-status <from>..<to>`, and buckets every changed path into each area
  whose glob matches it. A path can land in several areas (cross-listed globs). Paths
  that match no area and no exclusion are reported as `unmatched` - those are the
  candidates for extending kb-areas.md.

  Writes one `<outDir>/kb-refresh-files-<AREA>.txt` per area, one `<status>\t<path>`
  line each (renames keep `Rnnn\told\tnew`), ready to hand to kb-architect /
  kb-issue-detector as `changedFiles`.

  Glob dialect: `**/` = any directory depth, `**` = anything, `*` = within one segment,
  trailing `/` = whole subtree. Parenthesised notes after a glob are ignored.

.INPUT (JSON manifest via -ManifestFile or stdin)
  { "from": "<sha>", "to": "origin/master" }          # required: delta bounds
  { ..., "outDir": ".build/.agents" }                  # optional (default shown)
  { ..., "areasFile": ".claude/docs/kb-areas.md" }     # optional (default shown)

.OUTPUT (JSON)
  { "ok": true, "total": N, "excluded": N, "areaCount": N,
    "areas": [ { "area": "CORE", "count": 7, "file": ".build/.agents/kb-refresh-files-CORE.txt" }, ... ],
    "unmatched": [ "path", ... ] }
#>
param([string]$ManifestFile)

$ErrorActionPreference = 'Stop'

$raw = if ($ManifestFile) { [System.IO.File]::ReadAllText($ManifestFile) } else { [Console]::In.ReadToEnd() }
$m = $raw | ConvertFrom-Json
if (-not $m.from -or -not $m.to) { Write-Output (@{ ok = $false; error = 'from and to required' } | ConvertTo-Json -Compress); exit 1 }

$repoRoot  = (git rev-parse --show-toplevel).Trim()
$areasFile = Join-Path $repoRoot ($(if ($m.areasFile) { $m.areasFile } else { '.claude/docs/kb-areas.md' }))
$outDir    = Join-Path $repoRoot ($(if ($m.outDir) { $m.outDir } else { '.build/.agents' }))
New-Item -ItemType Directory -Force $outDir | Out-Null

function ConvertTo-GlobRegex([string]$g) {
	$g = $g.Trim().TrimStart('/').Replace('\', '/')
	$r = [regex]::Escape($g) -replace '\\\*\\\*/', '(?:.*/)?' -replace '\\\*\\\*', '.*' -replace '\\\*', '[^/]*' -replace '\\\?', '.'
	if ($g.EndsWith('/')) { $r += '.*' }
	'^' + $r + '$'
}

$lines = Get-Content $areasFile
$areas = [ordered]@{}
foreach ($l in $lines) {
	if ($l -notmatch '^\|\s*`([A-Z0-9-]+)`\s*\|([^|]*)\|') { continue }
	$globs = [regex]::Matches($Matches[2], '`([^`]+)`') | ForEach-Object { $_.Groups[1].Value }
	$areas[$Matches[1]] = @($globs | ForEach-Object { ConvertTo-GlobRegex $_ })
}

$excluded = @()
$inExcl = $false
foreach ($l in $lines) {
	if ($l -match '^## Excluded paths') { $inExcl = $true; continue }
	if ($inExcl -and $l -match '^## ') { break }
	if ($inExcl) { $excluded += [regex]::Matches($l, '`([^`]+)`') | ForEach-Object { ConvertTo-GlobRegex $_.Groups[1].Value } }
}

$changes = @(git -C $repoRoot diff --name-status $m.from $m.to)
$map = [ordered]@{}
$unmatched = @()
$excludedCount = 0
foreach ($c in $changes) {
	$path = ($c -split "`t")[-1]
	$hit = @($areas.Keys | Where-Object { $k = $_; @($areas[$k] | Where-Object { $path -match $_ }).Count -gt 0 })
	if ($hit.Count -eq 0) {
		if (@($excluded | Where-Object { $path -match $_ }).Count) { $excludedCount++ } else { $unmatched += $path }
		continue
	}
	foreach ($h in $hit) {
		if (-not $map.Contains($h)) { $map[$h] = [System.Collections.Generic.List[string]]::new() }
		$map[$h].Add($c)
	}
}

$result = foreach ($k in ($map.Keys | Sort-Object)) {
	$f = Join-Path $outDir "kb-refresh-files-$k.txt"
	[System.IO.File]::WriteAllLines($f, $map[$k])
	[ordered]@{ area = $k; count = $map[$k].Count; file = [System.IO.Path]::GetRelativePath($repoRoot, $f).Replace('\', '/') }
}

Write-Output ([ordered]@{
	ok        = $true
	total     = $changes.Count
	excluded  = $excludedCount
	areaCount = $map.Count
	areas     = @($result)
	unmatched = $unmatched
} | ConvertTo-Json -Depth 4)
