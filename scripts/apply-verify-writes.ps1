#!/usr/bin/env pwsh
<#
Apply the in-place edit batch produced by `/verify-review` step 9 in one pwsh
process.

Why this wrapper exists
-----------------------
`/verify-review` decides per prior finding (see SKILL.md step 7 table):
  - fixed × line  → PATCH the comment body: append "— ✓ Fixed in <sha>"
  - fixed × file  → PATCH the comment body (same annotation)
  - fixed × body  → PUT the prior review body: flip `[ ]` → `[x]`
  - partial × body → PUT the prior review body: flip `[ ]` → `[~]`
  - plus optional per-thread GraphQL `resolveReviewThread` mutations

Done inline from the skill, this is 1 PATCH per fixed line/file comment + 1
PUT per edited review body + 1 GraphQL mutation per thread resolve. Each
unique command string triggers its own permission prompt. Done here, one
allowlist rule covers the whole batch:

    Bash(pwsh -NoProfile -File .claude/scripts/apply-verify-writes.ps1 *)

The script fetches the current comment body for each commentPatches[] entry
before PATCHing. That spares the caller from duplicating the original body
text in its manifest, and it keeps the append idempotent: if the exact
appendNote already appears anywhere in the current body, we skip the write
(and mark the entry `ok: true, skipped: "already annotated"`). Uniqueness
is carried by the run's HEAD SHA embedded in the note.

Input (stdin, JSON)
-------------------
  {
    "pr":            5414,                             // required, int
    "owner":         "linq2db",                        // optional, default "linq2db"
    "repo":          "linq2db",                        // optional, default "linq2db"
    "appendNote":    "— ✓ Fixed in 83d743bb",         // required when commentPatches[] is non-empty
    "commentPatches": [                                // optional — append `appendNote` to these comments
      3109629364, 3109629397                          //   bare integers OR { "commentId": N, "appendNote": "..." }
    ],                                                 //   (per-entry appendNote overrides the top-level default)
    "threadResolves": [                                // optional — resolveReviewThread mutations
      "PRRT_kwDOAB09RM58JUqw"                         //   bare strings OR { "threadId": "...", "label": "MIN001" }
    ],
    "checkboxFlips": [                                 // optional — tick a body finding's checkbox
      { "reviewId": 4138820911, "findingId": "MIN007", "mark": "x" }   // mark: "x" (fixed) or "~" (partial)
    ],
    "reviewBodyEdits": [                               // optional — PUT prior review body
      { "reviewId": 4138820911, "newBody": "<full replacement body>" }
    ],
    "concurrency": 6                                   // optional, default 6
  }

checkboxFlips fetch the review body and replace `- [ ] **<findingId>**` (initial
review) or `- [ ] <findingId>` (verification body), which must occur exactly once
at a line start (leading whitespace allowed, so a nested item flips too), so the caller never rebuilds a full body; flips on one
review go out as one PUT. A flip whose box already carries the mark is skipped.
A review may appear in checkboxFlips or reviewBodyEdits, not both.

