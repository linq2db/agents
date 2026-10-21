#!/usr/bin/env pwsh
# test-cap.ps1 — stop a local linq2db test run whose filtered test count exceeds a cap.
#
# Armed by .claude/hooks/arm-test-cap.js when a test command is issued; not normally run by hand. It watches for
# the linq2db.Tests*.exe process that command starts, reads that process's --test-progress heartbeat, and once
# `total` (the filtered count, linq2db#6098) is known, stops the process if total > -Max. A filter that selects
# far more than intended is caught the same way as a deliberately wide run.
#
# A process is this watcher's only when it descends from the same claude.exe as -AnchorPid (another session's run
# is never touched) and, when -Filter is given, the filter text appears on its command line or an ancestor's.
# Each process is claimed through an exclusive marker file, so overlapping watchers never act on one run twice.
#
# Verdicts land next to the heartbeat as test-cap.<pid>.json; test-status.ps1 prints them. A heartbeat without
# `totalIsUpperBound` (reporter predates #6098) or with it set is recorded as unverifiable and left running —
# the count it carries is not the filtered one.
#
# Usage:
#   pwsh -NoProfile -File .claude/scripts/test-cap.ps1 -AnchorPid <pid> [-Filter <expr>] [-Max 1000] [-LogDir <dir>]
#   pwsh -NoProfile -File .claude/scripts/test-cap.ps1 -ArgsFile <json>   # hook mode: { anchorPid, filter, max, logDir, readyFile }
# The hook goes through `cmd /c start /b`, where a `|` in a filter would be a pipe, hence the args file. The ready
# file is written once the session is resolved (or found missing); nothing is ever written to stdout in hook mode.

[CmdletBinding()]
param(
	[int]    $AnchorPid,
	[string] $Filter,
	[int]    $Max             = 1000,
	[string] $LogDir,
	[string] $ArgsFile,
	[string] $ReadyFile,
	[int]    $StartTimeoutSec = 2400,
	[int]    $PollSec         = 3
)

$ErrorActionPreference = 'Stop'

if ($ArgsFile) {
	$a = Get-Content -Raw -Path $ArgsFile | ConvertFrom-Json
	Remove-Item -Path $ArgsFile -ErrorAction SilentlyContinue
	$AnchorPid = [int]$a.anchorPid
	if ($a.filter)    { $Filter    = [string]$a.filter }
	if ($a.max)       { $Max       = [int]$a.max }
	if ($a.logDir)    { $LogDir    = [string]$a.logDir }
	if ($a.readyFile) { $ReadyFile = [string]$a.readyFile }
}

function Signal-Ready([string] $text) {
	if ($ReadyFile) { try { Set-Content -Path $ReadyFile -Value $text } catch { } }
	else            { Write-Output $text }
}

try { (Get-Process -Id $PID).PriorityClass = 'BelowNormal' } catch { }

$armedUtc = [DateTime]::UtcNow
$logFile  = if ($LogDir) { Join-Path $LogDir "test-cap.watcher.$PID.log" } else { $null }

function Log([string] $msg) {
	if (-not $logFile) { return }
	try {
		$dir = Split-Path $logFile
		if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force $dir | Out-Null }
		Add-Content -Path $logFile -Value ("{0:HH:mm:ss} {1}" -f [DateTime]::Now, $msg)
	} catch { }
}

function Get-Proc([int] $id) {
	Get-CimInstance Win32_Process -Filter "ProcessId=$id" -ErrorAction SilentlyContinue
}

# Ancestors of $proc (itself first), guarded against pid reuse: a parent must predate its child.
function Get-Chain($proc, [hashtable] $all) {
	$chain = @()
	$cur   = $proc
	for ($i = 0; $cur -and $i -lt 20; $i++) {
		$chain += $cur
		$parent = if ($all) { $all[[int]$cur.ParentProcessId] } else { Get-Proc $cur.ParentProcessId }
		if (-not $parent -or $parent.CreationDate -gt $cur.CreationDate) { break }
		$cur = $parent
	}
	return $chain
}

function Normalize([string] $s) {
	if (-not $s) { return '' }
	return ($s -replace '[\s"''`]', '')
}

function Find-RepoRoot([string] $path) {
	for ($d = [IO.Path]::GetDirectoryName($path); $d; $d = [IO.Path]::GetDirectoryName($d)) {
		if (Test-Path (Join-Path $d 'linq2db.slnx')) { return $d }
	}
	return $null
}

# Mirrors TestProgressTracker.ResolvePath: an explicit --test-progress dir / .json wins, else <repo>/.build/.agents.
function Find-Heartbeat($proc, [string] $chainCmd) {
	$id = $proc.ProcessId
	if ($chainCmd -match '--test-progress\s+("([^"]+)"|''([^'']+)''|(\S+))') {
		$v = @($Matches[2], $Matches[3], $Matches[4]) | Where-Object { $_ } | Select-Object -First 1
		if ($v -and $v -notmatch '^(1|true|on|yes|enabled?)$' -and $v -notmatch '^--') {
			if ($v.EndsWith('.json', [StringComparison]::OrdinalIgnoreCase)) { return $v }
			if (Test-Path $v -PathType Container) {
				return Get-ChildItem -Path $v -Filter "test-progress.*.$id.json" -File -ErrorAction SilentlyContinue |
					Select-Object -First 1 -ExpandProperty FullName
			}
		}
	}
	$root = Find-RepoRoot $proc.ExecutablePath
	if (-not $root) { return $null }
	return Get-ChildItem -Path (Join-Path $root '.build/.agents') -Filter "test-progress.*.$id.json" -File -ErrorAction SilentlyContinue |
		Select-Object -First 1 -ExpandProperty FullName
}

