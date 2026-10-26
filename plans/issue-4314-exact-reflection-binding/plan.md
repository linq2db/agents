# Work plan: issue-4314-exact-reflection-binding — Exact reflection lookups: ban default-binder Type[] overloads

**Tier:** L  ·  **Status:** approved  ·  **Approved-at:** 2026-10-25  ·  **Branch:** issue/4314-exact-reflection-binding
**Schema:** `.claude/docs/work-plan.md`  ·  **Gates:** `.claude/docs/definition-of-done.md`

## P1 Problem

`Type.GetConstructor(Type[])` / `GetMethod(name, …, Type[], …)` / `GetProperty(name, …, Type[])` use `Type.DefaultBinder`, which accepts primitive widening (`byte`→`int`), `T`→`Nullable<T>` and similar coercions. `Expression.New` / `Expression.Call` accept only identical or reference-assignable argument types. Nearly every linq2db caller feeds the result to `Expression.New` / `Expression.Call` (exceptions: CLI `QueryExecutionExecutor.cs:955` and `ScaffoldCommand.Interceptors.cs:197-205` reflection-`Invoke` the member, where coercion would work). At the Expression-fed sites a loose match therefore surfaces later as `ArgumentException: Expression of type 'System.Byte' cannot be used for constructor parameter of type 'System.Int32'` instead of a null the caller handles ("Method not found" / feature-detection fallback). #4313 hit it in `TypeMapper` (`(IPAddress,int)` ctor matched for a `byte` request); #4314 asks to close the class. Repro (planned red test): `TypeMapper` wrapper method `M(byte)` mapped onto a dynamic type that declares only `M(int)` → today `Expression.Call` throws `ArgumentException`; expected `LinqToDBException("Method not found in target type: …M(Byte)")`. Same shape for a wrapper ctor at `TypeMapper.cs:672`.

There is also a TFM divergence today: on net462/ns2.0 the arity lookup at `TypeMapper.cs:802` goes to the Meziantou polyfill, which compares `ParameterType != types[i]` (exact), while net8+ `:800` uses the default binder (loose).

## P2 Success criteria

- SC-1 A `TypeMapper`-mapped wrapper method whose argument type needs a value coercion to reach the target overload fails with `LinqToDBException` "Method not found", not `ArgumentException`. → TO-1
- SC-2 Same for a `TypeMapper`-mapped wrapper constructor (`TypeMapper.cs:672`, the #4313 shape). → TO-2
- SC-3 A wrapper argument that is reference-assignable to the target parameter (derived → base, the Devart `OracleLoaderColumnCollection.Add(OracleLoaderColumn)` → `DbLoaderColumnCollection.Add(DbLoaderColumn)` shape) still binds. → TO-3
- SC-4 The new helpers implement D-1 exactly: identical accepted; reference-assignable accepted; `byte`→`int`, `T`→`Nullable<T>`, value→`object` boxing rejected; coercing helper still returns the loose match. → TO-4
- SC-5 ConvertBuilder's intentional coercions (enum→`Nullable<int>` ctor, `decimal`→`op_Explicit(decimal?)`) keep working. → TO-5
- SC-6 No `Type[]` overload of `GetConstructor` / `GetMethod` / `GetProperty` remains callable directly in `Source/` without a Release build error, on net10.0, net462 and netstandard2.0. → TO-6a, TO-6b, TO-6c
- SC-7 No behaviour change on existing paths: the provider adapters' reflection lookups and the EagerLoad / Association / TypeMapping / Convert suites are unchanged, and the DuckDB adapter (the arity helper's only caller) still maps. → TO-7, TO-8

## P3 Constraints & anti-goals (M/L)

