# Work plan: issue-6115-fix-clickhouse-timeofday — ClickHouse: coerce every epoch-function operand to DateTime64

**Tier:** M  ·  **Status:** draft  ·  **Approved-at:** —  ·  **Branch:** issue/6115-fix-clickhouse-timeofday
**Schema:** `.claude/docs/work-plan.md`  ·  **Gates:** `.claude/docs/definition-of-done.md`

## P1 Problem

[#6115](https://github.com/linq2db/linq2db/issues/6115), regression from [#5959](https://github.com/linq2db/linq2db/pull/5959), milestone 6.5.1. A `DateTime` property mapped with a bare `[Column]` over a server column of type `DateTime` (table created by raw SQL `CREATE TABLE TimeOfDayRepro (Id Int32, Dt DateTime) ENGINE = Memory`): `db.GetTable<T>().Select(x => x.Dt.TimeOfDay).ToArray()`. On master d23c509ea it renders `toInt64((toUnixTimestamp64Nano(x.Dt) - toUnixTimestamp64Nano(toDateTime64(toDate32(x.Dt), 7))) / 100)` and fails `Code: 43 ... toUnixTimestamp64Nano ... Expected: DateTime64, got: DateTime` on ClickHouse.Driver, Octonica and MySql (measured, this branch, red run). v6.5.0 renders `toUnixTimestamp64Nano(toDateTime64(x.Dt, 7))` and passes on Driver and MySql (measured by the release-prep session). Mechanism: `SqlField.Type` is `column.GetDbDataType(true)` (`Source/LinqToDB/Internal/SqlQuery/SqlField.cs:65`), completed from the mapping schema for an undeclared `DataType` (`Source/LinqToDB/Mapping/ColumnDescriptor.cs:500-509`), and for an attribute-less member `ColumnDescriptor.DataType` itself is the schema default (`ColumnDescriptor.cs:59`) — `DateTime64` for a CLR `DateTime` on ClickHouse. Translations copy the operand's type too: `addHours` & co. are typed `dateType` (`Translation/ClickHouseMemberTranslator.cs:112,141`) while the server answers `DateTime` (measured: `toTypeName(addDays(toDateTime(...), 1))` = `DateTime`). `AsDateTime64` passed any operand reporting `DateTime64` through unwrapped.

## P2 Success criteria

- SC-1 Over a bare-`[Column]` `DateTime` property on a server `DateTime` table, `.TimeOfDay` answers the CLR value instead of Code 43 (the regression). → TO-1
- SC-2 Same table: `.AddHours(1).TimeOfDay`, a `TimeSpan` difference, `Sql.DatePart(Millisecond)`, `AddMilliseconds` answer the CLR values (pre-existing in 6.5.0 except `.AddHours(1).TimeOfDay`). → TO-1
- SC-3 Same table: `values.Contains(column)` answers without Code 53 (measured HTTP probe: `DateTime IN (toDateTime64(...))` → Code 53). → TO-1
- SC-4 An attribute-less POCO `DateTime` member over the same table answers `.TimeOfDay`. → TO-1
- SC-5 No other ClickHouse test regresses. → TO-3

## P3 Constraints & anti-goals (M/L)

- No change outside `Source/LinqToDB/Internal/DataProvider/ClickHouse/`; no public API change; no change to `QueryHelper` or the mapping-schema default.
- No other provider's SQL changes.
- ClickHouse baselines regain `toDateTime64(x, p)` around epoch-function / interval / IN operands — accepted (P10).

## P4 Unknowns (M/L)

- U-1 Can a declared DateTime64 column be told apart from the schema default? — resolved-by scout (critic): no — `ColumnDescriptor.cs:59,63-67` give an attribute-less member and `[Column(DataType = DataType.DateTime64)]` the same descriptor; only an attribute lookup could, rejected for the hotfix (D-1).
- U-2 Will the optimizer drop a cast to the operand's own type? — resolved-by scout: `AsDateTime64` passes `isMandatory: true` to `factory.Cast` (`SqlExpressionFactoryExtensions.cs:122`), as `AsDate32` already does.
- U-3 Precision: the schema default stores 7 in `Scale`, not `Precision` (`ClickHouseMappingSchema.cs:33`, critic); the builder renders `Precision ?? 7` (`ClickHouseSqlBuilder.cs:584`). `AsDateTime64` keeps a declared `Precision` above 7 and uses 7 otherwise — resolved-by scout.
- U-5 Does `toDateTime64(col, 7) IN (...)` lose primary-key analysis on a MergeTree keyed on a DateTime64 column? — resolved-by probe (26.5.7, 1 M rows, `ORDER BY dt`, `EXPLAIN indexes = 1`): bare and wrapped both `Granules: 2/977`, condition `toDateTime64(dt, 7) in 2-element set` uses key `dt`.
- U-4 IN-list Code 53 — 6.5.0 status not measured; fixed here by user decision (2026-10-23), release note must not call it a regression — resolved-by user answer.

## P5 Decisions (M/L; rejected alternatives mandatory at L)

### D-1 — Coerce unconditionally

- **chosen:** `AsDateTime64` always casts to `DateTime64(max(declared precision, 7))`, mandatory cast; `VisitInListPredicate` widens a `DateTime64` operand too. `IsDateTime64` is removed. User choice "A" (2026-10-23).
- **rejected:** trust a declared `DateTime64` (first draft) — refuted by the critic: the attribute-less POCO and translator-copied types report the same `DateTime64`, so Code 43 stays.
- **rejected:** read `ColumnAttribute` / `DataTypeAttribute` and coerce precision-less `DateTime64` — more code and risk on release day; follow-up.
- **why this:** the server type of anything but an attribute-declared column is unknowable from the AST; `toDateTime64(x, p)` is exact for any operand of precision ≤ p.
- **failure mode of the choice:** a declared `DateTime64` column in `IN` or the epoch functions is wrapped, and literals/parameters can be double-wrapped (`toDateTime64(toDateTime64('…', 7), 7)`) — baseline churn, no value change; index analysis measured unaffected (U-5).

## P6 Edit-points

- E-1 `Source/LinqToDB/Internal/DataProvider/ClickHouse/ClickHouseExpressionExtensions.cs:AsDateTime64` — unconditional mandatory cast; `IsDateTime64` removed.
- E-2 `Source/LinqToDB/Internal/DataProvider/ClickHouse/ClickHouseSqlExpressionConvertVisitor.cs:VisitInListPredicate` — drop the `IsDateTime64` exclusion; `ElapsedTicks` remark updated.
- E-3 `Tests/Linq/Linq/IntervalTranslationTests.ClickHouse.cs` — new `UndeclaredColumnOverServerDateTimeIsCoerced` (one case per shape); `TheCoercionIsEmittedOnlyWhereTheOperandNeedsIt` renamed `TheCoercionIsEmittedWhateverTheOperandReports` and pins the wrap over `EventRow`; `[ActiveIssue(6044)]` removed from `ExtensionAnalyticFunctionOverASecondPrecisionColumnIsCoerced` (measured: passes on all three providers after E-1; #6044 stays open — its general typing gap is not fixed).

## P7 Impact map (M/L)

- `ClickHouseMemberTranslator.cs:89` (`toISOWeek`), `:96` (`ToUnixTimestamp64Milli`), `:130`, `:210-211` (`ToUnixTimestamp64Nano`) — searched `AsDateTime64|IsDateTime64|ToUnixTimestamp64(Nano|Milli)\(` across `Source/` (8 of 8, critic concurs) — covered by E-1
- `ClickHouseSqlExpressionConvertVisitor.cs:64-65` (difference), `:91` (`LowerTemporalArithmetic`) — covered by E-1
- `ClickHouseSqlExpressionConvertVisitor.cs:114` — `IsDateTime64` caller — covered by E-2
- `ClickHouseMemberTranslator.cs:112,127,141,180` — DateTime64-typed nodes copied from the operand (critic search `DateTime64` across `ClickHouse/`) — covered by E-1 (their consumers now coerce)
- `IntervalTranslationTests.ClickHouse.cs:35-37` — pinned the absence of `toDateTime64` over undeclared `EventRow` — covered by E-3
- `DateTimeFunctionsTests.cs:1157-1191` — `DbType = "DateTime"` guard; still coerced — out-of-scope
- ClickHouse baselines under `../linq2db.baselines` — move back to the wrapped form — out-of-scope (P10)
- `git grep -n "ActiveIssue(6115" -- Tests` — no hits — out-of-scope

## P8 Test obligations (M/L)

- TO-1 `UndeclaredColumnOverServerDateTimeIsCoerced`, one case per `UndeclaredOperandShape` (TimeOfDay, ShiftedTimeOfDay, Difference, MillisecondPart, MillisecondShift, Contains, UnattributedTimeOfDay): raw-SQL `DateTime` table, precondition asserts the schema default is DateTime64; expected values from P1 (10:00, 11:00, 36 000 000 ms, 0, 10:00:00.5, 1, 10:00). Direct contexts only (`IncludeDataSources(false, …)`): raw `Execute` needs a `DataConnection`; remote is covered only by TO-3's LinqService siblings. Measured red on unfixed code, the 7 original shapes × 3 providers: Code 43 (6 shapes), Code 53 (Contains). Shift shape `ShiftByClientDifference` (`r.At + (later - earlier)`, reaches `LowerTemporalArithmetic`) added after round 2: measured **green on unfixed code** (Driver: `r.At + toIntervalNanosecond(toInt64(500000000))`, ClickHouse promotes) and green after — a control for the unchanged-answer path, not red→green. A captured `TimeSpan` local instead renders `r.At + INTERVAL 0 SECOND` (sub-second truncated, `ClickHouseMappingSchema.cs:787-802`) on unfixed and fixed code alike — a separate defect, not this branch — providers: ClickHouse.Driver, ClickHouse.Octonica, ClickHouse.MySql — proof: red→green
- TO-2 `TheCoercionIsEmittedWhateverTheOperandReports` — `toUnixTimestamp64Nano(toDateTime64(r.FinishedOn, 7))` over undeclared `EventRow`, `now()` / `makeDateTime` / declared `DataType.DateTime` still wrapped (these no longer pin `DateTimeType`: the wrap is unconditional) — measured red on unfixed code (assertion) on all three — providers: ClickHouse.Driver, ClickHouse.Octonica, ClickHouse.MySql — proof: red→green
- TO-3 `IntervalTranslationTests`, `DateTimeFunctionsTests`, `ContainsTests`, `DateOnlyFunctionTests` on the three ClickHouse providers incl. LinqService — providers: ClickHouse.Driver, ClickHouse.Octonica, ClickHouse.MySql — proof: characterization

## P9 Verification gates

- G-01: pass — `worktree-test.ps1 -PerProvider` on ClickHouse.Driver/Octonica/MySql: red on unfixed code (7 shapes Code 43/53, TO-2 assertion), green after; `IntervalTranslationTests` 211 passed / 0 failed / 2 skipped per provider; `IntervalTranslationTests|DateTimeFunctionsTests|ContainsTests|DateOnlyFunctionTests` 662 passed / 0 failed / 36 skipped per provider (before the shift shape and the `DateTimeType` remark were added).
- G-02: skipped — `BaselinesPath` diff not taken locally; ClickHouse baselines will move to the wrapped form (P10); unverified until the CI baselines PR is read.
- G-05: pass — `dotnet build Source/LinqToDB/LinqToDB.csproj -c Release -f netstandard2.0`: 0 warnings, 0 errors. `dotnet build Tests/Linq/Tests.csproj -c Release -f net10.0`: 4 `MA0008` in untouched `ConcatUnionTests.cs` / `SelectTests.cs` (known local analyzer divergence), none in branch files.
- G-06: pass — `git diff --stat`: 3 files, only P6 edit-points.
- G-07: pass — no `Tests/Tests.Playground/` change.
- G-09: skipped — no adversarial diff read yet; the critic attacked the plan, not the diff.

## P10 Adjudicated (M/L)

- ClickHouse SQL baselines regain `toDateTime64(x, p)` around epoch-function, interval and IN operands, including over declared `DateTime64` columns — the server type of an undeclared operand cannot be known (U-1); precise skipping is a follow-up issue.

## P11 Amendments (M/L)

_None._

## P12 Critic verdict (M/L)

- Round 1 (fable): **refuted** — the "declared" signal does not exist for attribute-less members (`ColumnDescriptor.cs:59`); translator-copied types (`ClickHouseMemberTranslator.cs:112,141`) bypass a column-based check; U-2 rested on Precision where the default sets Scale; SC-1 bundled pre-existing arms; TO-1 proved only its first arm red. Searched: `AsDateTime64|IsDateTime64|ToUnixTimestamp64`, `DateTime64` across `ClickHouse/`, `new ColumnDescriptor\(`, `public DbDataType\(`, v6.5.0 `toDateTime64` sites, `DbType = "DateTime` in tests. Measured afterwards: `addDays(DateTime)` → `DateTime`. Revision: user chose unconditional coercion (D-1) and in-PR IN fix; TO-1 split per shape; SC split regression vs pre-existing.
- Round 2 (fable): **weak** — (1) `[ActiveIssue(6044)]` at `IntervalTranslationTests.ClickHouse.cs:294` flips red under E-1: confirmed by the green run (passes on all three providers, gate fails it), gate removed in E-3, #6044 stays open; (2) `LowerTemporalArithmetic` (`ClickHouseSqlExpressionConvertVisitor.cs:91`) has no TO-1 shape — a client-difference shift shape added and classified by run (TO-1); (3) IN index cost unmeasured — measured, U-5; (4) `DateTimeType` remark stale — rewritten; TO-2's now()/makeDateTime asserts no longer pin `DateTimeType` (noted in P8); (5) per-shape red recorded in P8. Searched: `IsMandatory` across `Source/` (`SqlExpressionOptimizerVisitor.cs:1352`), precision/range/nullable/DateTimeOffset, DateOnly guard, `ActiveIssue` messages across `Tests/`, baselines `IN (toDateTime64(` (6 files).
