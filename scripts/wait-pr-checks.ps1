#!/usr/bin/env pwsh
<#
.SYNOPSIS
Block until a PR's GitHub Actions gate legs reach a terminal state, then report them.

.DESCRIPTION
The counterpart to azp-wait.ps1 (Azure) for the GitHub Actions side. `gh run watch` is unusable for this:
it dies at the Bash tool's 600 s ceiling and re-prints the whole job tree every interval (see
agent-rules.md -> "Two limits on that blocking form"). This polls the PR's statusCheckRollup on a wide
cadence instead and returns one summary.

Only the legs named by -Gate are waited on. Azure contexts (`build`, `build (Build)`, `default`,
`test-all*`) and the dispatch-only `tests [all]` status are reported as informational but never gate,
because .github/workflows/build.yml is a superset of Azure's `build` pipeline on a PR — see
docs/github-actions.md -> "`build.yml` is a superset of Azure's `build` pipeline".

Launch it with run_in_background and wait for the completion notification; do not poll its output file.

.EXAMPLE
& .claude/scripts/wait-pr-checks.ps1 -Pr 5873

.EXAMPLE
& .claude/scripts/wait-pr-checks.ps1 -Pr 5873 -Gate @('Build and pack','Analyzer tests')

.OUTPUTS
Exit 0 = every gated leg SUCCESS. Exit 1 = at least one non-green. Exit 2 = timed out.
#>
[CmdletBinding()]
param(
	[Parameter(Mandatory)][int]$Pr,
	[string]$Repo = 'linq2db/linq2db',
	[int]$TimeoutMinutes = 60,
	[int]$PollSeconds = 45,
	# The DB-free gate from .github/workflows/build.yml. Override to wait on a subset.
	[string[]]$Gate = @(
		'Build and pack'
		'Examples build'
		'Analyzer tests'
		'PublishSingleFile smoke test'
		'CLI tests (ubuntu-24.04)'
		'CLI tests (windows-2025)'
	)
)

$ErrorActionPreference = 'Stop'
$deadline      = (Get-Date).AddMinutes($TimeoutMinutes)
$pendingStates = @('QUEUED', 'IN_PROGRESS', 'PENDING', 'WAITING', 'REQUESTED', 'EXPECTED')

function Get-Rollup {
	# --json takes ONE comma-joined argument: a space after the comma makes PowerShell pass two
	# arguments and gh dies with "accepts at most 1 arg(s), received 2".
	$json = gh pr view $Pr --repo $Repo --json 'headRefOid,statusCheckRollup' | ConvertFrom-Json
	$rows = foreach ($c in $json.statusCheckRollup) {
		[pscustomobject]@{
			Name   = if ($c.name) { $c.name } else { $c.context }
			Status = if ($c.status) { $c.status } else { '' }
			Result = if ($c.conclusion) { $c.conclusion } elseif ($c.state) { $c.state } else { '' }
		}
	}
	[pscustomobject]@{ Head = $json.headRefOid; Rows = @($rows) }
}

while ($true) {
	$all     = Get-Rollup
	$rows    = @($all.Rows | Where-Object { $Gate -contains $_.Name })
	$pending = @($rows | Where-Object { $pendingStates -contains $_.Status -or ($_.Status -eq '' -and $pendingStates -contains $_.Result) })
	$missing = @($Gate | Where-Object { $n = $_; -not ($rows | Where-Object { $_.Name -eq $n }) })

	# A leg absent from the rollup is not green - right after a push the workflow may not have
	# registered its checks yet, and treating "absent" as "done" merges an ungated head.
	'[{0}] PR {1} head={2} gated={3}/{4} pending={5} missing=[{6}]' -f `
		(Get-Date).ToString('HH:mm:ss'), $Pr, $all.Head.Substring(0, 8), $rows.Count, $Gate.Count, $pending.Count, ($missing -join ',')

	if ($pending.Count -eq 0 -and $missing.Count -eq 0) { break }

	if ((Get-Date) -gt $deadline) {
		"TIMEOUT after $TimeoutMinutes min. pending: $(($pending.Name) -join ', ') missing: $($missing -join ', ')"
		exit 2
	}

	Start-Sleep -Seconds $PollSeconds
}

''
'=== gated GitHub Actions legs ==='
$rows | Sort-Object Name | ForEach-Object { '  {0,-32} {1,-12} {2}' -f $_.Name, $_.Status, $_.Result }
''
'=== other contexts (informational, not gated) ==='
$all.Rows | Where-Object { $Gate -notcontains $_.Name } | Sort-Object Name | ForEach-Object { '  {0,-40} {1,-12} {2}' -f $_.Name, $_.Status, $_.Result }
''

$bad = @($rows | Where-Object { $_.Result -ne 'SUCCESS' })
if ($bad.Count) {
	"NON-GREEN: $(($bad.Name) -join ', ')"
	exit 1
}

'all gated legs green'
exit 0
