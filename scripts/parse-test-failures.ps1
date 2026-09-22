#!/usr/bin/env pwsh
<#
parse-test-failures.ps1 — turn an MTP run log into failures grouped by cause.

Why this exists
---------------
A full-suite log is 40 MB / 350 k lines, and the run summary gives you a count
and a flat list of test names — neither of which says *why*. Triaging a large
red run means reading one failure block per test name, which is dozens of
`Grep`/`Read` round-trips before any thinking starts. This does the grouping in
one allowlisted call: identical first-lines collapse, so ~120 failures become
~30 causes, each with a representative message and a count.

Two things about the log format that cost a rewrite when done by hand:

  1. A block is `failed <Test>("<cfg>") (<time>)`, and the message begins AFTER
     the `  from <...>.dll (<tfm>|<arch>)` line — not immediately after the
     `failed` line. Anchoring on the `failed` line alone yields empty messages.
  2. `[ActiveIssue]` verdicts land under **skipped**, not failed: since #5882 a
     gated test runs and reports `ResultState.Inconclusive` with the reason
     `[ActiveIssue] Known issue (...), still failing as expected:` followed by
     the observed failure. So `-IncludeSkipped` is how you audit whether a batch
     of gates is correctly scoped — `failed: 0` alone cannot tell you that.
     See .claude/docs/testing.md -> "Verifying an [ActiveIssue] gate".

Contract
--------
Input:
  -LogPath        <path>    required; the MTP run log (absolute or relative)
  -MessageLines   <int>     optional; how many message lines form the grouping
                            key and the representative sample. Default 3.
  -IncludeSkipped           optional; also parse `skipped` blocks, reported in a
                            separate `skipped` array.
  -Top            <int>     optional; keep only the N largest groups.

Output (stdout, single JSON object):
  {
    "ok": true,
    "logPath": "C:/.../run.log",
    "failedTotal": 119,
    "failed":  [ { "count": 16, "test": "Concat_...", "message": "..." }, ... ],
    "skippedTotal": 102,
    "skipped": [ { "count": 20, "test": "UpdateTest...", "message": "..." }, ... ]
  }

Groups are sorted by count descending. `test` is the method name with its
parameter list stripped, so the same method across providers and the direct /
LinqService transports collapses into one row.
#>
param(
    [Parameter(Mandatory)][string]$LogPath,
    [int]$MessageLines = 3,
    [switch]$IncludeSkipped,
    [int]$Top
)

. "$PSScriptRoot/_shared.ps1"
$global:ScriptBaseName = 'parse-test-failures'

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $LogPath -PathType Leaf)) {
    Exit-WithError -Message "Log not found: $LogPath" -NextAction 'pass -LogPath <path to an MTP run log>'
}

$full = (Resolve-Path -LiteralPath $LogPath).Path

# outcome -> list of @{ Test; Message }
$collected = @{ failed = [System.Collections.Generic.List[object]]::new()
                skipped = [System.Collections.Generic.List[object]]::new() }

$outcome  = $null   # 'failed' | 'skipped' while inside a block
$test     = $null
$seenFrom = $false
$msg      = [System.Collections.Generic.List[string]]::new()

function Close-Block {
    if ($script:outcome -and $script:test) {
        $script:collected[$script:outcome].Add(
            [pscustomobject]@{ Test = $script:test; Message = ($script:msg -join ' | ') })
    }
    $script:outcome  = $null
    $script:test     = $null
    $script:seenFrom = $false
    $script:msg.Clear()
}

foreach ($line in [System.IO.File]::ReadLines($full)) {
    # `failed X("cfg") (123ms)` / `skipped X("cfg")` - skipped carries no duration.
    if ($line -match '^failed (.+?) \(\d') {
        Close-Block
        $outcome = 'failed'; $test = $Matches[1]
        continue
    }

    if ($IncludeSkipped -and $line -match '^skipped (.+)$') {
        Close-Block
        $outcome = 'skipped'; $test = $Matches[1]
        # a skipped block states its reason immediately, with no `from` line
        $seenFrom = $true
        continue
    }

    if (-not $outcome) { continue }

    if (-not $seenFrom) {
        if ($line -match '^\s+from .*\.dll ') { $seenFrom = $true }
        continue
    }

    if ($msg.Count -ge $MessageLines) { Close-Block; continue }
    if ($line.Trim())                 { $msg.Add($line.Trim()) }
}

Close-Block

function Group-Outcome([System.Collections.Generic.List[object]]$rows) {
    $grouped = $rows |
        ForEach-Object { [pscustomobject]@{ Name = ($_.Test -replace '\(.*$', ''); Message = $_.Message } } |
        Group-Object Name |
        Sort-Object Count -Descending |
        ForEach-Object { [pscustomobject]@{ count = $_.Count; test = $_.Name; message = $_.Group[0].Message } }

    if ($Top -gt 0) { $grouped = $grouped | Select-Object -First $Top }
    # Unary comma: without it PowerShell unrolls the return value, and a single
    # group then serializes as a bare object instead of a one-element array -
    # so a consumer reading `.skipped[0]` breaks on exactly the runs that have
    # one cause. Caught by the fixture below, not by reading the code.
    return ,@($grouped)
}

$result = [ordered]@{
    ok          = $true
    logPath     = $full
    failedTotal = $collected.failed.Count
    failed      = Group-Outcome $collected.failed
}

if ($IncludeSkipped) {
    $result.skippedTotal = $collected.skipped.Count
    $result.skipped      = Group-Outcome $collected.skipped
}

Write-JsonOutput ([pscustomobject]$result)
