<#
Run a filtered linq2db test selection and measure the test process's memory profile.

Why this script exists
----------------------
Answering "is this test's memory use a leak/retention bug or just its working set?"
needs the *curve*, not the peak: memory that climbs monotonically through a run and
never drops is retention (something keeps every intermediate result reachable), while
a sawtooth that plateaus is ordinary steady-state allocation the GC is reclaiming.
A single peak number cannot tell those apart, and that distinction is what identifies
the fix.

It also launches the test exe **detached** (`Start-Process -WindowStyle Hidden -PassThru`)
rather than through the Bash tool, which kills anything running past its 600 s cap - see
`.claude/docs/agent-rules.md` and the long-run rules in `testing.md`.

Usage (invoke via the PowerShell tool, not wrapped in Bash):

    .claude\scripts\measure-test-memory.ps1 -Exe <path-to-linq2db.Tests.exe> `
        -Filter "FullyQualifiedName~CreateData.CreateDatabase|FullyQualifiedName~MyTest" `
        -Provider SqlServer.2022 -Label baseline

Measure the same selection before and after a change and compare `peakWorkingSetMB`
plus the `curve` shape.

Output: one JSON object on stdout - exit code, elapsed, peaks, a downsampled curve, and
the paths of the full CSV / run log under `-OutDir`.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]   $Exe,
    [Parameter(Mandatory)] [string]   $Filter,
                           [string[]] $Provider  = @(),
                           [string]   $Label     = 'run',
                           [int]      $IntervalMs = 500,
                           [int]      $CurvePoints = 20,
                           [string]   $OutDir    = '.build/.agents'
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/_shared.ps1"

if (-not (Test-Path $Exe))
{
    Exit-WithError -Message "test executable not found: $Exe" `
        -NextAction 'build the test project first, then pass the built exe path to -Exe'
}

$null = New-Item -ItemType Directory -Force -Path $OutDir
$log = Join-Path $OutDir "memtest-$Label.log"
$csv = Join-Path $OutDir "memtest-$Label.csv"

$argList = @()
if ($Provider.Count -gt 0) { $argList += '--provider'; $argList += $Provider }
$argList += '--filter'; $argList += $Filter

$proc = Start-Process -FilePath $Exe -ArgumentList $argList -WorkingDirectory (Split-Path $Exe) `
    -WindowStyle Hidden -RedirectStandardOutput $log -RedirectStandardError "$log.err" -PassThru

$start = Get-Date
$rows  = [System.Collections.Generic.List[object]]::new()

while (-not $proc.HasExited)
{
    Start-Sleep -Milliseconds $IntervalMs
    try { $proc.Refresh() } catch { break }
    if ($proc.HasExited) { break }

    $rows.Add([pscustomobject]@{
        sec    = [math]::Round(((Get-Date) - $start).TotalSeconds, 1)
        wsMB   = [math]::Round($proc.WorkingSet64 / 1MB)
        privMB = [math]::Round($proc.PrivateMemorySize64 / 1MB)
    })
}

$rows | Export-Csv -Path $csv -NoTypeInformation

# Downsample to a readable curve - the shape is the point, not every sample.
$curve = @()
if ($rows.Count -gt 0)
{
    $step = [math]::Max(1, [int][math]::Ceiling($rows.Count / [double]$CurvePoints))
    for ($i = 0; $i -lt $rows.Count; $i += $step) { $curve += $rows[$i] }
}

$summary = Select-String -Path $log -Pattern '^\s*(total|failed|succeeded|skipped):\s*\d+' -ErrorAction SilentlyContinue |
    ForEach-Object { $_.Line.Trim() }

[pscustomobject]@{
    label             = $Label
    exitCode          = $proc.ExitCode
    elapsedSec        = [math]::Round(((Get-Date) - $start).TotalSeconds)
    samples           = $rows.Count
    peakWorkingSetMB  = ($rows | Measure-Object wsMB   -Maximum).Maximum
    peakPrivateMB     = ($rows | Measure-Object privMB -Maximum).Maximum
    curve             = $curve
    testSummary       = @($summary)
    logPath           = $log
    csvPath           = $csv
} | ConvertTo-Json -Depth 5
