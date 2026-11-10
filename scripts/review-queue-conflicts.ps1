#!/usr/bin/env pwsh
<#
Report which PRs in a "PR Review Queue" lane (org Project #8), and which of their
baselines PRs on linq2db.baselines, conflict with master - in one call.

Why this script exists
----------------------
"Do any In Review PRs or their baselines PRs conflict with master?" took four hand-chained
calls (2026-11-06): project items by status, PR mergeability, the baselines PRs'
mergeability, and `git merge-tree` to name a conflicting PR's files. Two of those steps have
traps that are easy to miss:

  - `gh pr list --json mergeable` on linq2db.baselines returns UNKNOWN for nearly every PR,
    because GitHub computes mergeability lazily and nobody opens those PRs. UNKNOWN means
    "not computed", not "conflicting". An aliased GraphQL query by number computes it, so
    every UNKNOWN (either repo) is re-asked that way, with one retry for stragglers.
  - The head of a fork PR is not on origin, so the conflict probe fetches
    `refs/pull/<n>/head` into `refs/remotes/origin/pr/<n>` (both refspec sides spelled in
    full - see windows-dev-gotchas.md) rather than the head branch name.

See pr-and-push.md -> "Checking PRs and their baselines PRs for conflicts with master".

Invoke directly via the PowerShell tool (preferred):

    .claude\scripts\review-queue-conflicts.ps1
    .claude\scripts\review-queue-conflicts.ps1 -Status 'Waiting For Review'
    .claude\scripts\review-queue-conflicts.ps1 -NoMergeTree
    .claude\scripts\review-queue-conflicts.ps1 -AllBaselines

Contract
--------
  -Status        <string>  project lane to read; default 'In Review'. Others: 'Todo',
                           'In Progress', 'Waiting For Review', 'Done'.
  -Project       <int>     org project number; default 8 ("PR Review Queue")
  -Owner         <string>  default 'linq2db'
  -NoMergeTree             skip the fetch + `git merge-tree` probe that names a conflicting
                           PR's files (the script then makes no git calls at all)
  -AllBaselines            ignore the project lane: report every open baselines PR, its
                           source linq2db PR's state, and (unless -NoMergeTree) the files
                           a conflicting one collides on, probed in the baselines clone.
                           Output shape below. (2026-11-06: hand-rolled for "check all
                           open baselines PRs for conflicts" before this switch existed.)
  -BaselinesClone <path>   for -AllBaselines; default `../linq2db.baselines`, else the
                           primary clone's sibling

Run from the primary clone (or any clone with `origin` = linq2db/linq2db): the probe fetches
`origin/master` and `origin/pr/<n>` there. It writes only those remote-tracking refs.

Output: one JSON object on stdout.

  {
    "project": 8, "status": "In Review", "count": 10, "conflicting": 1,
    "baselinesConflicting": 0, "unknown": 0,
    "prs": [
      { "number": 6198, "title": "...", "mergeable": "CONFLICTING", "mergeState": "DIRTY",
        "head": "feature/fix-debug-parameter-type-names",
        "conflictFiles": [ "Source/LinqToDB/PublicAPI/PublicAPI.Unshipped.txt" ],
        "baselinesPr": 2240, "baselinesMergeable": "MERGEABLE" }
    ]
  }

`mergeState` BEHIND means "mergeable, but not on master's tip" - not a conflict.
`baselinesPr` is null when the PR has no open baselines PR (`baselines/pr_<n>`).
`unknown` counts values still UNKNOWN after the retry; re-run before reading those as clean.

With -AllBaselines:

  {
    "mode": "all-baselines", "count": 18, "conflicting": 1, "unknown": 0, "staleSources": 1,
    "prs": [
      { "number": 2266, "head": "baselines/pr_5763", "sourcePr": 5763, "sourceState": "MERGED",
        "mergeable": "CONFLICTING", "conflictFiles": [ "YDB/Tests/..." ] }
    ]
  }

`staleSources` counts open baselines PRs whose linq2db PR is no longer open: a MERGED one
leaves baselines master behind master's code, and every later PR re-records that drift
(baselines-repo-layout.md -> "The other direction").
#>

[CmdletBinding()]
param(
    [string] $Status  = 'In Review',
    [int]    $Project = 8,
    [string] $Owner   = 'linq2db',
    [switch] $NoMergeTree,
    [switch] $AllBaselines,
    [string] $BaselinesClone
)

$ErrorActionPreference = 'Stop'
$global:ScriptBaseName = 'review-queue-conflicts'
. "$PSScriptRoot/_shared.ps1"

$mainRepo      = "$Owner/linq2db"
$baselinesRepo = "$Owner/linq2db.baselines"

# Mergeability by number via one aliased GraphQL query; GitHub computes it on demand.
function Get-Mergeable {
    param([string]$Repo, [long[]]$Numbers)
    $result = @{}
    if (-not $Numbers -or $Numbers.Count -eq 0) { return $result }
    $owner, $name = $Repo.Split('/')
    $fields = ($Numbers | ForEach-Object { "p${_}:pullRequest(number:$_){number mergeable}" }) -join ' '
    $query  = "{ repository(owner:`"$owner`", name:`"$name`") { $fields } }"
    $r = Invoke-GhJson -ArgumentList @('api', 'graphql', '-f', "query=$query")
    if (-not $r.ok) { Exit-WithError "graphql mergeable query on ${Repo} failed: $($r.error)" }
    foreach ($p in $r.data.data.repository.PSObject.Properties) {
        if ($p.Value) { $result[[long]$p.Value.number] = [string]$p.Value.mergeable }
    }
    return $result
}

