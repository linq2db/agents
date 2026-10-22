#!/usr/bin/env pwsh
<#
Whole-diff structural scan of a PR's baselines branch.

Why this wrapper exists
-----------------------
`/review-pr` step 8 rule 4 requires the *parent skill* (not the
`baselines-reviewer` subagent) to ground the baselines section in its own
measurements: headline A/M/D counts from the three-dot range, a net-line
split so cosmetic churn is separated from real SQL, a per-file delta for the
structural signal the PR's mechanism would move, and a provider histogram
bounding the blast radius. The subagent's grouped summary is sample-based and
has repeatedly under-reported these.

Hand-rolling the scan means several `git diff` calls plus throwaway analysis
scripts on every review. This does it in one call.

The rename map is the part that generalises: it normalises every parameter
identifier on both sides of each changed line-pair and byte-compares the
result, which turns "this change is name-only" from an author's claim into a
measurement — `mismatches` is 0 exactly when nothing but identifiers moved.

Invocation
----------
    pwsh -NoProfile -File .claude/scripts/baselines-pr-scan.ps1 -Pr 5733

Parameters
----------
  -Pr <int>            required — PR number, resolves branch `baselines/pr_<n>`
  -Clone <path>        default `../linq2db.baselines`, else the primary clone's
                       sibling (so it also resolves from a worktree)
  -BaseRef <ref>       default `origin/master`
  -Signal <regex>      default `^\s*DECLARE\s` — the structural signal counted
                       per file on the added and removed sides. Override for a
                       mechanism whose fingerprint is not a parameter DECLARE
                       (e.g. `^\s*ORDER BY` , `\bas \[c\d+\]`).
  -IdentifierPrefixes  default `@:?$` — characters that introduce a parameter
                       identifier across providers. Used by the normaliser.
  -NoFetch             skip the `git fetch` of the baselines branch.
  -MaxRenameTests <int> default 40 — cap on test names listed per rename.
  -MaxAddedTests <int>  default 60 — cap on `addedTests.tests` entries listed.
  -OutFile <path>      write the JSON there and print one compact line
                       ({ ok, outFile, bytes, status, counts, inherited }), so
                       the scan runs once and the file is queried after.

Output (stdout, single JSON object)
-----------------------------------
  {
    "status": "ok" | "branch_missing",
    "branch": "baselines/pr_5733",
    "branchTip":  { "sha": "...", "dateIso": "...", "subject": "..." },
    "counts": { "added": 0, "modified": 1335, "deleted": 0 },
    "lines":  { "added": 6784, "removed": 6784,
                "netZeroFiles": 1335, "netPositiveFiles": 0, "netNegativeFiles": 0 },
    "netPositive": [ { "file": "...", "add": 9, "del": 3 }, ... ],
    "netNegative": [ ... ],
    "permutation": { "pureFiles": 158, "impureFiles": 9,
                     "impure": [ { "file": "...", "onlyAdded": [ "..." ],
                                   "onlyRemoved": [ "..." ] } ] },
    "signal": { "pattern": "^\\s*DECLARE\\s", "added": 2267, "removed": 2267,
                "filesWithDelta": [ { "file": "...", "added": 4, "removed": 2 } ] },
    "casts":  { "prefix":  { "added": 547, "removed": 494 },
                "postfix": { "added": 66,  "removed": 309 },
                "perFileLosses": [ { "file": "...", "prefixNet": 0, "postfixNet": -3 } ] },
    "providers": [ { "provider": "SQLite.Classic", "files": 41 }, ... ],
    "inherited": { "files": 175, "samples": [ "..." ] },
    "addedTests": { "universe": 68,
                    "tests": [ { "test": "Tests.Linq.X.Y", "providers": 63,
                                 "missing": [ "ClickHouse.Driver", "..." ] } ] },
    "decimalFacets": { "checked": 4210, "violationCount": 0,
                       "violations": [ { "file": "...", "facet": "Decimal(32, 3)",
                                         "reason": "precision 32 > DB2 max 31" } ] },
    "statementParity": { "groups": 610, "deviatingCount": 2,
                         "deviating": [ { "test": "Tests.Linq.X.Y(False)", "mode": 3, "providers": 41,
                                          "deviating": [ { "provider": "DB2", "count": 4 } ] } ] },
    "renames": {
      "mismatches": 0,
      "mismatchSamples": [ { "file": "...", "old": "...", "new": "..." } ],
      "map": [ { "from": "ValueStr", "to": "param_1", "hits": 3150,
                 "providers": 40, "tests": [ "..." ] } ]
    }
  }

