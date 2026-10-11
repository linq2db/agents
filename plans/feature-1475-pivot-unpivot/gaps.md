# Gap ledger: feature-1475-pivot-unpivot

## Round 1 — reviewed HEAD fe655cf93 (2026-10-11)

Plan authored 2026-09-20 19:15, over a branch already carrying ~4,357 lines (SelectDynamic 09-19, the shadowing
guard 09-20). P1–P8 design only the native-emission / static-API removal; P3 freezes the dynamic API without a P7
row, so no finding qualifies as `not-a-gap: out-of-plan-scope`. A-13/A-14 (09-22) superseded D-3/D-4, added the
public type `PivotCells` and two user-expression-tree readers (`SelectDynamicBuilder.FindCellsPlaceholder`,
`LinqExtensions.PivotDynamic.ReadTemplates`, 3a9d54dee) with no re-derived P4/P7/P8, no P12 round and no P9 re-run.

| Finding | GAP | Block that would have carried it | Gate | Preventable |
|---|---|---|---|---|
| MIN001 nested cell chain not found | GAP-02 (+GAP-05) | P4 row per projection shape a placeholder can sit in | G-01 re-derived after A-14 | yes |
| MIN002 pre-built aggregate argument | GAP-02 | P4 row per form of an `Expression<>` argument inside a tree | — | yes |
| MIN003 probe build duplicates tags/hints | GAP-02 | enumeration of builder-scoped state for a throwaway build (dbe4b5636 had no P11 entry) | — | partly |
| Copilot identifier check premise | GAP-02 | P7 row for frozen pre-plan surface; alias path via `CorrectAlias` never checked | — | partly |
| MIN201 count cell reads 0, doc said null | GAP-06 | E-n on user-facing doc naming the SC/D it restates (D-4/A-13 Count qualifier) | — | yes |
| MIN202 `Values` null in non-store roles | GAP-02 | failure-mode line on A-14's one-carrier decision | G-03 re-run after A-14 | yes |
| NIT001 wrong cache-key comment rationale | GAP-10 | — (pre-plan prose) | — | no |
| NIT201 test comment names deleted static API | GAP-03 | P7 prose-consumer row for D-2's deletion | — | yes |
| NIT202 missing `<returns>` | GAP-10 | — (prose completeness) | — | no |
| NIT203 `UnpivotNulls` doc names one consumer | GAP-03 | A-5 / E-22 / P7 prose row listing `UnpivotNulls.cs` | — | yes |
| SUG202 `[InstantHandle]` on `nameSelector` | GAP-01 | convention unstated in `code-design.md` | — | partly |
| SUG203 `[Pure]` on `Cell` | GAP-01 | same; A-14 immutable chain had no failure-mode line | — | partly |
| MIN203 Unpivot name/value pairing unpinned | GAP-05 | TO-1 discriminating input without a recorded mutation | G-01 | yes |
| MIN204 name-factory guard test non-discriminating | GAP-05 | TO-n with recorded mutation for the A-13/A-14 negatives | G-01 | yes |
| SUG201 argument guards untested | GAP-05 | P8 obligation per guard on the surviving surface | — | partly |
| MIN205 SelectDynamic guards untested | GAP-05 | same root as SUG201 | — | partly |
| Same names over different values untested | GAP-05 | A-10's runtime-value-set lesson extended to the query cache | — | partly |
| MIN206 PR body counts stale | GAP-06 | post-push body re-derivation after A-13/A-14 | — | yes |
| OOS ExcludeNulls over outer join | GAP-03 | P7 NULL row scoped to native path only; U-9/D-4 lesson not swept into the lowering | — | partly |
| OOS shadowing guard rejects methods/indexer | GAP-02 (+GAP-05) | which member kinds shadow a dynamic column; fixture per member kind | — | yes |
| OOS public `PivotCells()` constructor | GAP-01 | per-member role enumeration for a new public type | G-03 re-run after A-14 | yes |
| OOS builder errors name SelectDynamic | GAP-03 | P7 row for messages of a builder gaining a second caller | — | partly |

### Aggregate

22 rows: GAP-02 ×6, GAP-05 ×5, GAP-03 ×4, GAP-01 ×3, GAP-06 ×2, GAP-10 ×2. Classes are spread, location is not:
9 of 22 sit in code A-13/A-14 introduced or re-scoped, with no re-derived P4/P7/P8, critic round, or G-01/G-03/G-09
re-run afterwards; 5 more sit in pre-plan code the delta-only plan froze without mapping. The rules that would have
fired existed in prose (P9 re-derivation 09-06, P11 control corollary 09-06, amendment-input-class 09-07) — the
weakness is enforcement, not a missing rule. The "treat a superseding amendment as a new plan pass" rule landed
2026-10-10 (#6003), 18 days after A-14.

### Recommended durable fixes

- GAP-02/05/01 × 9 (A-14 cluster) → `work-plan.ps1 -Action validate`: fail when an `A-n` supersedes a `D-n` or
  introduces a public type unless it carries a `re-derives:` line and a later-dated P12 round.
- GAP-02 × 4 (MIN001, MIN002, shadowing guard, MIN003) → `work-plan/SKILL.md` scout brief + `plan-critic.md`
  attack vector: a design that reads a user-written expression tree needs a P4 row per accepted shape (nested
  construction, `Convert` wrap, interface-typed member, captured `Expression` local / helper result vs inline
  `Quote`); a throwaway build needs an enumeration of builder-scoped state (tags, hints), not a containment argument.
- GAP-05/03 × 5 → `work-plan.md` P3/P7: a plan over a branch that already carries code gives every surviving file a
  P7 row (`covered by E-n` with mutation-recorded characterization, or `out-of-scope` with a reason); "X stays" in
  P3 does not exempt untested surface from P8.
- GAP-01 × 2 (SUG202, SUG203) → `code-design.md`: delegate parameters invoked before return carry
  `[InstantHandle]`; a method returning a new instance of its receiver carries `[Pure]`.

### Outcome

All 22 resolved in the review walk as local commits on `feature/1475-pivot-unpivot` (df7a56733 … e0935d57f);
MIN206 is a PR-body edit. Spun off: #6022 (v7 identifier quoting passthroughs/escaping), #6023 (Sybase
`Name` vs `value`).

