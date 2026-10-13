#!/usr/bin/env pwsh
#requires -Version 7
<#
.SYNOPSIS
    Where a Claude Code project's token spend goes: per-session and total usage from the
    transcript JSONL files, cost-weighted, with the most re-read files and the share of
    long sessions.

.DESCRIPTION
    Reads `<ProjectDir>/*.jsonl` (main sessions) and `<ProjectDir>/<session>/subagents/*.jsonl`.
    One API response is written as several `assistant` lines sharing `message.id`, each
    repeating the usage block, so usage is counted once per `message.id` (last line wins).

    Cost is expressed in input-token equivalents, using the published price ratios relative
    to the base input price: cache read 0.1x, 5-minute cache write 1.25x, 1-hour cache write
    2x, output 5x. Ratios, not dollars, so the answer does not depend on the model's price.

    `contextPeak` is the largest input + cache-read + cache-write of one request in a
    session — the context the session had reached.

.PARAMETER ProjectDir
    The Claude Code project transcript directory (per user — e.g.
    `~/.claude/projects/<encoded-repo-path>`). Required; never hardcode one here.

.PARAMETER Days
    Only sessions whose transcript was written in the last N days. Default 30.

.PARAMETER Top
    Rows in the per-session and re-read tables. Default 10.

.PARAMETER LongSession
    Request count at which a session counts as long. Default 150.

.OUTPUTS
    One JSON object: { window, totals, shares, longSessions, topSessions, topRereads }
