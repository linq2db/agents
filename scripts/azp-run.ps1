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

Hence two behaviours below, both defeatable:
  -SettleSeconds        pause before posting (default 5) so the push lands first
  -VerifyTimeoutSeconds poll the PR's checks afterwards until the pipeline shows
                        up (default 60); exit non-zero when it never does, so a
                        silent no-op surfaces as a failure the caller can retry
                        rather than as a comment URL that means nothing

Output: prints one new comment URL per line on stdout. Non-zero exit on the
first `gh` failure, leaving the already-posted triggers in place (a partially
triggered run is visible in the URLs printed before the error), or when
verification times out.
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

# Returns the check-run names currently on the PR. Empty on any gh failure: the caller treats that
# as "not seen yet" and keeps polling, so a transient gh hiccup does not read as a failed trigger.
function Get-CheckNames {
    $json = gh pr view $Pr --repo $Repo --json statusCheckRollup --jq '[.statusCheckRollup[].name]' 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $json) { return @() }
    try { return @($json | ConvertFrom-Json) } catch { return @() }
}

# A pipeline named `test-all` surfaces as `test-all` plus per-leg `test-all (Lin SQLite)` entries.
function Test-PipelineStarted([string]$name, [string[]]$checkNames) {
    return @($checkNames | Where-Object { $_ -eq $name -or $_ -like "$name (*" }).Count -gt 0
}

if ($SettleSeconds -gt 0) {
    Start-Sleep -Seconds $SettleSeconds
}

$notStarted = @()

foreach ($name in $Pipeline) {
    $body = if ($name -eq 'list') { '/azp list' } else { "/azp run $name" }

    # Checks already present before the trigger are not evidence this trigger worked.
    $before = if ($name -eq 'list') { @() } else { Get-CheckNames }

    $body | gh pr comment $Pr --repo $Repo --body-file -
    if ($LASTEXITCODE -ne 0) {
        [Console]::Error.WriteLine("azp-run: gh pr comment failed for '$name' with exit $LASTEXITCODE")
        exit $LASTEXITCODE
    }

    # `/azp list` answers with a comment rather than a run, so there is nothing to verify.
    if ($name -eq 'list' -or $VerifyTimeoutSeconds -le 0) { continue }

    if (Test-PipelineStarted $name $before) {
        Write-Output "azp-run: '$name' already had checks on this PR before the trigger; not verifying."
        continue
    }

    $deadline = (Get-Date).AddSeconds($VerifyTimeoutSeconds)
    $started  = $false

    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 5
        if (Test-PipelineStarted $name (Get-CheckNames)) { $started = $true; break }
    }

    if ($started) {
        Write-Output "azp-run: '$name' started."
    }
    else {
        $notStarted += $name
        [Console]::Error.WriteLine("azp-run: '$name' did not register a check within $VerifyTimeoutSeconds s - the comment posted but no run started. Re-run this trigger.")
    }
}

if ($notStarted.Count -gt 0) { exit 1 }