`aliases` ({ aliasOnlyFiles, otherFiles, otherSamples }) answers "is this drift only column
aliases?", which `renames` cannot: an alias has no identifier prefix, so every alias rename is a
mismatch there. A modified file is alias-only when both sides of its change-block read the same
with identifiers collapsed and `as <alias>` dropped; `otherFiles` = 0 means the delta renames
columns and changes nothing else.

`renames.mismatches` counts changed line-pairs that still differ after
identifier normalisation — i.e. real SQL changes. A non-zero value means the
delta is NOT name-only, and `mismatchSamples` shows the first few.

`permutation` answers the question a reorder-dominated delta actually turns on:
`pureFiles` is the count whose two sides are the same multiset of lines (a pure
reorder — no column added, dropped, retyped or rewritten), and `impure[]` lists
the rest with the lines unique to each side. Note a pure reorder scores as
thousands of `renames.mismatches`, so the two fields answer different questions
and a high mismatch count is not evidence of a content change on its own.

`inherited` counts delta paths that are byte-identical to current `$BaseRef`.
These are paths in the three-dot name-status but absent from a two-dot
name-only diff. Their content came from another PR's baselines merged into
baselines master after this branch was cut, so they are not this PR's work.
Subtract them before attributing the delta. A zero does NOT rule out lag on
the PR-branch side (see review-pr step 8).

`addedTests` covers every test that has at least one *added* file; the test
name is the file name up to the first `(`. For each test it lists the
providers that have no baseline for it anywhere in the branch tree, so a
pre-existing baseline counts as coverage. The reference set is the
`universe`: every provider that has at least one added file. Most of the time
a missing provider means the test threw or was excluded there, so compare it
with the test's `[ThrowsFor*]` / `[DataSources]` attributes. A provider whose
whole leg failed adds no files at all, so it is absent from the universe as
well. Cross-check the universe against the CI matrix. Only tests missing at
least one provider are listed.

`decimalFacets` checks every decimal type written on an added line — `Decimal(p, s)`,
DB2's `Decimal(value, p, s)`, YDB's `Decimal('value', p, s)`, ClickHouse's
`toDecimalNN(value, s)` — against the provider's maximum precision (from its folder
name) and for scale above precision. Zero violations bounds a "no facet exceeds a
provider's limit" claim over the whole delta, not a sample.

`statementParity` groups the added `.sql` files of one test case across providers
(the file name without its provider argument) and counts the commands each logs: the
blank-line-separated chunks holding a statement keyword at column 0. A provider off the
case's most common count took another path (a split batch, an emulation, an extra round
trip) or stopped part-way: read it.
`deviating` lists at most 25 cases; `deviatingCount` is the total.

Note: comparisons are Ordinal throughout. A case-only rename (`@Usage` ->
`@usage`) is a real rename and PowerShell's default case-insensitive `-ne`
would silently drop it — see `.claude/docs/script-authoring.md` → Gotchas.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)][int] $Pr,
    [string]   $Clone,
    [string]   $BaseRef            = 'origin/master',
    [string]   $Signal             = '^\s*DECLARE\s',
    [string]   $IdentifierPrefixes = '@:?$',
    [switch]   $NoFetch,
    [int]      $MaxRenameTests     = 40,
    [int]      $MaxImpureFiles     = 25,
    [int]      $MaxAddedTests      = 60,
    [string]   $OutFile
)

