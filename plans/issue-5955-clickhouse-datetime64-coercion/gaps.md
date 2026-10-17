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
