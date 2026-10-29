<#
Post `/azp run <pipeline>` (or `/azp list`) as a PR comment to trigger
Azure Pipelines.

Why this script exists
----------------------
Posting `/azp run test-all` directly via `gh pr comment --body "/azp run test-all"`
is a Windows Git Bash trap: MSYS rewrites the leading `/` into
`C:/Program Files/Git/...` before `gh` sees the value, and the comment lands
on GitHub silently corrupted (no error, just a mangled body that does not
trigger CI). See `.claude/docs/agent-rules.md` -> `Windows Git Bash gotchas`.

This script forwards the body via stdin (`--body-file -`), which is not
subject to MSYS path conversion. The slash literal is internal to the script,
never crossing the bash -> exe boundary as a CLI argument, so the failure
mode cannot fire.

Invoke directly via the PowerShell tool (preferred), NOT wrapped in Bash:

    .claude\scripts\azp-run.ps1 -Pr 5467
    .claude\scripts\azp-run.ps1 -Pr 5467 -Pipeline test-sqlite
    .claude\scripts\azp-run.ps1 -Pr 5467 -Pipeline test-access,test-mysql
    .claude\scripts\azp-run.ps1 -Pr 5467 -Pipeline list

`-Pipeline list` posts `/azp list` (every pipeline registered on the repo);
any other value posts `/azp run <value>`. Azure Pipelines parses one command
per comment, so several pipelines mean several comments - pass them as a list
and the script posts one comment each, in order.

Triggering too soon after a push silently does nothing
------------------------------------------------------
A `/azp run` comment posted in the same breath as a `git push` can be accepted
by GitHub and still never start a run: Azure resolves the trigger against the
PR head it knows about, and immediately after a push that view has not caught
up. The comment posts fine, no error appears anywhere, and the pipeline simply
never registers - which looks identical to a successful trigger unless someone
checks the PR's checks afterwards.

This is not specific to `test-all`. It applies to every pipeline this script can
trigger - `test-sqlite`, `test-sqlserver`, any `test-<provider>` - because the
cause is the push/trigger race, not the pipeline. Observed on #5614, where a
`test-all` trigger posted seconds after the push produced a comment URL and no
run at all, while the same command a few minutes later worked.

A PR that conflicts with its base is refused every time, whatever the delay: Azure
builds refs/pull/<n>/merge, which does not exist for a conflicting PR, and the bot answers
with the misleading `the pull request was updated after the run command was issued.
Review the pull request again and issue a new run command`. On #6003 three triggers were
refused this way (settle 180 s included) until master was merged into the branch. So the
script first reads `mergeable` and refuses to post on CONFLICTING - merge the base
branch, push, then trigger. (#5725 drew the same message on two triggers and started on a
third after `-SettleSeconds 180`; whether that was a conflict-free PR still being
evaluated was not established, so the longer settle remains the advice after a push.)

A PR whose head is behind master is refused too: results from a stale branch don't reflect
what will be validated at merge, and a stacked PR can be conflict-free against its own base
while the stack conflicts with master - the mergeable check cannot see that. Sync first
(stacked: sync the parent with master, then merge the parent forward), push, trigger.
Hit twice on 2026-10-13 in different sessions (#6037 on the #5707 stack, after #6025 landed).

Hence four behaviours below, the last three defeatable:
  mergeable check       wait for GitHub to compute `mergeable` (UNKNOWN right after a
                        push) and exit 2 without posting when it is CONFLICTING
  master sync check     exit 3 without posting when the PR head lacks master's tip
                        commit (-AllowStale to trigger anyway)
  -SettleSeconds        pause before posting (default 5) so the push lands first
  -VerifyTimeoutSeconds poll the PR's checks afterwards until the pipeline shows
                        up - on a re-run, with a build id other than the one it
                        had before (default 60); exit non-zero when it never does, so a
                        silent no-op surfaces as a failure the caller can retry
                        rather than as a comment URL that means nothing. Before
                        calling it a no-op, it looks for a failed build of that
                        pipeline on refs/pull/<n>/merge carrying validationResults:
                        that is a YAML validation error, which the bot reports only
                        as "Azure Pipelines failed to run 1 pipeline(s)" - not a
                        conflict and not the push race, so a retry cannot help. The
                        script prints the reason and exits 4.

Output: prints one new comment URL per line on stdout, then a verification
line per pipeline - `azp-run: '<name>' started (buildId <n>).` when the check
URL carries the Azure build id, ready for `azp-wait.ps1 -BuildId` - and
`azp-run: '<name>' GitHub run <id>` for the `tests (comment)` dispatch. On a PR
the main-suite provider legs run in that GitHub run, not in the Azure build (whose
main-suite steps are skipped), so a green Azure build alone does not prove the tests
ran. The GitHub run is attributed to master's commit, so it is matched by creation
time after the comment; under concurrent triggers on other PRs, confirm the PR in
its `authorize` job log (gh-leg-history.ps1 reads it). Non-zero exit on the
first `gh` failure, leaving the already-posted triggers in place (a partially
triggered run is visible in the URLs printed before the error), or when
verification times out. Exit 2, with nothing posted, when the PR conflicts with its base;
exit 3, with nothing posted, when the PR head is behind master; exit 4 when Azure
refused the pipeline's YAML (the reason is on stderr).
#>

param(
    [Parameter(Mandatory)][int]$Pr,
    [string[]]$Pipeline = @('test-all'),
    [string]$Repo = 'linq2db/linq2db',
    [int]$SettleSeconds = 5,
    [int]$VerifyTimeoutSeconds = 60,
    [switch]$AllowStale
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

# `pwsh -File … -Pipeline a,b` binds one string 'a,b'. Posted as one `/azp run a,b`, Azure starts both
# but tests-comment.yml reads only the first token and skips the GitHub legs (#6161).
$Pipeline = @($Pipeline | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })

# Returns the checks currently on the PR as { name, url }. Empty on any gh failure: the caller treats that
# as "not seen yet" and keeps polling, so a transient gh hiccup does not read as a failed trigger.
function Get-Checks {
    $json = gh pr view $Pr --repo $Repo --json statusCheckRollup --jq '[.statusCheckRollup[] | {name, url: (.detailsUrl // .targetUrl)}]' 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $json) { return @() }
    try { return @($json | ConvertFrom-Json) } catch { return @() }
}

