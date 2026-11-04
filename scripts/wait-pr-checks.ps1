#!/usr/bin/env pwsh
<#
.SYNOPSIS
Block until a PR's GitHub Actions gate legs reach a terminal state, then report them.

.DESCRIPTION
The counterpart to azp-wait.ps1 (Azure) for the GitHub Actions side. `gh run watch` is unusable for this:
it dies at the Bash tool's 600 s ceiling and re-prints the whole job tree every interval (see
ci-tests.md -> "Two limits on that blocking form"). This polls the PR's statusCheckRollup on a wide
cadence instead and returns one summary.

Only the legs named by -Gate are waited on. Azure contexts (`build`, `build (Build)`, `default`,
`test-all*`) and the dispatch-only `tests [all]` status are reported as informational but never gate,
because .github/workflows/build.yml is a superset of Azure's `build` pipeline on a PR — see
docs/github-actions.md -> "`build.yml` is a superset of Azure's `build` pipeline".

That is a claim about COVERAGE, not about MERGEABILITY, and the two diverge. `master`'s branch
protection lists exactly one required status check and it is the Azure one:

    gh api repos/linq2db/linq2db/branches/master/protection --jq '.required_status_checks.contexts'
    ["build"]

So "all gated legs green" (exit 0) can coincide with a PR still reporting mergeStateStatus BLOCKED,
and on 6.5.0 it did. Read exit 0 as "the DB-free coverage is in" and check the PR's own merge state
separately before concluding anything about merging; azp-wait.ps1 is what waits on the Azure side.

Launch it with run_in_background and wait for the completion notification; do not poll its output file.
-TimeoutMinutes is capped at 50 (the session's prompt cache expires after 1 hour); on exit 2, re-arm it —
turn-conduct.md -> "Cap a background wait at 50 minutes".

.EXAMPLE
& .claude/scripts/wait-pr-checks.ps1 -Pr 5873

.EXAMPLE
& .claude/scripts/wait-pr-checks.ps1 -Pr 5873 -Gate @('Build and pack','Analyzer tests')

.OUTPUTS
Exit 0 = every gated leg SUCCESS. Exit 1 = at least one non-green. Exit 2 = timed out. Exit 3 = gh failed 3 polls in a row.
#>
[CmdletBinding()]
param(
	[Parameter(Mandatory)][int]$Pr,
	[string]$Repo = 'linq2db/linq2db',
	[ValidateRange(1, 50)][int]$TimeoutMinutes = 50,
	[int]$PollSeconds = 45,
	# The DB-free gate from .github/workflows/build.yml. Override to wait on a subset.
	[string[]]$Gate = @(
		'Build and pack'
		'Examples build'
		'Analyzer tests'
		'PublishSingleFile smoke test'
		'CLI tests (ubuntu-24.04)'
		'CLI tests (windows-2025)'
		'CLI tests (macos-15)'
		'x86 FPU-unmasked JIT sweep'
		'WASM runtime tests'
	)
)

$ErrorActionPreference = 'Stop'
$deadline      = (Get-Date).AddMinutes($TimeoutMinutes)
$pendingStates = @('QUEUED', 'IN_PROGRESS', 'PENDING', 'WAITING', 'REQUESTED', 'EXPECTED')

function Get-Rollup {
	# --json takes ONE comma-joined argument: a space after the comma makes PowerShell pass two
	# arguments and gh dies with "accepts at most 1 arg(s), received 2".
	$raw = gh pr view $Pr --repo $Repo --json 'headRefOid,statusCheckRollup'
	if ($LASTEXITCODE -ne 0 -or -not $raw) { return $null }
	$json = $raw | ConvertFrom-Json
	$rows = foreach ($c in $json.statusCheckRollup) {
		[pscustomobject]@{
			Name   = if ($c.name) { $c.name } else { $c.context }
			Status = if ($c.status) { $c.status } else { '' }
			Result = if ($c.conclusion) { $c.conclusion } elseif ($c.state) { $c.state } else { '' }
		}
	}
	[pscustomobject]@{ Head = $json.headRefOid; Rows = @($rows) }
}

$transient = 0

while ($true) {
	$all = Get-Rollup

	# A failed poll (a GraphQL TLS handshake timeout on #5983) says nothing about the run: retry, and give up
	# only when the API stays down.
	if ($null -eq $all) {
		$transient++
		'[{0}] PR {1} transient gh failure {2}/3' -f (Get-Date).ToString('HH:mm:ss'), $Pr, $transient
		if ($transient -ge 3) {
			'gh pr view failed 3 polls in a row'
			exit 3
		}
		Start-Sleep -Seconds $PollSeconds
		continue
	}
	$transient = 0

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
