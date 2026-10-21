# Recorded dead-ends

Approaches tried on this codebase and abandoned — a disproven hypothesis, a reverted fix, a binding / tool / dialect path that does not fit. Read the entries for your area before reproducing or designing a fix ([`agent-rules.md`](agent-rules.md) → *Investigating & fixing bugs*); `/session-reflect` appends new ones.

Entry shape: `## <AREA>: <one-line subject>` (area codes per [`kb-areas.md`](kb-areas.md) — `Grep` it, don't `Read` it), then **Tried:** / **Failed because:** / **Don't re-attempt:**, and the issue / PR it came from. An entry is a codebase fact, so it belongs here rather than in per-user auto-memory, which no other contributor or agent can read. Delete an entry when the constraint it records goes away (a driver fix, an engine change), naming the change in the commit.

## EXPR-TRANS: one descriptor decision in `SuggestColumnDescriptor` for both literals and parameters

**Tried:** fixing a SQL Server regression — `MAX(datetimeCol) = @v` binding `@v` as `datetime2`, so a value read back from the column (`.003`) stopped matching — by removing the guard that withholds a coarse date/time descriptor reached through a computed value (MIN/MAX, COALESCE, value window functions).

**Failed because:** `VisitBinary` installs `SuggestColumnDescriptor(left, right)` as the ambient descriptor for visiting *both* sides, and `BuildConstant` and `BuildParameter` both read it. Without the guard, static literals beside a coarse aggregate were narrowed again (`Date(MAX(Day)) < Date('2026-06-01')`, 23 cases red across SQLite, SQL Server and ClickHouse); with it, parameters lost the column type. A literal wants its own precision, a parameter carrying a read-back value wants the column's type.

**Don't re-attempt:** a single lend/withhold decision for the comparison. Split it per consumer — the descriptor is lent to parameters and withheld from constants (`SuggestedDescriptor.ForConstants`, read through `ConstantDescriptor` in `HandleValue`). (#5959, `ed87cd5e9`)

## EXPR-TRANS: a builder-only fix for judging an outer reference's nullability where the outer join is

**Tried:** making an eager-loaded detail projection read the parent's missed-row column as `default(T)`, as the rest of #5983's missed-row rule does. The calculation is `(j.Value1 + 1) * 10` inside `Kids = t.Where(…).Select(k => …)` over `from j in t.LeftJoin(...)`. First, walking the operand's `IBuildContext.Parent` chain to collect enclosing queries for the `NullabilityContext`. Then setting an outer query (the cloned parent's `SelectQuery`) on the Default eager-load visitor in `ExpressionBuilder.EagerLoadDefault.cs`, and applying it to every read-as-default decision.

**Failed because:** the operand's frame is `j`'s own inner query, which outer-joins nothing, and the `Parent` chain (`SubQueryContext` → `DefaultIfEmptyContext` → wrapper `SubQueryContext`) ends before the query holding the `LEFT JOIN`. With the outer query supplied, shapes that read only the parent row got `Coalesce([m_1].[Value1], 0)`. A shape that also reads a detail column (`k.Value1 + j.Value1`) was decided at build (`MakeColumn` saw the `COALESCE`) and still emitted without it. The likely cause, reasoned rather than instrumented: the SQL optimizer drops a `COALESCE` whose argument reads as not nullable from the detail query's frame, and only parent-only expressions get moved up into the frame that can see the join. A `COALESCE` over a CTE field fed by an outer-joined column is lost the same way (`CalculationOverCteColumnOfMissedLeftJoinReadsDefault`).

