#!/usr/bin/env pwsh
# Work-plan scaffolding and validation.
#
#   -Action init       scaffold .claude/plans/<key>/plan.md from the template
#   -Action validate   schema completeness; ok=false with per-block errors (-Done: the exit check —
#                      a still-pending gate and a TO-n with no test named in G-01 become errors;
#                      -Summary: counts and errors only)
#   -Action gates      derive the applicable definition-of-done gate subset from P6
#   -Action reconcile  report changed files that no P6 edit-point authorizes
#   -Action gap-report render .claude/plans/<key>/gaps.md as counts + dominant class
#   -Action section    read the plan by P-block: no -Section / -Match lists every block's id, heading and
#                      line range; -Section P10,P11 returns those blocks' lines; -Match <regex> returns the
#                      text around each hit (-Context chars either side), in -Section's blocks or the whole
#                      plan. Lines are cut into -MaxLineChars chunks (L<n>: / L<n>+:), so a persisted result
#                      pages with Read
#
# Schema and block semantics: .claude/docs/work-plan.md
#
# The plan lives in the corpus submodule, so every path here resolves relative to
# this script, never to the caller's working directory — a worktree has its own
# .claude/ checkout and the plan must land in the one the caller is actually using.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('init', 'validate', 'gates', 'reconcile', 'gap-report', 'section')]
    [string] $Action,

    [string] $Key,
    [ValidateSet('S', 'M', 'L')]
    [string] $Tier = 'M',
    [string] $Title,
    [string] $Branch,
    [string] $Base = 'origin/master',

    # Where the *code* lives. Defaults to the clone that owns this corpus, but branch work
    # happens in a worktree (agent-rules -> Creating a new branch), and the plan lives in the
    # corpus either way -- so without this, -Reconcile diffs a tree that has none of the changes
    # and reports a clean zero.
    [string] $RepoRoot,

    # reconcile only: the ref whose changes are reconciled. A review reads a PR from the primary clone without
    # checking it out, so pass the fetched PR ref (origin/pr/<n>); the working tree is consulted only for HEAD.
    [string] $Head = 'HEAD',

    [switch] $Force,

    # validate only: the exit check run before the diff's adversarial read (definition-of-done G-09). An amend
    # mid-implementation legitimately has pending gates, so without it they stay warnings.
    [switch] $Done,

    # validate only: emit counts and errors, not the edit-point list or the warnings — a Tier L plan's full output
    # overflows a tool-output cap.
    [switch] $Summary,

    # section only: comma-separated block ids (a [string], since -File does not split arrays), a case-insensitive
    # regex, the characters kept either side of a hit, and the chunk size for long lines (0 = no cut).
    [string] $Section,
    [string] $Match,
    [int] $Context = 240,
    [int] $MaxLineChars = 1500
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/_shared.ps1"

$global:ScriptBaseName = 'work-plan'

$CorpusRoot   = (Resolve-Path "$PSScriptRoot/..").Path
$PlansRoot    = Join-Path $CorpusRoot 'plans'
$TemplatePath = Join-Path $CorpusRoot 'docs/work-plan-template.md'

# ---------------------------------------------------------------- helpers

function Get-RepoRoot {
    # The linq2db checkout that owns this corpus: one level above .claude/.
    return (Resolve-Path "$CorpusRoot/..").Path
}

function Get-CurrentBranch {
    param([string] $RepoRoot)
    $r = Invoke-Process -FilePath 'git' -ArgumentList @('-C', $RepoRoot, 'rev-parse', '--abbrev-ref', 'HEAD')
    if (-not $r.ok) { return $null }
    return $r.stdout.Trim()
}

function ConvertTo-Key {
    param([string] $BranchName)
    if ([string]::IsNullOrWhiteSpace($BranchName)) { return $null }
    return ($BranchName -replace '[/\\]', '-').Trim()
}

function Resolve-Key {
    param([string] $Explicit, [string] $RepoRoot)
    if (-not [string]::IsNullOrWhiteSpace($Explicit)) { return (ConvertTo-Key $Explicit) }
    $b = Get-CurrentBranch -RepoRoot $RepoRoot
    if ([string]::IsNullOrWhiteSpace($b) -or $b -eq 'HEAD') {
        Exit-WithError -Message 'cannot derive a plan key: not on a named branch' `
                       -NextAction 'pass -Key <branch-or-key>'
    }
    if ($b -in @('master', 'main')) {
        Exit-WithError -Message "refusing to derive a plan key from '$b'" `
                       -NextAction 'create a work branch first, or pass -Key <key> explicitly'
    }
    return (ConvertTo-Key $b)
}

function Get-PlanPath {
    param([string] $PlanKey)
    return (Join-Path (Join-Path $PlansRoot $PlanKey) 'plan.md')
}

function Read-PlanLines {
    param([string] $Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        Exit-WithError -Message "no plan at $Path" -NextAction 'run -Action init first'
    }
    return @([System.IO.File]::ReadAllLines($Path))
}

# Split the plan into ordered blocks: @{ id = 'P7'; heading = '...'; lines = @() }
function Split-PlanBlocks {
    param([string[]] $Lines)
    $blocks  = @()
    $current = $null
    foreach ($line in $Lines) {
        if ($line -match '^##\s+(P\d+)\b(.*)$') {
            if ($null -ne $current) { $blocks += $current }
            $current = [ordered]@{ id = $Matches[1]; heading = $Matches[2].Trim(); lines = @() }
        }
        elseif ($null -ne $current) {
            $current.lines += $line
        }
    }
    if ($null -ne $current) { $blocks += $current }
    return @($blocks)
}

function Get-Block {
    param($Blocks, [string] $Id)
    foreach ($b in $Blocks) { if ($b.id -eq $Id) { return $b } }
    return $null
}

# Content bullets of a block, ignoring blanks, comments and placeholders.
function Get-BlockRows {
    param($Block)
    if ($null -eq $Block) { return @() }
    $rows = @()
    foreach ($l in $Block.lines) {
        $t = $l.Trim()
        if ($t -eq '') { continue }
        if ($t.StartsWith('<!--')) { continue }
        if ($t -match '^_None') { continue }
        if ($t -match '^_Not yet') { continue }
        $rows += $t
    }
    return @($rows)
}

function Test-BlockHasContent {
    # A single-row block returns unwrapped, and `.Count` on a bare string throws
    # under StrictMode — wrap before counting.
    param($Block)
    return (@(Get-BlockRows -Block $Block).Count -gt 0)
}

# ---------------------------------------------------------------- init

