## Codebase design invariants

Design-level facts about what linq2db *is* as a library. These are invariants agents should preserve and reviewers should enforce — they describe the product, not the review workflow. Operational rules for how agents *act* on the codebase live in [`agent-rules.md`](agent-rules.md) → Agent Guardrails.

### Public API is a contract

Types, method signatures, and observable generated SQL in non-`Internal.*` namespaces under `Source/LinqToDB/` are a stability contract for downstream consumers. Don't modify them without a clear, explicit reason — new major-release milestone, documented breaking change, or a namespace-placement fix (see below).

The ApiCompat baseline files at `Source/**/CompatibilitySuppressions.xml` are the enforcement mechanism. Any surface change — add, modify, or remove — requires regenerating them (e.g. `dotnet pack -p:ApiCompatGenerateSuppressionFile=true`, or run the `api-baselines` skill).

### Provider-called core methods are public, not internal

When a provider's SQL builder/optimizer (`YdbSqlBuilder`, any `*SqlBuilder` / `*SqlOptimizer`) calls a *new* method on shared core — `OptimizationContext`, the SQL AST, optimizer/builder base classes — declare that method **`public`**, even when the only in-tree caller lives in the same assembly. Out-of-tree / external providers consume the same surface and need the entry point; `internal` locks them out. (A new public method then needs a `PublicAPI.Unshipped.txt` entry per the contract above.)

### Behavior is part of the public-API contract

The "stability contract" in **Public API is a contract** above covers types and signatures. It ALSO covers observable behavior of long-standing public methods — particularly the ones with a documented combination of in-memory C# and SQL behavior (`Sql.Concat`, `Sql.ConcatStrings*`, similar `Sql.*` helpers). User code has been written against the existing semantics, and a refactor that reshapes an internal pipeline must NOT shift the behavior of these methods even when the refactor's internal symmetry argues for it.

When a refactor seems to require a behavior change on such an API:

- Restore the pre-refactor behavior in the same PR. Don't accept the break with a release-notes callout — the callout doesn't save user code that already relied on the old semantics.
- The PR's design-symmetry / unification argument is not enough; the asymmetry lives inside the implementation, and the implementation can absorb it without exposing it to callers.
- If a behavior change is genuinely necessary, file it as a separate proposal with its own design review, milestone, and migration documentation.

This applies most strongly to APIs that have been public since v1.0 / older majors and have user code behind them. Newer APIs (added in the current major) have less downstream surface and the cost of a behavior change is lower.

**`[Obsolete]` does not unfreeze behavior.** A public method marked `[Obsolete]` stays callable by downstream code until it is actually removed — its observable behavior is as frozen as any other public API. When an *internal* caller (e.g. a member mapping in `Linq/Expressions.cs`) needs corrected behavior, do **not** edit the obsolete method's body: add a private copy with the fix and repoint the internal callers at it, leaving the public method untouched. (Done in #5577: public `ConvertToCaseCompareTo`'s null-returning body stayed frozen; the member mappings moved to a BCL-faithful private `ConvertToCaseCompareToImpl`. That private impl is **gone as of #5613** — `string.CompareTo` moved to a member translator — so don't expect to find it; the public `ConvertToCaseCompareTo` still stands in `Linq/Expressions.cs:1074`, which is the point: the frozen public method outlived the internal workaround.)

### Member-mapping bodies are the local-evaluation definition

A BCL method mapped via `Expressions.MapMember` / a `[Sql.Extension]` method has *two* roles: the SQL builder translates the call to an AST node (e.g. `string.Compare`/`CompareTo` → `SqlCompareToExpression`), and the mapping's **managed body / lambda is the local-evaluation fallback**. The expose pass can expand these mappings, and the test harness `AssertQuery` (plus any genuine client-side evaluation) then runs the expanded form as LINQ-to-objects. So the managed body MUST faithfully reproduce the original BCL method's semantics — including null handling — not just "something the SQL builder ignores".

