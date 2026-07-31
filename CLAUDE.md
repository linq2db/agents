# CLAUDE.md

Entry point for **Claude Code** working on linq2db. The canonical, agent-agnostic contributor rules live in `AGENTS.md` — this file imports them, then layers Claude-Code-specific mechanics on top.

@AGENTS.md

## Claude Code specifics

- `.claude/` is a **symlink to `.claude/`**. Skills, subagents, hooks, scripts, docs, and the knowledge base all live under `.claude/` and are discovered through the symlink — so `.claude/...` and `.claude/...` paths both resolve. Layout, settings precedence, and skill discovery: [.claude/docs/claude-setup.md](.claude/docs/claude-setup.md).
- The operational overlay imported below is Claude-Code-specific (shell/tool rules, permission-friendly Bash patterns, dedicated-tools-over-CLI, worktree mechanics, `.claude/` curation carry-over, subagent verification, skill-based workflows). It complements — never overrides — the rules in `AGENTS.md`.

@.claude/docs/agent-rules.md
