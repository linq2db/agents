#!/usr/bin/env pwsh
<#
release-notes-draft.ps1 — deterministic plumbing for the release-notes
automation (`/release-notes` skill).

This script does NOT compose prose. The agent writes the user-facing change
text (per the provider-claim-verification discipline) and hands it to this
script as manifest fields; the script wraps it in the draft scaffolding,
writes the per-PR draft file idempotently, harvests drafts at release time,
and regenerates the wiki release-notes section.

Draft store: one file per PR at `<corpus>/release-notes/<pr>.md` (corpus =
this script's parent directory). The script writes files only — it never
commits or pushes; the skill owns the corpus git step.

Actions
-------

  find        Locate the PR's draft file and parse its state.
              In:  -Pr <n>
              Out: { ok, present, path?, state: { lastSha, omit,
                     includeBrief, markerVersion } }

  upsert      Create or overwrite the draft file.
              In:  -ManifestFile { pr, lastSha, omit, includeBrief,
                                   fullText, briefText }
              Out: { ok, path, created|patched, verify: { ok,
                     sentLength, storedLength } }

  harvest     Collect every milestone PR's draft (flags + full + brief text).
              In:  -Milestone <ver> [-PlanFile <path>] [-Repo] [-Version]
              Out (stdout): counts + harvestFile path
              File: .build/.agents/release-<ver>-notes-harvest.json
                    { items[]: { pr, hasDraft, omit, includeBrief, lastSha,
                                 fullText, briefText, linkedIssues[] } }

  apply-wiki  Regenerate the version's release-notes section in the local wiki
              clone (idempotent — full-section rebuild) and emit a git diff.
              Does NOT commit or push (the skill confirms the diff, then the
              user-gated git commit + push runs separately).
              In:  -ManifestFile { version, wikiClone, [page], prBullets[],
                                   [deepDives[]] }
                     prBullets[]: { pr, [issue], component, changeType, text,
                                    [url] }
                     deepDives[]: { pr, heading, body }
              Out: { ok, page, sectionAction, diffPath, bulletCount,
                     deepDiveCount }

  omit        Persist an omit decision: upsert an omit-flagged, prose-less draft
              file per PR (head SHA looked up per PR).
              In:  -Prs <n>[,<n>…] [-Repo]
              Out: { ok, results[]: { pr, ok, path, created } }

  build-manifest  Turn the harvested drafts into the cumulative apply-wiki
              manifest. Parses each non-omitted draft's full text:
              `**<Component> — <type>**` headers (type: ⚠ Breaking changes /
              Added / Improved / Fixed) over `- ` bullets, and a
              `**Provider bullets**` block of `- **<Component>** — <text>`
              bullets (type Fixed; a text starting `known limitation:` goes to
              "Known limitations"). Indented continuation lines and code fences
              stay with their bullet.
              In:  -Milestone <ver> [-Version] [-WikiClone]   (run harvest first)
              Out: { ok, manifestFile, bulletCount, components{} } — exit 1 on
                   any unparseable draft, listing them in errors[]
              File: .build/.agents/release-<ver>-apply-wiki.json

  sweep-plan  Find milestone PRs missing a draft file and/or missing from
              the wiki notes (orphan sweep — catches user-merged PRs).
              In:  -Milestone <ver> [-PlanFile] [-WikiClone] [-Repo] [-Version]
              Out (stdout): counts + sweepFile path
              File: .build/.agents/release-<ver>-notes-sweep.json
                    { missingDraft[]: { pr, title, url },
                      missingWiki[]:  { pr, title, url, hasDraft, omit } }

Conventions: `.claude/docs/script-authoring.md`.
Marker scheme mirrors `release-state.ps1` (start/end + machine block).
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('find','upsert','harvest','apply-wiki','sweep-plan','omit','build-manifest')]
    [string]$Action,

    [int]$Pr,
    [int[]]$Prs,
    [string]$Milestone,
    [string]$Repo = 'linq2db/linq2db',
    [string]$Version,
    [string]$ManifestFile,
    [string]$PlanFile,
    [string]$WikiClone,
    [switch]$NoSync
)

$global:ScriptBaseName = 'release-notes-draft'
. "$PSScriptRoot/_shared.ps1"

if (-not $Version) { $Version = $Milestone }

# -- constants ---------------------------------------------------------------

$DraftMarkerPrefix = '<!-- release-notes:draft:'      # version-agnostic find anchor
$DraftStart   = '<!-- release-notes:draft:v1:start -->'
$DraftEnd     = '<!-- release-notes:draft:v1:end -->'
$FullStart    = '<!-- rn:full:start -->'
$FullEnd      = '<!-- rn:full:end -->'
$BriefStart   = '<!-- rn:brief:start -->'
$BriefEnd     = '<!-- rn:brief:end -->'
$StateStart   = '<!-- release-notes:state'
$OmitLabel    = '**Omit from release notes**'
$BriefLabel   = '**Include in the GitHub release highlights**'
$MarkerVersion = 1