- No public API change outside `LinqToDB.Internal.*`. `ReflectionExtensions` is `LinqToDB.Internal.Extensions` (shipped); changing the semantics of `GetMethodEx(name, params Type[])` / `GetPublicInstanceMethodEx` is allowed but disclosed in the PR body.
- No generated-SQL change; no baselines change expected.
- `Tests/` stays out of the ban (it has its own `Tests/BannedSymbols.txt`; tests legitimately probe BCL reflection).
- Not in scope, and not the #4313 failure class: name-based `Expression.Call(instance, "name", typeArgs, args)` (~52 sites) resolves via `MethodCallExpression.FindMethod`, which accepts only reference-assignable args and throws when none match; `ActivatorExt.CreateInstance(type, args)` (`ActivatorExt.cs:87`) and `ComWrapper.InvokeMember(Type.DefaultBinder)` (`ComWrapper.cs:58,65,72`) invoke with real values, where reflection coerces correctly. Follow-up issue dropped after the premise check (2026-10-25).
- No internal Roslyn analyzer (user decision 2026-10-25: banned API + helpers).
- No pragma suppressions at coercion sites (user decision 2026-10-25: separately named coercing helper).

## P4 Unknowns (M/L)

- U-1 Which call sites rely on loose matching today? — resolved-by probe: divergence logger on TypeMapper :672/:800/:804, `GetMethodEx(name, params)`, `GetPublicInstanceMethodEx`, ConvertBuilder:36, Associations:278, EagerLoad:447/:459; ran Tests.TypeMapping + Common.ConvertTests + all 18 `*ProviderAdapter` instances (25 loadable) and a SQLite.MS EagerLoad/Association run (582 tests, 1289 GetMethodEx hits). Divergences: ConvertBuilder:36 (enum→`Nullable<int>(int)`), ConvertBuilder:82-83 via GetMethodEx (`op_Explicit(decimal)`→`(decimal?)`), TypeMapper:804 Devart (derived→base). Nothing else.
- U-2 Does plain `BindingFlags.ExactBinding` suffice? — resolved-by probe: no, it returns null for the Devart derived→base case (U-1) → D-1.
- U-3 Do the reader `GetXxx(int)` / async Open/Close/Dispose/BeginTransaction/Commit/Rollback lookups in adapters change? — resolved-by probe: zero divergences across 25 adapter instances.
- U-4 Does the ban fire on all TFMs? — resolved-by probe: on net462/ns2.0, `GetConstructor(BindingFlags, Type[])` and `GetMethod(name, BindingFlags, Type[])` bind to Meziantou `PolyfillExtensions`, so the ban misses TypeMapper:672, Npgsql:334, ReflectionExtensions:224 there; those three are multi-TFM, so the net8+ legs catch them. No RS0030 inside generated polyfill `.g.cs`. Conversely, netfx/ns2.0-only code is invisible to the net10.0 probe build — see U-9.
- U-5 How many sites? — resolved-by probe: banning the 18 `Type[]` overloads → 58 RS0030 in `Source/LinqToDB` net10.0 (51 on net462), plus satellites by search: CLI `QueryExecutionExecutor.cs:950,955`, `QueryValueFormatter.cs:371`, `ScaffoldCommand.Interceptors.cs:197,201`; EF `EFCoreMetadataReader.cs:619,622` (EF9/10 only).
- U-6 Associations:278 (`PersistentTable<T>` ctor looked up with `result.Type`, which may be `ITable<T>`/`IOrderedQueryable<T>`) — resolved-by scout+probe: reference-assignable to `IQueryable<T>`, so D-1 accepts it; no site fix needed.
- U-7 Generic-arity lookup (`TypeMapper.cs:800-802`) — resolved-by scout+critic: on net462/ns2.0 the BCL has no arity overload (Meziantou polyfill, exact compare), so a default-binder-then-validate helper would keep the TFM split inside itself; D-5 implements the arity helper by enumeration on all TFMs. Only user: `TypeWrapperGenericArgs` at `DuckDBProviderAdapter.cs:305` (`ArgCount 0`, concrete `string` params). D-1 validation skips parameters whose type `ContainsGenericParameters`, mirroring `ReflectionExtensions.cs:196`.
- U-9 `Type[]` sites compiled only on net462/ns2.0 (missed by the net10.0 probe build) — resolved-by critic search over all 180 `GetConstructor|GetMethod|GetProperty` hits in `Source/`: one, `SqlServerDataProvider.cs:208` (`#else` of `#if NET8_0_OR_GREATER` at :195-214), identical types → E-25. The net462 probe count (51) is not on disk to cross-check; TO-6b/c rebuild it.
- U-10 Sites the probe did not instrument — resolved-by critic per-site read: identical by construction (`MakeGenericType(args)` then `GetConstructor(sameArgs)`: `EagerLoad.cs:115-116`, `EagerLoadDefault.cs:90,94`, `EagerLoadKeyedQuery.cs:175,273,598`, `EagerLoadUnion.cs:214,230,275,434,439`, `Associations.cs:248-250`, `AsyncFactory.cs:319-322`; `typeof(…)` literals equal to the declared params: `SqlServerProviderAdapter.cs:422,432-440,544-545`, `RemoteDataContextBase.cs:488-495,524,537`, `TypeMapper.cs:26-27,213`, `MemberAccessor.cs:20`; `NpgsqlProviderAdapter.cs:338` fallback `(IPAddress,int)` identical on Npgsql<8).
- U-8 Does `Source/BannedSymbols.txt` reach CLI / EF / LINQPad? — resolved-by scout: `Source/Directory.Build.props:17` adds it to every `Source/` project; LINQPad adds its own on top (`LinqToDB.LINQPad.csproj:235`); LINQPad has no `Type[]` lookups (search).