function Resolve-Unknown {
    param([string]$Repo, [hashtable]$Map)
    for ($attempt = 0; $attempt -lt 2; $attempt++) {
        $pending = @($Map.Keys | Where-Object { $Map[$_] -eq 'UNKNOWN' -or -not $Map[$_] })
        if ($pending.Count -eq 0) { return }
        if ($attempt -gt 0) { Start-Sleep -Seconds 5 }
        $fresh = Get-Mergeable -Repo $Repo -Numbers ([long[]]$pending)
        foreach ($k in $fresh.Keys) { $Map[$k] = $fresh[$k] }
    }
}

function Get-MergeTreeConflicts {
    param([string]$Repo, [string]$Ref)
    # Exit 1 = conflicts. Output: tree oid, conflicted paths, blank line, messages.
    $m = Invoke-Git -ArgumentList @('merge-tree', '--write-tree', '--name-only', 'origin/master', $Ref) -WorkingDirectory $Repo
    $files = @()
    if ($m.code -eq 1) {
        $lines = $m.stdout -split "`r?`n"
        for ($i = 1; $i -lt $lines.Count -and $lines[$i] -ne ''; $i++) { $files += $lines[$i] }
    } elseif ($m.code -ne 0) {
        $files = @("<merge-tree failed: $($m.error)>")
    }
    return ,$files
}

