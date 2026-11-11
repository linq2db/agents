# Work plan: feature-1404-explicit-query-batch — Explicit query batch: register reads across methods, run them in one round trip

**Tier:** L  ·  **Status:** approved  ·  **Approved-at:** 2026-11-11 (user, after critic round 2)  ·  **Branch:** feature/1404-explicit-query-batch
**Schema:** `.claude/docs/work-plan.md`  ·  **Gates:** `.claude/docs/definition-of-done.md`

Stacked on PR #6111 (`feature/1404-query-batch` @ `f798e94b51`, draft, still in review); every `-Action reconcile` runs with `-Base origin/feature/1404-query-batch`, and the branch syncs from #6111 by merge only. Probe evidence below was measured on 2026-11-11 against this worktree with a scratch Playground fixture (`Tests/Tests.Playground/ExplicitBatchProbe.cs`, never committed) that prototypes the fusion of D-2 through public and internal-namespace API, on SQLite.MS, SqlServer.2022.MS, PostgreSQL.16 and their `.LinqService` contexts (52 cases, 0 failed). SqlServer.2022.MS stands in for 2019: the `sql2019` container is stopped, and both use the DbBatch backend.

## P1 Problem

Absent capability, the half of [#1404](https://github.com/linq2db/linq2db/issues/1404) that #6111 left out: reads registered from several call sites and run together (`DeferValue` / `CompleteDefer` in the issue). #6111's `db.QueryBatch(...)` needs every read written in one expression at one call site, so a repository whose page count and page rows come from two methods, or whose set of reads is conditional, cannot use it without passing `Expression<Func<T>>`s up to one call of a statically known arity of at most 7. On `f798e94b51` the target shape does not compile: `db.CreateQueryBatch()` does not exist (searched `CreateQueryBatch|QueryBatchBuilder|QueryBatchResult` across `Source/` and `Tests/`: no hit). #6111's plan (P5 D-1) deferred an explicit batch object "until cross-method registration is asked for"; the user asked for it on 2026-11-11:

```csharp
var batch = db.CreateQueryBatch();
var total = batch.Add(() => query.Count());
var items = batch.Add(() => query.Skip(offset).Take(limit).ToList());
await batch.ExecuteAsync(cancellationToken);
return new Page<T> { Count = total.Value, Items = items.Value };
```

## P2 Success criteria

- SC-1 Each part's `Value` equals the part run alone, for every part kind (a scalar, an aggregate over an empty set, an entity, a `List`, an array, a list of values, a client constant, `Any`, `Sum`, `LongCount`) at every tuple position — collections and entities past the seventh part, a fifteenth part in `Rest.Rest` — for one part and for exactly eight, sync and async, on every provider family direct and remote, except Access (`NoFromlessSubquery`, as on #6111).  → TO-1, TO-2
- SC-1b The strict-`First` reads of a value (NULL in a row that exists, a string, an anonymous type) read as the part alone, and where a provider refuses such a read the whole batch reports that refusal (Sybase, as #6111's `NullValueReadsAsThePartAlone` declares).  → TO-20
- SC-2 On a `DataConnection` whose provider combines (`UsesCombinedQueryBatch`), `Execute` with a collection part sends exactly one command whatever `UseCombinedCommands` is; elsewhere the parts run one by one, as `db.QueryBatch` of the same parts does.  → TO-3
- SC-3 Parts added from different methods, a loop adding same-shaped parts over different captured values, and one lambda instance added twice each read their own value.  → TO-4, TO-5
- SC-4 `Value` before a successful `Execute` throws `InvalidOperationException`; after a successful `Execute`, `Add` and `Execute` throw `InvalidOperationException`; an empty batch's `Execute` sends no command and counts as run.  → TO-6, TO-7, TO-8
- SC-5 While `ExecuteAsync` is in flight, `Add` and `Execute` throw `InvalidOperationException`; a refusal before the first await (pending hints) leaves the batch un-run and retryable.  → TO-9, TO-10
- SC-6 A failed `Execute` leaves the batch un-run — after a strict `First` over an empty part (sync, async, remote) and after a database error — so `Value` throws the not-run error and a retry returns the values.  → TO-11, TO-12
- SC-7 `ExecuteAsync` with an already-cancelled token throws `OperationCanceledException` before any command or transaction, and the batch stays retryable.  → TO-13
- SC-8 Captured values are read at `Execute`: a value changed after `Add` reaches the result.  → TO-14
- SC-9 A second run of the same parts from the same call sites with new captured values reuses the cached query; the cached query is keyed by the part types, so batches of different part types do not compete for one cache bucket.  → TO-15, TO-16
- SC-10 Pending `QueryHints` / `NextQueryHints` make `Execute` of a batch with at least one part throw `LinqToDBException` before any command, and stay pending; `Add` does not check them; an empty batch sends nothing and does not check them.  → TO-17, TO-8
- SC-11 `Add` refuses with `ArgumentException`, recording nothing, a part whose result is a task (`Task`, `Task<T>`, `ValueTask`, `ValueTask<T>`, also under a conversion to `object`) and a part that creates one anywhere in its body (a call, a constructor, a property, or a field of a value the part computes — inside an anonymous type too); it accepts a part that reads the result of a task held by a captured variable, a static field or a constant (A-1).  → TO-18
- SC-13 A part that reads a handle of its own batch makes `Execute` throw the not-run `InvalidOperationException`, and the batch stays un-run.  → TO-21
- SC-14 An `IQueryable<T>`-typed part reads its rows inside the batch: on a combining provider the run is one command and enumerating the value sends nothing.  → TO-22
- SC-12 Existing behaviour is unchanged: the existing `QueryBatchTests` (tuple arities 2…7 through the untouched `NewQueryBatchTuple`) and `SelectScalarTests` stay green, and no baseline of an existing test moves.  → TO-19

## P3 Constraints & anti-goals (M/L)

- Public API is additive: `LinqExtensions.CreateQueryBatch`, `QueryBatchBuilder`, `QueryBatchResult<T>`, and `ErrorHelper` constants (internal namespace). No existing member changes signature.
- No engine change: no edit under `Source/LinqToDB/Internal/Linq/**` or `Source/LinqToDB/SqlQuery/**`; no SQL change and no query-cache key change for any existing query; `NewQueryBatchTuple`'s shape for arities 2…7 unchanged.
- Anti-goal (kept from #6111 P3): no pending state on the context — no registry, no flush, no Dispose behaviour.
- Anti-goal (the user's calls, 2026-11-11): no `IQueryable` shortcut overloads, no interfaces, no re-executable or incremental batch, no Faulted state, no lazy `Value`, no snapshot of captured values at `Add`.
- Anti-goal (the user's call): one round trip on a remote context. Remote runs sequentially, as `db.QueryBatch` does, and the docs promise nothing about it.
- Anti-goal — #1404 still narrowed, disclosed in the PR body ("Part of #1404"): deferred writes, a value from one statement feeding the next, subset flushing ("groups").
- User-visible deltas vs the parent branch (#6111): one new API family; no existing call changes behaviour. Shipped prose restating a contract this changes: none (searched the `<summary>` / `<remarks>` of `LinqExtensions.QueryBatch*`, `LinqExtensions.QueryBatch.cs:23-107`; they describe the one-call form only).

## P4 Unknowns (M/L)

- U-1 Does a runtime-built `ValueTuple<…>` body (a member-bound `New`, nested through `Rest` past seven) through `QueryBatch<TTuple>` read every part kind? — resolved-by probe: round 1 — 10, 9, 8 and 7 parts (collections at `Item6` / `Item7`, scalars in `Rest`), a single scalar, a single `List`, an anonymous-typed part and an all-client batch equal the parts alone on all six contexts, sync; round 2 (after critic round 2) — 15 parts with a `List` at index 7, an entity at 8, an anonymous type at 9, an array at 10, a value list at 12, an entity at 13 and a `List` at 14 (`Rest.Rest.Item1`) equal the parts alone on all six, sync and async, and so do the first 10 async; direct 1 reader (+1 begin with a collection) sync and async — the async log line counts the parts-alone reads too (10 = 1 + 9, 15 = 1 + 14, one client constant each) — remote 3 readers (10 parts) / 5 (15 parts).
- U-2 Does the single-lambda `QueryBatch<TTuple>` reach `NewQueryBatchTuple`? — resolved-by scout: no; with two arguments `ScalarSelectBuilder.cs:28-29` takes the body as written, so an 8+ tuple never reaches `NewQueryBatchTuple`, whose `GetField("Item8")` would be null (`LinqExtensions.QueryBatch.cs:460`); the builder needs no change.
- U-3 Does a nested `Rest` tuple meet the builder's tuple special cases? — resolved-by scout + probe: the only `ValueTuple` handling is the eager-load key code (`ExpressionBuilder.EagerLoad.cs:78-123,426-472`, member-less `New`), and `EagerLoadKeyedQuery.cs:264-278` truncates `Rest` only when a tuple is materialised as an entity; a member-bound `New` is visited per member (`ExpressionBuildVisitor.cs:1035-1070`) and projected per member (`ExpressionBuilder.SqlBuilder.cs:1510-1577`); U-1's round-2 batch (eager-loaded collections, entities and an anonymous type inside `Rest` and `Rest.Rest`) confirms.
- U-4 Does `IQueryProvider.Execute<object>` over `ExpressionQueryImpl<TTuple>` take the path `QueryBatch<TTuple>` takes? — resolved-by scout + probe: `TResult` appears only in the final casts (`ExpressionQuery.cs:132,144,312,325`); the hint check (`:119,302`), the load transaction and `TryGetCombinedEagerEnumerable` key on the instance's `T`; the probe ran exactly this path (`Provider.CreateQuery(call)`, then `Execute<object>` / `ExecuteAsync<object>`).
- U-5 Does a failed `Execute` consume anything a retry needs? — resolved-by scout + probe: `Info` is not memoised (`GetQuery(..., cache: false)`, `ExpressionQuery.cs:99-110`); `Preambles` is never assigned for a batch, which always sets `GetEagerElement` (`ScalarSelectBuilder.cs:168-184`); the load transaction and the connection lock are `using`-scoped (`ExpressionQuery.cs:121,304`, `DataContextTransaction.cs:195-222`); `NextQueryHints` is never reached (refused at `Query.cs:192-196`). Probe: a retry after a strict `First` over an empty part and after a missing-table error returned the values on all six contexts.
- U-6 What does a retry inside the user's own transaction do after a database error? — resolved-by probe: SQLite.MS and SqlServer.2022.MS retry and read the values; PostgreSQL.16 leaves the transaction aborted (`25P02: current transaction is aborted`), so nothing runs until the user rolls back.
- U-7 What does an already-cancelled token do on the inherited path? — resolved-by probe: it reaches the provider first — SQLite.MS scalars-only 1 reader then `OperationCanceledException`, with a collection 1 begin then `TaskCanceledException`; SqlServer.2022.MS 1 reader or 1 begin then `TaskCanceledException`; remote 0 client-side readers. A retry with a live token succeeded on all six.
- U-8 What does a task in a part do? — resolved-by probe: `() => items.ToListAsync(default)` is evaluated on the client and the batch returns a started `Task` (`AsyncStateMachineBox`) on all six contexts, a query running outside the batch on the batch's connection and observed by nobody (round 2: the same as `Add<object>(…)`, a `Convert` body, and inside an anonymous member, `new { A = items.ToListAsync(default) }`, where the direct contexts traced extra BEGINs). #6111's `db.QueryBatch` takes the same bodies through the same path. (A-1) Reading `.Result` of a task held by a captured variable, a static field or a constant starts nothing: TO-18's accepted arms read their values in the batch's single reader on SQLite.MS.
- U-9 What does a part over another context's table do? — resolved-by probe: values are correct; the part runs as its own query on the other context (1 reader there, direct), outside the batch.
- U-10 What does a context disposed between `Add` and `Execute` do? — resolved-by probe: `ObjectDisposedException` from the context on all six.
- U-11 Do same-shaped parts with different closures, and one lambda added twice, read their own values? — resolved-by probe: a loop over `id` 1…3 read 1, 2, 3; one `Count` and one `ToList` lambda each added twice read equal values; all six contexts.
- U-12 Is a second run of the same call sites a cache hit, and which cache bucket does a batch use? — resolved-by probe + scout: the same two parts with a new `take` → miss delta 0 on `Query<ValueTuple<int, List<…>>>` (SQLite.MS). The bucket key is `(resultType, contextType, ConfigurationID, flags, ChainHash)` and `ChainHash` stops at `SqlQueryRootExpression` (`QueryCache.cs:503-553`), cap 16 (`:57`): 17 distinct one-part shapes of `ValueTuple<int>` make the first a miss again (delta 1), and so do 17 shapes through #6111's public `db.QueryBatch<int>` (delta 1). `QueryCache.cs` is identical on origin/master fdc08bfe6a (`git diff --stat` empty), so on master every root `db.Select` of one result type shares one bucket.
- U-13 Which instrument lets TO-16 go red under a fusion type that ignores the part types? — resolved-by probe + scout: a pair on the per-type counter (`QueryCache.cs:228-231`) — the first run of a one-part batch moves `Query<ValueTuple<int>>.CacheMissCount` by 1 (probe: 17 one-part shapes, 17 misses), the rerun after the 1…17-part batches by 0; under `object[]` the first move is 0. Rejected: an `ActivityService` factory counting `ActivityID.GetQueryCreate` — `AddFactory` has no removal (`ActivityService.cs:70-82`) and would switch activity tracing on for every later test of a Release run (critic round 2).
- U-17 What does a part that reads a handle of its own batch do (`batch.Add(() => q.Where(x => x.Id > total.Value).ToList())`)? — resolved-by probe: with a stand-in handle whose `Value` throws, `Execute` throws that `InvalidOperationException` unwrapped, 0 readers, on all six; direct contexts sent and rolled back a BEGIN first (the load transaction starts before the parameters are read).
- U-18 What does an `IQueryable<T>`-typed part do (`batch.Add(() => items.Where(…))`)? — resolved-by probe: it is loaded inside the batch as a collection: direct 1 reader for the batch, the value is an `EnumerableQuery<T>` over the rows, enumerating it sends nothing; remote 2 readers; all six contexts.
- U-20 (A-2) What does a new part count cost, given that each distinct sequence of part types closes new generic types that are never unloaded? — resolved-by probe: scratch `TypeGrowth`, SQLite.MS, deltas after a full GC per new count N of `Count` parts. Tuple, N = 4…16: ~32 KB managed, ~68 JIT-compiled methods, ~7.4 KB IL each. `object[]` fusion over the same N: ~20 KB, ~39 methods, ~3.4 KB IL each (≤ 16, so its shared bucket evicts nothing). A count seen before: ~3 KB and ~2–3 methods, the same for both. Tuple, N = 17…64: ~57 KB; N = 65…128: ~111 KB — the query grows with N. So the generic types cost ~12 KB managed and ~29 methods per new count, beside what any new cached query costs. The native JIT code is not in `GC.GetTotalMemory`, and neither are the method tables of the closed types (loader heap; critic round 4). So this is a floor of the permanent cost, measured for homogeneous `int` parts on net10.0 only.
- U-19 Which SC-1 kinds does a provider refuse inside a batch? — resolved-by scout: on Sybase a strict `First` of a value that reads the row marker (a nullable value, a converter, a computed value) is refused with `Error_JoinToDerivedTableWithTakeInvalid` (`QueryBatchTests.cs:1742,1825,1960`, #6111 A-6); an entity `First` reads (#6111 A-6, E-19); YDB refuses only strict `Single` reads (`QueryBatchTests.cs:420,1668,1888`). Sybase and YDB are not run locally; CI is their measurement.
- U-14 Can a test hold `ExecuteAsync` in flight (TO-9)? — resolved-by scout: `CommandInterceptor.ExecuteReaderAsync` is virtual and returns a `Task` (`CommandInterceptor.cs:26`), so an interceptor can await a gate; an interceptor forces the concat backend (`DataConnection.cs:1110`), which TO-9 does not observe.
- U-15 Is the runtime tuple type serialized on a remote context? — resolved-by scout + probe: no; the client sends the statement only (`RemoteDataContextBase.QueryRunner.cs:186-216`), field types come back per column (`LinqService.cs:291-357`), the mapper builds the tuple on the client; U-1's remote runs confirm.
- U-16 Which reflection and cancellation APIs are banned? — resolved-by scout: `Type.GetConstructor(Type[])` (`Source/BannedSymbols.txt:239`) → `GetConstructorEx` (`ReflectionExtensions.cs:394`); `Activator.CreateInstance` (`:288-293`) → `ActivatorExt`; `CancellationToken.IsCancellationRequested` (`:18`) → `ThrowIfCancellationRequested`; `MakeGenericType`, `MakeGenericMethod`, `FieldInfo.GetValue` and `Type.GetField(string)` are allowed. No live trimming annotations exist in `Source/LinqToDB` (searched `RequiresUnreferencedCode|RequiresDynamicCode|DynamicallyAccessedMembers`).

## P5 Decisions (M/L; rejected alternatives mandatory at L)

### D-1 — An explicit batch object the caller holds

- **chosen:** `db.CreateQueryBatch()` returns a `QueryBatchBuilder` that the caller holds and passes to any method. `Add` records a lambda and returns a `QueryBatchResult<T>`. `Execute` runs every part through one `QueryBatch` call.
- **rejected:**
  - Context-level futures (`DeferValue` / `CompleteDefer`) — they need pending state on the context, flush triggers and Dispose behaviour (#6111 P5 D-1 and P3, kept).
  - A lazy `Value` that runs the batch on the first read — hidden synchronous I/O in async code (the user's call).
  - `IQueryable` shortcut overloads and interface types — the user's call: minimal surface.
- **why this:** the object carries the registration across call sites without the context knowing about it. One `QueryBatch` call keeps one build and one `ParametersContext`, so the `AccessorId` collision of independent builds cannot occur. It also keeps the read transaction, the hints refusal and the strict element operators of the node.
- **failure mode of the choice:** a forgotten `Execute` surfaces at the first `Value` read, not at the batch. The batch is not thread-safe, like `DataContext`.

### D-2 — Parts fuse into one runtime-built `ValueTuple`

- **chosen:**
  - The tuple type is built from the parts' body types: `ValueTuple<T1…T7>`, nested through `Rest` beyond seven parts.
  - The body is a member-bound `New` over the fields `Item1…Item7` and `Rest`, in a `Func<TTuple>` lambda, under the node `Methods.LinqToDB.QueryBatch.MakeGenericMethod(tupleType)`.
  - It runs through `ExpressionQueryImpl.CreateQuery(tupleType, …)` and `Execute<object>` / `ExecuteAsync<object>`.
  - Each handle reads its field through a `FieldInfo` path computed at `Execute`. The closed tuple type depends on every part, so the path cannot exist at `Add`. A read through `Rest` boxes each nested tuple once per read.
- **rejected:**
  - One `object[]` body — every batch would be `QueryBatch<object[]>`, sharing one 16-entry cache bucket per context type (critic round 1, `QueryCache.cs:503-553`, refuted).
  - `object[]` plus a `ChainHash` that hashes the body — a change to cross-cutting core.
  - `NewQueryBatchTuple` as it is — it cannot nest (`:460`).
  - The eager-load `GenerateKeyExpression` (`ExpressionBuilder.EagerLoad.cs:90-123`) — it builds a member-less `New`.
  - A compiled accessor per shape — one compilation per new shape, for a read done once per part per run.
- **why this:** the result type is the cache identity the engine already uses, and up to seven parts the shape is the one #6111's tuple overloads exercise. No engine edit. The batch is built on #6111's `QueryBatch`, as the user confirmed at approval: `Execute` builds the same node in its one-lambda form and runs it the way `QueryBatch<T>`'s body does (`LinqExtensions.QueryBatch.cs:76-79`), with the tuple type known only at run time. So every change to `QueryBatch` on #6111 reaches the batch.
- **failure mode of the choice:** batches with identical part types still share one bucket, as every root `db.Select` / `QueryBatch` of one result type does on master (U-12); a 17th live shape of the same types evicts the oldest. Separating input for the rejected `object[]`: batches of 1…17 `Count` parts, then the one-part batch again — 0 builds with the tuple, 1 with `object[]` (TO-16). Boxing: the tuple is boxed once per run and each field once per read.

### D-3 — Lifecycle: single use, a failure leaves the batch un-run

- **chosen:** the states are Pending → Running → Executed.
  - `Add` works only in Pending.
  - `Execute` starts from Pending. Success moves the batch to Executed, so it is single-use.
  - Any exception, including one thrown before the first await, returns the batch to Pending with no value set, so it can be retried.
  - An empty batch's `Execute` sends nothing and moves to Executed.
  - `Value` throws unless the batch is Executed — including while Running, so a part that reads a handle of its own batch fails every run (U-17). The remarks on `Value` say a handle is read after `Execute`, never inside a part.
  - Order of checks in `Execute` / `ExecuteAsync`: the state first (Running or Executed → `InvalidOperationException`), then the token (D-4), then the empty batch (no command and no hints check), then the `QueryBatch` node with its inherited checks (hints, disposed context).
- **rejected:**
  - A Faulted state that rethrows the original exception (the user's call).
  - A re-executable or incremental batch (the user's call).
  - An empty `Execute` that stays Pending — then "run" would depend on the part count.
- **why this:** a batch is a list of expressions, and a failure consumes nothing (U-5).
- **failure mode of the choice:** a retry inside a user transaction that the error aborted fails again until the user rolls back (PostgreSQL, U-6). The remarks say the retry runs in the caller's transaction as it stands.

### D-4 — `Execute()` and `ExecuteAsync(token)`; cancellation checked first

- **chosen:** `Execute()` and `ExecuteAsync(CancellationToken token = default)`, with the parameter named as on #6111's overloads. `ExecuteAsync` calls `token.ThrowIfCancellationRequested()` right after the state check (D-3's order), so a batch that already ran reports that, not the token. Everything else is inherited from the `QueryBatch` node: the hints refusal, the read transaction, combining, strict element operators and the sequential remote path.
- **rejected:**
  - Async only (the user's call).
  - Relying on the token to reach the provider — a command or a BEGIN goes out first, and the exception type differs per provider (U-7).
- **why this:** the pre-check makes "nothing sent" true on every provider, at one line's cost.
- **failure mode of the choice:** cancellation after the pre-check is the provider's (`TaskCanceledException` on SQL Server). The docs promise only `OperationCanceledException`, which `TaskCanceledException` derives from.

### D-5 — Captured values are read at `Execute`

- **chosen:** `Add` stores the lambda as written. Closures are read when `Execute` builds the parameters, which is C#'s and deferred LINQ's semantics (the user's call).
- **rejected:** a snapshot at `Add` — it needs partial evaluation of the tree and differs from the rest of LINQ.
- **why this:** no code; the behaviour every LINQ user expects.
- **failure mode of the choice:** a value changed between `Add` and `Execute` is read in its changed state — intended, documented in `Add`'s remarks, pinned by TO-14.

### D-6 — Remote contexts inherit the sequential path

- **chosen:** no code and no doc promise. On a remote context the parts run one by one, with no read transaction, as `db.QueryBatch` does (#6111 P10; the user's call).
- **rejected:** a `NotSupportedException` on remote — extra code and a test, and it would diverge from `db.QueryBatch`.
- **why this:** zero cost; the values are the same (U-1).
- **failure mode of the choice:** "one round trip" does not hold on remote; the remarks say only that a context which cannot combine runs the parts one after another.

### D-7 — Names and shape

- **chosen:**
  - `QueryBatchBuilder` and `QueryBatchResult<T>` (the user's call), created by `LinqExtensions.CreateQueryBatch(this IDataContext)`, which is `[Pure]`.
  - `Add<T>(Expression<Func<T>> part)`, not `[Pure]`.
  - Both classes are sealed; `QueryBatchResult<T>` has an internal constructor.
- **rejected:**
  - A class named `QueryBatch` — it collides with the method in docs and `cref`s.
  - `DeferredQueryBatch` / `Deferred<T>`.
  - `IQueryBatch` interfaces.
- **why this:** the name says what it builds; a sealed class adds the smallest surface.
- **failure mode of the choice:** `QueryBatchBuilder` sits in the root namespace next to the `QueryBatch` methods; the XML docs cross-reference both.

### D-8 — `Add` refuses a part that holds a task

- **chosen:** `Add` throws `ArgumentException` (`Error_QueryBatch_TaskPart`) and records nothing when the part's result, conversions stripped, is a `Task`, `Task<>`, `ValueTask` or `ValueTask<>`, or when its body holds a node of such a type that is not a held task. A held task is a constant, or a field whose receiver chain ends in a constant (a captured variable) or is static; reading one starts nothing. A call, a constructor, a property, or a field of a value the part computes, may start one (A-1).
- **rejected:**
  - Accept the part — it starts an unobserved query outside the batch, on the batch's connection (U-8).
  - Check `T` alone — misses `Add<object>(…)` and a task inside an anonymous member, both measured (U-8, critic round 2).
  - Refuse in the `QueryBatch` node — that widens #6111's surface; reported to the user as a #6111 finding instead.
- **why this:** a task created in a part is never translated; it runs as a separate, unobserved query. A part whose result is a task reads nothing. A walk per `Add` costs little beside the build.
- **failure mode of the choice:** some bodies that start nothing are refused, because their task comes through a node that could start one — `tcs.Task.Result`, an auto-property holding a task, `tasks[0].Result`, `(Task)ready`, `cond ? a : b`, `Task.FromResult(2).Result`. The workaround is to capture the task (or its result) into a local first; the `ArgumentException` doc says a captured variable is allowed. A custom awaitable and an `IAsyncEnumerable<T>` part are not refused (unmeasured). A part over another context's table also runs outside the batch (U-9), but it is awaited and correct, so it is not refused.

## P6 Edit-points

- E-1 `Source/LinqToDB/QueryBatchBuilder.cs:QueryBatchBuilder` — new public sealed class: state (D-3), `Add<T>` (null check, D-8's walk, records the lambda and its handle), `Execute` / `ExecuteAsync` (D-3's order of checks, D-4, through E-3's helpers); XML docs restate SC-2, SC-4…SC-8, SC-10, SC-11, SC-14, D-3's transaction line and D-6's remark, and point to `QueryBatch{T}`'s remarks for combining, strictness, SQL order and provider refusals.
- E-2 `Source/LinqToDB/QueryBatchResult{T}.cs:QueryBatchResult` — new public sealed class with an internal constructor; `Value` throws `InvalidOperationException` (`Error_QueryBatch_NotExecuted`) unless its batch ran; XML docs restate SC-4 and SC-13 (read a handle after `Execute`, never inside a part).
- E-3 `Source/LinqToDB/LinqExtensions/LinqExtensions.QueryBatch.cs:CreateQueryBatch` — new `[Pure]` extension; an internal builder of the nested tuple type and its member-bound `New` (D-2) beside `NewQueryBatchTuple`, which stays unchanged; `CreateQueryBatchExpression` gains a non-generic overload taking the lambda and its type; (A-1) a `<seealso>` from `QueryBatch<T>` to `CreateQueryBatch` — restates P1 (reads from several call sites go through the batch).
- E-4 `Source/LinqToDB/Internal/Common/ErrorHelper.cs` — `Error_QueryBatch_NotExecuted`, `Error_QueryBatch_AlreadyExecuted`, `Error_QueryBatch_Running`, `Error_QueryBatch_TaskPart`.
- E-5 `Source/LinqToDB/PublicAPI/PublicAPI.Unshipped.txt` — the new public members and constants, in the root file only (the per-TFM files hold the header only, as on #6111).
- E-6 `Tests/Linq/Linq/QueryBatchTests.cs` — TO-1 … TO-18 and TO-20 … TO-22 in the owning fixture, reusing `NoFromlessSubquery`, `BatchItem`, `CommandTrace`, `Traced`, `PageIds`.

## P7 Impact map (M/L)

- `Source/LinqToDB/LinqExtensions/LinqExtensions.QueryBatch.cs:454-463` `NewQueryBatchTuple` — callers `:449` (`Combine`) and `ScalarSelectBuilder.cs:30` (searched `NewQueryBatchTuple` across `Source/`, `Tests/`); left as it is, the nesting builder is new and separate — covered by E-3
- `Source/LinqToDB/LinqExtensions/LinqExtensions.QueryBatch.cs:433-439` `CreateQueryBatchExpression` — callers `:76`, `:103` only (searched the name across `Source/`) — covered by E-3
- `Source/LinqToDB/Internal/Reflection/Methods.cs:213` `Methods.LinqToDB.QueryBatch` — used only at `LinqExtensions.QueryBatch.cs:437`; the builder matches by declaring type and name (`ScalarSelectBuilder.cs:20-21`, `ExpressionTreeOptimizationContext.cs:196`), so a `MakeGenericMethod` instance is recognised (U-1) — covered by E-3
- `Source/LinqToDB/Internal/Linq/Builder/ScalarSelectBuilder.cs:28-35` — a single-lambda batch takes its body as written, requests combining and pushes the strict and Default modifiers (searched `IsQueryBatch|CombinedCommandsRequested` across `Source/`) — out-of-scope (consumed unchanged; U-1, U-2)
- `Source/LinqToDB/Internal/Linq/ExpressionQuery.cs:114-145,295-326` `Execute<TResult>` / `ExecuteAsync<TResult>` — called with `TResult = object`; `TResult` is read only in casts; no `Info` memo (`:99-110`) — out-of-scope (consumed unchanged; U-4, U-5)
- `Source/LinqToDB/Internal/Linq/ExpressionQueryImpl.cs:19-24` `CreateQuery(Type, …)` — the non-generic factory E-1 uses — covered by E-1
- `Source/LinqToDB/Internal/Linq/QueryCache.cs:503-553` bucket key and `ChainHash` — a batch keys on its tuple type; batches of identical part types share one bucket, as every root `db.Select` / `QueryBatch` of one result type does on master (U-12) — deferred: master behaviour of `ChainHash`, filed as #6297
- `Source/LinqToDB/Internal/Linq/Query.cs:192-196` `ThrowIfQueryBatchHasQueryHints` — callers `ExpressionQuery.cs:119,302,335`, `CompiledTable{T}.cs:185,206` (searched the name) — out-of-scope (inherited; TO-17 proves the batch reaches it)
- `Source/LinqToDB/Internal/Linq/Query.cs:326-352` load transaction — `using`-scoped in both entry points (`ExpressionQuery.cs:121,304`) — out-of-scope (inherited; TO-11, TO-12)
- `Source/LinqToDB/Internal/Linq/QueryRunner.cs:1123,1158-1162` combine gate and `CanCombineCommands` — out-of-scope (inherited; TO-3)
- `Source/LinqToDB/Remote/RemoteDataContextBase.QueryRunner.cs:186-216` — sends the statement only, no result type (U-15) — out-of-scope
- `Source/LinqToDB/DataContextTransaction.cs:94-104` — a `BeginTransaction` that throws (cancelled while opening) leaves the `DataContext`'s connection held until the next release (scout, not measured) — deferred: master behaviour of every eager query; D-4's pre-check keeps an already-cancelled token away from it
- `Source/BannedSymbols.txt:18,239,288-293` — banned cancellation and reflection APIs (U-16) — covered by E-1
- `Source/LinqToDB/PublicAPI/PublicAPI.Unshipped.txt:301-315,328` — #6111's lines live in the root file; the per-TFM `PublicAPI.Unshipped.txt` files hold only the header (searched `QueryBatch` across all `PublicAPI*.txt`) — covered by E-5
- `Source/LinqToDB/Internal/Common/ErrorHelper.cs:28-30` — `public const string`, each listed in `PublicAPI.Unshipped.txt` (`:328`) — covered by E-4
- User-facing docs — `QueryBatch` appears in no readme, docs folder or KB page (searched `QueryBatch` in `Source/**/*.md`, `NuGet/`, `docs/`, `.claude/docs/`, `.claude/knowledge-base/`: plan files only); the wiki and nuget.org metadata are out of reach of a repo search and list no `db.Select`-style API; (A-1) `QueryBatch<T>`'s XML docs gain a `<seealso>` to `CreateQueryBatch` — covered by E-1, E-3
- `Tests/Linq/Linq/QueryBatchTests.cs:30-155` — fixture helpers reused by the new tests — covered by E-6
- `.claude/plans/` — searched `QueryBatch|CreateQueryBatch|LinqExtensions.QueryBatch`: the parent plan `feature-1404-query-batch/` (its P3 and P10 lines on cross-call-site registration are answered here) and one mention in `feature-5717-dml-output-as-source/gaps.md:11` — out-of-scope

## P8 Test obligations (M/L)

- TO-1 `ExplicitBatchReadsEachPart` — fifteen parts of SC-1's kinds in U-1's round-2 order (a `List`, an entity and an array past the seventh part, a `List` as the fifteenth in `Rest.Rest`), each `Value` equal to the part alone, `[Values] bool isAsync`; `Traced`, so no SQL baseline (as #6111 A-1); separates: the seed gives each part a distinct value — providers: `[DataSources(NoFromlessSubquery)]` (direct and remote; SqlCe is the file DB; Access out for the FROM-less subquery, as #6111; no strict `First` of a value, so no Sybase refusal applies, U-19) — proof: red→green — mutation "read part i from field i+2"
- TO-2 `ExplicitBatchOfEightPartsAndOfOne` — exactly eight parts (seven plus `ValueTuple<T8>` in `Rest`) and a one-part batch — providers: `[IncludeDataSources(TestProvName.AllSQLite)]` (the nesting is decided before any SQL; engine test) — proof: red→green — mutation "flat eight-field tuple, eighth part as `Rest`"
- TO-3 `ExplicitBatchSendsOneCommand` — a count and a page, `[Values] bool useCombinedCommands`: 1 reader where `UsesCombinedQueryBatch()`, otherwise the reader count of `db.QueryBatch` over the same two parts, measured in the same test — providers: `[DataSources(false, NoFromlessSubquery)]` — proof: red→green — mutation "run each part through its own QueryBatch"
- TO-4 `PartsFromSeveralMethods` — the `Page<T>` shape: the count added in one local method, the page in another, sync and async — providers: `[IncludeDataSources(TestProvName.AllSQLite)]` — proof: characterization (no product code decides where `Add` is called; proves the headline shape compiles and reads)
- TO-5 `SameShapedPartsReadTheirOwnValues` — a loop adding `Count(i => i.Id <= id)` for `id` 1…3 reads 1, 2, 3; one `Count` lambda and one `ToList` lambda each added twice read equal values — providers: `[IncludeDataSources(TestProvName.AllSQLite)]` — proof: characterization (U-11 measured it on the parent's engine; guards a future parameter dedupe)
- TO-6 `ValueBeforeExecuteThrows` — `Value` before `Execute` throws `InvalidOperationException` with `Error_QueryBatch_NotExecuted`, and no reader was sent — providers: `[IncludeDataSources(TestProvName.AllSQLite)]` — proof: red→green — mutation "Value returns default when not run"
- TO-7 `ExecutedBatchRefusesAddAndExecute` — after a successful run, `Add` and `Execute` (sync and async) throw `Error_QueryBatch_AlreadyExecuted` — providers: `[IncludeDataSources(TestProvName.AllSQLite)]` — proof: red→green — mutations "no state check in Add" and "no state check in Execute", one per arm
- TO-8 `EmptyBatchSendsNothing` — an empty batch's `Execute` / `ExecuteAsync` (`[Values] bool isAsync`, A-1) sends 0 readers and 0 begins, also with a `NextQueryHints` entry pending (which stays pending); `Add` afterwards throws `Error_QueryBatch_AlreadyExecuted` — providers: `[IncludeDataSources(TestProvName.AllSQLite)]` — proof: red→green — mutations "empty batch builds a query", "empty batch stays Pending" and (A-1) "empty async batch stays Pending", "empty async batch builds a query"
- TO-9 `RunningBatchRefusesAddAndExecute` — an interceptor holds `ExecuteReaderAsync` on a gate (U-14); while held, `Add` and `Execute` throw `Error_QueryBatch_Running` and a handle's `Value` throws `Error_QueryBatch_NotExecuted`; released, the run completes with the values — providers: `[IncludeDataSources(TestProvName.AllSQLite)]` — proof: red→green — mutations "no Running check in Add", "no Running check in Execute" and "Value reads the slot while Running"
- TO-10 `RefusedHintsLeaveTheBatchRetryable` — `NextQueryHints` pending: `ExecuteAsync` throws `LinqToDBException`; the hints cleared, `ExecuteAsync` returns the values — providers: `[IncludeDataSources(TestProvName.AllSQLite)]` — proof: red→green — mutation "Running not reset on a throw"
- TO-11 `FailedRunLeavesTheBatchRetryable` — a strict `First` over an empty part throws `InvalidOperationException`; the other part's `Value` throws not-run; a row is inserted; the same batch then reads both values; `[Values] bool isAsync` — providers: `[IncludeDataSources(true, TestProvName.AllSQLite)]` (direct and remote) — proof: red→green — mutations "a failed run counts as executed" and (A-1) "the catch leaves the state Running"; a literal "move to Executed before running" still meets the catch's reset and stays green here, and TO-9 and TO-21 catch it
- TO-12 `DatabaseErrorLeavesTheBatchRetryable` — a count over a table that does not exist yet plus a page: the first run throws the provider's exception; the table created, the retry reads 0 and the page — providers: `[IncludeDataSources(TestProvName.AllSQLite, TestProvName.AllPostgreSQL)]` (PostgreSQL aborts a transaction on error, so the batch's own read transaction must have been rolled back, U-6) — proof: characterization (the rollback is the node's; D-3's own clause is TO-11's mutation)
- TO-13 `CancelledTokenSendsNothing` — a count and a page under an already-cancelled token: `ExecuteAsync` throws `OperationCanceledException`, 0 readers, 0 begins; a retry with a live token returns the values — providers: `[IncludeDataSources(TestProvName.AllSQLite, TestProvName.AllSqlServer)]` (U-7 measured a reader or a BEGIN on both before the pre-check) — proof: red→green — mutation "remove ThrowIfCancellationRequested"
- TO-14 `CapturedValuesAreReadAtExecute` — `take` changed after `Add` reaches the page — providers: `[IncludeDataSources(TestProvName.AllSQLite)]` — proof: characterization (closure semantics; no product code decides it)
- TO-15 `SameCallSitesReuseTheCachedQuery` — `[QueryCacheTest]`; a local function adds the same two parts twice with a different `take`; `Query<ValueTuple<int, List<BatchItem>>>.CacheMissCount` does not move on the second run, and the second page has the new size — providers: `[IncludeDataSources(TestProvName.AllSQLite)]` — proof: characterization (the cache identity is the engine's; a reference-typed constant would be parameterised, so no simple product mutation reddens it)
- TO-16 `PartTypesKeyTheCachedQuery` — `[QueryCacheTest]`; the first run of a one-part `Count` batch moves `Query<ValueTuple<int>>.CacheMissCount` by 1; batches of 2…17 `Count` parts follow; the one-part batch again moves it by 0 (U-13) — providers: `[IncludeDataSources(TestProvName.AllSQLite)]` — proof: red→green — mutation "fuse into object[]"
- TO-17 `PendingHintsAreRefusedAtExecute` — `QueryHints` and `NextQueryHints` arms: `Add` succeeds, `Execute` throws `LinqToDBException` with `Error_QueryHints_In_QueryBatch`, 0 readers, the hint still pending — providers: `[IncludeDataSources(TestProvName.AllSQLite)]` — proof: characterization (the refusal is the node's, #6111 TO-9; proves the batch reaches it)
- TO-18 `TaskPartIsRefused` — refused arms, each an `ArgumentException` with `Error_QueryBatch_TaskPart`: `Add(() => items.ToListAsync(default))`, `Add<object>(() => items.ToListAsync(default))`, `Add(() => new { A = items.ToListAsync(default) })`, a `ValueTask<int>` part, (A-1) `RefusedPartRuns()` (throws if ever called, so a refused part that was still recorded fails the run), a captured existing task as the result and as `object`, and `HoldTask().Pending.Result` (a field of a computed value); accepted arms, read in the same run of 1 reader: `.Result` of a captured task, of a static-field task, and of a constant task — providers: `[IncludeDataSources(TestProvName.AllSQLite)]` — proof: red→green — mutations "no task check", "check T only", (A-1) "refuse every task-typed node", "record the refused part" (red through `RefusedPartRuns`; the reader count could not see it), "drop the constant arm", "skip any field", "no result-type check" (U-8)
- TO-20 `StrictValueReadsReadAsThePartAlone` — NULL in a row that exists (`Where(Id == 3).Select(Value).First()`), a string `First` and an anonymous-type `First`, beside a count, each `Value` equal to the part alone; the whole batch carries the sibling's `[ThrowsForProvider(typeof(LinqToDBException), TestProvName.AllSybase, ErrorMessage = ErrorHelper.Sybase.Error_JoinToDerivedTableWithTakeInvalid)]` (`QueryBatchTests.cs:1742`, U-19) — providers: `[DataSources(false, NoFromlessSubquery)]` (as the sibling) — proof: characterization (the strict reads are #6111's; proves they survive the fusion)
- TO-21 `HandleReadInsideAPartFails` — `batch.Add(() => items.Where(i => i.Id > total.Value).ToList())` where `total` is a handle of the same batch: `Execute` throws `InvalidOperationException` with `Error_QueryBatch_NotExecuted`, 0 readers, and `total.Value` still throws not-run (U-17) — providers: `[IncludeDataSources(TestProvName.AllSQLite)]` — proof: red→green — mutation "Value reads the slot while Running" (the part then reads 0 and the run succeeds)
- TO-22 `QueryablePartReadsInsideTheBatch` — `batch.Add(() => items.Where(i => i.Id < 3))` beside a count: 1 reader where `UsesCombinedQueryBatch()`, the value enumerates to the two rows and enumerating sends nothing more (U-18) — providers: `[IncludeDataSources(TestProvName.AllSQLite, TestProvName.AllSqlServer)]` (both combining backends) — proof: characterization (the eager load of an `IQueryable` member is #6111's projection path)
- TO-19 `ExistingSuitesUnchanged` — the existing `QueryBatchTests` (tuple arities 2…7 through `NewQueryBatchTuple`) and `SelectScalarTests` stay green, and no existing baseline moves; symmetry guard on the unchanged tuple path of E-3 — providers: SQLite.MS, SqlServer.2019.MS or SqlServer.2022.MS, PostgreSQL.16 — proof: characterization

## P9 Verification gates

- G-01: pass — 2026-11-11, uncommitted tree on f798e94b51, Testing net10.0 with `BaselinesPath` set, final tree after A-1 (rebuilt after the last mutation run): `QueryBatchTests` on SQLite.MS, SQLite.Classic, SqlServer.2022.MS (stands in for 2019, `sql2019` stopped), PostgreSQL.16, SqlCe and their `.LinqService` — 591 total, 589 passed, 0 failed, 2 skipped (`MarkerSurvivesCteUnion`, `[ActiveIssue(5823)]`), the 88 new cases all passed; after the last two analyzer fixes (NUnit1032, IDE0340) SQLite.MS + SQLite.Classic 320 / 318 / 0 failed / 2 skipped. Before A-1 the same five providers gave 589 / 587 / 0 / 2 with 86 new cases. First run: `FailedRunLeavesTheBatchRetryable` failed on the four `.LinqService` cases with the remote/direct baselines check (remote runs the parts one by one), fixed with `Traced` as #6111 A-1 did.
- G-01: pass — mutations through `mutation-run.ps1` (`.build/.agents/explicit-batch-mutations.json`, SQLite.MS + `.LinqService`, the 21 new tests): green 32 / 0 failed; 17 mutants, every one caught, every file restored byte-exact (`restored: true`). Per obligation below.
- G-01 TO-1: pass — mutation "read part i from field i+2", applied as reading the next field (`read-part-from-next-field`, `(index + 1) % 7 + 1`): red on all four `ExplicitBatchReadsEachPart` cases (direct and remote, sync and async), with 22 other new cases.
- G-01 TO-2: pass — mutation "flat eight-field tuple, eighth part as `Rest`" (`flat-eight-field-tuple`, `> 7` → `> 8`): `ExplicitBatchOfEightPartsAndOfOne` red, and `ExplicitBatchReadsEachPart` ×4.
- G-01 TO-3: pass — mutation "run each part through its own QueryBatch" (`own-querybatch-per-part`): `ExplicitBatchSendsOneCommand` red on both arms, `trace.Readers should be 1 but was 2`.
- G-01 TO-4: pass — characterization; green, red only under the field-shift mutant.
- G-01 TO-5: pass — characterization; green.
- G-01 TO-6: pass — mutation "Value returns default when not run" (`value-default-when-not-run`): `ValueBeforeExecuteThrows` red.
- G-01 TO-7: pass — mutation "no state check in Add" (`no-state-check-in-add`): both `ExecutedBatchRefusesAddAndExecute` arms red; mutation "no state check in Execute" (`no-state-check-in-execute`, both methods): both arms red.
- G-01 TO-8: pass — mutation "empty batch builds a query" (`empty-batch-builds-query`): `EmptyBatchSendsNothing` red; mutation "empty batch stays Pending" (`empty-batch-stays-pending`): red; (A-1) "empty async batch stays Pending" (`empty-async-stays-pending`): the `isAsync: true` case red, `Add` should throw; "empty async batch builds a query" (`empty-async-builds-query`, r4): the `isAsync: true` case red, `IndexOutOfRangeException`.
- G-01 TO-9: pass — mutations "no Running check in Add", "no Running check in Execute" and "Value reads the slot while Running" (`no-running-check-in-add`, `no-running-check-in-execute`, `value-reads-slot-while-running`): `RunningBatchRefusesAddAndExecute` red under each. The test checks that the refused second `ExecuteAsync` is already completed, so the mutant fails instead of waiting on the held reader.
- G-01 TO-10: pass — mutation "Running not reset on a throw" (`running-not-reset-on-throw`): `RefusedHintsLeaveTheBatchRetryable` red (and both async `FailedRun…` cases).
- G-01 TO-11: pass — mutation "a failed run counts as executed" (`failed-run-counts-as-executed`, both catches set Executed): all four `FailedRunLeavesTheBatchRetryable` cases red; (A-1) "the catch leaves the state Running" (`catch-leaves-running`): all four red, "The query batch is being executed.".
- G-01 TO-12: pass — characterization; green on SQLite.MS, SQLite.Classic, PostgreSQL.16; red under TO-11's mutant.
- G-01 TO-13: pass — mutation "remove ThrowIfCancellationRequested" (`no-cancellation-precheck`): `CancelledTokenSendsNothing` red, `trace.Begins should be 0 but was 1`.
- G-01 TO-14: pass — characterization; green.
- G-01 TO-15: pass — characterization; green.
- G-01 TO-16: pass — mutation "fuse into object[]" (`fuse-into-object-array`: a `NewArrayInit` body read back by index): only `PartTypesKeyTheCachedQuery` red, `afterFirst - before should be 1 but was 0`; every other new test passed under the `object[]` mutant, so the cache key is the one thing that separates D-2 from its rejected alternative.
- G-01 TO-17: pass — characterization; green.
- G-01 TO-18: pass — mutation "no task check" (`no-task-check`): `TaskPartIsRefused` red; mutation "check T only" (`check-T-only`): red, `add should throw System.ArgumentException`; (A-1) "refuse every task-typed node" (`refuse-every-task-node`): red, the accepted captured-task arm throws; "record the refused part" (`record-refused-part`): survived the reader-count instrument (r2), red with "A refused part was recorded." (r3); "drop the constant arm" (`drop-constant-arm`, r4): red, the accepted arms throw; "skip any field" (`skip-any-field`, r4): red, `HoldTask().Pending.Result` is accepted; "no result-type check" (`no-result-type-check`, r4): red, the existing task as the result is accepted.
- G-01 TO-19: pass — characterization; the existing `QueryBatchTests` (tuple arities 2…7 through `NewQueryBatchTuple`) are inside the 589-case run above, green. `SelectScalarTests` not run locally.
- G-01 TO-20: pass — characterization; green on the five local providers; its Sybase declaration is unrun locally.
- G-01 TO-21: pass — mutation "Value reads the slot while Running": `HandleReadInsideAPartFails` red.
- G-01 TO-22: pass — characterization; green on SQLite.MS, SQLite.Classic, SqlServer.2022.MS; red under `own-querybatch-per-part` (readers).
- G-01: blocked — CI `test-all` on the pushed head (not started): MySqlConnector.8.0 (its container is stopped), Sybase (TO-20's declaration), YDB, Oracle, DB2, Informix, SAP HANA, ClickHouse, Firebird, MySQL / MariaDB, DuckDB, and `SelectScalarTests` on every provider.
- G-01: pass — conventions: `test-diff-sweep.ps1 -Base f798e94b51 -IncludeWorkingTree`, outside the scratch probe: 0 chains, 0 nested chains, 21 narrowed sets with 0 lacking a reason line, 0 Shouldly-subject or type-only gates, 0 unanchored gates (first sweep: 1 chain, 2 nested chains, 12 without a reason — fixed).
- G-02: blocked — CI baselines PR: the new tests that are not `Traced` write new baselines; no existing baseline should move, because no engine code changed and `CreateQueryBatchExpression` builds the same node for the existing overloads; the local baselines folder is not a git clone, so it cannot show a diff.
- G-03: pass — 7 public members and 4 `ErrorHelper` constants in the root `PublicAPI.Unshipped.txt`; `Source/LinqToDB` Release `-f net10.0 -p:RunApiAnalyzersDuringBuild=true`: no RS0016 / RS0017 on the new surface; control: with `QueryBatchResult<T>.Value.get` removed, RS0016 on that symbol. The same build reports 3 RS0016 on `AccessSqlExpressionConvertVisitor` overrides from master's #6203, which origin/master fdc08bfe6a's PublicAPI files also lack — not this branch's. XML docs on every new public member.
- G-04: pass — additive surface; no `CompatibilitySuppressions.xml` changed (`git status`).
- G-05: pass — `Source/LinqToDB` Release `-f net10.0` and `-f netstandard2.0`: 0 warnings, 0 errors, DLLs rewritten; `Tests/Linq` Release `-f net10.0 -p:NuGetAudit=false`: 0 errors after fixing 5 IDE0200, then NUnit1032 (a static task field in the fixture, moved to a nested static class) and IDE0340 (restore without the flag fails on NU1903 / NU1902 advisories for test-host packages, unrelated to this change). Re-run after A-1: `Source/LinqToDB` net10.0 with API analyzers — only the three #6203 Access RS0016; netstandard2.0 0 errors.
- G-06: pass — the diff touches only E-1 … E-6 files; `-Action reconcile -Base origin/feature/1404-query-batch`: 6 covered, unplanned only the scratch probe.
- G-07: pass — `Tests/Tests.Playground/ExplicitBatchProbe.cs` is untracked and is not staged.
- G-08: n/a — no cross-cutting core path in P6 (`-Action gates`)
- G-01: pass — A-1 mutations (`explicit-batch-mutations-r2.json` / `-r3.json` / `-r4.json`, SQLite.MS + `.LinqService`, the 21 new tests): green 33 / 0 failed each time; r4's four mutants all red, per TO-8 and TO-18 above; "refuse every task-typed node" → `TaskPartIsRefused` red (`ArgumentException` on the accepted arm); "empty async batch stays Pending" → `EmptyBatchSendsNothing(isAsync: true)` red; "the catch leaves the state Running" → all four `FailedRunLeavesTheBatchRetryable` cases red ("The query batch is being executed."); "record the refused part" → first survived under the reader-count instrument, then red with "A refused part was recorded." after the throwing-part arm; every file restored byte-exact.
- G-09: pass — `code-reviewer` (2026-11-11) on the uncommitted diff: 2 MIN, 5 SUG, 2 NIT, every one applied (A-1); state machine, tuple nesting for 7 / 8 / 14 / 15 / 22 parts, async, PublicAPI and banned APIs checked clean by it.

## P10 Adjudicated (M/L)

- Batches with identical part types share one cache bucket (cap 16), as every root `db.Select` and `QueryBatch` of one result type does on master (U-12, measured for #6111's `db.QueryBatch<int>` too). A fix belongs to `QueryCache.ComputeChainHash` on master — descend into the quoted lambda of a root `db.Select` / `QueryBatch` — filed as #6297 (Backlog, the user's call; measured for `db.Select<long>` alone: the 17th selector evicts and the evicted one rebuilds), not done here.
- A part over another context's table runs as its own query on that context, outside the batch, with the right value (U-9). Not refused: detecting it needs a walk of every part, and the result is correct.
- `db.QueryBatch` on #6111 accepts a task in its body and starts an unobserved query (U-8). Only the explicit batch refuses it here (D-8); the #6111 case is reported to the user.
- A handle cannot feed a part of its own batch (U-17): "a value from one statement feeding the next" stays out of scope (P3), and the run fails with the not-run error rather than reading a default. A direct context sends and rolls back a BEGIN before the failure.
- An `IQueryable<T>`-typed part is loaded inside the batch as a collection and returned as an in-memory `IQueryable<T>` (U-18). Composing on it later runs in memory, not in the database. That is #6111's projection behaviour, documented in `Add`'s remarks, not changed.
- A retry inside a user transaction that the error aborted fails until the user rolls back (PostgreSQL, U-6).
- A `BeginTransaction` that throws while opening leaves a `DataContext`'s connection held until the next release (`DataContextTransaction.cs:94-104`, scout, not measured). Master behaviour of every eager query.
- Remote contexts run the parts one by one with no read transaction, as `db.QueryBatch` does (#6111 P10, U-10 there).
- (A-2, the user's call 2026-11-11: document) A batch whose parts follow the data builds and caches one query per distinct set of parts (their number, order and types). Each new sequence of part types also closes generic types that are never unloaded: at least ~12 KB managed and ~29 JIT-compiled methods per new count; the loader and code heaps were not measured (U-20). Conditional parts of one type share a tuple type, so their subsets share one 16-entry bucket: six optional `Count`s taken three at a time give 20 shapes, and the oldest is evicted (critic round 4, not run). `QueryBatchBuilder`'s remarks state the rule. Not bounded in code. The fusion type is internal — only TO-16 pins it — so after #6297 the batch can move to `object[]` with no API change.
- Every limit #6111's P10 records for a part applies here unchanged: strict `First` / `Single` and their exceptions, SQL in eager-load order, the Sybase and YDB refusals, Access's FROM-less refusal.

## P11 Amendments (M/L)

- A-1 (2026-11-11, G-09: `code-reviewer` read of the uncommitted diff; every finding applied, SUG001 with a different instrument) — no new edit-point; E-3 widened by one doc line.
  - MIN001: D-8's walk refused a part that reads `.Result` of a captured, existing task, which starts nothing. The walk now skips a constant and a field. A call, a constructor or a property yielding a task is still refused. TO-18 gains an accepted arm, red under "refuse every task-typed node".
  - MIN002: the async empty branch had no test. TO-8 now runs both entry points; red under "empty async batch stays Pending".
  - SUG001: TO-18 could not see a refused part that is still recorded. The reviewer's instrument (reader count) stayed green under "record the refused part" (measured: a recorded task part starts its query outside the trace). The instrument is instead a refused part whose call throws, and TO-18 goes red with "A refused part was recorded."
  - SUG002: TO-11's mutation text did not describe the run. A literal "move to Executed before running" meets the catch's reset and stays green there; TO-9 and TO-21 catch it. TO-11 now names "a failed run counts as executed" and "the catch leaves the state Running", both measured red.
  - SUG003: a successful run clears the parts and the setters (`Complete()`), so a kept result pins nothing else. Not test-observable; covered by reading.
  - SUG004: TO-12 drops `BatchLater` first, so a table left by an interrupted PostgreSQL run cannot turn it green.
  - SUG005: `QueryBatch<T>` gains `<seealso cref="CreateQueryBatch(IDataContext)">`, which restates P1. D-7's "the docs cross-reference both" now holds.
  - NIT001: `Add`'s `part` doc no longer says "anything `QueryBatch` accepts".
  - NIT002: loop counter and local `Run` functions renamed.
  - Out of scope, for the user: every distinct sequence of part types closes new generic types, which are never unloaded — the nested `ValueTuple`, `ExpressionQueryImpl<TTuple>`, `Query<TTuple>`, `Func<TTuple>` — and JIT-compiles their struct instantiations. A part count that depends on data grows them by the largest count seen. Unmeasured; see the question to the user.
  - After critic round 3, which attacked this amendment:
    - The field skip is tied to a receiver chain that ends in a constant or is static, so `HoldTask().Pending.Result` is refused.
    - A part whose result is a task is refused, also under a conversion to `object`.
    - `Error_QueryBatch_TaskPart` and `Add`'s `<exception>` say "returns or creates a task … could run", and that a captured variable is allowed.
    - D-8's "why" and failure mode name the refused bodies that start nothing, with the workaround.
    - TO-18 gains a refused arm per shape and accepted arms for a static field and a constant.
    - TO-8 gains the mutation "empty async batch builds a query".
  - re-derives: SC-11, P4 (U-8: held tasks), P7 (the user-facing docs row: `QueryBatch<T>`'s new `<seealso>`), D-8, E-1, E-3, TO-8, TO-11, TO-18; G-01 rows for them; G-09.
  - conventions: testing.md → *Test layout*, *A narrowed provider set is a claim* and *Gating an assertion failure* were embedded at authoring and re-checked here. The sweep was re-run after these edits (`test-diff-sweep.ps1 -Base f798e94b51 -IncludeWorkingTree`); counts are in G-01.
- A-2 (2026-11-11, the review's out-of-scope note on closed generic types; the user's calls: "measure, then decide", then "document") — U-20 measured the cost. `QueryBatchBuilder`'s remarks gain one sentence stating the rule: the parts (their number, order and types) are part of the cached query, so a batch whose parts follow the data builds a query for each distinct set of parts. This is round 4's correction of a first wording that named only the count. There is no case list, following the user's rule for public docs. The text sits inside E-1's existing XML-doc authorization; no P6 row changes and no code behaviour changes. `Source/LinqToDB` Release `-f net10.0`: 0 errors.
  re-derives: P4 (U-20), P10 (the part-count line), D-2 (its failure mode gains the per-count cost through U-20), E-1's remarks (text only).

## P12 Critic verdict (M/L)

Round 1 (plan-critic, model fable, 2026-11-11, on the pre-plan before this file existed): **refuted.**
- The `object[]` fusion was refuted: every explicit batch shares one 16-entry cache bucket per context type (`QueryCache.cs:503-519,525-553,57`). Verified by reading, then measured (U-12). The user chose the runtime `ValueTuple` (D-2), and TO-16 separates the two.
- Accepted and folded in:
  - the up-front cancellation check (D-4), whose need U-7 then measured;
  - TOs for loop-added and same-instance parts (TO-5), for `Running` (TO-9, TO-10), for a database-error retry (TO-12), for a remote retry (TO-11) and for a one-part batch (TO-2);
  - the `Traced` rule for `[DataSources]` with remote cases (TO-1);
  - the parameter name `token`;
  - no `[Pure]` on `Add`.
- The fresh `ExpressionQueryImpl` per `Execute` became moot: a batch never assigns `Preambles`, and `Info` is not memoised (U-5). A fresh one is still built, because `Execute` builds the expression anew.
- The critic found the altitude sound: the node carries hints, the transaction and strictness.

Round 2 (plan-critic, model fable, 2026-11-11, on this file; the same model family proposed D-2 in round 1, so it was told to treat D-2 like any other decision): **weak.** It found no missed engine touch-point: every node consumer matches by name and declaring type. Objections and what changed — probed where a probe could answer (round-2 probe, six contexts, 9/9 green):
- TO-1 put a Sybase-refused read in a batch with every other kind, so on Sybase the whole test would throw (`QueryBatchTests.cs:1742`). Confirmed by grep (U-19). TO-1 now holds no strict `First` of a value; those reads moved to TO-20 with the sibling's declaration (new SC-1b).
- U-1 / U-3 had no collection, entity or anonymous part inside `Rest`, no `Rest.Rest`, and async only up to two parts. Probed (U-1 round 2): fifteen parts with those kinds at indexes 7–14, sync and async, all six green, async also one command. TO-1 now uses that order.
- D-8's check on `T` missed `Add<object>` and a task inside an anonymous member. Both measured (U-8). D-8 now walks the body, TO-18 has four arms, and the "why" no longer says "the only shape" (U-9 also leaves the batch).
- Lead: an `IQueryable<T>`-typed part. Probed (U-18): loaded inside the batch; SC-14, TO-22, a P10 line.
- Lead: a handle read inside a part. Probed (U-17): the not-run error surfaces unwrapped; SC-13, TO-21, a P10 line, a remark on `Value`.
- The order of checks was unspecified, so a cancelled token on an executed batch would have contradicted SC-4, and an empty batch skips the hints refusal. The order is now in D-3 (state, token, empty, node) and D-4. SC-10 is qualified, and TO-8 gains the empty-batch-with-hints arm.
- TO-16's `ActivityService` factory would have left global state. It is replaced by the per-type miss pair (U-13). TO-15 and TO-12 are relabelled characterization. TO-9 gains a `Value`-while-Running arm.
- D-2's `FieldInfo` path is computed at `Execute`, not `Add`, and nested `Rest` reads box: said so in D-2.

Carried verdict: **weak**, with every objection answered in the text above. Unprobed and left to CI: Sybase and YDB, where U-19's refusals are read from the sibling declarations.

Round 3 (plan-critic, model fable, 2026-11-11, on A-1 and the implemented code; G-09's `code-reviewer` round preceded it): **weak.** It confirmed that `Complete()` is safe — nothing reads the parts or setters after it — and that A-1's four mutants turn red for their stated reasons. Objections and what changed (the A-1 "After critic round 3" line):
- The field skip ignored the receiver, so a field of a value the part computes (`Start(items).Pending.Result`) was accepted again. The skip is now tied to a captured or static receiver, and a TO-18 arm covers it.
- SC-11 said "as its type", while `Add(() => ready)` was accepted. A part whose result is a task is now refused; SC-11 is rewritten and added to `re-derives`.
- D-8's "why" still said no valid body is refused. It now names the refused bodies that start nothing, with the workaround.
- The constant arm had no witness. TO-18 now has a constant-task arm and the mutation "drop the constant arm".
- TO-18's row named the reader count, which A-1 itself had measured as blind. The row is rewritten, and the per-obligation G-01 rows carry the A-1 mutation names.
- The empty async branch's "builds a query" was unmutated. The mutation is added to TO-8.

Carried verdict: **weak**, every objection answered above; no further round (the skill caps a weak verdict at folding the objections in).

Round 4 (plan-critic, model fable, 2026-11-11, on A-2 and the user's question "fuse into `object[]` instead?"; the same family proposed the tuple in round 1 and was told to judge both afresh): **weak.** It recommends keeping D-2 and judged each option:
- (B) `object[]` as is: still refuted — every explicit batch would share one bucket key per context type and configuration.
- (C) `object[]` with #6297 first: outside P3 — a cache-key change for every root `db.Select` / `QueryBatch`, plus a body walk in `BuildKey` on every execution. It becomes viable once #6297 lands.
- (D) the hybrid: rejected — the shared bucket comes back exactly where loop-driven batches land, and the obligations would be owed twice.
- (E) no cheaper key exists without touching `QueryCache`.

A-2's documentation-only disposition holds, conditionally. Objections and what changed:
- U-20 sees only the GC heap. It is now labelled a floor, with the loader and code heaps unmeasured.
- The doc sentence named the count, while the key is the set of parts. It is reworded, and P10 records that conditional same-type subsets share one bucket.
- The fusion type is internal and swappable. P10 records it, with #6297 as the trigger.
- Not acted on, stated here: `_misses` keeps one counter per result type (`QueryCache.cs:67,233`); the rebuild time of an eviction is unmeasured; reference-type and net462 cells of U-20 are unprobed. The critic's settling measurement is `Process.PrivateMemorySize64` across ~2,000 counts, tuple versus `object[]`, on net10 and net462. It has not been run.