# A pipeline named `test-all` surfaces as `test-all` plus per-leg `test-all (Lin SQLite)` entries.
function Get-PipelineChecks([string]$name, [object[]]$checks) {
    return @($checks | Where-Object { $_.name -eq $name -or $_.name -like "$name (*" })
}

function Get-BuildId([object[]]$pipelineChecks) {
    foreach ($c in $pipelineChecks) {
        if ($c.url -match 'buildId=(\d+)') { return $Matches[1] }
    }
    return $null
}

if ($SettleSeconds -gt 0) {
    Start-Sleep -Seconds $SettleSeconds
}

# GitHub computes mergeability lazily, so UNKNOWN is normal for a while after a push.
$mergeable = 'UNKNOWN'
for ($i = 0; $i -lt 12 -and $mergeable -eq 'UNKNOWN'; $i++) {
    if ($i -gt 0) { Start-Sleep -Seconds 5 }
    $mergeable = gh pr view $Pr --repo $Repo --json mergeable --jq .mergeable 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $mergeable) { $mergeable = 'UNKNOWN' }
}
if ($mergeable -eq 'CONFLICTING') {
    [Console]::Error.WriteLine("azp-run: PR #$Pr conflicts with its base branch - Azure would refuse the run. Merge the base branch, push, then trigger again.")
    exit 2
}

if (-not $AllowStale) {
    $head   = gh pr view $Pr --repo $Repo --json headRefOid --jq .headRefOid
    $behind = gh api "repos/$Repo/compare/master...$head" --jq .behind_by
    if ($LASTEXITCODE -eq 0 -and [int]$behind -gt 0) {
        [Console]::Error.WriteLine("azp-run: PR #$Pr head is $behind commit(s) behind master. Sync with master first (stacked PR: sync the parent, then merge it forward), push, then trigger again; -AllowStale to trigger anyway.")
        exit 3
    }
}

$notStarted = @()
$invalid     = @()
$claimedRuns = @{}

# A pipeline whose YAML fails validation never gets a check, but Azure still records a failed build on the PR's
# merge ref carrying the reason in validationResults; the bot only answers "failed to run 1 pipeline(s)".
function Get-RefusedBuild([string]$name, [datetime]$since) {
    try {
        $builds = Invoke-RestMethod "https://dev.azure.com/linq2db/linq2db/_apis/build/builds?branchName=refs/pull/$Pr/merge&`$top=10&queryOrder=queueTimeDescending&api-version=7.0"
    }
    catch { return $null }
    return @($builds.value | Where-Object {
        $_.definition.name -eq $name -and
        ([datetime]$_.queueTime).ToUniversalTime() -ge $since -and
        @($_.validationResults | Where-Object { $_.result -eq 'error' }).Count -gt 0
    })[0]
}