# -- paths -------------------------------------------------------------------

function Get-WorkDir {
    $dir = Join-Path (Get-Location) '.build/.agents'
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    return $dir
}

function Get-DraftPath {
    param([int]$PrNumber)
    return Join-Path (Join-Path (Split-Path -Parent $PSScriptRoot) 'release-notes') "$PrNumber.md"
}

# -- draft body parse/build --------------------------------------------------

function Get-BetweenMarkers {
    param([string]$Body, [string]$Open, [string]$Close)
    if (-not $Body) { return $null }
    $a = $Body.IndexOf($Open, [System.StringComparison]::Ordinal)
    if ($a -lt 0) { return $null }
    $a += $Open.Length
    $b = $Body.IndexOf($Close, $a, [System.StringComparison]::Ordinal)
    if ($b -lt 0) { return $null }
    return $Body.Substring($a, $b - $a).Trim("`r","`n")
}

# Parse the draft body into a state object. The checkboxes are authoritative
# for the flags (the maintainer may have ticked them by hand);
# the embedded JSON is authoritative for lastSha.
function Read-DraftState {
    param([string]$Body)
    $state = [ordered]@{ lastSha = $null; omit = $false; includeBrief = $false; markerVersion = $MarkerVersion }
    if (-not $Body) { return $state }

    # checkbox flags
    $omitRx  = [regex]::Escape($OmitLabel)
    $briefRx = [regex]::Escape($BriefLabel)
    if ($Body -match "(?m)^\s*-\s*\[(?<m>[ xX])\]\s*$omitRx")  { $state.omit         = ($Matches['m'] -match '[xX]') }
    if ($Body -match "(?m)^\s*-\s*\[(?<m>[ xX])\]\s*$briefRx") { $state.includeBrief = ($Matches['m'] -match '[xX]') }

    # machine block (JSON inside the HTML comment); lastSha + markerVersion
    $stateBlock = Get-BetweenMarkers -Body $Body -Open $StateStart -Close '-->'
    if ($stateBlock) {
        try {
            $j = $stateBlock | ConvertFrom-Json -Depth 20
            if ($j.lastSha) { $state.lastSha = [string]$j.lastSha }
            if ($j.markerVersion) { $state.markerVersion = [int]$j.markerVersion }
        } catch { }
    }
    return $state
}

function Build-DraftBody {
    param(
        [int]$PrNumber, [string]$LastSha, [bool]$Omit, [bool]$IncludeBrief,
        [string]$FullText, [string]$BriefText
    )
    $omitMark  = if ($Omit)         { 'x' } else { ' ' }
    $briefMark = if ($IncludeBrief) { 'x' } else { ' ' }
    $shortSha  = if ($LastSha -and $LastSha.Length -ge 7) { $LastSha.Substring(0,7) } else { [string]$LastSha }
    $full  = if ($FullText)  { $FullText.Trim("`r","`n") }  else { '_(none — nothing user-facing in this PR)_' }
    $brief = if ($BriefText) { $BriefText.Trim("`r","`n") } else { '_(none)_' }
    $stateJson = ([pscustomobject]@{
        lastSha       = $LastSha
        omit          = $Omit
        includeBrief  = $IncludeBrief
        markerVersion = $MarkerVersion
    } | ConvertTo-Json -Compress)

    $lines = [System.Collections.Generic.List[string]]::new()
    [void]$lines.Add($DraftStart)
    [void]$lines.Add('## 📝 Release-notes draft')
    [void]$lines.Add('')
    [void]$lines.Add("<sub>🤖 User-facing summary for [#$PrNumber](https://github.com/$Repo/pull/$PrNumber), maintained by ``/release-notes``. Tick the boxes to control how it ships; the text is regenerated when new commits land (the maintainer confirms every change).</sub>")
    [void]$lines.Add('')
    [void]$lines.Add("- [$omitMark] $OmitLabel (exclude from both the wiki notes and the GitHub release highlights)")
    [void]$lines.Add("- [$briefMark] $BriefLabel (the brief release-page notes)")
    [void]$lines.Add('')
    [void]$lines.Add('### Full release notes (wiki)')
    [void]$lines.Add($FullStart)
    [void]$lines.Add($full)
    [void]$lines.Add($FullEnd)
    [void]$lines.Add('')
    [void]$lines.Add('### GitHub release highlight (brief)')
    [void]$lines.Add($BriefStart)
    [void]$lines.Add($brief)
    [void]$lines.Add($BriefEnd)
    [void]$lines.Add('')
    [void]$lines.Add('---')
    [void]$lines.Add("<sub>Generated from commit ``$shortSha``.</sub>")
    [void]$lines.Add("$StateStart")
    [void]$lines.Add($stateJson)
    [void]$lines.Add('-->')
    [void]$lines.Add($DraftEnd)
    return ($lines -join "`n")
}

# -- draft file read/write ---------------------------------------------------

