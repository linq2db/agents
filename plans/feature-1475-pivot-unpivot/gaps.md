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
