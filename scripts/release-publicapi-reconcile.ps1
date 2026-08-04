<#
release-publicapi-reconcile.ps1 — PublicAPI.Shipped / PublicAPI.Unshipped
move for release prep. Distinct from `api-baselines` (which handles
`CompatibilitySuppressions.xml` — different tool, different files).

Actions:

  build       Run `dotnet build linq2db.slnx -c Release
              -p:RunApiAnalyzersDuringBuild=true` and capture stdout+stderr to
              .build/.agents/release-<ver>-publicapi-raw.txt.
              The flag is NOT optional: Source/Directory.Build.props gates the
              Microsoft.CodeAnalysis.PublicApiAnalyzers PackageReference itself
              on it, defaulting to false, so an ordinary Release build never
              loads the analyzers and reports zero RS diagnostics no matter how
              much drift exists. CI only enables them for PRs targeting
              `release`, which makes this the sole gate before that PR.
              Inputs:   -Version <ver>  [-Configuration <Release|Debug|Testing|Azure>]
              Output:   { ok, statusCode, rawFile, lineCount }

  discover    Parse the raw build log for RS0016 (missing-from-declared-API),
              RS0017 (in-declared-API-not-in-code) and RS0025 (declared more
              than once across the API files) diagnostics.
              Note RS0025 masks RS0016: while the declared set is malformed by
              duplicates the analyzer stops reporting missing symbols, so
              clearing RS0025 reveals more RS0016. Expect several passes.
              Inputs:   -Version <ver>  [-RawFile <path>]
              Output:   { ok, rsFindings[], rs0016Count, rs0017Count, rs0025Count }

  fix-drift   Transcribe the discovered diagnostics into PublicAPI.Unshipped.txt
              entries so plan/apply can move them into Shipped. Writes only what
              a diagnostic reported, never a declaration inferred from source.
              Dry-run unless -Apply. Asserts before writing (RS0016 symbols must
              be absent, RS0017 present, RS0025 duplicates still declared in the
              flat file) and refuses to write on any mismatch.
              Inputs:   -Version <ver>  [-RawFile <path>] [-Apply]
              Output:   { ok, edits[], assertionFailures[], written[] }

  plan        Walk every PublicAPI.Shipped.txt + sibling PublicAPI.Unshipped.txt
              pair under Source/. Compute the move (sorted union + Unshipped
              tombstones honored). Write plan JSON.
              Inputs:   -Version <ver>  [-SourceRoot <path>]
              Output:   { ok, planFile, files[], totalChanges, removalsOutsideInternal }
              Note:     stdout files[] is summary-only (paths + counts + flags).
                        Full shipped/unshipped before/after line arrays and the
                        added/removed lists are persisted to planFile on disk;
                        the diff and apply actions read them from there.

  diff        Print a per-file added/removed-lines view from the plan.
              Inputs:   -Version <ver>
              Output:   { ok, diffs[] }   (each entry: { path, kind, added[], removed[] })

  apply       Apply the plan to disk. UTF-8 encoding mirrors each file's
              existing BOM state. Line endings are normalized to LF
              (CRLF inputs are read but rewritten as LF — the analyzer is
              whitespace-tolerant and existing PublicAPI files in the repo
              use LF, so no churn in practice).
              Inputs:   -Version <ver>  [-Force]
              Output:   { ok, writtenFiles[], skippedFiles[] }

Tombstones: A line in Unshipped of the form `*REMOVED*<symbol>` is the
Roslyn convention for "this Shipped entry should disappear on next ship".
When moving Unshipped → Shipped we remove the matching `<symbol>` from
Shipped and drop the tombstone (it does NOT survive into Shipped).

The leading `#nullable enable` directive is preserved as the first line
of each file. Empty Unshipped files keep just that directive.

Conventions: `.claude/docs/script-authoring.md`. Sort order:
`System.StringComparer.Ordinal` — matches Roslyn's DeclarePublicApiAnalyzer
codefix output exactly.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('build','discover','plan','diff','apply','fix-drift')]
    [string]$Action,

    [string]$Version,
    [string]$Configuration = 'Release',
    [string]$RawFile,
    [string]$SourceRoot,
    [switch]$Force,
    [switch]$Apply
)

