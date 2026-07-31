#!/usr/bin/env pwsh
#requires -Version 7
<#
.SYNOPSIS
    Resolve every intra-corpus markdown link and report the broken ones.

.DESCRIPTION
    Mechanises the link half of /audit-agents' dead-reference check (2a in
    audit-agents-checks.md), which otherwise resolves links by hand.

    The corpus uses two link conventions and both must resolve:
      * superproject-relative - `.claude/docs/foo.md`, correct because the corpus is
        mounted at `.claude/` in a linq2db checkout (resolved by stripping the prefix);
      * file-relative - `worktree.md`, `../AGENTS.md`, `../../docs/worktree.md`.

    Targets that leave the corpus (Source/**, Tests/**, linq2db.slnx, CONTRIBUTING.md, ...)
    belong to the superproject: reported as `skipped`, never as broken, since this script
    may run from a standalone corpus clone where they do not exist.

    Known-noisy by design: KB area files reference INDEX.md siblings that were never
    generated, and `](url)` / `](<sampleUrl>)` placeholders inside prose look like links.
    Compare counts against a previous run rather than expecting zero.

.PARAMETER Root
    Corpus root. Defaults to this script's parent directory, so it works from a mounted
    checkout and from a standalone clone alike.

.PARAMETER FailOnBroken
    Exit non-zero when any broken link is found. Default is to report and exit 0.

.OUTPUTS
    One JSON object: { checked, skipped, broken: [ { file, target, line } ] }
#>
[CmdletBinding()]
param(
	[string]$Root,
	[switch]$FailOnBroken
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/_shared.ps1"
$global:ScriptBaseName = 'check-corpus-links'

if (-not $Root) { $Root = (Resolve-Path "$PSScriptRoot/..").Path }
if (-not (Test-Path -LiteralPath (Join-Path $Root 'AGENTS.md'))) {
	Exit-WithError -Message "Not a corpus root: $Root (no AGENTS.md)" -NextAction 'pass -Root <corpus-root>'
}

$files = @(& git -C $Root ls-files '*.md')
if ($LASTEXITCODE -ne 0 -or $files.Count -eq 0) {
	Exit-WithError -Message "git ls-files found no markdown under $Root" -NextAction 'run from a corpus git checkout, or pass -Root <corpus-root>'
}

# Paths owned by the superproject, not the corpus - never reported as broken.
$superprojectPrefixes = '^(Source|Tests|Build|Data|NuGet|Redist|Examples|\.github|\.githooks)/'
$superprojectFiles    = '^(linq2db\.|Directory\.|global\.json|CONTRIBUTING\.md$|README\.md$|UserDataProviders|DataProviders)'

$rootFull = [System.IO.Path]::GetFullPath($Root)
$broken   = [System.Collections.Generic.List[object]]::new()
$checked  = 0
$skipped  = 0

foreach ($rel in $files) {
	$full = Join-Path $Root $rel
	if (-not (Test-Path -LiteralPath $full)) { continue }

	$lines = [System.IO.File]::ReadAllLines($full)
	$dir   = Split-Path -Parent $rel

	for ($i = 0; $i -lt $lines.Count; $i++) {
		foreach ($m in ([regex]'\]\(([^)\s#]+)(?:#[^)\s]*)?\)').Matches($lines[$i])) {
			$target = $m.Groups[1].Value

			if ($target -match '^(https?:|mailto:|#)')  { continue }
			if ($target -match '^[A-Za-z]:[\\/]')       { continue }   # absolute local path

			if ($target.StartsWith('.claude/')) {
				$probe = $target.Substring('.claude/'.Length)
			}
			elseif ($target -match $superprojectPrefixes -or $target -match $superprojectFiles) {
				$skipped++
				continue
			}
			else {
				$probe = if ($dir) { Join-Path $dir $target } else { $target }
			}

			$resolved = [System.IO.Path]::GetFullPath((Join-Path $Root $probe))

			# Escaped the corpus root => a superproject path spelled relatively.
			if (-not $resolved.StartsWith($rootFull, 'OrdinalIgnoreCase')) { $skipped++; continue }

			$checked++
			if (-not (Test-Path -LiteralPath $resolved)) {
				$broken.Add([pscustomobject]@{ file = $rel; target = $target; line = $i + 1 })
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
