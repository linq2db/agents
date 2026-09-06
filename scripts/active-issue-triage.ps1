#!/usr/bin/env pwsh
# active-issue-triage.ps1 — turn a triage sweep's sentinel lines into a per-site triage table.
#
# During a sweep, ActiveIssueAttribute is temporarily switched to "run the test, always report Failure",
# and each gated test case emits one line built by Tests/Base/ActiveIssueSentinel.cs:
#
#   ##L2DB-AI|1|<Test.FullName>|<provider|->|<0|1 remote>|<PASSED|FAILED>|<errorType|->|<escaped message>
#
# This script mirrors ActiveIssueSentinel.TryParse, groups the rows back onto the source site that owns the
# attribute (class + method, argument list stripped), and proposes what the site's replacement annotation
# should say. It never edits source — the annotation walk is a human-reviewed step.
#
# Front-end agnostic on purpose: it takes whatever files hold the lines, so a local run log and a CI step
# log go through the same parser.
#
# Usage:
#   pwsh -NoProfile -File .claude/scripts/active-issue-triage.ps1 -LogPath .build/.agents/sweep-ef10.log
#   pwsh -NoProfile -File .claude/scripts/active-issue-triage.ps1 -LogPath .build/.agents -WriteDir .build/.agents/triage

[CmdletBinding()]
param(
	[Parameter(Mandatory)] [string[]] $LogPath,
	[string] $WriteDir,
	[string] $StripNamespace,
	# Cells whose failure is the environment rather than the product, as '<log-name-fragment>:<provider>'.
	# A leg that cannot load a provider's native library fails every one of its cases identically, which would
	# otherwise read as a cross-TFM divergence and produce a wrong annotation. Declaring them keeps the exclusion
	# reviewable instead of hiding it in a heuristic.
	[string[]] $Exclude = @()
)

$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..' '..')

if (-not $WriteDir) { $WriteDir = Join-Path $repoRoot '.build/.agents/active-issue-triage' }
if (-not (Test-Path $WriteDir)) { New-Item -ItemType Directory -Path $WriteDir -Force | Out-Null }

$Prefix = '##L2DB-AI|1|'

function Expand-Logs {
	param([string[]] $Paths)

	$files = @()

	foreach ($p in $Paths) {
		if (-not (Test-Path $p)) {
			Write-Error "Log path not found: $p"
		}

		if ((Get-Item $p).PSIsContainer) {
			$files += Get-ChildItem -Path $p -Filter '*.log' -File -Recurse | Select-Object -ExpandProperty FullName
		}
		else {
			$files += (Resolve-Path $p).Path
		}
	}

	return $files
}

function Unescape-Field {
	param([string] $Value)

	if ($Value.IndexOf('%') -lt 0) { return $Value }

	return $Value.
		Replace('%0D', "`r").
		Replace('%0A', "`n").
		Replace('%7C', '|').
		Replace('%25', '%')
}

# Collapses the volatile parts of a provider error so two cases that differ only in an id, a table suffix or a
# timestamp land in the same cohort. Without it every provider looks like its own distinct failure.
function Get-NormalizedMessage {
	param([string] $Message)

	if (-not $Message) { return '' }

	$n = $Message
	$n = [regex]::Replace($n, '[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}', '<guid>')
	$n = [regex]::Replace($n, '[A-Za-z]:\\[^\s"'']+', '<path>')
	$n = [regex]::Replace($n, '\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}(\.\d+)?', '<timestamp>')
	$n = [regex]::Replace($n, '\d+', '<n>')
	$n = [regex]::Replace($n, '\s+', ' ')

	return $n.Trim()
}

# The stable part of a family of failure messages: what every one of them starts with. That is what an
# ErrorMessage fragment has to match, so deriving it here is what makes a suggestion directly usable.
# NUnit renders an unhandled exception as "<TypeFullName> : <message>". The type has to come off before the
# messages are compared: when it differs across legs - which it does for the MySQL family, MySqlConnector.* on
# net8.0+ vs MySql.Data.* on net462 - the common prefix truncates inside the type name and two genuinely
# different failures merge into one cohort carrying a nonsense fragment.
function Remove-TypePrefix {
	param([string] $Message)

	if (-not $Message) { return '' }

	$sep = $Message.IndexOf(' : ')

	if ($sep -le 0) { return $Message }

	$candidate = $Message.Substring(0, $sep)

	if ($candidate.IndexOf('.') -lt 0) { return $Message }
	if ($candidate -match '\s')        { return $Message }

	return $Message.Substring($sep + 3)
}

