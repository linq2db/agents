# Work plan: feature-5717-dml-output-as-source — InsertWithOutputQuery as an honest DML source instead of CteClause.DataModification

**Tier:** L  ·  **Status:** approved  ·  **Approved-at:** 2026-10-24 (user, after critic round 3); A-12 re-approved 2026-11-27 (user, after critic round 10)  ·  **Branch:** feature/5717-dml-output-as-source
**Schema:** `.claude/docs/work-plan.md`  ·  **Gates:** `.claude/docs/definition-of-done.md`

Context: PR [#5982](https://github.com/linq2db/linq2db/pull/5982) (author to11mtm, fork `to11mtm/linq2db`, `maintainerCanModify: true`). This plan reworks the PR head `a8605803b0` in place, as local commits on top of the author's branch. Nothing is pushed without the user's explicit go-ahead. **Restacked 2026-10-24 (A-8)** on the QueryBatch stack: PR [#6111](https://github.com/linq2db/linq2db/pull/6111) (`feature/1404-query-batch`) on [#5673](https://github.com/linq2db/linq2db/pull/5673) (`feature/query-batches`), merged in as `b94919f94b`; the PR base becomes `feature/1404-query-batch`. **Moved 2026-10-24** into linq2db/linq2db as PR [#6133](https://github.com/linq2db/linq2db/pull/6133) (same branch name, head `8b70c7b6de`), because GitHub stacks do not span forks. #5982 is closed in its favour, and its baselines PRs (#2165, #2207) are closed with their branch deleted.

The user decided (2026-10-23):
- rework the AST;
- one call = one INSERT;
- no workarounds: fix the query cache in this PR, as separate commits that also close the master `AsCte` cache bug;
- the body is a dedicated expression, not a builder state flag;
- identity is assigned at expose;
- `RETURNING` is rendered from the body, not stored;
- `VisitNestedStatement` goes in the base visitor;
- commit the load transaction instead of skipping it;
- keep-alive semantics, with no `NotRead`.

## P1 Problem

PR #5982 implements `InsertWithOutputQuery` by attaching the INSERT to the CTE layer:
- `LinqExtensions.InsertWithOutputQuery` wraps itself in `AsCte(...)` inside the extension method body (`LinqExtensions.Insert.cs:1253`).
- `CteContext.InitQuery` checks for `InsertBuilder.DataModificationOutputContext` and attaches the statement to `CteClause.DataModification` (`CteContext.cs:85`).
- `CteClause.Body` is a fake `SELECT Inserted(t.col) FROM <target>` that is never rendered.
- `BasicSqlOptimizer.Finalize` copies the body columns into the nested `RETURNING` (`BasicSqlOptimizer.cs:106`).
- The number of INSERTs is decided by the `AsCte` registry (`ExpressionBuildVisitor.RegisterCteContext`, keyed by `ExpressionEqualityComparer`).

Probes on PostgreSQL 16 against the PR head (session scratchpad `Probe5982.cs`, `probe*.log`):
- **(a) The query cache decides how many INSERTs run.** Take `Make(t, v) => t.InsertWithOutputQuery(() => new T { Value = v })`.
  - Query A: `var a = Make(t, 11); a.Select(x => x.Value).Concat(a.Select(x => x.Value))`.
  - Query B: `Make(t, 12)…Concat(Make(t, 13)…)`.
  - B alone in a fresh process: `[12,13]`, 2 rows.
  - A, then B in one process: B gives `[12,12]` with 1 row; an INSERT is silently lost.
  - B, then A: A inserts 2 rows.
  - Mechanism: `ExpressionCacheManager.ReplaceParameterizedAndClosures` (`ExpressionCacheManager.cs:449-481`) turns closure constants into `ConstantPlaceholderExpression`, so A and B share a key. The CTE registry, however, compares the closures by reference (`ExpressionEqualityComparer.cs:539-572`).
  - The same defect exists on master for a plain `AsCte`: probe H on `a1fee89c52` returns `[2,2]` instead of `[2,3]`.
- **(b) Two separate calls in one scope insert once.** Shape D: `var d1 = t.InsertWithOutputQuery(() => new T { Value = v }); var d2 = <same>;` gives `[1,1]` and 1 row.
- **(c) `CompiledQuery` throws `Error_OutputQuery_NotRead`.** `CompiledQuery.Compile((DataConnection dc, int v) => dc.GetTable<T>().InsertWithOutputQuery(…).Select(x => x.Value).Sum())` fails because the `AsCte` wrapper is never added.
- **(d) The NotRead check compares counts, not identities** (`ExpressionBuilder.cs:324`), and cannot see a duplicate.
- **(e) An unread output throws**, although PostgreSQL itself runs an unreferenced data-modifying CTE. The throw exists only because the pipeline drops unreferenced CTEs.
- **(f) The eager-load path skips the implicit load transaction** (`Query.cs:238-242`). Instead of committing it, the insert and the eager-load children are made non-atomic.
- **(g) Every `CteClause` consumer must special-case `DataModification`**, or it reads the fake target-table body. It is guarded in YDB (`YdbSqlBuilder.cs:369`) and unguarded in `SqlWithClause.GetTableSource`, `SqlQueryColumnUsageCollector.VisitCteClause` and `AliasesHelper.VisitCteClause`.

## P2 Success criteria

- SC-1 Shape A (one `IQueryable` from `InsertWithOutputQuery` referenced twice) inserts exactly once per execution, whatever query was built before it in the process → TO-1, TO-3
- SC-2 Shape B (two calls, different values) inserts twice with both values, whatever query was built before it in the process → TO-2
- SC-3 Shape D (two calls in one scope capturing the same variable) inserts twice → TO-4
- SC-4 `InsertWithOutputQuery` inside a `CompiledQuery` lambda inserts once per syntactic call per invocation → TO-5, TO-6
- SC-5 A plain `AsCte` referenced twice versus two distinct `AsCte` calls are distinct cache entries: probe H returns `[2,3]` → TO-19
- SC-6 A query containing `InsertWithOutputQuery` is still query-cached: the same shape executed twice builds once → TO-20
- SC-7 Keep-alive: every `InsertWithOutputQuery` present in the exposed query expression inserts exactly once per execution, whether or not its rows are read. A query whose projection drops the member reading the output still inserts → TO-7
- SC-8 A call that depends on the enclosing query's rows (correlated) fails at build with `Error_OutputQuery_Correlated` → TO-21
- SC-9 After the build, every call's identity has exactly one DML source across all statements the query will execute, that is the distinct statements of `_query.Queries` and of every preamble's queries. Otherwise the build throws `Error_OutputQuery_Duplicated` → TO-8, TO-24
- SC-10 `CteClause` carries no DML: no `DataModification`, no fake body; master's `CteClause` code, visitor branches and wire shape are restored → TO-9
- SC-11 The rendered PostgreSQL SQL of every existing `InsertWithOutputQueryTests` case is unchanged against the PR head's baselines (alias renumbering excepted, reviewed) → TO-10
- SC-12 An INSERT into `ITable<Derived>` of a TPH hierarchy renders a valid data-modifying CTE (no `WHERE` in the body) → TO-11
- SC-13 Providers without `IsInsertOutputQuerySupported` throw `Error_OutputQuery_NotSupported` at build, direct and remote → TO-12
- SC-14 Plain CTE behaviour and SQL are unchanged → TO-13
- SC-15 A chained `InsertWithOutputQuery` inserts into both targets once, in dependency order → TO-14
- SC-16 An association over the output works, and its join is placed outside the data-modifying CTE, as on the PR head (A-2) → TO-18
- SC-17 A consumer that reads no output column renders a valid statement and inserts → TO-17
- SC-18 With eager loading over the output, the insert and the child queries run in one implicit transaction. Since A-12 (the stack's buffering): it commits once the value is computed, or once every main row is buffered, before the first row reaches the caller, and a failure up to that point rolls the insert back. What happens after the commit is a known limit, not a criterion (L-9). This holds while `LinqOptions.UseEagerLoadingTransaction` is on, the default; with it off (#6456, A-12) no transaction is opened, the insert commits with the statement and a load failure keeps it → TO-22, TO-26, TO-27, TO-28, TO-36

## P3 Constraints & anti-goals (M/L)

- Public API outside `LinqToDB.Internal.*`: only the two `LinqExtensions.InsertWithOutputQuery` overloads, with unchanged signatures. Their `<remarks>` restate SC-1..SC-4, SC-7, SC-8, SC-16 and the eager-load rule.
- No SQL change for plain CTEs or for any provider other than PostgreSQL. Existing master baselines are unchanged.
- The query-cache key for queries containing no CTE-defining call is unchanged: no extra comparison function, no change on the lookup hot path. Queries with `AsCte`/`GetCte` gain one comparison function (D-4).
- `CteClause`'s LinqService wire shape returns to master's. The new node appends a `QueryElementType`.
- No DB2 / SQL Server / UPDATE / DELETE / MERGE support (P10 L-4).
- Not editing the PR body or other users' comments; the follow-up goes in a new comment after approval.
- Rule note: `AGENTS.md` says a separable shared-engine fix gets its own PR. The user chose to keep the cache fix in this PR. It lands as separate commits so that `/split-pr` can move it later.
- User-visible deltas vs master:
  - the master `AsCte` cache fix (SC-5): a query whose two `AsCte` calls were served from a cache entry built for "one CTE referenced twice" now builds its own;
  - otherwise only the PR's new feature.
- User-visible deltas vs the PR head:
  - D-shape calls insert separately (SC-3);
  - `CompiledQuery` works (SC-4);
  - an unread output inserts instead of throwing `NotRead`, and `Error_OutputQuery_NotRead` is removed (SC-7);
  - correlated calls get their own error (SC-8);
  - eager loading over the output commits in one transaction (SC-18);
  - the remarks no longer say "identical expressions share one CTE" or "throws when not read".
  - Shipped prose to edit: `LinqExtensions.Insert.cs` `<remarks>` of both overloads → E-19.

## P4 Unknowns (M/L)

- U-1 Is the per-call token preserved by expose for shape A? Yes: captured queries are inlined at the member node, preserving the token subtree by reference (`ExposeExpressionVisitor.cs:832`). The re-visit loop (`ExposeExpressionVisitor.cs:144-152`) does not re-invoke the tokenized internal call, whose first argument is a `GetTable(Constant(dc))` call or a query expression. The critic could not break A, B or D on this path — resolved-by scout
- U-2 Does expose leave the call in the expression when it sits under a condition on a captured value? No: `CapturedConditionRemovesOutput(flag: false)` passes on the PR head, whose NotRead check walks the exposed expression (`ExpressionBuilder.cs:282-286`) and would have thrown had the call remained. So keep-alive (SC-7) does not insert under `flag == false`, and the remarks state that captured-value conditions act like C# code — resolved-by probe
- U-3 Do the `CloneQuery` rewrites duplicate the DML source? No: they skip `SqlCteTable` (`BasicSqlOptimizer.cs:992-1007`, `SelectQuery.cs:347-350`), and the source lives only in a CTE body — resolved-by scout
- U-4 Can a join removal drop the source? It is the only FROM table of its CTE body, never joined (`JoinsOptimizer.cs:210-240`, `SelectQueryOptimizerVisitor.cs:1151-1178`). Removing a join to the CTE table leaves the CTE unreferenced, and keep-alive (D-11) retains it — resolved-by scout
- U-5 LinqService reads statements "last read wins" (`LinqServiceSerializer.cs:2073`). The nested statement is read before the root, the same assumption `DataModification` relied on. The `.LinqService` legs of TO-10 and TO-13 run it — resolved-by scout
- U-6 The TPH predicate reaches the body only for a derived target: `MakeIsPredicate` returns `null` when the type covers every mapping (`ExpressionBuilder.SqlBuilder.cs:676-680`) → D-8 — resolved-by scout; re-resolved by A-3: the output table's type is always the root, so no target gets a predicate
- U-7 Does anything after `Finalize` change body columns? Only `OptimizeAndConvertAll` (Modify on the first run of a non-parameter-dependent query, Transform otherwise; `DataConnection.QueryRunner.cs:233-254`), `PrepareQueryAndAliases` and `BuildSql`. None prunes columns. On the stack (A-8) the passes are `PrepareStructure` (Modify for `prepareOnce`, Transform otherwise, `DataConnection.QueryRunner.cs:264-309`) and the always-Transform eager render (`ScenarioCommandRenderer.cs:292-311`), and a baked query drops its statement graph after the first render; none prunes columns either. D-5 no longer depends on this, because `RETURNING` is read at render — resolved-by scout
- U-8 Do entity query filters attach to the new table's context? No (`TableBuilder.cs:243-256`). The target's filters are disabled by `InsertBuilder` (`InsertBuilder.cs:42-53`) — resolved-by scout
- U-9 Can the cache record a sharing pattern per position rather than per node? Yes: `PathVisitor` walks every position and dedupes only `IQueryable` constants' inner expressions (`PathVisitor.cs:18, 222-232`). `GetExpressionAccessors` dedupes by node (`InternalExtensions.cs:188-225`), so D-4 builds its own per-position accessor list. `ComparisionFunctions` already compare a build-time value against an accessor evaluated on the new expression (`Query.cs:112-114`, `ExpressionCacheManager.cs:616-634`) — resolved-by scout
- U-10 Are closure and token constants placeholders in the cached key? Yes, by `ShouldRemoveConstantFromCache` for non-scalar, non-array values (`ExpressionCacheHelpers.cs:10-24`), which is why A and B share a key today. D-4 adds the sharing pattern beside the placeholders — resolved-by scout
- U-19 Are scalar constants placeholders too? Yes, once parameterized: every `ConstantExpression` an accessor was applied to lands in the reference-keyed `NonComparableExpressions` (`ExpressionCacheManager.cs:29, 111-113, 521, 645`), and `ReplaceParameterizedAndClosures` replaces it (`:458-463`). A placeholder equals any constant (`EqualsToVisitor.cs:18-22`). So `q.Concat(q)` over `Where(p => p.Id > 5).AsCte()` and a `> 5` / `> 6` pair share a key → D-4 records every constant, classed by the registry's rule; TO-19's scalar arm. Reasoned, not yet measured; TO-19 measures it — resolved-by scout
- U-11 Which stateful visitors descend into the nested statement? `SelectQueryOptimizerVisitor` (`_parentSelect`, `:3909-3928` precedent), `SqlQueryColumnOptimizerVisitor` (`_inExpression`, `:69-103` precedent), `SqlQueryColumnNestingCorrector` (`_parentQueryNesting` `:145`, chain walk `:224-252`, push `:317-339`), `AliasesHelper` (alias registration). `SqlQueryValidatorVisitor` treats it as a FROM subquery (`:380-429`), which is benign on PostgreSQL's flags. The `CteCollectorVisitor` must see the nested `SqlCteTable` refs. All are covered through `VisitNestedStatement` (D-9) — resolved-by scout
- U-12 Where does an association over the output land? Inside the CTE body (`CteContext.cs:154-168`; `CteTests.TestAssociations`, `Tests/Linq/Linq/CteTests.cs:2645-2655`). PostgreSQL cannot have a join in a data-modifying CTE → SC-16 — resolved-by scout; re-resolved by A-2: at the reference. `CteTableContext.MakeExpression` returns an association root untouched (`CteTableContext.cs:78-79`), so the join is built outside the CTE and only the key becomes a CTE field. `CteTests.TestAssociations(PostgreSQL.16).sql` shows the same shape for a plain CTE
- U-13 Where does the load transaction cover a DML main query? The `KeyedQuery` strategy buffers the main query inside `InitPreambles` (`ExpressionBuilder.cs:381-384`, `SetRunQueryWithKeyedQueryBuffer`), which runs inside `StartLoadTransaction` at all ten sites (`ExpressionQuery.cs:118, 145, 174, 204, 266, 284, 310, 329`; `CompiledTable{T}.cs:184, 198`). The sites dispose without commit. Committing after `InitPreambles` succeeds covers the insert, and the later enumeration runs outside the transaction as today — resolved-by scout; re-resolved by A-8: on the stack the transaction spans the enumeration, the sites call `InitHarvesters`, and the commit moves to the owner's end (the element call, or the enumerator wrapper closing after its reader)
- U-14 Can an unbuilt call be built standalone for keep-alive? Only if it does not reference a parameter of a lambda enclosing the call within the exposed query expression. A correlated call cannot be a top-level CTE → D-12. `ExpressionBuilder.ParametersParam` (`ps`) is not such a parameter: `CompiledQuery` rewrites compiled-lambda parameters into `Convert(ArrayIndex(ps, i), T)` (`CompiledQuery.cs:236-247, 331`; `ExpressionBuilder.cs:195`), and the compiled expose keeps `ps[i]` for non-root arguments (`ExposeExpressionVisitor.cs:573-583`) — resolved-by scout
- U-15 Is the conditional evaluation the same on the compiled path? No: `CompiledTable.BuildQuery` exposes with `optimizeConditions: false` (`CompiledTable{T}.cs:110-111`), and a compiled `flag` is `ps[i]`, so `flag ? inserted.Count() : 0` keeps the call in both arms. Under D-11 it inserts for either value of `flag` → TO-23, P10 L-7, E-19 — resolved-by scout
- U-16 Can a preamble statement carry the DML CTE? The `KeyedQuery` buffer has two silent fallbacks to `sequence.SetRunQuery` (`ExpressionBuilder.EagerLoadKeyedQuery.cs:1044-1047`, `:1160`), which leave the key-extraction preamble to run `keyQuery` built from the main sequence (`:862-870`, executed at `:931-936`). That would be a second INSERT, so D-6 counts preamble statements as well. Reachability for a DML main query is unprobed; TO-24's mutation forces the path — resolved-by scout
- U-17 Are `BuildQuery` re-entries scoped? `BuildQuery` is re-entered for eager-load child, key and union queries (`ExpressionBuilder.EagerLoad.cs:378, 413`; `ExpressionBuilder.EagerLoadKeyedQuery.cs:866, 877`; `ExpressionBuilder.EagerLoadUnion.cs:1166, 1333`) inside the main `FinalizeProjection` (`ExpressionBuilder.cs:489`). So D-11's keep-alive build and D-4's registration run only for `ReferenceEquals(query, _query)`, in the slot after `:489` and before the `Finalize` loop at `:354` — resolved-by scout
- U-18 Do the tokenized overloads pass `InsertBuilder.CanBuildMethod`? It requires `call.IsQueryable` (`InsertBuilder.cs:25-26`), meaning a built-in declaring type (`InternalExtensions.cs:240-253`, which includes `LinqExtensions`) or `[IsQueryable]`. So the tokenized overloads and the `Source` marker are internal methods on `LinqExtensions`, as `AsCteInternal` is (`LinqExtensions.cs:1196-1209`); this also keeps compiled expose off `ExpandOverSource` (`ExposeExpressionVisitor.cs:614-618`) — resolved-by scout

## P5 Decisions (M/L; rejected alternatives mandatory at L)

### D-1 — AST: a `SqlTable` subclass holding the nested statement; the CTE body is an honest projection over it

- **chosen:**
  - New `SqlDataModificationTable : SqlTable` (`LinqToDB.Internal.SqlQuery`) with appended `QueryElementType.SqlDataModificationTable` and `SqlTableType.DataModification`.
  - It holds:
    - `Statement` (`SqlStatementWithQueryBase`, an insert for now);
    - `Identity`;
    - field copies of the target's mapped fields.
  - `Equals` is reference equality.
  - The CTE body is `SELECT d.f… FROM d`, built by the ordinary `CteContext`.
- **rejected:**
  - `CteClause.DataModification` (the user's rejection; P1 g).
  - A definition/reference pair outside CTEs, which re-implements `CteClause`/`SqlCteTable` for no current consumer.
  - A non-`SqlTable` `ISqlTableSource`, which loses `TableContext` reuse, as `RawSqlContext` has it (`TableBuilder.RawSqlContext.cs:152-157`).
  - Keeping `QueryElementType.SqlTable`, which the Transform visitor and the serializer downcast to a plain table (`QueryElementVisitor.cs:3126`), silently dropping the INSERT.
- **why this:**
  - Unaware code fails loudly: every `ElementType` switch throws on an unknown table type.
  - CTEs stay DML-unaware.
  - DB2 can render the same body as `SELECT … FROM FINAL TABLE (…) d`.
- **failure mode of the choice:** sites branching on `is SqlTable` would treat the node as a physical table (`Sql.Expressions.cs:346-363`, `BasicSqlBuilder.cs:1173`, `:2234/2254`). They are unreachable while the node is only ever the sole FROM table of a CTE body (E-14). TO-10 asserts the SQL.

### D-2 — The builder creates the CTE, with a dedicated body expression

- **chosen:**
  - `InsertBuilder`, given a tokenized `InsertWithOutputQuery` call, finds or registers a `CteContext` keyed by that call (`FindRegisteredCteContext` / `RegisterCteContext`). It does so before building `methodCall.Arguments[0]`, so the source is built once (`InsertBuilder.cs:54-57`).
  - The `CteContext`'s `CteExpression` is `LinqExtensions.DataModificationSource(call)`, an internal marker method on `LinqExtensions` (U-18) with its own `[BuildsMethodCall]` entry. Building it produces the insert statement, the `SqlDataModificationTable` and a `TableContext` over it.
  - `LinqExtensions` no longer emits `AsCte`.
- **rejected:**
  - `AsCte` in the method body (P1 c).
  - A builder-state flag (`IsInitializingBody`) to tell the body build from a reference — the same expression would mean two things depending on global state (the user rejected it).
  - Placement only at `Finalize` — that needs D-1's rejected pair.
- **why this:**
  - Dispatch is by expression, not by state.
  - The CTE is linq2db's sharing construct, and PostgreSQL needs a top-level `WITH`.
- **failure mode of the choice:**
  - DB2 and SQL Server follow-ups that need no CTE must inline a single-reference CTE (P10 L-4).
  - Separating input for "registered before the source is built": a chained call (TO-14), whose inner call is a distinct key.

### D-3 — Identity: a per-call token, assigned before the build

- **chosen:**
  - The public overloads emit calls to internal tokenized overloads on `LinqExtensions` (U-18) that carry a `DataModificationIdentity` constant, created once per C# invocation. Shape A shares it; B and D do not.
  - `ExposeExpressionVisitor` rewrites any public-`MethodInfo` call left un-evaluated (`CompiledQuery` lambdas, other non-evaluable trees) into the tokenized form with a fresh token. Every call therefore has its identity before the builder runs.
  - The internal overload, if invoked, re-emits the identical call with the same token, so it is a fixed point for the expose equality check at `ExposeExpressionVisitor.cs:605`.
  - Identity collection reads the tokens and never uses an `ExpressionEqualityComparer` set.
- **rejected:**
  - Structural identity (P1 a/b).
  - Reference identity of call nodes, which expose rebuilds.
  - A builder-side reference map for raw calls, whose stability across builder rebuilds is unprovable (round-1 U-9).
- **why this:** identity is decided at one point, before any build or cache key exists.
- **failure mode of the choice:** a raw call inside a `CompiledQuery` gets a token per compile, not per invocation. That is correct, because a compiled lambda's call sites are fixed. Separating input: TO-6 (two identical raw calls).

### D-4 — The query cache records the sharing pattern of non-cacheable constants inside CTE-defining calls

- **chosen:**
  - In `ExpressionBuilder.FinalizeQueryCacheInformation`, for the main query only and once per build (U-17), walk the main expression with `PathVisitor`.
  - At every position of a CTE-defining call, collect a per-position accessor for **every `ConstantExpression` node** inside it. This covers scalars too: parameterized scalar literals become `NonComparableExpressions` placeholders in the key just as closures do (U-19). The calls are exactly four methods: `AsCte`, `AsCteInternal`, `GetCte`, and the tokenized `InsertWithOutputQuery`. Not the whole `TableBuilder.cs:17` attribute set, which also lists `FromSql*`.
  - Register the pattern only when at least two CTE-call positions carry a constant. Otherwise no cross-position merge decision exists, and the query keeps `IsFastComparable` (`QueryCacheCompareInfo.cs:34`).
  - Compute the canonical pattern: a class index by first occurrence. Constants are classed with the registry's own constant equality (`ExpressionEqualityComparer`'s constant rule: reference, then `Equals`, `SequencesEqual` for `IEnumerable`, the inner `.Expression` for `ExpressionQuery<>`, `ExpressionEqualityComparer.cs:539-572`), not by reference.
  - Register it through `ExpressionCacheManager.MarkAsValue` as a value comparison: build-time pattern string versus pattern recomputed from the new expression (`ExpressionCacheManager.cs:616-634`; checked in `Query.cs:112-114`).
  - Register exactly once per cache manager, guarded by a flag on `ExpressionCacheManager`. `FinalizeQueryCacheInformation` runs at `ExpressionBuilder.cs:541` and again at `:282`, and the `validateSubqueries` retry reuses the same `ParametersContext` (`Query{T}.cs:262-266`).
- **rejected:**
  - `DoNotCache` (round 1) — a workaround that leaves the master bug.
  - Comparing token *values* — tokens differ per execution and would never hit.
  - Recording the pattern of every constant in every query — a lookup cost on every cached query.
  - Keying on the CTE registry's decisions — the registry keys are builder-transformed nodes with no stable path into the main expression.
- **why this:**
  - The CTE registry merges two occurrences when their constants compare equal: by reference first, then by `Equals`, `SequencesEqual` for `IEnumerable`, and the inner `.Expression` for `ExpressionQuery<>` (`ExpressionEqualityComparer.cs:539-572`).
  - Given structurally equal subtrees, the registry's merge decision is exactly the pairwise constant-equality relation across their positions. Recording that relation, classed by the same rule, makes every expression that matches the key and the pattern produce the same merges. This holds for closures (the master bug), scalar literals (U-19) and DML tokens (reference equality, since the token has no `Equals` override).
  - A reference-only pattern (round 2) was unsafe for value-compared constants. Two separate `Where(p => p.Id > 5).AsCte()` merge by value while their boxed `5`s differ by reference, so a later `5` / `6` query would have matched the "distinct" pattern and reused the merged plan.
- **failure mode of the choice:**
  - A CTE-defining call missing from the four-method list would keep the old conflation; E-24 defines the list in one place.
  - Lookup cost: the classifier runs the registry's constant comparison on every lookup of a qualifying query, including `SequencesEqual` over captured collections (P10 L-1).
  - Separating inputs: probe H's A/B pair (TO-19) and the DML AB/BA pair (TO-2, TO-3).
  - Cost: one comparison function per query with CTE calls (TO-20 asserts that caching still hits).

### D-5 — `RETURNING` is rendered from the CTE body; nothing is stored

- **chosen:**
  - `BasicSqlBuilder.BuildCteBody`, for a body whose only FROM source is a `SqlDataModificationTable`, renders the nested statement through a child builder. It passes a render-local output list built from the body columns in body order:
    - every `d.f` is replaced by `SqlAnchor(Inserted, target.f)` when `OutputInsertUseSpecialTable`, else by `target.f`;
    - a column with no `d` field (the dummy `SqlValue(1)`, `SqlQueryColumnOptimizerVisitor.cs:343-356, 552-561`) is copied verbatim;
    - an empty body renders no `RETURNING`.
  - The nested `Statement.Output` stays `null`.
  - `Finalize` only validates the projection-only shape (one FROM table; no joins / where / group / having / order / distinct / set operators / take / skip) and runs `FinalizeInsert` on the nested statement. A violation throws `Error_OutputQuery_Projection`.
- **rejected:**
  - Syncing `Output` at the end of `Finalize` (round 1) — a second representation kept in step by pass ordering.
  - Filling it at build — column pruning would desync it.
- **why this:**
  - The body is the single source of truth.
  - Rendering creates transient nodes without mutating the cached AST, as convert-during-render already does.
- **failure mode of the choice:** the render-time list must reach the nested insert's output builder (`BasicSqlBuilder.cs:614`, `:640`). A provider builder that overrides `BuildInsertQuery` and reads `statement.OutputClause` directly would miss it. Only PostgreSQL is enabled, and it does not override it (searched in E-11).

### D-6 — Exact identity check

- **chosen:**
  - At the end of `Build<T>`, where the preambles are in hand, every token collected from the exposed expression must map to exactly one `SqlDataModificationTable`.
  - The count runs over the final `With` clauses of the distinct statements, deduped by reference, that the query will execute: `_query.Queries` and every preamble's statements.
  - `Preamble` gains an abstract `GetStatements()`, implemented by all eight subclasses (E-32..E-35). It is abstract so that a new preamble kind cannot skip the check.
  - The `KeyedQuery` buffer preamble runs `query.Queries[0].Statement`, the same object as the main statement (`ExpressionBuilder.EagerLoadKeyedQuery.cs:1088-1090`), so it counts once. The fallbacks' `KeyedQueryKeysPreamble` carries a cloned copy (`:294-296, 862-866` → `CteContext.cs:434`) and counts as a second source.
  - Otherwise the build throws `Error_OutputQuery_Duplicated`, an internal-consistency error. This also catches the `KeyedQuery` fallbacks (U-16).
- **rejected:** the PR's `rendered < calls.Count` (P1 d).
- **why this:** with keep-alive (D-11) a missing source is a bug, not a user error, and a duplicate would be a double INSERT.
- **failure mode of the choice:** none user-visible. It turns a silent double insert into an exception. Separating input: TO-8's mutation.

### D-7 — Provider gate at build time

- **chosen:**
  - `InsertBuilder` throws `Error_OutputQuery_NotSupported` when `IsInsertOutputQuerySupported` is false.
  - Remove the `FinalizeCte` gate (`BasicSqlOptimizer.cs:783`) and the YDB guard (`YdbSqlBuilder.cs:369`).
  - `BasicSqlBuilder` backstop cases for the new table throw the same error.
- **rejected:** gates in generic CTE code.
- **why this:** the refusal happens before any SQL, like other builder refusals.
- **failure mode of the choice:** a provider that sets the flag and overrides `BuildCteBody` (as `ClickHouseSqlBuilder.cs:436` does) hits the backstop.

### D-8 — The new table's `TableContext` skips the TPH predicate (withdrawn by A-3)

- **chosen:** an internal `TableContext` ctor parameter `applyInheritanceFilter` (default `true`); the DML-source context passes `false`.
- **rejected:**
  - Refusing TPH targets — a regression against the PR head.
  - Moving the predicate to the consumer — it would filter inserted rows out.
- **why this:** the discriminator filters reads of a table holding several types; an INSERT's output is exactly the inserted rows.
- **failure mode of the choice:** UPDATE / DELETE follow-ups must re-evaluate it. Separating input: `ITable<Derived>` with a non-default code (TO-11); a base-type target gets no predicate either way.

### D-9 — `VisitNestedStatement` in the base visitor

- **chosen:**
  - `QueryElementVisitor.VisitSqlDataModificationTable` visits `Fields` and then calls a new `protected virtual VisitNestedStatement(SqlStatement)`, whose default is `Visit(statement)`, in all three modes.
  - Its Transform case mirrors `VisitSqlTable`'s `NotifyReplaced` remap of `All` and the fields (`QueryElementVisitor.cs:3018-3023`).
  - Stateful visitors override `VisitNestedStatement` to visit the statement as an isolated root:
    - `SelectQueryOptimizerVisitor` (save/null/restore `_parentSelect`);
    - `SqlQueryColumnOptimizerVisitor` (`_inExpression = true`, so INSERT…SELECT columns survive);
    - `SqlQueryColumnNestingCorrector` (save/null/restore `_parentQueryNesting`).
  - `AliasesHelper` registers the node's alias.
- **rejected:**
  - Ad-hoc overrides of the table visit (round 1) — the concept has no name, so a missed visitor is invisible.
  - An opaque statement — parameters, aliases and conversion would be lost.
- **why this:** "a statement nested inside a statement" becomes a named, searchable override point.
- **failure mode of the choice:** a future stateful visitor must still opt in. The override point makes the omission findable by name, but only tests prove behaviour (TO-10 covers sequence identity, pre-18 and the VALUES form; TO-14 covers chaining).

### D-10 — The eager-load transaction is committed for a data-modifying query

- **chosen:**
  - Remove the `HasDataModification` skip in `Query.GetTransactionOwner` (`Query.cs:238-242`).
  - `Query.StartLoadTransaction(Async)` returns an internal `LoadTransaction` holder. Its `Complete()` commits when the query has data modification. Dispose without `Complete()` rolls back, as today.
  - Re-derived by A-8 for the stack, where the transaction spans the whole enumeration. `Complete()` runs when the owner finishes without an exception: for an element call, after the value is computed; for an enumeration, when the stack's enumerator wrapper closes, after its reader, early `break` included, unless `MoveNext` threw. A `ForEachAsync` callback exception rolls back, because the callback runs inside the call. An exception from a caller's `foreach` body commits, because the enumerator never sees it (L-9).
  - **Re-derived by A-12: the stack now buffers.** #6111's `bbd9de082` ("Buffer an eager load's main rows inside its read transaction", 2026-10-29, an ancestor of A-11's head and missed by it) replaced the spanning transaction. Every enumeration site reads all main rows inside the transaction (`BufferedRows<T>.Read`, `BufferedAsyncEnumerable<T>.CreateAsync`), calls `Complete()`, and only then yields the first row: `ExpressionQuery.cs:396-401` (sync), `:172-177` (`ExecuteAsyncEnumerable`), `:211-215` (`ForEachAsync`), `:248-253` (`GetAsyncEnumerator`). The element sites complete after the value (`:130`, `:142`, `:311`, `:324`, `:344`, `:357`; `CompiledTable{T}.cs:187`, `:219`). So the insert commits before any caller code runs. A materialization failure happens while buffering, inside the transaction, and rolls the insert back. A failure in a `foreach` body or a `ForEachAsync` callback happens after the commit and keeps the insert (L-9). The wrapper classes of A-8 are gone, and this PR no longer edits any load-transaction site: E-28..E-30 and E-37..E-39 are withdrawn. D-10's remaining contribution here is that a DML query is not exempt: it takes the same transaction as any eager load, which the PR head inherits with no edit.
- **rejected:**
  - Skipping the transaction (the PR) — the insert commits and the children are read outside one snapshot, non-atomically.
  - Always committing — it changes every read-only eager load for no gain.
- **why this:** the insert and its eager-loaded children become atomic and consistent.
- **failure mode of the choice:**
  - A site that forgets `Complete()` rolls back the insert silently. The element sites and the three wrappers are enumerated (A-8). TO-22 and TO-26 check that the inserted rows persist through every site family, and TO-27 checks the rollback. Since A-12 the sites are the stack's buffered ones; the same tests guard them, under mutations of the stack's code.
  - Harvesters invariant: every `InitHarvesters` site must stay wrapped (memory note: preambles need a transaction).
  - Once committed, the holder must not dispose again. That was load-bearing before the restack (A-7): the connection's current transaction could then be the user's. On the stack nothing can start a transaction between the commit and the release, so the `_released` guard is defensive (A-8). Since A-12 that is false for `ForEachAsync`: its holder stays undisposed until the loop ends (`ExpressionQuery.cs:202`, `await using` around the callback loop), so a callback can open a transaction after the commit, and the guard is what keeps disposal from touching it. The other sites dispose the holder before caller code runs. Read from code, unprobed.
  - Committing with the reader open fails on PostgreSQL ("A command is already in progress"). The wrappers close the inner enumerator first, and TO-28 pins that order on the streamed (detached-child) shape. Since A-12 buffering closes the reader before every commit, so this mode cannot occur; TO-28 is a characterization.

### D-11 — Keep-alive semantics

- **chosen:**
  - For the main query only (`ReferenceEquals(query, _query)`), in `BuildQuery` after `FinalizeProjection` (`ExpressionBuilder.cs:489`) and before `Finalize` (`:508`), the builder builds a CTE for every collected token that has none: a pruned projection member, or a call never reached by translation. It adds every DML CTE to the root statement's `With`. Eager-load child, key and union `BuildQuery` re-entries (U-17) never do this.
  - `FinalizeCte` keeps existing `With` clauses whose body reads a `SqlDataModificationTable` even when unreferenced; PostgreSQL runs them. It runs twice per `Finalize` (`BasicSqlOptimizer.cs:55, 71`), and its collector does not descend into `With` (`:720-723`). So on both runs it reads the incoming `With`, keeps the DML clauses, and runs the collector over each kept body to pick up its dependencies before the topological sort.
  - Remove `Error_OutputQuery_NotRead`.
- **rejected:** throwing `NotRead` (the PR) — an error that exists only because the pipeline drops unreferenced CTEs (P1 e).
- **why this:** "present in the query → runs once" is deterministic and matches PostgreSQL's own rule.
- **failure mode of the choice:**
  - On the normal path a condition on a captured value removes the call at expose (U-2), so no insert runs.
  - On the compiled path conditions are not evaluated at expose (U-15), so the call stays and inserts for either arm.
  - Both follow the one rule "present in the exposed expression → runs once", and the remarks state both (E-19, P10 L-7).
  - Separating inputs: `UnreadOutput*` and `CapturedConditionRemovesOutput` (TO-7), and the compiled flag (TO-23).

### D-12 — Correlated calls are refused

- **chosen:** identity collection rejects, with `Error_OutputQuery_Correlated`, a call whose subtree uses a `ParameterExpression` bound by a `LambdaExpression` that encloses the call within the exposed query expression. No exemption is needed: compiled queries read their arguments through `ExpressionBuilder.ParametersParam`, which no lambda in the exposed expression binds (`CompiledTable{T}.cs:110-120`), so it is never "enclosing" (U-14).
- **rejected:** letting the builder fail on an unbound parameter, which gives an unhelpful message.
- **why this:** a data-modifying CTE is top-level and cannot read the enclosing row.
- **failure mode of the choice:** none known. Separating input: `source.Select(s => t.InsertWithOutputQuery(() => new T { Value = s.Value }).Count())` (TO-21).

## P6 Edit-points

- E-1 `Source/LinqToDB/Internal/SqlQuery/SqlDataModificationTable.cs` — new class (D-1)
- E-2 `Source/LinqToDB/Internal/SqlQuery/QueryElementType.cs` — append `SqlDataModificationTable`
- E-3 `Source/LinqToDB/Internal/SqlQuery/SqlTableType.cs` — append `DataModification`
- E-4 `Source/LinqToDB/Internal/SqlQuery/Visitors/QueryElementVisitor.cs` — `VisitSqlDataModificationTable` (3 modes, field remap) and `VisitNestedStatement` (D-9); revert `VisitCteClause` to master
- E-5 `Source/LinqToDB/Internal/SqlQuery/Visitors/SqlQueryCloneVisitor.cs` — revert to master
- E-6 `Source/LinqToDB/Internal/SqlQuery/Visitors/SqlQueryColumnOptimizerVisitor.cs` — `VisitNestedStatement` override; revert `VisitCteClause` to master
- E-7 `Source/LinqToDB/Internal/SqlQuery/Visitors/SelectQueryOptimizerVisitor.cs:VisitNestedStatement` — isolation override
- E-8 `Source/LinqToDB/Internal/SqlQuery/CteClause.cs` — revert to master
- E-9 `Source/LinqToDB/Internal/SqlQuery/SqlWithClause.cs` — revert to master
- E-10 `Source/LinqToDB/Internal/Remote/LinqServiceSerializer.cs` — revert `CteClause` to master; register, pre-visit, write and read the new table
- E-11 `Source/LinqToDB/Internal/SqlProvider/BasicSqlBuilder.cs` — `BuildCteBody` DML rendering with the render-local output list (D-5); the output list reaches `BuildInsertQuery`/`BuildInsertQuery2`; backstop cases in `BuildPhysicalTable`, `GetTableAlias`, `GetPhysicalTableName` and the expression switch (D-7); replace the PR head's `BuildDataModificationCteBody` and its `BuildWithClause` branch with a new `BuildDataModificationCteBody` (`:551`), dispatched from `BuildCteBody` (`:538`) on the body's FROM shape (D-5)
- E-12 `Source/LinqToDB/Internal/SqlProvider/BasicSqlOptimizer.cs` — `Finalize` validation and nested `FinalizeInsert` (D-5); `FinalizeCte` keeps DML CTEs (D-11); remove `FinalizeDataModificationCtes`, the gate and the collector's `DataModification` visit
- E-13 `Source/LinqToDB/Internal/DataProvider/Ydb/YdbSqlBuilder.cs` — revert to master
- E-14 `Source/LinqToDB/Internal/Linq/Builder/InsertBuilder.cs` — tokenized-call path (CTE registration before source build, D-2); the `LinqExtensions.DataModificationSource` body path (statement, new table, `TableContext` with the inheritance filter applied, which is null for the output table's type per A-3); provider gate (D-7); remove `DataModificationOutputContext`
- E-15 `Source/LinqToDB/Internal/Linq/Builder/CteContext.cs` — revert to master
- E-16 `Source/LinqToDB/Internal/Linq/Builder/TableBuilder.TableContext.cs` — internal ctor `applyInheritanceFilter` (D-8) — withdrawn by A-3: dead code, removed; the file equals master
- E-17 `Source/LinqToDB/Internal/Linq/Builder/ExpressionBuilder.cs` — token collection, correlated check (D-12), keep-alive build of missing calls before `Finalize` (D-11), exact check (D-6), sharing-pattern registration in `FinalizeQueryCacheInformation` (D-4); remove the NotRead check
- E-18 `Source/LinqToDB/Internal/Linq/Builder/ExpressionBuilder.EagerLoad.cs` — guards keep working on tokenized calls; forced `KeyedQuery` kept
- E-19 `Source/LinqToDB/LinqExtensions/LinqExtensions.Insert.cs` — public overloads emit the internal tokenized overloads, and the internal tokenized overloads plus the `DataModificationSource` marker are declared here on `LinqExtensions` (D-3, U-18); remove `WrapOutputSource`; `<remarks>` restate SC-1..SC-4, SC-7, SC-8, SC-16, the eager-load rule and the compiled-condition rule (P10 L-7); A-12 re-touched the commit-with-statement sentence for `LinqOptions.UseEagerLoadingTransaction` (`af52f547d`)
- E-20 `Source/LinqToDB/Internal/Common/ErrorHelper.cs` — remove `Error_OutputQuery_NotRead`; add `Error_OutputQuery_Projection`, `Error_OutputQuery_Duplicated`, `Error_OutputQuery_Correlated`
- E-21 `Source/LinqToDB/PublicAPI/PublicAPI.Unshipped.txt` — remove the `CteClause.DataModification` and `NotRead` entries; add the new type, enum values, visitor methods and error constants
- E-22 `Tests/Linq/Update/InsertWithOutputQueryTests.cs` — P8 tests; `UnreadOutputThrows` becomes `UnreadOutputStillInserts`; TO-36's `EagerLoadOverOutputWithoutLoadTransaction` (A-12)
- E-23 `Source/LinqToDB/Internal/DataProvider/AliasesHelper.cs` — register the new table's alias — withdrawn by A-4: not needed, not edited
- E-24 `Source/LinqToDB/Internal/Linq/DataModificationIdentity.cs` — new internal sealed token type (D-3); the sharing-pattern helper moved to E-36 (A-1)
- E-25 `Source/LinqToDB/Internal/SqlQuery/Visitors/SqlQueryColumnNestingCorrector.cs:VisitNestedStatement` — isolation override (D-9)
- E-26 `Source/LinqToDB/Internal/Linq/Builder/Visitors/ExposeExpressionVisitor.cs` — rewrite raw public calls to the tokenized form (D-3)
- E-27 `Source/LinqToDB/Internal/Linq/ExpressionCacheManager.cs` — accept the sharing-pattern value comparison once, via a "registered" flag (D-4); no change to the existing paths
- E-28 `Source/LinqToDB/Internal/Linq/Query.cs` — remove the `HasDataModification` transaction skip; `LoadTransaction` holder with `Complete()` that completes and releases once (D-10, A-7, A-8) — withdrawn by A-12: the stack (#5673, #6111 `bbd9de082`, #6456) owns this code, and the own delta does not touch the file
- E-29 `Source/LinqToDB/Internal/Linq/ExpressionQuery.cs` — `Complete()` after the element at the element sites (eager and harvester paths) and after the `ForEachAsync` loop; the enumerator sites hand the holder to the wrappers (D-10, A-8) — withdrawn by A-12: stack-owned buffering (D-10), not in the own delta
- E-30 `Source/LinqToDB/Internal/Linq/CompiledTable{T}.cs` — call `Complete()` after the element at the two sites (D-10, A-8) — withdrawn by A-12: stack-owned, not in the own delta
- E-31 `Tests/Linq/Linq/CteTests.cs` — the plain-`AsCte` cache test (TO-19)
- E-32 `Source/LinqToDB/Internal/Linq/Harvester.cs` (was `Preamble.cs`; the stack renamed it, A-8) — abstract `GetStatements()` (D-6)
- E-33 `Source/LinqToDB/Internal/Linq/Builder/ExpressionBuilder.EagerLoadDefault.cs` — `GetStatements()` for its two preamble classes (`:159`, `:201`)
- E-34 `Source/LinqToDB/Internal/Linq/Builder/ExpressionBuilder.EagerLoadKeyedQuery.cs` — `GetStatements()` for its harvester classes, including the stack's `KeysDataSlotHarvester` (A-8)
- E-35 `Source/LinqToDB/Internal/Linq/Builder/ExpressionBuilder.EagerLoadUnion.cs` — `GetStatements()` for its two preamble classes (`:1602`, `:1820`)
- E-36 `Source/LinqToDB/Internal/Linq/CteConstantsPattern.cs` — the four CTE-defining method names and the sharing-pattern helper (D-4), moved out of E-24 by A-1
- E-37 `Source/LinqToDB/Internal/Linq/EnumeratorWrapper.cs` — holds a `LoadTransaction`, records a `MoveNext` exception, and completes after the inner enumerator closes (A-8) — withdrawn by A-12: the file no longer exists at the head (removed by the stack's `bbd9de082`)
- E-38 `Source/LinqToDB/Internal/Async/AsyncEnumeratorAsyncWrapper.cs` — the async counterpart of E-37 (A-8) — withdrawn by A-12: the stack keeps the class without a `LoadTransaction`, and the own delta does not touch it
- E-39 `Source/LinqToDB/Internal/Async/AsyncEnumerableAsyncWrapper.cs` — passes its `LoadTransaction` to E-38 (A-8) — withdrawn by A-12: the file no longer exists at the head
- E-40 `Source/LinqToDB/Internal/SqlProvider/SqlProviderFlags.cs` — `IsInsertOutputQuerySupported` moves to `DataMember` order 85, after the stack's 80-84 (A-8); to 87 after #6111 took 85-86 (2026-11-25 sync)
- E-41 `Source/LinqToDB/Remote/LinqService.cs:ValidateQuery` — with `AllowUpdates = false`, also refuses a statement that carries a `SqlDataModificationTable` (A-10, review round 1 MAJ001)
- E-42 `Source/LinqToDB/Internal/SqlProvider/BasicSqlBuilder.cs:BuildSql`, `BuildInsertQuery`, `BuildInsertQuery2` — the trailing set-operator loop of `BuildSql` becomes a `protected BuildSetOperators` helper, with a `PublicAPI.Unshipped.txt` entry, because a provider builder calls it and an out-of-tree provider that copies the insert body must be able to (`code-design.md` → *Provider-called core methods are public*; critic round 8). The insert paths call it right after `BuildSubQueryExtensions`, inside the `From.Tables.Count != 0` guard, so it runs before `RETURNING` / the identity clause. A builder flag, reset at the protected `BuildSql(statement, …)` entry, makes the trailing call skip operators already rendered. An override that does not call the helper keeps today's trailing placement (A-11, review round 2 MIN008)
- E-43 `Source/LinqToDB/Internal/DataProvider/MySql/MySqlSqlBuilder.cs:BuildInsertQuery` — the same helper call, since its override copies the base body and MariaDB renders `RETURNING` (A-11)
- E-44 `Source/LinqToDB/Internal/DataProvider/Ydb/YdbSqlOptimizer.cs:CorrectInsertStatement` — the target column names and `DoNotSetAliases` also go on every set-operator branch of the insert's source, because YQL combines `UNION` branches by column name (A-11, L-18)
- E-45 `Source/LinqToDB/Internal/DataProvider/PostgreSQL/PostgreSQLDataProvider.cs` — `SqlProviderFlags.IsInsertOutputQuerySupported = true` for every PostgreSQL version (D-7). The line has been in the diff since the rework; recorded by A-12
- E-46 `Tests/Linq/Update/InsertTests.cs:InsertConcat` — TO-35's plain-insert witness (A-11), with `ThrowsForProvider` for both Access drivers and, since `2a57acbd9`, Informix (L-17, A-12)
- E-47 `Tests/Linq/Update/InsertWithOutputTests.cs:InsertWithOutputFromConcatTest` — TO-32's multi-row `InsertWithOutput` arm (A-11); recorded by A-12

## P7 Impact map (M/L)

- `Source/LinqToDB/Internal/SqlQuery/Visitors/QueryElementVisitor.cs:3126` `VisitSqlTable` Transform downcast — covered by E-1, E-4
- `Source/LinqToDB/Internal/SqlQuery/Visitors/QueryElementVisitor.cs:169-214` `VisitCteClause` `DataModification` branches — covered by E-4
- `Source/LinqToDB/Internal/Remote/LinqServiceSerializer.cs:695-743` pre-registration visitor — covered by E-10
- `Source/LinqToDB/Internal/Remote/LinqServiceSerializer.cs:888-891` type registration — covered by E-10
- `Source/LinqToDB/Internal/Remote/LinqServiceSerializer.cs:1079-1182` and `:2282-2386` table writers and readers — covered by E-10
- `Source/LinqToDB/Internal/Remote/LinqServiceSerializer.cs:1454-1486` and `:2690-2716` `CteClause` with `DataModification` — covered by E-10
- `Source/LinqToDB/Internal/Remote/LinqServiceSerializer.cs:2073` "last statement wins" — out-of-scope (U-5)
- `Source/LinqToDB/Internal/SqlProvider/BasicSqlBuilder.cs:2004-2118`, `:3551-3561`, `:4745-4787` and `:4789-4866` table-type switches — covered by E-11
- `Source/LinqToDB/Internal/SqlProvider/BasicSqlBuilder.cs:569-583` and `:836` CTE body rendering and the `DataModification` branch — covered by E-11
- `Source/LinqToDB/Internal/SqlProvider/BasicSqlBuilder.cs:585-641` `BuildInsertQuery`/`BuildInsertQuery2` output emission — covered by E-11
- `Source/LinqToDB/Internal/SqlProvider/BasicSqlBuilder.cs:2234` and `:2254` hints on `is SqlTable` — out-of-scope (D-1)
- `Source/LinqToDB/Internal/DataProvider/PostgreSQL/PostgreSQLSqlBuilder.cs` overrides of `BuildInsertQuery` / output — Localized — searched `BuildInsertQuery|BuildOutputSubclause|OutputClause` in `PostgreSQLSqlBuilder.cs`, no override; E-11's render-local list is not bypassed
- `Source/LinqToDB/Internal/DataProvider/ClickHouse/ClickHouseSqlBuilder.cs:436` `BuildCteBody` override — out-of-scope (flag false; D-7 backstop)
- `Source/LinqToDB/Internal/DataProvider/Ydb/YdbSqlBuilder.cs:356-372` — covered by E-13
- `Source/LinqToDB/Internal/DataProvider/DB2LUW/DB2LUWSqlBuilder.cs:31-41` and the Oracle11/Firebird/MySql80/SapHana `SqlTableType.Function` branches — out-of-scope (they branch on `Function` only)
- `Source/LinqToDB/Internal/SqlProvider/BasicSqlOptimizer.cs:52-83` `Finalize` order — covered by E-12
- `Source/LinqToDB/Internal/SqlProvider/BasicSqlOptimizer.cs:92-115`, `:725-762` and `:765-799` (`FinalizeDataModificationCtes`, collector, `FinalizeCte`) — covered by E-12
- `Source/LinqToDB/Internal/SqlProvider/BasicSqlOptimizer.cs:992-1007` and `Source/LinqToDB/Internal/SqlQuery/SelectQuery.cs:347-350` `CloneQuery` — out-of-scope (U-3)
- `Source/LinqToDB/Internal/SqlProvider/JoinsOptimizer.cs:210-240` and `Source/LinqToDB/Internal/SqlQuery/Visitors/SelectQueryOptimizerVisitor.cs:1151-1178`, `:1613` and `:2925-2944` join removal — out-of-scope (U-4)
- `Source/LinqToDB/Internal/SqlQuery/Visitors/SelectQueryOptimizerVisitor.cs:3909-3928` — covered by E-7
- `Source/LinqToDB/Internal/SqlQuery/Visitors/SqlQueryColumnOptimizerVisitor.cs:69-103` — covered by E-6
- `Source/LinqToDB/Internal/SqlQuery/Visitors/SqlQueryColumnNestingCorrector.cs:145`, `:224-252` and `:317-339` — covered by E-25
- `Source/LinqToDB/Internal/SqlQuery/Visitors/SqlQueryValidatorVisitor.cs:380-429` — out-of-scope (benign on PostgreSQL; P10 L-4)
- `Source/LinqToDB/Internal/SqlQuery/Visitors/SqlQueryColumnUsageCollector.cs:84-123` and `:284-294` — out-of-scope (unreferenced in `Source` apart from PublicAPI)
- `Source/LinqToDB/Internal/SqlQuery/Visitors/SqlQueryCloneVisitor.cs:37-78` and `Source/LinqToDB/Internal/SqlQuery/Visitors/SqlQueryCloneVisitorBase.cs:5-31` — covered by E-5, E-4
- `Source/LinqToDB/Internal/DataProvider/AliasesHelper.cs:174-240` — covered by E-23
- `Source/LinqToDB/Internal/SqlQuery/SqlWithClause.cs:82` and `:121-131` — covered by E-9
- `Source/LinqToDB/Internal/SqlQuery/CteClause.cs:33` and `:105-110` — covered by E-8
- `Source/LinqToDB/Internal/SqlQuery/QueryHelper.cs:1081-1088` and `Source/LinqToDB/Internal/SqlProvider/JoinsOptimizer.RemoveDuplicates.cs:93,106` — out-of-scope (subclass rejected by `GetType()`)
- `Source/LinqToDB/Internal/SqlQuery/SqlTable.cs:233-244` `Equals` — covered by E-1
- `Source/LinqToDB/Sql/Sql.Expressions.cs:346-363` — out-of-scope (D-1)
- `Source/LinqToDB/Internal/Linq/Builder/CteContext.cs:85` and `:154-168` — covered by E-15 (revert); an association resolves at the reference (`CteTableContext.cs:78-79`, A-2), and E-12's projection check is only D-5's backstop
- `Source/LinqToDB/Internal/Linq/Builder/TableBuilder.cs:17` `BuildsMethodCall` CTE method set — covered by E-17 and E-36: `CteConstantsPattern.IsCteDefiningCall` keeps its own list of the four names, a second copy of the builder's dispatch (D-4 failure mode)
- `Source/LinqToDB/Internal/Linq/Builder/TableBuilder.CteTableContext.cs:11-67` — out-of-scope (unchanged pattern reused)
- `Source/LinqToDB/Internal/Linq/Builder/ExpressionBuildVisitor.cs:440-455` CTE registry — out-of-scope (unchanged)
- `Source/LinqToDB/Internal/Linq/Builder/TableBuilder.TableContext.cs:96-114` and `:200-211` — out-of-scope (A-3): the output table's type always yields a null predicate; no edit
- `Source/LinqToDB/Internal/Linq/Builder/ExpressionBuilder.cs:227-326` and `:396-430` — covered by E-17
- `Source/LinqToDB/Internal/Linq/Builder/ExpressionBuilder.EagerLoad.cs:549`, `:622` and `:688` — covered by E-18
- `Source/LinqToDB/Internal/Linq/Builder/Visitors/ExposeExpressionVisitor.cs:539-647` and `:144-152` — covered by E-26
- `Source/LinqToDB/Internal/Linq/ExpressionCacheManager.cs:449-481` and `:616-634` — covered by E-27
- `Source/LinqToDB/Internal/Linq/Query.cs:62-111` cache compare — out-of-scope (consumes `ComparisionFunctions` as is)
- `Source/LinqToDB/Internal/Linq/Query.cs:203-263` load transaction — was covered by E-28; out-of-scope since A-12 (stack-owned; `git diff --stat 8bf07d878 origin/pr/6133 -- Source` lists no `Query.cs`), consumed by D-10. See the `Query.cs:237-281` row
- `Source/LinqToDB/Internal/Linq/ExpressionQuery.cs` load-transaction sites (element, `ExecuteAsyncEnumerable`, `GetForEachCoreAsync`, `GetAsyncEnumerator`, both `GetEnumerator`) — was covered by E-29; out-of-scope since A-12: stack-owned and buffered (`:130`, `:142`, `:172-177`, `:211-215`, `:248-253`, `:311`, `:324`, `:344`, `:357`, `:396-401`), not in the own delta
- `Source/LinqToDB/Internal/Linq/EnumeratorWrapper.cs`, `Source/LinqToDB/Internal/Async/AsyncEnumeratorAsyncWrapper.cs` and `AsyncEnumerableAsyncWrapper.cs` — was covered by E-37, E-38, E-39; since A-12 only `AsyncEnumeratorAsyncWrapper.cs` exists (`git ls-tree origin/pr/6133`), without a `LoadTransaction`; out-of-scope
- `Source/LinqToDB/Internal/Linq/CompiledTable{T}.cs:185` and `:204` — was covered by E-30; out-of-scope since A-12 (stack-owned, now `:187`, `:219`)
- `Source/LinqToDB/Internal/Linq/Query{T}.cs:40` and `:208` `DoNotCache` — out-of-scope (not used any more)
- `Source/LinqToDB/Internal/Linq/Harvester.cs` (was `Preamble.cs:9-22`) and the nine harvester subclasses, the eight below plus the stack's `KeysDataSlotHarvester` (`ExpressionBuilder.EagerLoadDefault.cs:159,201`; `ExpressionBuilder.EagerLoadKeyedQuery.cs:962,1033,1415,1453`; `ExpressionBuilder.EagerLoadUnion.cs:1602,1820`) — covered by E-32, E-33, E-34, E-35
- `Source/LinqToDB/Internal/Linq/Builder/ExpressionBuilder.EagerLoadKeyedQuery.cs:1044-1047` (`SetRunQueryWithKeyedQueryBuffer` fallback) and `:1160` (`SetupKeyedQueryBuffer` fallback) — out-of-scope as code; detected by D-6 (U-16), TO-24
- `Source/LinqToDB/Internal/Linq/Query{T}.cs:262-266` `validateSubqueries` retry sharing the `ParametersContext` — covered by E-27 (registration flag)
- `Source/LinqToDB/Internal/SqlProvider/SqlProviderFlags.cs` `IsInsertOutputQuerySupported` — covered by E-40 (order 87; 80-87 distinct). `Source/LinqToDB/Internal/DataProvider/PostgreSQL/PostgreSQLDataProvider.cs:72` — covered by E-45 (the flag's only setter: `git grep -n "IsInsertOutputQuerySupported" origin/pr/6133 -- Source` finds it there, at the property, in `GetHashCode` / `Equals` and in `InsertBuilder.cs:287`; A-12)
- `Source/LinqToDB/Internal/Linq/Query.cs:237-281` `StartLoadTransaction` / `StartLoadTransactionAsync` (#6456, arrived with the `c79b830e8` restack) — out-of-scope as code, consumed by D-10. Searched `git grep -n -E "StartLoadTransaction|new LoadTransaction\(|LoadTransaction\.WithoutTransaction|EagerLoadingIsolationLevel" origin/pr/6133 -- Source/LinqToDB/Internal Source/LinqToDB/LinqExtensions`: they are the only openers of the implicit load transaction, and `BeginTransaction(` appears elsewhere under `Internal/Linq` only in `Query.cs`, so the `QueryBatch` path (TO-29) and the compiled sites (`CompiledTable{T}.cs:187`, `:219`; E-30 withdrawn) share them. With the option off they return the shared `LoadTransaction.WithoutTransaction`, whose `Complete` is a no-op; with it on, the transaction opens at `EagerLoadingIsolationLevel ?? DefaultMultiQueryIsolationLevel` (`:277-281`), and the insert runs at that level (L-22, L-23) (A-12)
- `Source/LinqToDB/Internal/Common/ErrorHelper.cs:30-32` — covered by E-20
- `Source/LinqToDB/PublicAPI/PublicAPI.Unshipped.txt` — covered by E-21
- `Source/LinqToDB/LinqExtensions/LinqExtensions.Insert.cs:1139-1260` — covered by E-19
- Unreachable surfaces: the wiki/docs (no page yet; release notes at merge) and the PR body owned by to11mtm (follow-up comment instead) — out-of-scope
- `Source/LinqToDB/Remote/LinqService.cs:75` `ValidateQuery` — covered by E-41; called from all four service entry points (`:117`, `:149`, `:212`, `:249`), so one refusal covers every remote path (A-10)
- `Source/LinqToDB/Internal/SqlProvider/BasicSqlBuilder.cs:251-282` trailing set-operator loop, now `BuildSetOperators` — covered by E-42. Callers and overrides searched (`override … BuildInsertQuery|BuildSql(|BuildSql()`): SQL Server calls the base insert path; MySQL copies it (E-43); ClickHouse copies it without output and keeps the trailing placement; DB2, Informix and YDB override `BuildSql(statement, …)` and call the base; PostgreSQL and MySQL override `BuildSql()` with `BuildSqlForUnion` (L-13) (A-11)
- `Source/LinqToDB/Internal/DataProvider/Ydb/YdbSqlOptimizer.cs:42-56` `CorrectInsertStatement` — covered by E-44; `Source/LinqToDB/Internal/DataProvider/AliasesHelper.cs:267-279` copies branch aliases only when the first query is not `DoNotSetAliases`, which is why the optimizer sets every branch itself (A-11)
- `Source/LinqToDB/Internal/Linq/CteConstantsPattern.cs:42` `TryCreate` and `Source/LinqToDB/Internal/Linq/Builder/ExpressionBuilder.cs:321` `CollectDataModificationCalls` — covered by E-36 and E-17 (allocation-free `Find` pre-check, A-11). For `CollectDataModificationCalls`, the old `Visit` and the new `Find` walk the same nodes in a user tree. For `TryCreate`, `Path` also descends into an `IQueryable` held in a constant (`PathVisitor.cs:233-247`) and `Find` does not; the pre-check holds because its input is the exposed tree, where expose has inlined every queryable constant (`ExposeExpressionVisitor.cs:945-960`, L-20)

## P8 Test obligations (M/L)

DML tests go in `Tests/Linq/Update/InsertWithOutputQueryTests.cs`, using the fixture's models plus an identity table, a TPH model and an associated table defined in the fixture. Shapes that must share the query cache run in one test method.

- TO-1 Shape A inserts 1 row and returns `[v,v]` — providers: AllPostgreSQL, direct and LinqService — proof: characterization (green on the PR head)
- TO-2 A, then B, in one test: B returns its two values and inserts 2 rows. The PR head answers `[12,12]` and 1 row (probe `AB_CacheConflation`) — providers: AllPostgreSQL, direct and LinqService — proof: red→green
- TO-3 B, then A, in one test: A inserts 1 row. The PR head answers 2 (probe `BA_CacheConflation`) — providers: AllPostgreSQL, direct and LinqService — proof: red→green
- TO-4 Shape D inserts 2 rows with distinct ids. The PR head answers 1 (probe `D_TwoInsertsSameScope`) — providers: AllPostgreSQL, direct and LinqService — proof: red→green
- TO-5 `CompiledQuery` with one raw call returns `v`; invoked with two values, it inserts twice. The PR head throws `NotRead` (probe `G2_Compiled`) — providers: AllPostgreSQL, direct — proof: red→green
- TO-6 `CompiledQuery` with two identical raw calls via `Concat` inserts 2 rows per invocation — providers: AllPostgreSQL, direct — proof: red→green (the PR head throws `NotRead`)
- TO-7 Keep-alive: `source.Select(s => new { s.Id, N = inserted.Count() }).Select(x => x.Id)` returns the ids and inserts 3 rows (`UnreadOutputStillInserts`; the PR head throws `NotRead`). `CapturedConditionRemovesOutput` keeps 3 rows for `flag: true` and 0 for `flag: false` — providers: AllPostgreSQL, direct and LinqService — proof: red→green (unread arm), characterization (flag arms)
- TO-8 Duplicate guard: with E-14 mutated to register a fresh CTE under a new key per build while keeping the token (mutation "InsertBuilder registers under a new key per build"), `OutputReferencedTwiceInsertsOnce` throws `Error_OutputQuery_Duplicated`. Without the mutation it passes. (`Dictionary.Add` at `ExpressionBuildVisitor.cs:444` rules out a skip-the-lookup mutation) — providers: PostgreSQL.16, direct — proof: control
- TO-9 `git diff 4d7b0a4d1a --` (the stack head; `origin/master` before A-8) on `CteClause.cs`, `SqlWithClause.cs`, `SqlQueryCloneVisitor.cs`, `YdbSqlBuilder.cs` and `CteContext.cs` is empty. The `CteClause` parts of `QueryElementVisitor.cs`, `LinqServiceSerializer.cs` and `SqlQueryColumnOptimizerVisitor.cs` equal master — providers: n/a (diff), with TO-13 for runtime — proof: characterization
- TO-10 Every existing `InsertWithOutputQueryTests` case passes, with SQL equal to the PR head's baselines (baselines PR #2165, PostgreSQL 9.2-18; alias renumbering reviewed under G-02), including `FromQuery_SequenceIdentity`, `FromQuery_PreV18Dialect`, `SingleRecord_*`, `OutputFeedsInsert/Update`, `GeneratedKeysJoinedBackToInput`, `OutputInSubqueryPredicate` and the eager-load guards — providers: PostgreSQL.16 locally (PostgreSQL.18 if available, else CI), direct and LinqService — proof: characterization
- TO-11 TPH: insert into `ITable<Derived>` with a non-default discriminator code returns the inserted rows, with no `WHERE` in the CTE. A-3: the planned E-16 control could not disagree, because no target type produces the predicate — providers: AllPostgreSQL, direct — proof: characterization
- TO-12 `NotSupported` and `NotSupported_Remote` throw `Error_OutputQuery_NotSupported` on every non-PostgreSQL provider (the same message from any gate; SC-13 asks only for build-time refusal) — providers: SQLite.MS, SQLite.Classic, Access ACE ODBC and SqlCe locally; the rest CI — proof: characterization
- TO-13 `Tests/Linq/Linq/CteTests` full fixture green — providers: SQLite.MS and PostgreSQL.16, direct and LinqService — proof: characterization (symmetry guard on the unchanged CTE path)
- TO-14 Chained calls insert into t1 and t2 once each, with t1's CTE first — providers: AllPostgreSQL, direct and LinqService — proof: characterization
- TO-15 An inline call in a query lambda inserts 1 row and returns 1 (probe `G_InlineInLambda`) — providers: AllPostgreSQL, direct and LinqService — proof: characterization
- TO-16 UPDATE and IN-list consumers insert once (existing, in TO-10) — providers: AllPostgreSQL — proof: characterization
- TO-17 `inserted.Count()` as the whole query inserts 3 rows and returns 3 — providers: AllPostgreSQL, direct and LinqService — proof: characterization (pins D-5's non-field rule)
- TO-18 `AssociationOverOutput`: an association over the output returns the parents' `ValueStr` (`Str1..Str3`) and inserts 3 rows. Measured green on the PR head, with the join outside the CTE (A-2) — providers: AllPostgreSQL, direct and LinqService — proof: characterization
- TO-19 Plain `AsCte`, three arms, each also run in reverse order. Closure arm: `c.Concat(c)`, then `MakeCte(t, 2).Concat(MakeCte(t, 3))` in one test, return `[1,1]` and `[2,3]`; master answers `[2,2]` for the second (probe H on `a1fee89c52`). Scalar-literal arm (U-19): `var q = t.Where(p => p.Id > 3).AsCte(); q.Concat(q)`, then `t.Where(p => p.Id > 3).AsCte().Concat(t.Where(p => p.Id > 4).AsCte())`, which must return the `> 3` rows plus the `> 4` rows. Value-merge arm: two separately written `Where(p => p.Id > 3).AsCte()` (merged by value), followed by a `> 3` / `> 4` pair that must not reuse the merged plan — providers: SQLite.MS and PostgreSQL.16, direct and LinqService — proof: red→green (closure arm measured red on master; scalar and value-merge arms predicted red, measured before the fix)
- TO-20 Caching still hits: the same DML query shape executed twice with fresh `IQueryable`s (fresh tokens) adds one cache miss, measured through `Query<T>` cache-miss counting. A DoNotCache-style mutation (mutation "DoNotCache = true for DML queries") makes it two — providers: PostgreSQL.16, direct — proof: control
- TO-21 A correlated call throws `Error_OutputQuery_Correlated` at build. On the PR head the same shape throws a different error — providers: AllPostgreSQL, direct — proof: red→green
- TO-22 Eager load over the output (`KeyedQuery`, children from another table keyed to the output) leaves the inserted rows present after the query, and one `BeginTransaction` plus one `CommitTransaction` are traced (`TraceOperation`, as in `ElementFormLoadWithOpensLoadTransaction`). There are three arms: `ToList()` (the sync `IEnumerable` site), `ToListAsync()` (the async site) and an element-typed compiled query ending in `.First()` (the `CompiledTable.Execute` site, `CompiledTable{T}.cs:187` since A-12). A `ToList()`-typed compiled lambda enumerates through the `ExpressionQuery` sites instead (`CompiledQuery.cs:163-176, 301-307`) and would leave the compiled element site unexercised. With `Complete()` removed (mutation "LoadTransaction.Complete not called"), the rows are gone. Re-proved by A-12 on the stack's code, mutation "LoadTransaction.Complete never commits" (`Query.cs:314-338`; G-01) — providers: PostgreSQL.16, direct — proof: control
- TO-23 Compiled conditional: `CompiledQuery.Compile((DataConnection dc, bool flag) => src.Where(s => s.Id == 2).Select(s => flag ? dc.GetTable<T>().InsertWithOutputQuery(…).Count() : 0).First())` inserts once for `flag: true` and once for `flag: false` (U-15). The normal-path arm, `CapturedConditionRemovesOutput`, inserts 0 for `false` — providers: AllPostgreSQL, direct — proof: characterization (pins the documented divergence of the two paths)
- TO-24 Preamble duplicate guard: with the `SetRunQueryWithKeyedQueryBuffer` fallback forced (mutation "EagerLoadKeyedQuery buffer fallback taken": the `placeholders.Count == 0` fallback to `sequence.SetRunQuery`, `ExpressionBuilder.EagerLoadKeyedQuery.cs:1044-1047`), `EagerLoadOverOutputInsertsOnce` throws `Error_OutputQuery_Duplicated` instead of inserting twice. Without the mutation it passes — providers: PostgreSQL.16, direct — proof: control
- TO-25 (A-7) A query with two CTE-defining calls still hits the cache when built again with fresh `IQueryable`s: `CteTests.CacheTwoCapturedCtesHit` (plain `AsCte`) and `TwoOutputQueriesAreCached` (two `InsertWithOutputQuery` calls), both `[QueryCacheTest]`. With `Compute` returning a fresh value each time (mutation "CteConstantsPattern.Compute never repeats"), both miss — providers: PostgreSQL.16 (both tests, direct and LinqService for the CTE one) and SQLite.MS (CTE) — proof: control
- TO-26 (A-7, re-derived by A-8) An eager-loading DML query commits when its enumeration ends, whether completed or after an early `break`, in sync and async enumeration and through `ForEachAsync`. Afterwards the connection holds no transaction and the 3 rows persist: `EagerLoadOverOutputCommitsWhenEnumerationEnds`. With the wrappers never completing (mutation "enumerator wrappers never complete"), the four wrapper arms lose their rows. Re-proved by A-12 on the stack's buffered sites: with no `Complete` / `CompleteAsync` at `ExpressionQuery.cs:177`, `:215`, `:253`, `:401` (mutation "buffered enumeration sites never commit"), all five arms lose their rows — providers: PostgreSQL.16, direct — proof: control
- TO-27 (A-8) A materialization failure in an eager-loading DML query rolls the insert back: `EagerLoadOverOutputRollsBackOnFailure`, with `ToList()`, `await foreach` and `ForEachAsync` arms, leaves 0 rows and no transaction. With the wrappers ignoring the fault (mutation "enumerator wrappers complete after a fault"), the `ToList()` and `await foreach` arms keep the rows. Re-proved by A-12 on the stack's buffered sites: with `Complete` / `CompleteAsync` moved before the buffering at the same four sites (mutation "commit before buffering"), all three arms keep 3 rows — providers: PostgreSQL.16, direct — proof: control
- TO-28 (A-8, critic round 5) The streamed shape commits after its reader closes. A child that does not read the output is detached, so the main query streams the insert with its reader open. `EagerLoadOverOutputWithDetachedChildCommitsAfterReader` runs it with `UseCombinedCommands` on and off, with `ToList()`, `Break` and `AsyncBreak` arms, and asserts 3 rows, one traced `CommitTransaction` and no transaction left. With a wrapper completing before its inner enumerator closes (mutation "wrapper commits with the reader open"), the matching `Break` / `AsyncBreak` arms fail with `NpgsqlOperationInProgressException`. Since A-12 the stack buffers, so the reader is always closed before the commit and the order mutation has no code to act on. The test still has a control: under "buffered enumeration sites never commit" (TO-26) all six arms fail on `committed` (0 instead of 1) — providers: PostgreSQL.16, direct — proof: control (commit), characterization (order)
- TO-29 (A-9, critic round 6) The stack's `QueryBatch` entry point. `QueryBatchWithOutputCount` puts a scalar over the output beside an independent collection, and asserts 3 inserted rows, the collection, one traced `CommitTransaction` and no transaction left. With `LoadTransaction.Complete` never committing (mutation "LoadTransaction never commits"), the batch loses its rows. `QueryBatchWithOutputCollectionThrows` puts a collection over the output in a batch and asserts `Error_OutputQuery_EagerLoad` with nothing inserted — providers: PostgreSQL.16, direct — proof: control (count), characterization (refusal)
- TO-30 (A-10) A read-only `LinqService` refuses an output query: `ReadOnlyServiceRefusesOutputQuery`, with a plain `Insert` as the control, nothing written. `MaterializationFailureKeepsInsert` pins that, without eager loading and outside a transaction, a read failure keeps the insert — providers: PostgreSQL.16, direct (other versions in CI) — proof: red→green (refusal, red before `545a7d49f8`), characterization (keeps insert)
- TO-31 (A-11, MIN005) `Sql.Property` over a column the entity does not map, read from the output, returns the column instead of throwing `Field '…' not found`. The entity maps a subset of a table that has the extra column — providers: PostgreSQL.16, direct and LinqService (other versions in CI) — proof: red→green
- TO-32 (A-11, MIN008) A `Concat` source inserts all rows and returns them: `InsertWithOutputTests.InsertWithOutputFromConcatTest` (the fixture's multi-row output set) and `InsertWithOutputQueryTests.ConcatSourceOutput`. The red is proven only for providers that render `RETURNING` after the source. Measured red before E-42 with the syntax error at `UNION`: SQLite.MS and DuckDB, direct and LinqService; PostgreSQL 18 per the reviewer. SQL Server is not red, because `OUTPUT` precedes the source. After E-42: green on PostgreSQL.16, SqlServer.2022.MS, MariaDB.11, SQLite.MS and DuckDB, direct and LinqService. PostgreSQL.16 was red under the mutation with `42601` at `UNION`. YDB then failed for another reason (L-18), fixed by E-44: the same test's YDB arm is red→green across E-44. Firebird 5 is left to CI — providers: PostgreSQL.16, SqlServer.2022.MS, MariaDB.11, SQLite.MS, DuckDB, YDB — proof: red→green (RETURNING providers)
- TO-35 (A-11, critic round 7) The plain insert's text does not change: `InsertTests.InsertConcat` inserts from `Concat` with a plain setter, so the set operator stays on the insert's own source. `InsertUnion1` cannot see the path, because its computed setter puts the union in a derived table. The baselines with E-42 and with its insert-path calls removed (mutation "BuildSetOperators not called from the insert path") are byte-identical. ClickHouse and SQL Server, the trailing and the `OUTPUT`-first sides, run in CI. Measured: under the mutation the control `InsertWithOutputFromConcatTest` goes red again and `InsertConcat`'s SQLite.MS / DuckDB baselines are byte-identical. Access.Ace.Odbc fails with the same `Syntax error (missing operator)` with and without E-42 (L-17) — providers: SQLite.MS, DuckDB, Access.Ace.Odbc — proof: characterization
- TO-33 (A-11, SUG003) `CorrelatedCallThrows` gains a source-overload arm (`other.Where(o => o.Id == s.Id).InsertWithOutputQuery(...)` inside `Select(s => ...)`) — providers: PostgreSQL.16, direct (other versions in CI) — proof: characterization
- TO-34 (A-11, MIN007) `EagerLoadOverOutputInsertsOnce` and `EagerLoadOverOutput_UnionStrategyMarker` run without `DisableBaseline` on the remote arm and report no direct-vs-remote mismatch. The check fires only in a combined `X` + `X.LinqService` run with `BaselinesPath` set (`c:\GitHub\linq2db.bls`). Its negative was observed under A-5, before `ec94a2892c`, when the direct trace carried `CommitTransaction` — providers: PostgreSQL.16, direct and LinqService in one run (other versions in CI) — proof: characterization
- TO-36 (A-12, `af52f547d`) With `UseEagerLoadingTransaction(false)`, an eager load over the output opens no transaction, and the insert survives a materialization failure: `EagerLoadOverOutputWithoutLoadTransaction`, `[Values] bool fail`, asserts no traced `BeginTransaction`, no transaction left, and 3 rows for both arms. With the sync `StartLoadTransaction` ignoring the option (mutation "load transaction opened although the option is off", `Query.cs:244`), both arms fail first on the `BeginTransaction` count (`begun` 1). The async opener (`:262`) and the compiled element sites (`CompiledTable{T}.cs:187`, `:219`) with the option off are owned by master's `EagerLoadingTransactionTests` (`ExecuteAsyncEnumerable`, `AwaitForeach`, `CompiledElement`, each `[Values] bool useTransaction`), which this PR does not change — providers: PostgreSQL.16, direct (a `DataConnection` option; L-8 covers remote) — proof: control

## P9 Verification gates

- G-01: blocked — CI for PostgreSQL other than 16 and for every container provider. Local runs on `1487fd230c` and, after A-7, on `5309315ff3` (logs in the session scratchpad) are below.
  - After A-7, on `5309315ff3`. PostgreSQL.16, `InsertWithOutputQueryTests` + `CteTests` + `EagerLoad*`: 559 passed, 4 skipped (`review_pg16.log`). SQLite.MS, the same set + `TransactionTests`: 556 passed, 13 skipped (`review_sqlite.log`). After the TO-25 probe was reverted, `InsertWithOutputQueryTests` + `CteTests.Cache*` on PostgreSQL.16: 82/82 (`final_pg16.log`).
  - TO-25, mutation "CteConstantsPattern.Compute never repeats": `CacheTwoCapturedCtesHit` (direct and LinqService) and `TwoOutputQueriesAreCached` miss. `OutputQueryIsCached` stays green, which is the gap MIN003 named (`mut_min003.log`).
  - A-7's TO-26 was red on both arms before the `LoadTransaction` fix (`min005_red.log`) and green after it. A-8 replaced it.
  - After A-8, on `b94919f94b` (restacked on #6111). The stack alone, `4d7b0a4d1a`, SQLite.MS, `QueryBatchTests` + `SelectScalarTests` + `EagerLoadingTests` + `InsertWithIdentity*`: 491 passed, 6 skipped (`stack_sqlite.log`). This branch, PostgreSQL.16, `InsertWithOutputQueryTests` + `CteTests` + `EagerLoad*` + `LoadWith*` + `QueryBatch*` + `*WithOutputTests` + `MergeTests`: 1343 passed, 15 skipped, 0 failed of 1358 (`restack_reg_pg16.log`). SQLite.MS, `InsertWithOutputQueryTests` + `CteTests` + `EagerLoad*` + `LoadWith*` + `QueryBatch*` + `TransactionTests` + `SelectScalarTests`: 964 passed, 17 skipped, 0 failed of 981 (`restack_reg_sqlite.log`).
  - TO-26 and TO-27 after A-8 (`d10s_green.log`, `d10s_mut_fault.log`, `d10s_mut_nocomplete.log`):
    - TO-26, mutation "enumerator wrappers never complete": the four wrapper arms of `EagerLoadOverOutputCommitsWhenEnumerationEnds` fail, and the `ForEachAsync` arm passes, because it completes in `GetForEachCoreAsync`.
    - TO-27, mutation "enumerator wrappers complete after a fault": the `ToList()` and `await foreach` arms of `EagerLoadOverOutputRollsBackOnFailure` fail, and the `ForEachAsync` arm passes on its own path.
    - Before the third arm was added, the `ToListAsync()` arm passed under the fault mutation, because it does not use the async wrapper. That is why `await foreach` is now an explicit arm.
  - TO-28 on `5e8869085e` (`to28_green.log`, `to28b_green.log`): 6/6 green. The mutation "wrapper commits with the reader open" in `EnumeratorWrapper` fails both `Break` arms, combined and not, with `NpgsqlOperationInProgressException: A command is already in progress` (`to28_mut.log`); TO-26 stays green under it, because buffer mode has no open reader. The same mutation in `AsyncEnumeratorAsyncWrapper` fails both `AsyncBreak` arms (`to28b_mut.log`). The full `InsertWithOutputQueryTests` fixture afterwards: 80/80 (`restack3_pg16.log`).
  - After A-9, the pre-restack controls were re-run on the restacked tree. The earlier logs predate the stack's edits to `EagerLoadKeyedQuery.cs`, `Query{T}.cs` and `ExpressionCacheManager.cs`. Each control was red under its mutation, and the tree was rebuilt clean afterwards (`.build/.agents/pr5982-controls.ps1`, logs `ctl_<name>.log`):
    - TO-8, mutation "InsertBuilder registers under a new key per build": `OutputReferencedTwiceInsertsOnce` throws `Error_OutputQuery_Duplicated`, direct and LinqService.
    - TO-20, mutation "DoNotCache = true for DML queries": `OutputQueryIsCached` misses.
    - TO-24, mutation "EagerLoadKeyedQuery buffer fallback taken" (now `:1044-1047`): `EagerLoadOverOutputInsertsOnce` throws `Error_OutputQuery_Duplicated`, direct and LinqService.
    - TO-25, mutation "CteConstantsPattern.Compute never repeats": `TwoOutputQueriesAreCached` and `CacheTwoCapturedCtesHit` miss, direct and LinqService.
    - TO-29, mutation "LoadTransaction never commits": `QueryBatchWithOutputCount` fails on the commit count. Unmutated, both TO-29 tests are green (`qb_green.log`).
  - TO-12 after the restack, on SQLite.Classic, Access.Ace.Odbc and SqlCe: 6/6 each (`to12r_<provider>.log`). SQLite.MS is in `restack_reg_sqlite.log`.
  - Sweep against the stack head: `test-diff-sweep.ps1 -Repo . -Base 4d7b0a4d1a -IncludeWorkingTree`: 0 chains, 0 nested, 41 narrowed sets (all `AllPostgreSQL`).
  - PostgreSQL.16, direct and LinqService. `InsertWithOutputQueryTests` + `CteTests`: 187 passed, 1 skipped, the existing `[ActiveIssue]` in `CteTests` (`fmt_pg16.log`). `InsertWithOutputQueryTests` + `EagerLoad*` + `LoadWith*`: 498 passed, 3 skipped (`d10b_pg16.log`). `InsertWithOutputTests` / `UpdateWithOutputTests` / `DeleteWithOutputTests` / `MergeTests`, on the rework commit: 534 passed, 7 skipped (`regress_pg16.log`).
  - SQLite.MS. The full `Tests/Linq`: 12104 tests, 11852 passed, 242 skipped, 10 failed (`full_sqlite.log`). The 10 are `SQLiteTests.DateTimeRoundtrip_BulkCopyUtc` ×8 and `DateTimeRoundtrip_InsertUtc` ×2, all `[ActiveIssue(2107)]` with an `ErrorMessage` signature. On this host (FLE, UTC+2) the value assertion fails first: expected `13:12`, got `11:12`, which is exactly the UTC offset. The gate expects the `Kind` assertion that fails first under CI's UTC. The branch touches neither `SQLiteTests.cs` nor the SQLite provider. Not run on master, so this is host-dependent by mechanism, not by bisection. `InsertWithOutputQueryTests` + `CteTests` after the layout commit: 130/130 (`fmt_sqlite.log`). `EagerLoad*` + `LoadWith*` + `TransactionTests` + the DML fixture after D-10: 530 passed, 13 skipped (`d10_sqlite.log`).
  - TO-12 on SQLite.MS, SQLite.Classic, Access.Ace.Odbc and SqlCe, direct and LinqService: `NotSupported`, `NotSupported_Remote` and `OutputAsSourceSurface` green (`to12_<provider>.log`).
  - Tests per obligation: TO-1/TO-2 `OneQueryableTwiceThenTwoCalls`; TO-3 `TwoCallsThenOneQueryableTwice`; TO-4 `TwoIdenticalCallsInsertTwice`; TO-5 `CompiledQueryInsertsPerInvocation`; TO-6 `CompiledQueryTwoIdenticalCalls`; TO-7 `UnreadOutputStillInserts`, `CapturedConditionRemovesOutput`; TO-8 `OutputReferencedTwiceInsertsOnce`; TO-9 `git diff 4d7b0a4d1a` on the five files is empty; TO-10 the PR's existing `InsertWithOutputQueryTests` cases; TO-11 `DerivedTypeTarget`; TO-12 `NotSupported`, `NotSupported_Remote`, `OutputAsSourceSurface`; TO-13 `CteTests`; TO-14 `ChainedOutputQueries`; TO-15 `InlineCallInQueryLambda`; TO-16 `OutputFeedsUpdate`, `OutputInSubqueryPredicate`; TO-17 `OutputCountOnly`; TO-18 `AssociationOverOutput`; TO-19 the six `CteTests.Cache*` tests; TO-20 `OutputQueryIsCached`; TO-21 `CorrelatedCallThrows`; TO-22 `EagerLoadOverOutputCommitsLoadTransaction` (three arms); TO-23 `CompiledConditionKeepsInsert`, `CapturedConditionRemovesOutput`; TO-24 `EagerLoadOverOutputInsertsOnce`; TO-25 `CacheTwoCapturedCtesHit`, `TwoOutputQueriesAreCached`; TO-26 `EagerLoadOverOutputCommitsWhenEnumerationEnds`; TO-27 `EagerLoadOverOutputRollsBackOnFailure`; TO-28 `EagerLoadOverOutputWithDetachedChildCommitsAfterReader`; TO-29 `QueryBatchWithOutputCount`, `QueryBatchWithOutputCollectionThrows`.
  - Proof modes: red→green for TO-2..TO-7, TO-19 and TO-21 (`red_pg16.log`, `red_sqlite.log` on the test commit `51ee396f6a`). The cache commit turned TO-2/TO-3 and TO-19 green (`cache_pg16.log`, `cache_sqlite.log`), and the rework turned the rest green.
  - Controls, each red under its mutation and green after revert, on PostgreSQL.16:
    - TO-8, mutation "InsertBuilder registers under a new key per build": `OutputReferencedTwiceInsertsOnce` throws `Error_OutputQuery_Duplicated`, direct and LinqService (`mut_to8.log`).
    - TO-20, mutation "DoNotCache = true for DML queries": `OutputQueryIsCached` sees one extra miss (`mut_to20.log`).
    - TO-22, mutation "LoadTransaction.Complete not called": all three arms fail on `events.Count()`, because the insert rolls back (`d10_mut.log`).
    - TO-24, mutation "EagerLoadKeyedQuery buffer fallback taken": `EagerLoadOverOutputInsertsOnce` throws `Error_OutputQuery_Duplicated` (`mut_to24.log`).
    - TO-11's control could not disagree, so A-3 turned it into a characterization.
  - Sweep (A-6): `test-diff-sweep.ps1 -Repo . -IncludeWorkingTree` on the implemented tree: 0 one-line chains, 0 nested chains, 35 narrowed sets (all `AllPostgreSQL`).
  - After A-11, on `0d2c5ad157` plus the working tree (results under `.build/.agents/pr6133-*.json`):
    - PostgreSQL.16, direct and LinqService in one run, `InsertWithOutputQueryTests` + `CteTests` + the Concat tests: 219 passed, 1 skipped, 0 failed (`pr6133-pg16.json`).
    - File providers, `InsertTests` + `InsertWithOutputTests` + `CteTests` + every Union/Concat/SetOperation test: SQLite.MS 1274 passed, DuckDB 1226, Access.Ace.Odbc 834, 0 failed (`pr6133-fileproviders-sweep.json`).
    - The Concat tests: SqlServer.2022.MS 8/8 (`pr6133-crossprov.json`), MariaDB.11 8/8 (`pr6133-ydb-maria.json`). YDB after E-44, with the insert and set-operator tests: 964 passed, 8 skipped, 4 failed, all `Insert11` / `Insert12` (L-19) (`pr6133-ydb-fix.json`).
    - Tests per obligation:
      - TO-30: `ReadOnlyServiceRefusesOutputQuery`, `MaterializationFailureKeepsInsert`.
      - TO-31: `DynamicColumnOverOutput`.
      - TO-32: `InsertWithOutputFromConcatTest`, `ConcatSourceOutput`.
      - TO-33: `CorrelatedCallThrows` (the `fromSource` arm).
      - TO-34: `EagerLoadOverOutputInsertsOnce`, `EagerLoadOverOutput_UnionStrategyMarker`.
      - TO-35: `InsertConcat`.
    - TO-30 was red before `545a7d49f8` (A-10).
    - TO-31 and TO-32 red, with E-11's dynamic branch and E-42's insert-path calls removed, on PostgreSQL.16 direct and LinqService (`pr6133-pg16-red.json`):
      - `DynamicColumnOverOutput` throws `Field 'Id' not found`.
      - `ConcatSourceOutput` and `InsertWithOutputFromConcatTest` fail with `42601` at `UNION`, 6 of 6 cases.
    - SQLite.MS and DuckDB were red with the syntax error at `UNION` before E-42 (`pr6133-min008-red.json`). YDB's arm was red before E-44 with `SELECT have 3 columns, UPDATE expects: 4` (`pr6133-crossprov.json`).
    - TO-35, mutation "BuildSetOperators not called from the insert path" (`pr6133-to35-mutant.json`):
      - `InsertWithOutputFromConcatTest` is red again on SQLite.MS and DuckDB, the control.
      - `InsertConcat`'s baselines are byte-identical to the fixed run.
      - Access.Ace.Odbc fails with the same `Syntax error (missing operator)` (L-17).
    - TO-34: both tests rewrote their baseline with no new `.other` file. The `.other` files dated 2026-10-24 are A-5's negative.
    - TO-35 after round 8 (`pr6133-insertconcat-more.json`):
      - SQLite.Classic: green.
      - Access.Ace.OleDb: `InsertConcat` passes through its `ThrowsForProvider`, so the OleDb driver raises the same `Syntax error (missing operator)`.
      - The local Access.Ace.OleDb `CreateDatabase` fails with an OLE DB parameter conversion error, an environment fault that also fails `InsertUnion1` there.
      - SqlCe is netfx-only and left to CI.
    - Release with analyzers, after E-44: `Source/LinqToDB` net10.0 and netstandard2.0, and `Tests/Linq` net10.0, 0 warnings, 0 errors. With `-p:RunApiAnalyzersDuringBuild=true`, net10.0 reports RS0016 for three `AccessSqlExpressionConvertVisitor` overrides. They come from master's `ab0264e863` (#6203), merged in through #6111, and are not this PR's surface.
  - After A-12, on `af52f547d` (worktree `C:/Worktrees/linq2db/6133-dml-output-as-source`, `worktree-test.ps1 -Provider PostgreSQL.16`, results `.build/.agents/pr6133-a12-*.json`). CI on this head: Azure `build` 26116 and `test-all` 26117 green, GitHub `tests [all]` 45995612867 green (all legs). The PostgreSQL legs' baselines push of that run is not on `baselines/pr_6133`, so no CI baseline shows TO-36's SQL, and the leg log has no per-test lines.
    - Green: `InsertWithOutputQueryTests`, direct and LinqService, 91/91 (`pr6133-a12-green.json`, `-ExpectTests` confirmed TO-26, TO-27 and TO-36 ran). The same 91 green again on the restored tree after both mutations (`pr6133-a12-probe.json`).
    - Mutation A, "buffered enumeration sites never commit" (no `Complete` / `CompleteAsync` at `ExpressionQuery.cs:177`, `:215`, `:253`, `:401`) together with "load transaction opened although the option is off" (`Query.cs:244`): 17 red (`pr6133-a12-mutA.json`). TO-26 all 5 arms, TO-22 `Enumerate` and `EnumerateAsync` (`CompiledElement` stays green: the element site was not mutated), TO-24 `EagerLoadOverOutputInsertsOnce` and TO-34 `EagerLoadOverOutput_UnionStrategyMarker` (direct; `events.Count()` 0), TO-28 all 6 arms (`committed` 0), TO-36 both arms (`begun` 1). TO-27 stays green.
    - Mutation B, "commit before buffering" at the same four sites: 3 red, TO-27's three arms (`events.Count()` 3 instead of 0) (`pr6133-a12-mutB.json`).
    - Mutation C, "LoadTransaction.Complete never commits" (`Query.cs:314-338`, both `Complete` and `CompleteAsync`): 17 red (`pr6133-a12-mutC.json`). TO-22 all three arms, `CompiledElement` included; TO-29 `QueryBatchWithOutputCount` (`committed` 0); TO-26 x5, TO-28 x6, TO-24 and TO-34 direct. This re-proves the element and batch sites that mutation A left alone.
    - L-23's probe: see L-23 (`pr6133-a12-probe.json`); the probe was removed.
    - Tests per obligation: TO-36 `EagerLoadOverOutputWithoutLoadTransaction`.
    - The worktree is clean afterwards (`git status --short` empty).
- G-02: pass for PostgreSQL.16; blocked — CI baselines PR for the other PostgreSQL versions. Local baselines (`c:\GitHub\linq2db.bls`) were compared file by file with `origin/baselines/pr_5982`. 12 of 15 are identical, including every `Value_1` CTE field name, which is the PR head's naming. Three differ:
  - `EagerLoadOverOutputInsertsOnce` and `EagerLoadOverOutput_UnionStrategyMarker` gain a `CommitTransaction` line: D-10, which TO-22 measures through the rows persisting and the traced commit.
  - `GeneratedKeysJoinedBackToInput`: the join drops the null-safe `OR (e."PersistenceId" IS NULL AND i."PersistenceId" IS NULL)` arm. The output columns now keep the target's nullability: `EventRecord.PersistenceId` is `CanBeNull = false`, and the input's is a primary key. With both sides `NOT NULL` no row reaches the dropped arm, so no seed row can tell the two forms apart. The test asserts the three joined tags.
  - `UnreadOutputThrows` is renamed to `UnreadOutputStillInserts` (stale key for the baselines PR).
  - New tests' baselines were read for shape, e.g. `TwoIdenticalCallsInsertTwice` has two data-modifying CTEs.
- G-03: pass — `dotnet build Source/LinqToDB/LinqToDB.csproj -c Release -p:RunApiAnalyzersDuringBuild=true`, all five TFMs: 0 RS0016/RS0017. Control: the same build before the entries reported 16 RS0016 and 1 RS0017, the PR's malformed `Error_OutputQuery_EagerLoad ="…"` line, fixed. Re-run on `5309315ff3` with `Error_OutputQuery_NotTranslated`: 0 diagnostics, after an RS0016/RS0017 pair that caught a lost space in the `NotSupported` line. Re-run on the merged tree (A-8, `QueryElementType.SqlDataModificationTable = 92`): 0 diagnostics on all five TFMs (`restack_api.log`). `SqlDataModificationTable` and its members carry XML docs. The `InsertWithOutputQuery` remarks state D-11's run-once rule, the captured vs compiled conditions (L-5/L-7), D-12's correlation refusal and the eager-load rule; the transaction clause is dropped (A-7, L-8).
- G-04: n/a — no shipped member is removed or changed; `CteClause.DataModification` and `Error_OutputQuery_NotRead` were PR-only `Unshipped` entries.
- G-05: pass — the same Release build covers net462, netstandard2.0 and net8.0–net10.0. It failed first on `KeyValuePair` deconstruction (CS8129) in `ExpressionBuilder.cs` on net462/netstandard2.0, which is now fixed. The merged tree (A-8) builds clean on all five TFMs.
- G-06: pass — against the stack head (A-8), `git diff 4d7b0a4d1a -w` drops 17 lines. Each comes from a line the change already touches: the dedent that the `using var` declarations forced (IDE0063) at the D-10 sites in `ExpressionQuery.cs` and `CompiledTable{T}.cs`, the re-aligned fields of the three wrappers, and one `InsertBuilder.cs` attribute line. `TableBuilder.TableContext.cs` equals the stack and master.
- G-07: pass — `git diff 4d7b0a4d1a --name-only -- Tests/Tests.Playground` is empty; the probes were removed.
- G-08: pass — the cross-cutting changes are D-4 (cache key), D-9 (`VisitNestedStatement` in the base visitor) and the new AST node (D-1). The user approved them in the plan rounds (P12). Each rests on red→green tests and the controls under G-01.
- G-09: pass — a `code-reviewer` pass over `git diff origin/master` on `1487fd230c` (working tree included, rubric modules `[rubric-tests.md]` from `review-rubric-modules.ps1`) returned 1 MAJ, 6 MIN, 3 NIT and one out-of-scope observation. Each was verified against the code, and all were fixed in `5309315ff3` (A-7). MIN005 was confirmed red first (TO-26), and MIN003's new test was proven by its control (TO-25).

## P10 Adjudicated (M/L)

- L-1 (D-4) A query with at least two CTE-call positions carrying constants pays one comparison function per cache lookup. That function classes the constants with the registry's own equality, including `SequencesEqual` over captured collections. The query also loses the per-instance `Info` short-circuit (`ExpressionQuery.cs:106`), because `IsFastComparable` becomes false, so each enumeration re-runs expose, `EqualsTo` and the function. Queries with zero or one such position are unaffected. Unmeasured; TO-20 asserts only that caching still hits.
- L-2 `LoadWith` over the output is ignored, as for any `AsCte` source (Igor's out-of-scope observation).
- L-3 The plain-`AsCte` cache fix lands here, at the user's decision, as separate commits. `AGENTS.md` prefers a separate PR; `/split-pr` can still move it.
- L-4 DB2 `FINAL TABLE`, SQL Server derived-table output and UPDATE/DELETE/MERGE sources are follow-ups. SQL Server will need single-reference CTE inlining (D-2), and the validator's view of the nested SELECT (`SqlQueryValidatorVisitor.cs:380-429`) must be revisited.
- L-5 (D-11) A condition on a captured value removes the call at expose, so no insert runs (U-2). This is documented as C#-like evaluation.
- L-7 (D-11, U-15) Under `CompiledQuery`, a condition on a compiled argument is not evaluated at expose, so the call stays in the expression and inserts for either arm. On the normal path a captured-value condition removes it. Both follow "present in the exposed expression → runs once"; the remarks state the difference.
- L-6 (withdrawn by A-2) Associations over the output are supported; nothing is adjudicated here.
- L-8 (D-10, A-5) A remote context (LinqService) starts no implicit load transaction, as for every eager load: the buffered insert and each child query run as separate commands. The remarks therefore promise no transaction (A-7).
- L-9 (D-10, A-8, re-derived by A-12) The insert commits once the main rows are buffered, before the caller sees the first row. An exception thrown by the body of a caller's `foreach` / `await foreach`, or by a `ForEachAsync` callback, therefore keeps the insert: the callback runs after `CompleteAsync` (`ExpressionQuery.cs:211-226`). Before A-12 the plan said a `ForEachAsync` callback exception rolled back; that held for A-8's spanning transaction only. No test of this PR pins the commit-before-caller-code order for a DML query; master's `EagerLoadingTransactionTests.QueryInsideEnumeration` (`:392`) owns it for eager loads in general.
- L-10 (A-8) — withdrawn by A-12: `AsyncEnumerableAsyncWrapper` no longer exists at the head.
- L-11 (A-9, reworded by A-11) A `QueryBatch` collection over the output is refused with `Error_OutputQuery_EagerLoad` (TO-29), like any child query that reads the output. Since A-11 the message names both shapes and says to run the output query on its own and run the batch from the returned records. A scalar over the output inside a batch runs once and commits with the batch.
- L-12 (A-11) `InsertWithIdentity` from a set-operator source now renders its identity clause after the whole source. On master the base path puts it between the first branch and `UNION` (on SQL Server, `SELECT SCOPE_IDENTITY()` followed by `UNION ALL SELECT …`). The change is from wrong to correct; it is unprobed and covered by no test.
- L-13 (A-11) An insert from a set-operator source whose `SelectQuery` carries query extensions is wrapped in parentheses by `BuildSqlForUnion` on PostgreSQL and MySQL. That is broken on master and stays broken: E-42 only moves the `UNION` branches inside the parentheses.
- L-14 (A-11) A set-operator source with no `FROM` (the `VALUES` path, `From.Tables.Count == 0`) keeps the trailing placement, because the helper sits inside the source guard. Whether the shape is reachable was not established.
- L-15 (A-11) The flag is instance state reset at the protected `BuildSql` entry. A "never reset" mutant is observable only if one builder renders two statements; none was found, but the census of `BuildSql(` callers was not completed.
- L-17 (A-11) Access rejects `INSERT … SELECT … UNION ALL SELECT …` (`Syntax error (missing operator)`), with and without E-42. `InsertConcat` declares it with `ThrowsForProvider` for both Access drivers, and both were measured: ODBC directly, and OleDb on a locally broken database. Wrapping the union in a derived table for Access would lift it; that is outside this PR. Informix rejects the same shape (`A syntax error has occurred`, test-all GHA 45618003867), and is declared the same way. Its builder only post-processes the text and its `InsertUnion1` (derived-table form) has a master baseline, so the plain-insert text, and with it the error, predates E-42.
- L-18 (A-11, fixed by E-44) On YDB, `InsertWithOutputFromConcatTest` failed after E-42 with `SELECT have 3 columns, UPDATE expects: 4`.
  - Cause: `YdbSqlOptimizer.CorrectInsertStatement` names the first branch's columns after the target fields and marks it `DoNotSetAliases`. `AliasesHelper` then skips the loop that copies the first branch's aliases to the others. The second branch is uniquified on its own: `Value` is reserved, so it becomes `Value_1`. YQL combines `UNION ALL` branches by column name.
  - Master's placement renders the same `Value_1` and fails earlier, with `mismatched input 'UNION'`, so the alias predates E-42; fixed here at the user's choice by E-44.
- L-19 (A-11) `InsertTests.Insert11` / `Insert12` fail on YDB with a `Person` key conflict when they run after the rest of the insert and set-operator tests, and pass alone. Same-set A/B over 976 tests: they fail identically with E-42 and E-44 removed, so the order dependence predates this PR.
- L-20 (A-11, critic round 8) The `TryCreate` pre-check rests on its input being the exposed tree. A queryable constant left un-inlined, which is reachable only through the interceptor loop's 10-iteration bail-out (`Query{T}.cs:121-134`), would skip the CTE constants pattern. No reaching input was constructed.
- L-21 (A-11, critic round 8) E-44 assumes every set-operator branch has the first query's column count, as `AliasesHelper` already does, and that a branch carries no set operators of its own. `TryCoalescePeerSetOperators` flattens same-operation nesting, and mixed operations stay in a derived table. E-44 applies to every YDB insert from a set-operator source, not only the output case. `InsertConcat(YDB)` passed with and without E-44, because its column names need no uniquifying; only a branch whose own alias was uniquified changes.
- L-22 (A-12) With the implicit load transaction on, the insert runs at `LinqOptions.EagerLoadingIsolationLevel`, or the provider's `DefaultMultiQueryIsolationLevel` when that is unset (`Query.cs:277-281`). PostgreSQL does not override the default, so it is `RepeatableRead` (`DataProviderBase.cs:60`). The remarks do not say so. Read from code, unprobed.
- L-23 (A-12) With `UseEagerLoadingTransaction` off, a `QueryBatch` scalar over the output (TO-29) has no load transaction either, because the batch reaches the same opener (P7 `Query.cs:237-281` row). Measured on PostgreSQL.16 with a scratch probe (scalar `Count()` over the output plus a collection part that fails), `UseCombinedCommands` on and off (`pr6133-a12-probe.json`):
  - option on: 0 rows for a server failure (`22012: division by zero`) and for a client materialization failure, combined and not;
  - option off, server failure in the other part: 0 rows, combined and not. The SQL and the statement count were not traced, so this shows only that the failure was raised in a statement that also carries the insert: the client-failure cell below proves that the insert's statement had already run when the other part was materialized;
  - option off, client failure while the other part is materialized: 3 rows, combined and not. The insert is kept.
  Not produced: a server failure in a separate statement that runs after the insert's, with the option off. The remarks' "outside a transaction the insert is committed when the statement runs" covers the kept case. No test pins it.
- L-16 (A-11, MIN005) The detached field is used only for a dynamic field (`field.IsDynamic`): any other unmatched field still throws. The `OutputInsertUseSpecialTable` arm (`SqlAnchor` over the detached field) is untested while only PostgreSQL supports the feature.

## P11 Amendments (M/L)

- A-1 (2026-10-24, implementation) — The D-4 helper (the four method names and the sharing-pattern computation) moves from E-24 `DataModificationIdentity.cs` to its own file, E-36 `CteConstantsPattern.cs`, because it serves plain `AsCte`/`GetCte` too and lands in the separate cache-fix commit before the DML token type exists. Behaviour is unchanged; E-24 keeps only the token type.
  re-derives: P6 (E-24, E-36), P7 (the `CteConstantsPattern.cs` row: called only from `ExpressionCacheManager.RegisterCteConstantsPattern`), P8 (TO-19, TO-20 unchanged: same mechanism, new file)
- A-2 (2026-10-24, red-test run on the PR head, `scratchpad/red_pg16.log`) — **U-12 was wrong.** An association over the output works on the PR head: the CTE exports `ParentId`, and the join is placed outside it (`FROM "CTE_1" t LEFT JOIN "InsertOutputQuerySource" "a_Parent" ON t."ParentId" = "a_Parent"."Id"`), with 3 rows. Refusing associations would be a regression. The run disagreed with the design, so the design changes, not just the test.
  - SC-16 becomes "an association over the output works and places its join outside the data-modifying CTE".
  - TO-18 becomes a characterization (`AssociationOverOutput`, direct and LinqService), also guarding the new design.
  - `Error_OutputQuery_Projection` stays only as D-5's internal backstop, with a generic message.
  - P10 L-6 and the E-19 remarks sentence on associations are dropped.
  - Two TO-19 arms measured green on unfixed code:
    - reverse order on plain CTEs: two CTEs with equal values return the same rows as one shared CTE, so the defect is invisible;
    - the value-merge arm: the merged-away occurrence's literal is never parameterized and stays literal in the key, so the `> 3` / `> 4` pair misses.
  - Both are characterization arms. The red arms are closure A→B and scalar-literal A→B.
  re-derives: P2 (SC-16), P4 (U-12), P8 (TO-18, TO-19), P10 (L-6 removed), P6 (E-19 remarks, E-20 message)
- A-3 (2026-10-24, TO-11 control, `scratchpad/mut_to11.log`) — **E-16 withdrawn.** The mutation "applyInheritanceFilter true" left `DerivedTypeTarget` green, with no `WHERE` in the CTE body. The output table copies the insert target's `SqlTable`, and that table's `ObjectType` is always the hierarchy root (`TableBuilder.TableContext.GetObjectType` builds it from the root's entity descriptor). `MakeIsPredicate` returns `null` for the root, because every mapped type is assignable to it. E-16's switch was therefore dead code. It is removed in `1b9f05d2a3`, and `TableBuilder.TableContext.cs` equals master.
  - U-6 is re-resolved: no target type puts the predicate in the body, a derived one included. D-8 is withdrawn: there is no predicate to skip.
  - TO-11 becomes a characterization: one row, materialized as `TphDerived` by its discriminator, no `WHERE`.
  - UPDATE / DELETE output sources (L-4) still need their own look: their source table is read, not only written.
  re-derives: P4 (U-6), P5 (D-8 withdrawn), P6 (E-16 withdrawn), P7 (`TableBuilder.TableContext.cs` no longer edited), P8 (TO-11 proof: control → characterization)
- A-4 (2026-10-24, implementation) — **E-23 withdrawn.** `AliasesHelper` needs no case for the new table. The target's name is registered by `VisitSqlTable` on the nested INSERT's `Into` table, which the base visitor reaches through `VisitSqlDataModificationTable` → `VisitNestedStatement`. The output table's own alias is never rendered. The nested aliases (`s`, `t1`) equal the PR head's baselines (G-02).
  re-derives: P6 (E-23 withdrawn), P7 (the `AliasesHelper.cs:174-240` row: covered by the base visitor, no edit)
- A-5 (2026-10-24, `scratchpad/d10_pg16.log`) — **D-10's commit makes two remote baselines differ.** With D-10, direct runs of `EagerLoadOverOutputInsertsOnce` and `EagerLoadOverOutput_UnionStrategyMarker` trace `CommitTransaction`. The LinqService client starts no implicit load transaction, so their remote baselines no longer equal the direct ones. `BaselinesWriter` strips `BeginTransaction` and `DisposeTransaction` lines, but not `CommitTransaction`. Stripping it too would rewrite 281 existing baseline files that record user commits.
  - Chosen: `DisableBaseline` on the remote arm of those two tests, as `PostgreSQLTests.cs:2360` and `MergeTests.Types.cs:654` do. The direct baselines keep the SQL and the commit line; the remote legs still assert the results.
  re-derives: P8 (TO-22 unchanged; TO-24's test keeps its remote leg)
  conventions: `testing.md` → *Test layout* rules 1-2, swept with A-6
- A-6 (2026-10-24, test-layout sweep) — **The branch's tests follow the test layout, the PR author's tests included.** `test-diff-sweep.ps1 -Repo . -IncludeWorkingTree` found 71 one-line chains and one nested chain. All are reformatted to one call per line, and `GeneratedKeysJoinedBackToInput`'s method-syntax `Join` becomes query syntax (rule 2). The expression trees are unchanged. The rewrite keeps each literal inside its lambda, so the literal arms of TO-19 still pin constants.
  - The 35 narrowed provider sets are all `AllPostgreSQL`: the feature's `IsInsertOutputQuerySupported` gate. TO-12 covers every other provider.
  re-derives: P8 (no obligation changes)
  conventions: `testing.md` → *Test layout* rules 1-2 embedded; swept `test-diff-sweep.ps1 -Repo . -IncludeWorkingTree`: 71 chains → 0, 1 nested → 0, 35 narrowed sets (all `AllPostgreSQL`)
- A-7 (2026-10-24, pre-push `code-reviewer` pass, G-09) — **Review fixes, `5309315ff3`.** All findings were verified against the code before fixing.
  - MIN005, a defect introduced by D-10: after `CompleteAsync` commits, the async dispose still called `DataConnection.DisposeTransactionAsync`, which disposes whatever transaction is current. A transaction the user started inside `await foreach` / `ForEachAsync` was therefore rolled back silently. TO-26 was red on both arms (`min005_red.log`). `LoadTransaction` now skips disposal once committed. D-10's site list is unchanged.
  - MIN001: a second CTE for one identity hit `Dictionary.Add`'s `ArgumentException` before D-6's check could run. It now throws `Error_OutputQuery_Duplicated`.
  - MIN002: D-6's "none" arm threw an inline `InvalidOperationException`. It now throws the new `Error_OutputQuery_NotTranslated` (E-20, E-21).
  - NIT003: E-11's two missing backstops are added (`GetTableAlias` and the expression switch in `BasicSqlBuilder`).
  - MIN006: the E-19 remarks promised "one transaction with the insert", which a remote context does not start. The clause is dropped rather than qualified, following the house rule against caveats in public docs. L-8 records the limit.
  - MAJ001 and MIN004: the cache-dependent tests (TO-2, TO-3, TO-19, TO-20) are `[QueryCacheTest]`, so an eviction cannot turn them vacuous.
  - MIN003: TO-20 had a single call and never reached D-4's comparison function. TO-25 adds the two-call hit and its control.
  - NIT001 and NIT002: the remaining chains are laid out.
  - Out-of-scope observation taken: `CollectDataModificationCalls` collects lambda parameters only once a call is found, so a query without the feature no longer allocates the set.
  re-derives: P5 (D-10's failure mode gains "a committed transaction is not disposed again"), P6 (E-11, E-19, E-20, E-21, E-22, E-28, E-31 re-touched), P7 (the `Query.cs` load-transaction and `BasicSqlBuilder.cs` rows: same files, no new caller), P8 (TO-25, TO-26 added), P10 (L-8)
  conventions: `testing.md` → *Test layout* rules 1-2 and the `[QueryCacheTest]` rule for cache-miss assertions embedded; swept `test-diff-sweep.ps1 -Repo . -IncludeWorkingTree` on `5309315ff3`: 0 chains, 0 nested, 37 narrowed sets (all `AllPostgreSQL`)
- A-8 (2026-10-24, restack on #6111 at the user's request) — **Base change and the D-10 re-derivation it forces.**
  - The stack was synced first, locally, by merge only. Master went into #5673 as `690be7136d` (only `PublicAPI.Unshipped.txt` conflicted, from the 6.5.1 release prep), and #5673 went into #6111 as `4d7b0a4d1a`. `4d7b0a4d1a` was then merged here as `b94919f94b`. The PR base becomes `feature/1404-query-batch`. Nothing is pushed.
  - Mechanical adaptations: `Preamble` is renamed `Harvester` (E-32). The stack's new `KeysDataSlotHarvester` gets `GetStatements()` (E-34). The checks read `Query.QueryInfo`, the stack's single query. `IsInsertOutputQuerySupported` takes `DataMember` order 85, because 80-84 are the stack's (E-40). `SqlDataModificationTable` is appended after the stack's `QueryElementType` members (92). The nested-statement render uses the stack's `RenderContext` `BuildSql` overload (E-11).
  - **D-10 re-derived.** The stack keeps the load transaction open for the whole enumeration (`EnumeratorWrapper`, `AsyncEnumeratorAsyncWrapper`, `AsyncEnumerableAsyncWrapper`), and it can read the main query and its children through one command. Committing right after the harvesters would therefore commit with a reader still open. The user chose (2026-10-24) "commit on success, roll back on an exception": `Complete()` runs when the owner finishes, and the wrappers record a `MoveNext` exception and complete only after the reader closes (E-37..E-39).
  - **TO-26 re-derived.** On the stack, `BeginTransaction()` inside the enumeration of any eager load throws "Data connection already has transaction", so A-7's user-transaction test cannot hold. MIN005's hazard is gone with it: nothing can start a transaction between the commit and the release. TO-26 now pins the commit at the end of the enumeration, and TO-27 pins the rollback.
  re-derives: P2 (SC-18), P4 (U-13), P5 (D-10), P6 (E-11, E-28, E-29, E-30, E-32, E-34; new E-37..E-40), P7 (the load-transaction, wrapper, harvester and `SqlProviderFlags.cs` rows), P8 (TO-26 rewritten, TO-27 and TO-28 added), P9 (G-01, G-03, G-05), P10 (L-9, L-10)
  conventions: `testing.md` → *Test layout* rules 1-2 embedded; swept `test-diff-sweep.ps1 -Repo . -Base 4d7b0a4d1a -IncludeWorkingTree`: 0 chains, 0 nested, 38 narrowed sets (all `AllPostgreSQL`)
- A-9 (2026-10-24, critic round 6 over the whole design on the stack) — **Re-measured proofs and the stack's own entry point.**
  - The controls of TO-8, TO-20, TO-24 and TO-25 predated the restack, and the stack edited their surface. They were re-run on the restacked tree, and each is red under its mutation (G-01). TO-24's mutation site moved to the `placeholders.Count == 0` fallback, `ExpressionBuilder.EagerLoadKeyedQuery.cs:1044-1047`.
  - No test reached `QueryBatch`. TO-29 adds it: a scalar over the output beside an independent collection commits once, and a collection over the output is refused. L-11 records the refusal. `8b70c7b6de`.
  - Bookkeeping:
    - TO-9, G-06 and G-07 are measured against the stack head `4d7b0a4d1a`.
    - E-11 names the new `BuildDataModificationCteBody`.
    - U-7 records the stack's `PrepareStructure` passes.
    - The P4, P5, P7 and P8 line anchors are refreshed to HEAD; P12 keeps the anchors of its own rounds.
    - TO-12 was re-run on the file providers.
  re-derives: P4 (U-7), P6 (E-11 wording), P7 (anchors), P8 (TO-9 base, TO-24 site, TO-29 added), P9 (G-01, G-06, G-07), P10 (L-11)
  conventions: `testing.md` → *Test layout* rules 1-2 embedded; swept `test-diff-sweep.ps1 -Repo . -Base 4d7b0a4d1a -IncludeWorkingTree`: 0 chains, 0 nested, 41 narrowed sets (all `AllPostgreSQL`)
- A-10 (2026-11-04, review round 1 on #6133, recorded retroactively) — **Read-only service and the commit-with-statement remark.** igor-tkachev's MAJ001: a query over the output reaches the service as a `SELECT` with the `INSERT` inside its CTE, so `AllowUpdates = false` let it through. `ValidateQuery` also refuses a statement that carries a `SqlDataModificationTable` (E-41). SUG001: the remarks of both overloads state that outside a transaction the insert commits with the statement (E-2's doc text). `545a7d49f8`.
  re-derives: P6 (E-41), P7 (the `LinqService.cs` row), P8 (TO-30), P9 (G-01)
  conventions: `testing.md` → *Test layout* rules 1-2 embedded; the remote test reuses the fixture's models and a nested `ReadOnlyRemoteDataContext`
  class: `ValidateQuery` is the single refusal point for all four `LinqService` entry points (P7 row), so no sibling path stays open
- A-11 (2026-11-11, review round 2 on #6133, MaceWindu; dispositions approved one by one by the user) — **Dynamic output columns, set-operator sources, and wording.**
  - MIN005: `SqlDataModificationTable` copies the target's fields at construction, and a dynamic field added later has no match in `insert.Into.Fields`, so `BuildDataModificationCteBody` throws. For a dynamic field it binds a detached `new SqlField(field) { Table = target }`, so the cached target is unchanged (E-11 re-touched). TO-31.
  - MIN008: `BuildSql` appends `SelectQuery.SetOperators` after the whole statement, which puts `UNION ALL` behind `RETURNING`. This predates the PR (`InsertWithOutput` fails the same way on master). The user chose to fix it here rather than in a separate PR. E-42 / E-43; TO-32. The provider overrides of `BuildInsertQuery` were swept. SQL Server calls the base and renders `OUTPUT` before the source, MySQL copies the base body (E-43), and ClickHouse has no output and keeps the trailing placement. For a plain insert the text does not change, because nothing follows the source. It does change for `InsertWithIdentity` from a set-operator source, where the identity clause now follows the whole source.
  - MIN006: both overloads' remarks scope the commit-with-statement sentence to "without eager loading", and add that with eager loading on a direct connection the implicit transaction rolls the insert back. TO-27 and `MaterializationFailureKeepsInsert` already pin both cases.
  - MIN007: the two remote-arm `DisableBaseline` waivers go. The stack's `ec94a2892c` added stripping of `CommitTransaction` to `BaselinesWriter.Normalize`, which removed the A-5 cause. TO-34.
  - SUG002 / SUG003: `Error_OutputQuery_EagerLoad` is reworded for any separately executed reader (a child query, a collection in a batch). `Error_OutputQuery_Correlated` takes the reviewer's text. The values in `PublicAPI.Unshipped.txt` follow. TO-33.
  - SUG004: `FeatureOutputQuery` names the provider set once. `FromQuery_PreV18Dialect` keeps the literal.
  - NIT001-NIT004: whitespace, alignment, and `[LinqTunnel]` on both overloads.
  - Out-of-scope perf note: `CollectDataModificationCalls` and `CteConstantsPattern.TryCreate` walk the expression on every main-query build. The user chose to measure first, then decide.
    - Measurement: Release, SQLite.MS, query cache off, 3000 builds of a join + subquery query per run, three interleaved runs per arm. The comparison arm was a temporary environment switch that skipped both walks (since removed).
    - Result: +8.5 KB per build (walks 664-668 KB against 655-660 KB, about 1.3 %). Time stayed inside the noise.
    - The cost came from `TryCreate`'s `Path` walk, which builds an accessor expression for every visited node.
    - The user chose an allocation-free `Find` pre-check in front of each walk (E-36, and E-17's `CollectDataModificationCalls`). Re-measured: 658-661 KB against 659-661 KB, indistinguishable from the skip arm. The cache tests (TO-20, TO-25) cover the CTE path behind the pre-check.
  re-derives: P6 (E-11 re-touched; E-42, E-43, E-44 added), P7 (the `BasicSqlBuilder.cs` set-operator, `YdbSqlOptimizer.cs` and pre-check rows), P8 (TO-31..TO-35), P9 (G-01), P10 (L-11..L-19)
  conventions: `testing.md` → *Test layout* rules 1-2 embedded (no `Issue<N>` names; `InsertConcat` builds on the shared `Parent` model, the output tests on the fixtures' own models); swept `test-diff-sweep.ps1 -Repo . -Base origin/feature/1404-query-batch -IncludeWorkingTree`: 0 chains, 0 nested, 45 narrowed sets (all `FeatureOutputQuery` / `FeatureInsertOutputMultiple`, plus `FromQuery_PreV18Dialect`'s `AllPostgreSQL`)
  class: the set-operator placement was searched over every `BuildInsertQuery` / `BuildSql` override (P7 row), and the alias copy over every `DoNotSetAliases` writer (`YdbSqlOptimizer.cs:52` is the only one)
- A-12 (2026-11-27, before review round 2 of #6133 by MaceWindu; recorded after the fact) — **The restacks onto 6.6.0 and #6456, the Informix gate, and `UseEagerLoadingTransaction` off.** The approval of SC-18 and of E-19's remarks is void until this amendment's critic round is folded in.
  - Restacks `d992d9a56` and `c79b830e8` merged master through 6.6.0, #6451, #6439, #6456, #6464 and #6485, via #6111. #6111's flags took `DataMember` orders 85 and 86, so E-40 moved to 87 (already in E-40's text). #6456 added `LinqOptions.UseEagerLoadingTransaction` and `EagerLoadingIsolationLevel`: with the option off, `StartLoadTransaction` returns `LoadTransaction.WithoutTransaction`, so D-10's commit/rollback does not apply. SC-18 is scoped to the option on.
  - `af52f547d` (author sdanyliv): both overloads' remarks say the insert commits with the statement outside a transaction, and that eager loading on a direct connection opens one implicitly unless the option is off (E-19). TO-36 `EagerLoadOverOutputWithoutLoadTransaction` pins the off case (E-22).
  - `2a57acbd9` (author sdanyliv): `InsertConcat` declares Informix's `A syntax error has occurred` with `ThrowsForProvider` (E-46, L-17). This narrows TO-35's provider set by one measured failure (test-all GHA 45618003867).
  - P6 bookkeeping: E-45, E-46 and E-47 name files that the diff has carried since A-11 or the rework, and which the file-keyed reconcile against the stack base reported as unplanned.
  - New known limits: L-22 (isolation level of the insert, read from code) and L-23 (`QueryBatch` with the option off, measured).
  - **Critic round 9 refuted the first draft** on the plan record: #6111's `bbd9de082` (2026-10-29, an ancestor of A-11's head) had already replaced A-8's spanning transaction with buffering, so D-10, SC-18, L-9, L-10, six edit-points and the TO-26..TO-28 controls described code that is no longer in this PR. Revised: D-10 re-derived for buffering; E-28..E-30 and E-37..E-39 withdrawn; the four load-transaction P7 rows say out-of-scope (stack-owned); SC-18 and L-9 rewritten (a `ForEachAsync` callback failure now keeps the insert); L-10 withdrawn; TO-26, TO-27 and TO-36 re-proved with mutations of the stack's code, and TO-28 keeps a commit control (G-01). Two PR test comments still state A-8's mechanism, `InsertWithOutputQueryTests.cs:1228` ("the load transaction spans the enumeration") and `:1438` ("streams the insert with its reader open"), and so do two test names, `EagerLoadOverOutputCommitsWhenEnumerationEnds` and `EagerLoadOverOutputWithDetachedChildCommitsAfterReader`; they go to the round-2 review. `ExecuteAsyncEnumerable` (`ExpressionQuery.cs:172-177`) is reached by no test of this PR; master's `EagerLoadingTransactionTests.ExecuteAsyncEnumerable` owns it.
  re-derives: P2 (SC-18), P5 (D-10), P6 (E-19, E-22 re-touched; E-28..E-30, E-37..E-39 withdrawn; E-45, E-46, E-47 added), P7 (the `SqlProviderFlags.cs` / `PostgreSQLDataProvider.cs` row; the four load-transaction rows; the `Query.cs:237-281` row added), P8 (TO-26, TO-27, TO-28, TO-36), P9 (G-01), P10 (L-9, L-10, L-22, L-23)
  conventions: `testing.md` → *Test layout* rules 1-2 embedded; swept `test-diff-sweep.ps1 -Repo C:/Worktrees/linq2db/6133-dml-output-as-source -Base origin/feature/1404-query-batch` on `af52f547d`: 0 chains, 0 nested, 45 narrowed sets (41 `IncludeDataSources(FeatureOutputQuery)`, 2 `DataSources(FeatureOutputQuery)`, 1 `FeatureInsertOutputMultiple`, 1 `AllPostgreSQL`), 0 in every gate category (`typeOnlyShouldlyGates`, `shouldlySubjectGates`, `unanchoredAssertionGates`, `narrowedContinuations`, `cacheMissOutsideQueryCacheTest`, `handDuplicatedAreEqual`, `issueNamedMembers`, `localModels`, `attributePadding`, `issueFixtureFiles`, `continuationIndents`, `invisibleChars`). The two adopted commits are another author's, so hits would be dispositioned here; there are none
  class: the option's reach was searched over every opener of the implicit transaction (P7 `Query.cs:237-281` row), not only the eager-load path that TO-36 exercises

## P12 Critic verdict (M/L)

**Current verdict: weak** — round 10 (A-12, after round 9 refuted its first draft on the plan record). Every objection is folded in or recorded in P10; none refuted a mechanism of the PR's code.

**Round 1 (2026-10-23, plan-critic on fable): weak.** All ten objections were folded in: TO-11 on `ITable<Derived>`; TO-8's mutation under a new key; D-5's non-field column rule; `SqlQueryColumnNestingCorrector` in D-9; associations → SC-16/TO-18/L-6; raw calls tokenized before registry use; ordering of registration before the source build; the U-7 mode text; E-4's field remap; and the minor wording fixes.

**User review after round 1 (2026-10-23).** The user asked whether the plan was free of workarounds and replaced six decisions:
- D-2: body marker instead of a state flag;
- D-3: expose-time identity instead of a builder reference map;
- D-4: sharing-pattern cache key instead of `DoNotCache`, closing the master `AsCte` bug here;
- D-5: render-time `RETURNING` instead of a `Finalize` sync;
- D-9: `VisitNestedStatement` instead of ad-hoc overrides;
- D-10: committed load transaction instead of a skip.

They also added D-11 (keep-alive, `NotRead` removed) and D-12 (correlated refusal). These are new decisions, so round 2 is due.

The user confirmed D-4's scope after a markers-only alternative was offered (2026-10-23): the general sharing-pattern fix, covering plain `AsCte`/`GetCte` too, in this PR.

**Round 2 (2026-10-23, plan-critic on fable): refuted**, on one clause: D-12 as written refused `CompiledQuery`'s `ps[i]` arguments, so TO-5 could not go green. The critic could not break D-4's sharing pattern (nested CTEs, `GetCte`, inlined captured queryables, value-equal constants, compiled queries) and verified D-10's ten sites and commit/dispose semantics, and D-5's feasibility. Objections and dispositions:

1. D-12 binding rule. Changed: U-14, D-12 (enclosing lambda within the exposed expression; `ParametersParam` exempt).
2. D-4 hot-path cost: loss of `IsFastComparable` / `Info`. Verified at `ExpressionQuery.cs:105` and `QueryCacheCompareInfo.cs:34`. Changed: D-4 (register only with ≥2 placeholder-carrying CTE positions), P10 L-1.
3. D-4 method list inconsistent (`FromSql*`). Changed: D-4 and E-24 (four named methods defined once).
4. D-4 rationale misstated the registry rule. Changed: D-4 "why" and failure mode (finer, so misses only), P10 L-1.
5. D-11 keep-alive was not scoped to the main query. Changed: U-17, D-11 (`ReferenceEquals(query, _query)`, the slot between `:341` and `:354`), D-4 registration once per build.
6. Lead: `KeyedQuery` buffer fallbacks could run the DML in a preamble. Changed: U-16, SC-9, D-6 (count across preamble statements), TO-24.
7. The compiled path does not evaluate conditions. Changed: U-15, D-11 failure mode, P10 L-7, E-19, TO-23.
8. Lead: the tokenized overloads must be `IsQueryable`. Changed: U-18, D-2, D-3, E-19, E-24 (internal methods on `LinqExtensions`).
9. Nit: registration must be idempotent. Changed: D-4 (once per build, main query only).

**Round 3 (2026-10-24, plan-critic on fable): weak.** It verified U-17 (only `ExpressionBuilder.cs:240` passes `_query`), U-16 (the buffer preamble is the same statement object, `EagerLoadKeyedQuery.cs:1106`; the fallbacks carry a cloned DML copy), U-18, U-15/TO-23, D-12's compiled premise and D-5's P7 row. Objections and dispositions:

1. Lead: scalar constants are placeholders too (`NonComparableExpressions`), and the registry merges them by value, so a reference-only pattern below the threshold missed them and was unsafe for value-merged pairs. Changed: U-19, D-4 (every `ConstantExpression` inside the four calls, classed by the registry's own constant equality), TO-19 (scalar and value-merge arms), P10 L-1.
2. D-6 not implementable: `Preamble` exposes no statements. Changed: D-6 (abstract `GetStatements()`, deduped by reference), E-32..E-35, P7.
3. TO-22's compiled arm hit the wrong site with a `ToList()` shape. Changed: TO-22 (element-typed `.First()`).
4. "Once per build" needed a guard. Changed: D-4 and E-27 (a flag on `ExpressionCacheManager`, which survives the `validateSubqueries` retry).
5. D-12's `ParametersParam` exemption was redundant and keyed by name. Changed: D-12, which drops the exemption and states why `ps` is never enclosing.
6. Nit: TO-24's method name. Changed: TO-24.
7. Note: `FinalizeCte` runs twice and its collector skips `With`. Changed: D-11 (keep logic on both runs, collector over kept bodies).

Not verified by the critic and left to tests: whether the dummy column appears for an unreferenced keep-alive body (TO-7) and the LinqService round trip of a zero-column body (TO-7's LinqService leg).

**Round 4 (2026-10-24, plan-critic on fable, delta A-1..A-6 against the implemented branch): weak.** All six amendments hold on the code: A-1 (one caller of `CteConstantsPattern`), A-2 (association at the reference), A-3, A-4 (every alias-relevant element of the nested statement is reached through `VisitNestedStatement`), A-5 and A-6 (the reformat keeps every expression tree, and the TO-19 literals stay inside their lambdas). The verdict is plan-text bookkeeping only; no objection touches an edit-point or a test.
- A-3 holds more strongly than written. `EntityDescriptor.HasInheritanceMapping()` gates `InitInheritanceMapping` (`EntityDescriptor.cs:186-189, 409-410`), so no type below a mapped base owns a mapping. `GetObjectType()` therefore always lands on the one mapped ancestor, and the predicate is null for every well-formed hierarchy.
- A-5's figure of 281 files was unverified by the critic, which read the local run output `c:\GitHub\linq2db.bls`. It was counted in the baselines repo, `linq2db.baselines` on `master`: 281 `.sql` files with a `CommitTransaction` line.

Objections and dispositions:
1. U-12 still carried the refuted resolution. Changed: U-12 is re-resolved at the reference (`CteTableContext.cs:78-79`).
2. P7 `TableBuilder.TableContext.cs` row and E-14 carried the withdrawn premise and a stale method name. Changed: both rows.
3. P7 `CteContext.cs` row named the projection check as the association handling. Changed: that row.
4. P7 `TableBuilder.cs:17` row claimed one source for the method names. Changed: it names the second copy in `CteConstantsPattern.IsCteDefiningCall`.
5. Nit: the E-19 remarks' transaction sentence is false on remote contexts. Changed: the clause is dropped, and L-8 is added (A-7).

A-7 narrows no decision and adds no edit-point. The review fixes stay inside E-11, E-19..E-22, E-28 and E-31, so no further critic round is due.

**Round 5 (2026-10-24, plan-critic on fable, delta A-8: the restack and D-10's re-derivation): weak.**
- Points 1-4 hold on the code:
  - All ten load-transaction openers map to exactly one completion, with the reader already closed.
  - The rollback rule is implemented consistently.
  - Read-only eager loads are unchanged; the holder is a no-op for them apart from one allocation.
  - Buffer mode keeps a second INSERT copy out of the combined command, because the buffered main query never gets a `GetResultFromReader`.

Objections and dispositions:
1. U-13 kept the pre-stack mechanism. Changed: U-13 re-resolved; A-8's `re-derives:` names P4.
2. D-10's text lagged the code. The "chosen" rule and the fault rule lived only in A-8, failure-mode bullet 3 asserted a hazard A-8 calls gone, and bullet 2 named `InitPreambles`. Changed: D-10 "chosen" carries both rules. Bullet 3 says the `_released` guard is defensive on the stack. Bullet 2 names `InitHarvesters`. SC-18 now covers commit-or-rollback → TO-22, TO-26..TO-28. L-9 records the body-vs-callback asymmetry, and L-10 the shared holder in `AsyncEnumerableAsyncWrapper`.
3. E-37..E-40 and the wrapper P7 row were missing, and the `SqlProviderFlags.cs` P7 row said out-of-scope. Changed: the rows are added and the flag row is corrected. A PowerShell array of `'a' + $N + 'b'` replacements had silently kept only `'a'`, because the comma binds tighter than `+`; every replacement was re-applied and re-verified by search.
4. "Complete only after the reader closes" had no reddening obligation. TO-26/TO-27 run in buffer mode, with no reader open. Changed: TO-28 (detached child, combined and not, sync and async break) is red under the order mutation in both wrappers, verified.
5. Lead: the combined DML shape was unprobed. Covered by TO-28's `combined: true` arms.
6. Nit: TO-27 asserted the exception type only. Changed: the message is pinned.
7. Nit, out of A-8's scope: the E-19 remarks say child queries that "cannot be keyed to the output" throw, while an independent child is detached and works. Not changed: an independent child is not keyed at all, and the house rule keeps the public remarks free of case lists.

A-8's corrections stay inside its own rows and add TO-28 only, so no further round is due.

**Round 6 (2026-10-24, plan-critic on fable, the whole design against the stack head `4d7b0a4d1a`, HEAD `5e8869085e`): weak.**
- Area 1 holds by construction. D-2, D-3, D-4, D-5, D-6, D-9, D-11 and the serializer survive the stack:
  - the stack did not touch the builder files;
  - every stack render path (baked, per-run Transform, `DbBatch`, combined) produces `RETURNING` from the body;
  - the buffer harvester still shares the main statement, so D-6's reference dedupe counts the INSERT once.
- Area 2 found no double or zero insert.

Objections and dispositions:
1. The pre-restack controls (TO-8, TO-20, TO-24, TO-25) were void on the stack. Changed: all re-run on the restacked tree and red under their mutations (G-01). TO-24's site is updated.
2. Lead: no obligation covered the stack's `QueryBatch`. Changed: TO-29 (scalar over the output, with a control; collection refused) and L-11. The message's advice does apply: the caller materializes the output outside the batch.
3. TO-9, G-06 and G-07 cited `origin/master`, and TO-12 had file-provider logs only from before the restack. Changed: re-measured against `4d7b0a4d1a`, and TO-12 re-run. TO-28's combined arm ran the `DbBatch` backend; the concatenated-command backend for this shape stays unmeasured, through the same `BuildSql` entry.
4. E-11's wording read as if no `BuildDataModificationCteBody` remained. Changed.
5. U-7 cited the pre-stack passes. Changed: it records `PrepareStructure` and the eager render; the conclusion is unchanged.
6. Stale anchors in P4, P5, P7 and P8. Changed: refreshed to HEAD. P12's own rounds keep their anchors as a record.

A-9 adds tests and re-measures proofs only, adding no decision and no edit-point, so no further round is due.

**Round 7 (2026-11-11, plan-critic on fable, A-10/A-11 before the MIN005/MIN008 code): weak.** The E-42/E-43 mechanism and the override sweep hold, as does MIN005's detached field (serializer, Transform clone and alias lookup all checked). The proofs were thinner than stated.

Objections and dispositions:
1. `InsertUnion1` cannot see the changed path: its computed setter puts the union in a derived table. Changed: TO-35 adds `InsertConcat` with a plain setter, and the baselines are A/B'd under a mutation.
2. "Plain insert text unchanged" had no witness. Changed: TO-35. SQL Server and ClickHouse are left to CI.
3. The `InsertWithIdentity` change was declared without an obligation. Recorded: L-12.
4. E-42 left its placement open. Changed: after `BuildSubQueryExtensions`, inside the source guard, flag reset at the `BuildSql` entry; L-14 and L-15.
5. A "never reset" mutant is caught by nothing. Recorded: L-15.
6. TO-32 overclaimed its providers. Changed: red only for RETURNING providers, measured on SQLite.MS and DuckDB with the syntax error at `UNION`; YDB, Firebird 5 and MariaDB go to CI.
7. Lead: `BuildSqlForUnion` wraps a hinted insert in parentheses. Recorded: L-13.
8. TO-34 did not name its negative. Changed: it cites A-5 and the `BaselinesPath`.
9. MIN005's gating and the anchor arm. Recorded: L-16.

**Round 8 (2026-11-11, plan-critic on fable, delta over the implemented A-11, E-44 and the `Find` pre-checks): weak.** No mechanism was refuted. The flag cannot mis-skip: every nested render uses a fresh builder, and every `BuildInsertQuery` caller passes the builder's own statement.

Objections and dispositions:
1. `BuildSetOperators` was `private protected` but called from a provider builder. Changed: `protected`, with a `PublicAPI.Unshipped.txt` entry (E-42).
2. TO-30, TO-31, TO-33 and TO-34 named PostgreSQL.18, which G-01 never measured. Changed: they name PostgreSQL.16, the measured one; other versions run in CI.
3. `InsertConcat`'s OleDb `ThrowsForProvider` was unmeasured. Changed: run on SQLite.Classic, Access.Ace.OleDb and SqlCe (G-01).
4. The `TryCreate` pre-check rests on exposed input. Recorded: the P7 row and L-20.
5. E-44's column-count and no-nesting invariants, and its reach into plain YDB inserts. Recorded: L-21.

**Round 9 (2026-11-27, plan-critic on fable, delta A-12 first draft): refuted** on the plan record, not the code. The rewritten remarks held for every shape the critic built (user transaction, `TransactionScope`, remote, compiled, option off), and A-12's single-opener claim was exact.

Objections and dispositions:
1. SC-18 contradicted the head: the stack buffers and commits before the first row (`ExpressionQuery.cs:396-401` and the async sites). Changed: SC-18 and D-10 re-derived.
2. D-10's six edit-points (E-28..E-30, E-37..E-39) were no longer in the own delta, removed by the stack's `bbd9de082`, which A-11 also missed; P7 contradicted itself between `:380` and the new row. Changed: withdrawn, P7 rows rewritten.
3. L-9's `ForEachAsync` clause was false, and L-10 described a deleted class. Changed: L-9 rewritten, L-10 withdrawn.
4. The TO-26..TO-28 controls targeted deleted code. Changed: re-proved under mutations A and B (G-01); TO-28 keeps a commit control, its order premise is a characterization.
5. Two PR test comments state the removed mechanism. Recorded in A-12 for the review.
6. Lead: L-23's prediction might be false for a combined batch. Changed: measured (L-23). A server failure raised in the statement that carries the insert undoes it, combined or not; a client failure keeps it. A server failure in a later, separate statement was not produced (narrowed after round 10).
7. TO-36 covers one of two option checks. Changed: TO-36 names master's `EagerLoadingTransactionTests` as owner of the async and compiled arms.
8. TO-36's mutation text overstated the run. Changed: it names the first failing assertion.
9. G-01 for A-12 was unmeasured. Changed: measured (G-01).
10. L-22 could name the level. Changed: `RepeatableRead`.

**Round 10 (2026-11-27, plan-critic on fable, the revised A-12): weak.** Round-9 dispositions 1-5 and 7-10 accepted. Mutations A and B separate cleanly on the head.

Objections and dispositions:
1. L-23's server-failure cell cannot tell "inside the insert's statement" from "a later statement", and P12 item 6 generalised from it. Changed: L-23 and item 6 narrowed; the later-statement cell is recorded as not produced.
2. The control re-proof covered the enumeration sites only; TO-22's compiled arm and TO-29 rested on pre-buffering proofs. Changed: mutation C, all three TO-22 arms and TO-29 red (G-01).
3. SC-18's loop-body clause had no owner. Changed: moved out of SC-18 into L-9, with master's `QueryInsideEnumeration` as owner.
4. Stale references: TO-22's `:185` and E-30, the P7 "compiled sites (E-30)", D-10's "nothing can start a transaction" (false for `ForEachAsync` under buffering, now stated), and the two test names. Changed: all four cleared; the test names go to the review with the comments.
5. Note: `ExecuteAsyncEnumerable` has no witness in this PR. Changed: master's `ExecuteAsyncEnumerable` test named as owner in A-12.

Not re-attacked after round 10: TO-22's mutation C record, the narrowed L-23 and item 6, L-9's owner line, and D-10's `ForEachAsync` sentence (read from code, unprobed).