if ($AllBaselines) {
    $bl = Invoke-GhJson -ArgumentList @('pr', 'list', '--repo', $baselinesRepo, '--state', 'open', '--limit', '500',
        '--json', 'number,headRefName')
    if (-not $bl.ok) { Exit-WithError "pr list on ${baselinesRepo} failed: $($bl.error)" }
    $all = @($bl.data | Sort-Object number)

    $blMergeable = Get-Mergeable -Repo $baselinesRepo -Numbers ([long[]]@($all | ForEach-Object { [long]$_.number }))
    foreach ($b in $all) { if (-not $blMergeable.ContainsKey([long]$b.number)) { $blMergeable[[long]$b.number] = 'UNKNOWN' } }
    Resolve-Unknown -Repo $baselinesRepo -Map $blMergeable

    $sourceOf = @{}
    foreach ($b in $all) {
        if ($b.headRefName -match '^baselines/pr_(\d+)$') { $sourceOf[[long]$b.number] = [long]$Matches[1] }
    }
    $sourceState = @{}
    if ($sourceOf.Count -gt 0) {
        $owner, $name = $mainRepo.Split('/')
        $fields = ($sourceOf.Values | Sort-Object -Unique | ForEach-Object { "p${_}:pullRequest(number:$_){number state}" }) -join ' '
        $r = Invoke-GhJson -ArgumentList @('api', 'graphql', '-f', "query={ repository(owner:`"$owner`", name:`"$name`") { $fields } }")
        if (-not $r.ok) { Exit-WithError "graphql state query on ${mainRepo} failed: $($r.error)" }
        foreach ($p in $r.data.data.repository.PSObject.Properties) {
            if ($p.Value) { $sourceState[[long]$p.Value.number] = [string]$p.Value.state }
        }
    }

    $conflictFiles = @{}
    $conflicting = @($all | Where-Object { $blMergeable[[long]$_.number] -eq 'CONFLICTING' })
    if (-not $NoMergeTree -and $conflicting.Count -gt 0) {
        $clone = Resolve-BaselinesClone -Path $BaselinesClone
        if (-not (Test-Path -LiteralPath $clone)) { Exit-WithError "baselines clone not found: $clone" -NextAction 'pass -BaselinesClone, or -NoMergeTree' }
        $refspecs = @('+refs/heads/master:refs/remotes/origin/master')
        foreach ($b in $conflicting) { $refspecs += "+refs/heads/$($b.headRefName):refs/remotes/origin/$($b.headRefName)" }
        $f = Invoke-Git -ArgumentList (@('fetch', 'origin') + $refspecs) -WorkingDirectory $clone
        if (-not $f.ok) { Exit-WithError "git fetch in ${clone} failed: $($f.error)" }
        foreach ($b in $conflicting) {
            $conflictFiles[[long]$b.number] = Get-MergeTreeConflicts -Repo $clone -Ref "origin/$($b.headRefName)"
        }
    }

    $prs = @()
    foreach ($b in $all) {
        $n   = [long]$b.number
        $src = if ($sourceOf.ContainsKey($n)) { $sourceOf[$n] } else { $null }
        $files = @()
        if ($conflictFiles.ContainsKey($n)) { $files = @($conflictFiles[$n]) }
        $prs += [ordered]@{
            number        = $n
            head          = [string]$b.headRefName
            sourcePr      = $src
            sourceState   = if ($null -ne $src -and $sourceState.ContainsKey($src)) { $sourceState[$src] } else { $null }
            mergeable     = $blMergeable[$n]
            conflictFiles = $files
        }
    }

    Write-JsonOutput -InputObject ([ordered]@{
        mode         = 'all-baselines'
        count        = $prs.Count
        conflicting  = @($prs | Where-Object { $_.mergeable -eq 'CONFLICTING' }).Count
        unknown      = @($prs | Where-Object { $_.mergeable -eq 'UNKNOWN' }).Count
        staleSources = @($prs | Where-Object { $_.sourceState -and $_.sourceState -ne 'OPEN' }).Count
        prs          = $prs
    })
    return
}

# 1. Project items in the lane.
$items = Invoke-GhJson -ArgumentList @('project', 'item-list', "$Project", '--owner', $Owner, '--limit', '1000', '--format', 'json')
if (-not $items.ok) { Exit-WithError "project item-list failed: $($items.error)" -NextAction 'check `gh auth status` has the read:project scope (`gh auth refresh -s read:project`)' }

$lane = @($items.data.items | Where-Object {
    $_.status -eq $Status -and $_.content.type -eq 'PullRequest' -and $_.content.repository -eq $mainRepo
})

# 2. Open PRs on both repos, one list call each.
$open = Invoke-GhJson -ArgumentList @('pr', 'list', '--repo', $mainRepo, '--state', 'open', '--limit', '500',
    '--json', 'number,mergeable,mergeStateStatus,headRefName')
if (-not $open.ok) { Exit-WithError "pr list on ${mainRepo} failed: $($open.error)" }
$openByNumber = @{}
foreach ($p in $open.data) { $openByNumber[[long]$p.number] = $p }

