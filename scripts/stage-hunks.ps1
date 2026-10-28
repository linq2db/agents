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

`-CutFile <path> -Cut '<start>|||<end>', ...` is the exact fallback when hunks will not separate -
typically an insertion directly beside an edited line, which git always reports as one hunk.
It stages the file's **working-tree** content with each span (start marker through end marker,
plus the blank line after it) removed, so everything except the later commit's parts goes in.
Markers are literal text; `<path>` is relative to the worktree. A start marker that begins mid-line
leaves that line's indentation behind, so include the leading tabs in it. The file's UTF-8 BOM, if any,
is preserved.

    .claude/scripts/stage-hunks.ps1 -Worktree <path> -CutFile docs/x.md -Cut '## New section|||last words.'

`-Replace '<old>|||<new>'` (with `-CutFile`, alone or beside `-Cut`) restores a line a later commit
changed - a cut can only drop text. Replacements run first; every `<old>` and every cut start marker must
occur exactly once, or the call fails rather than editing the wrong occurrence.

`-Hunks` refuses a hunk that applies at the wrong place. With one line of context, an addition whose
context line repeats (`/// <summary>`, a blank line) can apply cleanly one method off; the script counts
the file's index -> worktree removals before and after, restores the file's index entry if they grew, and
fails. Fall back to `-CutFile` / `-Replace` for that file. (#5959: two whole test methods landed one
method down, silently.) Simpler when the refused hunk belongs to one commit: commit that file's other
hunks first, so the refused one is the file's whole remaining diff and stages with a plain `git add`
(#5943 round 5).

`-AddFile <path> -Add '<start>|||<anchor>', ...` is the build-up inverse of `-CutFile`, for when most of a
file's diff belongs to *later* commits: it takes the file's **index** content and inserts each working-tree
span (start marker up to, not including, the anchor) before the same anchor there. The anchor must occur once
in the index content; the start marker must not occur there yet. The index version is checked out through
git's own eol / attribute conversion, so a CRLF working tree over an LF index needs no handling. (#5943 A-11:
a test file whose two new methods went to two commits and whose remaining edits went to a third.)

`-Add '<start>|||<end>|||<anchor>'` splits the two roles when the text after the span exists only in the
working tree - the span is interleaved with a later commit's additions, so nothing that follows it is in the
index yet. The span runs from `<start>` up to, not including, `<end>` (both in the working tree, `<end>`
after `<start>`), and is inserted before `<anchor>` in the index content. (#6181: the earlier commit's test
block sat between two later-commit blocks; it was staged by hand with `hash-object` / `update-index` before
this form existed.)

**Invoke it directly, never via `pwsh -NoProfile -File`** - that form flattens `-Hunks 6,18` into
the single string `"6,18"`, which binds to `[int[]]` as `618` and throws an out-of-range error
naming a hunk that does not exist. See `script-authoring.md`.
#>
param(
    [Parameter(Mandatory)][string]$Worktree,
    [int[]]$Hunks,
    [string]$Split,
    [switch]$ListOnly,
    [string]$CutFile,
    [string[]]$Cut,
    [string[]]$Replace,
    [string]$AddFile,
    [string[]]$Add
)

$ErrorActionPreference = 'Stop'

# Scratch goes under .build/.agents, never beside the script (agent-rules.md -> Temp files).
$scratchDir = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) '.build/.agents'
if (-not (Test-Path $scratchDir)) { New-Item -ItemType Directory -Path $scratchDir -Force | Out-Null }

function Read-TextWithBom([string]$path) {
    $head = [System.IO.File]::ReadAllBytes($path) | Select-Object -First 3
    [pscustomobject]@{
        HasBom = $head.Count -eq 3 -and $head[0] -eq 0xEF -and $head[1] -eq 0xBB -and $head[2] -eq 0xBF
        Text   = [System.IO.File]::ReadAllText($path, [System.Text.UTF8Encoding]::new($false))
    }
}

