#!/usr/bin/env pwsh
<#
List the TFM-gated `#if` / `#elif` blocks in linq2db's tracked C# sources, so a
change that drops a TFM - or adds a gate - can be checked for what the
netstandard2.0 asset loses.

Why this script exists
----------------------
Modern-runtime apps load the netstandard2.0 asset (via a netstandard2.0 library,
or because their runtime's TFM was dropped), so every `#if NET8_0_OR_GREATER` /
`SUPPORTS_*` / `ADO_*` / `!NETSTANDARD2_0` block is code they lose. The policy is
in `.claude/docs/code-design.md` -> "A TFM gate may withhold a feature, never
recognition of unchanged source"; this script makes its "list the gates" step
mechanical instead of a hand grep that misses `#elif` and macro spellings.

Contract
--------
Input (named parameters):
  -RepoRoot <path>   optional; repo root, default: current directory
  -Path     <path>   optional; subtree to scan, default: Source
  -Macro    <regex>  optional; keep only directives whose text matches, e.g.
                     'NET8_0|NET9_0|SUPPORTS_|ADO_' for a net8/net9 drop
  -Base     <ref>    optional; list only directives on lines ADDED in
                     `git diff <Base>...HEAD` - the review-time question
                     "which gates does this change introduce?"

Output (stdout, single JSON object):
  {
    "total":   123,
    "byMacro": { "NET8_0_OR_GREATER": 40, "SUPPORTS_DATEONLY": 60, ... },
    "byArea":  { "Internal/DataProvider/PostgreSQL": 7, ... },
    "gates":   [ { "file": "Source/LinqToDB/...cs", "line": 3756, "directive": "#if NET8_0_OR_GREATER", "macros": [ "NET8_0_OR_GREATER" ] } ]
  }

Exit codes: 0 = success (an empty list included); 1 = bad input / git failure.
#>

param(
    [string]$RepoRoot = (Get-Location).Path,
    [string]$Path     = 'Source',
    [string]$Macro,
    [string]$Base
)

. "$PSScriptRoot/_shared.ps1"

$ErrorActionPreference = 'Stop'

$tokenRegex     = '\b(NET\d+_\d+(_OR_GREATER)?|NETCOREAPP\w*|NETSTANDARD\w*|NETFRAMEWORK|NET\d{2,3}\w*|SUPPORTS_\w+|ADO_\w+)\b'
$directiveRegex = '^\s*#\s*(if|elif)\b'

if (-not (Test-Path -LiteralPath $RepoRoot -PathType Container)) {
    Exit-WithError -Message "RepoRoot not found: $RepoRoot" -NextAction 'pass -RepoRoot <linq2db checkout>'
}
$root = (Resolve-Path -LiteralPath $RepoRoot).Path

function Get-Macros([string]$text) {
    @([regex]::Matches($text, $tokenRegex) | ForEach-Object { $_.Value } | Select-Object -Unique)
}

$gates = [System.Collections.Generic.List[object]]::new()

if ($Base) {
    $diff = & git -C $root diff -U0 "$Base...HEAD" -- $Path
    if ($LASTEXITCODE -ne 0) { Exit-WithError -Message "git diff $Base...HEAD failed" -NextAction 'fetch the base ref first' }

    $file = $null; $lineNo = 0
    foreach ($l in $diff) {
        if ($l -match '^\+\+\+ b/(.+?)\t?$')             { $file = $Matches[1]; continue }
        if ($l -match '^@@ -\S+ \+(\d+)')                { $lineNo = [int]$Matches[1]; continue }
        if ($l.StartsWith('+') -and -not $l.StartsWith('+++')) {
            $text = $l.Substring(1)
            if ($file -like '*.cs' -and $text -match $directiveRegex) {
                $macros = Get-Macros $text
                if ($macros.Count -gt 0) { $gates.Add([ordered]@{ file = $file; line = $lineNo; directive = $text.Trim(); macros = $macros }) }
            }
            $lineNo++
        }
    }
}
else {
    $files = & git -C $root ls-files -- $Path
    if ($LASTEXITCODE -ne 0) { Exit-WithError -Message "git ls-files $Path failed" -NextAction 'run from a linq2db checkout' }

    foreach ($rel in $files) {
        if ($rel -notlike '*.cs') { continue }
        $n = 0
        foreach ($text in [System.IO.File]::ReadLines((Join-Path $root $rel))) {
            $n++
            if ($text -notmatch $directiveRegex) { continue }
            $macros = Get-Macros $text
            if ($macros.Count -gt 0) { $gates.Add([ordered]@{ file = $rel; line = $n; directive = $text.Trim(); macros = $macros }) }
        }
    }
}

if ($Macro) { $gates = @($gates | Where-Object { $_.directive -match $Macro }) }

$byMacro = [ordered]@{}
$byArea  = [ordered]@{}
foreach ($g in $gates) {
    foreach ($m in $g.macros) { $byMacro[$m] = 1 + ($byMacro[$m] ?? 0) }
    $area = ($g.file -replace '^Source/LinqToDB/', '' -replace '/[^/]+$', '')
    $byArea[$area] = 1 + ($byArea[$area] ?? 0)
}

[ordered]@{
    total   = @($gates).Count
    byMacro = $byMacro
    byArea  = $byArea
    gates   = @($gates)
} | ConvertTo-Json -Depth 5