. "$PSScriptRoot/_shared.ps1"
$global:ScriptBaseName = 'baselines-pr-scan'

$Clone = Resolve-BaselinesClone -Path $Clone
if (-not (Test-Path -LiteralPath $Clone)) {
    Exit-WithError -Message "baselines clone not found at '$Clone'" `
        -NextAction "clone https://github.com/linq2db/linq2db.baselines.git to '$Clone', or pass -Clone <path>"
}

$branch    = "baselines/pr_$Pr"
$remoteRef = "origin/$branch"

function Git {
    param([string[]]$GitArgs, [switch]$AllowFail)
    # Invoke-Process returns { ok, stdout, stderr, code, error } — lowercase.
    $r = Invoke-Process -FilePath 'git' -ArgumentList (@('-C', $Clone) + $GitArgs)
    if ($r.code -ne 0 -and -not $AllowFail) {
        Exit-WithError -Message "git $($GitArgs -join ' ') failed: $($r.stderr.Trim())"
    }
    return $r
}

if (-not $NoFetch) { [void](Git -GitArgs @('fetch', 'origin', $branch) -AllowFail) }

$verify = Git -GitArgs @('rev-parse', '--verify', '--quiet', $remoteRef) -AllowFail
if ($verify.code -ne 0 -or -not $verify.stdout.Trim()) {
    Write-JsonOutput -InputObject ([ordered]@{ status = 'branch_missing'; branch = $branch }) -OutFile $OutFile -Summary ([ordered]@{ status = 'branch_missing' })
    exit 0
}

$tip = (Git -GitArgs @('log', '-1', '--format=%H%x1f%cI%x1f%s', $remoteRef)).stdout.Trim() -split "`u{001f}"
$range = "$BaseRef...$remoteRef"

# ---- name-status -----------------------------------------------------------
$counts     = @{ added = 0; modified = 0; deleted = 0 }
$providers  = [System.Collections.Generic.Dictionary[string, int]]::new([System.StringComparer]::Ordinal)
$deltaPaths = [System.Collections.Generic.List[string]]::new()
# test name -> providers that have an added baseline for it
$addedByTest   = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
$addedUniverse = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
$addedPaths    = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)

foreach ($line in ((Git -GitArgs @('diff', '--name-status', $range)).stdout -split "`n")) {
    if (-not $line.Trim()) { continue }
    $parts = $line.TrimEnd("`r") -split "`t"
    $path  = $parts[-1]
    $p     = ($path -split '/')[0]
    switch ($parts[0].Substring(0, 1)) {
        'A' {
            $counts.added++
            $test = (($path -split '/')[-1] -replace '\(.*$', '')
            if (-not $addedByTest.ContainsKey($test)) {
                $addedByTest[$test] = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
            }
            [void]$addedByTest[$test].Add($p)
            [void]$addedUniverse.Add($p)
            [void]$addedPaths.Add($path)
        }
        'D' { $counts.deleted++ }
        'M' { $counts.modified++ }
    }
    $deltaPaths.Add($path)
    if (-not $providers.ContainsKey($p)) { $providers[$p] = 0 }
    $providers[$p]++
}

# ---- inherited: delta paths byte-identical to current $BaseRef ---------------
# A two-dot diff is used here only as a filter over paths, never as the diff to read.
$twoDot = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
foreach ($l in ((Git -GitArgs @('diff', '--name-only', $BaseRef, $remoteRef)).stdout -split "`n")) {
    if ($l.Trim()) { [void]$twoDot.Add($l.TrimEnd("`r")) }
}
$inherited = @($deltaPaths | Where-Object { -not $twoDot.Contains($_) })

