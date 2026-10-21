#!/usr/bin/env node
// PreToolUse hook on Bash / PowerShell: arm .claude/scripts/test-cap.ps1 for a linq2db test run, so a local run
// whose filtered test count exceeds the cap (default 1000) is stopped instead of running to the end.
//
// Never blocks: it starts the watcher, waits for its ready file (the watcher must resolve this session's
// claude.exe while this hook, its anchor, is still alive), and exits 0. Non-test commands cost one regex test.
//
// Spawn shape is forced: a direct child sits in libuv's kill-on-close job and dies with this hook; pwsh started
// `detached` exits at once, and a detached cmd gives its `start`ed pwsh a visible console. A hidden, non-detached
// `cmd /c start /b` works: the grandchild silently breaks away from the job and shares cmd's hidden console.
// Parameters travel in a JSON file because cmd would read a `|` in a filter as a pipe.
//
// Per-command override, written as a trailing shell comment on the command itself:
//   # test-cap:off     no watcher (an over-cap run the user asked for in that turn)
//   # test-cap:5000    a different cap for this run
//
// Wire in .claude/settings.local.json (gitignored) under hooks.PreToolUse with matcher "Bash|PowerShell".
// Payload (stdin JSON): { session_id, cwd, tool_name, tool_input: { command }, ... }.

const fs = require('fs');
const path = require('path');
const { spawn } = require('child_process');

const testRun =
    /linq2db\.Tests(\.Playground)?\.exe|worktree-test\.ps1|\bdotnet\s+test\b[\s\S]*(Tests[/\\]Linq[/\\]Tests\.csproj|Tests\.Playground\.csproj|linq2db\.playground\.slnf)/i;

let input = '';
process.stdin.on('data', c => (input += c));
process.stdin.on('end', () => {
    try {
        const data = JSON.parse(input || '{}');
        if (data.tool_name !== 'Bash' && data.tool_name !== 'PowerShell') return process.exit(0);

        const cmd = String((data.tool_input || {}).command || '');
        if (!testRun.test(cmd) || /--list-tests/.test(cmd)) return process.exit(0);

        // No heartbeat, nothing to read: require-test-progress.js blocks such a run anyway.
        const writesHeartbeat = /worktree-test\.ps1/.test(cmd) ? !/-NoTestProgress/i.test(cmd) : /--test-progress/.test(cmd);
        if (!writesHeartbeat) return process.exit(0);

        const override = cmd.match(/test-cap:\s*(off|\d+)/i);
        if (override && override[1].toLowerCase() === 'off') return process.exit(0);

        const f = cmd.match(/(?:^|\s)--?filter\s+(?:"([^"]*)"|'([^']*)'|(\S+))/i);

        const dir = path.join(data.cwd || process.env.CLAUDE_PROJECT_DIR || process.cwd(), '.build', '.agents');
        fs.mkdirSync(dir, { recursive: true });

        const tag = `${process.pid}.${Date.now()}`;
        const argsFile = path.join(dir, `test-cap.args.${tag}.json`);
        const readyFile = path.join(dir, `test-cap.ready.${tag}`);

        fs.writeFileSync(argsFile, JSON.stringify({
            anchorPid: process.ppid,
            filter: f ? (f[1] || f[2] || f[3]) : null,
            max: override ? Number(override[1]) : null,
            logDir: dir,
            readyFile,
        }));

        const script = path.join(__dirname, '..', 'scripts', 'test-cap.ps1');
        spawn('cmd', ['/c', 'start', '""', '/b', 'pwsh', '-NoProfile', '-NonInteractive', '-File', script, '-ArgsFile', argsFile],
            { windowsHide: true, stdio: 'ignore' }).unref();

        const deadline = Date.now() + 8000;
        const poll = () => {
            if (fs.existsSync(readyFile)) {
                try { fs.unlinkSync(readyFile); } catch (_) { }
                return process.exit(0);
            }
            if (Date.now() > deadline) return process.exit(0);
            setTimeout(poll, 50);
        };
        poll();
    } catch (e) {
        // A hook fault must not block real work.
        process.stderr.write(`arm-test-cap: ${e}\n`);
        process.exit(0);
    }
});
