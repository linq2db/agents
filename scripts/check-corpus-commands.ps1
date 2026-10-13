#!/usr/bin/env pwsh
#requires -Version 7
<#
.SYNOPSIS
    Find documented commands that would fail when run: a `.claude/scripts/<name>.ps1` call naming
    a script or a parameter that does not exist, and a `Skill('<name>')` naming no corpus skill.

.DESCRIPTION
    The stale-command half of /audit-agents (2l in audit-agents-checks.md). For every
    `scripts/<name>.ps1 -Param …` in a tracked .md / .ps1 / .js file (plans/ and knowledge-base/
    skipped unless -IncludeFrozen), the script must exist and every `-Param` must resolve
    against its param() block — exactly, or as a unique prefix, as PowerShell itself binds it.
    Common parameters (-Verbose, -ErrorAction, …) always resolve.

    Backticked `/name` mentions that match no corpus skill are reported separately as
    `unknownSlash`, not as broken: many are Claude Code built-ins (`/context`, `/mcp`) or
    user-level skills the corpus cannot see.

.PARAMETER Root
    Corpus root. Defaults to this script's parent directory.

.OUTPUTS
    One JSON object: { checked, broken: [ { file, line, script, param, reason } ], unknownSlash: [ … ] }
#>
[CmdletBinding()]
param(
	[string]$Root,
	[switch]$IncludeFrozen,
	[switch]$FailOnBroken
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/_shared.ps1"
$global:ScriptBaseName = 'check-corpus-commands'

if (-not $Root) { $Root = (Resolve-Path "$PSScriptRoot/..").Path }
$tracked = @(& git -C $Root ls-files '*.md' '*.ps1' '*.js')
if ($LASTEXITCODE -ne 0 -or $tracked.Count -eq 0) {
	Exit-WithError -Message "git ls-files found nothing under $Root" -NextAction 'pass -Root <corpus-root>'
}

$common = @('Verbose', 'Debug', 'ErrorAction', 'WarningAction', 'InformationAction', 'ProgressAction',
	'ErrorVariable', 'WarningVariable', 'InformationVariable', 'OutVariable', 'OutBuffer', 'PipelineVariable',
	'WhatIf', 'Confirm', 'NoProfile', 'File', 'Command', 'NonInteractive', 'ExecutionPolicy')

$paramCache = @{}
function Get-ScriptParams([string]$name) {
	if ($paramCache.ContainsKey($name)) { return $paramCache[$name] }
	$p = Join-Path $Root "scripts/$name.ps1"
	$val = $null
	if (Test-Path -LiteralPath $p) {
		$tokens = $null; $errors = $null
		$ast = [System.Management.Automation.Language.Parser]::ParseFile($p, [ref]$tokens, [ref]$errors)
		$val = @($ast.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })
	}
	$paramCache[$name] = $val
	$val
}

$skills = @(Get-ChildItem -LiteralPath (Join-Path $Root 'skills') -Directory | Select-Object -ExpandProperty Name)

# `.claude/scripts/` or a bare `scripts/` only — `Build/…/scripts/` belongs to the superproject. Arguments are
# consecutive `-Param [value]` pairs, so prose after the script name is not read as parameters.
$callRegex  = [regex]'(?:(?<=\.claude[/\\])|(?<![\w/\\.-]))scripts[/\\](?<name>[\w.-]+)\.ps1(?<args>(?:[ \t]+-[A-Za-z]\w*(?:[ \t]+(?!-)(?:''[^'']*''|"[^"]*"|<[^>]*>|@\([^)]*\)|[^\s`|;)\]]+))?)*)'
$skillRegex = [regex]'Skill\(\s*[''"]?(?<name>[\w:-]+)[''"]?'
$slashRegex = [regex]'`/(?<name>[a-z][\w-]*)(?=[\s`])'

$broken  = [System.Collections.Generic.List[object]]::new()
$unknown = [System.Collections.Generic.List[object]]::new()
$checked = 0

foreach ($rel in $tracked) {
	if (-not $IncludeFrozen -and $rel -match '^(plans|knowledge-base)/') { continue }
	$full = Join-Path $Root $rel
	if (-not (Test-Path -LiteralPath $full)) { continue }
	$lines = [System.IO.File]::ReadAllLines($full)
	for ($i = 0; $i -lt $lines.Count; $i++) {
		$line = $lines[$i]
		foreach ($m in $callRegex.Matches($line)) {
			$name = $m.Groups['name'].Value
			if ($name -match '^<|^\*' -or $name -in @('x', 'foo', 'bar', 'name', 'script', 'my-script')) { continue }   # placeholders
			$checked++
			$declared = Get-ScriptParams $name
			if ($null -eq $declared) {
				if ($rel -ne "scripts/$name.ps1") { $broken.Add([pscustomobject]@{ file = $rel; line = $i + 1; script = $name; param = $null; reason = 'script does not exist' }) }
				continue
			}
			# a parameter starts a whitespace-separated token; `pr<n>-context.json` or `@('-f', …)` are values
			foreach ($a in [regex]::Matches($m.Groups['args'].Value, '(?:^|[ \t])-(?<p>[A-Za-z]\w*)')) {
				$p = $a.Groups['p'].Value
				if ($common -contains $p) { continue }
				$hits = @($declared | Where-Object { $_ -ieq $p })
				if (-not $hits) { $hits = @($declared | Where-Object { $_.StartsWith($p, 'OrdinalIgnoreCase') }) }
				if ($hits.Count -ne 1) {
					$broken.Add([pscustomobject]@{ file = $rel; line = $i + 1; script = $name; param = $p
						reason = if ($hits.Count) { 'ambiguous prefix' } else { 'no such parameter (declared: ' + ($declared -join ', ') + ')' } })
				}
			}
		}
		foreach ($m in $skillRegex.Matches($line)) {
			$name = $m.Groups['name'].Value
			if ($name -match ':' -or $name -in @('name', 'x', 'foo')) { continue }
			$checked++
			if ($skills -notcontains $name) { $broken.Add([pscustomobject]@{ file = $rel; line = $i + 1; script = $null; param = $name; reason = 'Skill() names no corpus skill' }) }
		}
		foreach ($m in $slashRegex.Matches($line)) {
			$name = $m.Groups['name'].Value
			if ($skills -notcontains $name) { $unknown.Add([pscustomobject]@{ file = $rel; line = $i + 1; name = $name }) }
		}
	}
}

Write-JsonOutput ([pscustomobject]@{
	checked      = $checked
	broken       = @($broken)
	unknownSlash = @($unknown | Group-Object name | Sort-Object Count -Descending | ForEach-Object { [pscustomobject]@{ name = $_.Name; count = $_.Count; first = "$($_.Group[0].file):$($_.Group[0].line)" } })
})

if ($FailOnBroken -and $broken.Count -gt 0) { exit 1 }
