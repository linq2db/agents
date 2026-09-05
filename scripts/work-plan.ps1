#!/usr/bin/env pwsh
# Work-plan scaffolding and validation.
#
#   -Action init       scaffold .claude/plans/<key>/plan.md from the template
#   -Action validate   schema completeness; ok=false with per-block errors
#   -Action gates      derive the applicable definition-of-done gate subset from P6
#   -Action reconcile  report changed files that no P6 edit-point authorizes
#   -Action gap-report render .claude/plans/<key>/gaps.md as counts + dominant class
#
# Schema and block semantics: .claude/docs/work-plan.md
#
# The plan lives in the corpus submodule, so every path here resolves relative to
# this script, never to the caller's working directory — a worktree has its own
# .claude/ checkout and the plan must land in the one the caller is actually using.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('init', 'validate', 'gates', 'reconcile', 'gap-report')]
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

    [switch] $Force
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
    param([string] $PlanKey)

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

    # P2 rows are SC-n and should name a TO-n.
    $p2 = Get-Block -Blocks $blocks -Id 'P2'
    foreach ($row in (Get-BlockRows -Block $p2)) {
        if ($row -notmatch 'SC-\d+') { $errors += "P2 : row does not carry an SC-n id -- $row" }
        elseif ($row -notmatch 'TO-\d+') { $warnings += "P2 : SC row names no TO-n obligation -- $row" }
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
    foreach ($row in (Get-BlockRows -Block $p8)) {
        if ($row -notmatch '^-\s*[*_]{0,2}TO-\d+') { continue }
        if ($row -notmatch 'proof:\s*[*_]{0,2}\s*(red.{0,3}green|control|characterization)') {
            $errors += "P8 : row declares no proof mode (red-green | control | characterization) -- $row"
        }
    }

    # P9 gate results.
    $p9 = Get-Block -Blocks $blocks -Id 'P9'
    foreach ($row in (Get-BlockRows -Block $p9)) {
        if ($row -notmatch 'G-\d+') { continue }
        if ($row -match '\(pending\)') { $warnings += "P9 : gate still pending -- $row"; continue }
        if ($row -notmatch '(pass|fail|n/a|skipped|blocked)') {
            $errors += "P9 : gate carries no result -- $row"
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

    # P10 entries need a reason.
    $p10 = Get-Block -Blocks $blocks -Id 'P10'
    foreach ($row in (Get-BlockRows -Block $p10)) {
        if ($row -notmatch '^-\s') { continue }
        if ($row.Length -lt 40 -and $row -notmatch '—|--|because|measured') {
            $warnings += "P10 : entry looks reasonless, and a reasonless entry suppresses nothing -- $row"
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

    $ok = ($errors.Count -eq 0)
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

# ---------------------------------------------------------------- gates

function Invoke-Gates {
    param([string] $PlanKey)

    $planPath = Get-PlanPath -PlanKey $PlanKey
    $lines    = Read-PlanLines -Path $planPath
    $blocks   = Split-PlanBlocks -Lines $lines
    $p6       = Get-Block -Blocks $blocks -Id 'P6'

    $paths = @()
    foreach ($row in (Get-BlockRows -Block $p6)) {
        if ($row -match '`([^`]+)`') { $paths += $Matches[1] }
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

    $gates = @()
    $gates += [ordered]@{ id = 'G-01'; name = 'Tests pass via /test, declared proof mode observed'; applies = $true;           why = 'always' }
    $gates += [ordered]@{ id = 'G-02'; name = 'Baselines reviewed, not just regenerated';           applies = $movesSql;        why = 'the change can move emitted SQL' }
    $gates += [ordered]@{ id = 'G-03'; name = 'New public surface accounted for';                   applies = $touchesPublic;   why = 'a non-Internal path is in P6' }
    $gates += [ordered]@{ id = 'G-04'; name = 'API baselines refreshed via /api-baselines';         applies = $touchesPublic;   why = 'a non-Internal path is in P6' }
    $gates += [ordered]@{ id = 'G-05'; name = 'Builds on the portable TFMs';                        applies = $touchesSource;   why = 'Testing config is net10.0-only' }
    $gates += [ordered]@{ id = 'G-06'; name = 'No unrelated reformatting / renames';                applies = $true;            why = 'always' }
    $gates += [ordered]@{ id = 'G-07'; name = 'No playground scratch staged';                       applies = $true;            why = 'always' }
    $gates += [ordered]@{ id = 'G-08'; name = 'Cross-cutting core change surfaced, proven by test'; applies = $touchesCore;     why = 'P6 touches shared engine code' }

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
        if ($row -match '`([^`]+)`') {
            # Strip a :Symbol suffix — the authorization is per file.
            $p = $Matches[1]
            $p = ($p -split ':')[0]
            $authorized += $p.Trim()
        }
    }

    $r = Invoke-Process -FilePath 'git' -ArgumentList @('-C', $RepoRoot, 'diff', '--name-only', "$Base...HEAD")
    if (-not $r.ok) {
        Exit-WithError -Message "git diff against $Base failed: $($r.stderr.Trim())" `
                       -NextAction 'run git fetch origin master, or pass -Base <ref>'
    }
    $changed = @($r.stdout -split "`r?`n" | Where-Object { $_.Trim() -ne '' })

    $w = Invoke-Process -FilePath 'git' -ArgumentList @('-C', $RepoRoot, 'status', '--porcelain')
    if ($w.ok) {
        foreach ($l in @($w.stdout -split "`r?`n")) {
            if ($l.Trim() -eq '') { continue }
            $p = $l.Substring(3).Trim()
            if ($p -ne '' -and $changed -notcontains $p) { $changed += $p }
        }
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
    foreach ($l in $lines) {
        $t = $l.Trim()
        if ($t -notmatch '^-\s+\*\*([A-Za-z0-9-]+)\*\*\s*[-—]+\s*(.+)$') { continue }
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
            if ($rest -match '(G-\d+)')                              { $gate        = $Matches[1] }
            if ($rest -match 'preventable:\s*(yes|partly|no)')       { $preventable = $Matches[1] }
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

# ---------------------------------------------------------------- dispatch

$repoRoot = if ([string]::IsNullOrWhiteSpace($RepoRoot)) { Get-RepoRoot } else { (Resolve-Path $RepoRoot).Path }
$planKey  = Resolve-Key -Explicit $Key -RepoRoot $repoRoot

switch ($Action) {
    'init'      { Invoke-Init      -PlanKey $planKey -RepoRoot $repoRoot }
    'validate'  { Invoke-Validate  -PlanKey $planKey }
    'gates'     { Invoke-Gates     -PlanKey $planKey }
    'reconcile'  { Invoke-Reconcile  -PlanKey $planKey -RepoRoot $repoRoot }
    'gap-report' { Invoke-GapReport  -PlanKey $planKey }
}
