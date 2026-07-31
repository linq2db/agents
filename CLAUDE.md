# CLAUDE.md

Entry point for **Claude Code** working on linq2db. The canonical, agent-agnostic contributor rules live in `.claude/AGENTS.md`; this file layers Claude-Code-specific mechanics on top, and the operational overlay in [.claude/docs/agent-rules.md](.claude/docs/agent-rules.md) carries the harness detail.

All three are always-loaded, imported **by the linq2db root `CLAUDE.md` trampoline** in this order: `.claude/AGENTS.md`, `.claude/CLAUDE.md`, `.claude/docs/agent-rules.md`. This file deliberately contains no imports of its own — a nested import's resolution root (importing file vs. project root) is unspecified, so the whole set stays at the superproject root where both readings coincide. Consequence: adding a new always-loaded corpus file is the one corpus change that also needs a linq2db commit (to extend the trampoline).

## Claude Code specifics

- The corpus is a **git submodule mounted at `.claude/`** — repo [linq2db/agents](https://github.com/linq2db/agents), branch `master`. It is a real directory, not a symlink: skills, subagents, hooks, scripts, path-scoped rules, docs, and the knowledge base all sit where Claude Code natively looks for them. Layout, settings precedence, and skill discovery: [.claude/docs/claude-setup.md](.claude/docs/claude-setup.md).
- **Corpus edits are committed inside `.claude/` and pushed to the agents repo's `master`** — never onto a linq2db branch. The superproject's `.claude` gitlink is a bootstrap pointer, not a version pin, and `.githooks/pre-commit` refuses to commit a bump of it. Full mechanics: [.claude/docs/claude-setup.md](.claude/docs/claude-setup.md) → *The corpus is a git submodule*.
- The operational overlay imported alongside this file is Claude-Code-specific (shell/tool rules, permission-friendly Bash patterns, dedicated-tools-over-CLI, worktree mechanics, corpus/submodule mechanics, subagent verification, skill-based workflows). It complements — never overrides — the rules in `AGENTS.md`.
