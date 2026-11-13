#!/usr/bin/env pwsh
<#
Splits one-line call chains into one member access per line (testing.md -> Test layout, rule 1), on the lines
test-diff-sweep.ps1 reports under `chains`. Mechanical fixer for the sweep: read each hit first and drop the ones
that are not test code (C# inside a raw-string snippet fed to a generator, for example).

Usage (PowerShell tool):
    & .claude/scripts/split-test-chains.ps1 -File <path.cs> -Lines '69,70,101' -WhatIf
    & .claude/scripts/split-test-chains.ps1 -File <path.cs> -Lines '69,70,101'

  -File    the .cs file
  -Lines   1-based line numbers, comma-separated (a single string: `pwsh -File` does not collect arrays)
  -WhatIf  report the rewrite, write nothing

Per line: the expression starts after the indentation, an optional `return ` / `await `, or the first top-level
` = ` / `??= `. It is split at every depth-0 `.` (a `?.` moves with its dot); the first segment stays on the line,
each further segment goes on its own line one tab deeper than the statement. Depth counts (), [], {} and generic
<>, skips string and char literals, and reads `=>` / `->` as operators, not brackets.

Not handled, so edit by hand: expression-bodied members (`=> a.B().C()`), a split whose last segment is followed by
a binary operator (`?.Any(...) == true`), and argument lines continuing below a split line, which need one more tab.

Line endings and the BOM are preserved. Lines are rewritten bottom-up, so the numbers refer to the original file.

Output (stdout, one JSON object):
  { "ok": true, "file": "...", "written": true,
    "changed": [ { "line": 69, "before": "...", "after": [ "...", "..." ] } ],
    "skipped": [ { "line": 12, "reason": "no top-level member access" } ] }
#>
param(
	[Parameter(Mandatory)][string]$File,
	[Parameter(Mandatory)][string]$Lines,
	[switch]$WhatIf
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/_shared.ps1"

function Get-TopLevelDots([string]$text, [int]$start)
{
	$depth = 0; $dots = [System.Collections.Generic.List[int]]::new(); $i = $start

	while ($i -lt $text.Length)
	{
		$c = $text[$i]

		if ($c -eq '"')
		{
			$verbatim = $i -gt 0 -and ($text[$i - 1] -eq '@' -or ($i -gt 1 -and $text[$i - 2] -eq '@'))
			$i++
			while ($i -lt $text.Length)
			{
				if ($verbatim -and $text[$i] -eq '"' -and $i + 1 -lt $text.Length -and $text[$i + 1] -eq '"') { $i += 2; continue }
				if (-not $verbatim -and $text[$i] -eq '\') { $i += 2; continue }
				if ($text[$i] -eq '"') { break }
				$i++
			}
			$i++; continue
		}

		if ($c -eq "'")
		{
			$i++
			while ($i -lt $text.Length -and $text[$i] -ne "'") { if ($text[$i] -eq '\') { $i++ }; $i++ }
			$i++; continue
		}

		$next = if ($i + 1 -lt $text.Length) { $text[$i + 1] } else { ' ' }
		$prev = if ($i -gt 0) { $text[$i - 1] } else { ' ' }

		if ('([{'.Contains($c)) { $depth++ }
		elseif (')]}'.Contains($c)) { $depth-- }
		elseif ($c -eq '<' -and $prev -match '\w' -and $next -notmatch '[=<]') { $depth++ }
		elseif ($c -eq '>' -and $depth -gt 0 -and $next -ne '=' -and $prev -ne '=' -and $prev -ne '-') { $depth-- }
		elseif ($c -eq '.' -and $depth -eq 0 -and -not ($prev -match '\d' -and $next -match '\d')) { $dots.Add($i) }

		$i++
	}

	return ,$dots
}

function Get-ExpressionStart([string]$text)
{
	$s     = [regex]::Match($text, '^\s*').Length
	$depth = 0

	for ($i = $s; $i -lt $text.Length; $i++)
	{
		$c = $text[$i]
		if ('([{'.Contains($c)) { $depth++ } elseif (')]}'.Contains($c)) { $depth-- }
		elseif ($c -eq '"') { break }
		elseif ($c -eq '=' -and $depth -eq 0)
		{
			$next = if ($i + 1 -lt $text.Length) { $text[$i + 1] } else { ' ' }
			if ($next -ne '=' -and $next -ne '>' -and '=!<>'.IndexOf($text[$i - 1]) -lt 0)
			{
				$s = $i + 1
				while ($s -lt $text.Length -and $text[$s] -eq ' ') { $s++ }
				break
			}
		}
	}

	foreach ($keyword in 'return ', 'await ') { if ($text.Substring($s).StartsWith($keyword, [StringComparison]::Ordinal)) { $s += $keyword.Length } }

	return $s
}

if (-not (Test-Path -LiteralPath $File)) { Exit-WithError "file not found: $File" -NextAction 'pass an existing .cs path to -File' }

$numbers = @($Lines.Split(',', [StringSplitOptions]::RemoveEmptyEntries) | ForEach-Object { [int]$_.Trim() } | Sort-Object -Descending -Unique)
if ($numbers.Count -eq 0) { Exit-WithError 'no line numbers' -NextAction "pass -Lines '12,34'" }

$path    = (Resolve-Path -LiteralPath $File).Path
$bytes   = [System.IO.File]::ReadAllBytes($path)
$bom     = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
$content = [System.IO.File]::ReadAllText($path)
$nl      = if ($content.Contains("`r`n")) { "`r`n" } else { "`n" }
$all     = [System.Collections.Generic.List[string]]::new([string[]]($content -split "`r?`n"))

$changed = [System.Collections.Generic.List[object]]::new()
$skipped = [System.Collections.Generic.List[object]]::new()

foreach ($n in $numbers)
{
	if ($n -lt 1 -or $n -gt $all.Count) { $skipped.Add([ordered]@{ line = $n; reason = 'out of range' }); continue }

	$line   = $all[$n - 1]
	$indent = [regex]::Match($line, '^\t*').Value
	$start  = Get-ExpressionStart $line
	$dots   = Get-TopLevelDots $line $start

	if ($dots.Count -lt 1) { $skipped.Add([ordered]@{ line = $n; reason = 'no top-level member access' }); continue }

	$parts = [System.Collections.Generic.List[string]]::new()
	$from  = $start
	foreach ($d in $dots)
	{
		$cut = if ($d -gt 0 -and $line[$d - 1] -eq '?') { $d - 1 } else { $d }
		$parts.Add($line.Substring($from, $cut - $from))
		$from = $cut
	}
	$parts.Add($line.Substring($from))

	$new = [System.Collections.Generic.List[string]]::new()
	$new.Add($line.Substring(0, $start) + $parts[0].TrimEnd())
	for ($k = 1; $k -lt $parts.Count; $k++) { $new.Add($indent + "`t" + $parts[$k].Trim()) }

	$changed.Insert(0, [ordered]@{ line = $n; before = $line; after = @($new) })

	$all.RemoveAt($n - 1)
	$all.InsertRange($n - 1, $new)
}

$written = $false
if (-not $WhatIf -and $changed.Count -gt 0)
{
	[System.IO.File]::WriteAllText($path, ($all -join $nl), [System.Text.UTF8Encoding]::new($bom))
	$written = $true
}

Write-JsonOutput ([ordered]@{ ok = $true; file = $path; written = $written; changed = @($changed); skipped = @($skipped) })