# A test can gain a baseline on only some providers because it already had one elsewhere, e.g. a
# provider exclusion was just dropped. Count every baseline the test has anywhere in the branch tree,
# not only the added ones, so that case doesn't read as dozens of missing providers.
if ($addedByTest.Count -gt 0) {
    foreach ($l in ((Git -GitArgs @('ls-tree', '-r', '--name-only', $remoteRef)).stdout -split "`n")) {
        if (-not $l.Trim()) { continue }
        $l    = $l.TrimEnd("`r")
        $test = (($l -split '/')[-1] -replace '\(.*$', '')
        if ($addedByTest.ContainsKey($test)) { [void]$addedByTest[$test].Add(($l -split '/')[0]) }
    }
}

$addedTests = @()
foreach ($t in ($addedByTest.Keys | Sort-Object)) {
    $have    = $addedByTest[$t]
    $missing = @($addedUniverse | Where-Object { -not $have.Contains($_) } | Sort-Object)
    if ($missing.Count -eq 0) { continue }
    $addedTests += [pscustomobject]@{ test = $t; providers = $have.Count; missing = $missing }
}

# ---- per-file line / signal / rename analysis over the -U0 diff ------------
$diff = (Git -GitArgs @('diff', '-U0', $range)).stdout

$signalRe = [regex]::new($Signal)
$normRe   = [regex]::new("(?<=[$([regex]::Escape($IdentifierPrefixes))])[A-Za-z_][A-Za-z0-9_]*")

# Casts are spelled two ways, and a sweep that knows only one under-reports without saying so:
# most providers write CAST(x AS T), while PostgreSQL and DuckDB write x::T. Counted apart so a
# "no cast lost" claim is checked against the dialect the provider actually emits - matching only
# CAST( on a PostgreSQL-heavy diff returns a confident, specific, wrong answer.
$castPrefixRe  = [regex]::new('CAST\s*\(', 'IgnoreCase')
$castPostfixRe = [regex]::new('::\w+')

$stats           = [System.Collections.Generic.List[object]]::new()
$renameMap       = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
$mismatchCount   = 0
$mismatchSamples = [System.Collections.Generic.List[object]]::new()
$impure          = [System.Collections.Generic.List[object]]::new()
$pureCount       = 0

# A column reorder and a column rewrite are indistinguishable in every count above: both give a
# net-zero line delta and a symmetric change-block, and `renames.mismatches` reports a reorder as
# thousands of mismatches because the normalised line pairs genuinely differ. Comparing the two
# sides as *multisets* is the only check that answers "did any line's content actually change",
# which is the question a reorder-dominated delta turns on.
$trailingCommaRe = [regex]::new(',\s*$')

# Decimal facets on added lines, checked against what each provider accepts. A reviewer comparing 2000+ added files
# across providers by hand wrote ~30 throwaway scripts for this and the statement count below (#5959 round 8).
# Forms: `Decimal(p, s)` / `NUMERIC(p,s)` / `x::decimal(p, s)`, DB2 `Decimal(value, p, s)`, YDB `Decimal('value', p, s)`.
$decimalFacetRe = [regex]::new("(?i)\b(?:decimal|numeric|number|dec)\s*\(\s*(?:(?:'[^']*'|-?[\d.]+)\s*,\s*)?(\d+)\s*,\s*(\d+)\s*\)")
# ClickHouse names the family, so only the scale is written: `toDecimal64('value', s)`.
$chDecimalRe    = [regex]::new("toDecimal(32|64|128|256)\s*\(\s*(?:'[^']*'|[^,()]+)\s*,\s*(\d+)\s*\)")
$chFamilyMax    = @{ '32' = 9; '64' = 18; '128' = 38; '256' = 76 }

# Largest decimal precision a provider accepts; 0 = not checked (precision < scale is still flagged).
function Get-DecimalMax([string]$Provider) {
    switch -Regex ($Provider) {
        '^DB2'                              { return 31 }
        '^Informix'                         { return 32 }
        '^YDB'                              { return 35 }
        '^Firebird\.(2\.5|3)$'              { return 18 }
        '^Firebird'                         { return 38 }
        '^(MySql|MySqlConnector|MariaDB)'   { return 65 }
        '^PostgreSQL'                       { return 1000 }
        '^Access'                           { return 28 }
        '^(SqlServer|Sybase|Oracle|SapHana|DuckDB|SqlCe)' { return 38 }
        default                             { return 0 }
    }
}

