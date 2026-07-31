# linq2db agent instructions

AI coding-agent instruction corpus for [linq2db](https://github.com/linq2db/linq2db) — skills, subagent
contracts, reference docs, hooks, helper scripts, path-scoped rules, and the knowledge base.

This repo is **contributor tooling for working on linq2db**, not the consumer-facing library-usage pack
that ships in the NuGet packages. It is mounted into a linq2db checkout as a git submodule at `.claude/`,
so every path in these docs is spelled relative to the **linq2db** repo root (`.claude/docs/testing.md`,
`.claude/scripts/kb-state.ps1`), which is also what an agent's tool calls need. Read standalone, those
links don't resolve; read from a mounted checkout, they do.

## Layout

| Path | What |
|-|-|
| `AGENTS.md` | Canonical, agent-agnostic contributor rules. Codex reads it directly; Claude imports it. |
| `CLAUDE.md` | Claude Code entry point (imported by the superproject's trampoline). |
| `docs/` | Reference material — architecture, testing, release, review, Windows gotchas. Linked on demand. |
| `docs/agent-rules.md` | Claude-Code operational overlay, auto-loaded every session. |
| `skills/<name>/SKILL.md` | Skills invocable as `/<name>`. |
| `agents/<name>.md` | Subagent contracts (`code-reviewer`, `test-runner`, KB indexers, …). |
| `scripts/*.ps1` | PowerShell Core helpers used by skills and subagents. |
| `rules/*.md` | Path-scoped rules that load only when a matching file is opened. |
| `knowledge-base/` | Built KB over linq2db's code, issues, PRs, and history. |

## Working on the corpus

Edit the files under `.claude/` in a linq2db checkout, then **commit inside the submodule and push to
this repo's `master`** — corpus history does not live in the linq2db repo. The superproject's `.claude`
gitlink is a bootstrap pointer, not a version pin: `.githooks/` in linq2db fast-forwards the submodule to
this repo's tip on checkout / merge / rebase, and its `pre-commit` refuses an accidental gitlink bump.

`AGENTS.md` and `CLAUDE.md` at the linq2db root are generated trampolines that point here — edit the
copies in this repo, never those.

Maintenance guidance for the corpus itself is in [`.claude/docs/maintaining-the-corpus.md`](docs/maintaining-the-corpus.md).

## License

MIT — see [MIT-LICENSE.txt](MIT-LICENSE.txt).
