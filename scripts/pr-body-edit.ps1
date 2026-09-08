#!/usr/bin/env pwsh
<#
Insert new content into a GitHub PR body at one or more ASCII anchors, in a
single allowlisted pwsh call. Solves two recurring problems when editing a PR
body from an automated agent session on Windows (Git Bash + pwsh):

  1. **Encoding.** `gh pr view` / `gh api … --jq '.body'` stdout arriving via
     Git Bash + pwsh gets decoded through the Windows console code page (cp850
     on most non-English locales), so any non-ASCII character in the body
     (emoji, em-dash, accented letters) becomes a 3–4 character garble in the
     pwsh string. Subsequent string matching / replacement then silently fails
     or — worse — pushes the garbled bytes back to GitHub.
  2. **Permission friction.** A scratch "fetch body, mutate, push" pwsh loop
     is typically 3–5 iterations because each round hits a fresh encoding /
     stringification surprise. Every retry is a new `Bash(pwsh -File ...)`
     command string that the allowlist evaluates afresh.

This script sidesteps both by:

  - Using `Invoke-Gh` from `_shared.ps1` (UTF-8 stdio on the process pipes).
  - Reading the current body via `gh api` into a temp file and then loading
    it with `[System.IO.File]::ReadAllText(path, UTF8NoBom)`.
  - Writing the new body back the same way.
  - Presenting a single allowlist rule:
        Bash(pwsh -NoProfile -File .claude/scripts/pr-body-edit.ps1 *)

Contract
--------

Input (stdin, JSON):
  {
    "pr":      5479,                       // required, int
    "owner":   "linq2db",                  // optional, default "linq2db"
    "repo":    "linq2db",                  // optional, default "linq2db"
    "insertions": [                        // required, non-empty
      {
        "anchor":   "## Test plan",        // ASCII literal, must match exactly once (or matchCount: "first"/"last" when multiple allowed)
        "position": "before",              // "before" | "after"; default "before"
        "text":     "…full text block…"    // inserted verbatim; caller is responsible for leading/trailing blank lines
                                           // NOTE with position "after": the insertion is spliced immediately after
                                           // the matched STRING, not after the line containing it. The two coincide
                                           // only when the anchor IS the whole line — which every example here is —
                                           // so a SUBSTRING anchor splits its line and strands the tail after your
                                           // inserted block. Anchor the entire line, and always -dryRun first and
                                           // read bodyAfter: that is what catches it.
                                           // Given the above, a single leading "\n" only terminates the anchor line
                                           // and yields no blank line. An inserted "## Heading" then sits flush
                                           // against the anchor paragraph (it still renders — ATX headings may
                                           // interrupt a paragraph — but it is the one heading in the body without
                                           // a blank line before it). Use TWO leading newlines when the text starts
                                           // with a heading.
      },
      {
        "anchor":   "## Checklist",
        "position": "before",
        "text":     "…"
      }
    ],
    "replacements": [                      // optional; either this or `insertions` must be non-empty
      {
        "old":        "- Analyzer fixtures: **12/12**.",   // literal, matched Ordinal; MAY contain non-ASCII (see below)
        "new":        "- Analyzer fixtures: **37/37**.",   // "" deletes
        "matchCount": "one"                                // "one" (default) | "first" | "last" | "all"
      }
    ],
    "dryRun":  false,                      // optional, default false — when true, compute and write the candidate body but don't call `gh pr edit`
    "workDir": ".build/.agents"            // optional — where to stage the before/after body files; default ".build/.agents"
  }

`replacements` exist because the common edit to a *stale* body is a correction, not an
append: a fixture count that moved, a caveat that a later CI run discharged, a claim a
follow-up commit falsified. Expressing that as an insertion leaves the wrong sentence in
place directly above the right one.

**Replacements run before insertions**, so both are written against a body state the
caller can see: a replacement reasons about the body as it stands, while an insertion
anchor is frequently a heading some replacement may have just reworded.

