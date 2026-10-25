#!/usr/bin/env pwsh
# gh-issue-digest.ps1 - one call that returns a compact digest of many issues / PRs: title, state, state reason,
# milestone, labels, the head of the body and the head of each comment.
#
# For surveying prior art (related issues, closed answers, maintainer positions) before a design or a reply.
# Hand-rolling it is N `gh issue view --json ... --jq` calls of the same shape, and `gh issue view` rejects
# `--comments` together with `--json` and fails on a PR number; the REST issues endpoint serves both kinds.
#
# Usage: pwsh -NoProfile -File .claude/scripts/gh-issue-digest.ps1 -Numbers 2206,2771,5803 [-BodyChars 1500]
#        [-CommentChars 700] [-MaxComments 20] [-Repo linq2db/linq2db] [-OutFile .build/.agents/<name>.json]
#
# Output: one JSON object on stdout ({ repo, items: [...] }); with -OutFile, the digest goes to the file and stdout
# carries a one-line summary. A per-item failure is reported in that item's `error`, not as a script failure.

[CmdletBinding()]
param(
	# Comma-separated issue / PR numbers. A [string], not [string[]]: `pwsh -File` passes one string.
	[Parameter(Mandatory)][string] $Numbers,
	[string] $Repo         = 'linq2db/linq2db',
	[int]    $BodyChars    = 1500,
	[int]    $CommentChars = 700,
	[int]    $MaxComments  = 20,
	[string] $OutFile
)

$ErrorActionPreference = 'Stop'
$global:ScriptBaseName = 'gh-issue-digest'
. "$PSScriptRoot/_shared.ps1"

$list = @($Numbers.Split(',', [StringSplitOptions]::RemoveEmptyEntries) | ForEach-Object { $_.Trim().TrimStart('#') } | Where-Object { $_ })
if ($list.Count -eq 0) { Exit-WithError 'no issue numbers given' -NextAction 'pass -Numbers 123,456' }
foreach ($n in $list) {
	if ($n -notmatch '^\d+$') { Exit-WithError "not an issue number: '$n'" -NextAction 'pass -Numbers as comma-separated integers' }
}

function Get-Head([string] $Text, [int] $Max) {
	if (-not $Text) { return @{ text = ''; truncated = $false } }
	if ($Text.Length -le $Max) { return @{ text = $Text; truncated = $false } }
	return @{ text = $Text.Substring(0, $Max); truncated = $true }
}

$shared = "$PSScriptRoot/_shared.ps1"

$items = @($list | ForEach-Object -ThrottleLimit 6 -Parallel {
	. $using:shared
	$n    = $_
	$repo = $using:Repo

	$issue = Invoke-GhJson -ArgumentList @('api', "repos/$repo/issues/$n")
	if (-not $issue.ok) { return [pscustomobject]@{ number = [int]$n; error = $issue.error } }
	$d = $issue.data

	$comments = @()
	$commentError = $null
	if ($d.comments -gt 0 -and $using:MaxComments -gt 0) {
		$c = Invoke-GhJson -ArgumentList @('api', "repos/$repo/issues/$n/comments?per_page=100")
		if ($c.ok) { $comments = @($c.data | Select-Object -First $using:MaxComments) }
		else       { $commentError = $c.error }
	}

	[pscustomobject]@{
		number       = [int]$n
		kind         = if ($d.pull_request) { 'pr' } else { 'issue' }
		title        = $d.title
		state        = $d.state
		stateReason  = $d.state_reason
		milestone    = $d.milestone.title
		labels       = @($d.labels | ForEach-Object { $_.name })
		author       = $d.user.login
		createdAt    = $d.created_at
		closedAt     = $d.closed_at
		body         = $d.body
		commentCount = $d.comments
		comments     = @($comments | ForEach-Object { [pscustomobject]@{ author = $_.user.login; body = $_.body } })
		commentError = $commentError
	}
})

# Truncate after the parallel join: the helper is a function of this scope, not of the runspaces.
foreach ($it in $items) {
	if ($it.PSObject.Properties['error'] -and $it.error) { continue }
	$h = Get-Head $it.body $BodyChars
	$it.body = $h.text
	$it | Add-Member -NotePropertyName bodyTruncated -NotePropertyValue $h.truncated
	foreach ($c in $it.comments) {
		$ch = Get-Head $c.body $CommentChars
		$c.body = $ch.text
		$c | Add-Member -NotePropertyName truncated -NotePropertyValue $ch.truncated
	}
}

$items = @($items | Sort-Object number)
$failed = @($items | Where-Object { $_.PSObject.Properties['error'] -and $_.error }).Count

$result = [ordered]@{ repo = $Repo; count = $items.Count; failed = $failed; items = $items }

if ($OutFile) { Write-JsonOutput -InputObject $result -OutFile $OutFile -Summary @{ count = $items.Count; failed = $failed } }
else          { Write-JsonOutput -InputObject $result }
