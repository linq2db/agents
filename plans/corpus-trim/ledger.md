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

Unchanged in group 2: *Bash command rules* prose and both bullets; the `gh api`, `git show`, `docker exec`, stdout-decoding and `Glob` one-liners (wording only shortened).

## Dropped provenance fragments

Incidental "how often / where seen" asides with no obligation and no incident number, dropped rather than moved:

- `Read` row of the tools table: "recurred on the `docker-session-started.txt` check".
- `git grep` row: the `fatal: unable to resolve revision: -A` error text and "hit twice in one session out of habit".
- *Worktrees are the default*: "it reads `origin/pr/<n>` via `diff-reader.ps1`" (the `/review-pr` skill owns it).

## Observed, not fixed (P3: no policy changes in this plan)

- `worktree.md:7` says to use a worktree "only when the user explicitly asks", contradicting *Worktrees are the default for branch-based task work* (L-03). Pre-existing; left for a separate pass.
- `pr-and-push.md:10` and `ci-tests.md:59` cite a merge-vs-rebase rule in *Creating a new branch*; it lives in `AGENTS.md`. Pre-existing dangling reference.