# Line endings are normalised on read: a checkout with core.autocrlf yields CRLF.
function Read-DraftFile {
    param([string]$Path)
    return [System.IO.File]::ReadAllText($Path, [System.Text.UTF8Encoding]::new($false)).Replace("`r`n", "`n").TrimEnd("`n")
}

function Find-Draft {
    param([int]$PrNumber)
    $path = Get-DraftPath -PrNumber $PrNumber
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    $body = Read-DraftFile -Path $path
    if (-not $body.Contains($DraftMarkerPrefix)) { Exit-WithError "draft file has no '$DraftMarkerPrefix' marker: $path" }
    return [pscustomobject]@{ path = $path; body = $body }
}

# Write the draft file + byte-verify the re-read content.
function Write-Draft {
    param([int]$PrNumber, [string]$Body)
    $path = Get-DraftPath -PrNumber $PrNumber
    $dir = Split-Path -Parent $path
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $created = -not (Test-Path -LiteralPath $path)
    [System.IO.File]::WriteAllText($path, "$Body`n", [System.Text.UTF8Encoding]::new($false))
    $stored = Read-DraftFile -Path $path
    return [pscustomobject]@{
        path         = $path
        created      = $created
        verifyOk     = ($stored -ceq $Body)
        sentLength   = [System.Text.Encoding]::UTF8.GetByteCount($Body)
        storedLength = [System.Text.Encoding]::UTF8.GetByteCount($stored)
    }
}

# -- merged-PR listing (for harvest / sweep) ---------------------------------