# A baseline separates the commands it logs with blank lines. A chunk holding a statement keyword at column 0 is one
# command: `WITH … SELECT` is one chunk, and YDB's `$CTE_1 = SELECT …;` prologue chunk holds none, so neither double-counts.
$statementRe     = [regex]::new('^(?:SELECT|INSERT|UPDATE|DELETE|MERGE|WITH|CREATE|DROP|TRUNCATE|UPSERT|REPLACE|ALTER)\b')
$facetChecked    = 0
$facetViolations = [System.Collections.Generic.List[object]]::new()
$statementCounts = [System.Collections.Generic.List[object]]::new()

# Column aliases have no identifier prefix, so `renames` scores every alias rename as a mismatch (#6091: 6421 of them,
# all name-only). A file is alias-only when its two sides read the same once every identifier is collapsed to one token
# and every `as <alias>` is dropped. Compared over the whole change-block, not per line, so an alias that re-wraps a line
# still counts. Kept verbatim, because they are not names a query chose: an all-uppercase keyword, a function name (a word
# before `(`), the type after an uppercase `AS` (CAST), `DECLARE` / `SET` parameter lines and `--` comments - collapsing
# those hid a parameter retype (#5640: `NVarChar` -> `Text`). linq2db writes an alias with a lowercase `as`.
$aliasClauseRe   = [regex]::new('\bas\s+(\[[^\]]*\]|"[^"]*"|`[^`]*`|[A-Za-z_][A-Za-z0-9_]*)')
$aliasTokenRe    = [regex]::new('\[[^\]]*\]|"[^"]*"|`[^`]*`|''[^'']*''[A-Za-z]?|[A-Za-z_][A-Za-z0-9_]*|[0-9][0-9.]*|\S')
$aliasVerbatimRe = [regex]::new('^\s*(DECLARE|SET)\b')
$aliasOnlyCount  = 0
$aliasOther      = [System.Collections.Generic.List[object]]::new()

function Get-AliasShape([System.Collections.Generic.List[string]]$Lines) {
    $tokens = [System.Collections.Generic.List[string]]::new()
    foreach ($line in $Lines) {
        if ($script:aliasVerbatimRe.IsMatch($line)) { $tokens.Add($line.Trim()); continue }

        $code = $line; $comment = $null
        $at = $line.IndexOf('--')
        if ($at -ge 0) { $code = $line.Substring(0, $at); $comment = $line.Substring($at).Trim() }

        $code    = $script:aliasClauseRe.Replace($code, '')
        $found = $script:aliasTokenRe.Matches($code)
        for ($i = 0; $i -lt $found.Count; $i++) {
            $t    = $found[$i].Value
            $next = if ($i + 1 -lt $found.Count) { $found[$i + 1].Value } else { '' }
            $prev = if ($i -gt 0) { $found[$i - 1].Value } else { '' }
            if ($t -eq ',') { continue }
            if ($t -cmatch '^[A-Z][A-Z_]+$' -or $next -eq '(' -or $prev -ceq 'AS') { $tokens.Add($t) }
            elseif ($t -match '^(\[|"|`|[A-Za-z_])') { $tokens.Add('X') }
            else { $tokens.Add($t) }
        }
        if ($comment) { $tokens.Add($comment) }
    }
    return ($tokens -join ' ')
}

$curFile = $null
$add = [System.Collections.Generic.List[string]]::new()
$del = [System.Collections.Generic.List[string]]::new()

