#!/usr/bin/env node
// PreToolUse hook on Bash / PowerShell: refuse a hand-run linq2db test invocation that omits `--test-progress`.
//
// The rule it enforces is `.claude/docs/agent-rules.md` -> "Every hand-run `dotnet test` / test-exe invocation
// carries `--test-progress`", restated in `.claude/docs/testing.md` and carried by every command example there.
// Prose was not enough: the flag is dropped on exactly the runs the rule names -- an ad-hoc filtered check that
// "will only take a moment" -- and the cost lands later, when that run turns out to hang and there is no heartbeat
// to say where it stopped. The heartbeat is also what `arm-test-cap.js` reads to cap a run's size.
//
// Scope: the provider test hosts that register the extension (`linq2db.Tests.exe`, `linq2db.Tests.Playground.exe`,
// and `dotnet test` against their projects / the playground solution filter). The bare-NUnit hosts are exempt --
// `Tests.Analyzers` and `Tests.LinqToDB.CLI` do not register it and exit 5 ("Zero tests ran") when it is passed.
// A `--list-tests` invocation runs nothing and is exempt too.
//
// Node rather than pwsh: this runs before every Bash / PowerShell call, and pwsh startup costs 0.6-1.2 s each time.
//
// Wire under `hooks.PreToolUse` with matcher "Bash|PowerShell". Exit 2 blocks the call and returns stderr to
// Claude as feedback.

// Hosts that do not register the progress extension - passing the flag there exits 5. Matched by family rather
// than by exact name: a DB-free analyzer-fixture project is added roughly once per analyzer family
// (Tests.Analyzers, Tests.Analyzers.Internal, ...) and each inherits the trap.
const exemptHost = /Tests\.Analyzers|linq2db\.CLI\.Tests|Tests\.LinqToDB\.CLI/;

let input = '';
process.stdin.on('data', c => (input += c));
process.stdin.on('end', () => {
    try {
        const data = JSON.parse(input || '{}');
        if (data.tool_name !== 'Bash' && data.tool_name !== 'PowerShell') return process.exit(0);

        const cmd = String((data.tool_input || {}).command || '');
        if (!cmd.trim()) return process.exit(0);

        // Neutralise separators inside quotes first, so `--filter "A|B"` stays one segment.
        const masked = cmd.replace(/"[^"]*"|'[^']*'/g, q => q.replace(/[|;&]/g, '_'));

        // Split on pipe / && / || / ; so a chained invocation is still inspected on its own.
        for (const segment of masked.split(/\s*(?:\|\||&&|\||;)\s*/)) {
            const s = segment.trim();
            if (!s || exemptHost.test(s) || /--list-tests/.test(s)) continue;

            // The exe counts only in command position: `ls` / `Get-Item` of the build output names it too.
            const isTestRun =
                /^(?:&\s*|Start-Process\s+(?:-FilePath\s+)?)?["']?[^\s"']*linq2db\.Tests(\.Playground)?\.exe["']?(?:\s|$)/i.test(s) ||
                (/\bdotnet\s+test\b/.test(s) &&
                    /Tests[/\\]Linq[/\\]Tests\.csproj|Tests\.Playground\.csproj|linq2db\.playground\.slnf/.test(s));

            if (!isTestRun || /--test-progress/.test(s)) continue;

            process.stderr.write(
                'Blocked: this test run omits --test-progress, so it writes no heartbeat to ' +
                '.build/.agents/test-progress.<tfm>.<pid>.json and nothing can say how far it got or ' +
                'whether it started at all. Add a bare --test-progress and re-issue. ' +
                "(.claude/docs/agent-rules.md -> 'Every hand-run dotnet test / test-exe invocation carries --test-progress')\n");
            return process.exit(2);
        }
    } catch (e) {
        // A hook fault must not block real work.
        process.stderr.write(`require-test-progress: ${e}\n`);
    }
    process.exit(0);
});