Unlike an insertion `anchor`, a replacement's `old` **may contain non-ASCII**. The ASCII
restriction on anchors guards against console-code-page mangling, which `Invoke-Gh`'s
UTF-8 pipe already eliminates here — and a correction to existing prose in this repo's PR
bodies almost always has to match an em-dash or an arrow. `old` not being found, or being
found more than once under the default `matchCount: "one"`, is a hard error: a body edit
that silently matches the wrong occurrence is worse than one that fails.

Blank lines around an insertion are the CALLER's job, and the off-by-one bites.
`text` is inserted verbatim at the anchor boundary, so when the anchor is the last
text on its line and `position` is `"after"`, the insertion begins immediately after
that character - there is no implicit newline. A `text` that starts with a single
newline therefore yields:

    ...end of previous paragraph.
    ## My New Heading

i.e. a heading glued to the paragraph above it. GitHub still renders it as a heading
(ATX headings need no preceding blank line), so the mistake is invisible in the
rendered view and only shows in the source - which is exactly how it survives. Use
**two** leading newlines to get a blank line, and one trailing newline if the anchor
resumes text below. Note the script collapses runs of 3+ blank lines, so over-padding
is safe while under-padding is not.

Rules for `anchor`:
  - Must be ASCII (any UTF-8 is technically accepted but defeats the whole point — the script will reject non-ASCII anchors with a clear error).
  - Must appear in the body. By default must appear EXACTLY ONCE; callers that want the first or last of many duplicates can pass `"matchCount": "first"` or `"matchCount": "last"` on the entry.
  - String-literal match, not regex.

Output (stdout, JSON):
  {
    "pr":          5479,
    "url":         "https://github.com/linq2db/linq2db/pull/5479",
    "applied":     true,                   // false when dryRun
    "bodyBefore":  ".build/.agents/pr5479-body-before.txt",
    "bodyAfter":   ".build/.agents/pr5479-body-after.txt",
    "insertions": [
      { "anchor": "## Test plan", "position": "before", "ok": true, "insertedAt": 3912 },
      { "anchor": "## Checklist", "position": "before", "ok": true, "insertedAt": 7013 }
    ],
    "diffStat": { "charsBefore": 8012, "charsAfter": 8741 }
  }

Exit codes:
  0 = success (all insertions applied, optional `gh pr edit` succeeded)
  1 = hard failure (bad input, anchor not found, gh error, etc.)
#>

param([string]$ManifestFile)

$global:ScriptBaseName = 'pr-body-edit'
. "$PSScriptRoot/_shared.ps1"

$m = Read-ManifestFromFileOrStdin -ManifestFile $ManifestFile

if (-not (Test-IsInteger $m.pr) -or [long]$m.pr -le 0) { Exit-WithError 'pr (positive integer) required' }
$pr    = [int]$m.pr
$owner = if ($m.owner) { [string]$m.owner } else { 'linq2db' }
$repo  = if ($m.repo)  { [string]$m.repo  } else { 'linq2db' }
$repoFull = "$owner/$repo"
$dryRun   = [bool]$m.dryRun
$workDir  = if ($m.workDir) { [string]$m.workDir } else { '.build/.agents' }

$hasInsertions   = $m.insertions   -and @($m.insertions).Count   -gt 0
$hasReplacements = $m.replacements -and @($m.replacements).Count -gt 0
if (-not $hasInsertions -and -not $hasReplacements) {
    Exit-WithError 'insertions or replacements (at least one non-empty array) required'
}

