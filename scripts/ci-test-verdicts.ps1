#!/usr/bin/env pwsh
<#
Parse downloaded CI test logs into one per-case verdict table, for both CI systems.

Why this script exists
----------------------
Answering "which tests failed, on which providers, and how" from a `test-all` round means
parsing the same runner output over and over. On #5882 that produced six throwaway parsers in
one session — one to classify failures, one to pull the expected-vs-actual out of an
[ActiveIssue] mismatch, one to list a single test's providers, one to find gated tests that
still ran, and two more. They all read the same two line shapes.

The shapes, after stripping the leading ISO timestamp and ANSI escapes:

    failed  <Test>("<provider>"[,<args>]) (<duration>)
      <message line>
    skipped <Test>("<provider>"[,<args>]) (<duration>)
      <message line>

and, for a case the ActiveIssue attribute rewrote, the message line is one of:

    [ActiveIssue] Test passed but is marked with [ActiveIssue] (<details>).      -> gate-too-wide
    [ActiveIssue] Expected <T> with message matching '<pat>' for <d>, but found: -> signature-mismatch
    [ActiveIssue] Expected <T> for <d>, but found:                               -> signature-mismatch
    [ActiveIssue] Expected any failure for <d>, but found:                       -> signature-mismatch
    [ActiveIssue] More than one equally specific [ActiveIssue] applies to '<p>'  -> gate-collision
    [ActiveIssue] Known issue (<details>), still failing as expected:            -> gate-holds

The message clause is optional because `ErrorMessage` is: a gate declaring only `ErrorTypeName`, or
neither, still mismatches its signature and must not be read as an ordinary regression.

Anything else on a `failed` line is an ordinary `failure`.

Getting the logs
----------------
Azure : .claude/scripts/azp-build-failures.ps1 -BuildId <n>   (persists to .build/.agents/azp-<n>/)
GitHub: .claude/scripts/gh-run-logs.ps1 -RunId <id>           (persists to .build/.agents/gh-<id>/)
        Fetch-only by design; it wraps the per-job `gh api …/jobs` + `…/logs
        --allow-escape-sequences` pair, because `gh run view --log-failed`
        stream-errors on a run this size. Pass -Conclusion all to include green
        legs (see "Harvesting what a holding gate hides" below).

See `.claude/docs/ci-tests.md` -> *Reading failed CI test runs*.

Usage
-----
    .claude/scripts/ci-test-verdicts.ps1 -Dir .build/.agents/gh-5882,.build/.agents/azp-23600
    .claude/scripts/ci-test-verdicts.ps1 -Dir <dirs> -Test String_PadRight_Translation
    .claude/scripts/ci-test-verdicts.ps1 -Dir <dirs> -Verdict gate-too-wide -Format table

Output: JSON on stdout by default (one object per deduped case), plus the full row set at
<WriteDir>/ci-test-verdicts.json. `-Format table` prints a grouped human summary instead.

Deduping: a leg that retries prints the same case once per attempt, and a case appears in every
leg that ran it. Rows are deduped on test+args+provider+verdict+actual, so a count here is a
count of distinct outcomes, not of executions.

A provider can appear under two verdicts at once — read before narrowing a gate
-------------------------------------------------------------------------------
The verdict is per test *case*, and `[ActiveIssue]` cannot target a `[Values]` / `[ValueSource]`
argument. So one provider routinely lands under `gate-too-wide` for some argument values and
`gate-holds` for others, and a `gate-too-wide` row on its own does **not** mean the provider passes.

Before narrowing a Configuration or deleting a gate on the strength of a `gate-too-wide` row, group
that test's rows by provider and check whether the same provider also appears under `gate-holds`. If
it does, the fix is to **split the test on the argument that divides them**, not to touch the gate's
provider list.

On #5882 this cost a whole CI round: build 23600 put the same twelve Oracle configs under both
verdicts for `DateTimeOffsetAddTimeSpan` — holding for the null interval, too-wide for the six
non-null ones — the too-wide half was read as "Oracle passes", the gate was deleted, and the null
case came back red in 23608. The MySQL half of the same site failed symmetrically, narrowed onto a
driver the test's own `[DataSources]` excludes.

