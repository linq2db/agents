# CLAUDE.md

Entry point for **Claude Code** working on linq2db. The canonical, agent-agnostic contributor rules live in `.claude/AGENTS.md`; this file layers Claude-Code-specific mechanics on top, and the operational overlay in [.claude/docs/agent-rules.md](.claude/docs/agent-rules.md) carries the harness detail.

All three are always-loaded, imported **by the linq2db root `CLAUDE.md` trampoline** in this order: `.claude/AGENTS.md`, `.claude/CLAUDE.md`, `.claude/docs/agent-rules.md`. This file deliberately contains no imports of its own — a nested import's resolution root (importing file vs. project root) is unspecified, so the whole set stays at the superproject root where both readings coincide. Consequence: adding a new always-loaded corpus file is the one corpus change that also needs a linq2db commit (to extend the trampoline).

## Claude Code specifics

- The corpus is a **git submodule mounted at `.claude/`** ([linq2db/agents](https://github.com/linq2db/agents), `master`); corpus edits are committed and pushed there, never onto a linq2db branch. Mechanics: the overlay → *The corpus is a submodule*; layout and settings precedence: [.claude/docs/claude-setup.md](.claude/docs/claude-setup.md).
- The operational overlay imported alongside this file is Claude-Code-specific (shell/tool rules, permission-friendly Bash patterns, dedicated-tools-over-CLI, worktree mechanics, corpus/submodule mechanics, subagent verification, skill-based workflows). It complements — never overrides — the rules in `AGENTS.md`.

# Reply structure

Never mix explanation, questions and proposals in one block of text. When a reply has more than
one of them, split it into labelled sections in this order, and omit the ones that are empty:

1. **Prose** — what was found, what was done, what it means. Statements only: no questions, no proposals.
2. **Questions** — what the user must decide before work continues. One per bullet, each answerable on its own; mutually exclusive options are lettered (a/b/c), one label space per turn.
3. **Next actions** — what the agent proposes to do, numbered so the user can reply "1, 3" instead of restating it.

Rules:

- Keep each section to its own job. A question buried in a paragraph of findings does not count as asked.
- Don't repeat prose inside the questions or the actions; reference it.
- If there is nothing to ask and nothing to propose, prose alone is the whole reply — but check before omitting: "nothing to ask" has to mean every open point can proceed without the user, not that one felt too small to interrupt for.
- **An open question is re-asked in full in the reply that needs it.** Never refer back to an earlier one ("the question from my last message is still open") — the reference is invisible in the reply being read.
- **A prose sentence that names something unresolved and waits on the user is a question wearing prose** ("still open", "worth deciding", "unless you want otherwise") and belongs in **Questions**.
- **A wrap-up turn with anything undecided is still a sectioned turn.** A closing summary reads as pure prose, so open items get appended as a trailing paragraph instead of a **Next actions** section — the content the sections exist to separate.
- **Sections 2 and 3 are for real forks only, not for the obvious next step.** A *fork* is one of:
  mutually exclusive options where the choice changes the work; an irreversible or outward-facing
  action (per *Git commit rules*); or a goal-level ambiguity not resolvable from the task. When
  the next step follows from what just happened — widen a narrow run, re-run after a fix, take the
  next item of a plan already agreed — **do it and report the result**. Do not close a turn with a
  menu whose every answer is "yes"; that is asking permission, not proposing a choice.