$global:ScriptBaseName = 'release-publicapi-reconcile'
. (Join-Path $PSScriptRoot '_shared.ps1')

$script:BoundParams = $PSBoundParameters

# -- paths -------------------------------------------------------------------

function Get-WorkDir {
    $dir = Join-Path (Get-Location) '.build/.agents'
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    return $dir
}

function Get-RawFilePath {
    param([string]$Ver, [string]$Override)
    if ($Override) { return $Override }
    if (-not $Ver) { Exit-WithError "Version required for raw-file path" }
    return (Join-Path (Get-WorkDir) "release-$Ver-publicapi-raw.txt")
}

function Get-PlanFilePath {
    param([string]$Ver)
    if (-not $Ver) { Exit-WithError "Version required for plan-file path" }
    return (Join-Path (Get-WorkDir) "release-$Ver-publicapi-plan.json")
}

function Get-SourceRootPath {
    param([string]$Override)
    if ($Override) { return $Override }
    return (Join-Path (Get-Location) 'Source')
}

# -- file IO helpers ---------------------------------------------------------

# Detect a UTF-8 BOM by reading the first 3 bytes. Used to preserve whatever
# BOM state an existing PublicAPI file has when we write it back. The repo's
# .cs/.vb files mandate BOM per .editorconfig, but PublicAPI.*.txt does not —
# preserving existing state avoids spurious BOM-add/remove churn in diffs.
function Test-HasUtf8Bom {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    $fs = [System.IO.File]::OpenRead($Path)
    try {
        $buf = New-Object byte[] 3
        $read = $fs.Read($buf, 0, 3)
        return ($read -ge 3 -and $buf[0] -eq 0xEF -and $buf[1] -eq 0xBB -and $buf[2] -eq 0xBF)
    } finally { $fs.Dispose() }
}

# Read a PublicAPI text file into an ordered array of lines.
# Strips BOM (via .NET's auto-detect on ReadAllText), normalizes CRLF→LF,
# drops trailing empty entries from the `Split('\n')` tail. Per-line content
# is left untouched — no whitespace trimming — because leading whitespace can
# be semantically meaningful in PublicAPI files (nested type declarations:
# `inner LinqToDB.Foo.Bar` etc).
function Read-PublicApiLines {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return @() }
    $text = [System.IO.File]::ReadAllText($Path, [System.Text.UTF8Encoding]::new($false))
    if (-not $text) { return @() }
    $text = $text -replace "`r`n","`n" -replace "`r","`n"
    $lines = $text -split "`n"
    # Trim trailing blank entries (file might end with \n, producing one
    # empty trailing element after split).
    while ($lines.Count -gt 0 -and -not $lines[-1]) {
        $lines = $lines[0..($lines.Count - 2)]
    }
    return $lines
}

function Write-PublicApiFile {
    param([string]$Path, [string[]]$Lines, [bool]$WithBom)
    $body = ($Lines -join "`n")
    if ($body) { $body += "`n" }
    $enc = [System.Text.UTF8Encoding]::new($WithBom)
    [System.IO.File]::WriteAllText($Path, $body, $enc)
}

# -- Phase: build ------------------------------------------------------------

function Do-Build {
    if (-not $Version) { Exit-WithError "build: -Version required" }
    $raw = Get-RawFilePath -Ver $Version -Override $RawFile
    # -p:RunApiAnalyzersDuringBuild=true is load-bearing, not a tuning knob:
    # without it Source/Directory.Build.props omits the PublicApiAnalyzers
    # PackageReference entirely and the build reports zero RS diagnostics
    # regardless of actual drift. Global property, so it reaches every project.
    $args = @('build','linq2db.slnx','-c',$Configuration,'-p:RunApiAnalyzersDuringBuild=true','--nologo','/clp:NoSummary')

    # Stream to file while running. Use Invoke-Process to merge stdout+stderr.
    $r = Invoke-Process -FilePath 'dotnet' -ArgumentList $args
    $combined = $r.stdout
    if ($r.stderr) {
        if ($combined) { $combined = $combined + "`n" + $r.stderr } else { $combined = $r.stderr }
    }
    [System.IO.File]::WriteAllText($raw, $combined, [System.Text.UTF8Encoding]::new($false))
    $lineCount = ($combined -split "`n").Count

    Write-JsonOutput @{
        ok         = $r.ok
        action     = 'build'
        statusCode = $r.code
        rawFile    = $raw
        lineCount  = $lineCount
        error      = if (-not $r.ok) { $r.error } else { $null }
    }
}

