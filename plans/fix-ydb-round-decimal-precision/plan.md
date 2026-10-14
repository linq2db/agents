# Work plan: fix-ydb-round-decimal-precision — Exact Decimal rounding in YDB's ROUND emulation

**Tier:** L  ·  **Status:** approved  ·  **Approved-at:** 2026-10-14 (critic round 3: weak, objections folded in)  ·  **Branch:** fix/ydb-round-decimal-precision
**Schema:** `.claude/docs/work-plan.md`  ·  **Gates:** `.claude/docs/definition-of-done.md`

Context: written mid-review of PR #5943 at head `153a68af7`, over a branch that already carries 13 commits. It covers the review finding MIN006 (Double precision) and NIT003 (stale strategy comment). The surviving PR surface is mapped in P7.

## P1 Problem

`YdbMemberTranslator.RoundScaledAs` rounds a Decimal by scaling it by 10^p in a widened Decimal type, then `CAST(... AS Double)`, `Math::NearbyInt` / `Math::Round`, and back through `Text` to Decimal. A Double carries ~15-17 significant digits, so the rounding is silently wrong whenever the scaled value has more. Measured on local YDB (net10.0), `Decimal(22,9)` column, both midpoint modes, at PR head `153a68af7` vs master's `YdbMemberTranslator.cs`:

| value, precision | expected | PR head | master |
|---|---|---|---|
| `900719925474.09931`, 4 | `900719925474.0993` | `900719925474.0994` (silent) | `PreconditionFailed` (overflow) |
| `123456789012.34567`, 5 | `123456789012.34567` | `123456789012.34568` (silent) | `PreconditionFailed` (overflow) |
| `12345678901.234999999`, 2 | `12345678901.23` | `12345678901.24` (silent) | `12345678901.24` (silent) |
| `1234.56789`, 4 (control) | `1234.5679` | correct | correct |

Rows 1-2 are a regression introduced by the PR's widening (loud failure becomes a wrong value); row 3 is pre-existing on master (significant digits, not magnitude). The same Double step serves the no-precision path (`Math.Round(d)`), so `1234567890123.499999999` is expected to round to `...124` there too (unprobed, TO-5 settles it).

## P2 Success criteria

- SC-1 Constant-precision rounding of a Decimal whose scaled value exceeds 2^53 returns the exact result in both modes (rows 1-2 above). → TO-1
- SC-2 Constant-precision rounding of a Decimal with more than ~15 significant digits returns the exact result in both modes (row 3 above). → TO-2
- SC-3 Midpoint semantics are exact at high significance: to-even and away-from-zero disagree on exact ties and each returns its own answer, both signs. → TO-3
- SC-4 The runtime-precision path (`Sql.Round(d, r.P)` / `Sql.RoundToEven(d, r.P)`) is exact on the same inputs, positive and negative precision. → TO-4
- SC-5 The no-precision path (`Math.Round(d)`, `Sql.Round(d)`) is exact for a Decimal with more than ~15 significant digits. → TO-5
- SC-6 A Decimal column in the scaffolded shape `DbType = "Decimal(6, 2)", Precision = 6, Scale = 2` rounds exactly: the computed CASTs render their own precision/scale, not the `DbType` string (narrowed by A-1; `DbType`-only columns are out of scope, P10). → TO-6
- SC-7 No regression: every existing YDB rounding test stays green; rounding of `double` values on YDB emits byte-identical SQL. → TO-7, TO-8
- SC-8 The strategy comment above `TranslateRoundToEven` describes the new algorithm (D-1, D-2). → TO-9

## P3 Constraints & anti-goals (M/L)

- No change to any provider other than YDB; no change to `MathMemberTranslatorBase.cs`, `PostgreSQLSqlExpressionConvertVisitor.cs` or any shared `Translation/` / `SqlQuery/` type.
- No public API change.
- Rounding of `double` / `float` values on YDB keeps the existing Double path and its SQL.
- The PR's widening rules (`ScaledDecimalType` arithmetic, the runtime sign branch, the `Ensure` guard, the precision-at-or-above-scale no-op) are not redesigned; only the integer-rounding step and DbType handling change.
- YDB baselines of decimal Round tests are expected to move (the Double/Text chain disappears); no other provider's baselines may move.
- Anti-goal: not fixing `Math.Floor` / `Math.Ceiling` / `Math.Truncate` on Decimal, which round-trip through Double in `YdbSqlExpressionConvertVisitor.cs:257-270` (P7, deferred).

## P4 Unknowns (M/L)