A body that diverges passes for years while only the SQL path runs, then breaks the moment expose expands it into local evaluation. Concrete case (#5577): `ConvertToCaseCompareTo` returned `null` when an operand was null, which `string.Compare` never does; once the always-expand expose change made `AssertQuery` evaluate it in-memory, the `null` collapsed to `0` via null-propagation and flipped comparisons. Verify both paths: SQL correctness **and** in-memory equivalence.

### `DbType` carries the column type and nothing else

`ColumnAttribute.DbType` is emitted **verbatim** by `BasicSqlBuilder.BuildCreateTableStatement` in place of the built type, which makes it tempting to smuggle other column-definition syntax through it — an identity clause, a default, a constraint. That is **not supported**: the value must be the type alone. Anything else works only for as long as nothing else in the builder writes to the same slot, and silently produces unparseable DDL the moment something does.

So a mapping that spells such syntax in `DbType` is a defect in the mapping, not a compatibility burden on the builder: don't add sniffing (a `Contains("IDENTITY")` guard or similar) to tolerate it, and don't treat breaking it as a regression needing a deprecation path. Fix the mapping to use the real facility — `IsIdentity` / `[Identity]`, a default-value attribute, an explicit constraint. (Established 2026-08-26 on #5773: `OracleTests.ItentityColumnTable` carried `IsIdentity = true` *and* `DbType = "NUMBER GENERATED BY DEFAULT AS IDENTITY …"`; once the Oracle 12 builder began emitting the identity clause itself the column got it twice and `CREATE TABLE` stopped parsing — `ORA-00907`, `ORA-03076` on 23c. Maintainer: *"dbType must contain only type and putting to it unrelated attributes is not supported"*.)

### Calculated columns may also be physical columns; entity construction must not double-emit

A calculated column (`ExpressionMethodAttribute.IsColumn=true`, in `EntityDescriptor.CalculatedMembers`) can simultaneously be a mapped **physical** column. Fluent `EntityMappingBuilder.Property(x)` forces this — it calls `.IsColumn()`, registering a `ColumnAttribute` — whereas `.Member(x)` attaches attributes *without* mapping a column. So `.Property(e => e.X).HasAttribute(new ExpressionMethodAttribute(...) { IsColumn = true })` makes `X` both a physical column and a calculated member; `.Member(...)` makes it calculated-only.

Entity construction must emit each such member **once**: `BuildGenericFromMembers` (in `EntityConstructorBase`) excludes members present in `CalculatedMembers` from the physical-column assignments, because `BuildCalculatedColumns` emits the expanded substitution for them. Use `MemberInfoComparer.Instance` for any `MemberInfo` set here — `column.MemberInfo` can carry a different `ReflectedType` than the `CalculatedMembers` entry, so default equality misses the match. Skipping this dedup emits a bogus physical column read alongside the calculated expression (#5540: PostgreSQL `42703 column … does not exist`; the v6 blanket `ConvertExpressionTree(fullEntity)` pass used to mask it by rewriting the stray read).

### Cross-cutting internals are shared

The SQL AST (`Source/LinqToDB/SqlQuery/` and `Source/LinqToDB/Internal/SqlQuery/`), the `IDataProvider` interface, and the translator interfaces under `Source/LinqToDB/Linq/Translation/` are consumed by every database provider in the repo. A fix scoped to one provider or one test shouldn't reshape them — the blast radius is the whole product. When a local task seems to need a cross-cutting change, surface the question explicitly rather than making the change silently.

### Don't grow core builder API for a helper-only fix

A fix scoped to a helper / peripheral API (e.g. `ToSqlQuery`'s by-name `Query<T>` round-trip) must not expand core builder surface (`ISqlBuilder` / `BasicSqlBuilder`) to serve it — threading a new flag/parameter through the shared builder for one convenience path fails the cost/benefit test. If the fix genuinely needs new core surface, drop or narrow it instead. (User call on #5657: an export-scoping `ForGetSqlText` seam on `ISqlBuilder` was rejected — "if we need to add api changes to sqlbuilder then we will not use this fix for helper API"; the peripheral behavior was left as-is.) This is the API-surface counterpart of the general "propose minimal, let the user expand" preference.

### Companion interfaces to public contracts stay public, in the contract's namespace

An opt-in companion interface extending an existing public contract (e.g. a schema-aware extension of `IMetadataReader`) defaults to **public, in the same namespace as the contract it extends** — not `LinqToDB.Internal.*`, and not `InternalsVisibleTo` (the repo uses none). An extension seam that third parties may implement has no value hidden; it is part of the same contract surface. (User decision on #5675, overriding a proposed `Internal.Metadata` placement: "no value in hiding it".) This does not soften the SQL AST rule below — AST construction types are *not* extension seams and MUST stay in `LinqToDB.Internal.SqlQuery`.

### Never `InternalsVisibleTo` — widen to public in an `Internal.*` namespace

linq2db deliberately carries **no** `[assembly: InternalsVisibleTo(...)]`, and none should be added — not even to give tests access to an `internal` type. IVT makes a member look reachable from a test while it stays unavailable to real consumers, so the test proves something about an accessibility level the product doesn't offer.

When a test needs an `internal` cache or primitive, either widen the type to `public` inside its `Internal.*` use-at-your-own-risk namespace (`QueryCache` is a `public sealed class` in `LinqToDB.Internal.Linq` for exactly this reason — add the `PublicAPI.Unshipped.txt` entries), or expose a purpose-built public diagnostic such as `Tools.GetCacheEntryCounts()`. This is the same reasoning as **Provider-called core methods are public, not internal** above, arriving from the test side.

### Propose the minimal API surface first

When adding public API, propose the **minimal viable surface** — the one or two methods that satisfy the cited issue — then list the *possible* further overloads and ask which to keep before writing them. Do not build out full symmetric overload sets (sync × async × `IDataContext` × `IQueryable` × projected × non-projected × update × delete) up front.

Over-building costs review rounds and `PublicAPI.Unshipped.txt` churn, and the surplus gets cut: 16 proposed `ConcurrencyExtensions` overloads on #5642 were trimmed to 4 (update write-back only) over three rounds, each group questioned in turn. **Don't grow core builder API for a helper-only fix** above is the same preference applied to core surface.

### New API parameters take the weakest useful type

For a **new** public API parameter, prefer the weakest useful type — `IEnumerable<T>` over `T[]` — and fold an optional second dimension into `params` so two overloads collapse into one. Materialize to an array inside the method for query-cache stability.

An **already-shipped** parameter type can't change (an existing `params Type[]` overload stays), but a new sibling is free to use the weaker type. On #5525 this collapsed `IgnoreFilters(string[])` + `IgnoreFilters(string[], Type[])` into a single `IgnoreFilters(IEnumerable<string> filterKeys, params Type[] entityTypes)`.

### Throw when a provider can't honour the contract — don't degrade to best-effort

When a provider cannot honour an API's documented contract, make the API **throw / report unsupported** for that provider rather than silently falling back to a best-effort heuristic. A path that can't guarantee the contract returns misleading results, which is worse than an explicit failure.

Prefer the **broad** throw over the narrow one: on #5643 `UpdateOptimisticWithRefresh`, a no-rowcount `SELECT` fallback mutated the entity yet returned the documented `0`-means-concurrency-failure sentinel, and the verify-by-written-columns fallback was itself unreliable (async ClickHouse mutations read pre-apply). The resolution was to throw `LinqToDBException` — *before* executing any `UPDATE` — whenever the provider supports neither `OUTPUT`/`RETURNING` nor a reliable affected-rows count, deleting the whole best-effort path. Maintainer: *"such databases too broken to use concurrency api — we shouldn't try to do best-effort when it is not guaranteed."*

### `IsDependsOnSources` ignore-set doesn't cover field/column refs

`QueryHelper.IsDependsOnSources(expr, onSources, sourcesToIgnore:)` applies `sourcesToIgnore` only on the **direct `ISqlTableSource`-element** match path. The `SqlField` / `SqlColumn` paths — how predicates actually reference tables — check `OnSources.Contains(field.Table)` / `Contains(column.Parent)` **without** consulting `sourcesToIgnore`. So `sourcesToIgnore` does *not* subtract a table a predicate reaches through a field, and `IsDependsOnSources(pred, [t], sourcesToIgnore: [t])` still returns true.

To ask "does this expression depend on any source *outside* a given subtree" — e.g. is a join predicate purely right-side, in `SelectQueryOptimizerVisitor.MoveJoinConditionsToWhere` — use **`QueryHelper.IsDependsOnOuterSources(expr, currentSources: <subtree sources>)`**, which collects `field.Table` / `column.Parent` and excepts `currentSources` at the field level. Reaching for `IsDependsOnSources(..., sourcesToIgnore:)` here is a dead end.

### Internal AST APIs trust NRT — validation lives in factory extensions

Constructors and `Modify` methods on types under `LinqToDB.Internal.SqlQuery.*` (and peer internal AST namespaces) do **not** carry null / empty argument guards. Validation is the job of the factory extensions (`SqlExpressionFactoryExtensions.Concat`, peers) that provide the validated entry point for broader use; bare AST ctors trust callers to respect `<Nullable>enable</Nullable>` and pass sane parameters. Adding the same guard on the ctor duplicates the check at no benefit and adds noise NRT analysis would have already surfaced.

Reviewer consequence: do **not** flag missing constructor / `Modify` null-or-empty guards on a new AST type as a defect — `SqlConcatExpression`, `SqlCoalesceExpression`, and the rest of the peers follow this convention by design. Exception: when a caller path is genuinely unverified (data off the wire with no schema validation, etc.), surface the concern at the *caller*, not the AST type itself.

### Version-aware translators: derive a subclass, don't parameterize

When provider behavior depends on the database version, the repo's convention is to **create a version-specific translator subclass** and dispatch on `Version` in the data provider's `CreateMemberTranslator()`. Do **not** parameterize the base translator constructor with a feature flag — that's not how the codebase is structured.

Canonical pattern (SqlServer; same shape used by MySql 8/MariaDB):

```csharp
// In <Provider>DataProvider.cs:
protected override IMemberTranslator CreateMemberTranslator() => Version switch
{
    >= SqlServerVersion.v2022 => new SqlServer2022MemberTranslator(),
    >= SqlServerVersion.v2017 => new SqlServer2017MemberTranslator(),
    >= SqlServerVersion.v2016 => new SqlServer2016MemberTranslator(),
    ...
    _                         => new SqlServerMemberTranslator(),
};

// Source/LinqToDB/Internal/DataProvider/SqlServer/Translation/SqlServer2022MemberTranslator.cs:
public class SqlServer2022MemberTranslator : SqlServer2017MemberTranslator
{
    protected override IMemberTranslator CreateStringMemberTranslator() => new SqlServer2022StringMemberTranslator();

    protected class SqlServer2022StringMemberTranslator : SqlServer2017StringMemberTranslator
    {
        // override the methods that gained 2022 support
    }
}
```

Each subclass inherits everything from its lower-version parent and only overrides the methods whose translation actually changed in that version. When two providers gained the same capability in equivalent versions (e.g. MySQL 8 + MariaDB 10 both got `REGEXP_REPLACE`), the data provider's switch can route both versions to the same subclass — no need to create a dedicated subclass that just inherits with no body. A `MariaDB10MemberTranslator : MySql80MemberTranslator {}` empty-body class is non-idiomatic; collapse it into `MySql80 or MariaDB10 => new MySql80MemberTranslator()` in the dispatch instead.

### Never branch provider logic on `ContextName`

`IDataContext.ContextName` defaults to `DataProvider.Name` but is **user-settable**, so it is not a provider identifier. Never branch provider or capability logic on it — no `ContextName.StartsWith("SqlServer")`-style matching, no capability lists keyed by context name. A renamed or custom-named context silently takes the wrong branch, with no error to show for it.

For a per-provider capability use a `SqlProviderFlags` bool (`dc.SqlProviderFlags.X`, and see the next section); for provider identity use the name on `IDataProvider`. (Applied on #5643: a `ConcurrencyOutputSupport` list keyed off `ContextName` was replaced by `SqlProviderFlags.IsUpdateOutputSupported`.)

### A per-provider capability is a `SqlProviderFlags` bool plus a probing guard test

When a feature needs to know whether a provider supports something, expose it as a `SqlProviderFlags` bool set per-provider **and** add a test that probes the provider's actual runtime behaviour and asserts the flag equals the probe result. An unenforced flag is rejected — maintainer: *"adding flag when it is not enforced on implementation is not a good idea"* — because a bool nothing verifies drifts as providers change, silently. The probing test makes divergence fail loudly.

Adding a flag means updating, in `SqlProviderFlags.cs`: the property (`[DataMember(Order = N)]`, next free order), the `GetHashCode` chain, and the `Equals` chain — plus a `PublicAPI.Unshipped.txt` get/set entry. Then set it `= true` in each supporting provider's `*DataProvider` constructor. `IsUpdateOutputSupported` is the worked example.

### Moving a correctness transform to a shared stage needs a provider opt-out

A fold / cast / wrapper that exists because *most* providers reject the bare form is usually applied where a provider can still escape it — a convert visitor a provider overrides, a builder hook it replaces. Moving it earlier (to translation, or to a shared base) makes it **unconditional**, and providers that accepted the bare form start receiving output they don't need. Add a capability property alongside the transform and let those providers opt out, defaulting it to the conservative value so only providers with *evidence* opt out. Maintainer: *"I prefer to not have this case garbage generated if it is not needed."*

The evidence bar for opting a provider in is a green, value-asserting test on `master` showing the bare form worked there — not an inference that its type system looks permissive. Opting in on a guess trades redundant SQL for wrong SQL.

`IsMinMaxOverBooleanSupported` on `AggregateFunctionsMemberTranslatorBase` is the worked example (#5725): the `MIN`/`MAX`-over-boolean 1/0 fold moved out of `SqlExpressionConvertVisitor.ConvertSqlExtendedFunction` — which ClickHouse overrode and returned from without calling `base`, so the fold had never run there — into the translation stage, where nothing could escape it. ClickHouse's `Bool` is `UInt8`, so `max` applies to a comparison directly, and the relocation bought it a `CASE` for no gain. The flag defaults `false` (keep folding) and ClickHouse alone opts in. Related: [*A per-provider capability is a `SqlProviderFlags` bool plus a probing guard test*](#a-per-provider-capability-is-a-sqlproviderflags-bool-plus-a-probing-guard-test) — prefer a `protected virtual` on the translator base when the capability is consulted only at translation and needs no wire representation.

### Don't pioneer a provider feature with no cross-provider precedent

Before building a provider-specific translation, grep the other providers' translators for the same member or feature. Precedent → mirror it. No precedent → surface that and default to **not** building it.

Firebird 6 server-side `DateTime.ToString(format)` (`CAST … FORMAT`) was dropped on exactly this ground — no provider translates arbitrary date format strings server-side, every one falls back to client-side, so doing it for one provider would be a no-precedent, format-token-mapping lift with no cross-provider value. Maintainer: *"if it is not implemented by other providers - don't do it."* This is the provider-feature form of preferring the least-invasive resolution.

### A cross-provider capability found mid-PR becomes its own feature request

When work on a provider-scoped PR surfaces a capability that really spans providers, keep the PR provider-scoped and file the capability separately — describing the new API, which providers support it server-side, and the fallback. Firebird 6's `GEN_UUID(7)` suggested UUIDv7 support during #5483/#5485, but `Guid.CreateVersion7()` + a `Sql.NewGuid7` API is cross-provider; it was split out as #5646. This mirrors the *distinct shared-engine fix gets its own branch/PR* rule in [`AGENTS.md`](../AGENTS.md), applied to features rather than fixes.

### Use `MemberHelper.MethodOf` for expression-tree `MethodInfo` capture

When a translator needs a `System.Reflection.MethodInfo` to construct an `Expression.Call(method, args)` node (e.g. wrapping an accessor expression, or matching a target method in a rewrite), the codebase uses `LinqToDB.Expressions.MemberHelper`:

```csharp
static readonly MethodInfo _stringTrimEndCharArrayMethodInfo =
    MemberHelper.MethodOf<string>(s => s.TrimEnd((char[])null!));

static readonly MethodInfo _toValueMethodInfo =
    MemberHelper.MethodOfGeneric<Sql.IAggregateFunction<string, string>>(f => f.ToValue());
```

`MethodOf(() => Foo(arg))` for static or instance methods reachable via expression; `MethodOf<T>(t => t.Foo())` when an instance receiver of type `T` is needed; `MethodOfGeneric<T>` strips the generic instantiation off the result. Don't roll raw `typeof(X).GetMethod(name, BindingFlags.NonPublic | BindingFlags.Static)!` — it's fragile, doesn't give compile-time validation that the method exists with the expected signature, and isn't the codebase pattern.

When **matching** a method-call node's identity (rather than constructing a call), register the `MethodInfo` in the shared `Methods.LinqToDB.*` registry (`Internal/Reflection/Methods.cs`, captured via the same `MemberHelper.MethodOf*` helpers) and compare with `node.IsSameGenericMethod(Methods.LinqToDB.…)` — the idiom used throughout the builders (`Methods.LinqToDB.ApplyModifierInternal`, etc.). Don't hand-roll `node.Method.DeclaringType == typeof(X) && node.Method.Name == nameof(...)`: string-by-name matching is fragile (no signature/arity check, breaks on overloads) and isn't the codebase pattern. Inside a nested `Methods.LinqToDB.*` class, fully-qualify the captured method with `global::LinqToDB.Sql.…` — a bare `LinqToDB.Sql` binds to the enclosing `Methods.LinqToDB` class, not the root namespace.

**In `Source/LinqToDB.FSharp`, a `GetMethod` on an F#-declared type needs `BindingFlags.NonPublic`.** The F# project reflects directly rather than through `MemberHelper`, and F# compiles the members of a `type private` / `type internal` as **assembly**-visible in IL even when the member itself is declared public — so the default `GetMethod(name)` binding (Public | Instance | Static) returns `null`. Pass `BindingFlags.Static ||| BindingFlags.Public ||| BindingFlags.NonPublic` explicitly. The failure is loud but badly misattributed: in a `static let` the resulting `nonNull` throws inside the type initializer, so *every* test that touches the assembly fails with `TypeInitializationException` pointing at an unrelated entry point (`FSharpQueryExpressionInterceptor.Instance`), which reads as a broken assembly rather than a null lookup. (Cost a full red cycle on #5701's `FreeVarMarker.Get`.)

### A reference-identity set over `Expression` needs the comparer spelled out

`new HashSet<Expression>()` / `new Dictionary<Expression, …>()` does **not** give you reference identity. `EqualityComparer<Expression>.Default` defers to the node's own `Equals`, and thirteen types under `Source/LinqToDB/Internal/Expressions/` override it — `ChangeTypeExpression`, `ConstantPlaceholderExpression`, `ContextRefExpression`, `DefaultValueExpression`, `SqlAdjustTypeExpression`, `SqlAggregateLifterExpression`, `SqlEagerLoadExpression`, `SqlGenericConstructorExpression`, `SqlGenericParamAccessExpression`, `SqlPathExpression`, `SqlPlaceholderExpression`, `SqlQueryRootExpression`, `SqlReaderIsNullExpression`. For those, membership is **structural**, and some are aggressively so: `ConstantPlaceholderExpression.Equals` compares only `ConstantType`, so any two placeholders of the same type are equal.

When the question you're asking is "is this the same node object", pass the in-repo comparer: `new HashSet<Expression>(Utils.ObjectReferenceEqualityComparer<Expression>.Default)` (`LinqToDB.Internal.Common`, `Internal/Common/Utils.cs`). Used verbatim that way in `Internal/Expressions/InternalExtensions.cs` and `Internal/Linq/Builder/DistinctBuilder.cs`. `System.Runtime.CompilerServices.ReferenceEqualityComparer` is .NET 5+, so it is not available on the `net462` / `netstandard2.0` legs.

Structural membership where identity was meant is silent — the set behaves correctly for the ordinary nodes and diverges only for those thirteen — so it won't show up in tests aimed at anything else. (Surfaced on #5841, where the extension-argument tracking set was created without the comparer.)

### `CanBeEvaluatedOnClient` does not reject every extension node

`ExpressionTreeOptimizationContext.CanBeEvaluatedOnClient` is often relied on to mean "no linq2db-internal node got in here", and it mostly does — `CanBeEvaluatedOnClientCheckVisitorBase` explicitly refuses `ContextRefExpression`, `SqlPlaceholderExpression`, `SqlQueryRootExpression`, `SqlGenericConstructorExpression`, `SqlEagerLoadExpression`, `SqlGenericParamAccessExpression` and `SqlErrorExpression`. But its `VisitExtension` fallback only sets `CanBeEvaluated = false` when the node's **`CanReduce` is `false`**; a reducible node has its `Reduce()` visited instead and can pass. `ConstantPlaceholderExpression`, `DefaultValueExpression` and `SqlAdjustTypeExpression` all reduce.

So "this path is unreachable because `CanBeEvaluatedOnClient` filters those nodes out" is not a sound argument for the reducible ones — check `CanReduce` before relying on it. (A subagent's reachability rationale on #5841 rested on the blanket reading and was wrong; the conclusion happened to survive for unrelated reasons.)

### C# 14 `extension(...)` blocks defeat signature-based searches

Extension members are increasingly declared inside an `extension(<Type> <param>)` block rather than as `static M(this <Type> x)`, so any search built on the `this`-parameter shape misses them completely. `git grep "Unwrap(this Expression"` and `git grep "static Expression? Unwrap"` both return nothing for `InternalExtensions.Unwrap`, which exists and is called across the tree. Search the **bare member name** first (`git grep -ln Unwrap`) and narrow afterwards. The failure mode is silent and actively misleading — an empty result reads as "no such member" — and it will spread as more of the codebase adopts the syntax. (Cost six consecutive failed searches in one `code-reviewer` pass on #5801, all hunting the same symbol; one broad `-ln` search would have replaced all of them.)

### SQL AST types live in `LinqToDB.Internal.SqlQuery`

The SQL query tree building blocks — `SqlFrameClause`, `SqlKeepClause`, `SqlExtendedFunction`, `SqlFrameBoundary`, `SqlSearchCondition`, and every other AST node used only during query construction, translation, and rendering — are library-internal. They are not part of the stable public surface. New AST types MUST go in the `LinqToDB.Internal.SqlQuery` namespace.

A handful of legacy AST classes still live under the public `LinqToDB.SqlQuery` namespace; some carry a `// TODO: v7 - move to internal namespace` marker acknowledging the debt. When a PR modifies one of those legacy AST types' signatures and ApiCompat flags it as a breaking public-API change, the correct fix is to **move the class to `LinqToDB.Internal.SqlQuery` in the same PR** — that repays the pre-existing design debt and removes the apparent public-API breakage in one step. Do **not** target a major-release milestone for what is really just internal AST evolution, and do not add the signature change to the suppression baseline as if it were an intentional public-API break.

This rule refines the `/review-pr` classification in [`api-surface-classification.md`](api-surface-classification.md): a `modified` or `removed` entry whose symbol is in `LinqToDB.SqlQuery` and targets a SQL AST type should be reviewed as a namespace-placement finding (fix: move to `Internal.SqlQuery`), not as a milestone-gated public-API-break BLK.

### LinqService has no cross-version wire contract

A mixed-version LinqService deployment — client and server on different builds of the same major — is **not** a supported configuration. Client and server are expected to be the same build, so the serialized layout in `Internal/Remote/LinqServiceSerializer.cs` carries no compatibility obligation across 6.x releases: changing, adding, or removing a field's token in the stream is not a breaking change, and no legacy placeholder is warranted to preserve an older payload's shape.

**This contradicts comments in the codebase, which is why it needs stating here.** Several `QueryElementType` members carry a `// TODO: appended here for v6.x LinqService wire-compat (enum ordinals are serialized as int)` marker. That rationale is inaccurate. The real reason those members are tail-appended is the **public-enum ABI**: `QueryElementType` is public API, so inserting mid-enum renumbers every later member and trips ApiCompat `CP0011`. The constraint is real; the stated reason for it is not. Treat a wire-compat argument sourced from those comments as unfounded — on PR #5723 it produced a bot finding, and an agent review rated it a blocker, before the maintainer corrected the premise.

### Column-aligned formatting is intentional

Large blocks of the codebase use column-aligned formatting — property declarations line their `{ get; }` up at the same column, constructor parameters line their defaults up at the same column, constant declarations line their `=` up at the same column. This is deliberate house style, not accidental. Preserve it when editing; match the existing alignment of surrounding code rather than reformatting it to a narrower width.

When you *do* edit an aligned block, align each `=` / `=>` to the longest left-hand side **within its contiguous same-kind subgroup** — declarations of one type form a subgroup independent of an adjacent block of another type (a `var` group and a `List<T>?` group align to *different* columns even with no blank line between them), a bare assignment aligns with the variable-declaration block it sits directly above/below, and a `switch`-expression's arms align their `=>` one space past the longest pattern. A lone declaration takes a single space; a group that loses a member re-collapses to the new longest LHS. The common defect is an `=`/`=>` sitting one column off its neighbours — fix it by adding/removing the one space, never by stripping the alignment.

Formatting is only worth flagging when it is clearly broken — three or more consecutive blank lines, mixed tabs and spaces that cause visible misalignment, indentation that doesn't match the enclosing scope. The positive alignment style is never the bug.

### TODO markers signal deferred cleanup, not bugs

Comments of the form `// TODO: ... v<N>` or `// FIXME: ... in next major` are an intentional project convention for flagging code that's known to need cleanup or removal in a specific future major release. They're tracked manually rather than via an issue tracker because they only need to be acted on at a major-version boundary.

Don't flag these as scope-creep, stray comments, or "uncommitted thinking-aloud edits" — even when the wording is informal (`// ??? TODO: remove Flags in v7` is a real example). When a PR introduces a new TODO marker that follows this shape, treat it as part of the deferred-cleanup ledger.

The narrower case — `// TODO: v7 - move to internal namespace` markers on legacy SQL AST types — is covered above under **SQL AST types live in `LinqToDB.Internal.SqlQuery`**.

### Exceptions carry cause + remediation; don't collapse specifics into a generic message

linq2db is a library a developer debugs at 2 a.m. through a stack trace, so a thrown exception's message is the primary diagnostic. When adding or editing a `throw`, the message should convey what failed, enough context to see why (the offending member / type / SQL fragment / provider), and — where there is a real one — the remediation. The anti-pattern to avoid is **swallowing a specific failure into a generic one**: catching a precise reason ("this member can't be translated because the subquery is correlated and provider X doesn't support it") and re-throwing it as a bare "conversion error" discards exactly the signal the user needs and makes a fixable usage error look like an engine bug. (linq2db has live instances of this — correlated-subquery reasons collapsing into a generic conversion message — currently parked as deferred work.) Preserve the inner exception / specific reason rather than flattening it.

### Interpolate exception messages with a plain `$"…"`

The house form is `throw new LinqToDBException($"…{symbol}…")` — used across `DataExtensions`, `DataContext`, `Sql.TableFunctionAttribute` and elsewhere. Do **not** reach for `FormattableString.Invariant($"…")`: it appears nowhere in `Source/LinqToDB`, so introducing it makes the site look like it has a culture concern the neighbours don't. Message interpolation here is type names, member names and SQL fragments, none of which format culture-sensitively, and the Release-only analyzer set does not require an `IFormatProvider` for them.

### Prefer `??` over `Nullable<T>.GetValueOrDefault(fallback)`

When an option falls back to a provider default, write the null-coalesce: `helper.Options.BulkCopyOptions.MaxParametersForBatch ?? maxParameters`. The `GetValueOrDefault(fallback)` overload expresses the same thing with more ceremony, and reads as though something more than a null check is happening. Maintainer, 2026-08-31, on #5828: *"GetValueOrDefault use - replace with ??, no need to introduce overcomplicated syntax."* Applies to the fallback overload specifically — parameterless `GetValueOrDefault()` on a nullable is a different operation and is fine where the `default(T)` result is what you want.

### An option's XML doc lives in three places

A `BulkCopyOptions` / `LinqOptions` property is documented on the record's `<param>` **and** on both fluent extensions — for `MaxSqlLengthForBatch` that is `DataOptionsExtensions.WithMaxSqlLengthForBatch` and `UseBulkCopyMaxSqlLengthForBatch` — and the three copies are kept byte-identical. So any wording change to an option's documentation is a three-site edit, and a divergence between the copies is itself a defect worth flagging. `Grep` the block's first sentence before editing to find all three; `Edit` with `replace_all` covers the two that share `DataOptionsExtensions.cs`. Note the indentation differs between the files — one tab in the record's file-scoped namespace, two in `DataOptionsExtensions.cs`. (Three separate doc findings on #5828 were each a three-site edit.)

### Prefer types that make invalid states unrepresentable

The library is `<Nullable>enable</Nullable>` and type-safe by design; lean into it. When a new API or internal structure has a "this combination is illegal" rule, prefer encoding it in the type — a non-nullable field, a discriminated shape, a required ctor parameter, an enum over loose bools — rather than a runtime guard plus a comment. Fewer reachable invalid states means fewer defensive guards, fewer "can this be null here?" review questions, and less of the defensive bloat that accretes when correctness is enforced by convention instead of by the compiler. This is the constructive flip side of **Internal AST APIs trust NRT** above: bare AST ctors can skip guards precisely because the surrounding types already make the bad states hard to construct.

### Oversized files carry an agent-comprehension cost, not just a style one

Very large source files (multi-thousand-line builders, optimizers, AST visitors) are harder for an agent to reason about correctly: comprehension and edit accuracy degrade as a single file grows, and a partial read invites the "looks done but missed a branch" failure. This is **not** a mandate to split existing files — the column-aligned, large-file house style is intentional and churn for its own sake is unwelcome (see **Column-aligned formatting is intentional**). It's a tie-breaker: when genuinely new, separable logic is added, prefer a new focused file / partial over growing an already-huge one; and when a fix inside a giant file needs the surrounding method understood, read the whole method, not a window. A heuristic, never a metric to enforce.

### Read back only the columns you consume

When reading values back from a modifying statement — `OUTPUT` / `RETURNING`, or a follow-up `SELECT` — project **only** the columns the caller will actually use, built from the target column set (`new T { col = src.col, … }`); don't select the whole row and then discard all but a few. Over-fetching is wasteful and obscures intent.

### Tuples only when tuples are what's under test

A multi-field tuple used as an internal carrier gets a **record** instead. Maintainer, 2026-08-20: *"we use tuples only when we need to test tuples."* The cost of the tuple is positional access at every read site — `result.Item5`, `result.Item3` — which says nothing about what the value is, and which a reader has to resolve by counting the declaration's type arguments.

The give-away that a tuple has outgrown its place is arity plus distance: constructed in one method and read in another, three or more fields, or a `null` element that needs a cast to disambiguate the overload. Converting also tends to surface latent sloppiness that the tuple's shape was hiding — a `Tuple<…, DbParameter[], Exception?>` whose every construction actually passed `(DbParameter[]?)null` with a `!` suppression becomes an honest `DbParameter[]?` on the record, and the suppressions and casts disappear with it. (Applied on #5614 to `ConcurrentRunner`'s five-wide `Tuple<TParam, TResult, string, DbParameter[], Exception?>`, which became `ConcurrentRunOutcome<TParam, TResult>` with named members.)

This is about carriers, not about `ValueTuple` in general: a two-field local return, a deconstructed `(context, isRemote)` helper result, and any test whose subject *is* tuple mapping are all fine as tuples.
