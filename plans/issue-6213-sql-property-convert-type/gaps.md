# Gap ledger — PR 6268 (issue/6213-sql-property-convert-type, no work plan)

## Round 1 — reviewed HEAD b30089e14e9494314d638688dbb9d4b0d6df7316

No plan exists on this branch, so each row names the absent block that would have carried the finding. No `P9` results exist.

- **MAJ001** (this review) — GAP-03 — needed a `P7` row for the readers of the shape `HandleSqlProperty` emits: `EntityBuilderParser.cs:76` `Canonicalise` plus `EntitySetterBuilder.cs:172,187` `IsIgnored`/`FindOverride` and their `UpsertBuilder.cs:128,135` callers, which match by `ExpressionEqualityComparer`; `UpsertBuilder.cs:120` names `Sql.Property` as a selector shape, so a tree-wide search of the touched call reaches it; the row also needed a `P3` delta for "master throws, head drops silently" and a probe; second class `GAP-05`, no `TO-n` on `.Set`/`.Ignore` with `T` differing from the member — — — preventable: partly (the sweep finds the site, but the PR's and igor's Upsert/EntityInsert/EntityUpdate class runs were green because no existing test has that selector shape, so only a per-reader probe exposes it)
- **MIN001** (igor) — GAP-02 — needed a `P4` row probing the guard's whole domain at `ExposeExpressionVisitor.cs:355` (`T` value or reference, by member value or reference): #6213 states the requirement as "converted to `T` when the types differ", so it was named, and the PR body and code comment instead assert that reference `T` must keep the plain access because of `Sql.Property<object>` over `int`, which a master probe of the shapes that actually need it (`.Equals`, `DynamicGoesBanana2`) would have tested; the alternative outcome is a `P10`/`P3` line deferring `object` with a reason — — — preventable: yes
- **MIN002** (igor) — GAP-07 — rule exists at `testing.md:583` (added 2026-10-17 in `ed602b5`, before the PR's 2026-11-08 commit), and no step 4 embed of *Test layout* (`work-plan/SKILL.md:70`, triggered by a `P6` edit-point under `Tests/`) put it in front of the author; neither `CONTRIBUTING.md` nor `.github/copilot-instructions.md` carries it, and the rule lives only in the agent corpus an external contributor has no reason to read — — — preventable: yes
- **NIT001** (this review) — GAP-07 — rule exists at `testing.md:598` (added 2026-10-12 in `406f742`), finding at `Issue6213Tests.cs:39`; same absent step 4 embed as MIN002 and the same absence from contributor-facing docs — — — preventable: yes
- **NIT001** (igor) — GAP-05 — needed a `P8` obligation per surface `Sql.Property<T>` reaches: `TO-n` for `Set(...).Update()` and `Value(...).Insert()`; the PR's three tests at `Issue6213Tests.cs:29,44,58` cover only the three read shapes in #6213 — — — preventable: yes

## Aggregate

3 of 5 findings trace to blocks a Tier M plan would have required (`P7`, `P4`, `P8`). The other 2 trace to the step 4 convention embed; both share one cause: the house test rules never reach a contributor outside the agent corpus.

## Recommended durable fixes

- GAP-07 × 2 → `CONTRIBUTING.md`: state the two test-layout rules (no new `Issue<N>Tests.cs`, one call per line in a chain).
- GAP-03 × 1 → scout brief in `work-plan/SKILL.md` step 5: when an edit changes the node a rewrite emits, list every reader that matches that output structurally, and probe each input that throws on master and now gets through.
- GAP-05 × 1 → `testing.md` *Test layout* or `P8` semantics in `work-plan.md`: a fix to a rewrite shared by read and write paths owes one `TO-n` per path kind.