#>
[CmdletBinding()]
param(
	[Parameter(Mandatory)][string]$ProjectDir,
	[int]$Days = 30,
	[int]$Top = 10,
	[int]$LongSession = 150,
	[int]$Concurrency = 6
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/_shared.ps1"
$global:ScriptBaseName = 'session-usage'

if (-not (Test-Path -LiteralPath $ProjectDir)) {
	Exit-WithError -Message "project dir not found: $ProjectDir" -NextAction 'pass -ProjectDir <~/.claude/projects/<encoded-repo-path>>'
}
$since = (Get-Date).AddDays(-$Days)
$mains = @(Get-ChildItem -LiteralPath $ProjectDir -Filter '*.jsonl' -File | Where-Object { $_.LastWriteTime -ge $since })
if (-not $mains.Count) { Exit-WithError -Message "no transcripts newer than $Days days in $ProjectDir" -NextAction 'raise -Days' }

$rows = $mains | ForEach-Object -ThrottleLimit $Concurrency -Parallel {
	function Read-Transcript([string]$path) {
		$byId  = @{}
		$reads = @{}
		$title = $null
		foreach ($line in [System.IO.File]::ReadLines($path)) {
			if ($line.Contains('"type":"ai-title"')) {
				try { $title = ($line | ConvertFrom-Json).aiTitle } catch { }
				continue
			}
			if (-not $line.Contains('"type":"assistant"')) { continue }
			try { $o = $line | ConvertFrom-Json -Depth 64 } catch { continue }
			$m = $o.message
			if (-not $m -or -not $m.id) { continue }
			if ($m.usage) { $byId[$m.id] = $m.usage }
			foreach ($c in @($m.content)) {
				if ($c.type -eq 'tool_use' -and $c.name -eq 'Read' -and $c.input.file_path) {
					$k = [string]$c.input.file_path
					$reads[$k] = 1 + [int]$reads[$k]
				}
			}
		}
		$t = [ordered]@{ requests = 0; input = 0L; cacheRead = 0L; write5m = 0L; write1h = 0L; output = 0L; contextPeak = 0L }
		foreach ($u in $byId.Values) {
			$t.requests++
			$in = [long]$u.input_tokens; $cr = [long]$u.cache_read_input_tokens; $cw = [long]$u.cache_creation_input_tokens
			$w1h = [long]$u.cache_creation.ephemeral_1h_input_tokens
			$w5m = if ($u.cache_creation) { [long]$u.cache_creation.ephemeral_5m_input_tokens } else { $cw }
			$t.input += $in; $t.cacheRead += $cr; $t.write5m += $w5m; $t.write1h += $w1h; $t.output += [long]$u.output_tokens
			$ctx = $in + $cr + $cw
			if ($ctx -gt $t.contextPeak) { $t.contextPeak = $ctx }
		}
		[pscustomobject]@{ title = $title; usage = $t; reads = $reads }
	}

	$main = Read-Transcript $_.FullName
	$subDir = Join-Path $_.DirectoryName (Join-Path $_.BaseName 'subagents')
	$subs = if (Test-Path -LiteralPath $subDir) { @(Get-ChildItem -LiteralPath $subDir -Filter '*.jsonl' -File | ForEach-Object { Read-Transcript $_.FullName }) } else { @() }
	[pscustomobject]@{ session = $_.BaseName; written = $_.LastWriteTime; main = $main; subs = $subs }
}

function Get-Cost($u) {
	[double]$u.input + 0.1 * $u.cacheRead + 1.25 * $u.write5m + 2.0 * $u.write1h + 5.0 * $u.output
}

$tot = [ordered]@{ sessions = 0; requests = 0; subagentRequests = 0; input = 0L; cacheRead = 0L; write5m = 0L; write1h = 0L; output = 0L }
$cost = [ordered]@{ input = 0.0; cacheRead = 0.0; cacheWrite = 0.0; output = 0.0; subagents = 0.0; total = 0.0 }
$perSession = foreach ($r in $rows) {
	$tot.sessions++
	$sc = 0.0; $req = 0
	foreach ($part in @(@{ u = $r.main.usage; sub = $false }) + @($r.subs | ForEach-Object { @{ u = $_.usage; sub = $true } })) {
		$u = $part.u
		$c = Get-Cost $u
		$sc += $c; $req += $u.requests
		$tot.requests += $u.requests; if ($part.sub) { $tot.subagentRequests += $u.requests; $cost.subagents += $c }
		$tot.input += $u.input; $tot.cacheRead += $u.cacheRead; $tot.write5m += $u.write5m; $tot.write1h += $u.write1h; $tot.output += $u.output
		$cost.input += $u.input; $cost.cacheRead += 0.1 * $u.cacheRead; $cost.cacheWrite += 1.25 * $u.write5m + 2.0 * $u.write1h; $cost.output += 5.0 * $u.output
	}
	$cost.total += $sc
	[pscustomobject]@{
		session     = $r.session
		title       = $r.main.title
		written     = $r.written.ToString('yyyy-MM-dd HH:mm')
		requests    = $req
		mainRequests = $r.main.usage.requests
		contextPeak = $r.main.usage.contextPeak
		cost        = [math]::Round($sc)
	}
}

$long = @($perSession | Where-Object { $_.mainRequests -ge $LongSession })
$rereads = @{}
foreach ($r in $rows) {
	foreach ($t in @($r.main) + @($r.subs)) {
		foreach ($k in $t.reads.Keys) {
			$n = [int]$t.reads[$k]
			if ($n -gt 1) { $rereads[$k] = [int]$rereads[$k] + ($n - 1) }
		}
	}
}

function Get-Share([double]$part) { if ($cost.total) { [math]::Round(100 * $part / $cost.total, 1) } else { 0 } }

Write-JsonOutput ([ordered]@{
	window       = [ordered]@{ projectDir = $ProjectDir; days = $Days; since = $since.ToString('yyyy-MM-dd') }
	totals       = $tot
	shares       = [ordered]@{
		unit           = 'percent of cost in input-token equivalents (read 0.1x, write 1.25x/2x, output 5x)'
		input          = Get-Share $cost.input
		cacheRead      = Get-Share $cost.cacheRead
		cacheWrite     = Get-Share $cost.cacheWrite
		output         = Get-Share $cost.output
		subagents      = Get-Share $cost.subagents
	}
	longSessions = [ordered]@{
		threshold   = $LongSession
		count       = $long.Count
		costShare   = Get-Share (($long | Measure-Object cost -Sum).Sum)
	}
	topSessions  = @($perSession | Sort-Object cost -Descending | Select-Object -First $Top)
	topRereads   = @($rereads.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First $Top | ForEach-Object { [ordered]@{ file = $_.Key; extraReads = $_.Value } })
})
