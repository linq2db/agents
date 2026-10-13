#!/usr/bin/env pwsh
#requires -Version 7
<#
.SYNOPSIS
    Size of the always-loaded skill / agent listing: every `description:` in skills/*/SKILL.md
    and agents/*.md, the total, and the ones over a per-description budget.

.DESCRIPTION
    Claude Code puts each skill's and agent's description into every request's prefix, so the
    listing is paid on every turn like CLAUDE.md is. Used by /audit-agents (2g) and /chores.
    Tokens are estimated at 2.6 chars/token, the rate measured for this corpus's markdown on
    2026-10-13 with /context; treat them as an estimate, /context is the measurement.

.PARAMETER Root
    Corpus root. Defaults to this script's parent directory.

.PARAMETER Budget
    Characters above which a single description is reported. Default 300.

.OUTPUTS
    One JSON object: { skills, agents, totalChars, estTokens, overBudget: [ { kind, name, chars } ] }
#>
[CmdletBinding()]
param(
	[string]$Root,
	[int]$Budget = 300
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/_shared.ps1"
$global:ScriptBaseName = 'skill-descriptions'

if (-not $Root) { $Root = (Resolve-Path "$PSScriptRoot/..").Path }

$rows = foreach ($f in @(Get-ChildItem -Path (Join-Path $Root 'skills/*/SKILL.md')) + @(Get-ChildItem -Path (Join-Path $Root 'agents/*.md'))) {
	$line = [System.IO.File]::ReadLines($f.FullName) | Where-Object { $_ -match '^description:' } | Select-Object -First 1
	if (-not $line) { continue }
	$text = ($line -replace '^description:\s*', '').Trim('"', "'")
	[pscustomobject]@{
		kind  = if ($f.Name -eq 'SKILL.md') { 'skill' } else { 'agent' }
		name  = if ($f.Name -eq 'SKILL.md') { $f.Directory.Name } else { $f.BaseName }
		chars = $text.Length
	}
}

$total = ($rows | Measure-Object chars -Sum).Sum
Write-JsonOutput ([ordered]@{
	skills     = @($rows | Where-Object kind -eq 'skill').Count
	agents     = @($rows | Where-Object kind -eq 'agent').Count
	totalChars = $total
	estTokens  = [int]($total / 2.6)
	budget     = $Budget
	overBudget = @($rows | Where-Object chars -gt $Budget | Sort-Object chars -Descending)
})