A transient GitHub error (a 5xx, gh's "unexpected end of JSON input" for an
empty response, or a dropped connection's "unexpected EOF") is retried up to twice. A comment patch or checkbox flip re-reads
the stored body before each retry, because GitHub sometimes applies a write it
answered with an error; such an item reports `ok: true, recovered: "<error>"`, and
`ok: false` means the write is not in what GitHub stored. (#6430: three runs at
a 502-heavy hour reported writes as failed that had landed.)

Output (stdout, single JSON object):
  {
    "commentPatches":  [ { commentId, ok, skipped?, recovered?, error? } ],
    "threadResolves":  [ { threadId, label?, ok, isResolved?, error? } ],
    "checkboxFlips":   [ { reviewId, ok, flipped[], skipped[], storedLength?, recovered?, error? } ],
    "reviewBodyEdits": [ { reviewId, ok, storedLength?, error? } ]
  }

Exit codes
----------
  0 = every request succeeded (or was skipped as already-applied)
  1 = hard failure (bad input, missing required field, gh not on PATH)
  2 = at least one write failed; inspect the output for per-item `ok: false`
#>

param([string]$ManifestFile)

$global:ScriptBaseName = 'apply-verify-writes'
. "$PSScriptRoot/_shared.ps1"

$m = Read-ManifestFromFileOrStdin -ManifestFile $ManifestFile

if (-not (Test-IsInteger $m.pr) -or [long]$m.pr -le 0) { Exit-WithError 'pr (positive integer) required' }
$pr = [int]$m.pr
$owner = if ($m.owner) { [string]$m.owner } else { 'linq2db' }
$repo  = if ($m.repo)  { [string]$m.repo }  else { 'linq2db' }
$repoFull = "$owner/$repo"
$defaultAppendNote = if ($m.appendNote) { [string]$m.appendNote } else { '' }
$concurrency = if ((Test-IsInteger $m.concurrency) -and [long]$m.concurrency -gt 0) { [int]$m.concurrency } else { 6 }

# --- Normalise commentPatches input ---------------------------------------
$commentPatchJobs = @()
if ($m.commentPatches) {
    foreach ($entry in @($m.commentPatches)) {
        $cid = $null
        $note = $defaultAppendNote
        if (Test-IsInteger $entry) {
            $cid = [long]$entry
        } elseif ($entry -is [pscustomobject] -or $entry -is [hashtable]) {
            $obj = if ($entry -is [hashtable]) { [pscustomobject]$entry } else { $entry }
            if (Test-IsInteger $obj.commentId) { $cid = [long]$obj.commentId }
            if ($obj.appendNote) { $note = [string]$obj.appendNote }
        }
        if ($null -eq $cid) { Exit-WithError "commentPatches: each entry must be an integer id or { commentId, appendNote? }" }
        if (-not $note) { Exit-WithError "commentPatches[$cid]: no appendNote (set top-level appendNote or per-entry appendNote)" }
        $commentPatchJobs += [pscustomobject]@{ commentId = $cid; appendNote = $note }
    }
}

# --- Normalise threadResolves input ---------------------------------------
$threadResolveJobs = @()
if ($m.threadResolves) {
    foreach ($entry in @($m.threadResolves)) {
        $tid = $null
        $label = $null
        if ($entry -is [string]) {
            $tid = $entry
        } elseif ($entry -is [pscustomobject] -or $entry -is [hashtable]) {
            $obj = if ($entry -is [hashtable]) { [pscustomobject]$entry } else { $entry }
            if ($obj.threadId -is [string]) { $tid = [string]$obj.threadId }
            if ($obj.label) { $label = [string]$obj.label }
        }
        if (-not $tid) { Exit-WithError "threadResolves: each entry must be a string threadId or { threadId, label? }" }
        $threadResolveJobs += [pscustomobject]@{ threadId = $tid; label = $label }
    }
}

# --- Normalise reviewBodyEdits input --------------------------------------
$reviewBodyEditJobs = @()
if ($m.reviewBodyEdits) {
    foreach ($entry in @($m.reviewBodyEdits)) {
        $obj = if ($entry -is [hashtable]) { [pscustomobject]$entry } else { $entry }
        if (-not (Test-IsInteger $obj.reviewId)) { Exit-WithError "reviewBodyEdits: reviewId (integer) required" }
        if (-not ($obj.newBody -is [string])) { Exit-WithError "reviewBodyEdits[$($obj.reviewId)]: newBody (string) required" }
        $reviewBodyEditJobs += [pscustomobject]@{ reviewId = [long]$obj.reviewId; newBody = [string]$obj.newBody }
    }
}

# --- Normalise checkboxFlips input (grouped per review) -------------------
$checkboxFlipJobs = @()
if ($m.checkboxFlips) {
    $byReview = [ordered]@{}
    foreach ($entry in @($m.checkboxFlips)) {
        $obj = if ($entry -is [hashtable]) { [pscustomobject]$entry } else { $entry }
        if (-not (Test-IsInteger $obj.reviewId)) { Exit-WithError "checkboxFlips: reviewId (integer) required" }
        if (-not ([string]$obj.findingId -match '^(BLK|MAJ|MIN|SUG|NIT)\d{3}$')) { Exit-WithError "checkboxFlips[$($obj.reviewId)]: findingId like MIN007 required" }
        if ([string]$obj.mark -notin @('x', '~')) { Exit-WithError "checkboxFlips[$($obj.findingId)]: mark must be 'x' or '~'" }
        $rid = [long]$obj.reviewId
        if (@($reviewBodyEditJobs | Where-Object { $_.reviewId -eq $rid }).Count -gt 0) { Exit-WithError "review $rid is in both checkboxFlips and reviewBodyEdits" }
        if (-not $byReview.Contains($rid)) { $byReview[$rid] = @() }
        $byReview[$rid] += [pscustomobject]@{ findingId = [string]$obj.findingId; mark = [string]$obj.mark }
    }
    foreach ($rid in $byReview.Keys) { $checkboxFlipJobs += [pscustomobject]@{ reviewId = $rid; flips = @($byReview[$rid]) } }
}

$totalJobs = $commentPatchJobs.Count + $threadResolveJobs.Count + $reviewBodyEditJobs.Count + $checkboxFlipJobs.Count
if ($totalJobs -eq 0) { Exit-WithError 'no work: at least one of commentPatches / threadResolves / checkboxFlips / reviewBodyEdits must be non-empty' }

$root = $PSScriptRoot

# --- Run commentPatches in parallel (GET current body, append, PATCH) -----
$commentPatchResults = @()
if ($commentPatchJobs.Count -gt 0) {
    $commentPatchResults = $commentPatchJobs | ForEach-Object -ThrottleLimit $concurrency -Parallel {
        . "$using:root/_shared.ps1"
        $job = $_
        $rf = $using:repoFull
        $cid = $job.commentId
        $note = $job.appendNote

        # A transient error (Test-GhTransientError) is retried up to twice, and every attempt re-reads the
        # body first: GitHub can apply a PATCH it answered with a 5xx, so "failed" is decided by what it stored.
        $lastError = $null
        for ($attempt = 0; ; $attempt++) {
            if ($attempt -gt 0) { Start-Sleep -Seconds (2 * $attempt) }

            $getRes = Invoke-GhJson @('api',"repos/$rf/pulls/comments/$cid")
            if (-not $getRes.ok) {
                if ($attempt -lt 2 -and (Test-GhTransientError $getRes.error)) { $lastError = "GET: $($getRes.error)"; continue }
                return [pscustomobject]@{ commentId = $cid; ok = $false; error = "GET failed: $($getRes.error)" }
            }
            $currentBody = [string]$getRes.data.body

            # Idempotence: skip the PATCH when the exact appendNote is already
            # anywhere in the body. The note embeds the run's HEAD SHA, so a match
            # proves this exact annotation was appended before; noise from a
            # different SHA falls through and is a genuine "re-append".
            if ($currentBody.Contains($note)) {
                if ($lastError) { return [pscustomobject]@{ commentId = $cid; ok = $true; recovered = $lastError } }
                return [pscustomobject]@{ commentId = $cid; ok = $true; skipped = 'already annotated' }
            }

            $newBody = $currentBody + "`n`n" + $note
            $payload = [pscustomobject]@{ body = $newBody } | ConvertTo-Json -Depth 3 -Compress
            $patchRes = Invoke-GhJson -ArgumentList @(
                'api','--method','PATCH',"repos/$rf/pulls/comments/$cid",'--input','-'
            ) -StdinInput $payload
            if ($patchRes.ok) {
                if ($lastError) { return [pscustomobject]@{ commentId = $cid; ok = $true; recovered = $lastError } }
                return [pscustomobject]@{ commentId = $cid; ok = $true }
            }
            if ($attempt -lt 2 -and (Test-GhTransientError $patchRes.error)) { $lastError = "PATCH: $($patchRes.error)"; continue }
            return [pscustomobject]@{ commentId = $cid; ok = $false; error = "PATCH failed: $($patchRes.error)" }
        }
    }
}
if ($null -eq $commentPatchResults) { $commentPatchResults = @() }

# --- Run threadResolves in parallel ---------------------------------------
$threadResolveResults = @()
if ($threadResolveJobs.Count -gt 0) {
    $resolveMutation = 'mutation($tid:ID!){resolveReviewThread(input:{threadId:$tid}){thread{isResolved}}}'
    $threadResolveResults = $threadResolveJobs | ForEach-Object -ThrottleLimit $concurrency -Parallel {
        . "$using:root/_shared.ps1"
        $job = $_
        # Resolving is idempotent, so a transient error is simply retried (up to twice).
        for ($attempt = 0; ; $attempt++) {
            if ($attempt -gt 0) { Start-Sleep -Seconds (2 * $attempt) }
            $res = Invoke-GhJson @(
                'api','graphql',
                '-f',"query=$using:resolveMutation",
                '-F',"tid=$($job.threadId)"
            )
            if ($res.ok -or $attempt -ge 2 -or -not (Test-GhTransientError $res.error)) { break }
        }
        if (-not $res.ok) {
            return [pscustomobject]@{ threadId = $job.threadId; label = $job.label; ok = $false; error = $res.error }
        }
        $thread = $res.data.data.resolveReviewThread.thread
        return [pscustomobject]@{ threadId = $job.threadId; label = $job.label; ok = $true; isResolved = [bool]$thread.isResolved }
    }
}
if ($null -eq $threadResolveResults) { $threadResolveResults = @() }

# --- Run reviewBodyEdits in parallel (PUT the full body per review) -------
$reviewBodyEditResults = @()
if ($reviewBodyEditJobs.Count -gt 0) {
    $reviewBodyEditResults = $reviewBodyEditJobs | ForEach-Object -ThrottleLimit $concurrency -Parallel {
        . "$using:root/_shared.ps1"
        $job = $_
        $rf = $using:repoFull
        $pr = $using:pr
        $rid = $job.reviewId
        $payload = [pscustomobject]@{ body = $job.newBody } | ConvertTo-Json -Depth 3 -Compress
        $putRes = Invoke-GhJson -ArgumentList @(
            'api','--method','PUT',"repos/$rf/pulls/$pr/reviews/$rid",'--input','-'
        ) -StdinInput $payload
        if (-not $putRes.ok) {
            return [pscustomobject]@{ reviewId = $rid; ok = $false; error = "PUT failed: $($putRes.error)" }
        }
        $storedBody = [string]$putRes.data.body
        return [pscustomobject]@{ reviewId = $rid; ok = $true; storedLength = $storedBody.Length }
    }
}
if ($null -eq $reviewBodyEditResults) { $reviewBodyEditResults = @() }

# --- Run checkboxFlips in parallel (GET body, flip every anchor, one PUT) --
$checkboxFlipResults = @()
if ($checkboxFlipJobs.Count -gt 0) {
    $checkboxFlipResults = $checkboxFlipJobs | ForEach-Object -ThrottleLimit $concurrency -Parallel {
        . "$using:root/_shared.ps1"
        $job = $_
        $rf = $using:repoFull
        $pr = $using:pr
        $rid = $job.reviewId

        # Same transient-error handling as commentPatches: each attempt re-reads the body, so a PUT GitHub
        # applied despite an error shows up as already-flipped boxes rather than as a failure.
        $lastError = $null
        for ($attempt = 0; ; $attempt++) {
            if ($attempt -gt 0) { Start-Sleep -Seconds (2 * $attempt) }

            $getRes = Invoke-GhJson @('api',"repos/$rf/pulls/$pr/reviews/$rid")
            if (-not $getRes.ok) {
                if ($attempt -lt 2 -and (Test-GhTransientError $getRes.error)) { $lastError = "GET: $($getRes.error)"; continue }
                return [pscustomobject]@{ reviewId = $rid; ok = $false; error = "GET failed: $($getRes.error)" }
            }
            $body = [string]$getRes.data.body
            $flipped = @()
            $skipped = @()

            foreach ($flip in $job.flips) {
                # Initial reviews write `- [ ] **MIN007** — …`; verification bodies list `- [ ] MIN007 — …`. Either can be
                # nested under a review note (`  - [ ] **MAJ001** — …`, #5913), so leading whitespace is kept.
                $id      = [regex]::Escape($flip.findingId)
                $done    = '(?m)^[ \t]*- \[' + [regex]::Escape($flip.mark) + '\] (\*\*)?' + $id + '(\*\*)?(?=\s|$)'
                if ([regex]::IsMatch($body, $done)) { $skipped += $flip.findingId; continue }

                $anchor  = '(?m)^(?<indent>[ \t]*)- \[ \] (?<id>(\*\*)?' + $id + '(\*\*)?)(?=\s|$)'
                $count = ([regex]::Matches($body, $anchor)).Count
                if ($count -ne 1) {
                    return [pscustomobject]@{ reviewId = $rid; ok = $false; error = "'- [ ] $($flip.findingId)' (bold or plain) occurs $count times; expected exactly once" }
                }
                $mark  = $flip.mark
                $body  = [regex]::Replace($body, $anchor, { param($m) $m.Groups['indent'].Value + "- [$mark] " + $m.Groups['id'].Value })
                $flipped += $flip.findingId
            }

            if ($flipped.Count -eq 0) {
                $result = [pscustomobject]@{ reviewId = $rid; ok = $true; flipped = @(); skipped = @($skipped) }
                if ($lastError) { $result | Add-Member -NotePropertyName recovered -NotePropertyValue $lastError }
                return $result
            }

            $payload = [pscustomobject]@{ body = $body } | ConvertTo-Json -Depth 3 -Compress
            $putRes = Invoke-GhJson -ArgumentList @(
                'api','--method','PUT',"repos/$rf/pulls/$pr/reviews/$rid",'--input','-'
            ) -StdinInput $payload
            if ($putRes.ok) {
                $result = [pscustomobject]@{ reviewId = $rid; ok = $true; flipped = @($flipped); skipped = @($skipped); storedLength = ([string]$putRes.data.body).Length }
                if ($lastError) { $result | Add-Member -NotePropertyName recovered -NotePropertyValue $lastError }
                return $result
            }
            if ($attempt -lt 2 -and (Test-GhTransientError $putRes.error)) { $lastError = "PUT: $($putRes.error)"; continue }
            return [pscustomobject]@{ reviewId = $rid; ok = $false; error = "PUT failed: $($putRes.error)" }
        }
    }
}
if ($null -eq $checkboxFlipResults) { $checkboxFlipResults = @() }

$out = [pscustomobject]@{
    commentPatches  = @($commentPatchResults)
    threadResolves  = @($threadResolveResults)
    checkboxFlips   = @($checkboxFlipResults)
    reviewBodyEdits = @($reviewBodyEditResults)
}
Write-JsonOutput $out

$anyFailed = @(
    @($commentPatchResults)  | Where-Object { -not $_.ok }
    @($threadResolveResults) | Where-Object { -not $_.ok }
    @($checkboxFlipResults)  | Where-Object { -not $_.ok }
    @($reviewBodyEditResults) | Where-Object { -not $_.ok }
).Count -gt 0

if ($anyFailed) { exit 2 } else { exit 0 }
