<#
trx-failures.ps1 — groups the failed results of a local TRX report into buckets, so a full-suite run with
hundreds of failures reads as a handful of causes.

Produce the TRX by running the built test executable directly:
  .build/bin/Tests/<Config>/<tfm>/linq2db.Tests.exe --provider <name> --test-progress
      --report-trx --report-trx-filename <file>.trx --results-directory .build/.agents/<dir>

-GroupBy message   normalises the first message line (quoted text, brackets and numbers collapsed) - the
                   first pass over a run, where one bucket is one symptom.
-GroupBy reason    groups by the translator's "Additional details: '…'" text when present, else by the first two
                   message lines - the pass for "could not be converted to SQL", where the message is the same
                   for every refused feature and only the reason tells them apart.

-Like filters failures by a -like pattern on the full message (e.g. '*could not be converted*').
-DirectOnly drops the LinqService twins, which repeat the direct failure through the remote transport.

Output (single JSON object on stdout):
  { ok, trx, failed, buckets: [ { count, key, tests: [ first -Samples names ] } ] }

Conventions: `.claude/docs/script-authoring.md`.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $Trx,
    [ValidateSet('message', 'reason')]
    [string] $GroupBy = 'message',
    [string] $Like = '*',
    [int]    $Samples = 6,
    [switch] $DirectOnly
)

$global:ScriptBaseName = 'trx-failures'
. (Join-Path $PSScriptRoot '_shared.ps1')

if (-not (Test-Path -LiteralPath $Trx)) {
    Exit-WithError "TRX not found: $Trx" -NextAction 'pass -Trx as the path the test run printed under "Out of process file artifacts produced"'
}

[xml]$x = [IO.File]::ReadAllText((Resolve-Path -LiteralPath $Trx))
$ns     = @{ t = 'http://microsoft.com/schemas/VisualStudio/TeamTest/2010' }

function Get-Key([string]$message) {
    if ($GroupBy -eq 'reason' -and $message -match "Additional details: '([^']*)'") {
        return $Matches[1]
    }

    $lines = @($message -split "`r?`n" | Where-Object { $_.Trim() })
    $take  = if ($GroupBy -eq 'reason') { 2 } else { 1 }
    $text  = if ($lines.Count -gt 0) { ($lines | Select-Object -First $take) -join ' | ' } else { '<no message>' }

    if ($GroupBy -eq 'message') {
        $text = $text `
            -replace '"[^"]*"', '"…"' `
            -replace "'[^']*'", "'…'" `
            -replace '\[[^\]]*\]', '[…]' `
            -replace '\b\d+(\.\d+)?\b', 'N'
    }

    $text = ($text -replace '\s+', ' ').Trim()
    if ($text.Length -gt 220) { $text = $text.Substring(0, 220) }
    return $text
}

$rows = foreach ($r in (Select-Xml -Xml $x -XPath '//t:UnitTestResult[@outcome="Failed"]' -Namespace $ns)) {
    $n       = $r.Node
    $message = [string]$n.Output.ErrorInfo.Message

    if ($message -notlike $Like) { continue }
    if ($DirectOnly -and $n.testName -like '*.LinqService*') { continue }

    [pscustomobject]@{ Test = [string]$n.testName; Key = Get-Key $message }
}

$buckets = @($rows | Group-Object Key | Sort-Object Count -Descending | ForEach-Object {
    [ordered]@{
        count = $_.Count
        key   = $_.Name
        tests = @($_.Group.Test | Select-Object -Unique | Select-Object -First $Samples)
    }
})

Write-JsonOutput ([ordered]@{
    ok      = $true
    trx     = $Trx
    failed  = @($rows).Count
    buckets = $buckets
})