function Set-IndexContent([string]$path, [string]$text, [bool]$hasBom) {
    $blobPath = Join-Path $scratchDir 'stage-hunks-cut.tmp'
    [System.IO.File]::WriteAllText($blobPath, $text, [System.Text.UTF8Encoding]::new($hasBom))

    # --path applies the file's attributes / eol conversion, as `git add` would.
    $sha = & git -C $Worktree hash-object -w "--path=$path" $blobPath
    if ($LASTEXITCODE -ne 0) { throw "git hash-object failed ($LASTEXITCODE)" }
    $entry = & git -C $Worktree ls-files -s -- $path
    $mode  = if ($entry) { $entry.Split(' ')[0] } else { '100644' }
    & git -C $Worktree update-index --add --cacheinfo "$mode,$sha,$path"
    if ($LASTEXITCODE -ne 0) { throw "git update-index failed ($LASTEXITCODE)" }
}

if ($AddFile -or $Add) {
    if (-not $AddFile -or -not $Add) { throw '-AddFile goes with -Add' }
    if ($CutFile -or $Cut -or $Replace) { throw '-AddFile and -CutFile are separate calls' }

    $work = (Read-TextWithBom (Join-Path $Worktree $AddFile)).Text

    # The index version, smudged as a checkout would, so its line endings match the working tree's.
    # checkout-index creates the path's directories below the prefix, not the prefix itself.
    $prefix = Join-Path $scratchDir 'stage-hunks-index'
    New-Item -ItemType Directory -Path $prefix -Force | Out-Null
    & git -C $Worktree checkout-index -f "--prefix=$($prefix.Replace('\', '/'))/" -- $AddFile
    if ($LASTEXITCODE -ne 0) { throw "git checkout-index failed ($LASTEXITCODE) - is $AddFile in the index?" }
    $index = Read-TextWithBom (Join-Path $prefix $AddFile)
    $text  = $index.Text

    foreach ($span in $Add) {
        $markers = $span -split '\|\|\|'
        if ($markers.Count -notin 2, 3) { throw "malformed -Add '$span' - expected '<start>|||<anchor>' or '<start>|||<end>|||<anchor>'" }

        $start  = $markers[0]
        $end    = $markers[1]
        $anchor = $markers[$markers.Count - 1]

        $s = $work.IndexOf($start, [System.StringComparison]::Ordinal)
        if ($s -lt 0) { throw "start marker not found in the working tree's ${AddFile}: $start" }
        if ($work.IndexOf($start, $s + 1, [System.StringComparison]::Ordinal) -ge 0) { throw "start marker not unique in the working tree's ${AddFile}: $start" }
        $e = $work.IndexOf($end, $s, [System.StringComparison]::Ordinal)
        if ($e -lt 0) { throw "end marker not found after the start marker in the working tree's ${AddFile}: $end" }

        if ($text.IndexOf($start, [System.StringComparison]::Ordinal) -ge 0) { throw "start marker already in the index content of ${AddFile}: $start" }
        $i = $text.IndexOf($anchor, [System.StringComparison]::Ordinal)
        if ($i -lt 0) { throw "anchor not found in the index content of ${AddFile}: $anchor" }
        if ($text.IndexOf($anchor, $i + 1, [System.StringComparison]::Ordinal) -ge 0) { throw "anchor not unique in the index content of ${AddFile}: $anchor" }

        $text = $text.Insert($i, $work.Substring($s, $e - $s))
    }

    Set-IndexContent $AddFile $text $index.HasBom
    Remove-Item -LiteralPath (Join-Path $prefix $AddFile) -Force
    "staged $AddFile with $($Add.Count) span(s) added"
    return
}

