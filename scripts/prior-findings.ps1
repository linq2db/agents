#!/usr/bin/env pwsh
<#
Collect the current user's prior findings on a PR - `/verify-review` step 3 - from the
context `pr-context.ps1 -OutFile` saved, and hand them to the verify-mode `code-reviewer`.

Why this script exists
----------------------
Step 3 is a parse, not a judgement: which of our review comments and body lines carry a
finding ID, which thread each one lives in and whether it is resolved, what the author
replied, which body checkboxes are still open, and the next free ID per severity. By hand it
was a fresh builder script every round, and its reply matching (same path and line, a later
id) breaks once a thread spans rounds. `in_reply_to_id` makes it exact.

    pwsh -NoProfile -File .claude/scripts/prior-findings.ps1 -Pr 5987

Input (named parameters)
------------------------
  -Pr <n>               required
  -ContextFile <path>   default .build/.agents/pr<n>-context.json; must come from a
                        pr-context.ps1 that emits `in_reply_to_id`
  -OutFile <path>       default .build/.agents/pr<n>-prior-findings.json
  -User <login>         default: the context's `currentUser`

Output
------
The JSON goes to -OutFile; stdout carries one summary line (see Write-JsonOutput).
  {
    pr, user, prAuthor, headSha,
    latestOwnReview:  { id, state, submitted_at, commit_id } | null,
    pendingOwnReview: { id, commit_id } | null,   // replaced, never PUT - verify-review step 2
    idFloor:   { BLK, MAJ, MIN, SUG, NIT },       // max ID per severity in our reviews + 1
    findings:  [ {
      id, severity, number,
      location: { kind: line|file|body, review_id, review_state, comment_id, node_id,
                  thread_id, thread_resolved, resolved_by, path, line, original_line, commit_id },
      checkbox,                                   // body findings only: ' ' | 'x' | '~'
      original_text,
      replies: [ { user, id, created_at, body } ],
      alsoAt:  [ <earlier location> ]             // the same ID posted before; newest wins
    } ],
    unnumbered:     [ ... ],  // our thread-starting comments with no ID (out-of-scope notes, FYIs)
    openNotes:      [ { review_id, text } ],      // unchecked body checkboxes that carry no ID
    authorComments: [ { id, created_at, body } ]  // PR-author conversation comments after our latest review
  }

An ID counts as a finding only where it opens a comment (`**Major · MAJ001**`) or a body
checkbox line (`- [ ] **MAJ001** —`). An ID mentioned in prose still raises the floor.

Exit codes
----------
  0 = success
  1 = hard failure (missing or too old context file)
#>

param(
    [Parameter(Mandatory)][int]$Pr,
    [string]$ContextFile,
    [string]$OutFile,
    [string]$User
)

$global:ScriptBaseName = 'prior-findings'
. "$PSScriptRoot/_shared.ps1"

if (-not $ContextFile) { $ContextFile = ".build/.agents/pr$Pr-context.json" }
if (-not $OutFile)     { $OutFile     = ".build/.agents/pr$Pr-prior-findings.json" }

if (-not (Test-Path -LiteralPath $ContextFile -PathType Leaf)) {
    Exit-WithError "context file not found: $ContextFile" -NextAction "run pr-context.ps1 -Pr $Pr -OutFile $ContextFile first"
}

$contextPath = (Resolve-Path -LiteralPath $ContextFile).Path
$ctx = [System.IO.File]::ReadAllText($contextPath, [System.Text.UTF8Encoding]::new($false)) | ConvertFrom-Json -Depth 100

$comments = @($ctx.reviewComments)
if ($comments.Count -gt 0 -and -not ($comments[0].PSObject.Properties.Name -contains 'in_reply_to_id')) {
    Exit-WithError "context file predates in_reply_to_id: $ContextFile" -NextAction "re-run pr-context.ps1 -Pr $Pr -OutFile $ContextFile"
}

if (-not $User) { $User = [string]$ctx.currentUser }
if (-not $User) { Exit-WithError 'no -User given and the context carries no currentUser' }

$prAuthor = [string]$ctx.pr.author.login