function Flush-File {
    param([string]$File, $Added, $Removed)
    if (-not $File) { return }

    $fileProvider = ($File -split '/')[0]
    $maxPrecision = Get-DecimalMax $fileProvider
    foreach ($l in $Added) {
        foreach ($m in $script:decimalFacetRe.Matches($l)) {
            $script:facetChecked++
            $fp = [int]$m.Groups[1].Value; $fs = [int]$m.Groups[2].Value
            $why = if ($maxPrecision -gt 0 -and $fp -gt $maxPrecision) { "precision $fp > $fileProvider max $maxPrecision" }
                   elseif ($fs -gt $fp)                                { "scale $fs > precision $fp" }
            if ($why) { $script:facetViolations.Add([pscustomobject]@{ file = $File; facet = $m.Value; reason = $why }) }
        }
        foreach ($m in $script:chDecimalRe.Matches($l)) {
            $script:facetChecked++
            $cap = $script:chFamilyMax[$m.Groups[1].Value]
            if ([int]$m.Groups[2].Value -gt $cap) {
                $script:facetViolations.Add([pscustomobject]@{ file = $File; facet = $m.Value; reason = "scale $($m.Groups[2].Value) > Decimal$($m.Groups[1].Value) max $cap" })
            }
        }
    }

    if ($script:addedPaths.Contains($File) -and $File.EndsWith('.sql')) {
        $fileName = ($File -split '/')[-1] -replace '\.sql$', ''
        # The test key drops the provider, the first argument in the file name, so every provider's file of one case groups.
        $key = if ($fileName -match '^([^(]+)\(([^,)]*)(.*)\)$') { "$($Matches[1])($($Matches[3].TrimStart(',')))" } else { $fileName }
        $count = 0; $chunkHasStatement = $false
        foreach ($l in @($Added) + '') {
            if (-not $l.Trim()) { if ($chunkHasStatement) { $count++ }; $chunkHasStatement = $false }
            elseif ($script:statementRe.IsMatch($l)) { $chunkHasStatement = $true }
        }
        $script:statementCounts.Add([pscustomobject]@{ key = $key; provider = $fileProvider; count = $count })
    }

    $sigAdd = 0; $sigDel = 0
    foreach ($l in $Added)   { if ($signalRe.IsMatch($l)) { $sigAdd++ } }
    foreach ($l in $Removed) { if ($signalRe.IsMatch($l)) { $sigDel++ } }

    $preAdd = 0; $preDel = 0; $postAdd = 0; $postDel = 0
    foreach ($l in $Added)   { $preAdd += $castPrefixRe.Matches($l).Count; $postAdd += $castPostfixRe.Matches($l).Count }
    foreach ($l in $Removed) { $preDel += $castPrefixRe.Matches($l).Count; $postDel += $castPostfixRe.Matches($l).Count }

    # Trailing commas are stripped before comparing: a column moving to or from the last position
    # in a SELECT list gains or loses one without its content changing.
    $normA  = @($Added   | ForEach-Object { $script:trailingCommaRe.Replace($_.Trim(), '') } | Sort-Object)
    $normD  = @($Removed | ForEach-Object { $script:trailingCommaRe.Replace($_.Trim(), '') } | Sort-Object)
    $isPerm = [string]::Equals(($normA -join "`n"), ($normD -join "`n"), [System.StringComparison]::Ordinal)

    if ($isPerm) {
        $script:pureCount++
    }
    elseif ($script:impure.Count -lt $script:MaxImpureFiles) {
        $script:impure.Add([pscustomobject]@{
            file        = $File
            onlyAdded   = @($normA | Where-Object { $normD -notcontains $_ })
            onlyRemoved = @($normD | Where-Object { $normA -notcontains $_ })
        })
    }

    if ($Added.Count -gt 0 -and $Removed.Count -gt 0) {
        $shapeA = Get-AliasShape $Added
        $shapeD = Get-AliasShape $Removed
        if ([string]::Equals($shapeA, $shapeD, [System.StringComparison]::Ordinal)) { $script:aliasOnlyCount++ }
        else { $script:aliasOther.Add($File) }
    }

    $script:stats.Add([pscustomobject]@{
        file = $File; add = $Added.Count; del = $Removed.Count
        sigAdd = $sigAdd; sigDel = $sigDel
        castPreAdd = $preAdd; castPreDel = $preDel; castPostAdd = $postAdd; castPostDel = $postDel
        isPermutation = $isPerm
    })

    # Rename extraction only makes sense on a symmetric change-block.
    if ($Added.Count -ne $Removed.Count) { return }

    $provider = ($File -split '/')[0]
    $test     = (($File -split '/')[-1] -replace '\(.*$', '')

    for ($i = 0; $i -lt $Added.Count; $i++) {
        $a = $Added[$i]; $d = $Removed[$i]
        if ([string]::Equals($script:normRe.Replace($a, 'X'), $script:normRe.Replace($d, 'X'), [System.StringComparison]::Ordinal)) {
            $am = $script:normRe.Matches($a); $dm = $script:normRe.Matches($d)
            if ($am.Count -ne $dm.Count) { continue }
            for ($k = 0; $k -lt $am.Count; $k++) {
                # Ordinal on purpose: a case-only rename is a real rename.
                if ([string]::Equals($dm[$k].Value, $am[$k].Value, [System.StringComparison]::Ordinal)) { continue }
                $key = "$($dm[$k].Value)`u{001f}$($am[$k].Value)"
                if (-not $script:renameMap.ContainsKey($key)) {
                    $script:renameMap[$key] = [pscustomobject]@{
                        from  = $dm[$k].Value
                        to    = $am[$k].Value
                        hits  = 0
                        provs = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
                        tests = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
                    }
                }
                $e = $script:renameMap[$key]
                $e.hits++
                [void]$e.provs.Add($provider)
                [void]$e.tests.Add($test)
            }
        }
        else {
            $script:mismatchCount++
            if ($script:mismatchSamples.Count -lt 25) {
                $script:mismatchSamples.Add([pscustomobject]@{ file = $File; old = $d; new = $a })
            }
        }
    }
}