# --- Normalise replacement entries ----------------------------------------
# Unlike an insertion anchor, `old` MAY contain non-ASCII: the body is read through
# Invoke-Gh's UTF-8 pipe, so em-dashes and arrows round-trip intact, and a correction
# to existing prose almost always has to match some.
$replacements = @()
$ridx = 0
foreach ($rep in @(if ($hasReplacements) { $m.replacements })) {
    $ridx++
    if ($null -eq $rep.old -or -not ([string]$rep.old)) { Exit-WithError "replacements[$ridx].old is required" }
    if ($null -eq $rep.new) { Exit-WithError "replacements[$ridx].new is required (use an empty string to delete)" }
    $rMatchCount = if ($rep.matchCount) { [string]$rep.matchCount } else { 'one' }
    if ($rMatchCount -notin @('one','first','last','all')) {
        Exit-WithError "replacements[$ridx].matchCount must be 'one', 'first', 'last', or 'all'"
    }
    $replacements += [pscustomobject]@{
        old        = [string]$rep.old
        new        = [string]$rep.new
        matchCount = $rMatchCount
    }
}

# --- Normalise insertion entries ------------------------------------------
$entries = @()
$idx = 0
foreach ($ins in @(if ($hasInsertions) { $m.insertions })) {
    $idx++
    if (-not $ins.anchor -or -not ([string]$ins.anchor)) { Exit-WithError "insertions[$idx].anchor is required" }
    $anchor = [string]$ins.anchor
    if ($anchor -cmatch '[^\x00-\x7F]') {
        Exit-WithError "insertions[$idx].anchor contains non-ASCII characters; anchors must be ASCII to survive round-tripping through native-command stdout"
    }
    $position = if ($ins.position) { [string]$ins.position } else { 'before' }
    if ($position -ne 'before' -and $position -ne 'after') {
        Exit-WithError "insertions[$idx].position must be 'before' or 'after'"
    }
    if ($null -eq $ins.text) { Exit-WithError "insertions[$idx].text is required" }
    $text = [string]$ins.text
    $matchCount = if ($ins.matchCount) { [string]$ins.matchCount } else { 'one' }
    if ($matchCount -notin @('one','first','last')) {
        Exit-WithError "insertions[$idx].matchCount must be 'one', 'first', or 'last'"
    }
    $entries += [pscustomobject]@{
        anchor     = $anchor
        position   = $position
        text       = $text
        matchCount = $matchCount
    }
}

# --- Fetch current body via file roundtrip (avoids console code-page decoding) -----
[void][System.IO.Directory]::CreateDirectory($workDir)
$bodyBeforePath = Join-Path $workDir "pr$pr-body-before.txt"
$bodyAfterPath  = Join-Path $workDir "pr$pr-body-after.txt"

$getResult = Invoke-Gh -ArgumentList @('api', "repos/$repoFull/pulls/$pr", '--jq', '.body')
if (-not $getResult.ok) { Exit-WithError "gh api pulls/$pr failed: $($getResult.error)" }
$body = $getResult.stdout
# `gh api --jq '.body'` appends a trailing newline; strip it so we don't grow the body on every edit
if ($body.EndsWith("`n")) { $body = $body.Substring(0, $body.Length - 1) }
# Normalise CRLF → LF so anchor matching and inserted text are EOL-agnostic
$body = $body.Replace("`r`n", "`n")

$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
# Use GetFullPath against pwsh's current location so relative workDir values
# resolve under the repo root (not against .NET's Environment.CurrentDirectory,
# which can diverge from Get-Location), while absolute workDir values pass
# through unchanged.
$bodyBeforeAbs = [System.IO.Path]::GetFullPath($bodyBeforePath, (Get-Location).Path)
$bodyAfterAbs  = [System.IO.Path]::GetFullPath($bodyAfterPath,  (Get-Location).Path)
[System.IO.File]::WriteAllText($bodyBeforeAbs, $body, $utf8NoBom)