# -- Phase: discover ---------------------------------------------------------

# MSBuild diagnostic line format from `dotnet build`:
#   <path>(<line>,<col>): <sev> <code>: <message> [<projectFile>[::<TFM>]]
# RS0016 message: "Symbol '<symbol>' is not part of the declared public API."
# RS0017 message: "Symbol '<symbol>' is part of the declared API, but is either not public or could not be found."
# RS0025 message: "The symbol '<symbol>' appears more than once in the public API files."
# Note the lower-case 's' in RS0025's leading "The symbol" — hence (?:The s|S)ymbol.
# For RS0016/RS0017 <file> is the source file; for RS0025 it is the PublicAPI
# file holding the duplicate, which is what makes tombstone placement possible.
# We capture the project + TFM tail when present so the orchestrator can group findings.
# Deliberately NOT anchored at ^, and the file group must start at a drive
# letter and may not span " -> ": under a parallel solution build MSBuild
# interleaves a project-output line with a diagnostic on the same physical line
# ("  linq2db.Benchmarks -> C:\...dllC:\...\PublicAPI.Shipped.txt(12,1): error
# RS0025: ..."), and a ^-anchored greedy [^()]+ then captures both paths as the
# file. Counts survive that (the symbol group is still correct) but RS0025
# tombstone placement reads the file path, so it resolved to a bogus directory.
$script:DiagRx = '(?im)(?<file>[A-Za-z]:\\(?:(?!\s->\s)[^()\r\n])*?)\((?<line>\d+),(?<col>\d+)\):\s+(?<sev>error|warning)\s+(?<code>RS0016|RS0017|RS0025):\s+(?:The s|S)ymbol\s+''(?<symbol>[^'']+)''\s+(?<rest>[^\[]*)(?:\[(?<projTfm>[^\]]+)\])?'

function Do-Discover {
    if (-not $Version) { Exit-WithError "discover: -Version required" }
    $raw = Get-RawFilePath -Ver $Version -Override $RawFile
    if (-not (Test-Path -LiteralPath $raw)) {
        Exit-WithError "discover: raw build log not found at $raw — run -Action build first"
    }
    $text = [System.IO.File]::ReadAllText($raw, [System.Text.UTF8Encoding]::new($false))
    $findings = @()
    foreach ($m in [regex]::Matches($text, $script:DiagRx)) {
        $projTfm = $m.Groups['projTfm'].Value
        $csproj = $projTfm
        $tfm = $null
        if ($projTfm -and $projTfm -match '^(?<p>.+)::(?<t>[^:]+)$') {
            $csproj = $Matches['p']
            $tfm = $Matches['t']
        }
        $findings += [ordered]@{
            file     = $m.Groups['file'].Value.Trim()
            line     = [int]$m.Groups['line'].Value
            col      = [int]$m.Groups['col'].Value
            severity = $m.Groups['sev'].Value
            code     = $m.Groups['code'].Value
            symbol   = $m.Groups['symbol'].Value
            csproj   = $csproj
            tfm      = $tfm
        }
    }
    $rs0016 = @($findings | Where-Object { $_.code -eq 'RS0016' })
    $rs0017 = @($findings | Where-Object { $_.code -eq 'RS0017' })
    $rs0025 = @($findings | Where-Object { $_.code -eq 'RS0025' })
    Write-JsonOutput @{
        ok           = $true
        action       = 'discover'
        rawFile      = $raw
        rsFindings   = $findings
        rs0016Count  = @($rs0016).Count
        rs0017Count  = @($rs0017).Count
        rs0025Count  = @($rs0025).Count
        # Unique symbol counts matter more than diagnostic counts: one symbol is
        # reported once per TFM (and RS0025 once per hosting file), so the raw
        # totals run several times the number of entries actually needed.
        uniqueSymbols = @($findings | ForEach-Object { $_.symbol } | Sort-Object -Unique).Count
        clean        = (@($findings).Count -eq 0)
    }
}