function Get-MergedMilestonePRs {
    param([string]$RepoFull, [string]$Title)
    $r = Invoke-GhJson -ArgumentList @(
        'pr','list','--repo',$RepoFull,
        '--state','closed',
        '--search', "is:pr is:merged milestone:`"$Title`"",
        '--limit','500',
        '--json','number,title,body,url,closingIssuesReferences'
    )
    if (-not $r.ok) { Exit-WithError "merged PR list failed: $($r.error)" }
    return @($r.data)
}

# Resolve the PR list for harvest/sweep: from a plan file (audit output) if
# given, else by listing merged milestone PRs.
function Resolve-MilestonePRs {
    param([string]$RepoFull, [string]$Title, [string]$Plan)
    if ($Plan) {
        if (-not (Test-Path -LiteralPath $Plan)) { Exit-WithError "plan file not found: $Plan" }
        $p = (Get-Content -Raw -LiteralPath $Plan) | ConvertFrom-Json -Depth 100
        $byPr = @{}
        foreach ($it in @($p.items)) {
            if (-not $it.prNumber) { continue }
            $n = [int]$it.prNumber
            if (-not $byPr.ContainsKey($n)) {
                $byPr[$n] = [pscustomobject]@{ number = $n; title = $it.title; url = $it.url; linkedIssues = @() }
            }
            if ($it.issueNumber) { $byPr[$n].linkedIssues = @(@($byPr[$n].linkedIssues) + [int]$it.issueNumber | Sort-Object -Unique) }
        }
        return @($byPr.Values)
    }
    $prs = Get-MergedMilestonePRs -RepoFull $RepoFull -Title $Title
    $out = @()
    foreach ($pr in $prs) {
        $out += [pscustomobject]@{
            number       = [int]$pr.number
            title        = [string]$pr.title
            url          = [string]$pr.url
            linkedIssues = @(Get-PrLinkedIssues -Pr $pr)
        }
    }
    return $out
}

# -- wiki section regeneration -----------------------------------------------

$ChangeTypeOrder = @('Breaking','Added','Improved','Fixed','Changed','Removed','Other')

# Component grouping order: all project (linq2db package) areas sort before any
# database / provider area. Within each band components sort alphabetically.
#   0   = LinqToDB core (always first)
#   100 = other linq2db packages (EntityFrameworkCore, LINQPad, ...)
#   300 = linq2db CLI (last project area)
#   1000= database / provider areas (Access, ClickHouse, Oracle, SQLite, ...)
function Get-ComponentRank {
    param([string]$Name)
    if ($Name -ieq 'LinqToDB') { return 0 }
    if ($Name -ieq 'LinqToDB CLI' -or $Name -ieq 'linq2db.cli') { return 300 }
    if ($Name -imatch '^(LinqToDB|linq2db)') { return 100 }
    # Project areas whose header doesn't start with LinqToDB/linq2db need an explicit rank,
    # otherwise they fall into the 1000 database bucket and sort in among the providers.
    if ($Name -ieq 'Analyzers') { return 400 }
    return 1000
}

function Get-ChangeTypeRank {
    param([string]$Name)
    for ($i = 0; $i -lt $ChangeTypeOrder.Count; $i++) { if ($Name -ieq $ChangeTypeOrder[$i]) { return $i } }
    return $ChangeTypeOrder.Count
}

# GitHub-wiki heading slug (matches github-slugger): lowercase, drop everything
# that isn't a letter / digit / space / hyphen, then spaces -> hyphens (consecutive
# separators are NOT collapsed, e.g. "A / B" -> "a--b").
function Get-GitHubAnchor {
    param([string]$Heading)
    $s = ([string]$Heading).ToLowerInvariant()
    $s = [regex]::Replace($s, '[^\p{L}\p{Nd} -]', '')
    return ($s -replace ' ', '-')
}

# Build the markdown for a version section from prBullets + deepDives.
function Build-VersionSection {
    param([string]$Ver, $PrBullets, $DeepDives)
    $lines = [System.Collections.Generic.List[string]]::new()
    [void]$lines.Add("### Release $Ver")
    [void]$lines.Add('')

    # map PR -> deep-dive anchor, so a bullet whose PR has a deep-dive gets a
    # "See [details](#anchor) below" link (matches the older-release convention).
    $deepDiveAnchorByPr = @{}
    foreach ($d in @($DeepDives)) {
        $deepDiveAnchorByPr[[int]$d.pr] = (Get-GitHubAnchor $d.heading)
    }

    # group bullets by component, then change type
    $byComp = @{}
    foreach ($b in @($PrBullets)) {
        $comp = if ($b.component) { [string]$b.component } else { 'LinqToDB' }
        $ct   = if ($b.changeType) { [string]$b.changeType } else { 'Other' }
        if (-not $byComp.ContainsKey($comp)) { $byComp[$comp] = @{} }
        if (-not $byComp[$comp].ContainsKey($ct)) { $byComp[$comp][$ct] = @() }
        $byComp[$comp][$ct] += $b
    }

    $comps = @($byComp.Keys) | Sort-Object @{Expression={Get-ComponentRank $_}}, @{Expression={$_}}
    foreach ($comp in $comps) {
        [void]$lines.Add("#### $comp")
        [void]$lines.Add('')
        $cts = @($byComp[$comp].Keys) | Sort-Object @{Expression={Get-ChangeTypeRank $_}}, @{Expression={$_}}
        foreach ($ct in $cts) {
            # change-type as h5 so it renders visibly smaller than the h4 component header
            $label = if ($ct -ieq 'Breaking') { '##### ⚠ Breaking changes' } else { "##### $ct" }
            [void]$lines.Add($label)
            [void]$lines.Add('')
            # -Stable: several bullets can share one PR number (a PR spanning two change types, or
            # two separate findings from one PR). Sort-Object is unstable by default, so equal keys
            # would come out in arbitrary order and a regenerate would reshuffle already-published
            # bullets — churn in the diff and loss of the authored sequence.
            $bullets = @($byComp[$comp][$ct]) | Sort-Object -Stable @{Expression={[int]$_.pr}}
            foreach ($b in $bullets) {
                $ref = if ($b.url) { "[#$($b.pr)]($($b.url))" } else { "#$($b.pr)" }
                $txt = ([string]$b.text).Trim()
                # The anchor map is keyed by PR, so every bullet of a deep-dive PR would get the link.
                # A PR can also carry an unrelated bullet (e.g. a Fixed side effect alongside its Added
                # feature); linking that one points the reader at a spotlight about something else.
                # Per-bullet noDeepDiveLink opts out.
                $skipLink = $b.PSObject.Properties['noDeepDiveLink'] -and [bool]$b.noDeepDiveLink
                if (-not $skipLink -and $deepDiveAnchorByPr.ContainsKey([int]$b.pr)) {
                    $txt = $txt.TrimEnd() + " See [details](#$($deepDiveAnchorByPr[[int]$b.pr])) below."
                }
                # A bullet ending in a code fence would get the citation glued onto the closing ```,
                # which breaks the fence; put it on its own continuation line instead.
                if ($txt -match '```\s*$') { [void]$lines.Add("- $txt`n`n  ($ref)") }
                else                       { [void]$lines.Add("- $txt ($ref)") }
            }
            [void]$lines.Add('')
        }
    }

    foreach ($d in (@($DeepDives) | Sort-Object @{Expression={[int]$_.pr}})) {
        [void]$lines.Add("<!-- rn:deepdive:#$($d.pr) -->")
        # deep-dive spotlight at h4 (component-level peer), above the h5 change-type buckets
        [void]$lines.Add("#### $($d.heading)")
        [void]$lines.Add('')
        [void]$lines.Add((([string]$d.body).Trim("`r","`n")))
        [void]$lines.Add('')
    }
    return (($lines -join "`n").TrimEnd() + "`n")
}

