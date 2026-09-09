<#
PreToolUse hook on Bash / PowerShell: refuse a hand-run linq2db test invocation that
omits `--test-progress`.

The rule it enforces is `.claude/docs/agent-rules.md` -> "Every hand-run `dotnet test` /
test-exe invocation carries `--test-progress`", restated in `.claude/docs/testing.md` and
carried by every command example there. Prose was not enough: the flag is dropped on
exactly the runs the rule names -- an ad-hoc filtered check that "will only take a moment"
-- and the cost lands later, when that run turns out to hang and there is no heartbeat to
say where it stopped.

Scope: the provider test hosts that register the extension (`linq2db.Tests.exe`,
`linq2db.Tests.Playground.exe`, and `dotnet test` against their projects / the playground
solution filter). The bare-NUnit hosts are exempt -- `Tests.Analyzers` and
`Tests.LinqToDB.CLI` do not register it and exit 5 ("Zero tests ran") when it is passed.
A `--list-tests` invocation runs nothing and is exempt too.

Wire under `hooks.PreToolUse` with matcher "Bash|PowerShell". Exit 2 blocks the call and
returns stderr to Claude as feedback.
#>

$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

try {
    $raw = [Console]::In.ReadToEnd()
    if ([string]::IsNullOrWhiteSpace($raw)) { exit 0 }

    $payload = $raw | ConvertFrom-Json -ErrorAction Stop
    if ($payload.tool_name -notin @('Bash', 'PowerShell')) { exit 0 }

    $cmd = [string]$payload.tool_input.command
    if ([string]::IsNullOrWhiteSpace($cmd)) { exit 0 }

    # Hosts that do not register the progress extension - passing the flag there exits 5. Matched by
    # family rather than by exact name: a DB-free analyzer-fixture project is added roughly once per
    # analyzer family (Tests.Analyzers, Tests.Analyzers.Internal, ...) and each inherits the trap.
    $exemptHost = 'Tests\.Analyzers|linq2db\.CLI\.Tests|Tests\.LinqToDB\.CLI'

    # Split on pipe / && / || / ; so a chained invocation is still inspected on its own.
    foreach ($segment in [regex]::Split($cmd, '\s*(?:\|\||&&|\||;)\s*')) {
        $s = $segment.Trim()
        if ($s -eq '') { continue }
        if ($s -match $exemptHost) { continue }
        if ($s -match '--list-tests') { continue }

        $isTestRun =
            $s -match 'linq2db\.Tests(\.Playground)?\.exe' -or
            ($s -match '\bdotnet\s+test\b' -and $s -match 'Tests[/\\]Linq[/\\]Tests\.csproj|Tests\.Playground\.csproj|linq2db\.playground\.slnf')

        if (-not $isTestRun) { continue }
        if ($s -match '--test-progress') { continue }

        [Console]::Error.WriteLine(
            "Blocked: this test run omits --test-progress, so it writes no heartbeat to " +
            ".build/.agents/test-progress.<tfm>.<pid>.json and nothing can say how far it got or " +
            "whether it started at all. Add a bare --test-progress and re-issue. " +
            "(.claude/docs/agent-rules.md -> 'Every hand-run dotnet test / test-exe invocation carries --test-progress')")
        exit 2
    }
}
catch {
    # A hook fault must not block real work.
    [Console]::Error.WriteLine("require-test-progress: $_")
}

exit 0
