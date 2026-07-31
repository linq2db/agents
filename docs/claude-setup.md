# Claude Code setup

Claude Code configuration for this project lives under `.claude/` — the single agent-instruction source shared with Codex (`AGENTS.md`) and Copilot. It is a **real directory**, mounted as a git submodule (see *The corpus is a git submodule* below), which is exactly where Claude Code hardcodes discovery of skills / subagents / hooks / rules / settings. Every path in these docs is spelled relative to the linq2db repo root, which is also what an agent's tool calls resolve against.

> **Fresh-clone note.** `git clone` leaves `.claude/` as an **empty directory** unless you pass `--recurse-submodules`; an unpopulated submodule is not a deletion, so `git status` reads clean and the only symptom is that no skills, rules or instructions load. Populate it with `git submodule update --init`, then **`git -C .claude switch master`** — `update --init` checks out the gitlink SHA as a *detached HEAD*, and a corpus commit made there lands on no branch (the refresh hook fast-forwards the content either way, so the detachment is otherwise invisible). Then `git config core.hooksPath .githooks` to enable the auto-refresh and guard hooks. Same trap in a new `git worktree` — see [`worktree.md`](worktree.md) → *Bootstrapping `.claude/` in a worktree*.

- `.claude/skills/<name>/SKILL.md` — project-specific skills invocable as `/<name>`. The full catalogue (one row per skill, with staleness signals for the periodic ones) lives in [`/chores`](../skills/chores/SKILL.md); skills are also visible to Claude Code at session start via the system-reminder list. To know "what runs when", read either of those — don't maintain a parallel list here.
- `.claude/agents/<name>.md` — subagent contracts invoked from skills (e.g. `code-reviewer`, `kb-architect`).
- `.claude/scripts/*.ps1` — PowerShell Core helpers used by skills and subagents (multi-step `gh` / `git` orchestrations live here, not in raw Bash chains). Authoring contract: [`script-authoring.md`](script-authoring.md).
- `.claude/docs/*.md` — reference material linked or imported from `CLAUDE.md`. `agent-rules.md` is auto-imported into every Claude Code session; the others are linked and loaded on demand.
- `.claude/rules/*.md` — path-scoped conditional rules. A rule with a `paths:` frontmatter glob list loads into context only when Claude opens/edits a file matching one of its globs (a rule with no `paths:` loads at session start like `CLAUDE.md`). Use these to auto-surface guidance that only matters for specific source trees — e.g. `cross-cutting-core.md` points at the `code-design.md` AST/translator invariants when editing `Source/LinqToDB/**/SqlQuery/**` or `**/Translation/**`. Frontmatter schema is `paths:`-only (undocumented keys risk a strict parser dropping the rule).
- `.claude/hooks/*` — opt-in PreToolUse / PostToolUse / SessionEnd hooks (`.ps1` and `.js`). **Nothing in the corpus registers them** — there is no committed `settings.json`, so they fire only if you wire them yourself in `.claude/settings.local.json` or `~/.claude/settings.json`. Until then they are inert, which is why the docker-tracking rule in [`agent-rules.md`](agent-rules.md) tells you to verify the state file rather than trust the hook. (Distinct from linq2db's `.githooks/`, which are *git* hooks for the submodule — see below.)
- `.claude/settings.local.json` — **gitignored**. Personal project-level overrides: permissions allowlists, hook wiring, model/effort preferences, env vars. Created on demand; `{}` is a valid starting content.

The project deliberately does **not** commit a `.claude/settings.json`. Hooks, statuslines, and global preferences belong in your user profile (`~/.claude/`), not in the repo. That means nothing in the repo enforces the agent-side rules — compliance depends on you (and any hooks you install personally; see the Bash command rules in `.claude/docs/agent-rules.md`).

Settings precedence: project-local `.claude/settings.local.json` > user-level `~/.claude/settings.json` > Claude Code defaults.

## The corpus is a git submodule

`.claude/` is a submodule pointing at [linq2db/agents](https://github.com/linq2db/agents) — the corpus has its own repo and its own history, so corpus churn never touches linq2db's. linq2db tracks only `.gitmodules`, the `.claude` gitlink, `.githooks/`, and two root trampolines.

**`.gitmodules`**

```
[submodule ".claude"]
	path = .claude
	url = https://github.com/linq2db/agents.git
	branch = master
	update = merge
	ignore = all
```

- `branch = master` + `update = merge` are what make the checkout *follow the corpus tip* instead of the recorded gitlink: `git submodule update --remote --merge` fetches `agents/master` and merges it in, and `merge` mode is a no-op when the submodule is already ahead (plain `checkout` mode would detach and **rewind** it).
- `ignore = all` — the gitlink is a bootstrap pointer, not a version pin, so the superproject must not nag about being behind it. `all` is required: `ignore = dirty` still reports *committed* differences from the gitlink and would leave linq2db permanently dirty. It also stops `git add .` from staging a gitlink bump (that needs `git add --force .claude`).
- **What `ignore = all` hides:** new corpus commits, uncommitted corpus edits, and untracked files inside `.claude/`. Superproject `git status` says nothing about the corpus — use `git -C .claude status`, `git submodule summary`, or `git status --ignore-submodules=none` when you need to see it.
- **Never set `submodule.recurse=true`.** `checkout --recurse-submodules` ignores `update = merge`, detaches the submodule and rewinds it to the stale gitlink.

**Hooks** (`.githooks/` in linq2db, enabled per clone with `git config core.hooksPath .githooks`)

- `post-checkout` / `post-merge` / `post-rewrite` → `_refresh-corpus.sh`: fast-forwards `.claude/` to the corpus tip after a branch switch, pull, or rebase. It skips when `.claude/` has uncommitted tracked changes (never clobbers in-flight corpus work) and always exits 0 — a `post-checkout` failure would become the `git checkout`'s exit status.
- `pre-commit`: refuses a staged `.claude` gitlink bump and refuses staged edits to the root `AGENTS.md` / `CLAUDE.md` trampolines. Both are deliberate-action gates, overridable with `git commit --no-verify`.

**Editing the corpus.** Edit files under `.claude/`, then commit **inside** the submodule and push to `agents/master` (`git -C .claude add <pathspec>` / `commit` / `push`). Nothing lands on a linq2db branch and the gitlink stays put. Per-worktree bootstrap: [`worktree.md`](worktree.md) → *Bootstrapping `.claude/` in a worktree*.

**Trampolines.** linq2db's root `AGENTS.md` and `CLAUDE.md` are generated pointers into the corpus — Codex reads root `AGENTS.md` natively, and Claude Code's root `CLAUDE.md` carries the whole always-loaded import set (`.claude/AGENTS.md`, `.claude/CLAUDE.md`, `.claude/docs/agent-rules.md`). Imports stay at the superproject root because a *nested* import's resolution root is unspecified. Edit the corpus copies, never the trampolines; adding a new always-loaded file is the one corpus change that also needs a linq2db commit.

## Agent-agnostic corpus guidance lives elsewhere

Guidance that applies to **any** agent maintaining this corpus — authoring long instruction docs ("lost in the middle" placement), the supply-chain risk of editing skills/hooks/agents, and the eval-harness proposal — has moved to [`maintaining-the-corpus.md`](maintaining-the-corpus.md). The rule for treating untrusted fetched agent/editor config as executable is in [`AGENTS.md`](../AGENTS.md) → *Security*. This file keeps only the Claude-Code-specific harness mechanics below.

## Permission allowlist syntax

When adding entries to `permissions.allow` in `.claude/settings.local.json`:

- **Prefix-match wildcard is space-then-asterisk**, not colon-then-asterisk: `Bash(git fetch *)` — *not* `Bash(git fetch:*)`. The `:*` form is obsolete; current Claude Code matching expects ` *`, and the rest of the file already uses ` *` consistently.
- **Exact-match patterns carry no wildcard at all**: `Bash(git status)` — not `Bash(git status*)` and not `Bash(git status:*)`.
- PowerShell-script entries follow the prefix convention: `Bash(pwsh -NoProfile -File .claude/scripts/<name>.ps1 *)`. Inserting `-NonInteractive` between `-NoProfile` and `-File` breaks the prefix match — see [`agent-rules.md`](agent-rules.md) → *Permission-friendly patterns*.
- **Allowlist target is `settings.local.json`, always.** This project doesn't commit a `.claude/settings.json` — every allowlist-touching skill (`/fewer-permission-prompts` and any future ones) writes into `.claude/settings.local.json`, even when the skill's own default points at `settings.json`. Do not create `settings.json`. Merge into the existing local file, dedupe against what's already there, and don't reorder unrelated keys.

## Harness mechanics the corpus relies on

A few Claude Code internals that several `.claude/` rules quietly depend on — documented here so the rationale is visible (behaviors observed on the v2.1.x line; re-verify if the harness changes):

- **A background subagent can't show a permission dialog, so a gated action becomes a silent `deny`.** An agent spawned to run in the background that hits a permission-gated tool gets it auto-denied rather than queued for approval. This is *why* [`agent-rules.md`](agent-rules.md) → *Agent guardrails* says to frame subagent prompts to allow failure and to verify subagent output with `git status` — a background agent that "couldn't" may simply have been denied a tool, not actually blocked by the task.
- **Compaction paraphrases; it does not preserve recent turns verbatim.** When context auto-compacts, prior turns are replaced by a summary plus recently-accessed files — in-context recall of an exact string, line number, or decision is lossy afterward. Persist load-bearing facts to disk (`.build/.agents/…`, the knowledge base, a doc) rather than trusting they survive a compaction. This underwrites the *Temp files* rule and the KB's existence.
- **One tool call failing cancels its dependent siblings in the same batch.** Batch only genuinely independent calls in a single turn (the *Batch independent tool calls* rule); a dependent call chained into a parallel batch can be cancelled when an earlier sibling errors, so true dependencies stay sequential.
- **`bypassPermissions` still protects `.claude/`, `.git/`, and shell-config paths.** Even with permissions bypassed, edits to those trees stay gated. The guard is keyed on the literal `.claude/` path, which now *is* where the corpus physically lives — so it covers the whole corpus again (under the previous `.claude` → `.agents` symlink layout, an edit addressed to the resolved target slipped past it). Don't lean on it as the only safeguard for corpus edits; it gates the write, it doesn't review it.

A fuller reverse-engineering of these internals (context-management tiers, autocompact buffer, hook return codes) is external write-up territory, not corpus material — the four above are the ones a rule here leans on.