# Splice the regenerated section into the page text, replacing an existing
# `### Release <ver>` block or inserting a new one at the top of the release
# list. Also maintains the TOC bullet. Returns @{ text; action }.
function Splice-VersionSection {
    param([string]$PageText, [string]$Ver, [string]$Section)
    $nl = "`n"
    $text = $PageText.Replace("`r`n", "`n")
    $verRx = [regex]::Escape($Ver)
    $anchor = '#release-' + ($Ver -replace '\.', '')

    # locate existing section: `### Release <ver>` up to next release heading or EOF
    $headRx = "(?m)^###?\s+Release\s+$verRx\b.*$"
    $m = [regex]::Match($text, $headRx)
    $action = ''
    if ($m.Success) {
        $start = $m.Index
        # next release heading after this one
        $nextRx = '(?m)^###?\s+Release\s+\S'
        $after = [regex]::Match($text.Substring($m.Index + $m.Length), $nextRx)
        if ($after.Success) {
            $end = $m.Index + $m.Length + $after.Index
        } else {
            $end = $text.Length
        }
        $newText = $text.Substring(0, $start) + $Section.TrimEnd() + $nl + $nl + $text.Substring($end).TrimStart("`n")
        $text = $newText
        $action = 'replaced'
    } else {
        # insert before the first existing `### Release ` section, or after `***`
        $firstRel = [regex]::Match($text, '(?m)^###?\s+Release\s+\S')
        $insertAt = if ($firstRel.Success) { $firstRel.Index } else { $text.Length }
        $block = $Section.TrimEnd() + $nl + $nl
        $text = $text.Substring(0, $insertAt) + $block + $text.Substring($insertAt)
        $action = 'inserted'
    }

    # TOC bullet maintenance: add `- [Release <ver>](#release-xyz)` as the first
    # TOC entry if not already present.
    if ($text -notmatch [regex]::Escape("($anchor)")) {
        $tocM = [regex]::Match($text, '(?m)^- \[Release ')
        if ($tocM.Success) {
            $tocLine = "- [Release $Ver]($anchor)" + $nl
            $text = $text.Substring(0, $tocM.Index) + $tocLine + $text.Substring($tocM.Index)
        }
    }
    return [pscustomobject]@{ text = $text; action = $action }
}

# Extract existing deep-dive blocks (<!-- rn:deepdive:#n --> + #### heading + body) from the
# current version section. Deep-dive *bodies* live only in the wiki — they are never stored in the
# per-PR draft files, so `harvest` can't supply them. A full-section regenerate from a manifest that
# omits them would silently delete them; Do-ApplyWiki carries these forward.
function Get-ExistingDeepDives {
    param([string]$PageText, [string]$Ver)
    $text = $PageText.Replace("`r`n", "`n")
    $verRx = [regex]::Escape($Ver)
    $m = [regex]::Match($text, "(?m)^###?\s+Release\s+$verRx\b.*$")
    if (-not $m.Success) { return @() }
    $after = [regex]::Match($text.Substring($m.Index + $m.Length), '(?m)^###?\s+Release\s+\S')
    $end = if ($after.Success) { $m.Index + $m.Length + $after.Index } else { $text.Length }
    $section = $text.Substring($m.Index, $end - $m.Index)
    $out = @()
    $rx = [regex]'(?s)<!-- rn:deepdive:#(?<pr>\d+) -->\n#### (?<h>.+?)\n(?<body>.*?)(?=\n<!-- rn:deepdive:#|\z)'
    foreach ($dm in $rx.Matches($section)) {
        $out += [pscustomobject]@{ pr = [int]$dm.Groups['pr'].Value; heading = $dm.Groups['h'].Value.Trim(); body = $dm.Groups['body'].Value.Trim("`n") }
    }
    return $out
}

# -- actions -----------------------------------------------------------------

function Do-Find {
    if (-not $Pr) { Exit-WithError '-Pr required for find' }
    $c = Find-Draft -PrNumber $Pr
    if (-not $c) {
        Write-JsonOutput ([ordered]@{ ok = $true; action = 'find'; pr = $Pr; present = $false; state = $null })
        return
    }
    $state = Read-DraftState -Body $c.body
    Write-JsonOutput ([ordered]@{
        ok = $true; action = 'find'; pr = $Pr; present = $true
        path = $c.path; state = $state
    })
}

function Do-Upsert {
    $m = Read-ManifestFromFileOrStdin -ManifestFile $ManifestFile
    if (-not (Test-IsInteger $m.pr) -or [long]$m.pr -le 0) { Exit-WithError 'manifest.pr (positive int) required' }
    $prNum = [int]$m.pr
    $lastSha = [string]$m.lastSha
    $omit = [bool]$m.omit
    $includeBrief = [bool]$m.includeBrief
    $fullText  = [string]$m.fullText
    $briefText = [string]$m.briefText

    $body = Build-DraftBody -PrNumber $prNum -LastSha $lastSha -Omit $omit -IncludeBrief $includeBrief -FullText $fullText -BriefText $briefText
    $res  = Write-Draft -PrNumber $prNum -Body $body
    Write-JsonOutput ([ordered]@{
        ok = $res.verifyOk; action = 'upsert'; pr = $prNum; path = $res.path
        patched = -not $res.created; created = $res.created
        verify = [ordered]@{ ok = $res.verifyOk; sentLength = $res.sentLength; storedLength = $res.storedLength }
    })
    if (-not $res.verifyOk) { exit 2 }
}

