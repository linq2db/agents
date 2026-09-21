#!/usr/bin/env pwsh
<#
Summarize already-fetched provider-leg logs: per-suite test counts, whole-suite retries, and a
census of provider error codes.

Why this script exists
----------------------
Answering "did that leg actually test anything, and what went wrong" is a fixed four-step chain that
was hand-rolled three times in one session (#5950, GitHub runs 35585752703 / 35590271257 /
35600848967): grep the runner's `Test run summary` blocks, grep the retry warnings, then
`grep -o -E "ORA-[0-9]+" | sort | uniq -c` for a census. Each step is a pipe, so each is a novel
command string that misses allowlist matching, and the census step in particular is easy to get
subtly wrong.

Two traps it removes, both of which produced a wrong published claim before it existed:

  - **The Grep tool cannot read these logs.** They carry ANSI escapes and NUL bytes, so ripgrep
    classifies them as binary and skips them, reporting `Found 0 total occurrences across 0 files`.
    That zero means "searched nothing", not "found nothing", and it is indistinguishable from a
    clean result unless the `across 0 files` half is read. This script uses .NET file reads.
  - **A raw error-code count is not a failure count.** The Oracle create script's idempotent cleanup
    issues `DROP TABLE` against a fresh database, so every green Oracle leg carries a constant
    baseline of ORA-00942. A census is only meaningful compared across legs and runs, which is why
    the output is per-code counts rather than a verdict.

Contract
--------
  -Dir       <path>    required; a directory of `*.log` files, as written by gh-run-logs.ps1
  -CodePrefix <string> error-code prefix to census, default 'ORA'. Use 'SQL' for DB2, etc.
  -Top       <int>     how many distinct codes to report, default 20

Output (JSON):
  {
    "dir": "...",
    "legs": [ {
        "leg": "tests-Lin-t_Oracle1112",
        "suites": [ { "tfm": "net10.0", "kind": "main", "verdict": "Passed!", "total": 20729, "failed": 0 } ],
        "retries": 0,
        "codes": [ { "code": "ORA-00942", "count": 114 } ]
    } ]
  }

`retries` counts the whole-suite retry warnings run-provider-tests.sh emits, so a nonzero value means
the leg went green only on a later attempt - which a check's colour never tells you.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $Dir,
    [string] $CodePrefix = 'ORA',
    [int]    $Top = 20
)

$ErrorActionPreference = 'Stop'

$global:ScriptBaseName = 'summarize-leg-logs'
. "$PSScriptRoot/_shared.ps1"

if (-not (Test-Path $Dir)) { Exit-WithError "directory not found: $Dir" }
$Dir = (Resolve-Path $Dir).Path

$logs = @(Get-ChildItem -LiteralPath $Dir -Filter *.log -File)
if ($logs.Count -eq 0) { Exit-WithError "no *.log files in $Dir - run gh-run-logs.ps1 first" }

# The runner prints the assembly path on the summary line and the counts on the next two, all
# ANSI-wrapped. Anchored on the path so the tfm/kind come from the same line as the verdict.
$summaryRx = [regex] '(?<verdict>Passed!|Failed!).*?/(?<tfm>net[\d.]+)/(?<kind>main|efcore)/x64/'
# Every log line is prefixed with the runner's ISO timestamp, so the count lines cannot be anchored
# at line start - only at line end, which is what keeps `total:` in prose from matching.
$countRx   = [regex] '(?:^|\s)(?<name>total|failed):\s*(?<n>\d+)\s*$'
$codeRx    = [regex] ("\b" + [regex]::Escape($CodePrefix) + "-\d+\b")
$retryRx   = [regex] 'attempt \d+/\d+\), retrying|::warning::.*retrying'

$legs = foreach ($log in $logs) {
    # ReadAllLines, not Get-Content: these files reach hundreds of MB and the pipeline overhead on a
    # 3M-line log is the difference between seconds and minutes.
    $lines = [System.IO.File]::ReadAllLines($log.FullName)

    $suites  = [System.Collections.Generic.List[object]]::new()
    $codes   = @{}
    $retries = 0
    $pending = $null

    for ($i = 0; $i -lt $lines.Length; $i++) {
        $line = $lines[$i] -replace "`e\[[0-9;]*m", ''

        $m = $summaryRx.Match($line)
        if ($m.Success) {
            # A summary arriving while one is still open means its counts never parsed. Keep it
            # rather than dropping it silently - a suite with null counts is a visible defect,
            # a vanished suite is not.
            if ($null -ne $pending) { $suites.Add([pscustomobject]$pending) }
            # Counts follow the summary line; hold it open until both are seen.
            $pending = [ordered]@{
                tfm     = $m.Groups['tfm'].Value
                kind    = $m.Groups['kind'].Value
                verdict = $m.Groups['verdict'].Value
                total   = $null
                failed  = $null
            }
            continue
        }

        if ($null -ne $pending) {
            $c = $countRx.Match($line)
            if ($c.Success) {
                $pending[$c.Groups['name'].Value] = [int]$c.Groups['n'].Value
                if ($null -ne $pending.total -and $null -ne $pending.failed) {
                    $suites.Add([pscustomobject]$pending)
                    $pending = $null
                }
                continue
            }
        }

        if ($retryRx.IsMatch($line)) { $retries++ }

        foreach ($hit in $codeRx.Matches($line)) {
            $codes[$hit.Value] = 1 + ($codes[$hit.Value] ?? 0)
        }
    }

    if ($null -ne $pending) { $suites.Add([pscustomobject]$pending) }

    [pscustomobject]@{
        leg     = $log.BaseName
        suites  = @($suites)
        retries = $retries
        codes   = @($codes.GetEnumerator() |
                      Sort-Object -Property Value -Descending |
                      Select-Object -First $Top |
                      ForEach-Object { [pscustomobject]@{ code = $_.Key; count = $_.Value } })
    }
}

Write-JsonOutput ([ordered]@{
    dir  = $Dir
    legs = @($legs | Sort-Object leg)
})
