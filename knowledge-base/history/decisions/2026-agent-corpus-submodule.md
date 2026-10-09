---
area: GLOBAL
kind: decision
sources: [git]
confidence: high
last_verified: 2026-10-09
last_verified_sha: 05150894edc2511f0dd0bc7829b2a309cec36ec9
---

# Move the agent-instruction corpus to a submodule at .claude/

## Context
Agent instructions lived in `.agents/` (with `.claude` a symlink to it). Churn accumulated on a long-lived curation branch that was rarely merged because it produced large diffs unrelated to product changes. The symlink also could not be followed by Claude Desktop, needed `core.symlinks` plus Developer Mode on Windows, and broke `Glob` through the symlink (measured: `.claude/skills/*/SKILL.md` matched 0 files, `.agents/skills/*/SKILL.md` matched 35).

## Decision
The corpus moved to github.com/linq2db/agents, mounted as a git submodule at `.claude/` (real directory, `.agents/` removed). linq2db keeps `.gitmodules`, the gitlink, `.githooks/`, and root `AGENTS.md` / `CLAUDE.md` as trampolines. The gitlink is a bootstrap pointer, not a version pin (`branch = master`, `update = merge`, `ignore = all`).

## Why
Own history and review surface for the corpus, no symlink in either direction. Root CLAUDE.md carries the always-loaded imports because a nested import resolution root is unspecified. `.github/copilot-instructions.md` became self-contained because GitHub-side Copilot has no submodule checkout.

## Consequences
- 1211 `.agents/**` deletions in the commit are the move, not a shrink, history is preserved in the agents repo.
- `.githooks/` (opt-in via `core.hooksPath`) refreshes the corpus on checkout/merge/rebase and refuses a gitlink bump or trampoline edit.
- The `/.agents/*` virtual-folder block (227 lines, 43 folders) left `linq2db.slnx`.
- `CONTRIBUTING.md` documents the submodule clone.

## Sources
- Commit `70b41a4` -- Move the agent-instruction corpus to a submodule at .claude/ (MaceWindu, 2026-07-31)
- PR #5735 (follow-up docs fix #5736)
- File anchors: `.gitmodules`, `.githooks/`, `CLAUDE.md`, `AGENTS.md`
