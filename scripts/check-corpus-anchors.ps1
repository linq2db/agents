#!/usr/bin/env pwsh
#requires -Version 7
<#
.SYNOPSIS
    Resolve every `<doc>.md → *Section*` reference in the corpus and report the ones
    whose section no longer exists.

.DESCRIPTION
    The section half of /audit-agents' dead-reference check (2a in audit-agents-checks.md);
    check-corpus-links.ps1 resolves the file half only. A reference is a doc name followed by
    an arrow and an emphasised name:

        [`pr-and-push.md`](pr-and-push.md) → *Creating a PR*
        `agent-rules.md` -> **Temp files**
        agent-guardrails.md → *Verify subagent output…*

    The doc is a markdown link target, a backticked name or a bare name, resolved with the
    same conventions as check-corpus-links.ps1, then by unique basename. The name resolves
    when it is a case-insensitive prefix of a heading or of any `**bold**` span in that doc
    (or the reverse); a trailing `…` / `...` marks an intended prefix. Only the first name
    after the arrow is checked. A reference wrapped onto the next line is found; one with no
    arrow ("the *X* rule in AGENTS.md") is not, nor is a `file:line` citation.

    `plans/` (frozen records) and `knowledge-base/` (generated) are skipped unless
    -IncludeFrozen. Targets outside the corpus (the superproject's root AGENTS.md,
    Source/**) are counted as skipped.

.PARAMETER Root
    Corpus root. Defaults to this script's parent directory.

.PARAMETER IncludeFrozen
    Also scan plans/ and knowledge-base/.

.PARAMETER FailOnBroken
    Exit non-zero when any reference is unresolved.

.OUTPUTS
    One JSON object: { checked, skipped, broken: [ { file, line, doc, name, reason } ] }
#>
[CmdletBinding()]
param(
	[string]$Root,
	[switch]$IncludeFrozen,
	[switch]$FailOnBroken
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/_shared.ps1"
$global:ScriptBaseName = 'check-corpus-anchors'

if (-not $Root) { $Root = (Resolve-Path "$PSScriptRoot/..").Path }
if (-not (Test-Path -LiteralPath (Join-Path $Root 'AGENTS.md'))) {
	Exit-WithError -Message "Not a corpus root: $Root (no AGENTS.md)" -NextAction 'pass -Root <corpus-root>'
}

$tracked = @(& git -C $Root ls-files '*.md' '*.ps1' '*.js')
if ($LASTEXITCODE -ne 0 -or $tracked.Count -eq 0) {
	Exit-WithError -Message "git ls-files found nothing under $Root" -NextAction 'run from a corpus git checkout, or pass -Root <corpus-root>'
}
$mdFiles = @($tracked | Where-Object { $_ -like '*.md' })
$byName  = $mdFiles | Group-Object { Split-Path -Leaf $_ } -AsHashTable -AsString
$rootFull = [System.IO.Path]::GetFullPath($Root)

function Get-Normalized([string]$s) {
	$s = ($s -replace '\*', '') -replace '\s+', ' '
	$s = $s.Trim().TrimEnd('…').TrimEnd('.').Trim().TrimEnd(':', ',', ';', '—', '-').Trim()
	$s.ToLowerInvariant()
}

$targetCache = @{}
function Get-Targets([string]$rel) {
	if ($targetCache.ContainsKey($rel)) { return $targetCache[$rel] }
	$set = [System.Collections.Generic.List[string]]::new()
	foreach ($line in [System.IO.File]::ReadAllLines((Join-Path $Root $rel))) {
		if ($line -match '^\s{0,3}#{1,6}\s+(.+?)\s*#*\s*$') { $set.Add((Get-Normalized $Matches[1])) }
		# A bold span may itself contain *italic*, so match to the next `**`, not the next `*`.
		foreach ($m in ([regex]'\*\*((?:(?!\*\*).)+)\*\*').Matches($line)) { $set.Add((Get-Normalized $m.Groups[1].Value)) }
	}
	$targetCache[$rel] = $set
	$set
}

function Resolve-Doc([string]$doc, [string]$fromDir) {
	if ($doc -match '^(https?:|[A-Za-z]:[\\/])') { return $null }
	$candidates = @()
	if ($doc.StartsWith('.claude/')) { $candidates += $doc.Substring('.claude/'.Length) }
	if ($fromDir) { $candidates += (Join-Path $fromDir $doc) }
	$candidates += $doc
	foreach ($c in $candidates) {
		$full = [System.IO.Path]::GetFullPath((Join-Path $Root $c))
		if ($full.StartsWith($rootFull, 'OrdinalIgnoreCase') -and (Test-Path -LiteralPath $full -PathType Leaf)) {
			return [System.IO.Path]::GetRelativePath($rootFull, $full).Replace('\', '/')
		}
	}
	$leaf = Split-Path -Leaf $doc
	if ($byName.ContainsKey($leaf) -and @($byName[$leaf]).Count -eq 1) { return @($byName[$leaf])[0] }
	return $null
}

# doc (link target | backticked | bare)  arrow  *name* / **name**
$refRegex = [regex]'(?:\]\((?<doc>[^)\s#]+\.md)(?:#[^)\s]*)?\)|`(?<doc>[^`\s]+\.md)`|(?<doc>(?<![\w`/.-])[\w./-]+\.md))\s*(?:→|->)\s*\*{1,2}(?<name>[^*]+?)\*{1,2}'

$broken  = [System.Collections.Generic.List[object]]::new()
$checked = 0
$skipped = 0

foreach ($rel in $tracked) {
	if (-not $IncludeFrozen -and $rel -match '^(plans|knowledge-base)/') { continue }
	$full = Join-Path $Root $rel
	if (-not (Test-Path -LiteralPath $full)) { continue }
	$dir   = Split-Path -Parent $rel
	$lines = [System.IO.File]::ReadAllLines($full)
	for ($i = 0; $i -lt $lines.Count; $i++) {
		# A reference may wrap: match line i joined with line i+1, keeping matches that start on line i
		# (those wholly on line i+1 are found on the next iteration).
		$cur    = $lines[$i]
		$joined = if ($i + 1 -lt $lines.Count) { $cur + ' ' + $lines[$i + 1].TrimStart() } else { $cur }
		foreach ($m in $refRegex.Matches($joined)) {
			if ($m.Index -ge $cur.Length) { continue }
			$doc  = $m.Groups['doc'].Value
			$name = Get-Normalized $m.Groups['name'].Value
			if (-not $name) { continue }
			$target = Resolve-Doc $doc $dir
			if (-not $target) {
				if ((Split-Path -Leaf $doc) -in @('AGENTS.md', 'CLAUDE.md') -and $doc -match '^\.\./') { $skipped++; continue }
				$skipped++
				continue
			}
			$checked++
			$hit = $false
			foreach ($t in (Get-Targets $target)) {
				if ($t.StartsWith($name) -or $name.StartsWith($t)) { $hit = $true; break }
			}
			if (-not $hit) {
				$broken.Add([pscustomobject]@{ file = $rel; line = $i + 1; doc = $target; name = $m.Groups['name'].Value.Trim(); reason = 'no heading or bold span starts with this name' })
			}
		}
	}
}

Write-JsonOutput ([pscustomobject]@{
	checked = $checked
	skipped = $skipped
	broken  = @($broken)
})

if ($FailOnBroken -and $broken.Count -gt 0) { exit 1 }