function Invoke-Init {
    param([string] $PlanKey, [string] $RepoRoot)

    if (-not (Test-Path -LiteralPath $TemplatePath)) {
        Exit-WithError -Message "template not found at $TemplatePath"
    }

    $planPath = Get-PlanPath -PlanKey $PlanKey
    if ((Test-Path -LiteralPath $planPath) -and -not $Force) {
        Exit-WithError -Message "a plan already exists at $planPath" `
                       -NextAction 'amend the existing plan instead of re-initialising, or pass -Force to overwrite'
    }

    $raw   = [System.IO.File]::ReadAllText($TemplatePath)
    $start = $raw.IndexOf('<!-- TEMPLATE-BEGIN -->')
    $end   = $raw.IndexOf('<!-- TEMPLATE-END -->')
    if ($start -lt 0 -or $end -lt 0 -or $end -le $start) {
        Exit-WithError -Message 'template markers missing or malformed in work-plan-template.md'
    }
    $start = $start + '<!-- TEMPLATE-BEGIN -->'.Length
    $body  = $raw.Substring($start, $end - $start).Trim()

    $branchName = $Branch
    if ([string]::IsNullOrWhiteSpace($branchName)) {
        $branchName = Get-CurrentBranch -RepoRoot $RepoRoot
    }
    $planTitle = $Title
    if ([string]::IsNullOrWhiteSpace($planTitle)) { $planTitle = $PlanKey }

    $body = $body.Replace('{{KEY}}', $PlanKey)
    $body = $body.Replace('{{TITLE}}', $planTitle)
    $body = $body.Replace('{{TIER}}', $Tier)
    $body = $body.Replace('{{BRANCH}}', ($branchName ?? '—'))

    # Tier S carries only P1/P2/P6/P9 — drop the (M/L) blocks rather than
    # shipping a plan full of empty headings.
    $dropped = @()
    if ($Tier -eq 'S') {
        $keep    = @('P1', 'P2', 'P6', 'P9')
        $lines   = @($body -split "`n")
        $out     = @()
        $skip    = $false
        foreach ($l in $lines) {
            if ($l -match '^##\s+(P\d+)\b') {
                $id   = $Matches[1]
                $skip = ($keep -notcontains $id)
                if ($skip) { $dropped += $id }
            }
            if (-not $skip) { $out += $l }
        }
        $body = ($out -join "`n").TrimEnd()

        # P8 is gone, so a criterion maps to the gate that observes it.
        $body = $body.Replace('each maps to a TO-n in P8', 'each maps to the G-nn gate in P9 that observes it')
        $body = $body.Replace('→ TO-1', '→ G-01')
    }

    $dir = Split-Path -Parent $planPath
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [System.IO.File]::WriteAllText($planPath, $body + "`n", (New-Object System.Text.UTF8Encoding $false))

    Write-JsonOutput ([ordered]@{
        ok           = $true
        action       = 'init'
        key          = $PlanKey
        tier         = $Tier
        path         = $planPath
        branch       = $branchName
        droppedBlocks = @($dropped)
        nextAction   = 'fill every `fill:` marker, then run -Action validate'
    })
}

# ---------------------------------------------------------------- validate

