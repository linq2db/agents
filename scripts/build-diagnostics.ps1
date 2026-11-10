#!/usr/bin/env pwsh
# Summarise compiler and analyzer diagnostics from an MSBuild log.
#
#   -LogPath   build log (required)
#   -Rule      only this diagnostic id (optional)
#   -Root      repo root for reading source lines (optional; default: two levels above this script)
#
# Output: one JSON object with per-rule counts, per-file counts, and one entry per distinct diagnostic
# (file, line, rule, target, source line). MSBuild prints each diagnostic twice; duplicates are removed.
# Rule ids may contain digits anywhere (LINQ2DB0007), which a letters-then-digits pattern misses.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $LogPath,
    [string] $Rule,
    [string] $Root
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/_shared.ps1"

$global:ScriptBaseName = 'build-diagnostics'

if (-not (Test-Path -LiteralPath $LogPath))
{
    Exit-WithError "log not found: $LogPath" -NextAction 'pass -LogPath with the path of an existing build log'
}

if (-not $Root)
{
    $Root = (Resolve-Path "$PSScriptRoot/../..").Path
}

$pattern = '^(?<file>.+?)\((?<line>\d+),(?<col>\d+)\): (?<severity>error|warning) (?<rule>[A-Z][A-Z0-9]+): (?<message>.*?)(?: \[[^\]]+\])?$'

$seen  = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
$items = [System.Collections.Generic.List[object]]::new()

foreach ($raw in [System.IO.File]::ReadLines($LogPath))
{
    $line = $raw.Trim()
    $m    = [regex]::Match($line, $pattern)

    if (-not $m.Success)
    {
        continue
    }

    $ruleId = $m.Groups['rule'].Value

    if ($Rule -and $ruleId -ne $Rule)
    {
        continue
    }

    $file = $m.Groups['file'].Value
    $key  = "$file|$($m.Groups['line'].Value)|$($m.Groups['col'].Value)|$ruleId"

    if (-not $seen.Add($key))
    {
        continue
    }

    $relative = $file

    if ($file.StartsWith($Root, [StringComparison]::OrdinalIgnoreCase))
    {
        $relative = $file.Substring($Root.Length).TrimStart('\', '/')
    }

    $source = $null
    $lineNo = [int]$m.Groups['line'].Value

    if (Test-Path -LiteralPath $file)
    {
        $source = ([System.IO.File]::ReadLines($file) | Select-Object -Skip ($lineNo - 1) -First 1)

        if ($null -ne $source)
        {
            $source = $source.Trim()
        }
    }

    $target = $null
    $tm     = [regex]::Match($m.Groups['message'].Value, "'(?<t>[^']+)'")

    if ($tm.Success)
    {
        $target = $tm.Groups['t'].Value
    }

    $items.Add([ordered]@{
        file     = $relative
        line     = $lineNo
        severity = $m.Groups['severity'].Value
        rule     = $ruleId
        target   = $target
        source   = $source
        message  = $m.Groups['message'].Value
    })
}

$byRule = $items | Group-Object { $_.rule } | Sort-Object Count -Descending | ForEach-Object { [ordered]@{ rule = $_.Name; count = $_.Count } }
$byFile = $items | Group-Object { $_.file } | Sort-Object Count -Descending | ForEach-Object { [ordered]@{ file = $_.Name; count = $_.Count } }

Write-JsonOutput ([ordered]@{
    total       = $items.Count
    byRule      = @($byRule)
    byFile      = @($byFile)
    diagnostics = @($items | Sort-Object { $_.file }, { $_.line })
})