function Get-CommonPrefix {
	param([string[]] $Values)

	$vals = @($Values | Where-Object { $_ } | ForEach-Object { Remove-TypePrefix $_ })

	if ($vals.Count -eq 0) { return '' }

	$prefix = $vals[0]

	foreach ($v in $vals) {
		$max = [Math]::Min($prefix.Length, $v.Length)
		$i   = 0

		while ($i -lt $max -and $prefix[$i] -ceq $v[$i]) { $i++ }

		$prefix = $prefix.Substring(0, $i)

		if ($prefix.Length -eq 0) { break }
	}

	# Trailing partial token is noise in a suggestion - cut back to the last separator.
	$cut = $prefix.LastIndexOfAny([char[]]@(' ', ':', '.', ',', "`n"))

	if ($cut -gt 20) { $prefix = $prefix.Substring(0, $cut) }

	return $prefix.Trim()
}

$files = Expand-Logs -Paths $LogPath

$records  = @()
$excluded = 0

foreach ($file in $files) {
	foreach ($line in [System.IO.File]::ReadLines($file)) {
		$at = $line.IndexOf($Prefix)

		if ($at -lt 0) { continue }

		$parts = $line.Substring($at + $Prefix.Length).Split('|')

		if ($parts.Count -ne 6) { continue }

		$fq       = Unescape-Field $parts[0]
		$provider = Unescape-Field $parts[1]
		$errType  = Unescape-Field $parts[4]
		$message  = Unescape-Field $parts[5]

		$site = $fq
		$open = $fq.IndexOf('(')
		if ($open -ge 0) { $site = $fq.Substring(0, $open) }

		if ($StripNamespace -and $site.StartsWith($StripNamespace)) {
			$site = $site.Substring($StripNamespace.Length)
		}

		$skip = $false

		foreach ($x in $Exclude) {
			$bits = $x.Split(':')

			if ($bits.Count -eq 2 -and $file -like "*$($bits[0])*" -and $provider -eq $bits[1]) {
				$skip = $true
				break
			}
		}

		if ($skip) { $excluded++; continue }

		$records += [pscustomobject]@{
			Site       = $site
			FullName   = $fq
			Provider   = if ($provider -eq '-') { $null } else { $provider }
			IsRemote   = $parts[2] -eq '1'
			Passed     = $parts[3] -eq 'PASSED'
			ErrorType  = if ($errType -eq '-') { $null } else { $errType }
			Message    = $message
			Normalized = Get-NormalizedMessage $message
			SourceLog  = [System.IO.Path]::GetFileName($file)
		}
	}
}

# One row per (case, transport, leg). The leg — the source log — MUST be part of the identity: Test.FullName
# carries the provider argument but not the target framework, so without it EF3/EF8/EF9/EF10 rows for one
# provider collapse into a single row and the cross-TFM disagreement that `review` exists to catch is gone
# before the check runs. Within one log the key still collapses a repeated failure block.
$records = $records | Group-Object -CaseSensitive FullName, IsRemote, SourceLog | ForEach-Object { $_.Group | Select-Object -Last 1 }

$sites = @()