# -- Phase: fix-drift --------------------------------------------------------

function Read-ApiLines {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return @() }
    return @(Read-PublicApiLines $Path | Where-Object { $_ -and $_ -ne '#nullable enable' })
}

function Do-FixDrift {
    if (-not $Version) { Exit-WithError "fix-drift: -Version required" }
    $raw = Get-RawFilePath -Ver $Version -Override $RawFile
    if (-not (Test-Path -LiteralPath $raw)) {
        Exit-WithError "fix-drift: raw build log not found at $raw — run -Action build first"
    }
    $text = [System.IO.File]::ReadAllText($raw, [System.Text.UTF8Encoding]::new($false))

    $diags = @()
    foreach ($m in [regex]::Matches($text, $script:DiagRx)) {
        $projTfm = $m.Groups['projTfm'].Value
        $csproj  = $projTfm
        $tfm     = $null
        if ($projTfm -and $projTfm -match '^(?<p>.+)::TargetFramework=(?<t>[^:]+)$') {
            $csproj = $Matches['p']
            $tfm    = $Matches['t']
        }
        $diags += [ordered]@{
            code   = $m.Groups['code'].Value
            symbol = $m.Groups['symbol'].Value
            file   = $m.Groups['file'].Value.Trim()
            csproj = $csproj
            tfm    = $tfm
        }
    }

    # edits: Unshipped path -> set of lines to add
    $edits    = @{}
    $failures = @()
    function Add-Edit {
        param([string]$Path, [string]$Line)
        if (-not $edits.ContainsKey($Path)) {
            $edits[$Path] = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
        }
        [void]$edits[$Path].Add($Line)
    }

    # RS0025 — tombstone the duplicate copy beside the file that hosts it, but
    # only after confirming the flat file still declares the symbol; otherwise
    # the tombstone would remove the sole declaration.
    foreach ($g in @($diags | Where-Object { $_.code -eq 'RS0025' } | Group-Object { "$($_.file)|$($_.symbol)" })) {
        $d          = $g.Group[0]
        $shippedDir = Split-Path -Parent $d.file
        $flatShip   = Join-Path (Split-Path -Parent $shippedDir) 'PublicAPI.Shipped.txt'
        if ((Read-ApiLines $d.file) -cnotcontains $d.symbol) {
            $failures += "RS0025 '$($d.symbol)': no longer present in $($d.file) — log is stale, the duplicate is already gone"
            continue
        }
        if ((Read-ApiLines $flatShip) -cnotcontains $d.symbol) {
            $failures += "RS0025 '$($d.symbol)': not declared in flat $flatShip — tombstoning the per-TFM copy would drop the only declaration"
            continue
        }
        Add-Edit -Path (Join-Path $shippedDir 'PublicAPI.Unshipped.txt') -Line "*REMOVED*$($d.symbol)"
    }

    # RS0016 / RS0017 — place per flagging TFM, promoting to the flat file only
    # when every per-TFM directory the project owns flagged the symbol. A
    # project family sharing one flat file (EF3/EF8/EF9/EF10) turns a wrongly
    # flattened RS0016 into RS0017s on its siblings.
    foreach ($code in @('RS0016','RS0017')) {
        foreach ($g in @($diags | Where-Object { $_.code -eq $code } | Group-Object { "$($_.csproj)|$($_.symbol)" })) {
            $d       = $g.Group[0]
            $apiRoot = Join-Path (Split-Path -Parent $d.csproj) 'PublicAPI'
            if (-not (Test-Path -LiteralPath $apiRoot)) {
                $failures += "$code '$($d.symbol)': no PublicAPI directory under $(Split-Path -Parent $d.csproj)"
                continue
            }
            $line = if ($code -eq 'RS0017') { "*REMOVED*$($d.symbol)" } else { $d.symbol }

            $declared = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
            foreach ($f in @(Get-ChildItem -LiteralPath $apiRoot -Recurse -File -Filter 'PublicAPI.Shipped.txt')) {
                foreach ($l in (Read-ApiLines $f.FullName)) { [void]$declared.Add($l) }
            }
            if ($code -eq 'RS0016' -and $declared.Contains($d.symbol)) {
                $failures += "RS0016 '$($d.symbol)': already declared — log is stale relative to the tree"
                continue
            }
            if ($code -eq 'RS0017' -and -not $declared.Contains($d.symbol)) {
                $failures += "RS0017 '$($d.symbol)': not declared — nothing to tombstone, log is stale"
                continue
            }

            $presentDirs = @(Get-ChildItem -LiteralPath $apiRoot -Directory | ForEach-Object Name | Sort-Object)
            $flagged     = @($g.Group | ForEach-Object { $_.tfm } | Where-Object { $_ } | Sort-Object -Unique)

            if ($presentDirs.Count -gt 0 -and $flagged.Count -gt 0 -and
                @(Compare-Object $presentDirs $flagged -SyncWindow 0).Count -eq 0) {
                Add-Edit -Path (Join-Path $apiRoot 'PublicAPI.Unshipped.txt') -Line $line
            } elseif ($flagged.Count -eq 0) {
                Add-Edit -Path (Join-Path $apiRoot 'PublicAPI.Unshipped.txt') -Line $line
            } else {
                foreach ($t in $flagged) {
                    $dir = Join-Path $apiRoot $t
                    if (-not (Test-Path -LiteralPath $dir)) {
                        $failures += "$code '$($d.symbol)': no PublicAPI directory for TFM $t under $apiRoot"
                        continue
                    }
                    Add-Edit -Path (Join-Path $dir 'PublicAPI.Unshipped.txt') -Line $line
                }
            }
        }
    }

    $editSummary = @($edits.Keys | Sort-Object | ForEach-Object {
        [ordered]@{ path = $_; lines = @($edits[$_]) ; count = $edits[$_].Count }
    })

    if ($failures.Count -gt 0) {
        Write-JsonOutput @{
            ok                = $false
            action            = 'fix-drift'
            error             = 'assertion-failures'
            assertionFailures = $failures
            edits             = $editSummary
            message           = 'Log and tree disagree — no files were modified. Re-run -Action build to refresh the log.'
        }
        return
    }

    if (-not $Apply) {
        Write-JsonOutput @{
            ok       = $true
            action   = 'fix-drift'
            dryRun   = $true
            edits    = $editSummary
            written  = @()
            message  = 'Dry run — pass -Apply to write.'
        }
        return
    }

    $written = @()
    foreach ($p in ($edits.Keys | Sort-Object)) {
        $set = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
        foreach ($l in (Read-ApiLines $p)) { [void]$set.Add($l) }
        foreach ($l in $edits[$p])         { [void]$set.Add($l) }
        $arr = $set.ToArray()
        [array]::Sort($arr, [System.StringComparer]::Ordinal)
        $bom = Test-HasUtf8Bom -Path $p
        Write-PublicApiFile -Path $p -Lines (@('#nullable enable') + @($arr)) -WithBom:$bom
        $written += $p
    }

    Write-JsonOutput @{
        ok           = $true
        action       = 'fix-drift'
        dryRun       = $false
        edits        = $editSummary
        written      = $written
        writtenCount = $written.Count
    }
}