## P5 Decisions (M/L; rejected alternatives mandatory at L)

### D-1 — Binding rule: "Expression-compatible" (identical or reference-assignable)

- **chosen:** a lookup succeeds only if every parameter type `P` and requested type `A` satisfy `P == A || (!P.IsValueType && !A.IsValueType && P.IsAssignableFrom(A))` (parameters whose type contains generic parameters are skipped). This is exactly what `Expression.New`/`Expression.Call` accept without an explicit `Convert`. Implementation: keep the default-binder lookup (so overload ranking and inherited-member search are unchanged), then validate the result; on mismatch return null.
- **rejected:** `BindingFlags.ExactBinding` — breaks Devart bulk-copy mapping (U-2) and Associations:278 when `result.Type` is `ITable<T>`. Own candidate enumeration — re-implements overload ranking and ambiguity; more code for no measured gain.
- **why this:** matches the consumer contract (Expression trees), so "lookup succeeded" means "Expression building succeeds".
- **failure mode of the choice:** post-validation can return null where a valid reference-assignable overload exists but the default binder ranked a coercing overload higher (mixed value + reference args, e.g. `(byte,string)` vs overloads `M(int,string)` / `M(byte,object)`). The binder throws `AmbiguousMatchException` for that shape anyway; no such site was found (U-1).

### D-2 — Enforcement: banned API + helpers

