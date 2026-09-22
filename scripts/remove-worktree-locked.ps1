<#
remove-worktree-locked.ps1 — remove a git worktree, recovering from whatever
blocked `git worktree remove --force`: a build-server file lock, or a path
longer than MAX_PATH ("Filename too long", from nested obj/bin output).

Note what a failed `git worktree remove --force` leaves behind: it can
**deregister the worktree before it fails**, so `git worktree list` no longer
shows it while the directory survives on disk, and a retry answers `is not a
working tree` — which reads as "already gone". That is why the recovery path
below deletes the directory and prunes rather than re-running the git command.

Codifies .claude/docs/worktree.md -> the lock-blocked cleanup sequence. GLUE ONLY
with one hard guard baked in: on a shared / multi-worktree machine, **do not lead
with `dotnet build-server shutdown`** — it is global per-SDK and disrupts other
concurrent worktree builds. So this script tries the clean removal first and only
runs build-server shutdown when you pass -AllowBuildServerShutdown (i.e. you've
confirmed no other builds are running). The shutdown judgment stays with you.

  pwsh -NoProfile -File .claude/scripts/remove-worktree-locked.ps1 -Path <worktree-path>
  pwsh -NoProfile -File .claude/scripts/remove-worktree-locked.ps1 -Path <worktree-path> -AllowBuildServerShutdown
#>
param(
    [Parameter(Mandatory)][string]$Path,
    [switch]$AllowBuildServerShutdown
)

. "$PSScriptRoot/_shared.ps1"
$global:ScriptBaseName = 'remove-worktree-locked'

$steps = @()

if (-not (Test-Path -LiteralPath $Path)) {
    $prune0 = Invoke-Git @('worktree', 'prune')
    if ($prune0.ok) { $steps += 'worktree-prune' }
    Write-JsonOutput ([pscustomobject]@{ ok = $true; path = $Path; existed = $false; removed = $true; lockBlocked = $false; steps = $steps })
    exit 0
}

# Step 0: clean removal first — succeeds outright when the worktree's own build
# has finished, no shutdown needed (the common case).
$rm = Invoke-Git @('worktree', 'remove', '--force', $Path)
if ($rm.ok) {
    $steps += 'worktree-remove-force'
    Write-JsonOutput ([pscustomobject]@{ ok = $true; path = $Path; existed = $true; removed = $true; lockBlocked = $false; steps = $steps })
    exit 0
}
$steps += "worktree-remove-force-failed: $($rm.error.Trim())"

# Lock-blocked path.
if ($AllowBuildServerShutdown) {
    $bs = Invoke-Process -FilePath 'dotnet' -ArgumentList @('build-server', 'shutdown')
    $buildServer = [pscustomobject]@{ ran = $true; ok = $bs.ok; note = $bs.error }
    $steps += 'build-server-shutdown'
} else {
    $buildServer = [pscustomobject]@{ ran = $false; reason = 'shared-machine guard — pass -AllowBuildServerShutdown only once you have confirmed no other worktree builds are running (worktree.md)' }
}

# Remove-Item succeeds in practice even when a lock-reporting process is still around.
$removed = $false; $rmErr = $null
try {
    Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
    $removed = $true
    $steps += 'remove-item'
} catch {
    $rmErr = $_.Exception.Message
    $steps += "remove-item-failed: $rmErr"

    # MAX_PATH: retry through the extended-length prefix, which is the only thing
    # that reaches a deeply nested .build/bin tree. Windows-only and harmless
    # elsewhere, since a rooted non-Windows path never matches.
    if ($IsWindows -and $Path -match '^[A-Za-z]:\\') {
        try {
            Remove-Item -LiteralPath "\\?\$Path" -Recurse -Force -ErrorAction Stop
            $removed = $true
            $rmErr   = $null
            $steps  += 'remove-item-longpath'
        } catch {
            $steps += "remove-item-longpath-failed: $($_.Exception.Message)"
        }
    }
}

$prune = Invoke-Git @('worktree', 'prune')
if ($prune.ok) { $steps += 'worktree-prune' }

Write-JsonOutput ([pscustomobject]@{
    ok          = $removed
    path        = $Path
    existed     = $true
    removed     = $removed
    lockBlocked = $true
    buildServer = $buildServer
    steps       = $steps
    error       = $rmErr
})