$bl = Invoke-GhJson -ArgumentList @('pr', 'list', '--repo', $baselinesRepo, '--state', 'open', '--limit', '500',
    '--json', 'number,headRefName')
if (-not $bl.ok) { Exit-WithError "pr list on ${baselinesRepo} failed: $($bl.error)" }
$baselinesFor = @{}
foreach ($b in $bl.data) {
    if ($b.headRefName -match '^baselines/pr_(\d+)$') { $baselinesFor[[long]$Matches[1]] = [long]$b.number }
}

$numbers = @($lane | ForEach-Object { [long]$_.content.number } | Where-Object { $openByNumber.ContainsKey($_) })

# 3. Mergeability: main repo from the list (re-asked where UNKNOWN), baselines always by GraphQL.
$mainMergeable = @{}
foreach ($n in $numbers) { $mainMergeable[$n] = [string]$openByNumber[$n].mergeable }
Resolve-Unknown -Repo $mainRepo -Map $mainMergeable

$blNumbers = @($numbers | Where-Object { $baselinesFor.ContainsKey($_) } | ForEach-Object { $baselinesFor[$_] })
$blMergeable = Get-Mergeable -Repo $baselinesRepo -Numbers ([long[]]$blNumbers)
foreach ($b in $blNumbers) { if (-not $blMergeable.ContainsKey($b)) { $blMergeable[$b] = 'UNKNOWN' } }
Resolve-Unknown -Repo $baselinesRepo -Map $blMergeable

# 4. Name the conflicting files.
$conflictFiles = @{}
$conflicting = @($numbers | Where-Object { $mainMergeable[$_] -eq 'CONFLICTING' })
if (-not $NoMergeTree -and $conflicting.Count -gt 0) {
    $refspecs = @('+refs/heads/master:refs/remotes/origin/master')
    foreach ($n in $conflicting) { $refspecs += "+refs/pull/$n/head:refs/remotes/origin/pr/$n" }
    $f = Invoke-Git -ArgumentList (@('fetch', 'origin') + $refspecs) -WorkingDirectory $PWD.Path
    if (-not $f.ok) { Exit-WithError "git fetch failed: $($f.error)" }

    foreach ($n in $conflicting) {
        $conflictFiles[$n] = Get-MergeTreeConflicts -Repo $PWD.Path -Ref "origin/pr/$n"
    }
}

# 5. Assemble.
$prs = @()
foreach ($item in $lane) {
    $n = [long]$item.content.number
    $isOpen = $openByNumber.ContainsKey($n)
    $blNum  = if ($baselinesFor.ContainsKey($n)) { $baselinesFor[$n] } else { $null }
    $files  = @()
    if ($conflictFiles.ContainsKey($n)) { $files = @($conflictFiles[$n]) }
    $prs += [ordered]@{
        number             = $n
        title              = [string]$item.content.title
        mergeable          = if ($isOpen) { $mainMergeable[$n] } else { 'NOT_OPEN' }
        mergeState         = if ($isOpen) { [string]$openByNumber[$n].mergeStateStatus } else { $null }
        head               = if ($isOpen) { [string]$openByNumber[$n].headRefName } else { $null }
        conflictFiles      = $files
        baselinesPr        = $blNum
        baselinesMergeable = if ($null -ne $blNum) { $blMergeable[$blNum] } else { $null }
    }
}

$unknown = @($prs | Where-Object { $_.mergeable -eq 'UNKNOWN' -or $_.baselinesMergeable -eq 'UNKNOWN' }).Count

Write-JsonOutput -InputObject ([ordered]@{
    project              = $Project
    status               = $Status
    count                = $prs.Count
    conflicting          = @($prs | Where-Object { $_.mergeable -eq 'CONFLICTING' }).Count
    baselinesConflicting = @($prs | Where-Object { $_.baselinesMergeable -eq 'CONFLICTING' }).Count
    unknown              = $unknown
    prs                  = $prs
})
