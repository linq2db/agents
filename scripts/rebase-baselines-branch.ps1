<#
rebase-baselines-branch.ps1 — rebase `baselines/pr_<n>` onto linq2db.baselines
master without a working tree, master winning every conflict, then force-push
it with a lease on the old head.

Codifies .claude/docs/pr-and-push.md -> "After test renames / moves / deletes:
clean up stale baselines" (the CONFLICTING-because-master-moved case). GLUE
ONLY — the decision to rebase, the push go-ahead and the follow-up test-all on
the source PR stay with the agent / user.

  pwsh -NoProfile -File .claude/scripts/rebase-baselines-branch.ps1 -Pr 6198 -DryRun
  pwsh -NoProfile -File .claude/scripts/rebase-baselines-branch.ps1 -Pr 6198

Why no checkout: the baselines repo has ~400k files, some past MAX_PATH, so a
worktree / `git rebase` on Windows runs 10+ minutes and dies with
`Filename too long` (.claude/docs/dead-ends.md -> BUILD: checking out
linq2db.baselines). Each commit is replayed with
`merge-tree --write-tree -X ours --merge-base=<parent> <new-tip> <commit>`
(`ours` = the master-based chain) and `commit-tree`, keeping author,
committer and message; commits that come out empty are dropped. A conflict
`-X ours` cannot settle (modify/delete) stops the run with the file list.

Output: one JSON object — oldHead, newHead, replayed / skipped counts, the
--shortstat of the new tip against master, pushed.
#>
param(
    [Parameter(Mandatory)][int]$Pr,
    [string]$BaselinesClone,
    [string]$Remote = 'origin',
    [switch]$DryRun
)

. "$PSScriptRoot/_shared.ps1"
$global:ScriptBaseName = 'rebase-baselines-branch'
$BaselinesClone = Resolve-BaselinesClone -Path $BaselinesClone

$branch   = "baselines/pr_$Pr"
$upstream = "$Remote/master"
$tracking = "$Remote/$branch"

function Git([string[]]$GitArgs) {
    $r = Invoke-Git -ArgumentList $GitArgs -WorkingDirectory $BaselinesClone
    if (-not $r.ok) { Exit-WithError "git $($GitArgs -join ' ') failed: $($r.error)" }
    return $r.stdout.Trim()
}

$fetch = Invoke-Git -WorkingDirectory $BaselinesClone -ArgumentList @(
    'fetch', $Remote,
    "refs/heads/master:refs/remotes/$upstream",
    "refs/heads/${branch}:refs/remotes/$tracking")
if (-not $fetch.ok) { Exit-WithError "fetch failed: $($fetch.error)" -NextAction "check that $branch exists on linq2db.baselines" }

$oldHead = Git @('rev-parse', $tracking)
$tip     = Git @('rev-parse', $upstream)
if ((Git @('merge-base', $upstream, $tracking)) -eq $tip) {
    Write-JsonOutput ([pscustomobject]@{ ok = $true; pr = $Pr; branch = $branch; oldHead = $oldHead; action = 'none'; reason = 'already based on master' })
    exit 0
}
$commits = @((Git @('rev-list', '--reverse', '--topo-order', "$upstream..$tracking")) -split "`n" | Where-Object { $_ })
if (Git @('rev-list', '--merges', "$upstream..$tracking")) {
    Exit-WithError "$branch has merge commits; this replay handles a linear branch only"
}

$msgFile = [System.IO.Path]::GetTempFileName()
$replayed = 0; $skipped = 0
try {
    foreach ($c in $commits) {
        $parent = Git @('rev-parse', "$c^")
        $mt = Invoke-Git -WorkingDirectory $BaselinesClone -ArgumentList @(
            'merge-tree', '--write-tree', '--name-only', '--no-messages', '-X', 'ours', "--merge-base=$parent", $tip, $c)
        if (-not $mt.ok) {
            $files = @($mt.stdout -split "`n" | Select-Object -Skip 1 | Where-Object { $_ } | Select-Object -First 50)
            Exit-WithError "unresolvable conflict replaying $c ($($files.Count)+ files): $($files -join ', ')"
        }
        $tree = ($mt.stdout -split "`n")[0].Trim()
        if ($tree -eq (Git @('rev-parse', "$tip^{tree}"))) { $skipped++; continue }

        $f = (Git @('log', '-1', '--format=%an%x00%ae%x00%aI%x00%cn%x00%ce%x00%cI', $c)).Split([char]0)
        $env:GIT_AUTHOR_NAME    = $f[0]; $env:GIT_AUTHOR_EMAIL    = $f[1]; $env:GIT_AUTHOR_DATE    = $f[2]
        $env:GIT_COMMITTER_NAME = $f[3]; $env:GIT_COMMITTER_EMAIL = $f[4]; $env:GIT_COMMITTER_DATE = $f[5]
        # The raw object body, so the message bytes survive unchanged (`log --format=%B` normalises them).
        $raw = (Invoke-Git -WorkingDirectory $BaselinesClone -ArgumentList @('cat-file', 'commit', $c)).stdout
        [System.IO.File]::WriteAllText($msgFile, $raw.Substring($raw.IndexOf("`n`n") + 2), [System.Text.UTF8Encoding]::new($false))
        $tip = Git @('commit-tree', $tree, '-p', $tip, '-F', $msgFile)
        $replayed++
    }
} finally {
    Remove-Item Env:GIT_AUTHOR_NAME, Env:GIT_AUTHOR_EMAIL, Env:GIT_AUTHOR_DATE, Env:GIT_COMMITTER_NAME, Env:GIT_COMMITTER_EMAIL, Env:GIT_COMMITTER_DATE -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $msgFile -ErrorAction SilentlyContinue
}

$stat   = Git @('diff', '--shortstat', $upstream, $tip)
$pushed = $false
if (-not $DryRun) {
    $push = Invoke-Git -WorkingDirectory $BaselinesClone -ArgumentList @(
        'push', "--force-with-lease=refs/heads/${branch}:$oldHead", $Remote, "${tip}:refs/heads/$branch")
    if (-not $push.ok) { Exit-WithError "push failed: $($push.error)" -NextAction 're-run: the branch moved while replaying (a CI leg pushed)' }
    $pushed = $true
}

Write-JsonOutput ([pscustomobject]@{
    ok = $true; pr = $Pr; branch = $branch; oldHead = $oldHead; newHead = $tip
    commits = $commits.Count; replayed = $replayed; skippedEmpty = $skipped
    diffVsMaster = $stat; dryRun = [bool]$DryRun; pushed = $pushed
})