function Do-Omit {
    $list = @($Prs | Where-Object { $_ -gt 0 })
    if (-not $list) { Exit-WithError '-Prs <n>[,<n>…] required for omit' }
    $results = New-Object 'System.Collections.Generic.List[object]'
    foreach ($n in $list) {
        $sha = Invoke-Gh -ArgumentList @('pr','view',[string]$n,'--repo',$Repo,'--json','headRefOid','--jq','.headRefOid')
        if (-not $sha.ok) { $results.Add([ordered]@{ pr = $n; ok = $false; error = "head lookup failed: $($sha.error)" }) | Out-Null; continue }
        $body = Build-DraftBody -PrNumber $n -LastSha $sha.stdout.Trim() -Omit $true -IncludeBrief $false -FullText '' -BriefText ''
        $res  = Write-Draft -PrNumber $n -Body $body
        $results.Add([ordered]@{ pr = $n; ok = $res.verifyOk; path = $res.path; created = $res.created }) | Out-Null
    }
    $allOk = -not ($results | Where-Object { -not $_.ok })
    Write-JsonOutput ([ordered]@{ ok = $allOk; action = 'omit'; results = $results.ToArray() })
    if (-not $allOk) { exit 1 }
}

function Do-BuildManifest {
    if (-not $Version) { Exit-WithError '-Milestone (or -Version) required for build-manifest' }
    $harvestPath = Join-Path (Get-WorkDir) "release-$Version-notes-harvest.json"
    if (-not (Test-Path -LiteralPath $harvestPath)) { Exit-WithError "harvest file not found: $harvestPath — run -Action harvest first" }
    $h = [System.IO.File]::ReadAllText($harvestPath, [System.Text.UTF8Encoding]::new($false)) | ConvertFrom-Json
    $typeMap = @{ '⚠ Breaking changes' = 'Breaking'; 'Added' = 'Added'; 'Improved' = 'Improved'; 'Fixed' = 'Fixed' }
    $bullets = New-Object 'System.Collections.Generic.List[object]'
    $errors  = New-Object 'System.Collections.Generic.List[string]'

    $flush = {
        param($prNum, $comp, $type, $buf)
        if (-not $buf) { return }
        $text = (($buf -join "`n").TrimEnd()) -replace '^- ', ''
        if ($comp -eq '*provider*') {
            if ($text -notmatch '^\*\*(?<c>[^*]+)\*\* — (?<t>[\s\S]*)$') { $errors.Add("#${prNum}: provider bullet not '- **<Component>** — <text>'"); return }
            $comp = $Matches.c; $text = $Matches.t
            if ($text -match '^known limitation: (?<t>[\s\S]*)$') { $type = 'Known limitations'; $text = $Matches.t }
            $text = $text.Substring(0, 1).ToUpperInvariant() + $text.Substring(1)
        }
        if (-not $comp -or -not $type) { $errors.Add("#${prNum}: bullet outside a component header"); return }
        $bullets.Add([ordered]@{ pr = $prNum; component = $comp; changeType = $type; text = $text; url = "https://github.com/$Repo/pull/$prNum" }) | Out-Null
    }

    foreach ($it in @($h.items) | Where-Object { $_.hasDraft -and -not $_.omit }) {
        $prNum = [int]$it.pr; $comp = $null; $type = $null; $buf = $null
        foreach ($line in ([string]$it.fullText -split "`r?`n")) {
            if ($line -match '^\*\*Provider bullets\*\*\s*$') {
                & $flush $prNum $comp $type $buf; $buf = $null; $comp = '*provider*'; $type = 'Fixed'; continue
            }
            if ($line -match '^\*\*(?<c>.+?) — (?<t>.+?)\*\*\s*$') {
                & $flush $prNum $comp $type $buf; $buf = $null
                $comp = $Matches.c; $type = $typeMap[$Matches.t]
                if (-not $type) { $errors.Add("#${prNum}: unknown change type '$($Matches.t)'") }
                continue
            }
            if ($line -match '^- ') { & $flush $prNum $comp $type $buf; $buf = @($line); continue }
            if ($null -ne $buf) { $buf += $line }
            elseif ($line.Trim()) { $errors.Add("#${prNum}: text outside a bullet: $line") }
        }
        & $flush $prNum $comp $type $buf
    }

    if ($errors.Count) {
        Write-JsonOutput ([ordered]@{ ok = $false; action = 'build-manifest'; errors = $errors.ToArray() })
        exit 1
    }
    $clone = if ($WikiClone) { $WikiClone } else { '../linq2db.wiki' }
    $manifest = [ordered]@{ version = $Version; wikiClone = $clone; prBullets = $bullets.ToArray(); deepDives = @() }
    $manifestPath = Join-Path (Get-WorkDir) "release-$Version-apply-wiki.json"
    [System.IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 10), [System.Text.UTF8Encoding]::new($false))
    $byComp = [ordered]@{}
    foreach ($b in $bullets) { $byComp[$b.component] = 1 + [int]$byComp[$b.component] }
    Write-JsonOutput ([ordered]@{ ok = $true; action = 'build-manifest'; manifestFile = $manifestPath; bulletCount = $bullets.Count; components = $byComp })
}

