#requires -Version 7
<#
Release-publish step 2 — triage the open baselines PRs before the anchor reset.

Lists every open PR in the baselines repo, resolves each one's parent linq2db PR
(state + milestone) in a single GraphQL call, classifies them against the release
milestone, and — with -Apply — comments on and closes the stale ones, deleting
their branches.

Dry-run by default: without -Apply nothing is mutated, so the plan can be shown
to the user for the confirmation the skill requires.

    pwsh -NoProfile -File .claude/scripts/baselines-triage.ps1 -Version 6.4.0
    pwsh -NoProfile -File .claude/scripts/baselines-triage.ps1 -Version 6.4.0 -Apply

Output (stdout, single JSON object):
    { action, version, repo, total, keep[], close[], results[], ok }

`keep[]` are PRs whose parent is on the release milestone — CI must be re-run on
those parents after the reset to regenerate them. `close[]` is everything else.
`results[]` is populated only under -Apply, one row per PR with per-call status.
#>
param(
    [Parameter(Mandatory)][string] $Version,
    [string] $Repo        = 'linq2db/linq2db.baselines',
    [string] $ParentOwner = 'linq2db',
    [string] $ParentName  = 'linq2db',
    [string] $CommentFile,
    [int]    $Limit       = 100,
    [int]    $Throttle    = 4,
    [switch] $Apply
)

$global:ScriptBaseName = 'baselines-triage'
. "$PSScriptRoot/_shared.ps1"

# ---- 1. open baselines PRs -------------------------------------------------

$listArgs = @(
    'pr', 'list',
    '--repo', $Repo,
    '--state', 'open',
    '--json', 'number,title,headRefName,createdAt',
    '--limit', "$Limit"
)
$list = Invoke-GhJson -ArgumentList $listArgs
if (-not $list.ok)
{
    Exit-WithError -Message "failed to list open PRs in ${Repo}: $($list.error)" `
                   -NextAction 'verify gh auth status and that the repo name is correct'
}

$prs = @($list.data)
if ($prs.Count -eq 0)
{
    Write-JsonOutput ([ordered]@{
        action  = if ($Apply) { 'apply' } else { 'plan' }
        version = $Version
        repo    = $Repo
        total   = 0
        keep    = @()
        close   = @()
        results = @()
        ok      = $true
    })
    return
}

# ---- 2. resolve each parent PR (one GraphQL round-trip) --------------------

# Title shape: "Baselines for https://github.com/linq2db/linq2db/pull/<n>".
# A PR whose title carries no parent number is left alone rather than guessed at.
$items = @()
foreach ($pr in $prs)
{
    $m = [regex]::Match([string]$pr.title, '/pull/(\d+)')
    $items += [pscustomobject]@{
        number   = [long]$pr.number
        title    = [string]$pr.title
        headRef  = [string]$pr.headRefName
        parent   = if ($m.Success) { [long]$m.Groups[1].Value } else { $null }
    }
}

$parents = @($items | Where-Object { $null -ne $_.parent } | ForEach-Object { $_.parent } | Sort-Object -Unique)

$parentInfo = @{}
if ($parents.Count -gt 0)
{
    $aliases = foreach ($p in $parents)
    {
        "p${p}: pullRequest(number: $p) { number state milestone { title } }"
    }
    $query = "query { repository(owner: `"$ParentOwner`", name: `"$ParentName`") { $($aliases -join ' ') } }"

    $gq = Invoke-GhJson -ArgumentList @('api', 'graphql', '-f', "query=$query")
    if (-not $gq.ok)
    {
        Exit-WithError -Message "failed to resolve parent PRs: $($gq.error)" `
                       -NextAction 'check gh auth scopes for the parent repository'
    }

    $repoNode = $gq.data.data.repository
    foreach ($p in $parents)
    {
        $node = $repoNode."p${p}"
        if ($null -ne $node)
        {
            $parentInfo[[string]$p] = [pscustomobject]@{
                state     = [string]$node.state
                milestone = if ($node.milestone) { [string]$node.milestone.title } else { $null }
            }
        }
    }
}

# ---- 3. classify -----------------------------------------------------------

# Keep only those whose parent sits on the release milestone: after the reset,
# CI re-run on the parent regenerates them and they are the ones we want back.
# Everything else (other milestone, none, closed/merged parent, unparseable
# title) is stale the moment master moves.
$keep  = @()
$close = @()
foreach ($it in $items)
{
    $info = if ($null -ne $it.parent) { $parentInfo[[string]$it.parent] } else { $null }
    $row  = [ordered]@{
        number          = $it.number
        headRef         = $it.headRef
        parent          = $it.parent
        parentState     = if ($info) { $info.state } else { $null }
        parentMilestone = if ($info) { $info.milestone } else { $null }
    }

    if ($info -and $info.milestone -eq $Version)
    {
        $keep += [pscustomobject]$row
    }
    else
    {
        $close += [pscustomobject]$row
    }
}

$result = [ordered]@{
    action  = if ($Apply) { 'apply' } else { 'plan' }
    version = $Version
    repo    = $Repo
    total   = $items.Count
    keep    = @($keep)
    close   = @($close)
    results = @()
    ok      = $true
}

if (-not $Apply -or $close.Count -eq 0)
{
    Write-JsonOutput $result
    return
}

# ---- 4. apply: comment, then close with branch delete ---------------------

# The comment text contains backticks, so it must travel as a file: `gh --body`
# is banned repo-wide and a backtick inside a shell argument would be command
# substitution.
if ($CommentFile)
{
    $commentPath = (Resolve-Path -LiteralPath $CommentFile).Path
}
else
{
    $dir = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) '.build/.agents'
    if (-not (Test-Path -LiteralPath $dir)) { [void](New-Item -ItemType Directory -Path $dir -Force) }
    $commentPath = Join-Path $dir "baselines-triage-$Version-comment.md"
    $text = @"
Closing as stale: ``linq2db.baselines/master`` is being force-reset to its anchor commit as part of the $Version release, so this PR's diff targets a base that no longer exists.

Re-run CI on the parent PR to regenerate a fresh baselines PR against the reset master.
"@
    [System.IO.File]::WriteAllText($commentPath, $text, [System.Text.UTF8Encoding]::new($false))
}

$targets = @($close | ForEach-Object { $_.number })

$rows = $targets | ForEach-Object -Parallel {
    # Helper functions from _shared.ps1 are not visible in a parallel runspace,
    # so gh is invoked directly here. Errors are returned, never thrown — `exit`
    # inside a parallel block would kill only this runspace.
    $n    = $_
    $repo = $using:Repo
    $body = $using:commentPath

    $row = [ordered]@{ number = $n; comment = 'skipped'; close = 'skipped' }

    $out = & gh pr comment $n --repo $repo --body-file $body 2>&1
    if ($LASTEXITCODE -ne 0)
    {
        $row.comment = "FAIL: $($out -join ' ')"
        return [pscustomobject]$row
    }
    $row.comment = 'ok'

    $out = & gh pr close $n --repo $repo --delete-branch 2>&1
    $row.close = if ($LASTEXITCODE -eq 0) { 'ok' } else { "FAIL: $($out -join ' ')" }

    [pscustomobject]$row
} -ThrottleLimit $Throttle

$rows = @($rows | Sort-Object number)

$result.results = $rows
$result.ok      = -not ($rows | Where-Object { $_.comment -ne 'ok' -or $_.close -ne 'ok' })

Write-JsonOutput $result
