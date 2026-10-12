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
| L-36 | Before coding a fix or feature | Non-trivial work starts with `/work-plan`, before the first source edit. | trigger-only | `work-plan.md` | — | C1 /work-plan before first edit · C2 plan is a corpus artifact, never on a linq2db branch · C3 worktree: switch its .claude to master · C4 critic on a different model passed explicitly | C1 ✓ C2 ✓ C3 ✓ C4 ✓ |
| L-37 | Before coding a fix or feature | When repairing dead or broken code, its payload and its conditions are in scope — don't treat them as fixed points. | moved | `bug-investigation.md` | `false dichotomy` | C1 fix body and predicate to do what the block was for · C2 not delete-vs-restore-as-written | C1 ✓ C2 ✓ |
| L-38 | Before coding a fix or feature | Handling a review finding — yours or someone else's — is | trigger-only | `acting-on-findings.md` | — | C1 read before proving/disputing/accepting/dispositioning · C2..C9 the eight triggers (red first; mechanism vs consequence; accepted claims; re-raise decline; incidental ≠ coverage; adjacent shape → test; provenance; fix it here) | C1 ✓ C2–C9 ✓ |
| L-39 | Before coding a fix or feature | Building the probe that settles any of that is | trigger-only | `evidence-discipline.md` | — | C1 read before write-up/down-scope/measurement · C2..C10 nine triggers (reachability incl. argue-less; sweep absence; instrument corpus; probe lock; control disagrees + measured value + wrong-reason red; mutation/revert traps; false-positive suite; acceptance void on edit; same-path verify) | C1 ✓ C2–C10 ✓ |
| L-40 | Before coding a fix or feature | Repro blocked by a separate, known engine bug → gate the test, defer the fix. | moved | `testing.md` | `blocker's** issue` | C1 gate the regression test on the blocker's issue · C2 defer the fix until the blocker merges | C1 ✓ C2 ✓ |
| L-41 | Before coding a fix or feature | A fix in cross-cutting core gets a core-layer regression test, not only the consumer-level one. | moved | `bug-investigation.md` | `never consumer-specific` | C1 add a consumer-agnostic core test beside the consumer repro · C2 red-proof recipe pointer | C1 ✓ C2 ✓ |
| L-42 | Before coding a fix or feature | Proposing a new cross-cutting core capability? Include a beneficiary survey. | moved | `code-design.md` | `workaround wearing a design's coat` | C1 sweep existing code with the same gap · C2 sweep issues it addresses · C3 fold into the design artifact | C1 ✓ C2 ✓ C3 ✓ |
| L-43 | Investigating & fixing bugs | Attribute a failure to the right layer before working around it. | moved | `bug-investigation.md` | `BatchFixer` | C1 prove it isn't our code before "tool is limited" · C2 isolate in the tool's SDK or a minimal harness | C1 ✓ C2 ✓ |
| L-44 | Investigating & fixing bugs | Explain the mechanism before proposing the fix — and certainly before offering a choice between fixes. | moved | `bug-investigation.md` | `deletes half the candidates` | C1 causal chain first · C2 fix scope falls out of it | C1 ✓ C2 ✓ |
| L-45 | Issue-proposed fix details… | (plain) Every claim you did not run is a hypothesis | trigger-only | `evidence-discipline.md` | — | C1 unrun claims are hypotheses (5 kinds) · C2 falsified comment = mis-scoped change · C3 your change can falsify prose elsewhere | C1 ✓ C2 ✓ C3 ✓ |
| L-46 | Reviewing a PR | (plain) invoke `Skill(review-pr)`; inline → suppression sections first | moved | `review-orchestration.md` | `#5804` | C1 invoke the skill · C2 inline: read both suppression sections first · C3 PublicAPI drift is never a finding | C1 ✓ C2 ✓ C3 ✓ |
| L-47 | Reviewing a PR | `code-reviewer.md` is 58 k tokens — `Grep` it, never `Read` it. | moved | `review-orchestration.md` | `focus-scoping table` | C1 Grep, never Read | C1 ✓ |
| L-48 | Reviewing a PR | An inline review still owes the user the interactive walk. | moved | `review-orchestration.md` | `where is review results` | C1 one finding per turn with evidence/recommendation/dispositions · C2 no consolidated table | C1 ✓ C2 ✓ |
| L-49 | Running tests | Every hand-run `dotnet test` / test-exe invocation carries `--test-progress`. | trigger-only | `testing.md` | — | C1 always pass --test-progress on ad-hoc runs | C1 ✓ |
| L-50 | Running tests | (plain) worktree target → `/test … worktree <path>` | trigger-only | `worktree.md` | — | C1 /test owns worktree runs · C2 hand-run misses --provider/.runsettings/CreateDatabase | C1 ✓ C2 ✓ |
| L-51 | Build & push gotchas | The `MSB4166` / dead-node recovery ladder applies to `dotnet build`, never to `dotnet test`. | kept | `testing.md` | — | C1 recover via explicit dotnet build then --no-build · C2 too-short run did not build | C1 ✓ C2 ✓ |
| L-52 | Build & push gotchas | MSBuild override precedence | trigger-only | `msbuild-override.md` | — | C1 only -p: beats conditional PropertyGroup · C2 -p: on a list replaces; use %3B union | C1 ✓ C2 ✓ |
| L-53 | Build & push gotchas | Before deleting a type or member — or removing/renaming a build or packaging concept (a NuGet package, a project's packable role, a target model) — sweep for references in XML doc-comments and inline comments, not just call sites. | moved | `pr-and-push.md` | `#5711` | C1 sweep comments/XML docs/.csproj · C2 extend to sibling build files · C3 removed NuGet id: check release tags | C1 ✓ C2 (in doc) C3 ✓ |
| L-54 | PowerShell Core scripts | When the agent would otherwise make ≥ 3 related `gh` / `git` calls whose outputs feed each other | trigger-only | `script-authoring.md` | — | C1 ≥3 chained calls → script · C2 skip one-shot | C1 ✓ C2 ✓ |
| L-55 | PowerShell Core scripts | A review finding that names a gap in a repo *procedure* the skills own | kept | — | — | C1 fix by adding the step verbatim to the owning skill · C2 not a PR code change or note | C1 ✓ C2 ✓ |
| L-56 | PowerShell Core scripts | Prefer the PowerShell tool over `Bash(pwsh -NoProfile -File …)` | moved | `script-authoring.md` | `cygheap races` | C1 PowerShell tool by default · C2 Bash wrapper only for shell-only features | C1 ✓ C2 ✓ |
| L-57 | Temp files | (plain) scratch files under `.build/.agents/` | moved | `script-authoring.md` | `pr5678` | C1 under .build/.agents, never OS temp · C2 name by skill+id · C3 never delete wholesale · C4 prefix ≠ session; enumerate with timestamps | C1 ✓ C2 ✓ C3 ✓ C4 ✓ |
| L-58 | Git commit rules | A second cause is a stale base, and it is the one that looks most alarming. | moved | `pr-and-push.md` | `#5860` | C1 diff against the merge base before believing the count · C2 don't checkout master's file onto an old base | C1 ✓ C2 ✓ |
| L-59 | Git commit rules | `git commit --amend` takes the *whole* index — amend with `--only -- <pathspec>` whenever anything else is staged. | kept | — | — | C1 amend with --only pathspec · C2 tell = file count · C3 recovery reset --soft + re-commit | C1 ✓ C2 ✓ C3 ✓ |
| L-60 | Git commit rules | Multi-line commit messages: `Write` the message to a file and `git commit -F <file>`. | moved | `windows-dev-gotchas.md` | `#5723` | C1 Write + -F · C2 here-string leaks @ in Bash · C3 ; && \|\| or banned names → -F · C4 another-repo -F traps pointer | C1 ✓ C2 ✓ C3 ✓ C4 ✓ |
| L-61 | Push to remote rules | When several related PRs are active in one session | kept | — | — | C1 pin unnamed instructions to the primary-goal PR · C2 confirm when ambiguous | C1 ✓ C2 ✓ |
| L-62 | Push to remote rules | After every successful push, check for a PR on the branch | trigger-only | `pr-and-push.md` | — | C1 diff commits vs body · C2 user's PR: append via pr-body-edit.ps1 as a diff · C3 never hand-roll · C4 verify whole body · C5 others' PR: never edit · C6 no PR → propose | C1–C6 ✓ |
| L-63 | Push to remote rules | Immediately after `gh pr create`, check the diff shape | trigger-only | `pr-and-push.md` | — | C1 gh pr view --json commits,files | C1 ✓ |
| L-64 | Push to remote rules | After every successful push, re-request Copilot review | trigger-only | `pr-and-push.md` | — | C1 gh pr edit --add-reviewer copilot-pull-request-reviewer · C2 not slug Copilot, not REST | C1 ✓ C2 ✓ |
| L-65 | Agent guardrails (anchor set) | Verify subagent output with `git status` after every invocation. | moved | `agent-guardrails.md` | `cannot change to '.claude'` | C1 only in-scope files modified · C2 also git -C <primary-clone>/.claude status, absolute · C3 unexpected files → suspect + restore | C1 ✓ C2 ✓ C3 ✓ |
| L-66 | Agent guardrails (anchor set) | A subagent's reported result is a claim, not evidence — verify it against an artifact. | moved | `agent-guardrails.md` | `3.066 s` | C1 confirm a gating pass/fail against a non-agent artifact · C2 implausible metric → re-derive the whole result | C1 ✓ C2 ✓ |
| L-67 | Agent guardrails (anchor set) | Frame subagent prompts to allow failure. | kept | — | — | C1 make "report what's missing" a valid outcome · C2 invite blocked/needDisambiguation | C1 ✓ C2 ✓ |

Group 6 notes: *Never commit playground scratch*, *Large-scale deletions…*, *Amending a commit on a non-checked-out branch…*, *Splitting one file's hunks…*, *Orphaned baselines…*, *Pull request rules*, *Docker containers*, *GitHub content authoring*, the guardrails intro, *Don't reformat…*, the two liveness / refutation sub-bullets, *Don't let progress artifacts outpace real work* and *Never hand-edit API baseline files* are unchanged. D-5 retargets applied: `testing.md:110` → `agent-guardrails.md`, `windows-dev-gotchas.md:546` → `pr-and-push.md`.

Group 5 notes: *Start from the KB…*, *Situational triggers*, *Except the bare-NUnit hosts*, *TFM API availability*, *Iterative-build…*, *The same rule of three…*, *Invoking one has argument-passing traps…* are unchanged or only shortened. L-53 C2 (sibling build files) now lives only in `pr-and-push.md`; the trigger names the sweep, not every file kind. Plan amendment A-1 adds E-13/E-14.

Group 4 notes: the section intro, *Do a blind-spot pass…*, *Offer the root-cause alternative…* and *A statically decidable invariant…* are unchanged. `bug-investigation.md:39`'s owner back-reference now points at the new section above it (D-5). The *Distinct lenses … satisfied by construction* remark on L-36 was dropped as rationale with no obligation (logged under *Dropped provenance fragments*).

Unchanged in group 3: *Ask-ask-do-all*, *One label space per turn*, *Cap same-failure retry loops*, *Spend context deliberately*, *Batch edits on a single config file*, *Offering a narrow fix…*, *Two-correction rule*, *Two rules govern how wide…*, *Urgency is not a waiver*, the rest of *Capability self-assessment*, *Inferring rules from user input*. `#5943` dropped from L-31 per U-6 (turn-conduct.md cites #5701 / #6026 for the same traps). `claude-setup.md:76` (*Agent guardrails* → frame subagent prompts) still resolves — lead-in kept — so D-5 needed no edit there.

Unchanged in group 2: *Bash command rules* prose and both bullets; the `gh api`, `git show`, `docker exec`, stdout-decoding and `Glob` one-liners (wording only shortened).

## Final pass (after group 6)

Compressed non-trigger text, every trigger kept: the opening paragraph; the guardrails intro (section titles kept verbatim after review); the *Situational triggers* tail; the *CI investigation* index (all five question → script mappings and the never-hand-roll rule kept; parameter spellings, the `gate-holds` note and the issue list live in `ci-tests.md:143-160`, `:203-213`, `:292-311`, `:321`). Correction: the group-3 note's "rest of *Capability self-assessment* unchanged" is superseded by this pass.

## TO-4 independent review (plan-critic-style, `fable`, 2026-10-13)

67/67 rows plus 6 unlisted changed items checked against `37e1c4b`. **Meaning changed: none.** Responses:

- Lost clauses restored to the trigger: L-53 C2 (`.csproj` + sibling build files), the `Glob` one-liner ("or reimplementing the helper"), L-57 ("create it before the first write"), L-09 C3 ("a third repetition … is the signal"), L-48 ("resolved before the next"). L-20 gained a per-bullet pointer.
- Rationale given a home: L-28 "a workaround invented mid-failure masks a real signal" → `turn-conduct.md` *Stopping and retrying*; L-26 / L-27 rationale → `turn-conduct.md` *Asking* ("Why reviews go one change, or one finding, per turn"); L-31 stale-DLL remark → `turn-conduct.md` in-flight-edit bullet; L-50 "needs `--project`" → `worktree.md` *Running tests from a worktree*; L-62 `#5686` → `pr-and-push.md` PR-body section.
- Accepted as equivalent by the reviewer: L-24, the CI-index "never hand-roll", L-46.
- Still logged as dropped: L-36's *Distinct lenses … by construction* remark.
- Ledger notes corrected: the guardrails intro was changed (now restores the exact titles); L-36's worktree mechanic lives in the trigger and `worktree.md`, not `work-plan.md`.

## Dropped provenance fragments

Incidental "how often / where seen" asides with no obligation and no incident number, dropped rather than moved:

- `Read` row of the tools table: "recurred on the `docker-session-started.txt` check".
- `git grep` row: the `fatal: unable to resolve revision: -A` error text and "hit twice in one session out of habit".
- *Worktrees are the default*: "it reads `origin/pr/<n>` via `diff-reader.ps1`" (the `/review-pr` skill owns it).
- *CI investigation*: the issue list "(#5819, #5828, #5841, #5882)"; `ci-tests.md` cites #5819 and #5828 for the same scripts.
- *Non-trivial work starts with `/work-plan`*: "the model difference *is* the mechanism, and the one place `agent-guardrails.md` → *Distinct lenses for parallel reviewers* is satisfied by construction".

## Observed, not fixed (P3: no policy changes in this plan)

- `worktree.md:7` says to use a worktree "only when the user explicitly asks", contradicting *Worktrees are the default for branch-based task work* (L-03). Pre-existing; left for a separate pass.
- `pr-and-push.md:10` and `ci-tests.md:59` cite a merge-vs-rebase rule in *Creating a new branch*; it lives in `AGENTS.md`. Pre-existing dangling reference.