foreach ($group in ($records | Group-Object -CaseSensitive Site | Sort-Object Name)) {
	$cells   = @($group.Group)
	$passed  = @($cells | Where-Object { $_.Passed })
	$failed  = @($cells | Where-Object { -not $_.Passed })

	# A provider that disagrees with itself across TFMs or logs is never aggregated away — that difference is
	# the finding, not noise to collapse.
	$divergent = @(
		$cells | Group-Object -CaseSensitive Provider | Where-Object {
			($_.Group | Select-Object -ExpandProperty Passed -Unique).Count -gt 1
		} | Select-Object -ExpandProperty Name
	)

	# Cohorts are built on the axis an annotation actually uses: the provider. Grouping on the message instead
	# splits one failure into several whenever the generated SQL differs by TFM, and grouping on the error type
	# splits the MySQL family whenever the driver name differs by TFM - both produce more attributes than the
	# site needs. Per provider we keep the error types seen and the longest common message prefix; providers
	# whose (types, prefix) agree then collapse into one attribute.
	$perProvider = @()

	foreach ($p in ($failed | Group-Object -CaseSensitive Provider)) {
		$types  = @($p.Group | Select-Object -ExpandProperty ErrorType -Unique | Where-Object { $_ } | Sort-Object)
		$prefix = Get-CommonPrefix -Values @($p.Group | Select-Object -ExpandProperty Message)

		$perProvider += [pscustomobject]@{
			provider  = $p.Name
			types     = $types
			prefix    = $prefix
			cases     = $p.Count
			# A type that varies across legs cannot go in ErrorTypeName - the message is the stable part.
			typeStable = $types.Count -le 1
		}
	}

	$cohorts = @()

	foreach ($c in ($perProvider | Group-Object -CaseSensitive { ($_.types -join '|') + '##' + $_.prefix })) {
		$cohorts += [pscustomobject]@{
			errorType   = if ($c.Group[0].typeStable -and $c.Group[0].types.Count -eq 1) { $c.Group[0].types[0] } else { $null }
			errorTypes  = $c.Group[0].types
			typeStable  = $c.Group[0].typeStable
			providers   = @($c.Group | Select-Object -ExpandProperty provider | Sort-Object)
			cases       = ($c.Group | Measure-Object cases -Sum).Sum
			suggestedMessage = $c.Group[0].prefix
		}
	}

	$cohorts = @($cohorts | Sort-Object { -$_.cases })

	$verdict = 'review'

	if ($divergent.Count -gt 0)                                   { $verdict = 'review' }
	elseif ($failed.Count -eq 0)                                  { $verdict = 'remove' }
	elseif ($passed.Count -eq 0 -and $cohorts.Count -eq 1)        { $verdict = 'replace-all' }
	elseif ($passed.Count -gt 0 -and $cohorts.Count -eq 1)        { $verdict = 'replace-scoped' }
	elseif ($cohorts.Count -gt 1)                                 { $verdict = 'replace-multi' }

	# One attribute per cohort, keyed by (issue, error type, error message); the providers that share a key go
	# into a single Configuration rather than getting an attribute each.
	$suggested = @()

	foreach ($c in $cohorts) {
		$args = @()

		# Omit Configuration when the cohort covers every provider this test failed on - the attribute is blanket.
		if ($c.providers.Count -lt ($failed | Select-Object -ExpandProperty Provider -Unique).Count -or $passed.Count -gt 0) {
			$args += 'Configuration = "' + ($c.providers -join ',') + '"'
		}

		if ($c.errorType) {
			$args += 'ErrorTypeName = "' + $c.errorType + '"'
		}
		elseif (-not $c.typeStable) {
			$args += '/* type varies across TFMs: ' + ($c.errorTypes -join ' | ') + ' - message is the stable key */'
		}

		if ($c.suggestedMessage) {
			$frag = ($c.suggestedMessage -split "`n")[0]
			$args += 'ErrorMessage = "' + ($frag -replace '"', '\"') + '"'
		}

		$suggested += '[ActiveIssueNew(<issue>, ' + ($args -join ', ') + ')]'
	}

	$sites += [pscustomobject]@{
		site             = $group.Name
		verdict          = $verdict
		suggested        = $suggested
		cells            = $cells.Count
		passedProviders  = @($passed | Select-Object -ExpandProperty Provider -Unique | Sort-Object)
		failedProviders  = @($failed | Select-Object -ExpandProperty Provider -Unique | Sort-Object)
		divergentProviders = $divergent
		cohorts          = $cohorts
	}
}

$byVerdict = @{}
foreach ($v in 'remove','replace-all','replace-scoped','replace-multi','review') {
	$byVerdict[$v] = @($sites | Where-Object { $_.verdict -eq $v }).Count
}

$resultsFile = Join-Path $WriteDir 'triage.json'
$mdFile      = Join-Path $WriteDir 'triage.md'

$payload = [pscustomobject]@{
	logs        = @($files)
	rows        = $records.Count
	excludedRows = $excluded
	sites       = $sites.Count
	byVerdict   = $byVerdict
	resultsFile = $resultsFile
	mdFile      = $mdFile
	detail      = $sites
}

$payload | ConvertTo-Json -Depth 8 | Out-File -FilePath $resultsFile -Encoding utf8

$md = @()
$md += '# ActiveIssue triage'
$md += ''
$md += "Rows: $($records.Count) · Sites: $($sites.Count)"
$md += ''
$md += '| site | verdict | passes on | fails on |'
$md += '|---|---|---|---|'

foreach ($s in $sites) {
	$md += '| {0} | {1} | {2} | {3} |' -f $s.site, $s.verdict, ($s.passedProviders -join ', '), ($s.failedProviders -join ', ')
}

foreach ($s in ($sites | Where-Object { $_.cohorts.Count -gt 0 })) {
	$md += ''
	$md += "## $($s.site) — $($s.verdict)"

	foreach ($c in $s.cohorts) {
		$md += ''
		$md += "- **$(if ($c.errorType) { $c.errorType } else { '(no stable type)' })** on $($c.providers -join ', ') — $($c.cases) cells"
		$md += '  ```'
		$md += '  ' + ((($c.suggestedMessage -split "`n") | Select-Object -First 3) -join "`n  ")
		$md += '  ```'
	}

	if ($s.suggested) {
		$md += ''
		$md += '  ```csharp'
		foreach ($a in $s.suggested) { $md += '  ' + $a }
		$md += '  ```'
	}
}

$md -join "`n" | Out-File -FilePath $mdFile -Encoding utf8

# stdout is summary-only: a full sweep is tens of thousands of rows and they belong on disk, not in a caller's context.
$payload | Select-Object -Property logs, rows, excludedRows, sites, byVerdict, resultsFile, mdFile | ConvertTo-Json -Depth 4
