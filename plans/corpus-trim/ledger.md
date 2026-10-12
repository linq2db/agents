# corpus-trim ledger

Per-bullet disposition for `docs/agent-rules.md` against baseline `37e1c4b`. Read by `.build/.agents/corpus-trim-check.ps1` (TO-2, TO-3) and by the TO-4 clause review.

Dispositions:

- `kept` — trigger text stays in agent-rules, wording compressed; no body moved.
- `trigger-only` — the body already exists in full in the named doc at baseline; agent-rules keeps the trigger.
- `moved` — the body is new to the destination; `Token` must be absent from it at baseline and present after (TO-3).
- `harness-duplicate` — bullet deleted; `Token` column quotes the harness text that states it.

**SC-2 lead-in set.** TO-2 checks *every* bold lead-in at baseline (94 by the script's regex), not only the referenced subset, so the referenced set needs no separate pin; only `harness-duplicate` rows are exempt, and each carries its retargeted references.

`Clauses` lists the obligations taken from the baseline body; `TO-4` marks each found in the post-trim trigger.

## Rows

| Id | Section | Lead-in | Disposition | Destination | Token | Clauses | TO-4 |
|---|---|---|---|---|---|---|---|
| L-01 | Creating a new branch | Name, base and dirty-tree handling are canonical in | kept | — | — | C1 canonical in AGENTS.md · C2 binds every branch-creating skill and ad-hoc branching | C1 ✓ C2 ✓ |
| L-02 | Creating a new branch | Blocked `git checkout` / `gh pr checkout`. | kept | — | — | C1 stop and ask (stash/commit/discard) naming files · C2 no silent worktree workaround | C1 ✓ C2 ✓ |
| L-03 | Creating a new branch | Worktrees are the default for branch-based task work | kept | `worktree.md` | — | C1 worktree, primary clone untouched · C2 root from memory or ask · C3 no ancestor/descendant assumption · C4 /review-pr needs no checkout | C1 ✓ C2 ✓ C3 ✓ C4 ✓ |
| L-04 | Creating a new branch | A separable shared-engine fix gets its own branch/PR | kept | — | — | C1 canonical in AGENTS.md · C2 don't offer to split a coupled fix | C1 ✓ C2 ✓ |
| L-05 | Creating a new branch | A structural migration an audit surfaces gets a filed issue, not a widened PR. | moved | `pr-and-push.md` | `#5861` | C1 file an issue, don't widen · C2 with the audit's evidence · C3 later milestone · C4 cross-link from code | C1 ✓ C2 ✓ C3 ✓ C4 ✓ |
| L-06 | Creating a new branch | Don't switch to a recovery branch mid-rebase. | moved | `pr-and-push.md` | `rebased-but-unpushed` | C1 finish in-flight branch (resolve, force-push) first · C2 then recovery branch off origin/master | C1 ✓ C2 ✓ |
| L-07 | The corpus is a submodule | Commit corpus edits inside the submodule and push them to its `master` | trigger-only | `claude-setup.md` | — | C1 commit+push inside submodule, gated · C2 never on a linq2db branch · C3 leave gitlink alone · C4 trampoline import change needs a linq2db commit | C1 ✓ C2 ✓ C3 ✓ C4 ✓ |
| L-08 | The corpus is a submodule | The superproject's `git status` is blind to the corpus. | kept | — | — | C1 `git -C .claude status` before asserting clean · C2 and after a subagent that could write there | C1 ✓ C2 ✓ |
| L-09 | The corpus is a submodule | The corpus moves under you in both directions. | moved | `claude-setup.md` | `#5880` | C1 commit same turn or re-verify survival · C2 prefer proposing while user curates · C3 re-read script header / log before a workaround | C1 ✓ C2 ✓ C3 ✓ |
| L-10 | The corpus is a submodule | A fresh worktree gets its corpus from `post-checkout`, not from git. | trigger-only | `worktree.md` | — | C1 confirm corpus present before working · C2 switch master before a corpus push | C1 ✓ C2 ✓ |
| L-11 | Dedicated tools over raw CLI | It applies to a background task's output file too — the single most-violated case. | moved | `turn-conduct.md` | `600-line log` | C1 output file → Grep/Read, never grep/tail/sed | C1 ✓ |
| L-12 | Dedicated tools over raw CLI | A working-tree search is evidence about *your checkout*, not about the repo. | moved | `worktree.md` | `#5936` | C1 empty result = not in this checkout · C2 re-ask against a ref · C3 cite line numbers from the branch's checkout | C1 ✓ C2 ✓ C3 ✓ |
| L-13 | Dedicated tools over raw CLI | When an `Edit` fails "string not found" on a line you just read, re-anchor — don't re-guess the indentation. | moved | `windows-gotchas.md` | `number and a tab` | C1 re-anchor from first non-whitespace char | C1 ✓ |
| L-14 | Dedicated tools over raw CLI | Finding the newest test heartbeat is `test-status.ps1`, not `ls -t`. | moved | `testing.md` | `newest by mtime` | C1 use test-status.ps1 / /test-progress, not ls -t | C1 ✓ |
| L-15 | Permission-friendly patterns | `>` redirect | trigger-only | `windows-gotchas.md` | — | C1 no redirect; --jq or persist+Read | C1 ✓ |
| L-16 | Permission-friendly patterns | Inline `pwsh -NoProfile -Command "…"` | trigger-only | `windows-gotchas.md` | — | C1 never inline pwsh; Grep/Read | C1 ✓ |
| L-17 | Permission-friendly patterns | `gh … --body @-` / `-f body=@<file>` | trigger-only | `windows-dev-gotchas.md` | — | C1 literal string; --body-file / --input | C1 ✓ |
| L-18 | Permission-friendly patterns | Scratch scripts | trigger-only | `windows-gotchas.md` | — | C1 under .build/.agents/*.ps1 | C1 ✓ |
| L-19 | Permission-friendly patterns | When the data is already on disk | trigger-only | `windows-gotchas.md` | — | C1 Read/Grep cached data, don't re-fetch | C1 ✓ |
| L-20 | Windows Git Bash gotchas | `git ls-tree … -- '<glob>'` does not glob, and an empty result is not absence. | moved | `windows-dev-gotchas.md` | `#5764` | C1 enumerate via diff --name-only / ls-files then Grep | C1 ✓ |
| L-21 | Windows Git Bash gotchas | `gh … --body` is banned. | trigger-only | `windows-dev-gotchas.md` | — | C1 --body-file only · C2 azp-run.ps1 for /azp | C1 ✓ C2 ✓ |
| L-22 | Windows Git Bash gotchas | (plain) `git fetch <headRefName>` | trigger-only | `windows-dev-gotchas.md` | — | C1 spell both refspec sides | C1 ✓ |
| L-23 | Windows Git Bash gotchas | (plain) Transient `fatal error — add_item` | moved | `windows-dev-gotchas.md` | `#6003` | C1 retry once then Bash unavailable for git/gh this session · C2 hook-running commit/push: wait and retry · C3 never --no-verify | C1 ✓ C2 ✓ C3 ✓ |
| L-24 | Windows Git Bash gotchas | (plain) file stays `M` after `git restore` | trigger-only | `windows-dev-gotchas.md` | — | C1 don't chase · C2 no --assume-unchanged (read merge-blocked case) | C1 ✓ C2 ✓ |
| L-25 | Batching and user interaction | Batch independent tool calls. | harness-duplicate | `claude-setup.md` | "If you intend to call multiple tools and there are no dependencies between the calls, make all of the independent calls in the same … block" (Claude Code system prompt, Opus 5.5 main + Fable 5.1 subagent, 2026-10-13) | C1 batch independent calls in one turn | C1 harness; `claude-setup.md:78` retargeted to "the harness system prompt's own batching rule" |
| L-26 | Batching and user interaction | Do not batch code-change reviews. | kept | — | — | C1 one review turn per unrelated change · C2 group only one logical change | C1 ✓ C2 ✓ |
| L-27 | Batching and user interaction | Interactive review of findings/comments: one at a time, with context. | kept | — | — | C1 one item per turn with context + recommendation · C2 never several in one prompt · C3 overrides ask-ask-do-all | C1 ✓ C2 ✓ C3 ✓ |
| L-28 | Batching and user interaction | On a surprising failure, stop and wait. | trigger-only | `turn-conduct.md` | — | C1 report briefly and wait, no invented workaround · C2 "surprising" = unknown cause; expected reds continue | C1 ✓ C2 ✓ |
| L-29 | Batching and user interaction | After launching a background task, await its completion notification — don't poll the output file. | trigger-only | `turn-conduct.md` | — | C1 await, don't poll · C2 incl. own redirect target and Grep polling · C3 ListAgents/sleep · C4 no "still waiting" turn | C1 ✓ C2 ✓ C3 ✓ C4 ✓ |
| L-30 | Batching and user interaction | A CI wait has its own mechanics | trigger-only | `ci-tests.md` | — | C1 use helper scripts · C2 never loop on gh pr checks | C1 ✓ C2 ✓ |
| L-31 | Batching and user interaction | Two more background-task traps, both repeat offences | trigger-only | `turn-conduct.md` | — | C1 no source edit while its tree's build/test runs · C2 no ScheduleWakeup fallback outside /loop | C1 ✓ C2 ✓ |
| L-32 | Capability self-assessment | Diagnose "stuck" as effort vs. capability before escalating. | moved | `agent-guardrails.md` | `a multiple of the tokens` | C1 effort shortfall → do the missing work first · C2 capability → larger model | C1 ✓ C2 ✓ (via pointer) |
| L-33 | Comments justify decisions, not mechanics | Write a comment only for what the code cannot say: a non-obvious decision, a rejected alternative, a constraint that isn't visible locally. | moved | `code-design.md` | `visitor cleanup pattern` | C1 comment only the non-obvious · C2 pattern-following change → no comment · C3 no commit rationale inline · C4 default zero | C1 ✓ C2 ✓ C3 ✓ C4 ✓ |
| L-34 | Comments justify decisions, not mechanics | A warranted comment is one to three lines. | moved | `code-design.md` | `#5858` | C1 ≤3 lines · C2 conclusion + constraint only; history to commit/PR | C1 ✓ C2 ✓ |
| L-35 | Comments justify decisions, not mechanics | If the rationale already lives in a tracked artifact, the file gets the change and no comment. | moved | `code-design.md` | `mariadb:12` | C1 rationale in issue/commit/PR → no comment · C2 applies to build/CI/setup scripts · C3 keep only file-local facts | C1 ✓ C2 ✓ C3 ✓ |

Unchanged in group 3: *Ask-ask-do-all*, *One label space per turn*, *Cap same-failure retry loops*, *Spend context deliberately*, *Batch edits on a single config file*, *Offering a narrow fix…*, *Two-correction rule*, *Two rules govern how wide…*, *Urgency is not a waiver*, the rest of *Capability self-assessment*, *Inferring rules from user input*. `#5943` dropped from L-31 per U-6 (turn-conduct.md cites #5701 / #6026 for the same traps). `claude-setup.md:76` (*Agent guardrails* → frame subagent prompts) still resolves — lead-in kept — so D-5 needed no edit there.

Unchanged in group 2: *Bash command rules* prose and both bullets; the `gh api`, `git show`, `docker exec`, stdout-decoding and `Glob` one-liners (wording only shortened).

## Dropped provenance fragments

Incidental "how often / where seen" asides with no obligation and no incident number, dropped rather than moved:

- `Read` row of the tools table: "recurred on the `docker-session-started.txt` check".
- `git grep` row: the `fatal: unable to resolve revision: -A` error text and "hit twice in one session out of habit".
- *Worktrees are the default*: "it reads `origin/pr/<n>` via `diff-reader.ps1`" (the `/review-pr` skill owns it).

## Observed, not fixed (P3: no policy changes in this plan)

- `worktree.md:7` says to use a worktree "only when the user explicitly asks", contradicting *Worktrees are the default for branch-based task work* (L-03). Pre-existing; left for a separate pass.
- `pr-and-push.md:10` and `ci-tests.md:59` cite a merge-vs-rebase rule in *Creating a new branch*; it lives in `AGENTS.md`. Pre-existing dangling reference.
