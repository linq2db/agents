#!/usr/bin/env pwsh
<#
Push one corpus commit to the agents repo's master without pushing the other local commits around it.

The primary clone's .claude/ is shared by every session on the machine, so its master routinely carries other
sessions' unpushed commits. `git push` would publish them too. This script rebuilds the given commit's changes on
top of origin/master through a temporary index (no checkout, working tree and real index untouched), pushes the
result, and prints it. Afterwards run `git -C <repo> pull --rebase origin master`, which skips the local copy as
already applied.

Parameters
  -Repo    <path>   default '.claude'; the corpus checkout
  -Commit  <sha>    required; the commit to publish
  -Remote  <name>   default 'origin'
  -Branch  <name>   default 'master'
  -DryRun           build the commit, print it, do not push

Every path the commit adds or modifies is taken at its state in <Commit>; every path it deletes is removed. The
commit message and author are reused. Fails when the commit is a merge.

Output: JSON { commit, rebuilt, pushed, paths }.
#>
[CmdletBinding()]
param(
    [string] $Repo   = '.claude',
    [Parameter(Mandatory)][string] $Commit,
    [string] $Remote = 'origin',
    [string] $Branch = 'master',
    [switch] $DryRun
)

$ErrorActionPreference = 'Stop'

function Invoke-CorpusGit { & git -C $Repo @args; if ($LASTEXITCODE -ne 0) { throw "git $($args -join ' ') failed ($LASTEXITCODE)" } }

Invoke-CorpusGit fetch $Remote $Branch | Out-Null

$parents = @((Invoke-CorpusGit rev-list --parents -n 1 $Commit) -split ' ')
if ($parents.Count -ne 2) { throw "$Commit is a merge or a root commit" }

$changes = Invoke-CorpusGit diff-tree --no-commit-id --name-status -r $Commit

$indexFile = Join-Path (Invoke-CorpusGit rev-parse --absolute-git-dir) ("corpus-push-one-" + [guid]::NewGuid().ToString('n') + '.index')
$saved     = $env:GIT_INDEX_FILE
$env:GIT_INDEX_FILE = $indexFile

try {
    Invoke-CorpusGit read-tree "$Remote/$Branch"

    $paths = @()
    foreach ($line in $changes) {
        $status, $path = $line -split "`t", 2
        if ($status -eq 'D') {
            Invoke-CorpusGit update-index --force-remove -- $path
        } else {
            $mode = (Invoke-CorpusGit ls-tree $Commit -- $path) -split '\s+' | Select-Object -First 1
            $blob = Invoke-CorpusGit rev-parse "${Commit}:$path"
            Invoke-CorpusGit update-index --add --cacheinfo "$mode,$blob,$path"
        }
        $paths += "$status $path"
    }

    $tree = Invoke-CorpusGit write-tree

    $env:GIT_AUTHOR_NAME  = Invoke-CorpusGit log -1 --format=%an $Commit
    $env:GIT_AUTHOR_EMAIL = Invoke-CorpusGit log -1 --format=%ae $Commit
    $env:GIT_AUTHOR_DATE  = Invoke-CorpusGit log -1 --format=%aI $Commit
    $message              = Invoke-CorpusGit log -1 --format=%B $Commit
    $rebuilt              = $message | & git -C $Repo commit-tree $tree -p "$Remote/$Branch"
    if ($LASTEXITCODE -ne 0) { throw 'commit-tree failed' }

    $pushed = $false
    if (-not $DryRun) {
        Invoke-CorpusGit push $Remote "${rebuilt}:refs/heads/$Branch" | Out-Null
        $pushed = $true
    }

    [ordered]@{ commit = $Commit; rebuilt = $rebuilt; pushed = $pushed; paths = $paths } | ConvertTo-Json
}
finally {
    $env:GIT_INDEX_FILE = $saved
    Remove-Item Env:GIT_AUTHOR_NAME, Env:GIT_AUTHOR_EMAIL, Env:GIT_AUTHOR_DATE -ErrorAction SilentlyContinue
    if (Test-Path $indexFile) { Remove-Item $indexFile }
}