foreach ($line in ($diff -split "`n")) {
    $line = $line.TrimEnd("`r")
    if ($line.StartsWith('diff --git ')) {
        Flush-File -File $curFile -Added $add -Removed $del
        $curFile = ($line -split ' b/', 2)[-1]
        $add = [System.Collections.Generic.List[string]]::new()
        $del = [System.Collections.Generic.List[string]]::new()
        continue
    }
    if (-not $curFile) { continue }
    if ($line.StartsWith('+++') -or $line.StartsWith('---') -or
        $line.StartsWith('@@')  -or $line.StartsWith('index ')) { continue }
    if     ($line.StartsWith('+')) { $add.Add($line.Substring(1)) }
    elseif ($line.StartsWith('-')) { $del.Add($line.Substring(1)) }
}
Flush-File -File $curFile -Added $add -Removed $del

# ---- assemble --------------------------------------------------------------
$netPositive = @(); $netNegative = @(); $netZero = 0
foreach ($s in $stats) {
    if     ($s.add -gt $s.del) { $netPositive += [pscustomobject]@{ file = $s.file; add = $s.add; del = $s.del } }
    elseif ($s.add -lt $s.del) { $netNegative += [pscustomobject]@{ file = $s.file; add = $s.add; del = $s.del } }
    else                       { $netZero++ }
}

$sigFiles = @()
foreach ($s in $stats) {
    if ($s.sigAdd -ne $s.sigDel) {
        $sigFiles += [pscustomobject]@{ file = $s.file; added = $s.sigAdd; removed = $s.sigDel }
    }
}

$castLosses = @()
foreach ($s in $stats) {
    $preNet  = $s.castPreAdd  - $s.castPreDel
    $postNet = $s.castPostAdd - $s.castPostDel
    if ($preNet -lt 0 -or $postNet -lt 0) {
        $castLosses += [pscustomobject]@{ file = $s.file; prefixNet = $preNet; postfixNet = $postNet }
    }
}

$renames = @()
foreach ($e in ($renameMap.Values | Sort-Object -Property hits -Descending)) {
    $renames += [pscustomobject]@{
        from      = $e.from
        to        = $e.to
        hits      = $e.hits
        providers = $e.provs.Count
        tests     = @($e.tests | Sort-Object | Select-Object -First $MaxRenameTests)
    }
}