function Invoke-Validate {
    param([string] $PlanKey, [string] $RepoRoot)

    $planPath = Get-PlanPath -PlanKey $PlanKey
    $lines    = Read-PlanLines -Path $planPath
    $blocks   = Split-PlanBlocks -Lines $lines
    $present  = @($blocks | ForEach-Object { $_.id })

    $errors   = @()
    $warnings = @()

    # Header: tier + status.
    $planTier   = $null
    $planStatus = $null
    foreach ($l in $lines) {
        if ($l -match '\*\*Tier:\*\*\s*([SML])\b')            { $planTier   = $Matches[1] }
        if ($l -match '\*\*Status:\*\*\s*([A-Za-z-]+)')        { $planStatus = $Matches[1] }
        if ($null -ne $planTier -and $null -ne $planStatus)    { break }
    }
    if ($null -eq $planTier) {
        $errors += 'header: no `**Tier:** S|M|L` found on the metadata line'
        $planTier = 'M'
    }

    # Unfilled markers.
    $fillCount = 0
    foreach ($l in $lines) { if ($l -match '<!--\s*fill:') { $fillCount++ } }
    if ($fillCount -gt 0) {
        # Single-quoted: a backtick before a letter is an escape in a
        # double-quoted string, so "`fill:`" would emit a form-feed.
        $errors += ('{0} unfilled fill: marker(s) remain - a filled block deletes its marker' -f $fillCount)
    }

    # Required blocks per tier.
    $required = @('P1', 'P2', 'P6', 'P9')
    if ($planTier -ne 'S') {
        $required = @('P1', 'P2', 'P3', 'P4', 'P5', 'P6', 'P7', 'P8', 'P9', 'P10', 'P11', 'P12')
    }
    foreach ($id in $required) {
        if ($present -notcontains $id) { $errors += "$id : block missing (required at Tier $planTier)" }
    }

    # P1/P2/P6 must actually say something.
    foreach ($id in @('P1', 'P2', 'P6')) {
        $b = Get-Block -Blocks $blocks -Id $id
        if ($null -ne $b -and -not (Test-BlockHasContent -Block $b)) {
            $errors += "$id : block is empty"
        }
    }

    # P2 rows are SC-n and should name a TO-n that P8 defines; Tier S has no P8, so a G-nn gate instead.
    $p2      = Get-Block -Blocks $blocks -Id 'P2'
    $p8Ids   = @(Get-BlockRows -Block (Get-Block -Blocks $blocks -Id 'P8') |
        Where-Object { $_ -match '^-\s*[*_]{0,2}(TO-\d+)' } | ForEach-Object { $Matches[1] })
    foreach ($row in (Get-BlockRows -Block $p2)) {
        if ($row -notmatch 'SC-\d+') { $errors += "P2 : row does not carry an SC-n id -- $row" }
        elseif ($planTier -eq 'S') {
            if ($row -match 'TO-\d+')       { $warnings += "P2 : SC row names a TO-n, but Tier S has no P8 -- map it to a G-nn gate -- $row" }
            elseif ($row -notmatch 'G-\d+') { $warnings += "P2 : SC row names no G-nn gate (Tier S has no P8) -- $row" }
        }
        elseif ($row -notmatch 'TO-\d+') { $warnings += "P2 : SC row names no TO-n obligation -- $row" }
        else {
            foreach ($m in [regex]::Matches($row, 'TO-\d+')) {
                if ($p8Ids -notcontains $m.Value) { $warnings += "P2 : SC row names $($m.Value), which P8 does not define -- $row" }
            }
        }
    }

    # P4: no OPEN row survives approval.
    $p4 = Get-Block -Blocks $blocks -Id 'P4'
    foreach ($row in (Get-BlockRows -Block $p4)) {
        # -cmatch, not -match: PowerShell compares case-insensitively by default, so the plain English
        # word "open" in a row's prose ("the open #5788 branch reserves ...") reads as the OPEN marker
        # and fails an otherwise-resolved unknown. The marker is uppercase by schema.
        if ($row -cmatch '\bOPEN\b') { $errors += "P4 : an OPEN unknown may not survive approval -- $row" }
        elseif ($row -match '^-\s' -and $row -notmatch 'resolved-by') {
            $errors += "P4 : row ends in neither `resolved-by ...` nor OPEN -- $row"
        }
    }

    # P6 rows: E-n <path> — what changes.
    $p6         = Get-Block -Blocks $blocks -Id 'P6'
    $editPoints = @()
    # Only bullet rows are edit-points. A block may also carry explanatory prose
    # -- a note on why something was dropped, a scoping caveat -- and demanding
    # an E-n id from a paragraph produces a diagnostic that reads as a malformed
    # edit-point. Same shape as the P8 rule below.
    # An edit-point row *leads* with its E-n id. A bullet that doesn't is prose --
    # a dropped-scope note, a caveat -- and demanding an id from it produces a
    # diagnostic that reads as a malformed edit-point. Same rule as P8's TO-n.
    foreach ($row in (Get-BlockRows -Block $p6)) {
        if ($row -notmatch '^-\s*[*_]{0,2}E-\d+') { continue }
        if ($row -match '`([^`]+)`') { $editPoints += $Matches[1] }
        else { $warnings += "P6 : row names no backticked path -- $row" }
    }
    if ($editPoints.Count -eq 0) { $errors += 'P6 : no edit-point row found (a row must lead with `- E-<n>`)' }

    # P7 rows each carry exactly one verdict.
    $p7 = Get-Block -Blocks $blocks -Id 'P7'
    foreach ($row in (Get-BlockRows -Block $p7)) {
        if ($row -notmatch '^-\s') { continue }
        $hasVerdict = ($row -match 'covered by E-\d+') -or
                      ($row -match 'deferred:') -or
                      ($row -match 'out-of-scope') -or
                      ($row -match 'Localized\b.*searched')
        if (-not $hasVerdict) {
            $errors += "P7 : row carries no verdict (covered by E-n | deferred: <reason> | out-of-scope | Localized - searched ...) -- $row"
        }
        if ($row -match '^\-\s*Localized' -and $row -notmatch 'searched') {
            $errors += "P7 : a bare 'Localized' with no named search is invalid -- $row"
        }
    }

    # P8 rows declare a proof mode.
    $p8 = Get-Block -Blocks $blocks -Id 'P8'
    # Only rows that *lead* with a TO-n id are obligations. A prose bullet that
    # merely references one (a symmetry note, a gating caveat) is not, and must
    # not be asked for a proof mode. Emphasis markers are tolerated on both the
    # id and the mode -- `- **TO-1** ... proof: **red-green**` is valid, and
    # rejecting it produces a diagnostic that reads as a missing declaration.
    # Amendment dates, for rules that apply only to amendments from a cutoff on.
    $amendDates = @{}
    $p11ForDates = Get-Block -Blocks $blocks -Id 'P11'
    if ($null -ne $p11ForDates) {
        foreach ($l in $p11ForDates.lines) {
            if ($l -match '^-\s+(?:\*\*)?(A-\d+)\b[^(\n]*\((\d{4}-\d{2}-\d{2})') { $amendDates[$Matches[1]] = $Matches[2] }
        }
    }

    foreach ($row in (Get-BlockRows -Block $p8)) {
        if ($row -notmatch '^-\s*[*_]{0,2}TO-\d+') { continue }
        if ($row -notmatch 'proof:\s*[*_]{0,2}\s*(red.{0,3}green|control|characterization)') {
            $errors += "P8 : row declares no proof mode (red-green | control | characterization) -- $row"
        }
        # work-plan.md -> P8: an unscoped obligation defaults to SQLite and the types its author thought of.
        # An amendment's obligation is the one a review round then finds red on an unrun provider (#5959 rounds
        # 4 and 7), so for amendments from 2026-10-21 the scope is required.
        if ($row -notmatch 'providers:') {
            $msg = "P8 : row names no providers: scope -- $row"
            $byAmendment = [regex]::Matches($row, '\bA-\d+\b') | Where-Object { $amendDates[$_.Value] -ge '2026-10-21' }
            if ($byAmendment) { $errors += $msg } else { $warnings += $msg }
        }
    }

    # P9 gate results.
    $p9 = Get-Block -Blocks $blocks -Id 'P9'
    foreach ($row in (Get-BlockRows -Block $p9)) {
        if ($row -notmatch 'G-\d+') { continue }
        if ($row -match '\(pending\)') {
            # work-plan.md -> P9: a gate left with no result is a fail, not an omission.
            if ($Done) { $errors += "P9 : gate still pending at the exit check -- $row" }
            else       { $warnings += "P9 : gate still pending -- $row" }
            continue
        }
        if ($row -notmatch '(pass|fail|n/a|skipped|blocked)') {
            $errors += "P9 : gate carries no result -- $row"
        }
        # A run left to CI has not passed yet, and the CI run that settles it is usually the next review's
        # (#5959 round 7: all three blockers sat in a G-01 written "pass, ... deferred to CI").
        if ($row -match '^-\s*[*_]{0,2}G-01\b[^:]*:\s*[*_]{0,2}pass\b' -and $row -match '(?i)\bdeferred\b|\bleft to CI\b') {
            $msg = "P9 : G-01 claims a pass but defers part of it to CI -- write 'blocked - CI <run>' until the run is read -- $row"
            $rowDate = [regex]::Match($row, '\b(\d{4}-\d{2}-\d{2})\b')
            if ($Done -and $rowDate.Success -and $rowDate.Groups[1].Value -ge '2026-10-21') { $errors += $msg } else { $warnings += $msg }
        }
        # A skipped/blocked gate must name what is therefore unverified. Test the
        # text *after* the result word — the gate id's own colon would otherwise
        # satisfy a naive "has a separator" check.
        if ($row -match '\b(skipped|blocked)\b(.*)$') {
            $tail = $Matches[2].Trim().TrimStart('-', [char]0x2014, ':').Trim()
            if ($tail.Length -lt 10) {
                $errors += "P9 : a $($Matches[1]) gate must name what is therefore unverified -- $row"
            }
        }
    }

    # G-01 names a test per TO-n: a run total counts tests, so an obligation with no test reads as covered
    # (work-plan.md -> P9). The entry is the G-01 row plus its continuation lines up to the next gate, since
    # per-obligation results are usually nested bullets. Only a pass/fail claim is checked.
    $g01Rows = @()
    $inG01   = $false
    foreach ($row in (Get-BlockRows -Block $p9)) {
        if ($row -match '^-\s*[*_]{0,2}G-(\d+)') { $inG01 = ($Matches[1] -eq '01') }
        if ($inG01) { $g01Rows += $row }
    }
    $g01 = $g01Rows -join "`n"
    # `TO-6a/6b/6c` and `TO-4a/b` name every listed obligation, not only the first (#4314)
    $g01 = [regex]::Replace($g01, 'TO-(\d+)([a-z])((?:/(?:\d+)?[a-z])+)', {
        param($m)
        $n   = $m.Groups[1].Value
        $ids = @("TO-$n$($m.Groups[2].Value)")
        foreach ($part in $m.Groups[3].Value.Split('/', [StringSplitOptions]::RemoveEmptyEntries)) {
            $ids += if ($part -match '^\d') { "TO-$part" } else { "TO-$n$part" }
        }
        $ids -join ' '
    })
    if ($g01 -match '\b(pass|fail)\b' -and $g01 -notmatch '\(pending\)') {
        foreach ($row in (Get-BlockRows -Block $p8)) {
            if ($row -notmatch '^-\s*[*_]{0,2}(TO-\d+[a-z]?)') { continue }
            $to = $Matches[1]
            if ($g01 -notmatch "(?<![\w-])$([regex]::Escape($to))(?!\w)") {
                $msg = "P9 : G-01 names no test for $to -- record one row per TO-n with its test method"
                if ($Done) { $errors += $msg } else { $warnings += $msg }
            }
        }

        # A mutation P8 names must have a recorded red in G-01: a named mutation nobody ran is a claim, not a
        # control (work-plan.md -> "A control obligation records the mutation").
        $mutationRx = '[Mm]utations?\s+(?:"([^"]+)"|`([^`]+)`(?:\s*(?:\u2192|->)\s*`([^`]+)`)?)'
        foreach ($row in (Get-BlockRows -Block $p8)) {
            if ($row -notmatch '^-\s*[*_]{0,2}(TO-\d+[a-z]?)') { continue }
            $to   = $Matches[1]
            $seen = [System.Collections.Generic.HashSet[string]]::new()
            foreach ($m in [regex]::Matches($row, $mutationRx)) {
                $name = if ($m.Groups[1].Success) { $m.Groups[1].Value }
                        elseif ($m.Groups[3].Success) { "$($m.Groups[2].Value)`` $([char]0x2192) ``$($m.Groups[3].Value)" }
                        else { $m.Groups[2].Value }
                if ($seen.Add($name) -and $g01.IndexOf($name, [StringComparison]::OrdinalIgnoreCase) -lt 0) {
                    $msg = "P9 : G-01 records no run of $to's mutation '$name' -- name the red it produced, or drop the claim"
                    if ($Done) { $errors += $msg } else { $warnings += $msg }
                }
            }
        }
    }

    # On a planned branch that edited Tests/, G-01 records test-diff-sweep.ps1's counts on the implemented tree
    # (definition-of-done.md). #6061: the sweep first ran after two review rounds, which drew four layout findings.
    # Not keyed on a pass/fail word in G-01: that plan's rows said "green" and "passed".
    $p6TestRows = if ($null -ne $p6) { @($p6.lines | Where-Object { $_ -match '^-\s+(?:\*\*)?E-\d+' -and $_ -match '`Tests/|\bTests/Linq/' }) } else { @() }
    if ($g01Rows.Count -gt 0 -and $p6TestRows.Count -gt 0 -and $g01 -notmatch 'test-diff-sweep') {
        $msg = "P9 : P6 edits Tests/ but G-01 records no test-diff-sweep.ps1 counts on the implemented tree -- run it before the commit and cite its counts"
        if ($Done) { $errors += $msg } else { $warnings += $msg }
    }

    # P10 entries need a reason.
    $p10 = Get-Block -Blocks $blocks -Id 'P10'
    foreach ($row in (Get-BlockRows -Block $p10)) {
        if ($row -notmatch '^-\s') { continue }
        if ($row.Length -lt 40 -and $row -notmatch '—|--|because|measured') {
            $warnings += "P10 : entry looks reasonless, and a reasonless entry suppresses nothing -- $row"
        }
    }

    # P10 ids: a cited `L-n` must be defined by a P10 entry. A promised P10 line that an edit never wrote reads
    # exactly like one that exists (#5943: D-12 cited a narrow-family entry for two rounds; it had been spliced away).
    $p10Ids = @()
    if ($null -ne $p10) {
        $p10Ids = @($p10.lines | ForEach-Object { if ($_ -match '^-\s+(?:\*\*)?(L-\d+)\b') { $Matches[1] } })
    }
    $otherLines = @($blocks | Where-Object { $_.id -ne 'P10' } | ForEach-Object { $_.lines })
    $cited = @($otherLines | ForEach-Object { [regex]::Matches($_, '\bL-\d+\b') | ForEach-Object { $_.Value } } | Sort-Object -Unique)
    foreach ($id in $cited) {
        if ($p10Ids -notcontains $id) { $errors += "P10 : $id is cited but no P10 entry defines it (``- $id ...``)" }
    }
    if ($p10Ids.Count -gt 0) {
        $p12Block = Get-Block -Blocks $blocks -Id 'P12'
        $p12Lines = if ($null -ne $p12Block) { $p12Block.lines } else { @() }
        foreach ($l in $p12Lines) {
            if ($l -match '(?i)Changed:[^\n]*\bP10\b' -and $l -notmatch '\bL-\d+\b') {
                $warnings += "P12 : a disposition adds P10 lines without naming their L-n ids -- $($l.Substring(0, [Math]::Min(120, $l.Length)))"
            }
        }
    }

    # P11 — an amendment that supersedes a D-n or adds a public type is a new plan pass: it must carry a
    # `re-derives:` line, and P12 must record a critic round that names it. The prose rule alone did not stop
    # #5708's A-13/A-14 (9 of 22 review findings), so entries dated from 2026-10-11 fail; older ones warn.
    $p11 = Get-Block -Blocks $blocks -Id 'P11'
    $p12Text = (Get-Block -Blocks $blocks -Id 'P12')
    $p12Text = if ($null -ne $p12Text) { $p12Text.lines -join "`n" } else { '' }
    if ($null -ne $p11) {
        $entries = @()
        $current = $null
        foreach ($l in $p11.lines) {
            # bold optional: most plans write `- A-n (date, note) —`, which a bold-only match skipped entirely
            if ($l -match '^-\s+(?:\*\*)?(A-\d+)') {
                if ($null -ne $current) { $entries += $current }
                $current = [ordered]@{ id = $Matches[1]; text = $l }
            }
            elseif ($null -ne $current) { $current.text += "`n" + $l }
        }
        if ($null -ne $current) { $entries += $current }

        foreach ($e in $entries) {
            $isNewPass = $e.text -match '(?i)\bsupersedes\b[^.\n]*\bD-\d+' -or $e.text -match '(?i)\b(new|adds? a) public type\b'
            if (-not $isNewPass) { continue }

            $missing = @()
            if ($e.text -notmatch '(?i)re-derives:') { $missing += 're-derives: line' }
            if ($p12Text -notmatch "\b$([regex]::Escape($e.id))\b") { $missing += 'P12 critic round naming it' }
            if ($missing.Count -eq 0) { continue }

            $msg = "P11 : $($e.id) supersedes a decision or adds a public type but has no $($missing -join ' and ') -- it is a new plan pass"
            $dated = [regex]::Match($e.text, '\((\d{4}-\d{2}-\d{2})[,)]')
            if ($dated.Success -and $dated.Groups[1].Value -ge '2026-10-11') { $errors += $msg } else { $warnings += $msg }
        }

        # An amendment that adds edit-points (a P6 row citing it) changed what the impact map and test list must
        # cover, so it owes a `re-derives:` line too. #6003 and #5959: most review findings sat in mechanisms
        # such amendments brought in without re-walking P4/P7/P8.
        $p6Lines = (Get-Block -Blocks $blocks -Id 'P6')
        $p6Lines = if ($null -ne $p6Lines) { $p6Lines.lines } else { @() }
        foreach ($e in $entries) {
            $idPattern = "\b$([regex]::Escape($e.id))\b"
            if (-not ($p6Lines | Where-Object { $_ -match '^-\s+(?:\*\*)?E-\d+' -and $_ -match $idPattern })) { continue }
            if ($e.text -match '(?i)re-derives:') { continue }

            $msg = "P11 : $($e.id) adds edit-points (a P6 row cites it) but has no re-derives: line -- re-walk P4/P7/P8 for what it brought in"
            $dated = [regex]::Match($e.text, '\((\d{4}-\d{2}-\d{2})[,)]')
            if ($dated.Success -and $dated.Groups[1].Value -ge '2026-10-16') { $errors += $msg } else { $warnings += $msg }
        }

        # The `re-derives:` line alone records an intention, not a re-walk: #5959's A-8/A-9 named only P6/P8/P9,
        # had no critic round, and 4 of round 5's 5 code findings sat in what they brought in. So an amendment
        # adding edit-points must also cite a P4/P7 row (or `P7: none - <searched>`) and be named by a P12 round.
        foreach ($e in $entries) {
            $idPattern = "\b$([regex]::Escape($e.id))\b"
            if (-not ($p6Lines | Where-Object { $_ -match '^-\s+(?:\*\*)?E-\d+' -and $_ -match $idPattern })) { continue }

            $missing = @()
            # any occurrence counts: prose in the entry may mention the token before the real line (#6162 A-5)
            $reDerives = [regex]::Matches($e.text, '(?i)re-derives:[^\n]*') | Where-Object { $_.Value -match '\b(P4|P7|U-\d+|R-\d+)\b' }
            if (-not $reDerives) { $missing += 'a P4/P7 row in its re-derives: line' }
            if ($p12Text -notmatch $idPattern) { $missing += 'a P12 critic round naming it' }
            if ($missing.Count -eq 0) { continue }

            $msg = "P11 : $($e.id) adds edit-points but lacks $($missing -join ' and ') -- the re-walk and its critique are what catch a dropped clause"
            $dated = [regex]::Match($e.text, '\((\d{4}-\d{2}-\d{2})[,)]')
            if ($dated.Success -and $dated.Groups[1].Value -ge '2026-10-19') { $errors += $msg } else { $warnings += $msg }
        }

        # An amendment adding test edit-points owes the amend-mode step 4 record: the *Test layout* embed and a sweep
        # of the branch's test diff. #5943 rounds 2, 4 and 5 drew layout nits from amendment-added tests; by round 5
        # the step existed in the skill and still was not run, so its record is now checked.
        foreach ($e in $entries) {
            $idPattern = "\b$([regex]::Escape($e.id))\b"
            # A Tests/ path anywhere on the row counts: an E-n leading with a source file can still add tests (#5943 E-39).
            if (-not ($p6Lines | Where-Object { $_ -match '^-\s+(?:\*\*)?E-\d+' -and $_ -match '`Tests/|\bTests/Linq/' -and $_ -match $idPattern })) { continue }
            if ($e.text -match '(?i)\bconventions:') { continue }

            $msg = "P11 : $($e.id) adds test edit-points but has no conventions: line -- record the Test layout embed and the sweep of the branch's test diff"
            $dated = [regex]::Match($e.text, '\((\d{4}-\d{2}-\d{2})[,)]')
            if ($dated.Success -and $dated.Groups[1].Value -ge '2026-10-19') { $errors += $msg } else { $warnings += $msg }
        }

        # An amendment answering a review finding fixes the instance it was shown unless it enumerates the class
        # (plan-critic.md vector 8). #6178 round 3: A-6 moved the route into the contract file and updated one of
        # the two comments describing that file. Warn from 2026-10-28; older entries predate the rule.
        foreach ($e in $entries) {
            if ($e.text -notmatch '(?i)/review-pr|/verify-review|/code-review|review round') { continue }
            if ($e.text -match '(?im)^\s*class:') { continue }
            $dated = [regex]::Match($e.text, '\((\d{4}-\d{2}-\d{2})[,)]')
            if (-not ($dated.Success -and $dated.Groups[1].Value -ge '2026-10-28')) { continue }
            $warnings += "P11 : $($e.id) answers a review finding but has no class: line -- name the search that enumerates every sibling and close or carry each"
        }
    }

    # P12 verdict — an error at Tier L, a warning at Tier M.
    #
    # Rounds are recorded chronologically, so the FIRST verdict word in the block is the OLDEST one. A plan
    # that was refuted in round 1 and holds in round 5 would otherwise report 'refuted' forever, which reads
    # as the standing state and is wrong. An explicit `**Current verdict: <word>**` line wins when present;
    # otherwise fall back to the last verdict word in the block, not the first. (#5788 ran five rounds.)
    $p12     = Get-Block -Blocks $blocks -Id 'P12'
    $verdict = $null
    if ($null -ne $p12) {
        foreach ($l in $p12.lines) {
            if ($l.Trim().StartsWith('<!--')) { continue }
            if ($l -match 'Current verdict:\s*\**\s*(holds|weak|refuted|waived)') { $verdict = $Matches[1]; break }
        }

        if ($null -eq $verdict) {
            # A round heading carries that round's verdict; prose inside a round can name any verdict word, so the
            # any-line scan below misread a two-round `weak` plan as `holds` (feature-release-tests-github).
            # A bold round (`**Round 2 (delta) — holds** (prose…)`) carries its verdict inside the bold span; a
            # markdown-heading round (`### Round 1 — <scope> — weak (note)`) after the heading's last dash. Heading
            # rounds used to fall through to the any-line scan, which read `holds` from "census holds" (#5906). The
            # highest-numbered round wins, not the last in file order: rounds are not always appended.
            $rounds   = @($p12.lines | Where-Object { $_ -match '^(\*\*|#{2,6}\s+)Round \d+' })
            $topRound = -1
            foreach ($l in $rounds) {
                $null = $l -match 'Round (\d+)'
                $n    = [int]$Matches[1]
                $v    = $null
                if     ($l -match '^\*\*Round \d+[^*]*[—-]\s*`?(holds|weak|refuted)\b')           { $v = $Matches[1] }
                elseif ($l -match '^#{2,6}\s+Round \d+.*[—-]\s*`?(holds|weak|refuted)\b[^—]*$')   { $v = $Matches[1] }
                if ($null -ne $v -and $n -ge $topRound) { $verdict = $v; $topRound = $n }
            }
            if ($rounds.Count -ge 2) {
                $warnings += 'P12 : several critic rounds but no `**Current verdict: <word>**` line -- add one at the top of P12'
            }
            if ($rounds.Count -ge 1 -and $null -eq $verdict) {
                $warnings += 'P12 : round headings found but none ends in a verdict word -- the verdict below is guessed from prose'
            }
        }

        if ($null -eq $verdict) {
            foreach ($l in $p12.lines) {
                # Skip the block's own fill comment — it names all three verdict
                # words in its instructions and would otherwise read as a verdict.
                if ($l.Trim().StartsWith('<!--')) { continue }
                if ($l -match 'waived-by-user')           { $verdict = 'waived' }
                elseif ($l -match '\b(holds|weak|refuted)\b') { $verdict = $Matches[1] }
            }
        }
    }
    if ($null -eq $verdict -and $planTier -ne 'S') {
        $msg = 'P12 : no critic verdict recorded (holds | weak | refuted | waived-by-user: <reason>)'
        if ($planTier -eq 'L') { $errors += $msg } else { $warnings += $msg }
    }

    # Edit-point commits after the last critic-reviewed commit. A critic objection folded in after the verdict is
    # design no critic attacked, and it gets no A-n of its own (#5959 round 7: all four code findings sat in two
    # such fold-ins). Implementation commits look the same to git, so this lists them for the reader rather than
    # failing; work-plan.md -> P12 says how to record each one.
    if ($null -ne $p12 -and -not [string]::IsNullOrWhiteSpace($RepoRoot)) {
        $reviewedSha = $null
        foreach ($l in $p12.lines) {
            foreach ($m in [regex]::Matches($l, '`([0-9a-f]{7,40})`')) { $reviewedSha = $m.Groups[1].Value }
        }
        $p6ForPaths = Get-Block -Blocks $blocks -Id 'P6'
        $paths = @()
        if ($null -ne $p6ForPaths) {
            $paths = @($p6ForPaths.lines | ForEach-Object { [regex]::Matches($_, '`((?:Source|Tests)/[^`:\s]+)') | ForEach-Object { $_.Groups[1].Value } } | Sort-Object -Unique)
        }
        if ($null -ne $reviewedSha -and $paths.Count -gt 0) {
            $r = Invoke-Process -FilePath 'git' -ArgumentList (@('-C', $RepoRoot, 'log', '--format=%h', "$reviewedSha..$Head", '--') + $paths)
            if ($r.ok -and -not [string]::IsNullOrWhiteSpace($r.stdout)) {
                $after = @($r.stdout -split "`n" | Where-Object { $_.Trim() } | ForEach-Object { $_.Trim() })
                $warnings += "P12 : $($after.Count) edit-point commit(s) after the last critic-reviewed commit $reviewedSha ($($after -join ', ')) -- a fold-in of a critic objection needs a delta round; implementation of an approved A-n needs none"
            }
        }
    }

    $ok = ($errors.Count -eq 0)

    if ($Summary) {
        Write-JsonOutput ([ordered]@{
            ok         = $ok
            action     = 'validate'
            key        = $PlanKey
            tier       = $planTier
            status     = $planStatus
            verdict    = $verdict
            editPoints = $editPoints.Count
            warnings   = $warnings.Count
            errors     = @($errors)
        })
        if (-not $ok) { exit 1 }
        return
    }

    Write-JsonOutput ([ordered]@{
        ok         = $ok
        action     = 'validate'
        key        = $PlanKey
        path       = $planPath
        tier       = $planTier
        status     = $planStatus
        verdict    = $verdict
        editPoints = @($editPoints)
        errors     = @($errors)
        warnings   = @($warnings)
    })
    if (-not $ok) { exit 1 }
}