# -- Phase: plan -------------------------------------------------------------

# Build the full list of PublicAPI.Shipped / PublicAPI.Unshipped pairs under
# Source/. Some projects use per-TFM subfolders (Source/X/PublicAPI/<tfm>/);
# others use a single intermediate folder (Source/X/PublicAPI/); others use
# flat root (Source/X/PublicAPI.Shipped.txt). All three patterns coexist in
# the linq2db tree.
function Get-PublicApiPairs {
    param([string]$Root)
    $shipped = Get-ChildItem -LiteralPath $Root -Recurse -File -Filter 'PublicAPI.Shipped.txt' -ErrorAction SilentlyContinue
    $pairs   = @()
    $skipped = @()
    foreach ($s in $shipped) {
        $unshipped = Join-Path $s.DirectoryName 'PublicAPI.Unshipped.txt'
        if (-not (Test-Path -LiteralPath $unshipped)) {
            # Some Shipped files have no sibling Unshipped (rare). Skip the
            # move for that pair entirely — recording unshipped=$null would
            # let Compute-MovePlan flag unshippedChanged=true (because empty
            # vs `#nullable enable`), and Do-Apply would then call
            # Write-PublicApiFile with a null path. Surface via Do-Plan's
            # skippedPairs[] so the orchestrator can report and decide.
            $skipped += $s.FullName
            continue
        }
        $pairs += @{ shipped = $s.FullName; unshipped = $unshipped }
    }
    return @{ pairs = $pairs; skipped = $skipped }
}

