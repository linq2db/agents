# Gap ledger — issue/5955-clickhouse-datetime64-coercion (PR #5959)

## Round 1 — reviewed HEAD ee69074134d995debea0041f0d0de9acb56306c0

No work plan exists on this branch; attributed against the absent artifact.

| Finding | Gap | Would-have-carried block | Gate | Preventable |
|---|---|---|---|---|
| BLK001 stale `[ActiveIssue(5955)]` on `IntervalTranslationTests.Difference.cs:230` (arrived via master #5987) | GAP-03 | `P7` row from a grep of `ActiveIssue(5955` across `Tests/`; `P4` "no gate on the fixed issue remains" | G-01 | yes |
| MIN001 SQL Server `datetime` parameter typed `datetime2` beside MAX/COALESCE | GAP-02 | `P5`/`P7` consumer rows for `SuggestColumnDescriptor`; `TO-n` SQL Server probe | — | partly |
| MIN002 set-op literal narrowed across from MAX(dateCol) | GAP-02 | `P7` caller sweep of the `QueryHelper.GetDbDataType` Element arm (`SetOperationBuilder`) | — | partly |
| MIN201 unanchored `ActiveIssue` `ErrorMessage` | GAP-06 | convention rule (`{1}but was`) | — | yes |
| SUG201 `MinMax…` test hand-feeds `SqlArgumentDomain.Element` | GAP-05 | `TO-n` must go through `ForAggregate` | — | yes |
| SUG202 coarse comparison test covers literal path only | GAP-05 | `TO-n` covering literal and parameter paths | — | yes |
| NIT201 "everywhere" remark vs YDB exclusion | GAP-10 | — | — | no |
| OOS Informix `DateTime2` CAST → FRACTION(3) | GAP-03 | `P7` row for sibling provider CAST rendering | — | partly |

### Aggregate

7 of 8 trace to blocks a Tier M plan would have required. Dominant class GAP-03 + GAP-02 (5): shared descriptor / type-inference seams changed without a consumer sweep. Single most useful change: mandatory `P7` consumer sweep for every altered shared helper, plus a grep for the fixed issue id across `Tests/` (would have prevented BLK001).

### Recommended durable fixes (route to `/session-reflect` plan-rule bucket)

- GAP-03/GAP-02 → `work-plan/SKILL.md` scout brief: grep `ActiveIssue(<id>` for the issue being fixed and list each as an un-gate edit-point; for every changed shared helper, list callers and the provider rendering paths it reaches.
- GAP-05 → `plan-critic.md` attack vector: can the `TO-n` go red if the mapping under test is broken, or does it hand-feed the intermediate value / cover one path only?
- GAP-06 → `code-reviewer.md` rubric: `ActiveIssue` `ErrorMessage` uses the anchored `{1}but was` form.

## Round 3 — reviewed HEAD f8966ef88b6152e0f2dec3f16af0708ebb5a0aa5 (+ uncommitted round-3 fixes)

Round 2 (the external review's MAJ/MIN items, absorbed by `A-5`) was never attributed.

### Attribution

- **R3-01** — GAP-02 — `A-3` made `AsDateTime64` trust `QueryHelper.GetDbDataType(expr, MappingSchema)` with no `P4` row on whether that type is the operand's own; `U-1`(a) already recorded the schema fallback (`Undefined` → `DateTime64(7)`) a disagreeing `COALESCE` falls into. `A-3` superseded `D-1` without a `re-derives:` line. Fix site `ClickHouseExpressionExtensions.cs:25` — G-01 — preventable: yes
- **R3-02** — GAP-05 — `E-13`'s predicate ("a literal beside a computed coarse value") was written into `P6` after the code, with no discriminating input; TO-16 used only `MAX(coarse)`, never a coarse-typed value that reaches no column (a cast to `Date`). Secondary GAP-02 — G-01 — preventable: yes
- **R3-03** — GAP-03 — `E-8` widened `GetColumnDescriptor`'s `Element` arm to the first argument and `E-11` admitted LAG/LEAD; no `P7` row for that helper's consumers, so LAG's default argument was never listed. Round 1's caller-sweep rule (`work-plan/SKILL.md:118`) predated `A-5`, which named the gap in prose without a `P7` row — G-01 — preventable: yes
- **R3-04** — GAP-05 — `E-12` enumerates the stored path's members; `P8` covers CTE columns and set operations separately but not a set operation over one CTE inside another, the only input where a shared visited set reads as recursion. The scoping bug itself is implementation-level — G-01 — preventable: partly
- **R3-05** — GAP-10 — the *Test layout* rule was codified (406f742, 2026-10-12) after every test on the branch was committed (7a786fb87, 2026-10-11) — — — preventable: no
- **R3-06** — GAP-02 — `A-3`'s conditional rule assumes an operand reporting `DateTime64` is one on the server, reversing `P1`; `P7`'s operand-kinds producer sweep was not re-run, missing user-extension results (`Sql.ExtensionAttribute.cs:875`). The `A-5` critic delta named it as an unprobed lead; it reached review instead of a `P10` / `P7 deferred:` row (#6044). Secondary GAP-03 — G-01 — preventable: yes
- **R3-07** — GAP-03 — `E-12` changed the descriptor a comparison value receives, but `P7` never listed the in-list consumers (`ConvertInPredicate`, `ContainsBuilder.cs:163-170`); the `A-5` critic delta named both sites — G-01 — preventable: yes
- **R3-08** — GAP-03 — `E-11`/`E-21` put the value window functions in `Element`; no `P7` row for `E-12`'s parameter rule as a consumer, so `LAG(col) < @p`'s change against master was never listed. TO-14's parameter half was already gated (#5997) and could not go red (secondary GAP-05). Accepted in `P10`; listing it would have moved the decision earlier, not removed the behaviour — G-01 — preventable: partly
- **R3-09** — GAP-07 — `testing.md` → *A narrowed provider set is a claim* requires a measured failure per exclusion, but `work-plan` step 4 embeds only *Test layout*; f4e364c69's unprobed "MySQL DATETIME has no fractional seconds" hid #6049. Secondary GAP-02. Also an `A-5` critic lead — — — preventable: yes
- **R3-10** — GAP-02 — TO-16 gated Sybase as a server limit (`no-issue:`) without a probe, though `E-16` had already shown a Sybase date/datetime mismatch is fixable by a cast; a silent wrong answer, now #6050. No corpus rule limits `no-issue:` to refusals — — — preventable: yes

### Aggregate

Classes: GAP-03 ×3, GAP-02 ×3, GAP-05 ×2, GAP-07 ×1, GAP-10 ×1. One cause: 7 of 10 (R3-01/02/03/04/06/07/08) sit in mechanisms `A-3`/`A-5` introduced, and R3-09/10 in TO-16 gates `A-5` reconciled — none of those amendments re-derived `P4`/`P7`/`P8`, though `work-plan.md`'s amendment rules and `SKILL.md:118` were in force. `-Action validate` did not stop `A-5` (no "supersedes", no new public type; `A-3` predates the error cutoff). The `A-5` critic delta named R3-06/07/09 verbatim and they went to review as unprobed leads. Round 1's caller-sweep recommendation landed; the defect recurred because this plan was never re-walked against it.

### Recommended durable fixes (route to `/session-reflect` plan-rule bucket)

- GAP-03/GAP-02/GAP-05 ×7 → `work-plan.ps1 -Action validate` + `work-plan.md` → *P11 Amendments*: an `A-n` that adds `E-n` rows must carry a `re-derives:` line naming new `P4`/`P7`/`P8` rows — an error regardless of date or wording.
- GAP-03/GAP-02/GAP-07 ×3 → `work-plan.md` → *P12* + `plan-critic.md`: a critic lead marked "reasoned, unprobed" may not be carried to review; it becomes a `TO-n`, a `P7 deferred:` row with a reason, or a `P10` entry, and `validate -Done` fails on an open lead.
- GAP-07/GAP-02 ×2 → `work-plan/SKILL.md` step 4: embed `testing.md` → *A narrowed provider set is a claim* beside *Test layout*; extend `testing.md`'s `no-issue:` rule to refusals and probed server limits only — a gate whose observed failure is a wrong value gets a filed issue.

## Round 4 — reviewed HEAD 13d9127549a47e03c8afe7ebeb396e8d7f34ec0c

Findings: BLK001 (Access ODBC gate missing on TO-22), BLK002 (Informix `DateCastSetOperationTypesTheLiteralAsDate`), MAJ001 (SQLite IN list beside a computed DATE — probed, regression vs master), MAJ002 (`PercentileDisc` over DATE in a set operation loses the literal's time — probed on DuckDB, regression), MIN001, MIN002, SUG001, SUG002, NIT001.

### Attribution

- **BLK001** — GAP-08 — `TO-22` (`A-7` R-1, `CoarseAggregateCapturedListKeepsValueTime`, `DateTimeFunctionsTests.cs:2006`) is `[DataSources]` but was proven on ClickHouse ×3 + YDB only, with no post-`A-5` `G-01` row; `work-plan.ps1 -Action validate -Done` fails today ("G-01 names no test for TO-19/TO-20/TO-21/TO-22"). The plan already held the fact (`A-4`, TO-20's sibling #5998 gate); TO-22's `P8` row names no provider scope — G-01 — preventable: yes
- **BLK002** — GAP-08 — `DateCastSetOperationTypesTheLiteralAsDate` (`b62b7eba3`) proven on Firebird.5 only, though TO-16's own row lists Informix among the servers that type the union themselves and Informix was run locally for `E-19`/`E-26`/TO-18. Secondary GAP-03: no `P7` Informix row for the `.Date` (`DATETIME YEAR TO DAY`) vs cast-to-`Date` (`DATE`) mismatch `E-13` exposed — G-01 — preventable: yes
- **MAJ001** — GAP-03 — `A-6` (`E-31`) / `A-7` R-1 (`E-34`) extended `==`'s own-type rule to IN lists; on SQLite `==` is only right because of `E-14`'s `strftime` normalisation in `ConvertExprExprPredicate`. No `P7` row for the IN-list twin of a provider `ExprExpr` compensation (`E-14` SQLite, `E-16` Sybase), though `E-32` built that twin for ClickHouse. Secondary GAP-05: TO-20/TO-22 use only `MAX(DateTime)`, never a computed DATE operand — G-01 — preventable: yes
- **MAJ002** — GAP-02 — `E-8`'s second arm rests on "every production constructor declares the schema default (critic census, 14 sites)"; the census searched `new SqlExtendedFunction\(` and missed factory / aggregate-builder construction (`WindowFunctionsMemberTranslator.cs:929/1151/1243`), where `PERCENTILE_*` and string aggregates take their argument's type. `A-7` named those sites and dismissed them unprobed as "not date-comparison paths", though `E-13`'s consumer is not a comparison. Secondary GAP-03 — G-01 — preventable: yes
- **MIN001** — GAP-05 — `E-13`'s predicate admits every node `GetColumnDescriptorForTyping` resolves (CASE, conditional, single-arg function); TO-16 covers `MAX(coarse)` and a date cast only, and `A-7` skipped `E-13` as covered. Repeats R3-02 on the same predicate — G-01 — preventable: partly
- **MIN002** — GAP-05 — `IsStoredValue`'s CTE guard's recursion arm (`ExpressionBuildVisitor.cs:5174-5176`) has no `TO-n` exercising real recursion; TO-19 covers the non-recursive path-scoping case. Secondary GAP-02: asserted in a comment, not asked in `P4`. Repeats R3-04 on the same guard — G-01 — preventable: partly
- **SUG001** — GAP-05 — `A-7` R-3's invariant (LAG/LEAD default shares the first argument's server type) has no `TO-n`; its interaction with `ConstantDescriptor`'s identity test inside a comparison was never exercised (TO-19 covers a projection) — — — preventable: partly
- **SUG002** — GAP-03 — `E-12` lists nullability among stored-path members, but no `P7` row covered provider renderings of a nullability wrapper (Informix `NVL(field, NULL)`); `A-7` listed `IsStoredValue`'s callers, not the shapes it receives — — — preventable: partly
- **NIT001** — GAP-10 — the YDB exclusion on `DatePartMillisecondBeforeTheEpoch` has a measured reason recorded only in `fa8b62519`'s commit message; `A-6`'s exclusion audit did not cover the fifth entry — — — preventable: no

### Aggregate

GAP-05 ×3, GAP-08 ×2, GAP-03 ×2, GAP-02 ×1, GAP-10 ×1. Everything above MIN has two causes: both blockers are tests added in a review-fix round, proven on 1–4 providers, declared `[DataSources]` and pushed with no `G-01` row (`validate -Done` would have stopped both); both MAJ sit inside `A-7`'s re-walk, which enumerated callers of each changed mechanism but not the provider compensations the old `==` path relied on (MAJ001) nor factory construction sites (MAJ002, named and dismissed unprobed). The three GAP-05 items land on predicates already flagged in round 3 (`E-13` R3-02, CTE guard R3-04), patched for the reported input only; neither `A-6` nor `A-7` got a `P12` critic round.

### Recommended durable fixes (route to `/session-reflect` plan-rule bucket)

- GAP-08 ×2 → `definition-of-done.md` + `review-pr` / `/code-review` dispatch: a review round on a planned branch may not start while `work-plan.ps1 -Action validate -Done` fails; promote `P8`'s "row names no providers: scope" warning to an error for any `TO-n` an `A-n` adds — the row names the providers its proof ran on beside those its `[DataSources]` declares, and `G-01` records a run closing the gap.
- GAP-03/GAP-02 ×3 → `work-plan/SKILL.md` scout brief + `work-plan.md` → *P11 Amendments*: a re-walk has two sides — callers of the changed mechanism, and the sibling compensations the old path relied on. Extending a rule to a new predicate kind (`==` → `IN`) lists every provider override of the old predicate's convert hook and requires a row for its twin. A census claim ("every constructor does X") searches factory and builder construction, not `new T(`. An "out of scope, no row" line whose reason is a domain claim becomes a `P4` probe.
- GAP-05 ×3 → `plan-critic.md` attack vector enforced by `validate`: every predicate an `E-n` adds or narrows needs a `TO-n` or `P10` entry per admitted arm, including the arm a guard exists for; `validate` requires a `P12` delta round for every `A-n` carrying a `re-derives:` line.

### Continuity with rounds 1–3

- Round 1 GAP-03/GAP-02 (caller sweep in the scout brief): landed (`SKILL.md:118`) and applied via `A-7`, which found R-1 (TO-22). Recurs in MAJ001/SUG002 because the sweep is caller-shaped only.
- Round 1 GAP-05 (critic: can the `TO-n` go red / one path only): recurs in MIN001/MIN002/SUG001 — no critic ran on `A-6`/`A-7`.
- Round 1 GAP-06 (anchored `ActiveIssue` `ErrorMessage`): does not recur.
- Round 3 rec 1 (`re-derives:` line): `A-7` carries it; `A-6` introduced `E-31`/`E-32` without one (warning only, pre-cutoff). `A-7` missed MAJ001 (in its own `E-34` and `E-31`) and MAJ002 (sites named in its own out-of-scope bullet) for scope reasons, not a missing line.
- Round 3 rec 2 (unprobed lead may not reach review): recurs in MAJ002, but the lead was the author's own dismissal, not a critic lead — the rule should cover author out-of-scope reasons too.
- Round 3 rec 3 (*A narrowed provider set is a claim*): landed (`work-plan/SKILL.md:70`); BLK001/BLK002 are the opposite case — a known failure with no gate — which this round's first fix covers.

## Round 5 — reviewed HEAD dd69903045c0e4958e051c2c079920e497ec9970

Findings: MIN001 (ClickHouse widens a computed `DateOnly` operand to `DateTime64` beside a captured collection), MIN002 (SQLite IN-list `strftime` rewrite applies to the operand only), MIN003 (decimal "own type" is the schema default, not the value's scale), MIN004 (#6050 Sybase gate `ErrorMessage` matches only the no-source form), SUG001 (`ValueConverter: null` clause untested on its only consumer), OOS-1 (`GetInListValueType`'s date arm ignores a `ValueConverter`). All source-traced, none probed at attribution time — a row is void if its finding is refuted in the walk.

### Attribution

- **MIN001** — GAP-03 — `A-8` widened `E-32` (`f0b8b0418`, `ClickHouseSqlExpressionConvertVisitor.cs:111-113`) to any computed operand beside a captured-collection parameter, with no `P4`/`P7` row listing the mapping shapes that reach its `DataType is DateTime or Date or Date32` test (CLR `DateOnly` maps to `Date32`) or `E-34`'s `GetInListValueType` → `ClickHouseMappingSchema.ConvertDateOnly` as a consumer of the widened operand. `work-plan/SKILL.md:130` prescribes that mapping-shape sweep. The sibling twin `E-35` carries `IsDateTime(type.SystemType)`; before the widening, `A-6`'s arm fired only beside a `DateTime64` value, which excluded `DateOnly` implicitly — preventable: yes
- **MIN002** — GAP-02 — `E-35` (`A-8`, `5c3a371f9`) assumes every list value is timestamp text and rewrites `Expr1` alone; checkable against the original it copies (`E-14`'s `ConvertExprExprPredicate`, which normalises whichever side is a `Date`) and against the shapes `InList.Values` can take. Secondary GAP-05: TO-23's lists are constants or captured arrays, never a `Date`-typed expression — preventable: yes
- **MIN003** — GAP-02 — `E-34`'s decimal arm (`d2da94700`, narrowed by `76fc77952`) takes the value's "own type" as `MappingSchema.GetDbDataType(value.GetType())`, the schema default — the same assumption as R3-01, and `U-1`(a) already records that the schema default is not an expression's own type. `A-9` asked what a column `DataType` means beyond width, not the mirror question for the value. Secondary GAP-05: TO-28 has one arm (a value finer than a scale-2 column), no column finer than the default, no YDB parameter case — preventable: yes
- **MIN004** — GAP-07 — `testing.md:79`/`:87` (`8886a9b`, written from this PR's own CI failure) say to match `should be{0}<expected>{1}but was`, but step 4 of `work-plan/SKILL.md:70` embeds only *Test layout* and *A narrowed provider set is a claim*. The gate came from `A-9`'s CI triage and was proven by `G-01` from CI alone, which cannot fail this form (no test sources there). Third `ErrorMessage` miss on this branch — preventable: partly
- **SUG001** — GAP-05 — `E-31`'s `ValueConverter: null` clause has no `TO-n` on its one reachable consumer (captured-collection branch of `ConvertInPredicate`); TO-14's `CoarseConvertedAggregateComparedWithValue` exercises `==` only, TO-20/TO-22 use unconverted columns. Round 4's per-arm rule landed in `plan-critic.md` (`df4eff5`), but neither `A-8` nor `A-9` had a `P12` round — preventable: partly
- **OOS-1** — GAP-03 — `E-34` is the IN-list twin of `E-12`'s descriptor rule, which carries a converter condition; R-1's `P7` row lists call sites, not the conditions mirrored. `d2da94700` put the converter test beside the date arm, `76fc77952` bound it to the decimal arm only, while the `<remarks>` state it for every arm. No `P7 deferred:` row or `P10` entry covers it — preventable: partly

### Aggregate

GAP-02 ×2, GAP-03 ×2, GAP-05 ×1, GAP-07 ×1. Four of the five code findings share one cause: IN-list mechanisms written as twins of an `==` rule (`E-32`, `E-34`, `E-35`) kept the clauses their author remembered and dropped one — the value side (`E-35` vs `E-14`), the CLR guard (`E-32` vs `E-35`), the converter (`E-34` vs `E-12`), the value type's facets (MIN003). None got a critic round: `A-8`/`A-9` carry `re-derives:` lines naming `P6`/`P8`/`P9` but no `P4`/`P7` row, and `validate -Done` passes because its `P12` check fires only on "supersedes `D-n`" / "public type" and its `re-derives:` check accepts any text.

### Recommended durable fixes (route to `/session-reflect` plan-rule bucket)

- GAP-02/03/05 ×5 → `work-plan.ps1 -Action validate`: an `A-n` carrying `re-derives:` without a `P12` round naming it is an error, and its `re-derives:` line must cite a `P4`/`P7` row id or `P7: none — <searched>`.
- GAP-02/03 ×4 → `work-plan/SKILL.md` step 5 beside *A re-walk has two sides*, plus a `plan-critic.md` attack vector: a twin's `P6` row carries a clause-parity table against the original — sides rewritten, value-side type test, CLR-type guard, converter test, and where the value's "own type" comes from (schema default vs the value's facets).
- GAP-07 ×1 → `testing.md` + `work-plan/SKILL.md:70`: move the `ErrorMessage` paragraph under its own `## Gating an assertion failure` heading and add it to step 4's embed list; a gate proven only by CI is unproven for its message form — one local run, or a pattern matching both Shouldly forms.

### Continuity with rounds 1–4

- Round 1 GAP-03/GAP-02 (caller sweep): landed; MIN001 needed the neighbouring mapping-shape sweep (`SKILL.md:130`), which `A-8` never ran.
- Round 1 GAP-05 (can the `TO-n` go red / one path only): recurs in SUG001 and as the secondary class of MIN002/MIN003.
- Round 1 GAP-06 (anchored `ErrorMessage`): the rubric rule caught MIN004 at review; the miss recurs author-side as GAP-07 — third occurrence (round 1 MIN201, TO-16 post-`A-5`, MIN004).
- Round 3 rec 1 (`re-derives:` line): `A-8`/`A-9` comply in form, but the line names no `P4`/`P7` row — fix 1 closes that.
- Round 3 rec 2 (unprobed lead may not reach review): not exercised — no critic ran on `A-8`/`A-9`, so no leads existed.
- Round 3 rec 3 (*A narrowed provider set is a claim*): met; MIN004's gate rests on a measured failure (#6050), only its message form is wrong.
- Round 4 rec 1 (`validate -Done` before review): landed and held — no GAP-08 this round.
- Round 4 rec 2 (two-sided re-walk): landed in `df4eff5` (10-17 01:52), after `5c3a371f9` and `f0b8b0418`. It ensures a twin exists, not that its clauses match — hence MIN001/MIN002/OOS-1 as clause-parity defects (fix 2).
- Round 4 rec 3 (a `TO-n` per admitted arm; a critic round per `re-derives:` amendment): landed as prose in `plan-critic.md` only; validate's `P12` check unchanged, so SUG001 and the secondaries of MIN002/MIN003 are exactly what it targeted (fix 1).

## Round 6 — reviewed HEAD fc8018a91d5a2e7a277bf7481dc0193a00049974

Findings: MIN013 (set-operation literal beside `MAX(Decimal64(18,2))` takes the column's scale — probed, regression: master 1.004, PR 1.00 on ClickHouse ×3 + DuckDB), MIN015 (COALESCE / FIRST_VALUE / LAG beside a sub-second literal tested on ClickHouse only), SUG011 (`GetInListValueType` walks `IsStoredColumn` per IN value), SUG012 (negative-only assert in `TheCoercionIsEmittedOnlyWhereTheOperandNeedsIt`), NIT004 (TO-13's comment names only MIN/MAX), OOS-10 (Firebird `ConditionalOverDateSetOperationKeepsLiteralTime` now refuses where master truncated). All probed against master `e05b3cc4f` in the walk. MIN014 (COALESCE(Date, DateTime) as IN operand) refuted by measurement (PR fixes it; master red) — no row. Items 7, 9, 11, 12, 13 are pre-existing on master (#6019, #5997 comment, issues to file) — no row.

### Attribution

- **MIN013** — GAP-03 — `A-8` item 13 (`d2da94700`) discovered that `E-8`'s `Element` arm makes `MAX` report a decimal column's scale, and its own commit message states the cause generally ("since MIN / MAX report their argument's type, every other computed operand lent its column's type too") — but added the decimal arm to `E-34` only. `A-8`'s `re-derives:` names `P6` E-8/E-32/E-34 and `P8`, with no `P7` row for the other consumers of that decimal facet; `E-13`'s `P6` row (`SetOperationBuilder.cs:607` `GetValueTypeBeside`) is the set-operation twin of the same "literal keeps its own type beside a computed value" rule and stayed date-only. `A-9` narrowed and `A-10` (MIN003) re-examined `E-34`'s decimal arm without looking at its siblings. Round 4's two-sided re-walk rule did not fire: the extension was to a new type kind on an existing predicate, not a new predicate kind. Secondary: clause-parity miss across twins (`E-34` → `E-13`). Gate: — — preventable: yes
- **MIN015** — GAP-05 — `E-12` admits MIN/MAX, COALESCE, value window functions and CTE / set-operation columns, but TO-14's `[DataSources]` cells cover MAX, CTE-over-MAX and converted MAX only; the COALESCE and window arms lived in `ComputedSecondPrecisionValueComparedWithSubSecondLiteral` (`ed87cd5e9`, `IntervalTranslationTests.ClickHouse.cs:212`), which `E-6`'s row itself files as a "ClickHouse-specific obligation" although `E-12` is provider-agnostic. `59ec00fd1` (`A-5`) widened TO-14..TO-16 off ClickHouse and left these cells behind. Round 4's per-arm rule is in `plan-critic.md`, but no `P12` round has run since the `A-5` delta. Secondary GAP-07: `A-5`/`A-8`/`A-9`/`A-10` carry no `conventions:` line (validate warns), so *A narrowed provider set is a claim* was never re-embedded for the amendments. (The copied gates that proved unmatchable during the fix are a pre-existing cause — item 13, filter-over-subquery drops "Additional details" — GAP-10.) Gate: — — preventable: yes
- **SUG011** — GAP-01 — `A-7` R-1 moved the own-type rule into `BasicSqlBuilder`'s IN-list value path (every provider, every value) and no `P3` row names its SQL-build cost; `P3`'s only non-functional line is query-cache behaviour for `D-1`. `d2da94700` made the `IsStoredColumn` walk the outer gate when the rule covered every type; `76fc77952` (`A-9`) narrowed the inner tests to coarser-date/time-or-decimal and left the walk outside them, which made the type test a free pre-filter nobody applied (`BasicSqlBuilder.cs:2984`). `plan-critic.md` attack 6 (unstated requirement) covers the class, but no critic round ran on `A-7`..`A-9`. Gate: — — preventable: partly
- **SUG012** — GAP-05 — TO-12's "absent over a default-mapped column" half (`A-3`) is stated as an absence with no discriminating input; `ShouldNotContain("toDateTime64")` alone also passes when the projection is not translated at all (`IntervalTranslationTests.ClickHouse.cs:35`), while its sibling halves assert presence. On the GAP-10 boundary (assertion form is below `P8`'s altitude), but TO-1/TO-5 show the plan records discrimination per row. Gate: — — preventable: partly
- **NIT004** — GAP-10 — `E-28`'s comment (`SelectQueryOptimizationTests.cs:62`) was written under `A-3`, when the `Element` arm held MIN/MAX only; `A-5`'s `E-11`/`E-21` gave the value window functions the same domain and made it incomplete. No plan block carries comment wording. Gate: — — preventable: no
- **OOS-10** — GAP-01 — TO-25's row (`A-8`, `1c6858d3f`) records "Firebird now refuses where master truncated to 00:00" as a gate reason only. Unlike `P10`'s two ad-hoc "Release-note material" entries, it got no behaviour-change entry, so it reached review as a missing PR-body note. No corpus rule requires a `P10` entry when a gate or pin records a change in kind against master (answered → refuses, refused → wrong answer) — the requirement should exist in `work-plan.md` → *P10*. Gate: — — preventable: yes

### Aggregate

GAP-05 ×2, GAP-01 ×2, GAP-03 ×1, GAP-10 ×1. The one regression (MIN013) is round 5's twin pattern again, in the reverse direction: a clause added later to one twin (`E-34`'s decimal arm) was not propagated to its sibling (`E-13`), though the commit that added it named a cause common to every consumer. MIN013, MIN015 and SUG011 trace to one missing step: no `P12` critic round has run on `A-7`..`A-10`, and the plan was never re-walked against the per-arm rule (round 4) or the clause-parity rule (round 5) after they landed — validate's 2026-10-19 cutoff keeps `A-8`..`A-10` at warning level. A single delta critic round on `A-8`..`A-10` with existing attack vectors would have hit every code finding above GAP-10.

### Recommended durable fixes (route to `/session-reflect` plan-rule bucket)

- GAP-03/05 ×3 (MIN013, MIN015, SUG012) → `work-plan.ps1 -Action validate` + `review-pr` dispatch: the "lacks a P4/P7 row / P12 critic round" check is dated per amendment, so the amendments that motivated it (`A-8`..`A-10`) stay warnings forever. On a plan whose status is not done, raise it as an error for every `A-n` dated after the last `P12` delta, whatever the date, and do not start a review round on a planned branch with that error open.
- GAP-03 ×1 (MIN013) → `work-plan/SKILL.md` step 5 clause-parity paragraph + `plan-critic.md` attack 4: twins form a family — an amendment that adds a clause to one member lists every sibling (here `E-12`, `E-13`, `E-34`) with that clause's disposition in its `re-derives:` line; a commit or amendment that states a general cause ("every other computed operand…") owes a consumer sweep of that cause, not one fix.
- GAP-01 ×1 (OOS-10) → `work-plan.md` → *P10*: a `TO-n` gate or pin whose recorded master behaviour differs in kind (answered → refuses, refused → answers wrong) gets a `P10` behaviour-change entry flagged for the PR body's *Behaviour notes*.

### Continuity with rounds 1–5

- Round 1 GAP-03/GAP-02 (caller sweep): landed; `A-7`'s sweep was framed by date typing — MIN013 is `E-8`'s decimal facet, found by `A-8` and fixed at one consumer.
- Round 1 GAP-05 (can the `TO-n` go red / one path only): recurs in MIN015 and SUG012.
- Round 1 GAP-06 / round 5 rec 3 (`ErrorMessage` forms): no recurrence; MIN015's copied gates failed on item 13's pre-existing message loss, not message form.
- Round 3 rec 1 (`re-derives:` line): `A-8`..`A-10` comply in form only — validate flags each as lacking a `P4`/`P7` row.
- Round 3 rec 2 (unprobed lead may not reach review): recurs as MIN014 — `A-7` R-5 recorded "unprobed and recorded, not claimed", reached review as a finding, refuted in the walk at the cost of a probe batch.
- Round 3 rec 3 (*A narrowed provider set is a claim*): met for the moved MIN015 tests, whose exclusions rest on measured messages (`pr5959-r6-p13-master.log`).
- Round 4 rec 1 (`validate -Done` before review): held, no GAP-08 — but passes because the round-5 check is still a warning before 2026-10-19 (fix 1).
- Round 4 rec 2 (two-sided re-walk): in force for `A-8` (`df4eff5` predates `d2da94700`), worded for a rule extended to a new predicate kind; `A-8` extended `E-34` to a new type kind, so it did not fire.
- Round 4 rec 3 (a `TO-n` per admitted arm): still prose in `plan-critic.md` with no critic round to apply it — MIN015 is exactly its target.
- Round 5 rec 1 (validate: `P4`/`P7` citation + `P12` round): landed in `a68358f` as an error from 2026-10-19; `A-8`/`A-9`/`A-10` are warnings, so round 6 started with all three open.
- Round 5 rec 2 (clause-parity table): landed in `a68358f` (10-18 00:19), after `fc8018a91` (00:01). No `P6` twin row carries a table yet; its text names "a comparison → a set operation" as a twin kind but covers creation, not later clause additions (fix 2).

### Addendum — the `A-8`..`A-11` delta critique (run after this attribution)

The recommended delta critic round was run (`P12`, verdict weak). Measuring its objections found two more regressions and confirms the aggregate above:

- **`==` / `<` beside `MAX(decimal)`** (critic objection 1) — GAP-03: a fourth twin, `ExpressionBuildVisitor.GetDataType`'s literal retyping, had only the date clause. Master's accidental widening hid it. The critic traced it as "as master"; measuring showed a regression. A source trace of a twin family does not settle a master comparison.
- **Converted-decimal IN list** (critic objection 4, P17) — GAP-03: the `ValueConverter` clause on `E-13`/`E-34`'s decimal arms let `E-8`'s narrowed type through. The round-5 OOS-1 disposition kept the clause without measuring a converted column.

Both are fix 2's case: a clause added to one twin (`E-34`'s decimal arm) and not swept through the family. The sweep is now `P7` R7-2.

## Round 7 — reviewed HEAD 693048d50184b946a04a73cd4cb056b9787407b7

Findings: BLK003 (TO-32 COALESCE cell missing the #5998 Access ODBC gate), BLK004 (TO-32 FIRST_VALUE cell uses a ROWS frame Firebird 3 refuses), BLK005 (TO-33 missing the #6062 SqlCe exclusion), MAJ010 (E-12/E-13/E-34 decimal arms substitute the schema-default decimal instead of widening — measured regression on ClickHouse, YDB, and in set operations on DB2 / SqlCe / DuckDB), SUG013 (E-12 comment "converter or not"), OOS-1 (E-12 lacks the `GetColumnDescriptorForTyping != null` clause), OOS-2 (Sybase IN twin one-sided). DB2/Informix/DuckDB CI legs infra-dead; round-6 tests green locally there — no row. All seven fixed on the branch (`A-12`); none posted.

### Attribution

- **BLK003** — GAP-08 — `P9` `G-01 (post-A-11)` recorded "pass, with the full provider matrix deferred to CI" after running TO-32 on YDB and SqlServer.2022.MS only, though TO-32 is `[DataSources]`, Access.Ace.Odbc runs locally (`A-5` held TO-16's gate on it), and the plan already held #5998 as measured sub-second loss on Access ODBC (`A-4`, TO-14, TO-22). `work-plan.md:204` forbids writing a deferred run as `pass`. The plan's `P8` row isn't missing anything (not GAP-03). Exact repeat of round 4's BLK001 (same gate, same provider, same test kind). Gate: G-01 — preventable: yes
- **BLK004** — GAP-02 — TO-32's `P8` row takes its exclusion set ("Providers without FIRST_VALUE (SQL Server 2008−) or LAG's default") as complete. It was derived from function-level support (`FirstValueBasic`, the YDB-only P13 probe). Nobody checked the other capability-gated clause in the query `6af8c7d50` moved verbatim out of the ClickHouse-only cell: `.RowsBetween.Unbounded.And.Unbounded`. `IsFrameRowsSupported` (`WindowFunctionsMemberTranslator.cs:832`) refuses it on Firebird 3, and master already pins that (`WindowFunctionsTests.LastValue.cs:18` ThrowsForProvider Firebird3 Error_WindowFunction_FrameRows). Secondary: GAP-08 (same deferred `G-01` as BLK003). Gate: G-01 — preventable: yes
- **BLK005** — GAP-08 — the post-critic-fixes `G-01` ran TO-33 on ClickHouse ×3, SQLite ×2, DuckDB, YDB, Sybase, Informix.DB2 and Firebird 5, but not SqlCe, again "deferred to CI". SqlCe ran locally in `A-8`'s regression run, which is where #6062 was found. TO-28's `P8` row in the same plan records "SqlCe excluded (#6062: compares a decimal literal at the other side's scale)", TO-33's exact shape (a literal vs `MAX(Decimal(18,2))`). TO-33's row has no `providers:` scope, and validate only warns. Gate: G-01 — preventable: yes
- **MAJ010** — GAP-02 — `A-11` (critic objection 1, `367c9698a`) and `P6` E-12 describe the new arm as "widens a decimal literal … to the schema's decimal type". That assumes the schema default dominates the operand's precision, scale and integer digits. The plan already held the counterexample: `A-10`/MIN003 measured ClickHouse truncating to `toDecimal128(…, 10)` beside a finer column and YDB overflowing `Decimal(22, 9)`. `A-10` then ruled that arm "pre-existing" on a `MAX`-only measurement, and `A-11` copied the same substitution into `E-12` and `E-13`. Dropping the converter clause widened its reach further. This is round 5's MIN003 assumption ("own type = schema default"; `U-1`(a)) in all three twins. Secondary GAP-05: TO-31/TO-33 have only Decimal(18,2) cells, coarser than the default. No cell is finer than the default, has more integer digits than it, or uses a non-`MAX` operand. That is exactly the "value at the provider's headroom" `separates:` row of `work-plan.md:182` (`217b0aa`, 10-19 19:34, ~3 h before `367c9698a`), which no `P12` round applied to this fold-in. Gate: — — preventable: yes
- **SUG013** — GAP-02 — the comment repeats a plan claim: `P6` E-12 "…to the schema's decimal type, converter or not". The plan held evidence against it: TO-33's row records that a literal vs `MAX` of the converted column "ClickHouse narrows … on master too", which is impossible if that path reached the widening. A converted constant is a forced parameter (`IsForceParameter`). A prose finding, but the false sentence came from a plan block, not from the comment's author. Gate: — — preventable: partly
- **OOS-1** — GAP-03 — `P7` R7-2 is the clause-parity table for the "literal keeps its own type" family. Its per-twin columns are date arm, decimal arm and converter clause. It has no column for the descriptor-reach conjunct `GetColumnDescriptorForTyping(other) != null`, which `E-13` gained in round 3 (TO-16 `DateCastSetOperationTypesTheLiteralAsDate`) and `E-34` carries. The columns came from round 5's fixed list (sides, value-side type test, CLR guard, converter, own-type source), which omits descriptor reach, not from each twin's actual conjuncts. Gate: — — preventable: partly
- **OOS-2** — GAP-03 — `P7` R7-3 checks only that a twin exists ("The `==` compensations with no IN twin: none left after `A-11`"). `P6` E-16 records a one-sided design without remark ("casts a DATE operand to `DateTime` when a list value is a timestamp…"). "Sides rewritten" is the first column of the clause-parity rule in `work-plan/SKILL.md` step 5 (`a68358f`, 10-18), in force when `d045d82d3` landed (10-19 22:23). Same class as round 5's MIN002 (`E-35` rewrote the operand only). The fix came from critic objection 2, and no critic round ran after it. Gate: — — preventable: yes

### Aggregate

GAP-02 ×3, GAP-08 ×2, GAP-03 ×2. There are two causes.

1. **All three blockers** are `[DataSources]` tests proven on a provider subset. `G-01` was recorded `pass` with "deferred to CI", and that CI run was the review's run. Two of the three failures were already measured on sibling tests in the same plan (#5998, #6062), and the third is pinned on master (`LastValue.cs:18`).
2. **Every code finding** (MAJ010, SUG013, OOS-1, OOS-2) sits in a critic fold-in (`367c9698a`, `d045d82d3`, 22:21–22:23) committed ~18 h after the `A-8`..`A-11` critic verdict (`e6e8426e2`, 04:18). No `P12` round attacked them, though the headroom `separates:` rule and the clause-parity rule were both in force.

The single most useful change is to key the `P12` requirement on commit time, not amendment id: a verdict must postdate the last commit touching any `E-n`, fold-ins included. That would have put MAJ010, SUG013, OOS-1, OOS-2, and probably BLK005, in front of a critic before review.

### Recommended durable fixes (route to `/session-reflect` plan-rule bucket)

- GAP-02/03 ×4 (MAJ010, SUG013, OOS-1, OOS-2) → `work-plan.ps1 -Action validate` + `work-plan.md` → *P12* + review-pr dispatch: any commit touching an `E-n` that is newer than the last `P12` verdict is an error, critic fold-ins included. A fold-in gets no new `A-n`, so round 6's per-`A-n` dating cannot see it. Don't start a review round with the error open. `plan-critic.md:71` already says to apply `separates:` "hardest to cells a critic round folded in"; this makes it enforceable.
- GAP-08/02 ×3 (BLK003, BLK004, BLK005) → `work-plan.ps1 -Action validate` + `testing.md` → *A narrowed provider set is a claim*:
  - A `G-01` row recorded as `pass` that contains "deferred" is an error under `-Done`; it must read `blocked — CI <run id>` until the run is read.
  - Promote round 4's unlanded rec 1: `P8`'s "no `providers:` scope" (`work-plan.ps1:346-347`) becomes an error for every `TO-n` an `A-n` adds.
  - `testing.md`: a measured gate on a sibling test of the same mechanism is a known failure, so a new `[DataSources]` test carries it. A moved or widened query is checked against master's tests for each capability-gated clause it contains (frames, defaults), not only for the function it is named after.
- GAP-03 ×2 (OOS-1, OOS-2) → `work-plan/SKILL.md` step 5 clause-parity paragraph + `plan-critic.md` attack 4: build the parity table's columns from each twin's actual predicate conjuncts, not a fixed list. A twin row records which sides it rewrites, next to the original's sides; an R7-3-style existence check is not parity.

### Continuity with rounds 1–6

- **Round 1 GAP-05 / round 4 rec 3** (a `TO-n` per admitted arm): recurs as MAJ010's secondary. The decimal arms have one cell each, all coarser than the schema default.
- **Round 3 rec 3** (*A narrowed provider set is a claim*): embedded (`A-11` `conventions:` line) and followed in form, since the tests were widened bare. BLK003–BLK005 are the opposite case round 4 named: a known failure with no gate.
- **Round 4 rec 1** (`P8` `providers:` scope as an error; `G-01` records a run closing the gap): not landed. `work-plan.ps1:347` still only warns, and a `G-01` "pass … deferred to CI" goes through. BLK003 repeats round 4's BLK001 exactly.
- **Round 4 rec 2** (two-sided re-walk): applied as R7-3, but checks twin existence, not sides → OOS-2.
- **Round 5 MIN003** (GAP-02, schema default taken as the value's own type): grows into MAJ010. `A-10` ruled it pre-existing on a `MAX`-only measurement, and `A-11` carried the arm into `E-12`/`E-13`. The `A-12` fix closes #6064 (filed by round 5 as the pre-existing half) as well.
- **Round 5 rec 2 / round 6 rec 2** (clause-parity table; family sweep): landed and worked for the listed clauses. Decimal and converter clauses propagated across `E-12`/`E-13`/`E-34` with no MIN013-style miss. The fixed column list produced OOS-1.
- **Round 6 rec 1** (`P12` round on `A-8`..`A-10`): held, since the delta critic ran. Its own fold-ins went unattacked (fix 1).
- **Round 6 rec 3** (`P10` entry when behaviour changes in kind): landed, and applied in `A-12` (YDB set-operation and Informix DDL entries).
- **Round 6 addendum** ("a source trace of a twin family does not settle a master comparison"): recurs. The objection-1 fix was measured on one decimal shape and generalised.

### Addendum — the `A-12` critique (four rounds)

The fix itself needed four critic rounds (refuted, refuted, weak, weak) and every round found something a measurement then confirmed: the cap read from `SqlDataType.GetMaxPrecision` was 29, not 38; DB2's and Informix's limits (31, 32) sat below the first chosen cap; the ClickHouse family overflow was real; Firebird 3 and 5 overflow the headroom shape on master too; YQL compares mixed decimal types numerically. Rounds 3 and 4 were cheap only because the containers were already up — the same "deferred to CI" pattern as BLK003–005 would have shipped two more defects.