# --- Apply replacements first, then insertions ------------------------------
# Order is fixed and deliberate: a caller writing a replacement reasons about the
# body as it stands today, while an insertion anchor is often a heading that a
# replacement may have just reworded. Doing replacements first means both are
# expressed against a state the caller can see.
$replacementResults = @()
foreach ($r in $replacements) {
    $indices = @()
    $from = 0
    while ($true) {
        $pos = $body.IndexOf($r.old, $from, [System.StringComparison]::Ordinal)
        if ($pos -lt 0) { break }
        $indices += $pos
        $from = $pos + 1
    }
    if ($indices.Count -eq 0) {
        Exit-WithError "replacement 'old' not found in PR body: $($r.old)"
    }
    if ($indices.Count -gt 1 -and $r.matchCount -eq 'one') {
        Exit-WithError "replacement 'old' appears $($indices.Count) times in PR body; set matchCount to 'first', 'last' or 'all' if that is intended: $($r.old)"
    }
    switch ($r.matchCount) {
        'all' {
            $body = $body.Replace($r.old, $r.new)
            $replacedAt = $indices
        }
        'last' {
            $at   = $indices[-1]
            $body = $body.Substring(0, $at) + $r.new + $body.Substring($at + $r.old.Length)
            $replacedAt = @($at)
        }
        default {
            $at   = $indices[0]
            $body = $body.Substring(0, $at) + $r.new + $body.Substring($at + $r.old.Length)
            $replacedAt = @($at)
        }
    }
    $replacementResults += [pscustomobject]@{
        old        = $r.old
        matchCount = $r.matchCount
        ok         = $true
        matched    = $indices.Count
        replacedAt = $replacedAt
    }
}

# --- Apply each insertion sequentially -------------------------------------
$results = @()
foreach ($e in $entries) {
    $indices = @()
    $from = 0
    while ($true) {
        $pos = $body.IndexOf($e.anchor, $from, [System.StringComparison]::Ordinal)
        if ($pos -lt 0) { break }
        $indices += $pos
        $from = $pos + 1
    }
    if ($indices.Count -eq 0) {
        Exit-WithError "anchor not found in PR body: $($e.anchor)"
    }
    if ($indices.Count -gt 1 -and $e.matchCount -eq 'one') {
        Exit-WithError "anchor appears $($indices.Count) times in PR body; set matchCount to 'first' or 'last' if duplicates are expected: $($e.anchor)"
    }
    $target = switch ($e.matchCount) {
        'last'  { $indices[-1] }
        default { $indices[0] }
    }
    $insertAt = if ($e.position -eq 'before') { $target } else { $target + $e.anchor.Length }
    # $body is rebuilt here so subsequent insertions search against the already-updated text.
    # Consequence: anchor offsets returned in the result are into the FINAL body, not the original.
    $body = $body.Substring(0, $insertAt) + $e.text + $body.Substring($insertAt)
    $results += [pscustomobject]@{
        anchor     = $e.anchor
        position   = $e.position
        ok         = $true
        insertedAt = $insertAt
    }
}

# --- Collapse triple+ blank-line runs introduced by concatenation -----------
# Not always desired, but common enough that we do it by default. Callers who
# need exact whitespace preservation should shape their `text` payloads to
# avoid leading/trailing blank lines beyond one each.
$body = $body -replace "\n{3,}", "`n`n"

[System.IO.File]::WriteAllText($bodyAfterAbs, $body, $utf8NoBom)

$applied = $false
if (-not $dryRun) {
    $editResult = Invoke-Gh -ArgumentList @('pr', 'edit', "$pr", '--repo', $repoFull, '--body-file', $bodyAfterPath)
    if (-not $editResult.ok) { Exit-WithError "gh pr edit $pr failed: $($editResult.error)" }
    $applied = $true
}

Write-JsonOutput ([pscustomobject]@{
    pr         = $pr
    url        = "https://github.com/$repoFull/pull/$pr"
    applied    = $applied
    dryRun     = $dryRun
    bodyBefore   = $bodyBeforePath
    bodyAfter    = $bodyAfterPath
    insertions   = $results
    replacements = $replacementResults
    diffStat   = [pscustomobject]@{
        charsBefore = (Get-Content -LiteralPath $bodyBeforePath -Raw -Encoding utf8).Length
        charsAfter  = $body.Length
    }
})