# Compute the post-move content for a Shipped/Unshipped pair.
# Returns @{
#   shippedBefore, shippedAfter, unshippedBefore, unshippedAfter,
#   added, removed, hasChanges, tombstones, removalsOutsideInternal
# }
function Compute-MovePlan {
    param([string]$ShippedPath, [string]$UnshippedPath)

    $shippedRaw   = if ($ShippedPath)   { Read-PublicApiLines $ShippedPath }   else { @() }
    $unshippedRaw = if ($UnshippedPath) { Read-PublicApiLines $UnshippedPath } else { @() }

    # Treat `#nullable enable` as a directive that always lives at top —
    # filter it out of the content-set computation, re-add at write time.
    $shippedBody   = @($shippedRaw   | Where-Object { $_ -ne '#nullable enable' -and $_ })
    $unshippedBody = @($unshippedRaw | Where-Object { $_ -ne '#nullable enable' -and $_ })

    $tombstones = @()
    $adds       = @()
    foreach ($l in $unshippedBody) {
        if ($l -match '^\*REMOVED\*(.+)$') {
            $tombstones += $Matches[1]
        } else {
            $adds += $l
        }
    }

    $set = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($l in $shippedBody) {
        if ($tombstones -ccontains $l) { continue }   # tombstoned: drop
        [void]$set.Add($l)
    }
    foreach ($a in $adds) { [void]$set.Add($a) }

    $newShippedBody = New-Object 'System.Collections.Generic.List[string]'
    foreach ($x in $set) { [void]$newShippedBody.Add($x) }
    $arr = $newShippedBody.ToArray()
    [array]::Sort($arr, [System.StringComparer]::Ordinal)
    $newShippedBody = @($arr)

    # Compute added/removed (set diff vs original Shipped body).
    # Explicit [string[]] cast: an empty `@()` array is typed object[] in
    # PowerShell, and HashSet<string>(IEnumerable<object>, IEqualityComparer<string>)
    # doesn't exist — the constructor overload resolution fails.
    $shippedSetBefore = [System.Collections.Generic.HashSet[string]]::new([string[]]$shippedBody, [System.StringComparer]::Ordinal)
    $shippedSetAfter  = [System.Collections.Generic.HashSet[string]]::new([string[]]$newShippedBody, [System.StringComparer]::Ordinal)
    $added   = @($newShippedBody | Where-Object { -not $shippedSetBefore.Contains($_) })
    $removed = @($shippedBody    | Where-Object { -not $shippedSetAfter.Contains($_)  })

    # Removals outside LinqToDB.Internal.* are policy-flagged (code-design.md).
    $removalsOutsideInternal = @($removed | Where-Object { $_ -notmatch '\bLinqToDB\.Internal\.' })

    # Final file content arrays (with directive at top).
    $newShippedLines   = @('#nullable enable') + $newShippedBody
    $newUnshippedLines = @('#nullable enable')

    $shippedChanged   = (($shippedRaw   -join "`n") -ne ($newShippedLines   -join "`n"))
    $unshippedChanged = (($unshippedRaw -join "`n") -ne ($newUnshippedLines -join "`n"))

    return @{
        shippedBefore           = $shippedRaw
        shippedAfter            = $newShippedLines
        unshippedBefore         = $unshippedRaw
        unshippedAfter          = $newUnshippedLines
        added                   = $added
        removed                 = $removed
        tombstones              = $tombstones
        hasChanges              = ($shippedChanged -or $unshippedChanged)
        shippedChanged          = $shippedChanged
        unshippedChanged        = $unshippedChanged
        removalsOutsideInternal = $removalsOutsideInternal
    }
}

