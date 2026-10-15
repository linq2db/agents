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

## SQL-AST: an end-to-end test telling per-boundary from outermost-only column-subquery scope apart in `SqlQueryValidatorVisitor`

**Tried:** a nested column-subquery control for the Oracle 11 parent-`IS NOT NULL` check, where the inner subquery's `IS NOT NULL` references the *middle* subquery's table, run with the scope reset mutated to fire only at the outermost boundary (`if (isColumnSubqueryEntry && _currentSources == null)`). Four middle shapes: uncorrelated `OrderBy(...).Select(...).FirstOrDefault()`, uncorrelated one-row `Where(...).FirstOrDefault()`, root-correlated `OrderBy` + `FirstOrDefault`, and an uncorrelated `Sum` over the inner `Count`. A root-correlated `Sum` middle hits `Error_OUTER_Joins` first.

**Failed because:** every shape still threw `Error_ColumnSubqueryShouldNotContainParentIsNotNull` under the mutation (rebuild confirmed by DLL timestamp). On Oracle 11 the `Take` shapes are rewritten into `LEFT JOIN … ROW_NUMBER()` derived tables, so no nested column-subquery boundary survives to the validator; the aggregate shape behaved the same.

**Don't re-attempt:** hunting for a LINQ shape. If the per-boundary reset needs a guard, test the visitor directly on a hand-built AST. (#6027)

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