# Every path-like backticked token in a P6 row, so one E-n may list several files. A row with
# none falls back to its first backticked token, which is what this used to read for every row.
function Get-RowPaths {
    param([string] $Row)

    $tokens = @([regex]::Matches($Row, '`([^`]+)`') | ForEach-Object { $_.Groups[1].Value })
    $paths  = @($tokens | Where-Object { $_ -match '/' -or $_ -match '^[\w.\-]+\.(cs|csproj|fsproj|vbproj|props|targets|json|md|slnx|slnf|txt|yml|yaml|ps1|xml)(:.*)?$' })
    if ($paths.Count -gt 0) { return $paths }
    if ($tokens.Count -gt 0) { return @($tokens[0]) }
    return @()
}

# ---------------------------------------------------------------- gates

function Invoke-Gates {
    param([string] $PlanKey)

    $planPath = Get-PlanPath -PlanKey $PlanKey
    $lines    = Read-PlanLines -Path $planPath
    $blocks   = Split-PlanBlocks -Lines $lines
    $p6       = Get-Block -Blocks $blocks -Id 'P6'

    $paths = @()
    foreach ($row in (Get-BlockRows -Block $p6)) {
        $paths += @(Get-RowPaths -Row $row)
    }

    # Markdown is excluded from the SQL / public-API / TFM heuristics below: a readme.md or an
    # AnalyzerReleases.*.md ships inside a package but cannot move emitted SQL, add public surface or
    # change a build. Only .md is excluded - PublicAPI.*.txt and csproj/props still count, which is why
    # this is not a "code files only" filter. (A readme-only touch of Source/LinqToDB/ was applying
    # G-02/G-03/G-04 on #5779, an analyzer-assembly change that can do none of the three.)
    $buildPaths    = @($paths | Where-Object { $_ -notmatch '\.md$' })

    # Roslyn components - the shipped analyzers, their code fixes, and the internal generator - live under
    # Source/ and outside Internal/, which is exactly the shape $touchesPublic keys on, but they are not the
    # shipped library: they carry no PublicAPI.*.txt and no CompatibilitySuppressions.xml
    # (RunApiAnalyzersDuringBuild is false in Source/Analyzers.Common.props), an analyzer's public members are
    # not API surface at all (agents/code-reviewer.md), and they run at compile time so they cannot emit SQL.
    # Tests/Tests.Analyzers is their test project and belongs to the same set: DB-free, single-TFM, run by a
    # plain `dotnet test` outside the provider matrix, and it emits no baselines.
    $roslynComponent = '^(Source/(LinqToDB\.Analyzers(\.CodeFixes)?|CodeGenerators)|Tests/Tests\.Analyzers)/'
    $productPaths    = @($buildPaths | Where-Object { $_ -notmatch $roslynComponent })

    # $touchesSource deliberately still counts a Roslyn component: those projects target netstandard2.0, so
    # G-05's portable-TFM build applies to them as much as to the library.
    $touchesSource = @($buildPaths   | Where-Object { $_ -match '^Source/' }).Count -gt 0
    $touchesTests  = @($buildPaths   | Where-Object { $_ -match '^Tests/' }).Count -gt 0
    $touchesCore   = @($productPaths | Where-Object { $_ -match 'SqlQuery/|Translation/|IDataProvider|SqlBuilder|SqlOptimizer' }).Count -gt 0
    $touchesPublic = @($productPaths | Where-Object { $_ -match '^Source/' -and $_ -notmatch 'Internal' }).Count -gt 0
    $movesSql      = @($productPaths | Where-Object { $_ -match '^(Source|Tests)/' }).Count -gt 0

    # G-09 keys on tier rather than on paths: a Tier S change is mechanical by definition (a version pin,
    # an [ActiveIssue] enable, a doc-only edit), so an adversarial read of its diff spends a subagent call
    # confirming what the diff already shows. An absent or unparseable tier leaves this at M and the gate
    # applies - the failure direction that costs one call rather than a maintainer's review round.
    $planTier = 'M'
    foreach ($l in $lines) { if ($l -match '\*\*Tier:\*\*\s*([SML])\b') { $planTier = $Matches[1]; break } }
    $needsReview   = $planTier -ne 'S'

    $gates = @()
    $gates += [ordered]@{ id = 'G-01'; name = 'Tests pass via /test, declared proof mode observed'; applies = $true;           why = 'always' }
    $gates += [ordered]@{ id = 'G-02'; name = 'Baselines reviewed, not just regenerated';           applies = $movesSql;        why = 'the change can move emitted SQL' }
    $gates += [ordered]@{ id = 'G-03'; name = 'New public surface accounted for';                   applies = $touchesPublic;   why = 'a non-Internal path is in P6' }
    $gates += [ordered]@{ id = 'G-04'; name = 'API baselines refreshed via /api-baselines';         applies = $touchesPublic;   why = 'a non-Internal path is in P6' }
    $gates += [ordered]@{ id = 'G-05'; name = 'Builds on the portable TFMs';                        applies = $touchesSource;   why = 'Testing config is net10.0-only' }
    $gates += [ordered]@{ id = 'G-06'; name = 'No unrelated reformatting / renames';                applies = $true;            why = 'always' }
    $gates += [ordered]@{ id = 'G-07'; name = 'No playground scratch staged';                       applies = $true;            why = 'always' }
    $gates += [ordered]@{ id = 'G-08'; name = 'Cross-cutting core change surfaced, proven by test'; applies = $touchesCore;     why = 'P6 touches shared engine code' }
    $gates += [ordered]@{ id = 'G-09'; name = 'Diff got an adversarial read before the PR opened';  applies = $needsReview;     why = "plan is Tier $planTier" }

    Write-JsonOutput ([ordered]@{
        ok          = $true
        action      = 'gates'
        key         = $PlanKey
        editPoints  = @($paths)
        applicable  = @($gates | Where-Object { $_.applies } | ForEach-Object { $_.id })
        gates       = @($gates)
        definedIn   = '.claude/docs/definition-of-done.md'
    })
}