# GitHub `tests (comment)` runs created at or after $since and not yet reported for an earlier pipeline.
# Every PR comment starts a `tests (comment)` run, the Azure bot's replies included, and those end `skipped`:
# taking the earliest one by time reported a skipped neighbour as the run (#6161: 40371420237 instead of
# 40371438419). So skip `skipped` runs, and give a still-queued neighbour a few seconds to settle.
function Get-DispatchRun([datetime]$since) {
    for ($attempt = 0; $attempt -lt 6; $attempt++) {
        if ($attempt -gt 0) { Start-Sleep -Seconds 5 }
        # The azure-pipelines bot's "started" reply is itself an issue_comment and dispatches a run that ends skipped,
        # but is still queued or in authorize when we look; only a human-triggered run can be ours.
        $json = gh api "repos/$Repo/actions/workflows/tests-comment.yml/runs?per_page=10" --jq '[.workflow_runs[] | {databaseId: .id, createdAt: .created_at, status, conclusion, actor: .triggering_actor.login}]' 2>$null
        if ($LASTEXITCODE -ne 0 -or -not $json) { return $null }
        $runs = @(@($json | ConvertFrom-Json) |
            Where-Object { ([datetime]$_.createdAt).ToUniversalTime() -ge $since -and -not $claimedRuns.ContainsKey([string]$_.databaseId) -and $_.conclusion -ne 'skipped' -and $_.actor -notlike '*`[bot`]' } |
            Sort-Object { [datetime]$_.createdAt })
        # A queued run may still end `skipped`; prefer one that has started.
        $live = @($runs | Where-Object { $_.status -eq 'in_progress' -or $_.status -eq 'completed' })
        if ($live.Count -gt 0) { return $live[0] }
    }
    return @($runs)[0]
}

foreach ($name in $Pipeline) {
    $body = if ($name -eq 'list') { '/azp list' } else { "/azp run $name" }
    $postedAt = (Get-Date).ToUniversalTime().AddSeconds(-5)

    # Checks already present before the trigger are not evidence this trigger worked.
    $before = if ($name -eq 'list') { @() } else { Get-Checks }

    $body | gh pr comment $Pr --repo $Repo --body-file -
    if ($LASTEXITCODE -ne 0) {
        [Console]::Error.WriteLine("azp-run: gh pr comment failed for '$name' with exit $LASTEXITCODE")
        exit $LASTEXITCODE
    }

    # `/azp list` answers with a comment rather than a run, so there is nothing to verify.
    if ($name -eq 'list' -or $VerifyTimeoutSeconds -le 0) { continue }

    # A re-run replaces the pipeline's checks with a new build id, so a re-trigger is verified by that change.
    $priorChecks  = Get-PipelineChecks $name $before
    $priorBuildId = Get-BuildId $priorChecks
    if ($priorChecks.Count -gt 0 -and -not $priorBuildId) {
        Write-Output "azp-run: '$name' already had checks on this PR before the trigger, without a build id to compare; not verifying."
        continue
    }

    $deadline = (Get-Date).AddSeconds($VerifyTimeoutSeconds)
    $started  = @()

    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 5
        $started = Get-PipelineChecks $name (Get-Checks)
        if ($started.Count -gt 0 -and (-not $priorBuildId -or (Get-BuildId $started) -ne $priorBuildId)) { break }
        $started = @()
    }

    if ($started.Count -gt 0) {
        $buildId = Get-BuildId $started
        if ($buildId) { Write-Output "azp-run: '$name' started (buildId $buildId)." }
        else          { Write-Output "azp-run: '$name' started." }

        $dispatch = Get-DispatchRun $postedAt
        if ($dispatch) {
            $claimedRuns[[string]$dispatch.databaseId] = $true
            Write-Output "azp-run: '$name' GitHub run $($dispatch.databaseId) (matched by time)."
        }
        else {
            Write-Output "azp-run: '$name' no GitHub 'tests (comment)' run found yet - check gh run list --workflow tests-comment.yml."
        }
    }
    else {
        $refused = Get-RefusedBuild $name $postedAt
        if ($refused) {
            $invalid += $name
            $why = (@($refused.validationResults | ForEach-Object { $_.message }) | Select-Object -Unique) -join ' | '
            [Console]::Error.WriteLine("azp-run: '$name' was refused - the pipeline YAML failed validation (Azure build $($refused.id)): $why A retry will not help; fix the template on the branch.")
        }
        else {
            $notStarted += $name
            [Console]::Error.WriteLine("azp-run: '$name' did not register a check within $VerifyTimeoutSeconds s - the comment posted but no run started. Re-run this trigger.")
        }
    }
}

if ($invalid.Count -gt 0)    { exit 4 }
if ($notStarted.Count -gt 0) { exit 1 }
