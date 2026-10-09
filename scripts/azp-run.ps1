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

Hence three behaviours below, the last two defeatable:
  mergeable check       wait for GitHub to compute `mergeable` (UNKNOWN right after a
                        push) and exit 2 without posting when it is CONFLICTING
  -SettleSeconds        pause before posting (default 5) so the push lands first
  -VerifyTimeoutSeconds poll the PR's checks afterwards until the pipeline shows
                        up (default 60); exit non-zero when it never does, so a
                        silent no-op surfaces as a failure the caller can retry
                        rather than as a comment URL that means nothing

Output: prints one new comment URL per line on stdout, then a verification
line per pipeline - `azp-run: '<name>' started (buildId <n>).` when the check
URL carries the Azure build id, ready for `azp-wait.ps1 -BuildId`. Non-zero exit on the
first `gh` failure, leaving the already-posted triggers in place (a partially
triggered run is visible in the URLs printed before the error), or when
verification times out. Exit 2, with nothing posted, when the PR conflicts with its base.
#>

param(
    [Parameter(Mandatory)][int]$Pr,
    [string[]]$Pipeline = @('test-all'),
    [string]$Repo = 'linq2db/linq2db',
    [int]$SettleSeconds = 5,
    [int]$VerifyTimeoutSeconds = 60
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

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

$notStarted = @()

foreach ($name in $Pipeline) {
    $body = if ($name -eq 'list') { '/azp list' } else { "/azp run $name" }

    # Checks already present before the trigger are not evidence this trigger worked.
    $before = if ($name -eq 'list') { @() } else { Get-Checks }

    $body | gh pr comment $Pr --repo $Repo --body-file -
    if ($LASTEXITCODE -ne 0) {
        [Console]::Error.WriteLine("azp-run: gh pr comment failed for '$name' with exit $LASTEXITCODE")
        exit $LASTEXITCODE
    }

    # `/azp list` answers with a comment rather than a run, so there is nothing to verify.
    if ($name -eq 'list' -or $VerifyTimeoutSeconds -le 0) { continue }

    if ((Get-PipelineChecks $name $before).Count -gt 0) {
        Write-Output "azp-run: '$name' already had checks on this PR before the trigger; not verifying."
        continue
    }

    $deadline = (Get-Date).AddSeconds($VerifyTimeoutSeconds)
    $started  = @()

    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 5
        $started = Get-PipelineChecks $name (Get-Checks)
        if ($started.Count -gt 0) { break }
    }

    if ($started.Count -gt 0) {
        $buildId = Get-BuildId $started
        if ($buildId) { Write-Output "azp-run: '$name' started (buildId $buildId)." }
        else          { Write-Output "azp-run: '$name' started." }
    }
    else {
        $notStarted += $name
        [Console]::Error.WriteLine("azp-run: '$name' did not register a check within $VerifyTimeoutSeconds s - the comment posted but no run started. Re-run this trigger.")
    }
}

if ($notStarted.Count -gt 0) { exit 1 }