# ---------------------------------------------------------------- reconcile

function Invoke-Reconcile {
    param([string] $PlanKey, [string] $RepoRoot)

    $planPath = Get-PlanPath -PlanKey $PlanKey
    $lines    = Read-PlanLines -Path $planPath
    $blocks   = Split-PlanBlocks -Lines $lines
    $p6       = Get-Block -Blocks $blocks -Id 'P6'

    $authorized = @()
    foreach ($row in (Get-BlockRows -Block $p6)) {
        # Strip a :Symbol suffix — the authorization is per file.
        foreach ($p in (Get-RowPaths -Row $row)) { $authorized += ($p -split ':')[0].Trim() }
    }

    $r = Invoke-Process -FilePath 'git' -ArgumentList @('-C', $RepoRoot, 'diff', '--name-only', "$Base...$Head")
    if (-not $r.ok) {
        Exit-WithError -Message "git diff $Base...$Head failed: $($r.stderr.Trim())" `
                       -NextAction 'run git fetch origin master, or pass -Base <ref> / -Head <ref>'
    }
    $changed = @($r.stdout -split "`r?`n" | Where-Object { $_.Trim() -ne '' })

    # Fold in the working tree before the emptiness check: the exit checks run before the first commit, when
    # every change is still uncommitted (#4314).
    # -z: plain porcelain quotes a path containing a space ("Data/Create Scripts/x.sql"), which then matches
    # no P6 path and reads as unplanned (#6161). NUL-separated entries are unquoted; a rename or copy is
    # followed by its source path as a separate entry, which is skipped.
    $w = if ($Head -eq 'HEAD') { Invoke-Process -FilePath 'git' -ArgumentList @('-C', $RepoRoot, 'status', '--porcelain', '-z', '--untracked-files=all') } else { $null }
    if ($w -and $w.ok) {
        $entries = @($w.stdout -split "`0")
        for ($i = 0; $i -lt $entries.Count; $i++) {
            $l = $entries[$i]
            if ($l.Length -lt 4) { continue }
            $p = $l.Substring(3)
            if ($l[0] -eq 'R' -or $l[0] -eq 'C') { $i++ }
            if ($p -ne '' -and $changed -notcontains $p) { $changed += $p }
        }
    }

    # An empty diff against a plan with edit-points is a wrong tree, not a clean branch: the primary clone on
    # master reports zero and reads as "nothing unplanned". (#5983 round 3.)
    if ($changed.Count -eq 0 -and $authorized.Count -gt 0) {
        Exit-WithError -Message "no changes between $Base and $Head in $RepoRoot, but the plan authorizes $($authorized.Count) edit-points" `
                       -NextAction 'pass -RepoRoot <worktree>, or -Head origin/pr/<n> after fetching the PR ref'
    }

    # The corpus is a separate repo; a plan edit is never linq2db work. Match the
    # bare gitlink too — the superproject reports it as `.claude`, not `.claude/`.
    $changed = @($changed | Where-Object { $_ -notmatch '^\.claude(/|$)' })

    $unplanned = @()
    $matched   = @()
    foreach ($f in $changed) {
        $hit = $false
        foreach ($a in $authorized) {
            if ($a -eq '') { continue }
            if ($f -eq $a -or $f.EndsWith($a) -or $a.EndsWith($f) -or $f.StartsWith($a.TrimEnd('*'))) { $hit = $true; break }
        }
        if ($hit) { $matched += $f } else { $unplanned += $f }
    }

    $ok = ($unplanned.Count -eq 0)
    Write-JsonOutput ([ordered]@{
        ok         = $ok
        action     = 'reconcile'
        key        = $PlanKey
        base       = $Base
        considered = $changed.Count
        authorized = @($authorized)
        covered    = @($matched)
        unplanned  = @($unplanned)
        nextAction = if ($ok) { $null } else { 'add an E-n row to P6 for each unplanned file and record the rationale in P11 — an amendment voids that part of the approval' }
    })
    if (-not $ok) { exit 1 }
}

# ---------------------------------------------------------------- gap-report

function Invoke-GapReport {
    param([string] $PlanKey)

    $gapsPath = Join-Path (Join-Path $PlansRoot $PlanKey) 'gaps.md'
    if (-not (Test-Path -LiteralPath $gapsPath)) {
        Exit-WithError -Message "no gap ledger at $gapsPath" `
                       -NextAction 'run review-gap-attributor after a review and write its output there'
    }

    $lines = @([System.IO.File]::ReadAllLines($gapsPath))
    $rows  = @()
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $t = $lines[$i].Trim()
        if ($t -notmatch '^-\s+\*\*([A-Za-z0-9-]+)\*\*(?:\s*\([^)]*\))?\s*[-—]+\s*(.+)$') { continue }
        $id   = $Matches[1]
        $rest = $Matches[2]

        $cls         = $null
        $gate        = $null
        $preventable = $null
        if ($rest -match '^not-a-gap:\s*([a-z0-9-]+)') {
            $cls = 'not-a-gap: ' + $Matches[1]
        }
        elseif ($rest -match '(GAP-\d+)') {
            $cls = $Matches[1]
            # The gate is the segment just before `preventable:`, which may carry a note (`G-02 (never ran)`); a G-nn
            # cited in the reasoning is not it (#6178: rows with gate `—` reported G-01).
            if ($rest -match '\s[-—]+\s+\(?(G-\d+[a-z]*)(?:(?!\s[-—]+\s).)*\s[-—]+\s+preventable:') { $gate = $Matches[1] }
            elseif ($rest -match '\bGate:\s*(G-\d+[a-z]*)')                                    { $gate = $Matches[1] }
            if ($rest -match 'preventable:\s*(yes|partly|no)')       { $preventable = $Matches[1] }

            # The spec keeps the gate and verdict on the row line, but a row that moved them into an indented
            # `- Gate: … — preventable: …` sub-bullet (round 8 of #5959) is read from there rather than reported null.
            if ($null -eq $preventable) {
                for ($j = $i + 1; $j -lt $lines.Count -and $lines[$j] -match '^\s+\S'; $j++) {
                    if ($lines[$j] -notmatch '^\s+-\s+Gate:\s*(.*)$') { continue }
                    $tail = $Matches[1]
                    $gate = if ($tail -match '^(G-\d+)') { $Matches[1] } else { $null }
                    if ($tail -match 'preventable:\s*(yes|partly|no)') { $preventable = $Matches[1] }
                    break
                }
            }
        }
        else { continue }

        $rows += [ordered]@{ id = $id; class = $cls; gate = $gate; preventable = $preventable }
    }

    if ($rows.Count -eq 0) {
        Exit-WithError -Message "no parseable attribution rows in $gapsPath" `
                       -NextAction 'each row must read: - **<ID>** - <GAP-nn> - <detail> - <G-nn | -> - preventable: yes|partly|no'
    }

    $byClass = @{}
    foreach ($r in $rows) {
        if (-not $byClass.ContainsKey($r.class)) { $byClass[$r.class] = 0 }
        $byClass[$r.class] = $byClass[$r.class] + 1
    }
    $counts = @($byClass.GetEnumerator() | Sort-Object -Property Value -Descending |
        ForEach-Object { [ordered]@{ class = $_.Key; count = $_.Value } })

    # The dominant class ignores the not-a-gap outcomes: those are findings about
    # the adjudication, not about the design pass. GAP-10 is excluded from the
    # ranking unless it *strictly* outnumbers every actionable class - it is the
    # floor, so on a tie the class someone can actually act on wins. Ties among
    # actionable classes break by id so the output is deterministic.
    $unpreventable = @($rows | Where-Object { $_.class -eq 'GAP-10' }).Count
    $actionable    = @($counts | Where-Object { $_.class -like 'GAP-*' -and $_.class -ne 'GAP-10' } |
        Sort-Object -Property @{ Expression = 'count'; Descending = $true }, @{ Expression = 'class'; Descending = $false })

    $dominant = $null
    if ($actionable.Count -gt 0) { $dominant = $actionable[0].class }
    if ($unpreventable -gt 0 -and ($actionable.Count -eq 0 -or $unpreventable -gt $actionable[0].count)) {
        $dominant = 'GAP-10'
    }

    $ratio = if ($rows.Count -gt 0) { [math]::Round($unpreventable / $rows.Count, 2) } else { 0 }

    $signal = $null
    if ($ratio -ge 0.6) {
        $signal = 'GAP-10 dominates - the design pass is not earning its cost on this shape of work. Cut the ceremony rather than defending it.'
    }

    Write-JsonOutput ([ordered]@{
        ok                 = $true
        action             = 'gap-report'
        key                = $PlanKey
        path               = $gapsPath
        findings           = $rows.Count
        dominantClass      = $dominant
        unpreventableRatio = $ratio
        calibrationSignal  = $signal
        counts             = @($counts)
        rows               = @($rows)
    })
}

# ---------------------------------------------------------------- section

# A Tier L plan runs to hundreds of KB, in lines of several KB that Read truncates and Grep returns whole (#5943: two
# agents in one review fell back to ad-hoc substring extraction, one probing for a plan-section script that did not exist).
function Invoke-Section {
    param([string] $PlanKey)

    $path  = Get-PlanPath -PlanKey $PlanKey
    $lines = Read-PlanLines -Path $path

    $index = @()
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^##\s+(P\d+)\b(.*)$') {
            if ($index.Count -gt 0) { $index[-1].endLine = $i }
            $index += [ordered]@{ id = $Matches[1]; heading = $Matches[2].Trim(); startLine = $i + 1; endLine = $lines.Count; chars = 0 }
        }
    }
    foreach ($b in $index) {
        for ($n = $b.startLine; $n -le $b.endLine; $n++) { $b.chars += $lines[$n - 1].Length }
    }

    $wanted = @()
    if (-not [string]::IsNullOrWhiteSpace($Section)) {
        $wanted = @($Section.Split(',', [StringSplitOptions]::RemoveEmptyEntries) | ForEach-Object { $_.Trim().ToUpperInvariant() })
        $known  = @($index | ForEach-Object { $_.id })
        $bad    = @($wanted | Where-Object { $known -notcontains $_ })
        if ($bad.Count -gt 0) {
            Exit-WithError -Message "no block $($bad -join ', ') in $path" -NextAction "pass -Section with ids from: $($known -join ', ')"
        }
    }
    $blocks = if ($wanted.Count -gt 0) { @($index | Where-Object { $wanted -contains $_.id }) } else { @($index) }

    $result = [ordered]@{ ok = $true; action = 'section'; key = $PlanKey; path = $path; sections = @($blocks) }

    if ($wanted.Count -eq 0 -and [string]::IsNullOrWhiteSpace($Match)) {
        Write-JsonOutput $result
        return
    }

    $numbers = if ($wanted.Count -gt 0) {
        @($blocks | ForEach-Object { $_.startLine..$_.endLine })
    } else {
        @(1..$lines.Count)
    }

    if (-not [string]::IsNullOrWhiteSpace($Match)) {
        try { $rx = [regex]::new($Match, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase) }
        catch { Exit-WithError -Message "-Match is not a valid regex: $($_.Exception.Message)" -NextAction 'escape the pattern, or pass a plain word' }

        $hits = @()
        foreach ($n in $numbers) {
            $text = $lines[$n - 1]
            $id   = 'header'
            foreach ($b in $index) { if ($n -ge $b.startLine -and $n -le $b.endLine) { $id = $b.id } }
            # Hits whose windows overlap on one line merge into one snippet.
            $windows = @()
            foreach ($m in $rx.Matches($text)) {
                $s = [Math]::Max(0, $m.Index - $Context)
                $e = [Math]::Min($text.Length, $m.Index + $m.Length + $Context)
                if ($windows.Count -gt 0 -and $s -le $windows[-1][1]) { $windows[-1][1] = [Math]::Max($windows[-1][1], $e) }
                else { $windows += , @($s, $e) }
            }
            foreach ($w in $windows) {
                $pre  = if ($w[0] -gt 0) { '...' } else { '' }
                $post = if ($w[1] -lt $text.Length) { '...' } else { '' }
                $hits += "L$n [$id]: $pre$($text.Substring($w[0], $w[1] - $w[0]))$post"
            }
        }
        $result.matchCount = $hits.Count
        $result.matches    = @($hits)
        Write-JsonOutput $result
        return
    }

    $out = @()
    foreach ($n in $numbers) {
        $text = $lines[$n - 1]
        if ($MaxLineChars -le 0 -or $text.Length -le $MaxLineChars) { $out += "L${n}: $text"; continue }
        for ($o = 0; $o -lt $text.Length; $o += $MaxLineChars) {
            $tag   = if ($o -eq 0) { "L${n}" } else { "L${n}+" }
            $out  += "${tag}: $($text.Substring($o, [Math]::Min($MaxLineChars, $text.Length - $o)))"
        }
    }
    $result.lines = @($out)
    Write-JsonOutput $result
}

# ---------------------------------------------------------------- dispatch

$repoRoot = if ([string]::IsNullOrWhiteSpace($RepoRoot)) { Get-RepoRoot } else { (Resolve-Path $RepoRoot).Path }
$planKey  = Resolve-Key -Explicit $Key -RepoRoot $repoRoot

switch ($Action) {
    'init'      { Invoke-Init      -PlanKey $planKey -RepoRoot $repoRoot }
    'validate'  { Invoke-Validate  -PlanKey $planKey -RepoRoot $repoRoot }
    'gates'     { Invoke-Gates     -PlanKey $planKey }
    'reconcile'  { Invoke-Reconcile  -PlanKey $planKey -RepoRoot $repoRoot }
    'gap-report' { Invoke-GapReport  -PlanKey $planKey }
    'section'    { Invoke-Section    -PlanKey $planKey }
}
