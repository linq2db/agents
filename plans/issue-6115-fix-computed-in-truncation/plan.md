# Work plan: issue-6115-fix-computed-in-truncation — ClickHouse: keep a computed IN operand's server precision

**Tier:** S  ·  **Status:** draft  ·  **Approved-at:** 2026-10-23 (user: "yes" to the follow-up PR)  ·  **Branch:** issue/6115-fix-computed-in-truncation
**Schema:** `.claude/docs/work-plan.md`  ·  **Gates:** `.claude/docs/definition-of-done.md`

## P1 Problem

Regression from [#6116](https://github.com/linq2db/linq2db/pull/6116) (merged `a1fee89c5`, unreleased 6.5.1). `VisitInListPredicate` widens the operand with `AsDateTime64(..., keepPrecision: true)`, which keeps the *reported* precision of any operand. A value computed from a `DateTime64(3)` column reports the column's type (`ClickHouseMemberTranslator.cs:112,127` copy the operand type) while ClickHouse answers `fromUnixTimestamp64Nano(…)` as `DateTime64(9)`, so the cast truncates it. Measured (ClickHouse.Driver, `MillisecondRow` storing `.100`): `new[] { stored }.Contains(r.At.AddMilliseconds(0.4))` and the captured-array form count 1 on `a1fee89c5` (SQL `toDateTime64(fromUnixTimestamp64Nano(…), 3) IN (…)`); CLR, `==` and pre-#6116 code count 0. Plan of origin: `issue-6115-fix-clickhouse-timeofday` U-6.

## P2 Success criteria

- SC-1 A computed operand beside a `DateTime64(3)` column is compared at its server precision: both list forms count 0 against the stored value and 1 against the shifted value.  → G-01
- SC-2 A stored `DateTime64(3)` column still compares at 3 (`FinerValueBesideAMillisecondColumnMatchesInEveryForm`) and no other ClickHouse test regresses.  → G-01

## P6 Edit-points

- E-1 `Source/LinqToDB/Internal/DataProvider/ClickHouse/ClickHouseSqlExpressionConvertVisitor.cs:VisitInListPredicate` — `keepPrecision: QueryHelper.IsStoredColumn(inList.Expr1)`.
- E-2 `Source/LinqToDB/Internal/DataProvider/ClickHouse/ClickHouseExpressionExtensions.cs:AsDateTime64` — correct the result-type comment: a cast renders by `DataType` (the ClickHouse `BuildTypedExpression` override, lines 567-589), so the carried-over `DbType` is not "rendered in preference".
- E-3 `Tests/Linq/Linq/IntervalTranslationTests.ClickHouse.cs` — new `ComputedValueBesideAMillisecondColumnKeepsItsPrecisionInAList`, direct and LinqService.

## P9 Verification gates

- G-01: pass — `worktree-test.ps1` net10.0, worktree `6115-probe`. Red: `ComputedValueBesideAMillisecondColumnKeepsItsPrecisionInAList` with `keepPrecision: true` fails `should be 0 but was 1` at the first list assertion, ClickHouse.Driver direct and LinqService. Green with E-1: `IntervalTranslationTests|ContainsTests|DateTimeFunctionsTests|DateOnlyFunctionTests|TypesTests.DateTime*` `-PerProvider` — ClickHouse.Octonica, ClickHouse.Driver, ClickHouse.MySql each 719 total / 683 passed / 0 failed / 36 skipped. `test-diff-sweep.ps1 -IncludeWorkingTree`: 0 chains; 1 narrowed set (`:249`, ClickHouse-only translator test with a leading doc comment).
- G-02: skipped — no local `BaselinesPath` in the worktree; unverified until `baselines/pr_6122` (PR [#6122](https://github.com/linq2db/linq2db/pull/6122), commit `1d2d8b678`) is read. Expected: the new test's baselines plus computed IN operands over a `DateTime64(<7)` column moving from `toDateTime64(…, p)` to `toDateTime64(…, 7)`.
- G-05: pass — `dotnet build Source/LinqToDB/LinqToDB.csproj -c Release -f net10.0` and `-f netstandard2.0`: exit 0, 0 warnings, 0 errors. Test change adds no `cref`.
- G-06: pass — `git diff --stat`: 3 files, +35/−2, only E-1–E-3.
- G-07: pass — nothing under `Tests/Tests.Playground/`.
- G-08: n/a — ClickHouse provider internals only; no SQL AST, `IDataProvider` or translator-interface change.
