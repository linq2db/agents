#!/usr/bin/env pwsh
<#
Compare two worktree-test.ps1 results - a run on the change under review and a
control run of the same filter on a tree without it - and split the test cases
into fixed / regressed / failing on both.

Why this script exists
----------------------
Every review probe and red-test proof ends in the same question: which cases
does the change turn green, and does it turn any green case red? Answering it
by eye over two failedTests lists is error-prone past a few dozen cases, and the
per-failure messages that say *how* a control failed (an exception, or wrong
rows) are capped at -MaxFailures (20) in worktree-test.ps1's `failures[]`, so a
large control run leaves most of them blank. This script diffs the full
`failedTests[]` lists and, for any case whose message was truncated away, reads
it back from the run's `logPath`.

Contract
--------

Input (named parameters):
  -Head      <path>    required; worktree-test.ps1 JSON for the run WITH the change
  -Control   <path>    required; worktree-test.ps1 JSON for the run WITHOUT it
                       (both as written by worktree-test.ps1 -OutFile, or its captured
                       stdout; a trailing "[exited with code N]" line is tolerated)
  -Filter    <string>  optional; -like wildcard on the test display name, e.g. 'Probe_*'
  -NoMessages          optional; skip the per-case message lookup

Output (stdout, single JSON object):
  {
    "head":      { "summary": {...}, "failed": 76,  "logPath": "..." },
    "control":   { "summary": {...}, "failed": 180, "logPath": "..." },
    "fixed":     [ { "test": "X(\"SQLite.MS\",1)", "control": "LinqToDB.LinqToDBException : ..." } ],
    "regressed": [ { "test": "...", "head": "Expected: ... But was: ..." } ],
    "bothFail":  [ "..." ]
  }

A case that passed on both runs is not listed. A case absent from one run (a
filter or data-source mismatch) cannot be told apart from a pass here - compare
the two `summary.total` values before trusting an empty `regressed`.

Messages come from `failures[]` when present, otherwise from the first non-empty
lines after `failed <test>` in the run's log; "" when the log is gone.

Exit codes:
  0 = compared, nothing regressed
  1 = bad input (missing / unparseable file)
  2 = compared, at least one case regressed
#>

param(
    [Parameter(Mandatory)][string]$Head,
    [Parameter(Mandatory)][string]$Control,
    [string]$Filter,
    [switch]$NoMessages
)

$ErrorActionPreference = 'Stop'

function Read-Result([string]$path) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Result file not found: $path"
    }

    $text = (Get-Content -LiteralPath $path -Raw) -replace '\[exited with code \d+\]\s*$', ''
    $json = $text | ConvertFrom-Json

    $messages = @{}
    foreach ($f in @($json.failures)) {
        if ($f -and $f.test) { $messages[$f.test] = (@($f.message) -join ' ').Trim() }
    }

    $failed = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($t in @($json.failedTests)) {
        if ($t -and (-not $Filter -or $t -like $Filter)) { [void]$failed.Add($t) }
    }

    [pscustomobject]@{
        Summary  = $json.summary
        LogPath  = $json.logPath
        Failed   = $failed
        Messages = $messages
        LogLines = $null
    }
}

function Get-Message($result, [string]$test) {
    if ($NoMessages) { return '' }
    if ($result.Messages.ContainsKey($test)) { return $result.Messages[$test] }

    if ($null -eq $result.LogLines) {
        $result.LogLines = if ($result.LogPath -and (Test-Path -LiteralPath $result.LogPath)) {
            @(Get-Content -LiteralPath $result.LogPath)
        } else { @() }
    }

    $lines  = $result.LogLines
    $marker = "failed $test "
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if (-not $lines[$i].StartsWith($marker)) { continue }

        $taken = @()
        for ($j = $i + 1; $j -lt $lines.Count -and $taken.Count -lt 3; $j++) {
            $line = $lines[$j].Trim()
            if ($line -eq '') { if ($taken.Count -gt 0) { break } else { continue } }
            if ($line -like 'from *') { continue }
            $taken += $line
        }
        return ($taken -join ' ')
    }

    return ''
}

try {
    $h = Read-Result $Head
    $c = Read-Result $Control
}
catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}

$fixed     = @($c.Failed | Where-Object { -not $h.Failed.Contains($_) } | Sort-Object |
    ForEach-Object { [ordered]@{ test = $_; control = (Get-Message $c $_) } })
$regressed = @($h.Failed | Where-Object { -not $c.Failed.Contains($_) } | Sort-Object |
    ForEach-Object { [ordered]@{ test = $_; head = (Get-Message $h $_) } })
$bothFail  = @($h.Failed | Where-Object { $c.Failed.Contains($_) } | Sort-Object)

[ordered]@{
    head      = [ordered]@{ summary = $h.Summary; failed = $h.Failed.Count; logPath = $h.LogPath }
    control   = [ordered]@{ summary = $c.Summary; failed = $c.Failed.Count; logPath = $c.LogPath }
    fixed     = $fixed
    regressed = $regressed
    bothFail  = $bothFail
} | ConvertTo-Json -Depth 6

exit ($(if ($regressed.Count -gt 0) { 2 } else { 0 }))
