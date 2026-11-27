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

## Round 4 — reviewed HEAD bf00c3547 (2026-11-26)

The round-4 findings were fixed in `28c9baef2`…`8f2029f35` and recorded as A-20. MAJ, MIN and MIN310 sit in `48de1d7cf`, and TO-34's test sits in `d30f7dc41`. Both commits are A-19's redesign answering critic round A-19. They were committed at 13:23, after that round's verdict, and recorded in plan commit `1404040` at 13:28. No delta round attacked them. This ledger has no Round 3 section. Rounds 1–2 are tables, which `gap-report` does not parse (it currently exits "no parseable attribution rows"), so only this round will count.

### Attribution

- **MAJ** (row-dependent cell name throws on re-execution) — GAP-03 — A-19's P7 row on `[SqlQueryDependent]` readers (plan.md:352) searched only `ExposeExpressionVisitor` (`GetQueryDependentAttributes` :184, `PrepareForCache`) and concluded "a row-dependent name stays as written"; the query-cache compare (`EqualsToVisitor` → base `ExpressionsEqual`, which evaluates both sides) was never listed, and A-20's repo-wide `git grep -n SqlQueryDependent` row is the search that finds it; second class GAP-02: the attribute's own summary (`SqlQueryDependentAttribute.cs:14-15`, "will be evaluated on client side") rules out a row-reading argument; TO-33 had only a captured-name arm; E-55 arrived in fold-in `48de1d7cf` — G-09 (no A-19 delta read before the push) — preventable: yes
- **MIN** (`Get<T>` in a SQL position read as the cell's own type; absent name unnamed) — GAP-01 — as A-19 wrote it, SC-17 said only "read the cell's column" for `Where` / `OrderBy` / an Unpivot column; it never said what a read as another `T` returns or what an absent name raises in SQL (A-20's cast-to-`T` is a user decision from the walk); its position list also left out `Distinct`, aggregates and grouping keys, which A-20's P7 row added (`DistinctBuilder.cs:47`); second class GAP-03 against SKILL.md:106's consumer census; E-54 decides a predicate with no D-n and is fold-in `48de1d7cf` — G-09 — preventable: partly
- **MIN310** (Unpivot cast chain over a cell read throws `ArgumentException`) — GAP-02 — no P4 row covers the selector shapes `ReadCellAsColumn` accepts, and E-53's strip-and-rewrap assumed one conversion over the read; critic round A-19 objection 6 probed `ConvertChecked` and a cast receiver against the earlier expose-rewrite form, but the strip-and-rewrap arrived in fold-in `48de1d7cf` after that round — G-09 — preventable: yes
- **MIN411** (`Sql.Property` over an `IReadOnlyDictionary`-typed member cannot be converted) — GAP-02 — P12 round 8 recorded "`DynamicColumnInfo` equality is name-keyed" as its strongest confirmation (plan.md:1240), but equality keys on Name and `DeclaringType` (`DynamicColumnInfo.cs:51-70`, per A-20's P7 row); P10's A-17 line (plan.md:555) promises flat-DTO reads through `Sql.Property(r.Cells, …)`, U-24 admits the interface-typed member for materialization only, and TO-22 composes only over a `PivotCells`-typed member; nobody crossed the two; the defect predates A-19 (TO-41's arm was red with the translation off too) — G-09 — preventable: yes
- **SUG001** (Unpivot selector error still says "simple member access") — GAP-03 — E-53 widened what an Unpivot selector accepts to cell reads, but A-19's three P7 rows list only code readers; no prose row covers `Error_UnpivotColumnSelector` (`ErrorHelper.cs:183`), the message that lists the accepted forms — G-09 — preventable: yes
- **MIN413** (name-column rule undocumented on the Unpivot overloads) — GAP-03 — SC-16 changed a user-visible rule of both `Unpivot` selector overloads, and A-19 had no E-n for their `resultSelector` docs (A-20 added E-64); this is the same missing prose row as SUG001; G-03's doc-content check (definition-of-done.md:16) was never re-recorded after A-17, and `validate` still warns "G-03 names no D-n / A-n contract point" — G-03 — preventable: yes
- **MIN412** (one of three assertion fixes in `b2a1db833`) — GAP-05 — the three arms: TO-34 asserted only names, so two branches reading one pivot's column passed (written in fold-in `d30f7dc41` after round A-19 accepted objection 4 for TO-30 only); TO-15 never pinned `GetDynamicMemberNames` on the `DynamicObject` D-9 introduced; TO-24 asserted row and store counts, not cell values; the inputs do not map ids to arms, but every arm is GAP-05 — G-01 — preventable: partly
- **MIN414** (one of three assertion fixes in `b2a1db833`) — GAP-05 — same three arms as MIN412 (TO-34 values, TO-15 `GetDynamicMemberNames`, TO-24 cell sums); id-to-arm mapping not in the inputs — G-01 — preventable: partly
- **SUG202** (one of three assertion fixes in `b2a1db833`) — GAP-05 — same three arms as MIN412; id-to-arm mapping not in the inputs — G-01 — preventable: partly
- **NIT-CHAINS** (84 one-line and 4 nested chains; part of NIT001, NIT201…NIT211) — GAP-06 — `testing.md:661` (one call per line, 2026-10-12) was embedded by A-17's `conventions:` line and by E-48's "house rules apply in full", and A-17's tests broke it with no sweep run; second class GAP-08: A-19's G-01 sweep counted 84 / 4 and recorded them as review items instead of fixing them (plan.md:482, P11 A-19) — G-01 — preventable: yes
- **NIT-REASONS** (5 narrowed provider sets without a reason line; part of NIT001, NIT201…NIT211) — GAP-06 — P7 (plan.md:346) says "covered by E-48 (each ported narrowed test states its reason)", yet 5 survived; A-19's sweep reported `narrowedWithoutReason 5` and handed them to review — G-01 — preventable: yes
- **NIT-THROWS** (28 `ShouldThrow` sites converted to `Assert.That`; part of NIT001, NIT201…NIT211) — GAP-07 — the rule is `testing.md:5-10` (2026-11-15, #6330), placed above *Test layout*; A-19 embedded only *Test layout*, *A narrowed provider set is a claim* and *Gating an assertion failure*; `test-diff-sweep.ps1` has no category for it; most sites predate the rule (A-17 tests, 2026-10-22) — — — preventable: partly
- **NIT-REGION** (`#region` around the added `DynamicColumnsTests` tests; part of NIT001, NIT201…NIT211) — GAP-07 — `testing.md:647` sits under *Test Patterns*, not the embedded *Test layout*; there is no sweep category for it; the tests were written under A-17 outside P6, and E-52 recorded them only in A-19 — — — preventable: partly
- **F** (held cells copied into a query row, then filtered) — not-a-gap: out-of-plan-scope — A-20's P7 row (plan.md:359): "could not be converted" with the translation off, so not a regression, "out-of-scope (no shape on master reads it)"; the row was written in answer to the finding, and no code changed

`8f2029f35` also realigned one parameter in `LinqExtensions.Unpivot.cs`. The inputs do not say whether a NIT named it, so it has no row.

Context from critic round A-20, which ran after the review. These are not review findings and get no ledger rows.

- `Get<int>` over a `decimal?` cell in an Unpivot column threw `ArgumentException`. This is MIN310's reader meeting its next shape: E-62 typed the access as the read's type, while the pivot binds the aggregate's type. Same GAP-02 class.
- A cast receiver lost its path in the Unpivot name column, because `GetColumnName` stopped at the `Convert`. Same reader-shape class. Critic round A-19 objection 6 had named a cast receiver, and A-19's P7 row (plan.md:351) left it "unprobed under the build-visitor E-54". That is a lead carried to review, against work-plan.md:350.
- `Sql.Property` over an interface-typed member failed under `Concat`. This is MIN411's class, and the "set-operator sources" half of SKILL.md:90. A-20's E-63 had dropped the generic-constructor branch because TO-41 did not reach it.

### Aggregate

There are 13 classed rows, with the 12 NIT ids collapsed into 4 category rows because the inputs have no per-id split, plus 1 not-a-gap. Counts: GAP-03 ×3, GAP-05 ×3, GAP-02 ×2, GAP-06 ×2, GAP-07 ×2, GAP-01 ×1, GAP-10 ×0. The classes are spread, but the location is not. 6 of 13 rows (MAJ, MIN, MIN310, TO-34's arm, SUG001, MIN413) sit in A-19's post-verdict redesign `48de1d7cf` / `d30f7dc41` or in the prose it made stale. That is design no critic attacked, against work-plan.md:354.

The single change that would have prevented the most is enforcing the fold-in delta round. The evidence that such a round works: critic round A-20, run on A-20's own fixes, found three measured defects of these same classes before the push. There is also a second-order miss. A-19 was pushed to an open PR without its own G-09 line (definition-of-done.md:28), so round 4 was that read, done after the push. Zero GAP-10 means the design pass is still earning its cost.

### Recommended durable fixes

- GAP-03/01/02/05 × 6 (MAJ, MIN, MIN310, SUG001, MIN413, TO-34's arm) → `work-plan.ps1 -Action validate`, the fold-in check (`work-plan.ps1:939-972`), plus *Mode: amend* in `work-plan/SKILL.md`.
  - Make edit-point commits after the last critic-reviewed sha an error under `-Done`, not a warning.
  - Resolve `-RepoRoot` to the worktree of the plan's `Branch`. Run by default from the primary clone, the check measures master: today's run names `63286e528`, a master commit.
  - Name the rule in amend mode, which never mentions it.
- GAP-06/07 × 4 rows (12 NIT ids) → `testing.md`, `test-diff-sweep.ps1` and `work-plan/SKILL.md:322`.
  - Rewrite `testing.md:1183`, which still says to "assert it as `Action act = () => …;` then `act.ShouldThrow<T>()`".
  - Add sweep categories for a Shouldly exception assertion and for `#region`.
  - Add the exception-form section and *Test Patterns* to the embed list at `SKILL.md:73`.
  - Restrict `SKILL.md:322`'s "name it as a review item" to adopted commits.
  - Have the G-01 deferral check match "dispositioned in A-n".
- GAP-02/01 × 3 (MIN310, MIN411, MIN), plus all three context defects → *Mode: amend* in `work-plan/SKILL.md`.
  - Run step 5's question list over each new E-n: `:90` input shapes, including dynamic columns through `Sql.Property` and set-operator sources; `:106` consumer census.
  - Land the reader-shape question in step 5 and in `plan-critic.md`: conversions above and below the matched node, cast receiver, interface-typed member. Rounds 1 and 2 recommended it and it never landed.

### Corpus trace

- MAJ · rule: `plan-critic.md:32` (grep the callers of every changed symbol); `work-plan.md:354` (a fold-in needs a delta round) · why it did not fire: E-55 was a fold-in after round A-19's verdict. The author read `PrepareForCache`'s `CanBeEvaluated` guard as the whole contract, although the attribute's summary says the argument is client-evaluated. The fold-in check is warning-only and blind to branch commits when run from the primary clone · correction: `work-plan.ps1` fold-in check, per durable fix 1 · recurs: round 1 aggregate (9 of 22 in A-13/A-14 code with no critic round).
- MIN · rule: `work-plan.md:311` (an E-n with a new predicate carries its own D-n, 2026-11-15); `SKILL.md:106` (consumer census) · why it did not fire: the own-D-n check (`work-plan.ps1:780-786`) triggers only on literal "D-n stands" text, which A-19 lacks, so E-54's predicate (receiver typed `PivotCells`, `BuildPurpose.Sql`, evaluable name) had no failure-mode or reach line, and SC-17 was written from the two repro positions · correction: `work-plan.ps1:782`, also fire on any A-n that adds an E-n under `Internal/Linq/Builder` that no P5 D-n names · recurs: round 2 rec 3 (per-member contract table for `PivotCells`).
- MIN310 · rule: none in the corpus. U-24's "(reader-shape rule.)" is plan-local, and a grep of `docs/`, `agents/` and `skills/` finds nothing · why it did not fire: no rule exists · correction: `SKILL.md` step 5 and a `plan-critic.md` vector. For each reader of a user-written lambda, list the conversions above and below the matched node, and require the rewrite to replace only the matched node · recurs: round 1 rec 2, round 2 rec 2; critic round A-20 objections 2–3 (context).
- MIN411 · rule: `SKILL.md:90` (2026-11-09) · why it did not fire: it landed after A-17's approval (2026-10-22), and amend mode (`SKILL.md:311-323`) never re-runs step 5's questions; round 8's false equality claim was never re-read against `DynamicColumnInfo.cs` · correction: `SKILL.md` *Mode: amend*, per durable fix 3 · recurs: the `Concat` defect in context.
- SUG001 · rule: `SKILL.md:317` (an amendment that changes a rule re-runs P7's prose sweep) · why it did not fire: widening a reader's accepted input set did not read as a "rule change"; A-19's P7 rows are code readers only · correction: `SKILL.md:317`, name "a reader's accepted input set" as a rule whose rejection messages and docs are prose · recurs: round 1 "builder errors name SelectDynamic" (GAP-03), NIT203.
- MIN413 · rule: `SKILL.md:317`; `definition-of-done.md:16` · why it did not fire: as for SUG001, and G-03 was recorded once, before A-17, with its warning left standing · correction: as for SUG001 · recurs: round 1 MIN201.
- MIN412 / MIN414 / SUG202 · rule: `plan-critic.md:34` (a test fixed for not separating re-checks its siblings) · why it did not fire: TO-34's test was a fold-in after the round, and TO-15 / TO-24 are A-17 characterizations with no discriminating input · correction: `plan-critic.md:34`, extend it to the round's own fold-ins · recurs: round 1 MIN203 / MIN204.
- NIT-CHAINS / NIT-REASONS · rule: `testing.md:661`, `testing.md:572`; `definition-of-done.md:11` ("never waived as outside this plan") · why it did not fire: A-17 embedded the rules but ran no sweep (validate: "A-17 has a conventions: line that cites no test-diff-sweep.ps1 run"). A-19's sweep found the hits and took `SKILL.md:322`'s adopted-commits option for its own code. Its G-01 wording slipped past `work-plan.md:228`'s "review item" refusal, and the P11 warning was ignored · correction: per durable fix 2 · recurs: —.
- NIT-THROWS · rule: `testing.md:5-10` · why it did not fire: outside the embedded sections; contradicted by `testing.md:1183`; no detector · correction: per durable fix 2 · recurs: the #5969 round-3 pattern (a rule's own neighbouring text endorsing the retired form).
- NIT-REGION · rule: `testing.md:647` · why it did not fire: it sits under *Test Patterns*, which is not embedded; no detector; the edit was outside P6 when written · correction: per durable fix 2 · recurs: —.

### Continuity

- **Round-1 rec 2 and round-2 rec 2 (reader shapes, generative questions per expression argument) did not land.** A grep of `work-plan.md`, `plan-critic.md` and `work-plan/SKILL.md` for `free variable`, `nested lambda`, `Convert wrap`, `interface-typed` and `reader-shape` returns nothing. They recur as MIN310 and as two of the three context defects. `SKILL.md:90` (#6133) covers only the pipeline-input half.
- **Round-2 rec 3 (per-member contract table for a public type) did not land.** `per-member` and `role table` have no hits. `PivotCells` adds MIN (`Get<T>`'s SQL contract) and the `GetDynamicMemberNames` arm, on top of six findings in rounds 1–2.
- **Round-1 rec 1 landed (`work-plan.md:320`) but covers only supersede / public-type amendments.** Its underlying class, design that reached review without a critic, recurs here as the post-verdict fold-in. That rule exists (`work-plan.md:354`) but is unenforced.
- **Round-1 GAP-03 prose rows (builder messages, NIT203, MIN201) recur** as SUG001 and MIN413.
- **Round-1 MIN203 / MIN204 (non-discriminating TO) recur** as TO-34's arm.
- **Round-2 MIN006 (a test rule outside the embedded sections) recurs** as NIT-THROWS and NIT-REGION.
- **Round-2's "the walk fixed instances, not the class" recurs.** A-19 and A-20 both lack a `class:` line (`validate` warns on both). A-20's E-63 dropped the branch that `Concat` needed, and A-20's E-62 fixed one conversion shape where critic round A-20 found the next.
- **Did not recur:** round-1 rec 3 (`work-plan.md:154`), round-1 rec 4 (`code-design.md:170`), round-2 rec 1 (sibling-parity row; not landed either).