function Claim-Dir($proc) {
	$root = Find-RepoRoot $proc.ExecutablePath
	if ($root) { return Join-Path $root '.build/.agents' }
	return $LogDir
}

function Try-Claim([string] $dir, [int] $id) {
	try {
		if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force $dir | Out-Null }
		$fs = [IO.File]::Open((Join-Path $dir "test-cap.$id.claim"), [IO.FileMode]::CreateNew, [IO.FileAccess]::Write)
		$fs.Dispose()
		return $true
	} catch { return $false }
}

function Write-Verdict([string] $dir, [hashtable] $v) {
	try { $v | ConvertTo-Json -Compress | Set-Content -Path (Join-Path $dir "test-cap.$($v.pid).json") -Encoding utf8 } catch { }
}

# ---- resolve this session's claude.exe while the hook (the anchor's child) still waits for the ready file ----
$anchor = Get-Proc $AnchorPid
$session = Get-Chain $anchor $null | Where-Object { $_.Name -like 'claude*' } | Select-Object -First 1
if (-not $session) {
	Log "no claude.exe above pid $AnchorPid; not armed"
	Signal-Ready "test-cap: no claude.exe above pid $AnchorPid; not armed"
	exit 0
}
$sessionPid   = [int]$session.ProcessId
$filterNorm   = Normalize $Filter
Log "armed session=$sessionPid max=$Max filter=$Filter"
Signal-Ready "test-cap: armed (session $sessionPid, max $Max)"

$seen    = @{}   # pid -> $true (examined, whatever the outcome)
$claimed = @{}   # pid -> @{ dir; done }
$lastLiveUtc = $null

while ($true) {
	$nowUtc = [DateTime]::UtcNow

	$cands = @(Get-CimInstance Win32_Process -Filter "Name LIKE 'linq2db.Tests%'" -ErrorAction SilentlyContinue |
		Where-Object { -not $seen.ContainsKey([int]$_.ProcessId) })

	if ($cands.Count -gt 0) {
		$all = @{}
		Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | ForEach-Object { $all[[int]$_.ProcessId] = $_ }

		foreach ($c in $cands) {
			$id = [int]$c.ProcessId
			$seen[$id] = $true
			if ($c.CreationDate.ToUniversalTime() -lt $armedUtc.AddSeconds(-5)) { continue }

			$chain = Get-Chain $c $all
			if (-not ($chain | Where-Object { [int]$_.ProcessId -eq $sessionPid })) { continue }

			$chainCmd = ($chain | Where-Object { [int]$_.ProcessId -ne $sessionPid } | ForEach-Object { $_.CommandLine }) -join ' '
			if ($filterNorm -and -not (Normalize $chainCmd).Contains($filterNorm)) { continue }

			$dir = Claim-Dir $c
			if (-not (Try-Claim $dir $id)) { Log "pid $id claimed by another watcher"; continue }

			$claimed[$id] = @{ dir = $dir; cmd = $chainCmd; done = $false; proc = $c }
			$lastLiveUtc  = $nowUtc
			Log "claimed pid $id ($($c.Name))"
		}
	}

	$anyLive = $false
	foreach ($id in @($claimed.Keys)) {
		$e = $claimed[$id]
		$alive = [bool](Get-Process -Id $id -ErrorAction SilentlyContinue)
		if ($alive) { $anyLive = $true }
		if ($e.done -or -not $alive) { continue }

		$hb = Find-Heartbeat $e.proc $e.cmd
		if (-not $hb -or -not (Test-Path $hb)) { continue }

		$p = $null
		try { $p = Get-Content -Raw -Path $hb | ConvertFrom-Json } catch { continue }
		$total = [long]$p.total
		if ($total -le 0) { continue }

		$e.done = $true
		$v = @{ pid = $id; total = $total; max = $Max; filter = $Filter; heartbeat = $hb; time = [DateTime]::Now.ToString('s') }

		if ($null -eq $p.PSObject.Properties['totalIsUpperBound']) {
			$v.verdict = 'unverifiable'; $v.reason = 'heartbeat predates the filtered total (linq2db#6098)'
		}
		elseif ($p.totalIsUpperBound) {
			$v.verdict = 'unverifiable'; $v.reason = 'total is the discovered upper bound, not the filtered count'
		}
		elseif ($total -gt $Max) {
			try {
				Stop-Process -Id $id -Force -ErrorAction Stop
				$v.verdict = 'stopped'
			} catch {
				$v.verdict = 'stop-failed'; $v.reason = "$_"
			}
		}
		else {
			$v.verdict = 'within-cap'
		}

		Log "pid $id total=$total -> $($v.verdict) $($v.reason)"
		if ($v.verdict -ne 'within-cap') { Write-Verdict $e.dir $v }
	}

	if ($anyLive) { $lastLiveUtc = $nowUtc }

	if ($claimed.Count -eq 0) {
		if (($nowUtc - $armedUtc).TotalSeconds -gt $StartTimeoutSec) { Log 'no run appeared; exiting'; break }
	}
	elseif (-not $anyLive -and ($nowUtc - $lastLiveUtc).TotalSeconds -gt 30) {
		Log 'claimed runs finished; exiting'
		break
	}

	Start-Sleep -Seconds $PollSec
}

foreach ($id in $claimed.Keys) {
	Remove-Item -Path (Join-Path $claimed[$id].dir "test-cap.$id.claim") -ErrorAction SilentlyContinue
}
