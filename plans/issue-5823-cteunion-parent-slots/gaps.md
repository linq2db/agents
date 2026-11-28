# Gap ledger — issue/5823-cteunion-parent-slots (PR #6285)

## Round 1 — reviewed HEAD 297487d7c

No work plan on this branch; attribution is to the block a Tier M plan would have required.

- **MAJ001** (ParentReadsOnlyTheKey asserts readers == 1 on non-CTE providers) — GAP-05 — P8 TO-n for the one-reader claim needed a `providers:` scope with one arm per side of ResolveStrategy's CteUnion→KeyedQuery remap (ExpressionBuilder.EagerLoad.cs:551); author ran only CTE-capable providers; secondary GAP-02 (assumption contradicted by the fixture's IsCteSupported idiom) — G-01 — preventable: yes
- **MAJ002** (ParentReadsCheckedAggregate lacks [ThrowsRequiresCorrelatedSubquery]) — GAP-02 — P8 row comparing gates with same-shape sibling Select_Union_ScalarAndCollection (:483-484); plan-critic.md:61 vector covers it; no run touched YDB/ClickHouse — G-01 — preventable: yes
- **MIN001** (ParentReadsCheckedAggregate never asserts row count) — GAP-10 — test-prose weakness no design block carries; caught only by exit-side read (test-review-checklist.md:127) — G-09 — preventable: partly
- **NIT001** (new tests exclude AllAccess; master switched to AllNativeAccess) — GAP-10 — convention changed by #5956 (2026-11-15) after the head commit (2026-11-09); catch point is the master merge (definition-of-done.md:30) — — — preventable: no

### Aggregate
2/4 (both Majors) trace to plan blocks: a provider-scoped P8 obligation spanning the fixture's capability split, and the critic's sibling-gate comparison. Shared mechanism: new tests copied sibling *bodies* but not their provider-capability idioms, and the local run had no provider on the other side of either capability. The rule exists reviewer-side (rubric-tests.md, test-review-checklist.md:53) and plan-side (plan-critic.md:61) only — not author-side.

### Recommended durable fixes (unapplied)
1. testing.md (near :913/:921) + agents/test-writer.md: a new [DataSources] test in an existing fixture copies the closest same-shape sibling's capability idioms — fixture-helper expected values (`IsCteSupported(context) ? 1 : 2`) and [ThrowsForProvider]-family gates with variant — and the local run names a provider on each side of the capability.
2. testing.md → *Assertions that pass on nothing* (:1343): author-side twin of test-review-checklist.md:127 — pin `result.Count` before a per-row loop over a query result.
3. NIT001: none (definition-of-done.md:30 covers it).

### Corpus trace
- MAJ001: plan-side work-plan.md:178/:234 and exit-side definition-of-done.md:12 (landed 2026-11-25, after the commit); no author-facing doc says an eager-load reader count depends on the strategy remap. Recurs: plans/issue-5932-mark-optional-row-values/gaps.md:120,:180.
- MAJ002: rubric-tests.md (since ae3fe8f) and plan-critic.md:61 (since baa2446) — neither runs for a planless author; testing.md names only Except/Intersect and apply-join instances; test-writer.md has no gate-mirroring step. Recurs: plans/issue-6024-fix-oracle11-isnotnull-validator/gaps.md:7.
- MIN001: test-review-checklist.md:127 reviewer-side only; testing.md:1343 lacks the per-row-loop case.
- NIT001: no rule missing.