# A provider whose added file for a test case has a different statement count from the case's most common one
# either took another code path (an extra round trip, a split batch, an emulation) or failed part-way.
$parityGroups = 0
$parity       = @()
foreach ($g in ($statementCounts | Group-Object key)) {
    if ($g.Count -lt 2) { continue }
    $parityGroups++
    $mode = ($g.Group | Group-Object count | Sort-Object Count -Descending | Select-Object -First 1).Name
    $off  = @($g.Group | Where-Object { [string]$_.count -ne $mode } | ForEach-Object { [pscustomobject]@{ provider = $_.provider; count = $_.count } })
    if ($off.Count -gt 0) { $parity += [pscustomobject]@{ test = $g.Name; mode = [int]$mode; providers = $g.Count; deviating = $off } }
}

$providerList = @()
foreach ($k in ($providers.Keys | Sort-Object { -$providers[$_] }, { $_ })) {
    $providerList += [pscustomobject]@{ provider = $k; files = $providers[$k] }
}

$result = [ordered]@{
    status    = 'ok'
    branch    = $branch
    range     = $range
    branchTip = [ordered]@{ sha = $tip[0]; dateIso = $tip[1]; subject = $tip[2] }
    counts    = [ordered]@{ added = $counts.added; modified = $counts.modified; deleted = $counts.deleted }
    lines     = [ordered]@{
        added            = ($stats | Measure-Object -Property add -Sum).Sum
        removed          = ($stats | Measure-Object -Property del -Sum).Sum
        netZeroFiles     = $netZero
        netPositiveFiles = $netPositive.Count
        netNegativeFiles = $netNegative.Count
    }
    netPositive = $netPositive
    netNegative = $netNegative
    permutation = [ordered]@{
        pureFiles   = $pureCount
        impureFiles = ($stats.Count - $pureCount)
        impure      = $impure
    }
    signal      = [ordered]@{
        pattern        = $Signal
        added          = ($stats | Measure-Object -Property sigAdd -Sum).Sum
        removed        = ($stats | Measure-Object -Property sigDel -Sum).Sum
        filesWithDelta = $sigFiles
    }
    casts     = [ordered]@{
        prefix  = [ordered]@{
            added   = ($stats | Measure-Object -Property castPreAdd  -Sum).Sum
            removed = ($stats | Measure-Object -Property castPreDel  -Sum).Sum
        }
        postfix = [ordered]@{
            added   = ($stats | Measure-Object -Property castPostAdd -Sum).Sum
            removed = ($stats | Measure-Object -Property castPostDel -Sum).Sum
        }
        perFileLosses = $castLosses
    }
    providers = $providerList
    inherited = [ordered]@{
        files   = $inherited.Count
        samples = @($inherited | Select-Object -First 25)
    }
    addedTests = [ordered]@{
        universe = $addedUniverse.Count
        tests    = @($addedTests | Select-Object -First $MaxAddedTests)
    }
    decimalFacets = [ordered]@{
        checked        = $facetChecked
        violationCount = $facetViolations.Count
        violations     = @($facetViolations | Select-Object -First 25)
    }
    statementParity = [ordered]@{
        groups         = $parityGroups
        deviatingCount = $parity.Count
        deviating      = @($parity | Sort-Object { -$_.deviating.Count } | Select-Object -First 25)
    }
    renames   = [ordered]@{
        mismatches      = $mismatchCount
        mismatchSamples = @($mismatchSamples)
        map             = $renames
    }
    aliases   = [ordered]@{
        aliasOnlyFiles = $aliasOnlyCount
        otherFiles     = $aliasOther.Count
        otherSamples   = @($aliasOther | Select-Object -First 25)
    }
}

Write-JsonOutput -InputObject $result -Depth 6 -OutFile $OutFile -Summary ([ordered]@{
    status    = 'ok'
    counts    = $result.counts
    inherited = $inherited.Count
})
