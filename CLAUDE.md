# CLAUDE.md

Entry point for **Claude Code** working on linq2db. The canonical, agent-agnostic contributor rules live in `.claude/AGENTS.md`; this file layers Claude-Code-specific mechanics on top, and the operational overlay in [.claude/docs/agent-rules.md](.claude/docs/agent-rules.md) carries the harness detail.

All three are always-loaded, imported **by the linq2db root `CLAUDE.md` trampoline** in this order: `.claude/AGENTS.md`, `.claude/CLAUDE.md`, `.claude/docs/agent-rules.md`. This file deliberately contains no imports of its own — a nested import's resolution root (importing file vs. project root) is unspecified, so the whole set stays at the superproject root where both readings coincide. Consequence: adding a new always-loaded corpus file is the one corpus change that also needs a linq2db commit (to extend the trampoline).

## Claude Code specifics

- The corpus is a **git submodule mounted at `.claude/`** — repo [linq2db/agents](https://github.com/linq2db/agents), branch `master`. It is a real directory, not a symlink: skills, subagents, hooks, scripts, path-scoped rules, docs, and the knowledge base all sit where Claude Code natively looks for them. Layout, settings precedence, and skill discovery: [.claude/docs/claude-setup.md](.claude/docs/claude-setup.md).
- **Corpus edits are committed inside `.claude/` and pushed to the agents repo's `master`** — never onto a linq2db branch. The superproject's `.claude` gitlink is a bootstrap pointer, not a version pin, and `.githooks/pre-commit` refuses to commit a bump of it. Full mechanics: [.claude/docs/claude-setup.md](.claude/docs/claude-setup.md) → *The corpus is a git submodule*.
- The operational overlay imported alongside this file is Claude-Code-specific (shell/tool rules, permission-friendly Bash patterns, dedicated-tools-over-CLI, worktree mechanics, corpus/submodule mechanics, subagent verification, skill-based workflows). It complements — never overrides — the rules in `AGENTS.md`.

# Reply structure

Never mix explanation, questions and proposals in one block of text. When a reply has more than
one of them, split it into labelled sections in this order, and omit the ones that are empty:

1. **Prose** — what I found, what I did, what it means. Statements only: no questions, no proposals.
2. **Questions** — what I need from you before continuing. One per bullet, each answerable on its own.
3. **Next actions** — numbered so you can reply "1, 3" instead of restating it.

Rules:

- Keep each section to its own job. A question buried in a paragraph of findings does not count as asked.
- Don't repeat prose inside the questions or the actions; reference it.
- If there is nothing to ask and nothing to propose, prose alone is the whole reply.
- **Sections 2 and 3 are for real forks only, not for the obvious next step.** A *fork* is one of:
  mutually exclusive options where the choice changes the work; an irreversible or outward-facing
  action (per *Git commit rules*); or a goal-level ambiguity you cannot resolve from the task. When
  the next step follows from what just happened — widen a narrow run, re-run after a fix, take the
  next item of a plan already agreed — **do it and report the result**. Do not close a turn with a
  numbered menu whose every answer is "yes"; that is asking permission, not proposing a choice.
