# CANONICAL COPY - this file does not run from here.
# The executed copy must live at ~/.claude/hooks/ and be wired as a SessionStart hook in
# ~/.claude/settings.json: a hook shipped only inside .claude/ cannot run when .claude/ is
# the very thing that failed to populate. See docs/worktree.md -> Bootstrapping `.claude/`
# in a worktree. Keep the two copies in sync; this one is source-of-truth for review.
#
# SessionStart hook: populate an empty `.claude` submodule when a session starts
# inside a linked git worktree.
#
# `git worktree add` runs `reset --hard --no-recurse-submodules` internally, so it
# cannot populate a submodule -- the new worktree gets an empty `.claude/`, and
# because `.gitmodules` sets `ignore = all`, `git status` there reads clean. An
# agent in that worktree loads no AGENTS.md, no CLAUDE.md and no skills, with
# nothing signalling the absence.
#
# Exits 0 and stays silent unless it actually has work to do.

$ErrorActionPreference = 'Stop'

function Emit-AndExit {
    param([string]$Message, [string]$Context)

    $payload = @{}
    if ($Message) { $payload.systemMessage = $Message }
    if ($Context) {
        $payload.hookSpecificOutput = @{
            hookEventName     = 'SessionStart'
            additionalContext = $Context
        }
    }
    if ($payload.Count -gt 0) { $payload | ConvertTo-Json -Depth 5 -Compress }
    exit 0
}

function Get-FullPath {
    param([string]$Path, [string]$BaseDir)

    if (-not [System.IO.Path]::IsPathRooted($Path)) { $Path = Join-Path $BaseDir $Path }
    return [System.IO.Path]::GetFullPath($Path)
}

try {
    # --- session cwd comes in as JSON on stdin ------------------------------
    $cwd = $null
    $raw = [Console]::In.ReadToEnd()
    if ($raw) {
        try { $cwd = ($raw | ConvertFrom-Json).cwd } catch { }
    }
    if (-not $cwd) { $cwd = (Get-Location).Path }
    if (-not (Test-Path $cwd -PathType Container)) { exit 0 }

    # --- are we in a *linked* worktree? -------------------------------------
    # In a linked worktree the per-worktree git dir (.git/worktrees/<n>) differs
    # from the shared common dir (.git); in the primary clone they are the same.
    $absGitDir = git -C $cwd rev-parse --absolute-git-dir 2>$null
    $commonDir = git -C $cwd rev-parse --git-common-dir   2>$null
    if ($LASTEXITCODE -ne 0 -or -not $absGitDir -or -not $commonDir) { exit 0 }

    $absGitDir = Get-FullPath -Path $absGitDir -BaseDir $cwd
    $commonDir = Get-FullPath -Path $commonDir -BaseDir $cwd
    if ($absGitDir -eq $commonDir) { exit 0 }   # primary clone -- nothing to do

    $worktreeRoot = git -C $cwd rev-parse --show-toplevel 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $worktreeRoot) { exit 0 }
    $worktreeRoot = Get-FullPath -Path $worktreeRoot -BaseDir $cwd
    $primaryRoot  = Split-Path $commonDir -Parent

    # --- is `.claude` a submodule on this branch, and is it empty? -----------
    $entry = git -C $worktreeRoot ls-tree HEAD .claude 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $entry -or -not $entry.StartsWith('160000')) { exit 0 }

    $target = Join-Path $worktreeRoot '.claude'
    $marker = Join-Path $target 'AGENTS.md'

    # Corpus was already complete when this session started -- the @-imports resolved
    # against real files, nothing to do.
    if (Test-Path $marker) { exit 0 }

    # A NON-EMPTY directory is not proof of a populated corpus. `git worktree add` fires
    # post-checkout, which clones the corpus into `.claude/` -- and the session starts
    # *concurrently*, part-way through that clone. Measured on 2026-09-02: worktree add
    # began at 12:23:00.7, the session at 12:23:09.7, the corpus landed at 12:23:16.6.
    # Throughout that window `.claude/` is non-empty (git creates `.git` in the first
    # milliseconds) and incomplete, so the old `Get-ChildItem | Count -gt 0` test read it
    # as "already populated" and exited silently -- leaving the session with no rules and
    # nothing signalling it. Wait for the in-flight clone instead of racing it.
    $deadline = (Get-Date).AddSeconds(30)
    while (-not (Test-Path $marker) -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 250 }

    if (Test-Path $marker) {
        Emit-AndExit `
            -Message "The .claude corpus landed after this session started; project rules were not auto-loaded." `
            -Context "The .claude submodule was still being populated when this session started, so the CLAUDE.md @-imports resolved against an incomplete directory and this session loaded NO project rules. The corpus is complete now at $target -- read AGENTS.md, CLAUDE.md and docs/agent-rules.md there before acting. Note that skills are registered once at startup and are not rescanned, so the repo's own skills (/test, /work-plan, /api-baselines, ...) are unavailable in this session: run tests via the built test executable instead, as described in docs/testing.md."
    }

    # --- populate it --------------------------------------------------------
    # `--reference <primary>/.claude --dissociate` reuses the primary clone's
    # objects (no download) and then copies them in, so the worktree's corpus is
    # fully independent afterwards -- verified not to touch the primary clone's
    # `core.worktree` on git 2.52. git refuses a *shallow* reference outright
    # ("fatal: reference repository ... is shallow"), so fall back to a plain
    # clone from origin in that case.
    $gitArgs = @('-C', $worktreeRoot, 'submodule', 'update', '--init')
    $reference = Join-Path $primaryRoot '.claude'
    $borrowed = $false
    if (Test-Path (Join-Path $reference '.git')) {
        $shallow = git -C $reference rev-parse --is-shallow-repository 2>$null
        if ($LASTEXITCODE -eq 0 -and $shallow -eq 'false') {
            $gitArgs += @('--reference', $reference, '--dissociate')
            $borrowed = $true
        }
    }
    $gitArgs += @('--', '.claude')

    $output = & git @gitArgs 2>&1
    $ok = ($LASTEXITCODE -eq 0)

    $populated = 0
    if (Test-Path $target) {
        $populated = (Get-ChildItem $target -Force -ErrorAction SilentlyContinue | Measure-Object).Count
    }

    if ($ok -and $populated -gt 0) {
        $how = if ($borrowed) { 'borrowing the primary clone''s objects' } else { 'cloned from origin' }
        Emit-AndExit `
            -Message "Bootstrapped the .claude corpus submodule in this worktree ($how)." `
            -Context "The .claude submodule was empty in this worktree and has just been populated by the SessionStart hook, so AGENTS.md, CLAUDE.md, docs, skills and agents are now present at $target. The CLAUDE.md @-imports were resolved against an empty directory when this session started, so re-read the project rules from $target before relying on them."
    }
    else {
        Emit-AndExit `
            -Message "Could not bootstrap the .claude corpus submodule in this worktree; run 'git -C `"$worktreeRoot`" submodule update --init -- .claude' by hand. git said: $($output -join ' ')"
    }
}
catch {
    # Never break a session over this.
    Emit-AndExit -Message "bootstrap-worktree-corpus hook errored: $($_.Exception.Message)"
}
