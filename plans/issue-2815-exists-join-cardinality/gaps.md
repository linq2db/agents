# Gap ledger — PR #6333 (issue/2815-exists-join-cardinality)

No work plan on this branch (external contributor). Rows name the block a plan would have needed.

## Round 1 — reviewed HEAD 389c6959d513c6c36f4dca1940338fdf622f0bb4

- **MIN001** (vestigial `ignoreJoinCardinality` on `RemoveUnusedLeftJoins`, false doc at JoinsOptimizer.cs:81-84) — GAP-09 — round-2 rework (389c6959d) superseded round-1's whole-subtree design (e00f4c032) with no amendment re-deriving the widened `RemoveUnusedLeftJoins` P6 row and its single `Optimize` caller (passes `false`); second class GAP-03 — — — preventable: yes
- **NIT001** (test layout at JoinOptimizeTests.cs:852-875 + 7 siblings) — GAP-07 — no `conventions:` embed of testing.md → Test layout for the external author; igor round-1 MIN002 fix text prescribed hand-duplicated `AreEqual` "as the rest of the file does" (file has 0 `AreEqual`, 1 `AssertQuery`); second class GAP-08 (test-diff-sweep never ran); EXCEPT ALL exception (#6457) is GAP-10 — G-01 — preventable: partly

## Aggregate

2 of 2 final findings trace to blocks a plan would have required; 6 of 7 counting igor's prior rounds (only round-1 NIT001 prose is GAP-10). Both final findings descend from a round-1 reviewer Fix text applied verbatim by the author and then marked "fixed" by round 2.

## Recommended durable fixes (proposed, not applied)

1. GAP-07 → `agents/code-reviewer.md` *Test layout in added test code* (~:265-270) or `docs/acting-on-findings.md:31`: a Fix that prescribes test code must itself use the Test layout form, and must not justify a form with "as the rest of the file does" without checking the file.
2. GAP-09 → `skills/review-pr/SKILL.md` / verify step: before marking a prior finding fixed, re-check its applied fix against the other fixes in the same commit (a wording fix can be falsified by an adjacent scope fix); run code-reviewer.md:192's orphaned-code check against the superseded approach.
3. GAP-02 → `docs/pr-and-push.md:194`: when a PR downgrades `Fixes #n` to `Relates to`, every commit message carrying the closing keyword must be reworded too (squash body concatenates them).

## Corpus trace

- MIN001 · rules: code-reviewer.md:192 (orphaned code), evidence-discipline.md:223 · didn't fire: external author; round-2 verified wording landed, not that it stayed true · correction: fix 2 · recurs: acting-on-findings.md:51 (#5750)
- NIT001 · rules: testing.md:651-711, code-reviewer.md:265-270 · didn't fire: external author; round 1 missed the layout and its MIN002 Fix seeded the hand-duplicated form · correction: fix 1 · recurs: plans/feature-access-libred-dialect/gaps.md:98,122; plans/feature-fix-concat-param-varchar-type/gaps.md:82
- igor round-1 BLK001/BLK002 · plan block: P4 premise "only row presence matters" checked per scope/operator + negative TO-n per guard (GAP-02/GAP-05) · fixed by author in round 2
- igor round-1 MIN001 / still-actual commit message · plan block: P2 SC-n reproducing the issue's own Oracle UPDATE shape (GAP-02) · no rule covers closing keywords in commit messages · correction: fix 3 · recurs: plans/issue-5814-projectflags-condition-analyzer/gaps.md:25
- igor round-1 MIN002 · plan block: P8 TO-n comparing rows (GAP-05) · correction: see NIT001
- igor round-1 NIT001 · GAP-10 (prose) · correction: see MIN001