function Do-Harvest {
    if (-not $Milestone) { Exit-WithError '-Milestone required for harvest' }
    $prs = Resolve-MilestonePRs -RepoFull $Repo -Title $Milestone -Plan $PlanFile
    $items = New-Object 'System.Collections.Generic.List[object]'
    foreach ($pr in $prs) {
        $c = Find-Draft -PrNumber ([int]$pr.number)
        if (-not $c) {
            $items.Add([ordered]@{
                pr = [int]$pr.number; title = $pr.title; hasDraft = $false
                omit = $false; includeBrief = $false; lastSha = $null
                fullText = $null; briefText = $null; linkedIssues = @($pr.linkedIssues)
            }) | Out-Null
            continue
        }
        $state = Read-DraftState -Body $c.body
        $items.Add([ordered]@{
            pr = [int]$pr.number; title = $pr.title; hasDraft = $true
            omit = $state.omit; includeBrief = $state.includeBrief; lastSha = $state.lastSha
            fullText  = (Get-BetweenMarkers -Body $c.body -Open $FullStart  -Close $FullEnd)
            briefText = (Get-BetweenMarkers -Body $c.body -Open $BriefStart -Close $BriefEnd)
            linkedIssues = @($pr.linkedIssues)
        }) | Out-Null
    }
    $harvestPath = Join-Path (Get-WorkDir) "release-$Version-notes-harvest.json"
    $payload = [ordered]@{ ok = $true; action = 'harvest'; milestone = $Milestone; harvestFile = $harvestPath; items = $items.ToArray() }
    [System.IO.File]::WriteAllText($harvestPath, ($payload | ConvertTo-Json -Depth 100), [System.Text.UTF8Encoding]::new($false))
    $briefCount = @($items | Where-Object { $_.includeBrief -and -not $_.omit }).Count
    Write-JsonOutput ([ordered]@{
        ok = $true; action = 'harvest'; milestone = $Milestone; harvestFile = $harvestPath
        counts = [ordered]@{ total = $items.Count; withDraft = @($items | Where-Object { $_.hasDraft }).Count; brief = $briefCount; omitted = @($items | Where-Object { $_.omit }).Count }
    })
}

function Do-ApplyWiki {
    $m = Read-ManifestFromFileOrStdin -ManifestFile $ManifestFile
    $ver = if ($m.version) { [string]$m.version } else { $Version }
    if (-not $ver) { Exit-WithError 'manifest.version (or -Version) required' }
    $clone = if ($m.wikiClone) { [string]$m.wikiClone } elseif ($WikiClone) { $WikiClone } else { Exit-WithError 'manifest.wikiClone (or -WikiClone) required' }
    if (-not (Test-Path -LiteralPath $clone)) {
        Exit-WithError "wiki clone not found at '$clone' — clone it once (on Windows use the no-checkout + sparse-checkout recipe in .claude/docs/release/external-repos.md; a plain 'git clone' fails on the colon-named wiki page)"
    }
    $page = if ($m.page) { [string]$m.page } else { 'Releases-and-Roadmap.md' }
    $pagePath = Join-Path $clone $page

    # sync: require clean tree, then ff-only pull (never reset — don't clobber)
    if (-not $NoSync) {
        $st = Invoke-Git -ArgumentList @('status','--porcelain') -WorkingDirectory $clone
        if (-not $st.ok) { Exit-WithError "git status in wiki clone failed: $($st.error)" }
        if ($st.stdout.Trim()) { Exit-WithError "wiki clone has uncommitted changes — commit/stash/discard them before apply-wiki, or pass -NoSync" }
        $fetch = Invoke-Git -ArgumentList @('fetch','origin') -WorkingDirectory $clone
        if (-not $fetch.ok) { Exit-WithError "git fetch in wiki clone failed: $($fetch.error)" }
        $pull = Invoke-Git -ArgumentList @('pull','--ff-only') -WorkingDirectory $clone
        if (-not $pull.ok) { Exit-WithError "git pull --ff-only in wiki clone failed (diverged?): $($pull.error)" }
    }

    if (-not (Test-Path -LiteralPath $pagePath)) { Exit-WithError "wiki page not found: $pagePath" }
    $pageText = [System.IO.File]::ReadAllText($pagePath, [System.Text.UTF8Encoding]::new($false))

    # Carry forward deep-dives already published in the live section that the manifest omits — their
    # bodies exist only in the wiki (never in draft files), so a manifest-only regenerate would drop them.
    $manifestDeepDives = @($m.deepDives)
    $manifestDdPrs     = @($manifestDeepDives | ForEach-Object { [int]$_.pr })
    $carriedDeepDives  = @(Get-ExistingDeepDives -PageText $pageText -Ver $ver | Where-Object { $manifestDdPrs -notcontains [int]$_.pr })
    $mergedDeepDives   = @($manifestDeepDives + $carriedDeepDives)

    $section = Build-VersionSection -Ver $ver -PrBullets $m.prBullets -DeepDives $mergedDeepDives
    $spliced = Splice-VersionSection -PageText $pageText -Ver $ver -Section $section
    [System.IO.File]::WriteAllText($pagePath, $spliced.text, [System.Text.UTF8Encoding]::new($false))

    $diff = Invoke-Git -ArgumentList @('diff','--', $page) -WorkingDirectory $clone
    $diffPath = Join-Path (Get-WorkDir) "release-$ver-wiki.diff"
    [System.IO.File]::WriteAllText($diffPath, [string]$diff.stdout, [System.Text.UTF8Encoding]::new($false))

    Write-JsonOutput ([ordered]@{
        ok = $true; action = 'apply-wiki'; page = $page; sectionAction = $spliced.action
        diffPath = $diffPath; bulletCount = @($m.prBullets).Count; deepDiveCount = @($mergedDeepDives).Count
        carriedForwardDeepDives = @($carriedDeepDives).Count
        clone = $clone
    })
}