**Don't re-attempt:** a builder-side frame fix alone. Correlated outer references and CTE fields need `NullabilityContext` itself to judge them in the frame that holds their outer join, or the optimizer undoes the builder's decision. Measure the mixed-column shape, not only the parent-only one. (#5983, igor-tkachev's MIN008 / MIN009; tests gated `[ActiveIssue(5983)]` in `7e24e0528`)

## SQL-PROVIDER: an IN-list value keeping its own type beside any computed column value

**Tried:** widening `BasicSqlBuilder.GetInListValueType` so a captured IN-list value keeps its own type beside any computed operand (MIN/MAX, COALESCE, value window functions, a CASE) that reaches a column without a value converter, not only a coarse date/time one. The aim was `[1.004m].Contains(MAX(Decimal64(18,2)))` writing `1.004` rather than `1.00` on ClickHouse.

**Failed because:** a column type can name how a value is stored, not just its width. `listText.Contains(r.ValueText.GetValueOrDefault())` over a Guid mapped `DataType.Text` / `DbType = "TEXT"` is a CASE over the column, so the Guid was written as a blob and matched nothing on every SQLite config (`SQLiteTests.Issue4808Test`, GitHub run 39044449090).

**Don't re-attempt:** a computed-vs-stored test alone. The value keeps its own type only where the two types differ in precision: a coarser date/time column, or decimal beside decimal with no converter. Every other column type still lends itself. (#5959, `d2da94700` narrowed by `76fc77952`)

## SQL-PROVIDER: typing a decimal literal beside a computed decimal from the schema default or a fixed cap

**Tried:** three ways to type a literal / IN-list value / set-operation branch beside a computed decimal (`MAX`, `Math.Abs`, a conditional) so `MAX(Decimal(18,2)) == 1.004m` keeps the `.004`: (a) the mapping schema's default decimal type; (b) widening, then clamping integer-first at the cap (`YdbMappingSchema.GetCommonDecimalType`'s rule); (c) `SqlDataType.GetMaxPrecision(DataType.Decimal)` as the cap.

**Failed because:** (a) the default (`Decimal128(29,10)` on ClickHouse, `(22,9)` on YDB, `(18,10)` on most) is narrower than many operands in scale or integer digits — measured against master: ClickHouse `Decimal128(38,12)` `Abs(x) == lit` 1 → 0, YDB `Decimal(35,2)` `IN` → `OverflowException` and `UNION` → `YdbException`, and set operations truncated on DB2, SqlCe and DuckDB. (b) An integer-first clamp narrows the literal back to the column scale, the defect it was meant to fix; that rule is for two column operands of unknown magnitude, while a literal's digits are known. (c) `GetMaxPrecision(Decimal)` is 29, the CLR decimal's width (`SqlDataType.cs:157`), not any provider's limit.

