#!/usr/bin/env node
// PreToolUse hook on Bash / PowerShell: refuse a `git fetch` refspec whose source side is a bare name.
//
// The rule it enforces is `.claude/docs/windows-dev-gotchas.md` -> "When you *do* need the branch itself, spell the
// source side `refs/heads/<branch>`", with a one-line trigger in `.claude/docs/agent-rules.md`. Prose was not enough:
// `git fetch origin <name>:refs/remotes/origin/<name>` can resolve the source to nothing and take the refspec as a
// delete, printing `- [deleted] (none) -> origin/<name>` and exiting 0. It deleted live tracking refs on #5877, #5720
// and #5942 (where `master:refs/remotes/origin/master` also left `origin/HEAD` dangling), each time with the rule
// already written down.
//
// Allowed sources: anything under `refs/`, `HEAD`, a commit SHA, and an empty source (`:<dst>`, an explicit delete).
// A refspec without `:` fetches into FETCH_HEAD only and is not inspected.
//
// Node rather than pwsh: this runs before every Bash / PowerShell call (`.claude/docs/maintaining-the-corpus.md`).
//
// Wire under `hooks.PreToolUse` with matcher "Bash|PowerShell". Exit 2 blocks the call and returns stderr to
// Claude as feedback.

let input = '';
process.stdin.on('data', c => (input += c));
process.stdin.on('end', () => {
    try {
        const data = JSON.parse(input || '{}');
        if (data.tool_name !== 'Bash' && data.tool_name !== 'PowerShell') return process.exit(0);

        const cmd = String((data.tool_input || {}).command || '');
        if (!/\bfetch\b/.test(cmd)) return process.exit(0);

        // Neutralise separators inside quotes first, so a quoted refspec stays in its segment.
        const masked = cmd.replace(/"[^"]*"|'[^']*'/g, q => q.replace(/[|;&]/g, '_'));

        for (const segment of masked.split(/\s*(?:\|\||&&|\||;|\r?\n)\s*/)) {
            const tokens = (segment.match(/"[^"]*"|'[^']*'|\S+/g) || []).map(t => t.replace(/^["']|["']$/g, ''));

            const git = tokens.findIndex(t => /(^|[\\/])git(\.exe)?$/i.test(t));
            if (git < 0) continue;

            // skip global options (`-C <path>`, `-c k=v`) up to the subcommand
            let i = git + 1;
            while (i < tokens.length && tokens[i].startsWith('-')) i += /^-[Cc]$/.test(tokens[i]) ? 2 : 1;
            if (tokens[i] !== 'fetch') continue;

            const positional = tokens.slice(i + 1).filter(t => !t.startsWith('-'));
            for (const spec of positional.slice(1)) {
                const colon = spec.indexOf(':');
                if (colon < 0) continue;

                const src = spec.slice(0, colon).replace(/^\+/, '');
                if (src === '' || src.startsWith('refs/') || src === 'HEAD' || /^[0-9a-f]{7,40}$/i.test(src)) continue;

                process.stderr.write(
                    `Blocked: git fetch refspec '${spec}' has a bare source '${src}'. git can resolve it to nothing and ` +
                    `treat the refspec as a delete of the destination ('- [deleted] (none) -> ...', exit 0). Spell the ` +
                    `source in full: '+refs/heads/${src}:${spec.slice(colon + 1)}' (or 'refs/pull/<n>/head:...'). ` +
                    "(.claude/docs/windows-dev-gotchas.md -> 'spell the source side refs/heads/<branch>')\n");
                return process.exit(2);
            }
        }
    } catch (e) {
        // A hook fault must not block real work.
        process.stderr.write(`require-qualified-fetch-refspec: ${e}\n`);
    }
    process.exit(0);
});
