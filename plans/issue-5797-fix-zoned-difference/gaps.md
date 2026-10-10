# Gap ledger — issue/5797-fix-zoned-difference (PR #5892)

## Round 1 — reviewed HEAD 7cb6b56ad

No work plan exists on this branch (external contributor). Each finding is attributed to the block that would have carried it. No `P9` gates were recorded, so nothing is classed `GAP-08`.

### Attribution

- **BLK001** — GAP-10. The conflicting content did not exist at plan time: master's #5882 (`76ae8336f`, 2026-09-18) rewrote the #5797 gates as run-and-verify `[ActiveIssue]`s and split out `Issue3766Test2` with its own gate, and #5987 declared the Oracle sub-ms refusal, both after the PR head (2026-09-08). A stale branch at review time, not a design miss. Preventable: no.
- **MAJ001** — GAP-02 (secondary GAP-03). This needed a `P4` row for the new `AsTimestamp` guard, asking whether the resolved `DataType` actually identifies an Oracle `date` column, with a probe of a `date` column mapped as plain `DateTime` (resolves to `DateTime2`). Commit 7cb6b56 asserts that assumption unchecked, while master's own `LowerTemporalArithmetic` remarks describe the counter-shape. Preventable: yes.
- **MAJ002** — GAP-01. This needed a `P2` criterion for the persisted-format change in SQLite Classic `SetParameter`: how rows written before the change behave under IN/Contains, UNIQUE-keyed upserts and GroupBy/Distinct, plus a migration path in the release note. Preventable: yes.
- **MIN001** — GAP-02. The claim that Microsoft.Data.Sqlite "already writes an equivalent ISO form" set the edit's scope (the `SQLiteClassic` guard) and was checkable with one probe (MS binds `.FFFFFFFzzz`). Preventable: partly.
- **MIN002** — GAP-05. This needed a `P8` `TO-n` for an Oracle interval difference over a `date` operand. Every interval test uses `CreateLocalTable` timestamp columns, so the guard's skip branch was never reached on a `date` column. Same root as MAJ001. Preventable: yes.

### Aggregate

4 of 5 findings trace to blocks a Tier M plan would have required (`P4` ×2, `P2` ×1, `P8` ×1). BLK001 is a genuine `GAP-10`. Dominant class `GAP-02`: two unchecked claims about what a type or driver does. One `P4` probe plus matching `TO-n` on the Oracle guard's discriminant would have prevented MAJ001 and MIN002.

### Recommended durable fixes

- GAP-02 ×2 (+ GAP-05 ×1, same root) → `work-plan/SKILL.md` step 5 scout brief: when an edit branches on a resolved `DbDataType`/`DataType`, `P4` lists each mapping shape that reaches it (attribute-declared, CLR-default, `CreateTable`-created), probes every shape whose declared type differs from storage, and each becomes a `TO-n`. A claim about external driver behaviour that narrows `P6` needs a recorded probe.
- GAP-01 ×1 → `plan-critic.md` attack vector: a change to a persisted representation must name, in `P2`, how previously written rows behave under comparison, uniqueness and grouping, and give a migration path in the release note.
- GAP-10 ×1 → `definition-of-done.md` review-side gate: if master touched any test file the PR edits since the PR head, merge master and re-run those tests on the merged tree.
