# Gap ledger — issue/6281-nested-cteunion-finalizes-root (PR #6282)

No work plan on this branch; each finding is attributed to the block a plan would have carried.

## Round 1 — reviewed HEAD b433394b6c7db4cdfaa1ade5d5069cdece832d2b

- **MIN001** (test coverage: `NestedInDetachedCollection_RootIsOptimized` narrowed to `AllSQLite` on an unmeasured "SQLite shows it" reason) — GAP-02 — a `P4` unknown "which providers render the unoptimized root?" settled by one merge-base `[DataSources]` run; scope was taken from #6281's single SQLite.MS measurement though the defect is in provider-neutral `BuildQuery`, and PostgreSQL.16 (running for the author's `EagerLoad*` sweep) also fails on master; a `P8` `TO-n` provider scope (`work-plan/SKILL.md:222`) would also have refuted "the Oracle 11 case … is left to CI" — G-01 — preventable: yes

### Aggregate

1 of 1 findings: GAP-02. Pattern: a regression test pinned to the provider its issue was measured on. On a planless branch nothing stops it: `definition-of-done.md:12` fires only on a new `[DataSources]` test, and narrowing takes the test out of that trigger.

### Measurement

Merge base `0678d1dfb` vs head, test on `[DataSources]`, direct + LinqService: master red on SQLite.Classic, SQLite.MS, PostgreSQL.16, DuckDB, Oracle.11.Managed; head green on all. A Skip/Take-in-child variant did not discriminate the child-finalization half on Oracle 11 (mutant with the new check removed also green).

### Corpus trace

- `testing.md:598` already requires a measured reason for an `[IncludeDataSources]` narrowing ("must have failed on at least one excluded provider; an unrun one is a guess"); the PR's reason was unrun. `test-diff-sweep.ps1` counts any `//` line as a reason (`hasReason: true` here), so the detector passed it.
- `definition-of-done.md:12` (beyond-SQLite run) triggers only on `[DataSources]` tests.
- `test-writer.md:89` "Pick the narrowest set that still covers the behavior" reads as endorsing the pin.
- Whether the author's agent loaded this corpus cannot be confirmed.
- Recurs: `feature-between-bound-descriptor/gaps.md` SUG001, `fix-object-to-string-invariant/gaps.md` MIN002, `feature-query-batches/gaps.md` MIN024.