function Do-Plan {
    if (-not $Version) { Exit-WithError "plan: -Version required" }
    $root = Get-SourceRootPath -Override $SourceRoot
    if (-not (Test-Path -LiteralPath $root)) {
        Exit-WithError "plan: source root not found at $root"
    }
    $pairInfo     = Get-PublicApiPairs -Root $root
    $pairs        = @($pairInfo.pairs)
    $skippedPairs = @($pairInfo.skipped)
    $files = @()
    $totalChanges = 0
    $totalRemovalsOutsideInternal = 0
    foreach ($p in $pairs) {
        $plan = Compute-MovePlan -ShippedPath $p.shipped -UnshippedPath $p.unshipped
        $entry = [ordered]@{
            shippedPath              = $p.shipped
            unshippedPath            = $p.unshipped
            hasChanges               = $plan.hasChanges
            shippedChanged           = $plan.shippedChanged
            unshippedChanged         = $plan.unshippedChanged
            addedCount               = @($plan.added).Count
            removedCount             = @($plan.removed).Count
            tombstoneCount           = @($plan.tombstones).Count
            removalsOutsideInternal  = @($plan.removalsOutsideInternal)
            shippedBefore            = $plan.shippedBefore
            shippedAfter             = $plan.shippedAfter
            unshippedBefore          = $plan.unshippedBefore
            unshippedAfter           = $plan.unshippedAfter
            added                    = $plan.added
            removed                  = $plan.removed
        }
        $files += $entry
        if ($plan.hasChanges) { $totalChanges++ }
        $totalRemovalsOutsideInternal += @($plan.removalsOutsideInternal).Count
    }
    $planPath = Get-PlanFilePath -Ver $Version
    [System.IO.File]::WriteAllText(
        $planPath,
        (($files | ConvertTo-Json -Depth 100)),
        [System.Text.UTF8Encoding]::new($false)
    )
    # Stdout view: summary-only (counts + per-file change flags). Full
    # shippedBefore/After / unshippedBefore/After / added / removed arrays
    # stay on disk in the plan file — for linq2db they sum to ~3.6 MB of
    # text across 72 file pairs, and duplicating that to stdout would push
    # the JSON output past 10 MB on every plan invocation. Do-Diff and
    # Do-Apply both read from the plan file, never from this stdout.
    $filesSummary = @($files | ForEach-Object { [ordered]@{
        shippedPath             = $_.shippedPath
        unshippedPath           = $_.unshippedPath
        hasChanges              = $_.hasChanges
        shippedChanged          = $_.shippedChanged
        unshippedChanged        = $_.unshippedChanged
        addedCount              = $_.addedCount
        removedCount            = $_.removedCount
        tombstoneCount          = $_.tombstoneCount
        removalsOutsideInternal = $_.removalsOutsideInternal
    }})
    Write-JsonOutput @{
        ok                          = $true
        action                      = 'plan'
        planFile                    = $planPath
        sourceRoot                  = $root
        totalPairs                  = @($pairs).Count
        totalChanges                = $totalChanges
        totalRemovalsOutsideInternal = $totalRemovalsOutsideInternal
        files                       = $filesSummary
        skippedPairs                = $skippedPairs
        skippedPairCount            = $skippedPairs.Count
    }
}

# -- Phase: diff -------------------------------------------------------------

