#!/usr/bin/env pwsh
<#
Stage selected hunks of `git diff HEAD` into the **index**, leaving the working tree alone.

Why this exists
---------------
The one-change-per-commit workflow (`agent-rules.md` -> *Git commit rules*) wants a commit per
finding, but a review pass routinely leaves several unrelated fixes in the *same* file - two
analyzer changes and three fixture changes in one pass is ordinary. `git add -p` is interactive
and therefore unavailable, and rebuilding the file per commit puts the tree in states nobody
tested.

Staging into the index instead inverts the problem: the working tree keeps the state you
actually verified from the first commit to the last, so every intermediate commit is made
without the tree ever leaving a green configuration, and `git status` is clean when you finish.

Usage
-----
    # 1. map the hunks (nothing is staged)
    .claude/scripts/stage-hunks.ps1 -Worktree <path> -Hunks 1 -ListOnly

    # 2. stage a finding's hunks, then commit; repeat
    .claude/scripts/stage-hunks.ps1 -Worktree <path> -Hunks 6,18
    git -C <path> commit -F <message-file>

**Re-run `-ListOnly` after every commit** - indices are relative to the *current* `git diff HEAD`
and renumber as hunks leave the diff. That renumbering is a feature: a hunk carrying two
findings' changes usually splits by itself once the first commit lands.

`-Split <n>:<k>` handles the case where it does not, keeping only the first k content lines of
hunk n (for an addition-only hunk whose two halves are contiguous in the file). The trailing
context line is preserved and the ranges are recomputed.

**Invoke it directly, never via `pwsh -NoProfile -File`** - that form flattens `-Hunks 6,18` into
the single string `"6,18"`, which binds to `[int[]]` as `618` and throws an out-of-range error
naming a hunk that does not exist. See `script-authoring.md`.
#>
param(
    [Parameter(Mandatory)][string]$Worktree,
    [Parameter(Mandatory)][int[]]$Hunks,
    [string]$Split,
    [switch]$ListOnly
)

$ErrorActionPreference = 'Stop'

# Scratch goes under .build/.agents, never beside the script (agent-rules.md -> Temp files).
$scratchDir = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) '.build/.agents'
if (-not (Test-Path $scratchDir)) { New-Item -ItemType Directory -Path $scratchDir -Force | Out-Null }

$patchPath = Join-Path $scratchDir 'stage-hunks-cur.patch'
& git -C $Worktree diff HEAD -U1 --output=$patchPath
if ($LASTEXITCODE -ne 0) { throw "git diff failed ($LASTEXITCODE)" }

$raw   = [System.IO.File]::ReadAllText($patchPath)
$lines = $raw -split "(?<=`n)"

# Walk the patch, recording each file's 4-line header and each hunk's line range.
$fileHeader = [System.Collections.Generic.List[int]]::new()
$current    = $null
$hunkList      = [System.Collections.Generic.List[object]]::new()

for ($i = 0; $i -lt $lines.Count; $i++) {
    $line = $lines[$i]

    if ($line -like 'diff --git *') {
        if ($current) { $current.End = $i - 1; $hunkList.Add($current); $current = $null }
        $fileHeader = [System.Collections.Generic.List[int]]::new()
        $fileHeader.Add($i)
        continue
    }

    if ($line -like 'index *' -or $line -like '--- *' -or $line -like '+++ *') {
        if (-not $current) { $fileHeader.Add($i) }
        continue
    }

    if ($line -like '@@ *') {
        if ($current) { $current.End = $i - 1; $hunkList.Add($current) }
        $current = [pscustomobject]@{ Start = $i; End = -1; Header = $fileHeader.ToArray() }
        continue
    }
}

if ($current) { $current.End = $lines.Count - 1; $hunkList.Add($current) }

$last = $hunkList[$hunkList.Count - 1]
# Only the split's trailing empty element, never a blank context line - which a unified diff writes as " ".
while ($last.End -gt $last.Start -and $lines[$last.End] -eq '') { $last.End = $last.End - 1 }

if ($ListOnly) {
    for ($n = 0; $n -lt $hunkList.Count; $n++) {
        $h = $hunkList[$n]
        $file = ($lines[$h.Header[0]] -replace '^diff --git a/', '' -replace ' b/.*', '').TrimEnd()
        '{0,3}  {1,-58} {2}' -f ($n + 1), $file, $lines[$h.Start].TrimEnd()
    }
    return
}

$splitHunk = -1; $splitKeep = 0
if ($Split) { $parts = $Split -split ':'; $splitHunk = [int]$parts[0]; $splitKeep = [int]$parts[1] }

$out          = [System.Text.StringBuilder]::new()
$emittedFiles = @{}

foreach ($n in ($Hunks | Sort-Object)) {
    if ($n -lt 1 -or $n -gt $hunkList.Count) { throw "hunk $n out of range (1..$($hunkList.Count))" }
    $h = $hunkList[$n - 1]

    $key = $lines[$h.Header[0]]
    if (-not $emittedFiles.ContainsKey($key)) {
        foreach ($hi in $h.Header) { [void]$out.Append($lines[$hi]) }
        $emittedFiles[$key] = $true
    }

    $body = @()
    for ($i = $h.Start + 1; $i -le $h.End; $i++) { $body += $lines[$i] }

    if ($n -eq $splitHunk) {
        $trailing = $body[-1]
        $body     = @($body[0..($splitKeep - 1)]) + @($trailing)

        # Recompute the ranges in place, so the header keeps its trailing context text and line terminator.
        if ($lines[$h.Start] -notmatch '^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@') { throw "cannot parse hunk $n" }
        $oldStart = $Matches[1]; $oldLen = $Matches[2]; $newStart = $Matches[3]
        if (-not $oldLen) { $oldLen = 1 }

        $newLen  = ($body | Where-Object { $_ -notlike '-*' }).Count
        $ranges  = "@@ -$oldStart,$oldLen +$newStart,$newLen @@"
        [void]$out.Append(($lines[$h.Start] -replace '^@@ -\d+(?:,\d+)? \+\d+(?:,\d+)? @@', $ranges))
    }
    else {
        [void]$out.Append($lines[$h.Start])
    }

    foreach ($b in $body) { [void]$out.Append($b) }
}

$stepPath = Join-Path $scratchDir 'stage-hunks-step.patch'
[System.IO.File]::WriteAllText($stepPath, $out.ToString())

& git -C $Worktree apply --cached --whitespace=nowarn $stepPath
if ($LASTEXITCODE -ne 0) { throw "git apply --cached failed ($LASTEXITCODE); patch left at $stepPath" }

"staged hunks: $($Hunks -join ', ')"
