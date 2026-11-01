#!/usr/bin/env node
// PostToolUse hook: relay a test-cap stop to the session whose run it stopped.
//
// test-cap.ps1 (armed by arm-test-cap.js) kills an over-cap run with Stop-Process, so the run's own output just
// ends - exit -1 under dotnet test, 255 from bash, no exception, no event-log entry - and reads exactly like a silent
// native crash. The watcher leaves <dir>/test-cap-notices/<session_id>/<pid>.json; this hook turns each notice into
// a message for the session and deletes it. A background run's notice surfaces on the next matched tool call.
//
// Wire in .claude/settings.local.json (gitignored) under hooks.PostToolUse with matcher "Bash|PowerShell|Read|Grep"
// AND under hooks.PostToolUseFailure with matcher "Bash|PowerShell": the stopped command exits non-zero, so its own
// tool call is a failure and PostToolUse never sees it. Payload (stdin JSON): { session_id, cwd, hook_event_name }.
// Never blocks.

const fs = require('fs');
const path = require('path');

let input = '';
process.stdin.on('data', c => (input += c));
process.stdin.on('end', () => {
    try {
        const data = JSON.parse(input || '{}');
        const session = String(data.session_id || '');
        if (!/^[\w-]+$/.test(session)) return process.exit(0);

        // arm-test-cap.js keys the notice dir off the PreToolUse cwd; the project dir covers a cd in between.
        const roots = [...new Set([data.cwd, process.env.CLAUDE_PROJECT_DIR].filter(Boolean))];
        const lines = [];

        for (const root of roots) {
            const dir = path.join(root, '.build', '.agents', 'test-cap-notices', session);
            if (!fs.existsSync(dir)) continue;

            for (const name of fs.readdirSync(dir)) {
                if (!name.endsWith('.json')) continue;
                const file = path.join(dir, name);
                try {
                    const v = JSON.parse(fs.readFileSync(file, 'utf8').replace(/^\uFEFF/, ''));
                    const what = v.verdict === 'stopped' ? 'stopped' : `tried to stop (${v.verdict}: ${v.reason || '?'})`;
                    lines.push(`test-cap ${what} test host pid ${v.pid}: its filter selects ${v.total} tests, over the cap of ${v.max}. ` +
                        'Its exit (-1 / 255, no exception) is this stop, not a crash. Narrow the filter, or - for an over-cap run ' +
                        'the user asked for - append `# test-cap:off` or `# test-cap:<n>` to the command.');
                } catch (_) { }
                try { fs.unlinkSync(file); } catch (_) { }
            }
            try { fs.rmdirSync(dir); } catch (_) { }
        }

        if (lines.length === 0) return process.exit(0);

        const text = lines.join('\n');
        process.stdout.write(JSON.stringify({
            systemMessage: text,
            hookSpecificOutput: { hookEventName: data.hook_event_name || 'PostToolUse', additionalContext: text },
        }));
        process.exit(0);
    } catch (e) {
        // A hook fault must not block real work.
        process.stderr.write(`report-test-cap: ${e}\n`);
        process.exit(0);
    }
});
