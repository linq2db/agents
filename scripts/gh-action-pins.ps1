<#
gh-action-pins.ps1 - report which SHA-pinned GitHub Actions are behind their latest release.

Workflows pin actions by commit SHA with the tag in a trailing comment:

    - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1

A pinned SHA never moves, which is the point - and also means nothing updates it. This is the
discovery half of that maintenance, run from /release-deps alongside the NuGet walk.

Why a script rather than the calls by hand: each action needs the latest release looked up, that tag
resolved to a ref, and an annotated tag dereferenced to its commit before the SHA can be compared -
three chained `gh` calls per action, fanned out over every action in every workflow.

Annotated tags matter. `git/ref/tags/<tag>` returns the *tag object* SHA for an annotated tag, not the
commit, and pinning that value produces a reference Actions cannot resolve. The deref below is the
difference between a correct pin and one that fails at run time.

Output: JSON to stdout.

    {
      "ok": true,
      "scanned": 1,
      "actions": [
        { "action": "actions/checkout", "pinnedSha": "3d3c42e...", "pinnedTag": "v7.0.1",
          "latestTag": "v7.0.1", "latestSha": "3d3c42e...", "upToDate": true,
          "sites": [ { "file": ".github/workflows/build.yml", "line": 68 } ] }
      ],
      "outdated": [ ... same shape, upToDate false ... ]
    }

Exit codes: 0 = every pin current, 1 = at least one behind, 2 = an error (unresolvable action, bad
`gh`). A non-zero exit on "behind" is deliberate, so the release checklist can gate on it.

Usage:

    pwsh -NoProfile -File .claude/scripts/gh-action-pins.ps1
    pwsh -NoProfile -File .claude/scripts/gh-action-pins.ps1 -RepoRoot C:\Worktrees\linq2db\x
#>

[CmdletBinding()]
param(
    [string] $RepoRoot = (Get-Location).Path,
    # Where to look for `uses:` lines. Composite actions live under .github/actions/ when we add any.
    [string[]] $Globs = @('.github/workflows/*.yml', '.github/workflows/*.yaml', '.github/actions/**/action.yml')
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

function Fail([string] $message) {
    (@{ ok = $false; error = $message } | ConvertTo-Json -Depth 5)
    exit 2
}

# Highest *version*, not newest release. `repos/<x>/releases` is ordered by creation date, so a
# maintainer who backports to an old line publishes a release that sorts first: on 2026-03-17
# actions/download-artifact re-published v3.1.0 and v3.1.0-node20, six days after v8.0.1, neither
# flagged prerelease. Taking `.[0]` reported v3.1.0-node20 as latest and would have had the release
# walk *downgrade* a correct v8 pin by five majors. `releases/latest` happened to answer v8.0.1
# here, but it is date-based too, so it is the same bug waiting for a different publish order.
#
# Tags carrying a pre-release suffix (`-node20`, `-beta.1`) are skipped unless nothing else is
# available - they are alternate builds of a line, not the line's head.
function Get-LatestVersionTag([string] $repo) {
    $json = gh api "repos/$repo/releases?per_page=100" 2>$null
    if (-not $json) { return $null }
    $releases = $json | ConvertFrom-Json
    if (-not $releases) { return $null }

    $ranked = foreach ($r in $releases) {
        if ($r.draft -or $r.prerelease) { continue }
        $m = [regex]::Match($r.tag_name, '^v?(\d+)(?:\.(\d+))?(?:\.(\d+))?(?<suffix>[-+].*)?$')
        if (-not $m.Success) { continue }
        [pscustomobject]@{
            tag     = $r.tag_name
            clean   = -not $m.Groups['suffix'].Success
            version = [version]::new(
                [int] $m.Groups[1].Value,
                [int] ($m.Groups[2].Success ? $m.Groups[2].Value : 0),
                [int] ($m.Groups[3].Success ? $m.Groups[3].Value : 0))
        }
    }
    if (-not $ranked) { return $null }
    ($ranked | Sort-Object -Property @{ E = 'clean'; Descending = $true },
                                     @{ E = 'version'; Descending = $true } |
        Select-Object -First 1).tag
}

# Resolve a tag to the commit it points at, dereferencing an annotated tag.
function Resolve-TagCommit([string] $repo, [string] $tag) {
    $ref = gh api "repos/$repo/git/ref/tags/$tag" 2>$null | ConvertFrom-Json
    if (-not $ref) { return $null }
    if ($ref.object.type -eq 'tag') {
        # Annotated: the ref points at a tag object, which in turn points at the commit.
        $tagObj = gh api "repos/$repo/git/tags/$($ref.object.sha)" 2>$null | ConvertFrom-Json
        if (-not $tagObj) { return $null }
        return $tagObj.object.sha
    }
    return $ref.object.sha
}

$files = @()
foreach ($glob in $Globs) {
    $files += Get-ChildItem -Path (Join-Path $RepoRoot $glob) -File -ErrorAction SilentlyContinue
}
$files = $files | Sort-Object FullName -Unique

if (-not $files) {
    (@{ ok = $true; scanned = 0; actions = @(); outdated = @(); note = 'no workflow files found' } |
        ConvertTo-Json -Depth 6)
    exit 0
}

# `uses: owner/repo@<40 hex> # vX.Y.Z` - the comment is advisory, the SHA is what runs.
$pattern = '^\s*-?\s*uses:\s*(?<action>[\w.-]+/[\w.-]+)@(?<sha>[0-9a-f]{40})\s*(#\s*(?<tag>\S+))?'
$found = @{}

foreach ($file in $files) {
    $lineNo = 0
    foreach ($line in [System.IO.File]::ReadAllLines($file.FullName)) {
        $lineNo++
        $m = [regex]::Match($line, $pattern)
        if (-not $m.Success) { continue }

        $key = '{0}@{1}' -f $m.Groups['action'].Value, $m.Groups['sha'].Value
        if (-not $found.ContainsKey($key)) {
            $found[$key] = [ordered]@{
                action    = $m.Groups['action'].Value
                pinnedSha = $m.Groups['sha'].Value
                pinnedTag = if ($m.Groups['tag'].Success) { $m.Groups['tag'].Value } else { $null }
                sites     = @()
            }
        }
        $relative = $file.FullName.Substring($RepoRoot.Length).TrimStart('\', '/').Replace('\', '/')
        $found[$key].sites += [ordered]@{ file = $relative; line = $lineNo }
    }
}

$results = @()
foreach ($entry in $found.Values) {
    $repo = $entry.action

    $latestTag = Get-LatestVersionTag $repo
    if (-not $latestTag) { Fail "could not read releases for '$repo' - check the action still exists" }

    $latestSha = Resolve-TagCommit $repo $latestTag
    if (-not $latestSha) { Fail "could not resolve tag '$latestTag' of '$repo' to a commit" }

    $results += [ordered]@{
        action    = $entry.action
        pinnedSha = $entry.pinnedSha
        pinnedTag = $entry.pinnedTag
        latestTag = $latestTag
        latestSha = $latestSha
        upToDate  = ($entry.pinnedSha -eq $latestSha)
        # The replacement line to write, so the walk has nothing left to assemble by hand.
        pinLine   = "$($entry.action)@$latestSha # $latestTag"
        sites     = $entry.sites
    }
}

$results  = @($results | Sort-Object action)
$outdated = @($results | Where-Object { -not $_.upToDate })

(@{
    ok       = $true
    scanned  = $files.Count
    actions  = $results
    outdated = $outdated
} | ConvertTo-Json -Depth 6)

if ($outdated.Count -gt 0) { exit 1 }
exit 0
