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

Output: prints one new comment URL per line on stdout. Non-zero exit on the
first `gh` failure, leaving the already-posted triggers in place (a partially
triggered run is visible in the URLs printed before the error).
#>

param(
    [Parameter(Mandatory)][int]$Pr,
    [string[]]$Pipeline = @('test-all'),
    [string]$Repo = 'linq2db/linq2db'
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

foreach ($name in $Pipeline) {
    $body = if ($name -eq 'list') { '/azp list' } else { "/azp run $name" }

    $body | gh pr comment $Pr --repo $Repo --body-file -
    if ($LASTEXITCODE -ne 0) {
        [Console]::Error.WriteLine("azp-run: gh pr comment failed for '$name' with exit $LASTEXITCODE")
        exit $LASTEXITCODE
    }
}