$idRegex    = [regex]'\b(BLK|MAJ|MIN|SUG|NIT)(\d{3})\b'
$severities = 'BLK', 'MAJ', 'MIN', 'SUG', 'NIT'
$maxBySev   = @{}
foreach ($s in $severities) { $maxBySev[$s] = 0 }

function Add-Ids([string]$Text) {
    if (-not $Text) { return }
    foreach ($m in $idRegex.Matches($Text)) {
        $n = [int]$m.Groups[2].Value
        if ($n -gt $maxBySev[$m.Groups[1].Value]) { $maxBySev[$m.Groups[1].Value] = $n }
    }
}

function Get-Time($Value) {
    if (-not $Value) { return [datetimeoffset]::MaxValue }
    return [datetimeoffset]$Value
}

$threadByFirst = @{}
foreach ($t in @($ctx.reviewThreads)) {
    if ($null -ne $t.firstCommentId) { $threadByFirst[[long]$t.firstCommentId] = $t }
}

$reviewById = @{}
foreach ($r in @($ctx.reviews)) { $reviewById[[long]$r.id] = $r }

$ownReviews = @($ctx.reviews | Where-Object { $_.user -eq $User })

$repliesByParent = @{}
foreach ($c in $comments) {
    if ($null -eq $c.in_reply_to_id) { continue }
    $key = [long]$c.in_reply_to_id
    if (-not $repliesByParent.ContainsKey($key)) { $repliesByParent[$key] = [System.Collections.Generic.List[object]]::new() }
    $repliesByParent[$key].Add([ordered]@{ user = $c.user; id = $c.id; created_at = $c.created_at; body = [string]$c.body })
}

$candidates = [System.Collections.Generic.List[object]]::new()
$unnumbered = [System.Collections.Generic.List[object]]::new()
$openNotes  = [System.Collections.Generic.List[object]]::new()

foreach ($c in ($comments | Where-Object { $_.user -eq $User } | Sort-Object { [long]$_.id })) {
    $body = [string]$c.body
    Add-Ids $body

    if ($null -ne $c.in_reply_to_id) { continue }

    $thread = $threadByFirst[[long]$c.id]
    $review = $reviewById[[long]$c.pull_request_review_id]

    $location = [ordered]@{
        kind            = if ($c.subject_type -eq 'file') { 'file' } else { 'line' }
        review_id       = $c.pull_request_review_id
        review_state    = if ($review) { $review.state } else { $null }
        comment_id      = $c.id
        node_id         = $c.node_id
        thread_id       = if ($thread) { $thread.threadId } else { $null }
        thread_resolved = if ($thread) { [bool]$thread.isResolved } else { $null }
        resolved_by     = if ($thread) { $thread.resolvedBy } else { $null }
        path            = $c.path
        line            = $c.line
        original_line   = $c.original_line
        commit_id       = $c.commit_id
    }

    # Assigned, not taken from an if/else expression, which unrolls an empty array to $null.
    $replies = @()
    if ($repliesByParent.ContainsKey([long]$c.id)) { $replies = @($repliesByParent[[long]$c.id]) }
    $first    = ($body -split "`n" | Where-Object { $_.Trim() } | Select-Object -First 1)
    $idMatch  = if ($first) { $idRegex.Match($first) } else { $null }

    if ($idMatch -and $idMatch.Success) {
        $candidates.Add([ordered]@{
            id            = $idMatch.Value
            severity      = $idMatch.Groups[1].Value
            number        = [int]$idMatch.Groups[2].Value
            time          = Get-Time $c.created_at
            location      = $location
            checkbox      = $null
            original_text = $body
            replies       = $replies
        })
    }
    else {
        $unnumbered.Add([ordered]@{
            label         = if ($first) { $first.Substring(0, [Math]::Min(100, $first.Length)) } else { '' }
            location      = $location
            original_text = $body
            replies       = $replies
        })
    }
}

$checkboxLine = [regex]'^\s*- \[( |x|X|~)\] (.*)$'
$findingStart = [regex]'^\*\*(BLK|MAJ|MIN|SUG|NIT)(\d{3})\*\*'

