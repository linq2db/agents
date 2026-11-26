# Gap ledger — PR #6438 (feature/between-bound-descriptor)

## Round 1 — reviewed HEAD 940dd5eab7aca3fb6fe0d5ac0c133bf9679b1ef5

No plan on this branch. Each row names the plan block that would have carried the finding (the branch would be Tier L). The branch builds the parent plan's P3 anti-goal (`plans/feature-between-member-translator/plan.md:54`, D-3 `:101`) with no plan of its own.

- **BLK001** (own new test red on all Access + Firebird) — GAP-08 — G-01 row for 1d23ef39's adopted reviewer `[DataSources]` test, Access/SqlCe locally + container providers (work-plan.md:254, :174); verified on SQLite only — G-01 — preventable: yes
- **MIN001** (side interface IComparedValueTranslationContext, silent null fallback) — GAP-04 — P5 D-n for where UsingComparisonDescriptor lives (ITranslationContext member vs side interface); precedent only in plans/issue-5843-…/plan.md:82-83 — — — preventable: partly
- **MIN002** (converter-only otherRight fallback splits a DataType-declared bound from its twin) — GAP-02 — P4 unknown + D-n separating input + TO-n on the predicate's rejected side (work-plan.md:166, :208); secondary GAP-07 acting-on-findings.md:53 — G-01 — preventable: yes
- **SUG001** (BetweenOfTimeColumn narrowed to SQLite.MS) — GAP-07 — TO-n providers scope (work-plan.md:174); testing.md:580/596 not surfaced; sweep passes any `//` reason — G-01 — preventable: partly
- **NIT001** (one-line chains in a projection) — GAP-08 — G-01 sweep row (definition-of-done.md:11) not run or not acted on; sweep flags :1178/:1180 — G-01 — preventable: yes

### Aggregate
5/5 trace to blocks a Tier-L plan would require; no dominant single class. Common cause: a stacked branch implementing a parent plan's anti-goal with no plan. 3 of 5 (BLK001, MIN002, SUG001) come from one review-fix commit (1d23ef39) verified on SQLite only.

### Recommended durable fixes
1. definition-of-done.md:11 — a new `[DataSources]` test (incl. one adopted from a reviewer snippet) runs on Access/SqlCe and every container provider before push, each excluded family named with a reason; re-run with the sweep on every follow-up commit. (BLK001, NIT001)
2. code-design.md:88 carve-out — ITranslationContext has one sealed implementor and is not user-implemented; a translator capability goes on it next to UsingColumnDescriptor, never on a side interface reached by an `is … ? … : null` cast. (MIN001)
3. work-plan.md P3 — an anti-goal naming a design marks it as needing its own plan; a stacked branch that builds a parent's anti-goal starts with /work-plan seeded from the parent's rejected D-n. (MIN002, SUG001)
4. testing.md:596 do/don't pair (reason must match the attribute) and test-diff-sweep reason check; test-diff-sweep.ps1:85-89 name a chain inside a projection member's argument as a rule-1 defect. (SUG001, NIT001)
