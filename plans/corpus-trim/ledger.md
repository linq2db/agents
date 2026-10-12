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

## Observed, not fixed (P3: no policy changes in this plan)

- `worktree.md:7` says to use a worktree "only when the user explicitly asks", contradicting *Worktrees are the default for branch-based task work* (L-03). Pre-existing; left for a separate pass.
- `pr-and-push.md:10` and `ci-tests.md:59` cite a merge-vs-rebase rule in *Creating a new branch*; it lives in `AGENTS.md`. Pre-existing dangling reference.