foreach ($r in $ownReviews) {
    $body = [string]$r.body
    Add-Ids $body
    if (-not $body) { continue }

    $lines = $body -split "`n"
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $cb = $checkboxLine.Match($lines[$i].TrimEnd("`r"))
        if (-not $cb.Success) { continue }

        # A checkbox item runs on over its indented continuation lines (Why / Fix / sub-bullets).
        $text = [System.Text.StringBuilder]::new($lines[$i].TrimEnd("`r"))
        for ($j = $i + 1; $j -lt $lines.Count; $j++) {
            $next = $lines[$j].TrimEnd("`r")
            if (-not $next.Trim() -or $next -notmatch '^\s') { break }
            [void]$text.Append("`n").Append($next)
        }

        $state = $cb.Groups[1].Value.ToLowerInvariant()
        $id    = $findingStart.Match($cb.Groups[2].Value)

        if ($id.Success) {
            $candidates.Add([ordered]@{
                id            = "$($id.Groups[1].Value)$($id.Groups[2].Value)"
                severity      = $id.Groups[1].Value
                number        = [int]$id.Groups[2].Value
                time          = Get-Time $r.submitted_at
                location      = [ordered]@{ kind = 'body'; review_id = $r.id; review_state = $r.state; commit_id = $r.commit_id }
                checkbox      = $state
                original_text = $text.ToString()
                replies       = @()
            })
        }
        elseif ($state -eq ' ') {
            $openNotes.Add([ordered]@{ review_id = $r.id; text = $text.ToString() })
        }
    }
}

# One entry per ID: the most recent location is the one to act on, earlier ones ride along.
$findings = foreach ($group in ($candidates | Group-Object { $_.id })) {
    $ordered = @($group.Group | Sort-Object { $_.time } -Descending)
    $primary = $ordered[0]
    $entry = [ordered]@{}
    foreach ($k in $primary.Keys) { if ($k -ne 'time') { $entry[$k] = $primary[$k] } }
    $entry.alsoAt = @($ordered | Select-Object -Skip 1 | ForEach-Object { $_.location })
    $entry
}
$severityRank = @{ BLK = 0; MAJ = 1; MIN = 2; SUG = 3; NIT = 4 }
$findings = @($findings | Sort-Object { $severityRank[$_.severity] }, { $_.number })

$idFloor = [ordered]@{}
foreach ($s in $severities) { $idFloor[$s] = $maxBySev[$s] + 1 }

$submitted = @($ownReviews | Where-Object { $_.submitted_at } | Sort-Object { [datetimeoffset]$_.submitted_at } -Descending)
$latest    = if ($submitted.Count -gt 0) { $submitted[0] } else { $null }
$pending   = @($ownReviews | Where-Object { $_.state -eq 'PENDING' }) | Select-Object -First 1

$since = if ($latest) { [datetimeoffset]$latest.submitted_at } else { [datetimeoffset]::MinValue }
$authorComments = @($ctx.issueComments |
    Where-Object { $_.user -eq $prAuthor -and $_.created_at -and [datetimeoffset]$_.created_at -gt $since } |
    ForEach-Object { [ordered]@{ id = $_.id; created_at = $_.created_at; body = [string]$_.body } })

Write-JsonOutput ([ordered]@{
    pr               = $Pr
    user             = $User
    prAuthor         = $prAuthor
    headSha          = $ctx.headSha
    latestOwnReview  = if ($latest) { [ordered]@{ id = $latest.id; state = $latest.state; submitted_at = $latest.submitted_at; commit_id = $latest.commit_id } } else { $null }
    pendingOwnReview = if ($pending) { [ordered]@{ id = $pending.id; commit_id = $pending.commit_id } } else { $null }
    idFloor          = $idFloor
    findings         = @($findings)
    unnumbered       = @($unnumbered)
    openNotes        = @($openNotes)
    authorComments   = $authorComments
}) -OutFile $OutFile -Summary ([ordered]@{
    findings         = @($findings).Count
    lineOrFile       = @($findings | Where-Object { $_.location.kind -ne 'body' }).Count
    body             = @($findings | Where-Object { $_.location.kind -eq 'body' }).Count
    unnumbered       = $unnumbered.Count
    openNotes        = $openNotes.Count
    authorComments   = $authorComments.Count
    idFloor          = ($severities | ForEach-Object { "$_$($idFloor[$_].ToString('000'))" }) -join ' '
    pendingOwnReview = if ($pending) { $pending.id } else { $null }
})