- **chosen:** add the 18 `Type[]` overloads of `Type.GetConstructor` / `GetMethod` / `GetProperty` to `Source/BannedSymbols.txt` with a message pointing at the helpers; helpers in `ReflectionExtensions` are the only callers (`#pragma warning disable RS0030` inside the helper bodies only).
- **rejected:** internal Roslyn analyzer (user decision); review-only convention (doesn't stop the next #4313).
- **why this:** RS0030 already runs in Release on CI; zero new infrastructure.
- **failure mode of the choice:** net462/ns2.0 polyfill extension overloads aren't `Type` members, so the ban misses them on those TFMs (U-4) — mitigated by net8+ legs; and RS0030 is Release-only, so `-c Testing` iteration won't show it.

### D-3 — Intentional coercion: separately named helpers

- **chosen:** `GetConstructorCoercing(this Type, params Type[])` and `GetMethodCoercing(this Type, string, params Type[])` keep the default-binder behaviour; XML doc states the caller must reconcile parameter types (ConvertBuilder inserts `Expression.Convert`). Used at ConvertBuilder:36 and :82-83 only.
- **rejected:** `#pragma warning disable RS0030` at the site (user decision); a `bool coerce` parameter on the strict helper (hides the choice in an argument).
- **why this:** the name makes the coercion visible at the call site and greppable.
- **failure mode of the choice:** someone uses `*Coercing` to silence a strict-lookup null instead of fixing the types — reviewable by grep.

### D-4 — Helper surface

- **chosen:** in `LinqToDB.Internal.Extensions.ReflectionExtensions`: new `GetConstructorEx(params Type[])`, `GetConstructorEx(BindingFlags, params Type[])`, `GetMethodEx(string, BindingFlags, params Type[])`, `GetMethodEx(string, int genericParameterCount, BindingFlags, params Type[])`, `GetPropertyEx(string, Type returnType, params Type[])` only if a site needs it (search: none in the 58 → not added); existing `GetMethodEx(string, params Type[])` and `GetPublicInstanceMethodEx` re-implemented on D-1; `GetDefaultConstructorEx` unchanged in behaviour (empty types → D-1 trivially identical). PublicAPI.Unshipped entries for the new members.
- **rejected:** a new internal static class (helpers already live here; `GetMethodEx(returnType,…)` and the generic-count overload are already exact).
- **why this:** one place, existing naming.
- **failure mode of the choice:** overload ambiguity between `GetMethodEx(string, params Type[])` and `GetMethodEx(string, BindingFlags, params Type[])` / `GetMethodEx(string, int, params Type[])` — `BindingFlags`/`int` are not `Type`, so C# resolves without ambiguity; verified by the build.

### D-5 — Generic-arity helper by enumeration on every TFM

- **chosen:** `GetMethodEx(string, int genericParameterCount, BindingFlags, params Type[])` enumerates `GetMethods(flags)`: ordinal name, generic arity (`0` → not a generic method definition), parameter count, D-1 per parameter. If one candidate has all-identical parameters it wins; else exactly one D-1-valid candidate is returned; more than one → `AmbiguousMatchException` (the BCL's outcome for an unresolvable tie). Same code on net462/ns2.0/net8+; removes the `#if NET8_0_OR_GREATER` split at `TypeMapper.cs:799-803` and the polyfill dependency.
- **rejected:** BCL arity overload + post-validate on net8+, polyfill on net462 — keeps the P1 TFM divergence inside the helper (polyfill rejects derived→base). Ban the polyfill too — then the helper itself needs the polyfill on net462, same divergence.
- **why this:** only way to make "unifies TFMs" true; the overload has one caller, so a reimplemented ranking is cheap and fully tested.
- **failure mode of the choice:** where several reference-assignable candidates of different specificity exist, the BCL picks the most specific, this helper throws. The single caller (`DuckDBProviderAdapter.cs:305`) has one candidate.

## P6 Edit-points

- E-1 `Source/LinqToDB/Internal/Extensions/ReflectionExtensions.cs:GetMethodEx/GetPublicInstanceMethodEx/new helpers` — D-1 validation, new strict helpers (D-4), arity helper by enumeration (D-5), coercing helpers (D-3), XML docs on every new public helper (the two public arity overloads must document their differences: the existing `GetMethodEx(string, int, params Type[])` requires `IsGenericMethod` so `0` never matches and it is first-match exact; D-5's treats `0` as non-generic and throws on ties), RS0030 pragma scoped to helper bodies. Strict `BindingFlags` helper bodies call the Binder overloads `GetConstructor(flags, null, types, null)` / `GetMethod(name, flags, null, types, null)` (BCL on every TFM), never the 2-/3-arg forms that bind to the Meziantou polyfill on net462/ns2.0.
- E-2 `Source/BannedSymbols.txt` — 18 `Type[]` overload doc-ids with message.
- E-3 `Source/LinqToDB/PublicAPI/PublicAPI.Unshipped.txt` — new helper members (per-TFM files only if the RS0016 build asks).
- E-4 `Source/LinqToDB/Internal/Conversion/ConvertBuilder.cs:GetCtor/GetOperator/GetValueOrDefault` — :36 and :82-83 → coercing helpers; :54 → strict helper.
- E-5 `Source/LinqToDB/Internal/Expressions/Types/TypeMapper.cs:139,140,213,672,800-804` — strict helpers; remove the `#if NET8_0_OR_GREATER` split at :799-803.
- E-6 `Source/LinqToDB/Internal/DataProvider/SqlServer/SqlServerProviderAdapter.cs` — 14 sites → strict helpers.
- E-7 `Source/LinqToDB/Internal/DataProvider/MySql/MySqlProviderAdapter.cs` — 11 sites → strict helpers.
- E-8 `Source/LinqToDB/Internal/DataProvider/PostgreSQL/NpgsqlProviderAdapter.cs:334,338,368` — strict helpers.
- E-9 `Source/LinqToDB/Internal/DataProvider/Oracle/OracleProviderAdapter.cs:836` — strict helper.
- E-10 `Source/LinqToDB/Remote/RemoteDataContextBase.cs:488,524,537` — strict helpers.
- E-11 `Source/LinqToDB/Internal/Async/AsyncFactory.cs:301,322` — strict helpers.
- E-12 `Source/LinqToDB/Reflection/MemberAccessor.cs:20` — strict helper.
- E-13 `Source/LinqToDB/Concurrency/ConcurrencyExtensions.cs:335` — strict helper.
- E-14 `Source/LinqToDB/Internal/Linq/Builder/ExpressionBuilder.Associations.cs:250,278` — strict helpers.
- E-15 `Source/LinqToDB/Internal/Linq/Builder/ExpressionBuilder.EagerLoad.cs:116,447,459` — strict helpers.
- E-16 `Source/LinqToDB/Internal/Linq/Builder/ExpressionBuilder.EagerLoadDefault.cs:94` — strict helper.
- E-17 `Source/LinqToDB/Internal/Linq/Builder/ExpressionBuilder.EagerLoadKeyedQuery.cs:273,598` — strict helpers.
- E-18 `Source/LinqToDB/Internal/Linq/Builder/ExpressionBuilder.EagerLoadUnion.cs:230,275,439` — strict helpers.
- E-19 `Source/LinqToDB.CLI/CommandLine/Commands/QueryExecution/QueryExecutionExecutor.cs:950,955` — strict helper.
- E-20 `Source/LinqToDB.CLI/CommandLine/Commands/QueryExecution/QueryValueFormatter.cs:371` — strict helper.
- E-21 `Source/LinqToDB.CLI/CommandLine/Commands/Scaffold/ScaffoldCommand.Interceptors.cs:197,201` — strict helpers.
- E-22 `Source/LinqToDB.EntityFrameworkCore/EFCoreMetadataReader.cs:619,622` — strict helpers.
- E-23 `Tests/Linq/TypeMapping/MappingTests.cs` — red tests TO-1/TO-2 and control TO-3 (new `Dynamic`/`Wrappers` fixture types following the file's pattern).
- E-24 `Tests/Linq/Common/ReflectionExtensionsTests.cs` (new) — helper contract tests TO-4.
- E-25 `Source/LinqToDB/Internal/DataProvider/SqlServer/SqlServerDataProvider.cs:208` — netfx/ns2.0-only `JsonSerializer.Deserialize` lookup → `GetMethodEx("Deserialize", BindingFlags.Public | BindingFlags.Static, typeof(string), jsonSerializerOptionsType)` (keeps today's public-only candidate set).

## P7 Impact map (M/L)

- `ReflectionExtensions.GetMethodEx(string, params Type[])` callers in `Source/` (8: `ReflectionExtensions.cs:136` `GetMemberEx` with 26 callers passing a real `MemberInfo`'s parameter types; `ConvertBuilder.cs:82,83,153,158,163,181,190`; Tests bind the name-only overload) — probe: 1289 SQLite-run hits + all TypeMapping/Convert tests, only ConvertBuilder:82-83 diverged — covered by E-1, E-4
- `ReflectionExtensions.GetPublicInstanceMethodEx` callers (`AsyncFactory.cs:247,337`) — probe: 9 hits, no divergence — covered by E-1
- The 58 RS0030 sites in `Source/LinqToDB` (net10.0 probe build, `.build/.agents/4314-probe-net10.log`) — uninstrumented ones identical by construction per U-10 — covered by E-4..E-18
- netfx/ns2.0-only `Type[]` site `SqlServerDataProvider.cs:208` (U-9) — covered by E-25
- CLI `QueryExecutionExecutor.cs:950,955` / `ScaffoldCommand.Interceptors.cs:197,201` reflection-`Invoke` consumers: strict helper is stricter than the consumer needs; requests are `[typeof(int)]` (ordinal reader getters, identical) and `(ScaffoldOptions)` / empty (identical) — no site affected — covered by E-19, E-21
- CLI / EF satellites (search `\.(GetConstructor|GetMethod|GetProperty)\(` over `Source/` minus `LinqToDB/`) — covered by E-19..E-22
- `LinqToDB.LINQPad` — searched same pattern, no `Type[]` lookups — out-of-scope
- `LinqToDB.Remote.Wcf`, EF3 (old-TFM-only, ban doesn't fire through polyfills) — searched, no sites — out-of-scope
- F# (`LinqToDB.FSharp`) — RS0030 doesn't run on F#; searched, no `Type[]` lookups — out-of-scope
- Name-based `Expression.Call(…, "name", …)`, `ActivatorExt.CreateInstance(type,args)`, `ComWrapper.InvokeMember` — out-of-scope: not the #4313 failure class (P3)
- Contract change throw→null: `TypeMapper` handles null at :674 / :806 (`IgnoreMissingMembers` abort or `LinqToDBException`); at every other site the request is identical by construction (U-10) or probed without divergence (U-3), so null can only replace today's `ArgumentException`, never a working binding (critic trace of `DefaultBinder.SelectMethod`) — covered by E-5..E-11
- Meziantou polyfill `GetMethod(name,int,BindingFlags,Type[])` (net462 `TypeMapper.cs:802`) — removed by E-5 (helper unifies TFMs) — covered by E-5

## P8 Test obligations (M/L)

- TO-1 `MappingTests`: wrapper `M(byte)` → dynamic `M(int)` throws `LinqToDBException` "Method not found"; discriminating input: `byte` arg vs `int`-only overload (today: `ArgumentException`) — providers: none (no DB) — proof: red→green
- TO-2 `MappingTests`: wrapper ctor `(byte)` → dynamic ctor `(int)` throws `LinqToDBException`; discriminating input: `byte` vs `int`-only ctor — providers: none — proof: red→green
- TO-3 `MappingTests`: wrapper method taking a mapped derived type binds to a dynamic method declared on the base type (Devart shape); symmetry guard on the reference-assignable path; mutation that turns it red: swap D-1 for `BindingFlags.ExactBinding` — providers: none — proof: control
- TO-4a `ReflectionExtensionsTests`: identical param types → found — providers: none — proof: characterization
- TO-4b derived→base param → found — providers: none — proof: control (mutation: `ExactBinding`)
- TO-4c `byte`→`int` → null from strict helper, non-null from `GetMethodCoercing` — providers: none — proof: red→green (today `GetMethodEx(name, params)` returns `M(int)`)
- TO-4d `int`→`int?` → null from strict, non-null from coercing — providers: none — proof: red→green
- TO-4e `int`→`object` (boxing) → null from strict — providers: none — proof: red→green
- TO-4f `GetConstructorEx`: `(byte)` request vs `(int)`-only ctor → null; `(Derived)` vs `(Base)` ctor → found; mutation that turns it red: drop the D-1 post-validation in the helper (a new helper can't be red on master for the right reason) — providers: none — proof: control
- TO-4g arity helper: generic-arity lookup with a concrete derived→base param returns the method on net10.0 **and net462** (today net462 polyfill returns null, net10.0 default binder returns it); plus one generic-parameter param case — providers: none, TFMs: net10.0 + net462 — proof: control (mutation: exact compare instead of D-1 → net462 and net10.0 both red)
- TO-5 `ConvertTests.NullableParameterInOperatorConvert` (`Tests/Linq/Common/ConvertTests.cs:532`) + the enum→`int?` ctor path stay green — providers: SQLite.MS — proof: characterization (proves no new behaviour)
- TO-6a Release build of `Source/LinqToDB` net10.0 + CLI + EF.Core net10.0 has 0 RS0030; mutation: a raw `typeof(X).GetMethod("M", [typeof(int)])` in `Source/LinqToDB` → RS0030 — providers: none — proof: control
- TO-6b Release build of `Source/LinqToDB` net462 has 0 RS0030 (catches E-25-class netfx-only sites); same mutation → RS0030 on net462 — providers: none — proof: control
- TO-6c Release build of `Source/LinqToDB` netstandard2.0 has 0 RS0030; same mutation → RS0030 on ns2.0 — providers: none — proof: control
- TO-7 characterization runs, unchanged pass set vs master: `Tests.TypeMapping|Tests.Common.ConvertTests` (no provider) and EagerLoad/Association on SQLite.MS — providers: SQLite.MS — proof: characterization (proves no new behaviour); CI full matrix covers provider adapters
- TO-8 D-5's single production caller: a DuckDB-filtered run (net10.0) constructs `DuckDBProviderAdapter` and maps `CreateAppender` via `[TypeWrapperGenericArgs(0)]` (`DuckDBProviderAdapter.cs:89-91,305`; non-generic and arity-2 overloads share parameter types, so a wrong arity filter → `AmbiguousMatchException` or the generic overload) — providers: DuckDB — proof: characterization (proves no new behaviour); net8+ only, the package has no net462 asset

## P9 Verification gates

- G-01: — (pending)
- G-02: — (pending)
- G-03: — (pending)
- G-04: — (pending)
- G-05: — (pending)
- G-06: — (pending)
- G-07: — (pending)
- G-09: — (pending)

## P10 Adjudicated (M/L)

- The ban doesn't fire on net462/ns2.0 for polyfill-bound overloads (U-4): the three such sites are multi-TFM and net8+ legs catch them; netfx/ns2.0-only code calling a polyfill-bound overload would slip through — none exists today (U-9 search). Banning the polyfill doc-ids is not worth it once D-5 removes the helpers' polyfill use; revisit only if such a site appears.
- Unprobed adapter variants (assembly not loadable locally, `4314-divergence.log:9,24,31`): Sybase Unmanaged (`Sybase.AdoNet45.AseClient`), Oracle Native (`Oracle.DataAccess`), Informix (`IBM.Data.Informix`). They share the adapter code paths probed for the loadable variants; their own wrappers are covered only by CI.
- Probe run timing (1h15m for 582 SQLite.MS tests, one `LinqService` gRPC 100 s timeout in `Select_KeyedQuery_NestedChildProjectsGrandparentFieldFallback`) attributed to the probe's per-call `StackFrame` + locked log writes; TO-7 re-runs without the probe.

## P11 Amendments (M/L)

_None._

## P12 Critic verdict (M/L)

**Current verdict: weak** (round 2; all round-2 objections addressed below, not re-critiqued)

Round 2 — **weak** (plan-critic, `fable`, 2026-10-25). All six round-1 objections confirmed closed. Objections and response:

- weak — P7 row still said "follow-up issue pending" while P3 said dropped → P7 row now `out-of-scope` citing P3; critic confirmed the P3 premise for `ActivatorExt` / `ComWrapper` from source, `Expression.Call` from recalled BCL source (not re-read).
- weak — D-5's one caller (`DuckDBProviderAdapter.cs:305`) had no local obligation → added TO-8 (DuckDB run). Critic decompiled DuckDB.NET 1.5.5: D-5 returns the same single non-generic `CreateAppender` as the BCL arity path.
- minor — E-25 widened flags to NonPublic → E-25 uses `Public | Static`.
- minor — two public arity overloads differ on `0` and tie semantics → documented in E-1.
- minor — P10's "D-5 removes polyfill use" conditional on helper bodies → E-1 names the Binder overloads.

Round 1 — **refuted** (plan-critic, `fable`, 2026-10-25). Objections and response:

- refuted — missed netfx/ns2.0-only site `SqlServerDataProvider.cs:208` (the ban would turn CI's Release build red) and TO-6 was net10.0-only → verified by reading :195-214; added E-25, U-9, P7 row, TO-6b/6c; rewrote the P10 "all multi-TFM" entry.
- weak — D-1 vs E-5 unclear for the arity helper on net462 → added D-5 (enumeration on all TFMs); TO-4g now uses a derived→base concrete param on net462.
- weak — P7 adapter row cited a probe that didn't instrument those sites → replaced by the critic's per-site identical-by-construction list (U-10); unloadable adapter variants added to P10.
- weak — TO-4f red→green would fail as a compile error → changed to `control` with a named mutation.
- weak — P1 "every caller feeds Expression" overstated → qualified; CLI `Invoke` sites row added to P7.
- minor — `GetMethodEx` caller count corrected (8 in `Source/`); E-1 now owes XML docs on every new helper.

Critic's strongest point: D-1 can only turn today's `ArgumentException` into a null callers already handle, never a working binding into null.