A second, independent reason, so don't stop at the per-case check: the verdict is also **per
environment**. A green case on one matrix leg is not evidence the test passes anywhere else — it is
evidence about the process that ran it. `Issue3117Test1/2` came back `gate-too-wide` on
`SQLite.Classic.MPM` from a full GitHub run, and the declared `NotImplementedException` reproduced
locally on demand; the failure turns on whether `MiniProfiler.Current` happens to be ambient when
the connection is created, so a narrow local filter fails where the whole fixture passes. **Reproduce
locally before deleting a declaration.** When a gate's outcome turns out to depend on ambient
process-global state at all, no declaration is stable — serialise the bucket (`[NonParallelizable]`)
or exclude the provider, rather than declaring around it.

Harvesting what a holding gate hides
------------------------------------
`-Verdict gate-holds -Format table` prints, per test, the failure each gate is actually holding
against and the providers sharing it. That message is quoted only in the runner output of a leg that
**passed**, so it is invisible to `azp-build-failures.ps1` (failures-only) — pull the green leg's log
with `azp-step-log.ps1` first. This is the evidence source for re-declaring a gate that was migrated
bare, or for validating one whose declaration was carried over from prose.
#>

[CmdletBinding()]
param(
    # Directories holding downloaded *.log files. Pass both CI systems' dirs at once.
    [Parameter(Mandatory)][string[]] $Dir,
    # Only these test methods (exact name, no arguments).
    [string[]] $Test,
    # Only these verdicts.
    [ValidateSet('gate-too-wide', 'signature-mismatch', 'gate-collision', 'gate-holds', 'failure')]
    [string[]] $Verdict,
    [ValidateSet('json', 'table')][string] $Format = 'json',
    [string] $WriteDir
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

if (-not $WriteDir) { $WriteDir = Join-Path (Get-Location) '.build/.agents/ci-test-verdicts' }
if (-not (Test-Path $WriteDir)) { New-Item -ItemType Directory -Path $WriteDir -Force | Out-Null }
$WriteDir = (Resolve-Path -LiteralPath $WriteDir).Path

$esc = [char]27

function Clear-Decoration {
    param([string] $Line)

    if ($null -eq $Line) { return '' }

    return ($Line -replace '^\S+Z\s?', '') -replace "$esc\[[0-9;]*m", ''
}

$testFilter = if ($Test) { '(?:' + (($Test | ForEach-Object { [regex]::Escape($_) }) -join '|') + ')' } else { '[A-Za-z_]\w*' }
$caseRx     = "^(failed|skipped)\s+($testFilter)\(""([^""]*)""([^)]*)\)\s+\(\d"

$rows = [System.Collections.Generic.List[object]]::new()

foreach ($d in $Dir) {
    if (-not (Test-Path $d)) { Write-Error "Log directory not found: $d" }

    foreach ($file in Get-ChildItem -LiteralPath $d -Filter *.log -File) {
        $leg   = $file.BaseName -replace '^tests-', ''
        $lines = [System.IO.File]::ReadAllLines($file.FullName)

        for ($i = 0; $i -lt $lines.Length; $i++) {
            $line = Clear-Decoration $lines[$i]
            if ($line -notmatch $caseRx) { continue }

            $outcome  = $Matches[1]
            $testName = $Matches[2]
            $provider = $Matches[3]
            $args_    = $Matches[4].TrimStart(',')

            $message = Clear-Decoration $lines[[Math]::Min($i + 1, $lines.Length - 1)]

            $kind         = 'failure'
            $details      = ''
            $expectedType = ''
            $expectedText = ''
            $actual       = ''

            if ($message -match '^\s*\[ActiveIssue\] Test passed but is marked with \[ActiveIssue\] \((.*)\)\. If the issue') {
                $kind = 'gate-too-wide'; $details = $Matches[1]
            }
            elseif ($message -match '^\s*\[ActiveIssue\] More than one equally specific \[ActiveIssue\] applies to ''([^'']+)''') {
                $kind = 'gate-collision'; $details = $Matches[1]
            }
            elseif ($message -match '^\s*\[ActiveIssue\] Known issue \((.*)\), still failing as expected') {
                $kind = 'gate-holds'; $details = $Matches[1]

                # The failure the gate is hiding, quoted right after the marker. This is the only place a
                # gate that already holds says what it holds against, and it appears in a *green* leg - so
                # it is the harvest source for re-declaring a gate that was migrated bare.
                for ($j = $i + 2; $j -lt [Math]::Min($i + 12, $lines.Length); $j++) {
                    $candidate = (Clear-Decoration $lines[$j]).Trim()
                    if ($candidate) { $actual = $candidate; break }
                }
            }
            # The message clause is OPTIONAL: ActiveIssueAttribute.Expectation emits four shapes, and a gate
            # declaring only a type (ErrorTypeName with no ErrorMessage) or nothing at all produces
            # "Expected <T> for <d>, but found:" / "Expected any failure for <d>, but found:". Requiring
            # "with message matching" silently dropped both into the `failure` bucket, where they read as
            # ordinary regressions - #5882's Issue4669QueryFilterTest surfaced that way.
            elseif ($message -match '^\s*\[ActiveIssue\] Expected (?:<(?<type>[^>]+)>|(?<anyfail>any failure|a failure))(?: with message matching ''(?<text>.*)'')?(?: for (?<details>.*?))?, but found:\s*$') {
                $kind         = 'signature-mismatch'
                $expectedType = if ($Matches['type']) { $Matches['type'] } else { '(any failure)' }
                $expectedText = $Matches['text']
                $details      = $Matches['details']

                # first non-blank line after "but found:" is what actually happened
                for ($j = $i + 2; $j -lt [Math]::Min($i + 12, $lines.Length); $j++) {
                    $candidate = (Clear-Decoration $lines[$j]).Trim()
                    if ($candidate) { $actual = $candidate; break }
                }
            }
            else {
                $actual = $message.Trim()
            }

            if ($outcome -eq 'skipped' -and $kind -eq 'failure') { continue }   # an ordinary NUnit skip

            $rows.Add([pscustomobject]@{
                verdict      = $kind
                test         = $testName
                args         = $args_
                provider     = $provider
                leg          = $leg
                expectedType = $expectedType
                expected     = $expectedText
                actual       = $actual
                details      = $details
            })
        }
    }
}

$deduped = $rows | Sort-Object test, args, provider, verdict, actual -Unique
if ($Verdict) { $deduped = $deduped | Where-Object { $Verdict -contains $_.verdict } }

$jsonPath = Join-Path $WriteDir 'ci-test-verdicts.json'
$deduped | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $jsonPath -Encoding utf8

if ($Format -eq 'json') {
    $deduped | ConvertTo-Json -Depth 4
    return
}

"cases: $($deduped.Count)   sites: $(($deduped | Group-Object test).Count)   written: $jsonPath"
''
foreach ($verdictGroup in $deduped | Group-Object verdict | Sort-Object Name) {
    "=== $($verdictGroup.Name)  [$($verdictGroup.Count)]"

    foreach ($site in $verdictGroup.Group | Group-Object test | Sort-Object Name) {
        $providers = ($site.Group.provider | Sort-Object -Unique)
        "  {0} ({1} provider configs)" -f $site.Name, $providers.Count
        "      providers: " + ($providers -join ', ')

        if ($verdictGroup.Name -eq 'signature-mismatch') {
            foreach ($shape in $site.Group | Group-Object expectedType, expected, actual) {
                $first = $shape.Group[0]
                if ($first.expected) {
                    "      expected <$($first.expectedType)> matching: $($first.expected)"
                } else {
                    "      expected <$($first.expectedType)>, any message"
                }
                "      actual                                   : $($first.actual)"
            }
        }

        # Only when the caller asked for holding gates: printing the hidden failure for every one of the
        # thousands that hold in a normal run would bury everything else. Asking for it is asking to harvest.
        if ($verdictGroup.Name -eq 'gate-holds' -and $Verdict -contains 'gate-holds') {
            foreach ($shape in $site.Group | Group-Object actual | Sort-Object Name) {
                $shapeProviders = ($shape.Group.provider | Sort-Object -Unique)
                "      holds against ($($shapeProviders.Count)): $($shape.Group[0].actual)"
                "          " + ($shapeProviders -join ', ')
            }
        }
    }

    ''
}
