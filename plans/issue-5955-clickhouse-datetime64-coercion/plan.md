# Work plan: issue-5955-clickhouse-datetime64-coercion — ClickHouse: coerce date/time operands to DateTime64 before toUnixTimestamp64Nano

**Tier:** L  ·  **Status:** reviewed  ·  **Approved-at:** 2026-09-22, E-1..E-7 including `D-3`'s retype  ·  **Branch:** issue/5955-clickhouse-datetime64-coercion
**Schema:** `.claude/docs/work-plan.md`  ·  **Gates:** `.claude/docs/definition-of-done.md`

Tier L because `E-2`/`E-3` sit under `Source/LinqToDB/Internal/DataProvider/ClickHouse/Translation/`, which matches
`.claude/rules/cross-cutting-core.md`'s `Source/LinqToDB/**/Translation/**`.

## P1 Problem

[#5955](https://github.com/linq2db/linq2db/issues/5955). On ClickHouse the reported query

```csharp
from grp in tempTable.GroupBy(_ => 1)
let minSampleDateTime = grp.Min(x => x.DateTime)      // [Column(DataType = DataType.DateTime)]
let maxSampleDateTime = grp.Max(x => x.DateTime)
let sampleDayCount = (int)(maxSampleDateTime - minSampleDateTime).TotalDays + 1
select new { sampleDayCount }
```

emits `toUnixTimestamp64Nano(MAX(grp.DateTime)) - toUnixTimestamp64Nano(MIN(grp.DateTime))` and the server answers

```
DB::Exception: A value of illegal type was provided as 1st argument 'value' to function
'toUnixTimestamp64Nano'. Expected: DateTime64, got: DateTime
```

**The general defect is not "the user declared a narrow `DataType`".** ClickHouse's `toUnixTimestamp64Nano` and
`toUnixTimestamp64Milli` accept **only** a `DateTime64`, and linq2db hands them whatever the operand happens to
be. The reported column is one of **four** ways an operand reaches them with a non-`DateTime64` *server* type,
and three of the four occur on the **default** mapping, where the user declared nothing at all. Measured against
the local server (26.5.7.64, `toTypeName` plus the raw call for each):

| operand kind | produced by | server type | `toUnixTimestamp64Nano` |
|---|---|---|---|
| `[Column(DataType = DataType.DateTime\|Date\|Date32)]` field | user declaration | `DateTime` / `Date` / `Date32` | `Code: 43 … got: DateTime` (and `got: Date32`) |
| `now()` | `ClickHouseMemberTranslator.cs:241-246` `TranslateNow` / `TranslateServerNow` | `DateTime` | `Code: 43 … got: DateTime` |
| `toDate32(col)` | `ClickHouseMemberTranslator.cs:185-189` `TranslateDateTimeTruncationToDate`, i.e. `x.Col.Date` | `Date32` | `Code: 43 … got: Date32` |
| `makeDateTime(y,m,d,H,M,S)` | `ClickHouseMemberTranslator.cs:161-168` `TranslateMakeDateTime` without milliseconds | `DateTime` | `Code: 43 … got: DateTime` |

So `(x.FinishedOn - x.FinishedOn.Date).TotalHours` and `(Sql.CurrentTimestamp - x.StartedOn).TotalHours` are
broken on ClickHouse **today, on a default-mapped column**. `MakeDateDifference`
(`DateFunctionsTranslatorBase.cs:1227`) accepts any translated operands, so every one of these reaches the
lowering.

**Why linq2db cannot see it.** All four operands are *typed* `DateTime64(7)` inside linq2db — `now()` and
`makeDateTime` because the translator types them from the mapping schema (`GetDbDataType(typeof(DateTime))`), the
aggregate over a declared column because `QueryHelper.GetDbDataTypeImpl` has no `SqlExtendedFunction` arm (`U-1`).
The declared type and the server type disagree by construction, so **no type test taken inside linq2db can
discriminate the broken operands**. That, not `U-1` alone, is why `D-1` is unconditional.

**Regression, 6.4.0 → 6.5.0.** Before [#5750](https://github.com/linq2db/linq2db/pull/5750) (`3a2960a20`)
`DateTime - DateTime` was not lowered: `(a-b).TotalDays` became `Sql.DateDiff(Day, …)` → `date_diff('day', …)`,
which ClickHouse accepts on any date type. #5750 gave ClickHouse `CanLowerIntervalDifference => true` plus a
lowering that passes its operands raw.

**Three raw-operand sites, plus one raw temporal.** A family sweep (`Grep "UnixTimestamp"` over `Source/`, 6
emission sites in 3 files) found exactly three that do not wrap:

| # | site | entry point | status |
|---|---|---|---|
| 1 | `ClickHouseSqlExpressionConvertVisitor.cs:62-63` `ElapsedTicks` | every `TimeSpan` member of a date difference | 6.5.0 regression |
| 2 | `ClickHouseMemberTranslator.cs:129` `TranslateDateTimeDateAdd`, `Millisecond` | `Sql.DateAdd(Millisecond, …)`, `DateTime.AddMilliseconds` | latent, pre-6.5.0 |
| 3 | `ClickHouseMemberTranslator.cs:95` `TranslateDateTimeDatePart`, `Millisecond` | `Sql.DatePart(Millisecond, …)`, `DateTime.Millisecond` | latent, pre-6.5.0 |
| 4 | `ClickHouseSqlExpressionConvertVisitor.cs:81-90` `LowerTemporalArithmetic` | a date shifted by an interval | 6.5.0 regression, `Date`/`Date32` operands only |

Site 4 is a different function but the same shape: measured, `toDate32('2026-01-01') + toIntervalNanosecond(100)`
raises `DB::Exception: addNanoseconds cannot be used with Date32` (and `… with Date`). A `DateTime` temporal is
fine — it returns `DateTime64(9)` with the sub-second part intact — so this site fails on the two date-only types
alone.

Already-wrapped, unaffected: `ClickHouseMemberTranslator.cs:215-216` (`CommonTruncationToTime`, precision 7) and
`Sql.DateTime.cs:488` (`DateDiffBuilderClickHouse`, precision 3).

## P2 Success criteria

- SC-1 The reported query answers on ClickHouse over a `DataType.DateTime` column, with the value the CLR computes → TO-1
- SC-2 `(b - a).Ticks` over a `DataType.DateTime` column equals the CLR tick count exactly → TO-2
- SC-3 A date difference over a `DataType.Date32` column answers, so the fix covers the declared-type class and not just the one type the issue named → TO-3
- SC-4 `Sql.DateAdd(Millisecond, 226, col)` and `col.AddMilliseconds(226)` over a `DataType.DateTime` column answer → TO-4
- SC-5 `Sql.DatePart(Millisecond, col)` and `col.Millisecond` over a `DataType.DateTime` column answer → TO-5
- SC-6 On a **default-mapped** column, a difference taken against `x.Col.Date` answers with the value the CLR computes → TO-8
- SC-7 On a **default-mapped** column, a difference taken against `Sql.CurrentTimestamp` answers → TO-9
- SC-8 A date shifted by a computed difference answers over both a `DataType.DateTime` and a `DataType.Date32` column → TO-7
- SC-9 A `DateAdd(Millisecond)` wrapped in an explicit `Sql.Convert` answers over a `DataType.DateTime` column → TO-10 (originally worded as "is honoured rather than silently discarded", on `D-3`'s premise; narrowed by `A-1` once that premise was measured false — it was never being discarded)
- SC-10 Every shape above still answers identically over the existing default-mapped fixtures, and no non-ClickHouse baseline moves → TO-6

## P3 Constraints & anti-goals (M/L)

- No change to any provider other than ClickHouse. Searched `git grep "ElapsedTicks(SqlIntervalDifferenceExpression"` across `origin/master`: 9 other providers override it, every one naming a type-tolerant function (DuckDB `Date_Diff`, YDB `Interval` subtraction, MySQL `TIMESTAMPDIFF`, SQL Server `DATEDIFF_BIG`, PostgreSQL `EXTRACT(EPOCH …)`). No sibling moves in lockstep.
- **No change to `Source/LinqToDB/Internal/SqlQuery/QueryHelper.cs`.** `U-1` found a real, provider-agnostic typing defect there; repairing it is a cross-cutting-core change with whole-product blast radius and is out of scope for a patch release (`.claude/rules/cross-cutting-core.md`).
- No new public API. The helper is `internal`, so no `PublicAPI.Unshipped.txt` entry and no `CompatibilitySuppressions.xml` work.
- Query-cache behaviour unchanged — the coercion is a static shape decision taken during SQL conversion, not a value-dependent one.
- The `~292-year` usable span `ElapsedTicks`' existing remarks already document is **not** widened or narrowed. `D-1` keeps precision 7 specifically so that no date that converts today stops converting.
- Anti-goal: the wider ClickHouse date-typing cleanup the sweep also surfaced (`toISOWeek`'s precision-`1` literal and `longDataType` result type at `:90`; `toDate32` tagged `DataType.DateTime` at `:193`; `DateDiffBuilderClickHouse`'s hardcoded `3`). Declined by the user after being offered; none of it produces a server error.
- Anti-goal: TO-8's and TO-9's shapes are pinned on ClickHouse only, not widened to `[DataSources]`. They are correct everywhere and only ever failed here; a repo-wide widening is coverage work, not this fix.

## P4 Unknowns (M/L)

- U-1 Can the coercion be applied only when the operand is not already `DateTime64`, discriminating on `QueryHelper.GetDbDataType(expr, MappingSchema)`? — **No. Refuted twice over.** (a) `MAX(field)` is a `SqlExtendedFunction` (`AggregateFunctionsMemberTranslatorBase.cs:375-387`), which `QueryHelper.GetDbDataTypeImpl` (`QueryHelper.cs:697-736`) has no arm for, so it falls to the catch-all at `:735` → `Undefined` → the mapping-schema fallback at `:671-681` → `DateTime64(7)`; the node's own declared type is schema-derived too (`AggregateFunctionsMemberTranslatorBase.cs:292`/`:364`). (b) More generally, `P1`'s table: `now()` and `makeDateTime(...)` are typed `DateTime64(7)` while the server makes them `DateTime`. A conditional would skip the reported repro **and** two default-mapping shapes. — resolved-by scout + critic
- U-2 Would a wrong `DbDataType` on the generated function node cause a downstream cast that truncates the value back to second precision? — Not on the read path. `WrapColumnExpression` (`SqlExpressionConvertVisitor.cs:2438-2458`, ClickHouse override `:487-495`) casts only null literals and null-valued non-query parameters; `BasicSqlBuilder.cs:977-980` and `ClickHouseSqlBuilder.cs:507-515` emit a column expression bare; `SqlExpressionOptimizerVisitor.cs:1350-1365` only removes casts. It *does* bite under an explicit `Sql.Convert`, a rendered `SqlCastExpression`, or an UPDATE `SET` — which is what `D-3` and TO-10 are for. — resolved-by scout
- U-3 Does fixing `ElapsedTicks` alone cover every `TimeSpan` member? — Yes. `LowerIntervalPart` (`SqlExpressionConvertVisitor.cs:1632`) routes `.Ticks` through `ElapsedTicks` at `:1645`, every other member through `:1652` (`ElapsedTicksResolveMembers` is `true`; ClickHouse does not override it), and the fallback at `:1677`; ClickHouse overrides neither `CountDateBoundaries` nor `ShiftDate`, so `:1661`/`:1668` return null and fall through. — resolved-by scout
- U-4 Would `Factory.Cast(expr, DateTime64)` work instead of an explicit `toDateTime64(…)` function? — **Yes, in its mandatory form.** `SqlExpressionOptimizerVisitor.cs:1352` strips only `!element.IsMandatory`, and `Factory.Cast(expr, type, isMandatory: true)` exists (`SqlExpressionFactoryExtensions.cs:122`); the provider already uses it at `ClickHouseMemberTranslator.cs:187`. The plan's original rejection reason was wrong and is corrected in `D-1`. — resolved-by critic, verified at `SqlExpressionOptimizerVisitor.cs:1350-1357`
- U-5 Is `LowerTemporalArithmetic` also broken on a non-`DateTime64` temporal? — **Yes, for `Date` and `Date32` only.** Measured: `toDate32('2026-01-01') + toIntervalNanosecond(100)` → `DB::Exception: addNanoseconds cannot be used with Date32`; `toDate(...)` → `… with Date`; `toDateTime('2026-01-01 10:00:00') + toIntervalNanosecond(500000000)` → `DateTime64(9)`, `2026-01-01 10:00:00.500000000`. So site 4 joins `P6` as part of `E-1`. — resolved-by probe (HTTP query against the local server)
- U-6 Does the local container reproduce the issue's failure? — Yes. `SELECT toUnixTimestamp64Nano(toDateTime('2026-01-01 10:00:00'))` on 26.5.7.64 returns the issue's error verbatim (`Code: 43 … Expected: DateTime64, got: DateTime`). — resolved-by probe
- U-7 Is `toDateTime64(x, 7)` an exact no-op over an operand that is already `DateTime64(7)`? — Yes: `toUnixTimestamp64Nano(v) = toUnixTimestamp64Nano(toDateTime64(v, 7))` returns `1` for a 7-digit value. Over `DateTime64(9)` it truncates to tick resolution (`…123456789` → `…123456700`), which is `D-1`'s named failure mode. — resolved-by probe
- U-8 Would raising the wrap precision to 9 remove that truncation for free? — No. `toDateTime64(toDateTime64('2290-01-01', 7), 9)` raises `Code: 407 … DateTime64 convert overflow`, so precision 9 turns dates in roughly 2262–2299 from a silently wrapped number into a hard error. Precision 7 keeps today's documented range behaviour exactly. — resolved-by probe
- U-9 Does a `DataType.Date32`-declared `DateTime` column round-trip through the Octonica writer? Both the literal path (`ClickHouseMappingSchema.cs:309` → `BuildDate32Literal`) and the parameter path (`ClickHouseDataProvider.cs:206`) look supported. — resolved-by probe: TO-3 fails on the *insert* rather than the query if not, which is distinguishable from the defect under test; if it does not round-trip the `Date32` obligations move to a `Date32`-typed literal comparison instead and `P11` records it.

## P5 Decisions (M/L; rejected alternatives mandatory at L)

### D-1 — Coerce **unconditionally** with `toDateTime64(x, 7)`

- **chosen:** every operand of a `toUnixTimestamp64*` call, and the temporal of the interval shift, is wrapped in `toDateTime64(x, ClickHouseMappingSchema.DEFAULT_DATETIME64_PRECISION)` with no type test.
- **rejected:** wrap only when `QueryHelper.GetDbDataType(operand).DataType != DataType.DateTime64` — refuted by `U-1`. linq2db's type for an operand and the operand's server type disagree *by construction* for three of the four kinds in `P1`'s table, so no in-process type test can discriminate them.
- **rejected:** `Factory.Cast(operand, DateTime64, isMandatory: true)` instead of the explicit function. This **would** work — `U-4` — and it is not rejected on correctness. It is rejected because the provider's own precedent for exactly this coercion is the explicit function (`ClickHouseMemberTranslator.cs:215-216`), and because the emitted SQL then names the ClickHouse function the operand actually needs rather than a `CAST` the builder has to translate back into one.
- **rejected:** return `null` from `ElapsedTicks` for a suspect operand, leaving the expression to .NET — it does not fall back. `CanLowerIntervalDifference` is read at expression-build time (`DateFunctionsTranslatorBase.cs:623`), long before the convert visitor runs, so the read expression is already bound to its columns. A `null` leaves the node for `base.VisitSqlIntervalDifferenceExpression` (`SqlExpressionConvertVisitor.cs:1471-1478`), which reaches the SQL builder and is refused by name — a hard failure with no client-side answer.
- **rejected:** route ClickHouse through `dateDiff('nanosecond', …)` — a redesign of the lowering for a patch release, and `dateDiff`'s own operand typing would still need probing.
- **why this:** the permanent reason is `P1`'s: the operands are *manufactured* with a server type the translator never records — `now()` is `DateTime`, `toDate32(col)` is `Date32`, `makeDateTime(...)` is `DateTime`, all three typed `DateTime64(7)` inside linq2db. That is a property of ClickHouse's own function signatures, not of any linq2db bug, so it does not go away if `U-1`'s `QueryHelper` gap is later fixed. `toDateTime64` is measured safe over `Date`, `Date32`, `DateTime` and every `DateTime64` precision (`U-7`), so an unconditional wrap is never wrong.
- **failure mode of the choice:** three costs, all bounded and all measured. (a) ClickHouse baselines move for every interval, `DateAdd(Millisecond)` and `DatePart(Millisecond)` query — noise, no behaviour change; `G-02` reviews it. (b) On a `DateTime64(8|9)` column each operand is truncated to 100 ns before the subtraction rather than the difference being truncated after, which can differ by one tick; `TimeSpan.Ticks` cannot represent finer than 100 ns, so the tick count is right either way. (c) The same truncation on `E-2` is observable on **write-back** — ClickHouse has `ALTER TABLE … UPDATE` (`ClickHouseSqlBuilder.cs:350`) — so `Set(x => x.Col9, x => x.Col9.AddMilliseconds(5))` over a `DateTime64(9)` column loses digits 8-9, which it did not before. Accepted rather than fixed with precision 9, because `U-8` measured that precision 9 raises a hard overflow for dates around 2262–2299 that convert fine today.

### D-2 — One `internal static` helper, not a private copy per file

- **chosen:** `ClickHouseDateTime.AsDateTime64(ISqlExpressionFactory, ISqlExpression)` in a new file under `Source/LinqToDB/Internal/DataProvider/ClickHouse/`, returning `GetDbDataType(expr).WithDataType(DataType.DateTime64).WithPrecision(DEFAULT_DATETIME64_PRECISION)`-typed `toDateTime64(expr, 7)`. Called from all four sites.
- **rejected:** a private helper in each of the two files — duplicated lines whose two copies can drift, and the whole point is that all four sites obey one rule.
- **rejected:** a `public static` member on `ClickHouseSqlExpressionConvertVisitor` — adds public API surface for something no external provider needs, and the visitor is the wrong home for a helper half of whose callers live in the translator.
- **why this:** four call sites in two files and two namespaces (`…ClickHouse` and `…ClickHouse.Translation`), both of which hold an `ISqlExpressionFactory` — the visitor as `Factory` (`SqlExpressionConvertVisitor.cs:27`), the translator as `translationContext.ExpressionFactory`. `internal` keeps it off the API surface. `SqlFunction`'s default nullability is `IfAnyParameterNullable` (`SqlFunction.cs:12`), which is right here — the literal precision is never null — so no explicit flag is needed.
- **failure mode of the choice:** a new file for one six-line method is more ceremony than the change deserves if a fifth site never appears; the alternative is worse, because a drifting copy is a silent wrong answer.

### D-3 — Result type of the `DateAdd(Millisecond)` node becomes `DateTime64(9)` — **ABANDONED, see A-1**

- **chosen:** ~~`E-2` also changes `fromUnixTimestamp64Nano`'s declared `DbDataType` from the operand's own type to `dateType.WithDataType(DataType.DateTime64).WithPrecision(9)`, which is what the function actually returns.~~ Abandoned: the premise below is refuted by measurement.
- **rejected:** leave the result typed as the operand's declared type — `U-2` proved nothing casts it on the read path, so a bare projection is right today. But the node then claims `DateTime` for a `DateTime64(9)` value, and `SqlExpressionOptimizerVisitor.cs:1352-1357` **strips a user's own non-mandatory `Sql.Convert(Sql.Types.DateTime, …)`** because `from.EqualsDbOnly(to)` holds — the requested conversion silently does not happen.
- **rejected:** `.WithDataType(DataType.DateTime64)` leaving precision null — the builder defaults null to 7 (`ClickHouseSqlBuilder.cs:174`), which is harmless but untrue.
- **why this:** the declared type should describe the value the expression produces. Where the operand is already `DateTime64` this row still changes (precision 7 → 9), which is why TO-6 guards the default path.
- **failure mode of the choice:** if some path relies on the node reporting the *column's* type rather than the expression's, this changes it — scout-searched (`U-2`), none found on the read path. TO-10 is the guard, and it is written to be able to fail: **if the run shows `Sql.Convert` does not discriminate either, `D-3` is dropped rather than shipped unguarded.**

## P6 Edit-points

- E-1 `Source/LinqToDB/Internal/DataProvider/ClickHouse/ClickHouseSqlExpressionConvertVisitor.cs:57-66:ElapsedTicks` — both operands wrapped via `ClickHouseDateTime.AsDateTime64`; the `<remarks>` paragraph asserting the `DateTime64(7)` mapping corrected to rest on the coercion. → TO-1, TO-2, TO-3, TO-6, TO-8, TO-9
- E-2 `Source/LinqToDB/Internal/DataProvider/ClickHouse/ClickHouseSqlExpressionConvertVisitor.cs:81-90:LowerTemporalArithmetic` — `element.Temporal` wrapped, per `U-5`'s measurement that `addNanoseconds` refuses `Date` and `Date32`. → TO-7
- E-3 `Source/LinqToDB/Internal/DataProvider/ClickHouse/Translation/ClickHouseMemberTranslator.cs:124-135:TranslateDateTimeDateAdd` (`Millisecond` branch) — operand wrapped. The result-type change `D-3` authorized was abandoned before it was written; see `A-1`. → TO-4, TO-6, TO-10
- E-4 `Source/LinqToDB/Internal/DataProvider/ClickHouse/Translation/ClickHouseMemberTranslator.cs:95:TranslateDateTimeDatePart` (`Millisecond` arm) — operand of `toUnixTimestamp64Milli` wrapped, and the remainder corrected into range per `A-2`. → TO-5, TO-6, TO-11
- E-5 `Source/LinqToDB/Internal/DataProvider/ClickHouse/ClickHouseDateTime.cs` — new file; `internal static class ClickHouseDateTime` with `AsDateTime64(ISqlExpressionFactory, ISqlExpression)` per `D-2`, at `max(operand precision, 7)` and over a `DbType`-free result type per `A-2`. → TO-1..TO-11
- E-6 `Tests/Linq/Linq/IntervalTranslationTests.ClickHouse.cs` — new partial; `CoarseEventRow` (`DataType.DateTime` pair + `DataType.Date32` pair) and the difference / shift / default-mapping obligations. → TO-1, TO-2, TO-3, TO-6, TO-7, TO-8, TO-9
- E-7 `Tests/Linq/Linq/DateTimeFunctionsTests.cs` — ClickHouse-scoped `DateAdd` / `DatePart` millisecond obligations over a second-precision column, plus TO-10's conversion guard. → TO-4, TO-5, TO-6, TO-10

## P7 Impact map (M/L)

- **Operand kinds**, not just emission sites — searched `TranslateNow|now\(|toStartOf|toDateTime\(|MakeDateTime|\.Date\)` across `DataProvider/ClickHouse` and `DateFunctionsTranslatorBase.cs`, then `toTypeName` on the server for each. Four kinds reach `toUnixTimestamp64*` with a non-`DateTime64` server type: a declared field, `now()` (`ClickHouseMemberTranslator.cs:241-246`), `toDate32(col)` (`:185-189`), `makeDateTime(...)` (`:161-168`). All four covered by E-1; TO-8 and TO-9 pin the two default-mapping ones
- `Source/` `toUnixTimestamp64*` / `fromUnixTimestamp64*` family — searched `Grep "UnixTimestamp"` over the worktree's `Source`, 6 emission sites in 3 files. Raw-operand sites exactly `ClickHouseMemberTranslator.cs:95`, `:129`, `ClickHouseSqlExpressionConvertVisitor.cs:62-63` — covered by E-1, E-3, E-4
- `ClickHouseMemberTranslator.cs:476` emits `toUnixTimestamp` (no `64`); measured to accept `DateTime` — out-of-scope
- `ClickHouseMemberTranslator.cs:215-216` (`CommonTruncationToTime`) and `Sql.DateTime.cs:488` (`DateDiffBuilderClickHouse`) already wrap their operands — out-of-scope
- Callers of `ElapsedTicks` / `LowerTemporalArithmetic` — searched `Grep "ElapsedTicks|LowerTemporalArithmetic" glob=*.cs`; nothing in `Source/` calls the ClickHouse overrides directly, they are reached only via `SqlExpressionConvertVisitor.cs:1416`, `:1492`, `:1645`, `:1652`, `:1677`. All three interval node kinds that can reach them — `SqlIntervalDifferenceExpression`, `SqlIntervalPartExpression`, `SqlTemporalArithmeticExpression` — covered by E-1, E-2
- `SqlIntervalExpression` → `VisitSqlIntervalExpression` (`SqlExpressionConvertVisitor.cs:1333`) returns `Visit(element.Value)` and never reaches `ElapsedTicks` — out-of-scope
- `TranslateDateTimeOffsetDateAdd` / `TranslateDateTimeOffsetDatePart` route to the `DateTime` variants (`DateFunctionsTranslatorBase.cs:1833-1835`; ClickHouse `:100-103`), so E-3/E-4 need no `DateTimeOffset` twin — covered by E-3, E-4
- Mirrored provider sites — searched `git grep "ElapsedTicks(SqlIntervalDifferenceExpression"` across `origin/master`; 9 other providers, every one naming a type-tolerant function. No lockstep move — out-of-scope
- `WrapColumnExpression` overrides across 9 providers (`SqlExpressionConvertVisitor.cs:2438`, ClickHouse `:487`) — all null/parameter-shaped, none type-driven on a function node, so `D-3`'s retyping cannot trigger a cast there — out-of-scope
- `SqlCastExpression.IsMandatory` round-trips the remote contract (`LinqServiceSerializer.cs:1781` write, `:3080-3082` read) — relevant only to the rejected cast alternative, which is not taken — out-of-scope
- `QueryHelper.GetDbDataTypeImpl` (`QueryHelper.cs:697-736`) has no `SqlExtendedFunction` arm, so every aggregate's declared `DbDataType` facets are discarded for the mapping-schema default — a real, provider-agnostic typing defect — deferred: cross-cutting core, out of a patch release's blast radius; to be filed as its own issue with this evidence
- `LinqService` / serialized enums — no AST node, enum member or wire shape is added or changed; the edit rewrites the parameters of an existing `SqlFunction` — Localized — searched `SqlIntervalDifferenceExpression`, `SqlTemporalArithmeticExpression` across `Source/LinqToDB/Internal/Remote`, no serialization surface touched
- `DataType` switches in the ClickHouse provider — searched `Grep "case DataType\.|DataType\.DateTime64|DataType\.Undefined"` over `…/DataProvider/ClickHouse`; `ClickHouseSqlBuilder.cs:171-174`, `ClickHouseMappingSchema.cs:304-316` and `:553-567` already enumerate `Date`/`Date32`/`DateTime` beside `DateTime64` — out-of-scope

## P8 Test obligations (M/L)

- TO-1 `ReportedDayCountOverASecondPrecisionColumn` — the issue's shape verbatim (`GroupBy(_ => 1)`, `Min`/`Max`, `(int)(max-min).TotalDays + 1`) over `CoarseEventRow`'s `DataType.DateTime` pair. Discriminating input: the declared `DataType.DateTime`, which is what makes the server see `DateTime` where linq2db reports `DateTime64(7)`. If the red does not appear, the premise is re-opened rather than worked around. — proof: red→green (red = `Code: 43 … Expected: DateTime64, got: DateTime`)
- TO-2 `TickCountOverASecondPrecisionColumnMatchesClr` — `(FinishedOn - StartedOn).Ticks` over the same pair, exact equality against the CLR, endpoints whole seconds apart so the column can hold both. — proof: red→green
- TO-3 `DifferenceOverADate32ColumnMatchesClr` — the same difference over the `DataType.Date32` pair. Distinguishes an insert-side failure (`U-9`) from the defect under test by asserting the round-tripped values first. — proof: red→green (red = `… got: Date32`)
- TO-4 `DateAddMillisecondOverASecondPrecisionColumn` — `Sql.DateAdd(Millisecond, 226, col)` **and** `col.AddMilliseconds(226)` over a `DataType.DateTime` column; asserts the CLR value including the 226 ms. This row guards `E-3`'s coercion only — it cannot distinguish `D-3` shipping from `D-3` being dropped, because `U-2` established that nothing casts the bare projection; TO-10 is `D-3`'s guard. — proof: red→green (red = the server exception)
- TO-5 `DatePartMillisecondOverASecondPrecisionColumn` — `Sql.DatePart(Millisecond, col)` **and** `col.Millisecond` over a `DataType.DateTime` column. Stated plainly: the asserted value (`0`) is **not** discriminating — every plausible wrong wrap precision also answers 0 over a whole-second column — so this row's entire content is that the query *executes*. Its red arm is `toUnixTimestamp64Milli` refusing `DateTime`, measured directly on the server. — proof: red→green (red = `Code: 43 … to function 'toUnixTimestamp64Milli' … got: DateTime`)
- TO-6 symmetry guard on the unchanged path — the existing `DateTimeFunctionsTests.DateAddMillisecond` / `AddMilliseconds` / `DatePartMillisecond` / `Millisecond` and the whole existing `IntervalTranslationTests` fixture, all of which run on ClickHouse over default-mapped columns, left untouched and required to stay green. `Tests/Model/LinqDataTypes.cs:18,92` declares `Precision = 3` for ClickHouse and `Data/Create Scripts/ClickHouse.sql:37` creates `DateTime64(3)`, so this genuinely exercises the (3)→(7) upscale rather than a no-op. — proof: characterization — proves no new behaviour on the default mapping
- TO-7 `ShiftOverASecondPrecisionColumn` **and** `ShiftOverADate32Column` — `ShiftOrigin + (FinishedOn - StartedOn)` over each pair, asserting the shifted date the CLR computes. The two halves have different proof modes and are recorded separately in `P9`: the `DateTime` half is green before the fix (measured: `DateTime + toIntervalNanosecond` works), the `Date32` half is red (measured: `addNanoseconds cannot be used with Date32`). — proof: red→green for the `Date32` half, characterization for the `DateTime` half
- TO-8 `DifferenceAgainstTheDatePartMatchesClr` — `(r.FinishedOn - r.FinishedOn.Date).TotalHours` over the **existing default-mapped** `EventRow`, i.e. no custom `DataType` anywhere. This is the obligation that pins `P1`'s central claim: the bug is not about user declarations. — proof: red→green (red = `… got: Date32`, from the `toDate32` the `.Date` translation emits)
- TO-9 `DifferenceAgainstServerNowAnswers` — `(Sql.CurrentTimestamp - r.StartedOn).TotalDays` over the default-mapped `EventRow`, with `StartedOn` seeded in the past and the assertion a bound rather than an equality, because `now()` is not deterministic. — proof: red→green (red = `… got: DateTime`, from `now()`)
- TO-11 `DatePartMillisecondBeforeTheEpoch` — `Sql.DatePart(Millisecond, col)` and `col.Millisecond` over a **default-mapped** column holding `1969-01-01 00:00:00.500`, asserting `500`. Added by `A-2`. Discriminating input: the pre-epoch date, the only input on which the corrected and uncorrected remainders differ; the column is default-mapped because a ClickHouse `DateTime` starts at 1970 and cannot hold one. — proof: red→green (red = `-500`, measured on the server before the change)
- TO-10 `ConvertedDateAddMillisecondHonoursTheRequestedType` — `Sql.Convert(Sql.Types.DateTime, col.AddMilliseconds(226))` over a `DataType.DateTime` column, asserting the milliseconds are gone. Written as `D-3`'s control and **failed to be one**: the cast is emitted rather than stripped, both before and after, so the assertion holds either way and `D-3` was abandoned on that evidence (`A-1`). Kept because it is still a real obligation for the coercion — the whole query is refused by the server without it. — proof: red→green (red = the `toUnixTimestamp64Nano` refusal, observed)
- Harness capability: every row needs `ClickHouse.Octonica` enabled in the `NET100` bucket and the local `clickhouse` container running. Both in place — the worktree carries its own `UserDataProviders.json` with `SQLite.MS` + `ClickHouse.Octonica` + `DuckDB` enabled and nothing else, and the container serves `testdb1` on 26.5.7.64.

## P9 Verification gates

All rows describe the worktree at the post-fix state (2026-09-22), i.e. after the four coercion edits and with
`D-3` abandoned per `A-1`. The red arms are from the run against unfixed code at the same head.

- G-01: pass — 2026-09-22. Red arm: `worktree-test.ps1 … -Provider ClickHouse.Octonica` before the fix → `total: 12, failed: 10`, and every failure message was read from the log and matched its row's expected refusal. Green arm after the fix → `total: 12, failed: 0, succeeded: 12` in 16.6 s. Per obligation:
  - TO-1 `ReportedDayCountOverASecondPrecisionColumn` — red `… 'toUnixTimestamp64Nano'. Expected: DateTime64, got: DateTime`; green, day count 8
  - TO-2 `TickCountOverASecondPrecisionColumnMatchesClr` — red same refusal; green, exact CLR tick count
  - TO-3 `DifferenceOverADate32ColumnMatchesClr` — red `… got: Date32`; green, and the round-trip guard on `OpenedOn`/`ClosedOn` passed, so `U-9` is resolved: `Date32` does round-trip through Octonica
  - TO-4 `DateAddMillisecondOverASecondPrecisionColumn` — red `… got: DateTime` on `SELECT fromUnixTimestamp64Nano(toUnixTimestamp64Nano(r.Value) + toInt64(226000000))`; green
  - TO-5 `DatePartMillisecondOverASecondPrecisionColumn` — red `… 'toUnixTimestamp64Milli'. Expected: DateTime64, got: DateTime` on `SELECT toUnixTimestamp64Milli(r.Value) % 1000`; green. Value assertion is non-discriminating by design (`P8`); the red arm is the whole content and it was observed
  - TO-6 characterization — the full `IntervalTranslationTests` + `DateTimeFunctionsTests` fixtures over the default-mapped models: `total: 1319, failed: 0, succeeded: 1286, skipped: 33` across ClickHouse.Octonica + SQLite.MS + DuckDB; plus `DateTimeOffsetTests` / `DateOnlyFunctionTests` / `ClickHouseTypeTests` / `TypesTests` / `ConvertTests` on ClickHouse.Octonica: `total: 556, failed: 0, succeeded: 553, skipped: 3`
  - TO-7 `ShiftOverASecondPrecisionColumnMatchesClr` — red, but on the *difference* inside it (`got: DateTime`), not on the shift; `characterization` for `E-2` as `P8` predicted. `ShiftOverADate32ColumnMatchesClr` — red `got: Date32`, and `E-2` is what its green needs, since `toDate32(x) + toIntervalNanosecond(…)` raises `addNanoseconds cannot be used with Date32` independently of `E-1`
  - TO-8 `DifferenceAgainstTheDatePartMatchesClr` — red `… got: Date32` on `SELECT … toUnixTimestamp64Nano(toDate32(r.FinishedOn)) … FROM EventRow`, i.e. the **default-mapped** model with no `DataType` declared anywhere; green. This is the obligation that carries `P1`'s central claim
  - TO-9 `DifferenceAgainstServerNowAnswers` — red `… got: DateTime` on `SELECT COUNT(*) FROM EventRow AS r WHERE … toUnixTimestamp64Nano(now()) …`; green, count 1
  - TO-10 `ConvertedDateAddMillisecondHonoursTheRequestedType` — red `… got: DateTime`; green. Its intended role as `D-3`'s control failed, see `A-1`
  - TO-11 `DatePartMillisecondBeforeTheEpoch` — added by `A-2`; green in the post-amendment run. Red measured at the SQL level rather than by a pre-change test run: `toUnixTimestamp64Milli(toDateTime64('1969-01-01 00:00:00.500', 7)) % 1000` returns `-500` against the asserted `500`
- G-02: pass, with the authoritative diff deferred to CI — 2026-09-22. `BaselinesPath` here is `C:\GitHub\linq2db.bls`, a plain dump directory rather than a git clone, so there is no local diff-against-master; the churn was characterized by inspecting the regenerated dumps directly. Of 258 `ClickHouse.Octonica` baseline files, **59** contain one of the three changed functions: 10 are the new tests and **49 are the churn** — every one an interval, `DateAdd(Millisecond)`, `DatePart(Millisecond)`, `DateDiff(Millisecond)`, `SubDate*` or `TimeOfDay` query, exactly the set `D-1`'s failure mode (a) predicts, and nothing outside it. A sweep for a surviving raw operand (`toUnixTimestamp64(Nano|Milli)\((?!toDateTime64\()`) returned **one** hit, `DateTimeOffsetTests.GroupByDateTimeOffsetByAddMillisecondsTest`, whose file is dated 2026-09-08 — a stale dump from an earlier session that this run's filter never re-ran, not a missed site. No non-ClickHouse dump was touched. The real cross-provider diff is CI's baselines PR
- G-03: n/a — the helper is `internal` and all four edited methods are existing overrides / private branches, so no new public surface
- G-04: n/a — no public API change, so no `CompatibilitySuppressions.xml` refresh
- G-05: pass — 2026-09-22. `dotnet build Source/LinqToDB/LinqToDB.csproj -c Release -f netstandard2.0` → exit 0, `0 Warning(s) 0 Error(s)`; `-f net10.0` → exit 0; `Tests/Linq/Tests.csproj -c Release -f net10.0` → exit 0, `0 Warning(s) 0 Error(s)` (this is the one that validates the new fixtures' XML doc `cref`s, which are silent in `Debug`)
- G-06: pass — `git diff --stat` is 3 files / +89 / -8 plus 2 new files; no reformatting, no renames, nothing outside `P6`
- G-07: pass — `git status` shows nothing under `Tests/Tests.Playground/`
- G-08: pass — `E-3`/`E-4` sit under a cross-cutting-core path, and every claim about them rests on a reproduced red→green against a real ClickHouse server plus direct SQL probes, not on static reasoning. The one design claim that *was* reasoned (`D-3`) was measured and abandoned (`A-1`)
- G-09: pass — 2026-09-22, `/code-review` at high effort over the worktree diff. 13 findings. **1 refuted by a run already in hand** (it claimed TO-10 was red as committed; TO-10 passed — the reviewer's mechanism requires `from.EqualsDbOnly(element.Type)`, and the column type carries `Precision = null` against the conversion target's `7`, so the cast is not stripped. Same static-reasoning error `plan-critic` made on the same line, and the second independent reason `A-1` was right to abandon `D-3`). **7 fixed** (`A-2`) — the load-bearing one was a DST-straddling test window I had introduced, green here and red on any server in an observing zone. **1 fixed after the user chose between three remedies** (the pre-epoch millisecond, `A-2` (i)). **4 declined**: three are the pre-existing ClickHouse date-typing items the user explicitly declined at scoping (`toISOWeek`'s precision-`1` literal and `longDataType` result type, `CommonTruncationToTime`'s hand-rolled duplicate, `toUnixTimestamp64Milli` declared `Int32`), and one asked the helper to hand its result type back rather than let the caller re-read it — declined because `QueryHelper.GetDbDataTypeImpl` returns a `SqlFunction`'s declared `Type` verbatim (`QueryHelper.cs:719`), so the round-trip is exact and free
- Post-`A-2` re-verification, 2026-09-22: `total: 1466, failed: 0, succeeded: 1433, skipped: 33` over `IntervalTranslationTests` + `DateTimeFunctionsTests` + `DateTimeOffsetTests` across ClickHouse.Octonica + SQLite.MS + DuckDB; all three Release builds re-run green (`netstandard2.0`, `net10.0`, `Tests/Linq net10.0`), `0 Warning(s) 0 Error(s)`. TO-11's red is measured directly on the server rather than by a pre-change run: the expression `toUnixTimestamp64Milli(toDateTime64('1969-01-01 00:00:00.500', 7)) % 1000` returns `-500` where the CLR gives `500`

## P10 Adjudicated (M/L)

- **ClickHouse baseline churn is expected and is not a finding.** `D-1` chooses unconditional coercion, so `toDateTime64(x, 7)` appears in ClickHouse SQL where it did not before, including on operands that were already `DateTime64`. Measured cause: `U-1` plus `P1`'s operand table — linq2db's type for three of the four broken operand kinds is `DateTime64(7)` while the server's is not.
- ~~**The `DateTime64(8|9)` truncation is accepted, not overlooked.**~~ Superseded by `A-2`: the coercion now uses `max(operand precision, 7)`, so an already-`DateTime64` operand keeps every digit and there is no truncation to accept. `U-8`'s objection to a flat precision 9 still stands and is why the floor is 7 rather than 9 — an operand is only ever widened past 7 when it already declares that precision, and a value it can hold converts.
- **The `QueryHelper.GetDbDataTypeImpl` gap is deliberately not fixed here.** `P7` records it with evidence; it is cross-cutting core, affects every provider, and belongs in its own issue rather than a 6.5.1 patch.
- **The wider ClickHouse date-typing cleanup is out of scope**, per `P3`'s anti-goal — declined by the user after being offered.
- **TO-5's asserted value is not discriminating, and the row says so.** Its content is that the query executes. Not a gap to re-raise.

## P11 Amendments (M/L)

- A-1 (2026-09-22) — **`D-3` abandoned; `E-3` narrowed to the operand coercion alone.** `D-3` rested on the critic's claim that, with the node typed as the operand's own `DataType.DateTime`, a user's `Sql.Convert(Sql.Types.DateTime, …)` would be stripped by `SqlExpressionOptimizerVisitor.cs:1356-1357` as a redundant cast. **Measured false.** The red run's own SQL for TO-10, against unfixed code and without `D-3`, is `SELECT toDateTime(fromUnixTimestamp64Nano(toUnixTimestamp64Nano(r.Value) + toInt64(toFloat64(226000000))))` — the cast is emitted, not stripped. TO-10 then passed after the coercion fix with `D-3` **not applied**, so nothing observable distinguishes the two typings and the decision has no justification left. Recorded as abandoned rather than deferred: the design was wrong, not mistimed. `D-1` and `E-1`/`E-2`/`E-4` are unaffected; approval for them stands, and the approval for `D-3`'s half of `E-3` is void and not re-sought. TO-10 is kept — it is a genuine `red→green` for the coercion under a conversion wrapper (red = the `toUnixTimestamp64Nano` refusal), just not a control for `D-3`.

- A-2 (2026-09-22) — **`G-09`'s adversarial read produced four changes to the authorized surface; approval for those parts is void and was re-earned for the one that is a behaviour change.** (i) `E-4` now also corrects the millisecond remainder into range: `toUnixTimestamp64Milli(x) % 1000` returns a **negative** millisecond before 1970 because the epoch is negative and `%` truncates toward zero — measured on the server, `1969-01-01 00:00:00.500` gives `-500` where the CLR gives `500`. A pre-existing defect on the line `E-4` already edits. The user chose the version-safe `((x % 1000) + 1000) % 1000` over ClickHouse's `toMillisecond`, which answers it in one call (measured: `500`) but needs 24.6, with a two-line note recording that for a later modernization. `TO-11` added. (ii) `E-5` coerces at `max(operand precision, 7)` rather than a flat 7, which removes `D-1` failure-mode (b) and (c) entirely: an operand that is already `DateTime64(8|9)` now keeps every digit, so the lowering is behaviour-preserving for all already-`DateTime64` columns instead of merely tick-exact. (iii) `E-5` builds its result `DbDataType` from the system type alone — inheriting the operand's meant a column with an explicit `DbType` would carry a type name the SQL builder renders in preference to the `DataType` set beside it. (iv) Test-only: three obligations spanned **2026-03-08**, a daylight-saving transition, so their exact expectations would have been an hour out on any server in an observing zone and green only here; moved to a transition-free June window with a fixture-local shift origin. Also added the missing `Date` / `Date32` coverage for `E-3`/`E-4`, made the seeders dispose their table if the insert throws, and trimmed `E-5`'s remark to the repo's comment limit.

## P12 Critic verdict (M/L)

**weak** — `plan-critic` on `fable`, against the worktree. The chosen design (`D-1`'s unconditional coercion) was
upheld as correct and as surviving every operand kind the critic could construct; the objections were all against
the plan's *record* and its *coverage*, and every checkable one was then verified. What changed:

1. **`P1` understated the failing class** — the critic found three translator-manufactured operand kinds (`now()`, `toDate32(col)` from `.Date`, `makeDateTime(...)`) that are typed `DateTime64(7)` inside linq2db while the server makes them `DateTime`/`Date32`, so the bug fires on the **default mapping** with no user declaration at all. Verified by `toTypeName` plus the raw call for each. `P1` rewritten around this; `D-1`'s "why this" now rests on it rather than on `U-1` alone (the critic's point: `U-1` is slated for a separate fix, so a reason resting only on it would evaporate); `P7` gained an operand-kinds row; TO-8 and TO-9 added as default-mapping red→green obligations.
2. **`U-4` / `D-1`'s cast rejection was wrong** — `SqlExpressionOptimizerVisitor.cs:1352` strips only `!element.IsMandatory`, and `Factory.Cast(…, isMandatory: true)` exists (`SqlExpressionFactoryExtensions.cs:122`), so the mandatory-cast alternative works. Verified. The rejection is re-grounded on house style, not correctness.
3. **TO-4 could not discriminate `D-3`** — `U-2` says nothing casts the bare projection, so the 226 ms survives either way and `D-3` was unguarded. TO-10 added with the critic's discriminating shape, and written so that a non-discriminating result drops `D-3` rather than shipping it.
4. **`D-1`'s failure mode omitted the `DateTime64(8|9)` write-back loss** — added as (c). The critic's proposed remedy (precision 9 at the `*64Nano` sites) was probed and **rejected**: `U-8` measured `Code: 407 … convert overflow` at 2290, so 9 would turn a silent wrap into a hard error inside a range that works today.
5. **`U-5` was documentation-backed and half wrong** — the critic's reading of ClickHouse's interval adders was right. Measured: `addNanoseconds cannot be used with Date32` / `with Date`, while `DateTime` works and returns `DateTime64(9)`. `LowerTemporalArithmetic` therefore joins `P6` as `E-2`, and TO-7 now runs both pairs with the two halves carrying different proof modes. Without this the fix would have left `Date32` shifts broken while `SC-3` claimed the class was covered.
6. **TO-5's value assertion is unfailable** — accepted and stated in the row rather than dressed up.
7. **`E-5` and `D-3` under-specified their result types** — both now name them (`DateTime64` with precision 7 for the wrapper, 9 for the `fromUnixTimestamp64Nano` node).

Not adopted: the critic's suggestion to raise the `*64Nano` wrap precision to 9 — disproved by `U-8`'s probe,
recorded above.