function Do-Diff {
    if (-not $Version) { Exit-WithError "diff: -Version required" }
    $planPath = Get-PlanFilePath -Ver $Version
    if (-not (Test-Path -LiteralPath $planPath)) {
        Exit-WithError "diff: plan not found at $planPath — run -Action plan first"
    }
    $files = [System.IO.File]::ReadAllText($planPath) | ConvertFrom-Json -Depth 100 -AsHashtable
    $diffs = @()
    foreach ($f in @($files)) {
        if (-not $f.hasChanges) { continue }
        if ($f.shippedChanged) {
            $diffs += [ordered]@{
                path    = $f.shippedPath
                kind    = 'shipped'
                added   = @($f.added)
                removed = @($f.removed)
                removalsOutsideInternal = @($f.removalsOutsideInternal)
            }
        }
        if ($f.unshippedChanged) {
            $diffs += [ordered]@{
                path  = $f.unshippedPath
                kind  = 'unshipped'
                added = @()
                removed = @($f.unshippedBefore | Where-Object { $_ -ne '#nullable enable' -and $_ })
            }
        }
    }
    Write-JsonOutput @{
        ok       = $true
        action   = 'diff'
        planFile = $planPath
        diffs    = $diffs
        diffCount = @($diffs).Count
    }
}

# -- Phase: apply ------------------------------------------------------------

function Do-Apply {
    if (-not $Version) { Exit-WithError "apply: -Version required" }
    $planPath = Get-PlanFilePath -Ver $Version
    if (-not (Test-Path -LiteralPath $planPath)) {
        Exit-WithError "apply: plan not found at $planPath — run -Action plan first"
    }
    $files = [System.IO.File]::ReadAllText($planPath) | ConvertFrom-Json -Depth 100 -AsHashtable

    # Policy gate: any removals outside LinqToDB.Internal.* require -Force.
    # The orchestrator surfaces these to the user before calling apply, but
    # the script itself refuses to silently delete public API without the
    # explicit -Force flag.
    $blockingRemovals = @()
    foreach ($f in @($files)) {
        if ($f.removalsOutsideInternal -and @($f.removalsOutsideInternal).Count -gt 0) {
            $blockingRemovals += [ordered]@{
                file    = $f.shippedPath
                symbols = @($f.removalsOutsideInternal)
            }
        }
    }
    if ($blockingRemovals.Count -gt 0 -and -not $Force) {
        Write-JsonOutput @{
            ok                = $false
            action            = 'apply'
            error             = 'removals-outside-internal-without-force'
            blockingRemovals  = $blockingRemovals
            message           = 'Public API removals outside LinqToDB.Internal.* require -Force after explicit user sign-off (code-design.md). No files were modified.'
        }
        return
    }

    $written = @()
    $skipped = @()
    foreach ($f in @($files)) {
        if (-not $f.hasChanges) {
            $skipped += $f.shippedPath
            continue
        }
        if ($f.shippedChanged) {
            $bom = Test-HasUtf8Bom -Path $f.shippedPath
            Write-PublicApiFile -Path $f.shippedPath -Lines @($f.shippedAfter) -WithBom:$bom
            $written += $f.shippedPath
        }
        if ($f.unshippedChanged) {
            $bom = Test-HasUtf8Bom -Path $f.unshippedPath
            Write-PublicApiFile -Path $f.unshippedPath -Lines @($f.unshippedAfter) -WithBom:$bom
            $written += $f.unshippedPath
        }
    }
    Write-JsonOutput @{
        ok            = $true
        action        = 'apply'
        writtenFiles  = $written
        skippedFiles  = $skipped
        writtenCount  = @($written).Count
        skippedCount  = @($skipped).Count
    }
}

# -- dispatch ----------------------------------------------------------------

switch ($Action) {
    'build'     { Do-Build }
    'discover'  { Do-Discover }
    'plan'      { Do-Plan }
    'diff'      { Do-Diff }
    'apply'     { Do-Apply }
    'fix-drift' { Do-FixDrift }
    default     { Exit-WithError "unknown action: $Action" }
}