if ($CutFile -or $Cut -or $Replace) {
    if (-not $CutFile -or -not ($Cut -or $Replace)) { throw '-CutFile goes with -Cut and/or -Replace' }

    # ReadAllText drops a UTF-8 BOM; write it back when the file had one, or the staged blob loses it (#6008).
    $source = Read-TextWithBom (Join-Path $Worktree $CutFile)
    $hasBom = $source.HasBom
    $text   = $source.Text

    # A replacement restores a line the later commit changed; a cut can only drop text. Both must match once.
    foreach ($pair in $Replace) {
        $parts = $pair -split '\|\|\|'
        if ($parts.Count -ne 2) { throw "malformed -Replace '$pair' - expected '<old>|||<new>'" }

        $s = $text.IndexOf($parts[0], [System.StringComparison]::Ordinal)
        if ($s -lt 0) { throw "-Replace text not found in ${CutFile}: $($parts[0])" }
        if ($text.IndexOf($parts[0], $s + 1, [System.StringComparison]::Ordinal) -ge 0) { throw "-Replace text not unique in ${CutFile}: $($parts[0])" }
        $text = $text.Remove($s, $parts[0].Length).Insert($s, $parts[1])
    }

    foreach ($span in $Cut) {
        $markers = $span -split '\|\|\|'
        if ($markers.Count -ne 2) { throw "malformed -Cut '$span' - expected '<start>|||<end>'" }

        $s = $text.IndexOf($markers[0], [System.StringComparison]::Ordinal)
        if ($s -lt 0) { throw "start marker not found in ${CutFile}: $($markers[0])" }
        if ($text.IndexOf($markers[0], $s + 1, [System.StringComparison]::Ordinal) -ge 0) { throw "start marker not unique in ${CutFile}: $($markers[0])" }
        $e = $text.IndexOf($markers[1], $s, [System.StringComparison]::Ordinal)
        if ($e -lt 0) { throw "end marker not found in ${CutFile}: $($markers[1])" }
        $e += $markers[1].Length

        # Take the end-of-line and the blank line after the span too, so no stray blank line is left.
        for ($k = 0; $k -lt 2; $k++) {
            if ($text.Length -ge $e + 2 -and $text.Substring($e, 2) -eq "`r`n") { $e += 2 }
            elseif ($text.Length -ge $e + 1 -and $text[$e] -eq "`n") { $e += 1 }
        }
        $text = $text.Remove($s, $e - $s)
    }

    Set-IndexContent $CutFile $text $hasBom

    "staged $CutFile with $($Cut.Count) span(s) cut, $($Replace.Count) replacement(s)"
    return
}

if (-not $Hunks -and -not $ListOnly) { throw 'pass -Hunks, -ListOnly, -CutFile with -Cut / -Replace, or -AddFile with -Add' }

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

# With one line of context, an addition hunk whose context line repeats (`/// <summary>`, a blank line) can
# apply cleanly at the wrong occurrence. Staged where the working tree has it, a hunk only removes lines from
# the index -> worktree diff; staged elsewhere, it adds removals there. So count them before and after.
function Get-RemovalCount([string]$path) {
    @(& git -C $Worktree diff -U0 -- $path | Where-Object { $_ -match '^-' -and $_ -notmatch '^---' }).Count
}

$touched = @{}
foreach ($n in $Hunks) {
    $path = ($lines[$hunkList[$n - 1].Header[0]] -replace '^diff --git a/', '' -replace ' b/.*', '').TrimEnd()
    if (-not $touched.ContainsKey($path)) {
        $touched[$path] = [pscustomobject]@{ Entry = (& git -C $Worktree ls-files -s -- $path); Removals = (Get-RemovalCount $path) }
    }
}

& git -C $Worktree apply --cached --whitespace=nowarn $stepPath
if ($LASTEXITCODE -ne 0) { throw "git apply --cached failed ($LASTEXITCODE); patch left at $stepPath" }

$misplaced = @($touched.Keys | Where-Object { (Get-RemovalCount $_) -gt $touched[$_].Removals })
if ($misplaced.Count -gt 0) {
    foreach ($path in $misplaced) {
        $entry = $touched[$path].Entry
        if ($entry) {
            $parts = $entry -split '\s+'
            & git -C $Worktree update-index --cacheinfo "$($parts[0]),$($parts[1]),$path"
        }
        else {
            & git -C $Worktree update-index --force-remove -- $path
        }
    }
    throw "a hunk landed at the wrong place in $($misplaced -join ', ') (its context line repeats); index restored for those files - stage them with -CutFile / -Replace instead"
}

"staged hunks: $($Hunks -join ', ')"