function Do-SweepPlan {
    if (-not $Milestone) { Exit-WithError '-Milestone required for sweep-plan' }
    $prs = Resolve-MilestonePRs -RepoFull $Repo -Title $Milestone -Plan $PlanFile

    # wiki text: local clone page if provided, else published raw URL
    $wikiText = ''
    $wikiFetchFailed = $false
    if ($WikiClone -and (Test-Path -LiteralPath (Join-Path $WikiClone 'Releases-and-Roadmap.md'))) {
        $wikiText = [System.IO.File]::ReadAllText((Join-Path $WikiClone 'Releases-and-Roadmap.md'), [System.Text.UTF8Encoding]::new($false))
    } else {
        $url = "https://raw.githubusercontent.com/wiki/$Repo/Releases-and-Roadmap.md"
        try { $wikiText = (Invoke-WebRequest -Uri $url -TimeoutSec 30 -UseBasicParsing).Content } catch { $wikiText = ''; $wikiFetchFailed = $true }
    }

    $missingDraft = New-Object 'System.Collections.Generic.List[object]'
    $missingWiki  = New-Object 'System.Collections.Generic.List[object]'
    foreach ($pr in $prs) {
        $prNum = [int]$pr.number
        $c = Find-Draft -PrNumber $prNum
        $hasDraft = [bool]$c
        $omit = $false
        if ($c) { $omit = (Read-DraftState -Body $c.body).omit }
        if (-not $hasDraft) {
            $missingDraft.Add([ordered]@{ pr = $prNum; title = $pr.title; url = $pr.url }) | Out-Null
        }
        # wiki application: covered if the PR# or any linked issue# is mentioned
        $covered = (Test-MentionsRef -Text $wikiText -N $prNum)
        if (-not $covered) {
            foreach ($iss in @($pr.linkedIssues)) {
                if (Test-MentionsRef -Text $wikiText -N ([int]$iss)) { $covered = $true; break }
            }
        }
        if (-not $covered -and -not $omit) {
            $missingWiki.Add([ordered]@{ pr = $prNum; title = $pr.title; url = $pr.url; hasDraft = $hasDraft; omit = $omit }) | Out-Null
        }
    }

    $sweepPath = Join-Path (Get-WorkDir) "release-$Version-notes-sweep.json"
    $payload = [ordered]@{
        ok = $true; action = 'sweep-plan'; milestone = $Milestone; sweepFile = $sweepPath
        wikiFetchFailed = $wikiFetchFailed
        missingDraft = $missingDraft.ToArray(); missingWiki = $missingWiki.ToArray()
    }
    [System.IO.File]::WriteAllText($sweepPath, ($payload | ConvertTo-Json -Depth 100), [System.Text.UTF8Encoding]::new($false))
    Write-JsonOutput ([ordered]@{
        ok = $true; action = 'sweep-plan'; milestone = $Milestone; sweepFile = $sweepPath
        wikiFetchFailed = $wikiFetchFailed
        counts = [ordered]@{ total = @($prs).Count; missingDraft = $missingDraft.Count; missingWiki = $missingWiki.Count }
    })
}

# -- dispatch ----------------------------------------------------------------

switch ($Action) {
    'find'       { Do-Find }
    'upsert'     { Do-Upsert }
    'harvest'    { Do-Harvest }
    'apply-wiki' { Do-ApplyWiki }
    'sweep-plan' { Do-SweepPlan }
    'omit'           { Do-Omit }
    'build-manifest' { Do-BuildManifest }
    default      { Exit-WithError "unknown action: $Action" }
}