## Round 2 — reviewed HEAD 413eaa7be (2026-10-11)

| Finding | GAP | Block that would have carried it | Gate | Preventable |
|---|---|---|---|---|
| MAJ001 two-column multi-value Unpivot untested | GAP-05 | P8 obligation per frozen overload (P3 "both multi-value overloads") | — | yes |
| MIN001 sugar overloads unbuildable inline in a lambda | GAP-02 (+GAP-03) | P4 row: the API call itself left unevaluated inside an outer tree; A-15 sub-query claim rested on a captured-local test | — | yes |
| MIN002 cell aggregate closes over selector `g` | GAP-02 | P4 row on A-14: free variables of a template lambda nested in the selector | — | yes |
| MIN003 nested column path → wrong name label | GAP-03 (+GAP-02) | P7 row for UnpivotBuilder's surviving name derivation (E-10 "lowering stays") | — | partly |
| MIN004 inline message literals, not `ErrorHelper` | GAP-07 | rule only in `code-reviewer.md:262`, absent from `code-design.md` | — | yes |
| MIN005 multi-value overloads lack guards | GAP-03 | P7 sibling-parity row over the Unpivot overload family | — | yes |
| MIN006 #6024 gate declares no error | GAP-07 | `testing.md:87` never embedded for a post-walk test edit | — | yes |
| MIN007 `Values` non-nullable though cells read null | GAP-06 | SC-7 applied by A-15/E-31 to the interface, not the sibling `Values` member | — | partly |
| MIN008 `BuildPivot` skips `ProcessIQueryable()` | GAP-03 | P7 sibling-parity row over the three marker entry points | — | yes |
| SUG001 remarks omit `KeyNotFoundException` split | GAP-10 | — (prose completeness) | — | no |
| SUG002 public `Values` setter | GAP-01 | per-member role table for public type `PivotCells` | — | yes |
| SUG003 `[QueryCacheTest]` on a `[DataSources]` test | GAP-06 | A-6's own "query-cache tests stay narrow", not checked by attribute | — | yes |

### Aggregate

12 rows: GAP-03 ×3, GAP-02 ×2, GAP-06 ×2, GAP-07 ×2, GAP-05 ×1, GAP-01 ×1, GAP-10 ×1. Location again concentrates:
6 of 12 (MAJ001, MIN001, MIN003, MIN005, MIN008, MIN004 partly) sit in pre-plan code P3 froze with one line; 4 (MIN002,
MIN007, SUG001, SUG002) in A-14/A-15's `PivotCells` / in-projection surface. One missing block — a sibling-parity pass
over every surviving overload and entry point (guards, `ProcessIQueryable`, in-tree builder acceptance, test coverage)
— covers MAJ001, MIN005, MIN008 and part of MIN001. Single GAP-10: the design pass still earns its cost.

### Recommended durable fixes

- GAP-03/05 × 4 (MAJ001, MIN005, MIN008, MIN001 partly) → `work-plan.md` P7 + `work-plan.ps1 -Action validate`: per
  public overload family, a sibling-parity row listing per overload: argument guards, `ProcessIQueryable()`, whether the
  builder accepts the in-tree form, and its P8 obligation.
- GAP-02 × 3 (MIN001, MIN002, MIN003) → `work-plan/SKILL.md` scout brief + `plan-critic.md`: replace the instance list
  with generative questions per expression argument — can the call itself sit unevaluated inside another lambda; what
  free variables can a nested lambda capture from an enclosing one; how deep can a member path go.
- GAP-01/06 × 3 (SUG002, MIN007, SUG001 partly; with round 1's constructor + MIN201/MIN202 on the same type) →
  `work-plan.md` P-block rule + `plan-critic.md` vector: a new or reshaped public type gets a per-member table
  (member → role → nullability → SC/D it honours → why public). `PivotCells` has produced six findings over two rounds.

### Continuity

- **Round-1 rec 3 recurs directly** — the "map every surviving file in P7; P3 'X stays' doesn't exempt from P8" rule
  landed (7c8336c) but this plan's P7/P8 were never re-derived under it and `validate` doesn't enforce it. MAJ001,
  MIN003, MIN005, MIN008 sit in exactly that unmapped surface.
- **Round-1 rec 2 recurs with new shapes** — the shape list names round 1's instances; MIN001 (call inline where it was
  assumed evaluated), MIN002 (closure over an enclosing parameter), MIN003 (multi-level member path) aren't on it.
- **Round-1 rec 1 recurs by design** — `re-derives:` + P12 enforcement errors only for entries dated from 2026-10-11, so
  A-13/A-14 (09-22) were never forced through re-derivation; MIN002, MIN007, SUG001, SUG002 sit there.
- **A round-1 block with no durable fix recurs** — per-member role enumeration for a new public type (round-1 OOS
  constructor) never got a home; SUG002 is the same block on the same type, MIN007 repeats MIN201's null-cell miss.
- **The round-1 walk fixed instances, not the class** — 9356b83f8 pinned existing guards (MIN005 is the overloads with
  none); 5fe1bed12 added a cache pin while SUG003 is an older widening of the same attribute class.
- Round-1 rec 4 (`[InstantHandle]`/`[Pure]` in `code-design.md`) did not recur.
