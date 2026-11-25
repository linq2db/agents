# Gap ledger — PR #6033 (fix/take-constant-sql-cache)

## Round 1 — reviewed HEAD 0902c16e4352200dfc0ae9723476850c675c583f

No plan on the branch; each row names the block that would have carried the finding.

- **BLK001** (tests read QueryInfo.Context, dead since #5673) — GAP-08 — merge 0902c16e4 brought #5673 into both edited files plus QueryInfo.cs / DataConnection.QueryRunner.cs that the tests observe; no G-01 re-run; DoD:28 keys only on the branch's test files, which #5673 did not touch; secondary GAP-05: null/same-instance arms lack a non-null guard so they pass vacuously — G-01 — preventable: yes
- **MIN001** (comment cites removed ConvertSkipTake) — GAP-10 — ConvertSkipTake existed when 2e36cb223 wrote the comment; #5673 removed it later; plain-text comment, no cref, no build catches it — — — preventable: partly
- **SUG001** (PR body describes the pre-#5673 pipeline) — GAP-08 — DoD:29 body refresh not walked after the merge push; no A-n to hang it on without a plan — — — preventable: partly

## Aggregate
2 of 3 trace to blocks a Tier M plan would require (G-01 re-run after an E-n-touching commit; body refresh after a base change); 1 honest GAP-10. Shared cause: merging #5673's render-pipeline rewrite into a branch written against the old pipeline, pushed without re-running anything.

## Recommended durable fixes
1. definition-of-done.md:28 — trigger the merged-tree re-run when master touches any file the branch changes, or a file declaring a member the branch's tests read; then re-walk item 29 against the body.
2. pr-and-push.md:292 — the both-sides-touched check adds: run the branch's tests covering the intersected files; Grep the branch's added lines and PR body for members master deleted since the merge-base.
3. testing.md:1076 — a ShouldBeSameAs over two reads of a nullable cached slot passes when both are null: assert ShouldNotBeNull first; a "renders per execution" arm needs a positive control, not a bare null.

## Corpus trace
- BLK001 — DoD:28 / pr-and-push.md:292 / testing.md:1076 did not fire (test-file-only trigger; build-only check; no non-null guard). Recurs: plans/issue-5797-fix-zoned-difference/gaps.md:23, plans/feature-access-libred/gaps.md:12.
- MIN001 — pr-and-push.md:30 binds the deleting author, not the merging branch.
- SUG001 — DoD:29 is written around follow-up commits and A-n; a merge-only push prompts nobody.

## Continuity
First round on this branch.