**Don't re-attempt:** any of the three. `QueryHelper.GetDecimalTypeForValue` keeps the operand's type when the value fits, otherwise takes both sides' integer digits and scale; ClickHouse moves up a family by total digits (a comparison stays in the operand's family and overflows it); the cap is 31, DB2's limit and the smallest among providers that render a literal's precision (Informix 32, YDB 35; Access drops decimal casts; SQL Server / Sybase / Firebird re-derive facets from the value); past it the value keeps its own facets. (#5959 A-12, `55204bb7f`; four critic rounds, each confirmed by a probe)

## SQL-PROVIDER: witnessing the cast-of-cast fold with an integer or integral-constant comparison

**Tried:** pinning that `SqlExpressionOptimizerVisitor.VisitSqlCastExpression` keeps `CAST(CAST(x AS Int) AS Double)` (an `int` result widened back to `double`) with `where Sql.Degrees((int)r.M) == 57`, then `== 57.0`, on the providers that emulate `Degrees` inside that pair.

**Failed because:** `== 57` compares in `int`, so the truncating cast stands alone and no pair reaches the fold: green with the guard reverted, as on master. `== 57.0` never reaches SQL as a widening: the build layer's comparison simplifier (`RestoreCompare`'s constant arm, #6070) rewrites an integral `double` constant into an `int` comparison and drops the cast, so it was red with the guard as well.

**Don't re-attempt:** a comparison shape. Project the value, then filter with a non-integral bound (`from d in … select Sql.Degrees((int)r.M)!.Value where d < 57.1 select d`), and prove it red under "revert the guard" before adding it. (#5943, `9f0c4fb08`)

## SQL-AST: an end-to-end test telling per-boundary from outermost-only column-subquery scope apart in `SqlQueryValidatorVisitor`

**Tried:** a nested column-subquery control for the Oracle 11 parent-`IS NOT NULL` check, where the inner subquery's `IS NOT NULL` references the *middle* subquery's table, run with the scope reset mutated to fire only at the outermost boundary (`if (isColumnSubqueryEntry && _currentSources == null)`). Four middle shapes: uncorrelated `OrderBy(...).Select(...).FirstOrDefault()`, uncorrelated one-row `Where(...).FirstOrDefault()`, root-correlated `OrderBy` + `FirstOrDefault`, and an uncorrelated `Sum` over the inner `Count`. A root-correlated `Sum` middle hits `Error_OUTER_Joins` first.

**Failed because:** every shape still threw `Error_ColumnSubqueryShouldNotContainParentIsNotNull` under the mutation (rebuild confirmed by DLL timestamp). On Oracle 11 the `Take` shapes are rewritten into `LEFT JOIN … ROW_NUMBER()` derived tables, so no nested column-subquery boundary survives to the validator; the aggregate shape behaved the same.

**Don't re-attempt:** hunting for a LINQ shape. If the per-boundary reset needs a guard, test the visitor directly on a hand-built AST. (#6027)

## SQL-AST: forcing a Transform-mode rebuild of a typed `SqlBinaryExpression` with an `x + 0` child

**Tried:** a `Decimal(10,2)`-typed `A + (B + 0)` emitted from a `Sql.Extension` builder, expecting the remoting pass (`PrepareStatementForRemoting`, Transform-mode visitors) to reduce `B + 0` and rebuild the sum with `element.SystemType` (`QueryElementVisitor.cs:3060`), dropping its `DbDataType`.

**Failed because:** the build-time `Finalize` already runs `SelectQueryOptimizerVisitor`'s expression optimizer in **Modify** mode (`SelectQueryOptimizerVisitor.cs:43,223`), which reduces `B + 0` in place before any Transform pass sees it, so the rebuild is never reached and the probe is the plain-sum case again.

**Don't re-attempt:** an optimizer-foldable child. Use a child only the *convert* visitor replaces — a `SqlCoalesceExpression`, turned into a `Coalesce` function — which does reach the rebuild; it showed the type loss on the direct path as well (#6056). (#6055)

## PROV-FIREBIRD: binary Guid *parameter* writes on a UTF8 Firebird 6 database

**Tried:** binding a binary Guid to a `CHAR(16) CHARACTER SET OCTETS` / `BINARY(16)` column (INSERT VALUES, UPDATE SET, WHERE compare) as raw `byte[]`; as native `FbDbType.Guid`; with `FbParameter.Charset` set to `Octets` (and, by reflection, every other charset value) or `FbDbType.Binary`; with explicit `CHAR(16) CHARACTER SET OCTETS` DDL instead of `BINARY(16)`; with an explicit OCTETS CAST target.

**Failed because:** every binary binding fails identically with "Malformed string" (isc 335544849) inside `FirebirdSql.Data.Client` — the client validates the OCTETS parameter bytes against the connection charset, below linq2db. It is encoding-driven, not version-driven: a UTF8-charset FB3/4/5 database fails the same way. Tell: an all-zero UUID parameter succeeds, a non-zero one fails.

**Don't re-attempt:** any linq2db-level parameter / DDL / charset permutation. What works is sending no binary parameter at all: rebind the Guid as its canonical `VARCHAR(36)` text and wrap it in `CHAR_TO_UUID(@p)` server-side (#5485). Keep that wrap octets-only — a Guid mapped to a text column must stay untouched. (#5483)

## PROV-FIREBIRD: an unzoned `DateTimeOffset` literal shifting with the session time zone

**Tried:** suspecting that Firebird 4+, which creates a `DateTimeOffset` column as `TIMESTAMP WITH TIME ZONE` but writes a `DateTimeOffset` literal without a zone (`TIMESTAMP '0001-01-01 00:00:00.0000'`, its zone-aware converter being commented out), moves an injected `0001-01-01` below year 1 in a session east of UTC, as MySQL 8's offset literal did in a session west of it.

**Failed because:** Firebird converts the unzoned literal in the session's zone and the value *keeps* that zone; `EXTRACT` reads in the value's own zone, so `EXTRACT(YEAR FROM COALESCE(col, TIMESTAMP '0001-01-01 …'))` is 1 at `+00:00`, `+05:00` and `-05:00`, with no range error. Measured on Firebird 4 and 5, both `PreferClientCalculation` arms.

**Don't re-attempt:** a Firebird `ConvertDefaultValue` override to add `+00:00`. `PreferClientCalculationTests.OffsetDefaultIsReadIndependentlyOfFirebirdSessionTimeZone` pins the behaviour. (#5983 round 4)

## REMOTE: "Signal/R's default JSON protocol escapes non-ASCII as `\uXXXX`"

**Tried:** a review finding that the Signal/R client's request-size check over-rejects because it measures with a default `JsonHubProtocol`, assumed to write every non-ASCII character as a 6-byte escape, while a client with a relaxed encoder writes UTF-8. Probed with a `LinqToDBSignalRConnection` configured via `AddJsonProtocol(o => o.PayloadSerializerOptions.Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping)` sending 10 000 Cyrillic characters under a 32 KB limit.

**Failed because:** the request was sent with or without the relaxed encoder — the default `JsonHubProtocol` frame is UTF-8-sized for such text. The PR's own `NonAsciiRequestUnderTheLimitIsSent` (6000 × `é` under 32 KB) shows the same.

**Don't re-attempt:** an over-rejection finding built on default-encoder escaping. The JSON-vs-MessagePack gap that remains is only `"`, `\` and control characters (2–6 bytes in JSON, 1 in MessagePack) — a narrow window, unprobed because the test projects reference no MessagePack protocol. (#6014)

## BUILD: regenerating `CompatibilitySuppressions.xml` for a field→property change

**Tried:** turning a **shipped** public static field into a property of the same name and type (`Configuration.OptimizeForSequentialAccess`), then regenerating suppressions with `dotnet pack -p:ApiCompatGenerateSuppressionFile=true`, expecting a new suppression for the removed field.

**Failed because:** the regeneration produced zero changes — ApiCompat as configured in this repo does not report field→property as a breaking removal. The PublicAPI analyzer files (`*REMOVED*` + the new accessors) are the only artifact that changes.

**Don't re-attempt:** a slow Release pack to "fix" suppressions for this shape, or a blocking review finding claiming "ApiCompat will fail" without running the tool. (#5639)

## BUILD: guarding an Azure test job with a matrix variable in its job-level `condition:`

**Tried:** adding `ne(variables['title'], '')` to the **job-level** `condition` of `test_windows_job` / `test_ubuntu_job`, so an OS whose matrix selects no leg is skipped instead of reporting a green job that ran nothing.

**Failed because:** a matrix variable is **empty when a job-level condition is evaluated** — it resolves at step level only. Build 23453 finished green in 53 min with no `Win` or `Lin` job record at all, including the populated matrix: every `test-all` would become a green run that executes nothing — the failure the guard was meant to prevent.

**Don't re-attempt:** any `variables[...]` matrix reference in a job-level `condition:`. Guard with a **step** whose `condition: and(eq(variables.title, ''), succeeded())` names the state in the timeline (the `test-workflow-*.yml` templates already use that form). More generally, an Azure expression is proven only in a position it already runs in, and a change whose failure mode is a silent green must not merge on reasoning. (#5880, reverted in `4043579ee`)

## BUILD: the intermittent `CS2012` file lock in the GitHub Actions build

**Tried:** `-p:UseSharedCompilation=false` on the solution build (no compiler server, so nothing should hold the DLL), and `--no-build` on the *Pack* step (one less compile to race).

**Failed because:** the cause is one project + TFM **compiled twice concurrently** into the same obj path in one `dotnet build linq2db.slnx`, not a long-lived handle. Without the server the lock holder just moved `VBCSCompiler` → `csc` and the file moved to `.build/obj/LinqToDB/Release/net8.0/linq2db.dll`. And `--no-build` breaks pack outright: `Source/LinqToDB.CLI` packs a .NET tool from per-RID publishes a plain build never produces (`MSB3030 … osx-x64\dotnet-linq2db.runtimeconfig.json`).

**Don't re-attempt:** either flag, or `-m:1`. What works is pre-building the contended projects so the solution build finds them current — `build.yml` → *Build hot-spot projects*; a project that starts failing later gets added there. It is intermittent: `gh run rerun <id> --failed` with no change tells a flake from a real failure, and a candidate fix has to be judged over several runs. (#5858, upstream dotnet/roslyn#77538)

## DATA: reproducing an ADO connection-pool leak in a test

**Tried:** looping past Max Pool Size with a `using var ctx` per iteration; looping with one shared context.

**Failed because:** both are false passes. Disposal returns the connection every iteration, and a single shared context holds a single physical connection — neither can exhaust the pool.

**Don't re-attempt:** those shapes. Create the leaking contexts **without disposing** them and keep them alive (e.g. in a `List`) so finalization can't return the connections, then loop past Max Pool Size (default 100). Expect the stress run to OOM-kill a DB container (`sql2022` exited 137); restart it between the red run and the fix-verify run. (#5364)

## EXPR-TRANS: `[EagerEvaluation]` to desugar an overload whose arguments carry `Sql.*` calls

**Tried:** marking the `Pivot` / `Unpivot` / `SelectDynamic` convenience overloads `[EagerEvaluation]` so the exposer runs them when they are written inline in a sub-query over a query-chain source.

**Failed because:** the attribute evaluates the call only when `IsCompilable` holds, and `CanBeEvaluatedOnClientCheckVisitorBase.VisitMethodCall` rejects any server-side-only method, including one inside a quoted lambda argument. A `SelectDynamic` template `(x, n) => Sql.Property<decimal>(x, n)` made every inline call throw *"requires client-side evaluation but its arguments are not compilable"*. A correlated source is not compilable either, so it gets the same error.

**Don't re-attempt:** `[EagerEvaluation]` for an overload whose lambdas may contain `Sql.*` calls. Desugar in a builder instead, running the public method over `ExpressionQueryImpl.CreateQuery(…, sourceExpression)`, and keep the folded arguments in the cache key: [`architecture.md`](architecture.md) → *Values a builder reads after the cache key*. (#5708)

## EXPR-TRANS: reproducing a host-only clrjit crash by matching the .NET Framework build

**Tried:** reproducing #6042, a stack overflow in `clrjit.dll` from the `QueryCache` static constructor. First on GitHub Actions images, including `windows-2025` with the reporter's exact build (4.8.09221) as x86 and x64. Then by measuring how much stack the JIT needs for that initializer, on the theory that the thread was already out of stack.

**Failed because:** neither reproduces; the stack headroom matched an empty class to within 1 KB. The trigger was the host: a C++Builder process that unmasks FP exceptions, so the x86 JIT faults compiling `double >= long.MaxValue`.

**Don't re-attempt:** chasing a native-host crash by framework version or stack depth. Ask first what hosts the process and whether it is x86, then probe with FP exceptions unmasked ([`bug-investigation.md`](bug-investigation.md) → *A .NET Framework crash only inside a native host*). (#6042, #6053)

## SQL-PROVIDER: ranking a `DateTime64` with no precision coarse on both sides of `IsCoarserDateTime`

**Tried:** fixing YDB's whole-second `Datetime64` being ranked sub-second (a literal beside `MAX(D64)` lost its fraction) by ranking every precision-less `DataType.DateTime64` as whole-second in `QueryHelper.DateTimeRank`.

**Failed because:** the rank is read for the other side too. On ClickHouse a literal's own type often arrives as `DateTime64` with no precision, so a `DateTime` column stopped counting as coarser than it and the literal was narrowed again: 18 tests per ClickHouse provider red (`CoarseAggregateComparedWithFinerLiteral`, `…InListKeepsLiteralTime`, `…SetOperationKeepsLiteralTime`, the window-function cells).

**Don't re-attempt:** a symmetric default. An unknown precision must answer "coarser" from both positions (low as the operand, high as the `than` side), so it only ever lets the value keep its own type. (#5959 MAJ012, `7eefd2deb`)

## SQL-PROVIDER: pinning the ClickHouse `Decimal128 → Decimal256` promotion in `GetDecimalTypeForValue` with a test

**Tried:** a `Decimal128(38,10)` column holding a 28-digit value beside a scale-11 literal, arm disabled, in three shapes: `MAX(col) = lit`, a captured `IN`, a `UNION`.

**Failed because:** the comparison and the `IN` pass without the arm (ClickHouse appears to widen a `Decimal128` comparison internally), and the `UNION` result overflows `System.Decimal` on the client whichever family is rendered. The `Decimal32` arm is observable (`Can't compare decimal number due to overflow`).

**Don't re-attempt:** a test cell for that arm; it cannot go red. (#5959 SUG203, `f93720bd9`)

## SQL-PROVIDER: reading the `DbType` on the IN-list values side of ClickHouse's `VisitInListPredicate`

**Tried:** testing the IN-list values with `ClickHouseExpressionExtensions.IsDateTime64` (`DataType` plus `DbType`), as the operand is, when fixing a DbType-only `DateTime` column beside a sub-second literal.

**Failed because:** a value lent the column's type carries `DateTime64` with `DbType "DateTime"`, but the ClickHouse literal writer renders by `DataType`. It was still written `toDateTime64(…)`, the operand was not wrapped, and the server refused with `Code: 53`.

**Don't re-attempt:** the `DbType` test on rendered values. Read the `DbType` for what the server sees of a column operand; test values by what the writer emits, their `DataType`. (#5959 MAJ011, `2940edbc4`)