- U-1 YQL scale-narrowing `CAST(Decimal AS Decimal(P,s'))` rounds half-to-even exactly, both signs, at 22-digit width — resolved-by probe: `CAST(Decimal('1.25',5,2) AS Decimal(5,1))`=1.2, `'1.35'`=1.4, `'-1.25'`=-1.2, `'1.251'`(5,3)=1.3, `'1.249'`=1.2, `CAST(Decimal('1234567890123.4999999',22,9) AS Decimal(22,0))`=1234567890123, `'...123.5000000'`=1234567890124.
- U-2 The optimizer folds `CAST(CAST(s AS D(P,0)) AS D(P,S))` back to `s` when both casts are non-mandatory — resolved-by scout + read: `SqlExpressionOptimizerVisitor.cs:1352-1364` (outer target `EqualsDbOnly` the inner operand's type → returns `castOther.Expression`); a mandatory cast skips the block; `SqlExpressionFactoryExtensions.cs:122` `Cast(..., bool isMandatory = false)`.
- U-3 A `DbType` on the value's `DbDataType` is rendered verbatim by `BasicSqlBuilder.BuildDataType` (`BasicSqlBuilder.cs:4494-4497`) and `WithPrecisionScale` keeps it (`DbDataType.cs:95`), so a narrowing/widening cast to a DbType-carrying type renders the source type — resolved-by scout (code path read); the runtime effect is unprobed and TO-6 must observe it red before the fix.
- U-4 With `YdbOptions.UseParametrizedDecimal = false` every Decimal cast renders bare `Decimal` (`YdbSqlBuilder.cs:193-204`) — resolved-by probe: `CAST(Decimal('1.55',5,2) AS Decimal)` and `CAST(CAST('1.5' AS Text) AS Decimal)` both return YQL `GenericError`, so Decimal rounding already fails under that option on master and at PR head (the Text→Decimal cast); no regression possible.
- U-5 A carry still fits the integer type: `CAST(Decimal('99999.5',6,1) AS Decimal(6,0))`=100000 — resolved-by probe. Integer type `Decimal(Pw,0)` has `Sw` spare integer digits; `Sw = 0` is short-circuited (D-1).
- U-6 Same-type Decimal subtraction and equality against a Decimal literal work in YQL — resolved-by probe: `Decimal('2.5',5,1) - CAST(Decimal('2',5,0) AS Decimal(5,1)) = Decimal('0.5',5,1)` = true. Literals render `Decimal('0.5', P, S)` / `Decimal('-0.5', P, S)` (`YdbMappingSchema.cs:629-637`, scout).
- U-7 Two Decimal operands of identical type get no Double cast in `YdbSqlExpressionConvertVisitor.ConvertSqlBinaryExpression` (`AlignFloatingDecimal` only fires for floating+Decimal, :234-253) — resolved-by scout.
- U-8 Nullable value: `CompareNulls.LikeSql` predicates add no null expansion (`PredicateExtensions.cs:39-57`, `SqlExpressionConvertVisitor.cs:428`); a NULL value makes each tie condition UNKNOWN, so the expression falls to the to-even branch, which is NULL — resolved-by scout; covered by an existing NULL-precision assertion in Round23 and a NULL value row in TO-3.
- U-9 Unscaling `rounded / 10^p` in the widened type is exact — resolved-by existing evidence: the same `Div(scaleType, ..., Pow10(...))` already runs under Round3/9/10/12/17-23, green on CI build 24135 at `153a68af7`; this plan does not change it.
- U-10 Nothing other than the two Round overrides consumes `RoundScaled` / `RoundScaledAs` / the `roundToInt` lambdas — resolved-by scout: pattern `RoundScaled|RoundScaledAs|ScaledDecimalType|Pow10|roundToInt` across `Source/`, all hits in `YdbMemberTranslator.cs` :726, :730, :792-802, :820-828, :773-800.
- U-12 `IsMandatory` survives the LinqService boundary despite the comments at `YdbMemberTranslator.cs:554-557` / `:641-643` saying it is lost — resolved-by critic code read: `LinqServiceSerializer.cs:1781` writes and `:3080` restores the flag, `SqlCastExpression.cs:67` compares it, KB `SQL-AST/INDEX.md:60` records the fix; TO-1/TO-2 run on `YDB.LinqService` to observe it.
- U-13 A `DbType`-only decimal column has null Precision/Scale on its `DbDataType`: `ColumnDescriptor.cs:66-67,509` take P/S only from the attribute or the schema default, `MappingSchema.cs:1453` registers decimal with no P/S, nothing parses the `DbType` string — resolved-by critic code read; consequence: `ScaledDecimalType` widens from `(22,9)` defaults and the non-mandatory widening cast can narrow the scale and round (U-1), so D-4 must read P/S from the string.
- U-14 Writing through a `DbType`-only decimal mapping sizes the value `(22,9)` regardless of the string — literals `YdbMappingSchema.cs:629-637` via `MultipleRowsHelper.cs:103`, parameters `YdbDataProvider.cs:446-455` — so such a fixture cannot be populated through its own entity — resolved-by critic code read (round 2); TO-6b..e populate through a sibling entity declaring `Precision`/`Scale` and query through the `DbType`-only entity on the same table (`db.GetTable<T>().TableName(t.TableName)`); the write-side sizing is a separate pre-existing defect (P10, follow-up issue).
- U-15 `YdbSchemaProvider.ParseType` assumes the closing `)` is the last character and tolerates whitespace around the numbers — resolved-by read (`YdbSchemaProvider.cs:125-143`); TO-6b uses the spaced form `Decimal(30, 15)`.
- U-16 YQL refuses a CAST between `Decimal(P,P)` and `Decimal(P,0)` in either direction at type-annotation time — resolved-by probe: `CAST(Decimal('0.1',35,35) AS Decimal(35,0))`, `(10,10)→(10,0)`, `(5,5)→(5,0)`, `(4,4)→(4,0)`, `(35,35)→(1,0)` all `Cannot cast type`, as is `CAST(Decimal('1',4,0) AS Decimal(4,4))`; `(35,34)…(35,30)→(35,0)`, `(5,4)→(5,0)` and `(35,35)→(35,1|4|5|10)` work. Found by `Round22` going red (A-2).
- U-11 `SubQueryTests.Issue1601` is `[ActiveIssue(5591)]` on YDB and calls `Math.Round(x + x)` on a decimal — the no-precision path changes, so the test may start passing and fail as "passed but marked" — resolved-by obligation: TO-7 runs it.

## P5 Decisions (M/L; rejected alternatives mandatory at L)

### D-1 — Round a Decimal exactly with a scale-narrowing CAST

- **chosen:** in `RoundScaledAs`, for a Decimal value, replace the Double round-trip with `even = CAST(CAST(scaled AS Decimal(Pw,0)) AS scaleType)`, both casts mandatory. When `(scaleType.Scale ?? DEFAULT_DECIMAL_SCALE) == 0` the scaled value is already integral and is returned as is (the no-precision path passes the value's own type, whose Scale can be null).
- **rejected:** (a) cap the widened integer digits at 15 so rows 1-2 fail loudly again — leaves row 3 (master's class) wrong and turns now-correct values back into failures; (b) truncate with Decimal `%` and compare the residue — `%` on Decimal is a commented-out rewrite area in `YdbSqlExpressionConvertVisitor` (KB `PROV-YDB` INDEX) and needs sign handling the CAST gets for free; (c) `CAST(Decimal AS Int64)` — also half-to-even (probe: 2.5→2, 3.5→4) but caps at 18 digits and `YdbSqlExpressionConvertVisitor.cs:369-380` rewrites Decimal→integer through Double, reintroducing the defect.
- **why this:** one YQL primitive, measured exact (U-1), no Double anywhere, keeps the PR's widening intact.
- **failure mode of the choice:** correctness rests on YQL's narrowing-CAST rounding rule; a YDB build that truncated instead would make to-even silently wrong. TO-3's ties discriminate it (truncation turns `...123.5` into `...123`, which is even's answer only for even integers — the odd-integer tie rows go red).

### D-2 — Away-from-zero by tie detection, adjusting in the integer type

- **chosen:** `evenI = CAST(scaled AS Decimal(Pw,0))`, `even = CAST(evenI AS scaleType)`, `diff = even - scaled`. If `diff = -0.5 AND scaled > 0` the result is `CAST(evenI + 1 AS scaleType)`; if `diff = 0.5 AND scaled < 0` it is `CAST(evenI - 1 AS scaleType)`; otherwise `even`. The ±1 is done in `Decimal(Pw,0)`, which has spare integer digits, so every overflow still surfaces through a CAST exactly as today.
- **rejected:** `scaled ± 0.5` in `scaleType` then round — needs a truncation primitive YQL lacks (CAST rounds), and YQL Decimal `+` overflow behaviour at the type maximum is unprobed.
- **why this:** away-from-zero differs from to-even only on an exact tie that to-even resolved toward zero; detecting that in exact Decimal arithmetic needs only U-6's operations.
- **failure mode of the choice:** a longer SQL expression (nested condition → `CASE`). The separating input is an exact tie on an even integer part (`...122.5` → even `...122`, away `...123`); TO-3 carries it, and the mutation "drop the tie branches" turns its away rows red.

### D-3 — Both rounding casts are mandatory

- **chosen:** `factory.Cast(..., isMandatory: true)` for `scaled → Decimal(Pw,0)` and `Decimal(Pw,0) → scaleType`.
- **rejected:** default non-mandatory casts — the optimizer folds the pair back to `scaled` (U-2) and the rounding vanishes silently.
- **why this:** `QueryHelper.cs:1953-1961` documents mandatory as the way to keep a semantically required cast.
- **failure mode of the choice:** a mandatory cast to an identical type would survive as a redundant CAST; excluded by the `scale == 0` short-circuit, which is the only case where `Decimal(Pw,0)` equals `scaleType`. Mutation "isMandatory: false" must turn TO-1/TO-2 red.

### D-4 — Strip `DbType` from the computed intermediates (narrowed by A-1)

- **chosen:** the integer type and `ScaledDecimalType`'s result are built without `DbType` (a new `DbDataType(SystemType, DataType, null, Length, P, S)`), so the CASTs render the computed `Decimal(P,S)`. The final narrowing cast back to the value's own type keeps its `DbType`. Precision/Scale are taken from the mapping only; a `DbType` string is never parsed (A-1).
- **rejected:** (a) keep `DbType` — the integer CAST and the widening CAST render the source type, so a scaffolded column (`DbType` + `Precision` + `Scale`) is not rounded at all; (b) parse P/S from a `Decimal(p,s)` `DbType` (rounds 1-3; implemented and measured green, reverted) — type inference from `DbType` is a known gap the user defers to the v7 mapping redesign; (c) decline when `DbType` is set and P/S are incomplete — rejected by the user for the same reason.
- **why this:** the computed types are internal intermediates; only the value's own type is user-facing, and the scaffolder always emits `Precision`/`Scale` beside `DbType`.
- **failure mode of the choice:** a `DbType`-only column with a declared scale above 9 is widened from the `(22,9)` defaults and silently rounded by the widening cast (P10, accepted). The separating input for the kept behaviour is TO-6a (red at head with `Decimal(6,2) != Decimal(7,2)`).

### D-5 — `double` values keep the Double path

- **chosen:** the change is gated on `isDecimal`; the `roundToInt` lambdas remain for doubles.
- **rejected:** one path for both — a double has no exact Decimal form to round, and changing its SQL is outside P3.
- **why this:** keeps SC-7's symmetry guard meaningful.
- **failure mode of the choice:** two code paths in one method; TO-8 guards the unchanged one.

## P6 Edit-points

- E-1 `Source/LinqToDB/Internal/DataProvider/Ydb/Translation/YdbMemberTranslator.cs:RoundScaledAs` — Decimal values round via D-1/D-2/D-3; doubles unchanged (D-5).
- E-2 `Source/LinqToDB/Internal/DataProvider/Ydb/Translation/YdbMemberTranslator.cs:RoundScaled` — thread the midpoint mode (`awayFromZero` flag) from `TranslateRoundToEven` / `TranslateRoundAwayFromZero` to `RoundScaledAs`.
- E-3 `Source/LinqToDB/Internal/DataProvider/Ydb/Translation/YdbMemberTranslator.cs:ScaledDecimalType` — result built without `DbType` (D-4).
- E-4 `Source/LinqToDB/Internal/DataProvider/Ydb/Translation/YdbMemberTranslator.cs:716` — strategy comment rewritten; restates D-1, D-2, D-5.
- E-5 `Tests/Linq/Linq/MathFunctionTests.cs:Round24` — new YDB-only tests `Round24` (TO-1..TO-5), `Round25` (TO-6a) and `Round26` (TO-10, A-2) with their table classes.

## P7 Impact map (M/L)

- `YdbMemberTranslator.cs:RoundScaled/RoundScaledAs/ScaledDecimalType/Pow10` callers — searched `RoundScaled|RoundScaledAs|ScaledDecimalType|Pow10|roundToInt` across `Source/` (worktree at PR head): only :726, :730, :792, :793, :802, :773, :774, :800, :820, :828 — covered by E-1
- Registrations reaching YDB's Round overrides — `MathMemberTranslatorBase.cs:71-99` `RegisterRound` (Math.Round decimal/double/float × precision × MidpointRounding, `Sql.Round`/`Sql.RoundToEven` nullable overloads `Sql.cs:1137-1167`), searched `TranslateRoundToEven|TranslateRoundAwayFromZero` — covered by E-2
- Shared decimal tests whose YDB SQL moves — `MathFunctionTests` Round1/3/5/7/9/10/12/13/14/15/16 (:219-:401), `WhereTests.SubQuery1` (:1186, no-op path, no move), `GroupByTests.AverageInGroup` (:1022), searched `(Math|Sql)\.Round(ToEven)?\s*\(|MidpointRounding` over `Tests/` — covered by E-1
- YDB-only decimal tests — `MathFunctionTests` Round17-Round23 (:424-:588) — covered by E-1
- Shared double tests (path unchanged) — `MathFunctionTests` Round2/4/4Sql/6/8/11 (:228-:331) — covered by E-1
- `SubQueryTests.Issue1601` (:673, `[ActiveIssue(5591)]` on YDB, `Math.Round(x + x)` decimal no precision) — covered by E-1
- Other providers' rounding — searched `Pow\(10|Pow10|Power.*10|\* 10\b` across `Internal/DataProvider` and read each Round override (ClickHouse `roundBankers` :271, Access :216-254, PostgreSQL :273-297, SqlServer/SqlCe/Sybase base) — Localized — searched Double-scaling rounding across Internal/DataProvider, no other provider rounds a Decimal through Double; no emitted-SQL change outside YDB.
- `Linq/Expressions.cs:791-945` per-provider `Sql.Round` mappings — searched for YDB entries — Localized — searched Sql.Round/RoundToEven mappings in Expressions.cs, none for YDB, no emitted-SQL change.
- `YdbSqlExpressionConvertVisitor.cs:257-270` `Math::Floor/Ceil/Trunc` on Decimal via plain `CAST(decimal AS Double)` — same precision class, different functions — deferred: not part of PR #5943's surface; candidate follow-up issue for Floor/Ceiling/Truncate.
- `YdbMemberTranslator.cs:678-681` `TranslateMinMax` via `GetCommonDecimalType` (`YdbMappingSchema.cs:31-44`), same DbType exposure as U-3 — out-of-scope
- `YdbOptions.UseParametrizedDecimal = false` — out-of-scope
- Surviving PR file `Source/LinqToDB/Internal/DataProvider/Translation/MathMemberTranslatorBase.cs` (descriptor cleared for Round precision) — out-of-scope
- Surviving PR file `Source/LinqToDB/Internal/DataProvider/PostgreSQL/PostgreSQLSqlExpressionConvertVisitor.cs` (`%` cast-back) — out-of-scope
- Serialized / remote shapes — the client's SQL AST crosses LinqService; `SqlCastExpression.IsMandatory` is serialized (`LinqServiceSerializer.cs:1781` write, `:3080` read) — covered by E-1
- `DbType`-only decimal columns (`ColumnDescriptor.cs:66-67,509`, `MappingSchema.cs:1453`) reaching `RoundScaled` with null P/S — out-of-scope
- Write-side `DbType`-only decimal sizing (`YdbMappingSchema.cs:629-637`, `MultipleRowsHelper.cs:103`, `YdbDataProvider.cs:446-455`) — deferred: pre-existing write-side defect, follow-up issue (P10)

## P8 Test obligations (M/L)

- TO-0 Every `Round24`/`Round25`/`Round26` case runs on both `YDB` and `YDB.LinqService` (`[IncludeDataSources(true, TestProvName.AllYdb)]`), so the mandatory casts are observed across the remote boundary (U-12) — proof: characterization
- TO-1 `Round24`: Decimal(22,9) `900719925474.09931` → `Math.Round(d, 4, mp)` = `900719925474.0993` and `123456789012.34567` → `Math.Round(d, 5, mp)` = `123456789012.34567`, both modes; discriminating input: scaled value > 2^53 (PR head answers `...0994` / `...34568`); mutation `isMandatory: false` on the rounding casts must also turn it red — proof: red→green
- TO-2 `Round24`: Decimal(22,9) `12345678901.234999999` → `Math.Round(d, 2, mp)` = `12345678901.23`, both modes; discriminating input: residue `.4999999` beyond Double precision (PR head and master answer `.24`) — proof: red→green
- TO-3 `Round24` ties at high significance, both modes, expected values from D-1/D-2: `12345678901.225` → even `.22`, away `.23`; `12345678901.235` → even `.24`, away `.24`; `-12345678901.225` → even `-.22`, away `-.23`; `-12345678901.235` → even `-.24`, away `-.24`; plus a NULL value row → NULL; mutation "drop the tie branches" must turn the `.225` away rows red, and mutation "CAST truncates" is represented by the `.235` to-even rows — proof: control
- TO-4 `Round24` runtime precision, `Sql.Round(d, r.P)` and `Sql.RoundToEven(d, r.P)` on Decimal(22,9): positive branch `12345678901.234999999`, P = 2 → `12345678901.23`; negative branch `1234567849999.999999999`, P = -5 → `1234567800000` and `1234567949999.999999999`, P = -5 → `1234567900000` (residue `.4999…` past Double precision; critic hand-computed head as `1234567900000` away / `1234568000000` even, to be observed red first) — proof: red→green
- TO-5 `Round24` no precision: `Math.Round(d, mp)` on Decimal(22,9) `1234567890123.499999999` → `1234567890123`, and `1234567890122.5` → even `1234567890122` / away `1234567890123` — proof: red→green
- TO-6a `Round25` scaffolded shape `[Column(DbType = "Decimal(6, 2)", Precision = 6, Scale = 2)]`, `1234.56` / `-1234.55` / `1000.05`, `Math.Round(d, 1, mp)` both modes, expected from C# `Math.Round`; a `t.ToArray()` round-trip assertion precedes the rounding one; head state observed before the fix (relabel characterization if green) — proof: red→green
- TO-10 `Round26` on `Decimal(4,4)`: `Math.Round(d, mp)` and `Sql.Round` / `Sql.RoundToEven(d, -1)` on `0.1234`, `-0.4999` (both modes) and `±0.5` (to-even) return 0; away-from-zero on `0.5` fails with `ROUND result is out of range for Decimal(4,4)`; the mutation "no `Decimal(P,P)` branch" is the pre-A-2 code, under which `Round22` failed with `Cannot cast type Decimal(35,35) into Decimal(35,0)` — proof: control
- TO-11 `Round27`: `Math.Round(g.Sum(x => x.D), mp)`, `Math.Round(g.Average(x => x.D), mp)` and `Math.Round(r.D * r.D, mp)` over a `Decimal(10,2)` column, both modes, expected from C#; mutation "no pin" turned AwayFromZero red with `Cannot substract different decimals` and left ToEven green (`mut-pin.log`) — proof: control
- TO-7 `MathFunctionTests.Round*`, `WhereTests.SubQuery1`, `GroupByTests.AverageInGroup`, `SubQueryTests.Issue1601` on YDB and YDB.LinqService all green (Issue1601's ActiveIssue gate either still holds or is removed in a P11 amendment if it now passes) — proof: characterization
- TO-8 Symmetry guard on the unchanged double path: YDB SQL for Round2/4/4Sql/6/8/11 byte-identical before/after, compared from the detailed test log SQL (or the CI baselines diff, which must list no YDB file for those tests) — proof: characterization
- TO-9 Strategy comment at E-4 matches D-1/D-2/D-5, checked by the plan critic or an independent reviewer, not the author — proof: characterization

## P9 Verification gates

- G-01: pass — uncommitted tree on `153a68af7`, 2026-10-14, local YDB, net10.0, YDB + YDB.LinqService. TO-0: every new test ran on both legs. TO-1/TO-2/TO-5 `Round24`: red at head with `…0994`, `…34568`, `…01.24`, `…124` (`round24-head3.log`), green after. TO-3 `Round24` tie rows 4-7: correct at head (exact in Double); mutation "drop the tie branches" turned only AwayFromZero red, on rows 4 and 6 (`mut-tie.log`). TO-4 `Round24` runtime: row 9 red at head (`1234568000000`), row 8 correct at head in ToEven, green after. TO-1 mutation `isMandatory: false` turned `Round24` red in both modes (`mut-mandatory.log`). TO-6a `Round25`: red at head with `Decimal(6,2) != Decimal(7,2)` after a passing round trip, green after. TO-10 `Round26`: green, guard message asserted for `+0.5` and `-0.5`. TO-11 `Round27`: control as recorded in P8. TO-7: 80 passed / 1 skipped of 81 (`to7-final3.log`, after A-3) — every `MathFunctionTests.Round*`, `WhereTests.SubQuery1`, `GroupByTests.AverageInGroup`; `SubQueryTests.Issue1601` skipped as `[ActiveIssue(5591)]` "still failing as expected", so its gate holds. TO-8: deferred to the CI baselines diff (G-02). TO-9: G-09 reader (`fable`) confirmed the strategy comment states D-1/D-2/D-5 correctly; its two imprecisions were fixed (A-3).
- G-02: — (pending) CI test-all baselines after push; expected: YDB decimal Round baselines move, no double-valued YDB test and no other provider moves (TO-8).
- G-05: pass — after A-3: `dotnet build Source/LinqToDB/LinqToDB.csproj -c Release -f netstandard2.0` and `-f net10.0`, and `Tests/Linq/Tests.csproj -c Release -f net10.0`: each Build succeeded, 0 warnings, 0 errors.
- G-06: pass — `git diff` limited to the rounding methods of `YdbMemberTranslator.cs` and additions to `MathFunctionTests.cs`.
- G-07: pass — scratch probes `ProbeYqlPrimitives`, `ProbeMin006`, `ProbeRound26Head`, `ProbeYqlCasts` and `using LinqToDB.Data;` removed; no Playground file touched.
- G-08: pass (local) — YDB-only translator under `Translation/`, resting on the red→green runs in G-01; CI test-all pending with G-02.
- G-09: pass — adversarial read by `fable` of the uncommitted diff: F1 (medium, computed values with no precision) measured and fixed (A-3, TO-11); F2-F5 fixed; verified non-issues recorded in its report (no optimizer folding of `scaled - scaled`, mandatory casts survive, sign/parity and NULL walked, no Decimal reaches the Double lambdas).

## P10 Adjudicated (M/L)

- A rounding carry past the declared precision at the type's maximum (`Math.Round(9999.99m, 1)` on `Decimal(6,2)`) still overflows: through `Unwrap` it fails the query for a non-null value, and for a nullable value the CAST yields NULL. Same as PR head and master (thread r4234063756, declined by the author with SQL Server's `ROUND` overflow as precedent); D-2 keeps every overflow inside a CAST so this does not change.
- Writing a decimal through a `DbType`-only mapping sizes the value `(22,9)` (U-14): literals and parameters ignore the string, so values with scale > 9 are cut and values with more than 13 integer digits are rejected on insert. Pre-existing, write side, outside P3; filed as a follow-up issue rather than fixed here.
- A `DbType`-only Decimal column (no `Precision`/`Scale`) is a known mapping gap, not handled before the v7 mapping redesign (A-1, user decision 2026-10-14). Its intermediates are sized from the `(22,9)` defaults, so with a declared scale above 9 the widening cast rounds the value silently (critic round 1: `Decimal(30,15)` `1.234999999999995` at p=2 → `1.24`), where PR head failed with a different-decimals error. Users are expected to declare `Precision`/`Scale`, as the scaffolder does.
- The comments at `YdbMemberTranslator.cs:554-557` / `:641-643` claiming `IsMandatory` is lost over LinqService are stale (U-12) but outside this plan's edit-points; E-4's new comment must not repeat the claim. Raised to the user as a separate observation.
- `UseParametrizedDecimal = false` is not supported by Decimal rounding: measured, a bare `CAST(... AS Decimal)` is a YQL `GenericError` (U-4), on master and at PR head alike.

## P11 Amendments (M/L)

- A-1 (2026-10-14, user decision) — narrows D-4: no `DbType` parsing. A `DbType`-only Decimal column (null Precision/Scale) is a known mapping gap, deferred to the v7 mapping redesign — users declare `Precision`/`Scale`. D-4 keeps only "strip `DbType` from the computed intermediates" (needed by the scaffolded shape). E-3b and E-3c are removed; `YdbSchemaProvider.cs` is unchanged; `Round26` is dropped. Approval of the narrowed set: given by the user in the same turn (choice C over "decline loudly" and "parse").
  re-derives (A-1): SC-6 (now the scaffolded shape only); U-13/U-14/U-15 (context only, no obligation); D-4 (chosen/rejected/failure mode); P6 (E-3b, E-3c struck); P7 (`DbType`-only row and `ParseType` row → out-of-scope); TO-6b..TO-6g (removed); P10 (new entry for the accepted gap); G-07 (scratch also covers `ProbeRound26Head`, removed). The implementation with parsing was measured green (`Round24`-`Round26`, 14/14 on YDB + YDB.LinqService) before the revert; the revert is mechanical.
- A-2 (2026-10-14) — narrows D-1 for a scaled type with no integer digits (`Decimal(P,P)`, U-16): `RoundDecimal` cannot cast it to `Decimal(P,0)`, so it returns `Ensure(scaled - scaled, <rounds to 0> OR scaled IS NULL, 'ROUND result is out of range for Decimal(P,S)')`. The value is below 1 in magnitude, so the result is 0, or ±1, which the type cannot hold — the P10 carry-at-maximum class, now failing with a message. Reached by the runtime negative branch and a constant negative precision on a `Decimal(P,P)` column, and by `Math.Round(d)` with no precision on one. Within E-1 (`RoundDecimal` is the helper `RoundScaledAs` calls) and E-5; the name `Round26` is reused for this new test after A-1 dropped the `DbType` one.
  re-derives (A-2): D-1 (chosen gains the `Decimal(P,P)` branch); P8 (TO-10 added); G-01 (`Round22` was the red that found it).
- A-3 (2026-10-14, from the G-09 read, finding F1) — narrows D-2: with no precision the tie arithmetic ran on the raw value, whose YQL type need not be the one linq2db infers (`Sum`, `Average`, a product over a `Decimal(10,2)` column), and YQL refused it with `Cannot substract different decimals` on both legs where PR head answered. Measured red, then fixed by a mandatory `CAST(value AS scaleType)` on the Decimal no-precision path in `RoundScaledAs` (E-1). New `Round27` (E-5) pins it; G-09's F2 (`Round26` now asserts both `±0.5` throw and compares lengths), F3 (new test chains one call per line) and F4/F5 (strategy and `Decimal(P,P)` comments) applied.
  re-derives (A-3): D-2 (the value is pinned before tie detection); P8 (TO-11 added, TO-10 widened to `-0.5`); G-01.

## P12 Critic verdict (M/L)

### Round 1 — `fable` — refuted

- D-4 / SC-6 / TO-6 refuted: a `DbType`-only column has null P/S (U-13), so stripping `DbType` alone widens from `(22,9)` defaults and the widening cast silently rounds a scale-15 value (`Decimal(30,15)` `1.234999999999995` p=2 → `1.24`, where head fails loudly). Changed: D-4 now parses P/S from a `Decimal(p,s)` DbType (E-3b); SC-6 names the accepted set; TO-6 split into a/b/c/d with round-trip controls; P10 records the unparseable-DbType reading.
- TO-6 weak: red mechanism was reasoned, and an insert into a `DbType`-only column is unprobed. Changed: U-14 and a round-trip assertion first in every TO-6 row.
- TO-4 weak: the negative row duplicated `Round23` and is green at head. Changed: replaced with `1234567849999.999999999` / `1234567949999.999999999` at P = -5.
- P7 remote row weak: wrong reason; the same file's comments claim `IsMandatory` is lost remotely. Changed: U-12 cites the serializer, TO-0 runs everything on `YDB.LinqService`, P10 records the stale comments.
- D-1 short-circuit hazard (`Scale` can be null). Changed: D-1 spells `(scaleType.Scale ?? DEFAULT_DECIMAL_SCALE) == 0`.
- Searched by the critic: helper callers across `Source/`; Round callers across `Tests/`; `IsMandatory` across `Source/` (optimizer fold, both ConvertConversion overrides, serializer, Equals); `AlignFloatingDecimal`; `PredicateExtensions` LikeSql; `YdbSqlBuilder.BuildSqlCastExpression` Unwrap; `BuildDataType`/`DbDataType.WithPrecisionScale`; D-2's four tie cases against truncating / half-away / half-up CAST mutants. Not checked by the critic: narrowing-cast rounding on a column (measured on literals only); DbType-only insert.
- Held: D-1, D-2, D-3 — "the tie adjustment is right for all four sign/parity cases, the mandatory cast pair survives both optimizer fold branches and the convert visitor".

### Round 2 — `fable` — refuted (fixtures only; design held)

- TO-6b/c/d and U-14 refuted: `CreateLocalTable` writes through `MultipleRowsHelper.cs:103` (literal sized `Precision ?? 22, Scale ?? 9`, `YdbMappingSchema.cs:629-637`) or parameters (`YdbDataProvider.cs:446-455`, no P/S, Sdk default 22,9) — neither reads the `DbType` string, so a `DbType`-only fixture is truncated or rejected on insert before and after the fix; the obligations cannot go green. D-4 and E-3b stand on the code read.
- D-4 parse condition weak: Precision and Scale are set independently (`ColumnDescriptor.cs:63-74`); fill each null component from the string, not only when both are null.
- E-3b weak (convention): `YdbSchemaProvider.ParseType` (`YdbSchemaProvider.cs:125-143`) already parses `Decimal(22, 9)`; reuse it.
- Whitespace variant unobserved: no `DbType`-only row uses the scaffolder's `Decimal(6, 2)` spacing.
- Verified by the critic: one reassignment of `valueType` at the top of `RoundScaled` reaches every P/S consumer (:753-755 no-op, :770-776, :788 Ensure message, :800, :819/:831); `MathMemberTranslatorBase.cs:234-249` adds no downstream P/S consumer.
- Revision cap reached (one round); outcome held for user direction. User chose (2026-10-14): apply all four fixes and send to the critic once more. Changed: D-4 fills each null component via `ParseType` (E-3b, new E-3c); U-14 restated, U-15 added; TO-6b..e moved to `Round26` with sibling-entity population, spaced form in TO-6b, partial mapping TO-6e; P7/P10 record the write-side sizing as a follow-up.

### Round 3 — `fable` — weak (folded in, visible here)

- D-4's per-component `??=` over `ParseType` would fill from a half parse (`"Decimal(30, 15) "` → `(30, null)` because `ParseType` drops the last character; `"Decimal(30)"` → `(30, null)`) and read the scale as 9 — the round-1 silent class behind a string that looks parsed. Changed: trim, require name `Decimal` and both numbers, otherwise decline (bare `Decimal` = defaults); TO-6f/TO-6g added.
- TO-0 omitted `Round26`. Changed.
- SC-6 did not name the partial shape TO-6e proves. Changed: SC-6(c), and (d) for the decline.
- Resolved by the critic's code read: remote member translation runs client-side (`RemoteDataContextBase.cs:151-168`, `:262-278`) and `DbType` is serialized (`LinqServiceSerializer.cs:164-172`, `:302-312`); the `GetTable<T>().TableName(...)` read-through-sibling pattern has precedent (`UpdateWithOutputTests.cs:673`); `YdbSchemaProvider` is public but `internal static ParseType` adds no public surface; TO-6e head/mutation/fixed states walked by hand.
- Not checked: YQL accepting whitespace inside a type in `CREATE TABLE` / `CAST` (TO-6a/6b observe it); head states and TO-4 negative values stay labelled unprobed.
- Held: D-1, D-2, D-3; "the fixture scheme is now sound end to end".
