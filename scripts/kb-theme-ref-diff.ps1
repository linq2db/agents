#!/usr/bin/env pwsh
<#
KB theme reference diff — for each regenerated github-themes envelope, compare
the `#<n>` references of every ARTIFACT against the file it would replace and
list the ones dropped. Run between capture and apply in /kb-refresh (issues /
prs source, step 9) so a regeneration that loses open items can be rejected.

One permission rule:
    Bash(pwsh -NoProfile -File .claude/scripts/kb-theme-ref-diff.ps1 *)

Input (stdin, JSON):
  {
    "areas":   ["LINQ", "PROV-ORACLE"],                      // reads .build/.agents/kb-refresh-theme-<AREA>.txt
    "pattern": ".build/.agents/kb-refresh-theme-{0}.txt"     // optional; {0} = area code
  }

Output (stdout, JSON):
  {
    "ok": true,
    "results": [
      { "area": "LINQ", "artifact": "areas/LINQ/issues.md",
        "old": 81, "new": 124, "added": 43, "dropped": [] },
      { "area": "X", "error": "no envelope" }
    ]
  }
#>

param([string]$ManifestFile)

$global:ScriptBaseName = 'kb-theme-ref-diff'
. "$PSScriptRoot/_shared.ps1"

$m = Read-ManifestFromFileOrStdin -ManifestFile $ManifestFile
if (-not $m.areas) { Exit-WithError 'areas[] is required' }
$pattern = if ($m.pattern) { [string]$m.pattern } else { '.build/.agents/kb-refresh-theme-{0}.txt' }

$repoRoot = Resolve-Path "$PSScriptRoot/../.." | Select-Object -ExpandProperty Path
$kbRoot   = Join-Path $repoRoot '.claude/knowledge-base'

function Get-Refs([string]$text) {
	@([regex]::Matches($text, '#(\d{2,5})\b') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
}

$results = @()
foreach ($area in $m.areas) {
	$envPath = Join-Path $repoRoot ($pattern -f $area)
	if (-not (Test-Path $envPath)) {
		$results += [pscustomobject]@{ area = $area; error = 'no envelope' }
		continue
	}
	# Envelopes may still carry the hook-dodging placeholders; refs are unaffected, but keep bodies faithful.
	$text = ([System.IO.File]::ReadAllText($envPath)) -replace '@@SEMI@@', ';' -replace '@@AMP@@', '&' -replace '@@PIPE@@', '|'
	$arts = [regex]::Matches($text, '(?ms)^=== ARTIFACT: (?<p>[^\r\n]+?) ===\r?\n(?<b>.*?)^=== END ARTIFACT ===')
	if ($arts.Count -eq 0) {
		$results += [pscustomobject]@{ area = $area; error = 'no artifacts in envelope' }
		continue
	}
	foreach ($a in $arts) {
		$rel     = $a.Groups['p'].Value.Trim()
		$oldPath = Join-Path $kbRoot $rel
		$oldRefs = if (Test-Path $oldPath) { Get-Refs ([System.IO.File]::ReadAllText($oldPath)) } else { @() }
		$newRefs = Get-Refs $a.Groups['b'].Value
		$results += [pscustomobject]@{
			area     = $area
			artifact = $rel
			old      = $oldRefs.Count
			new      = $newRefs.Count
			added    = @($newRefs | Where-Object { $_ -notin $oldRefs }).Count
			dropped  = @($oldRefs | Where-Object { $_ -notin $newRefs })
		}
	}
}

Write-JsonOutput -InputObject ([pscustomobject]@{ ok = $true; results = $results })
