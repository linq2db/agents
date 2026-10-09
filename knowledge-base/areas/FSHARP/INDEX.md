---
area: FSHARP
kind: area-index
sources: [code]
confidence: high
last_verified: 2026-10-09
last_verified_sha: 05150894edc2511f0dd0bc7829b2a309cec36ec9
coverage_tier_1: 8/8
coverage_tier_2: 0/0
---

# FSHARP

Optional NuGet package (`linq2db.FSharp`, assembly `linq2db.FSharp`) that adds F#-specific mapping support to linq2db. Provides F# record type support in mappings and projections, automatic mapping of F# `'T option` / `'T voption` columns and single-case scalar discriminated unions, query translation of option member access, and rewriting of F#-specific expression-tree shapes (record-copy `Update`, record-construction blocks, quotation-lambda reduction, chained group-join flattening) that the core translator doesn't understand. Target frameworks inherit from the main `Directory.Build.props`; `net462` adds an explicit `FSharp.Core` package reference (other TFMs receive it transitively from the SDK).

## Subsystems

### Entry point: `DataOptions.UseFSharp()`

`DataOptionsExtensions.fs` defines a C#-visible extension method on `DataOptions` via `[<Extension>]`. Calling `.UseFSharp()` registers two interceptors via `options.UseInterceptor`: `FSharpEntityBindingInterceptor.Instance` and `FSharpQueryExpressionInterceptor.Instance`, and a member translator via `.UseMemberTranslator(FSharpMemberTranslator.Instance)` (`DataOptionsExtensions.fs:33-35`). It also combines a static, shared `fsharpMappingSchema` (carrying two metadata readers: `FSharpOptionMetadataReader` and `FSharpSingleCaseUnionMetadataReader`, `DataOptionsExtensions.fs:11-15`) into the caller's `MappingSchema` via `MappingSchema.CombineSchemas`, added as a *lower-priority* fallback so it only fills in members the caller hasn't explicitly mapped -- `UseAdditionalMappingSchema` was rejected because its default attribute reader would shadow explicit fluent column metadata (`DataOptionsExtensions.fs:36-44`). When the options carry no mapping schema, the shared schema is used as is.

### `FSharpEntityBindingInterceptor`

`FSharpEntityBindingInterceptor.fs:18` -- inherits `EntityBindingInterceptor` (`Source/LinqToDB/Internal/Interceptors/EntityBindingInterceptor.cs`) and implements `IEntityBindingInterceptor`. Exposes a singleton via `Instance`.

**Record detection** (`isRecord`, line 29): returns `true` when the type carries `CompilationMappingAttribute` with `SourceConstructFlags.RecordType` and does **not** carry `[<CLIMutable>]`. CLIMutable records have property setters and need no special handling.

**Member-to-constructor mapping** (`TryMapMembersToConstructor`, line 37): walks `TypeAccessor.Members`, finds each member's `CompilationMappingAttribute` where `SourceConstructFlags = Field`, and builds a `Dictionary<int, MemberAccessor>` keyed by `SequenceNumber` (i.e., positional index in the F# record declaration). Result is cached in a `ConcurrentDictionary<Type, ...>`.

**`ConvertConstructorExpression`** (line 55): intercepts `SqlGenericConstructorExpression` at two points in the pipeline:

- `CreateType.New` -- the `Parameters` list is positional; for each position `i`, if `map` has entry `i`, the parameter is re-tagged with the concrete `MemberInfo` so downstream SQL generation can match column -> constructor arg by position. Handles linq2db-generated `new T(args...)` calls.
- `CreateType.Full` -- the expression has named `Assignments`. The interceptor locates the single constructor with `parameters.Length >= map.Count`, allocates an `Expression[]` of that length, fills each slot by looking up the assignment by `MemberInfo`, substitutes `DefaultValue`/`MappingSchema.GetDefaultValue` for any missing slot, builds `Expression.New(ctor, arguments)`, and wraps it in `Expression.MemberInit`. Remaining (non-positional) assignments are added as `MemberBinding`s. The result is wrapped in a new `SqlGenericConstructorExpression`.

The effect: F# records, whose generated constructors have no settable properties (unless `[<CLIMutable>]`), are materialized via their primary constructor rather than via object-initializer syntax.

### `FSharpOptionSupport` / `FSharpOptionMetadataReader`

`FSharpOptionSupport.fs` -- automatic mapping for `'T option` / `'T voption` columns, so option-typed members round-trip without manual `MappingSchema` configuration.

`IsOption` (`FSharpOptionSupport.fs:88`) detects `FSharpOption<_>` / `FSharpValueOption<_>` by generic type definition; `IsScalarOption` (line 95) additionally requires the element type to satisfy `MappingSchema.Default.IsScalarType` **or** to be a scalar single-case union (`FSharpSingleCaseUnionSupport.IsScalarSingleCaseUnion`) -- an option over a complex/entity element is left untouched (not treated as a column). A `TODO` notes the `MappingSchema.Default` check should switch to the callsite schema once metadata readers are schema-aware (#5675).

`build` (line 28) constructs a bidirectional `ValueConverter<TOption, TProvider>` via explicit `Expression` trees, cached by `GetConverter` (line 103) in a `ConcurrentDictionary<Type, IValueConverter>` keyed by the closed option type. A non-nullable value-typed element (`int`, `decimal`, etc.) is wrapped in `Nullable<'a>` as the provider type, so `None`/`ValueNone` serializes as SQL `NULL` rather than `default('a)` -- fixes issue #4646 (`int option` storing `None` as `0`). Reference-typed and already-nullable elements pass through unwrapped (the `Nullable.GetUnderlyingType` check also avoids the invalid `Nullable<Nullable<_>>`). For an option over a scalar single-case union (e.g. `UserId option`) the provider type is driven by the union's wrapped scalar: the union is unwrapped on the way out and rebuilt via the case constructor on the way in. The converter is created with `handlesNulls = true`.

`FSharpOptionMetadataReader` (line 108) implements `IMetadataReader` (`Source/LinqToDB/Metadata/IMetadataReader.cs`): `GetAttributes(Type)` returns `ScalarTypeAttribute` for a scalar option type; `GetAttributes(Type, MemberInfo)` returns `ColumnAttribute(CanBeNull = true)` (needed so a struct `voption` column does not DDL as NOT NULL) plus a `ValueConverterAttribute` wrapping the cached converter for every scalar-option member. The DB type is intentionally left unset -- `ColumnDescriptor` derives it from the value converter's provider type against the active provider-inclusive schema, preserving provider-faithful facets (decimal precision/scale, string length) that deriving from context-free `MappingSchema.Default` would truncate (issue #5645, e.g. `decimal option` -> `decimal(18,0)`).

### `FSharpSingleCaseUnionSupport` / `FSharpSingleCaseUnionMetadataReader`

`FSharpSingleCaseUnionSupport.fs` (internal) -- automatic mapping for single-case scalar discriminated unions such as `type UserId = UserId of int`, mirroring the option support. `IsSingleCaseUnion` (line 43) requires `FSharpType.IsUnion` with exactly one case having exactly one field (this excludes option/voption, list and multi-case unions); `IsScalarSingleCaseUnion` (line 48) additionally requires the wrapped field type to be a `MappingSchema.Default` scalar (same #5675 TODO). `build` (line 26) creates a `ValueConverter<TUnion, TField>` from expression trees: to-DB reads the wrapped-field property, from-DB calls the static case constructor (`FSharpValue.PreComputeUnionConstructorInfo`); `handlesNulls = false` because the constructor has no null branch, so linq2db short-circuits a NULL read to `null` instead of calling it with `default('T)`. Converters are cached in a `ConcurrentDictionary<Type, IValueConverter>`; `WrappedField` / `CaseConstructor` helpers are shared with the option converter. `FSharpSingleCaseUnionMetadataReader` (line 69) returns `ScalarTypeAttribute` for the type and a `ValueConverterAttribute` per scalar-union member (DB type left unset, as for options). Per the readme, a `[<Struct>]` union cannot hold `null`: a NULL read yields the union wrapping the element default (`Age 0`); use `option` for nullable columns.

### `FSharpMemberTranslator`

`FSharpMemberTranslator.fs` -- `MemberTranslatorBase` subclass (singleton `Instance`, so the DataContextOptions ConfigurationID / query cache key stays stable across `UseFSharp()` calls) that translates option member access, which otherwise fails with "could not be converted to SQL". It overrides `TranslateOverrideHandler` and matches generically (the members are generic over the element type, which the pattern registry can't match). Three syntactic forms are handled: property form (`MemberExpression` on an option-typed operand: `IsSome`/`IsValueSome` -> `IS NOT NULL`, `IsNone`/`IsValueNone` -> `IS NULL`, `Value` -> the column re-typed to the element via `ph.WithType`); getter-method form (`get_IsSome`/`get_IsNone` static, `get_Value` instance); and module-function form (`Option.isSome`/`isNone`/`get` and `ValueOption` equivalents, matched on `OptionModule`/`ValueOption` declaring type in `Microsoft.FSharp.Core`). `translateIsNull` / `translateValue` translate the operand with `TranslationFlags.Sql` and decline (return `null`) unless it yields a non-parameter `SqlPlaceholderExpression`. Consequence (readme): `.Value` on a NULL column reads back the element default instead of throwing, like `Nullable<T>.Value`.

### `FSharpQueryExpressionInterceptor`

`FSharpQueryExpressionInterceptor.fs` -- an `IQueryExpressionInterceptor` (`Source/LinqToDB/Interceptors/IQueryExpressionInterceptor.cs`) (`Instance` singleton), registered by `.UseFSharp()` alongside the entity-binding interceptor. `ProcessExpression` rewrites only the pre-expose tree (`args.Kind = QueryExpressionArgs.ExpressionKind.Query`); linq2db custom nodes from the post-expose tree never carry the F# shapes this interceptor targets.

Rewriting is done by the private `FSharpRewriteVisitor(mappingSchema)` (an `ExpressionVisitor`):

- **Block inlining** (`VisitBlock`, `FSharpQueryExpressionInterceptor.fs:135`): F# emits a `BlockExpression` for record construction (`{ var x = expr1; new type(x, expr2) }`); when the block's variable-assignment statements are each single-use, non-self-referential, and reference one of the block's own variables, the visitor substitutes the value into the result and re-visits it, producing `new type(expr1, expr2)`.
- **Record-copy `Update` rewrite** (`RewriteUpdate`, line 64): turns `q.Update(p, fun r -> { r with Field = v })` into `q.Where(p).Set(x => x.Field, x => v).Update()`, via `Methods.LinqToDB.Update.SetQueryablePrev` / `SetUpdatablePrev` / `UpdateUpdatable` (`LinqToDB.Internal.Reflection`). Uses `FSharpEntityBindingInterceptor.isRecord` and `TryMapMembersToConstructor` to map each ctor argument back to its member. A ctor argument that is a self-copy (`r.SameField`) is excluded from the change set. When every argument is a self-copy (a literal no-op `{ r with Field = r.Field }`), every non-PK column is assigned to itself instead -- keeping the primary key out of `SET` (YDB rejects a PK in `SET`) rather than falling back to a full all-column update.
- **F# quotation reduction** (`TryReduceFSharpQuotation`, line 203; issue #1813): a lambda capturing outer variables compiles to `LeafExpressionConverter.QuotationToLambdaExpression(SubstHelper(quotation, freeVars, capturedValues))`, which the translator's `UnwrapLambda` cannot cast to `LambdaExpression`. The visitor evaluates the quotation and `Var[]`, substitutes each free var with a `FreeVarMarker.Get<'T>(i)` call (a marker *call*, since no placeholder instance exists for string/interface/abstract types), re-runs the F# conversion, then replaces markers with the captured outer value-expressions (`StripBox` removes the `Convert(_, obj)` box) and wraps the result in `Quote(lambda)`. Calls are matched by name + declaring-type full name (tolerates FSharp.Core version differences between net10.0 and net462). Any unexpected shape returns `None` (node untouched); `FlattenInvariantException` is re-raised.
- **Chained group-join flatten** (`TryFlattenNestedGroupJoin`, line 277; #1813, #5790): rewrites the nested bind F# emits for `groupJoin ... into g; for x in g.DefaultIfEmpty()` -- `X.SelectMany(a => a.grp.DefaultIfEmpty().GroupJoin(...).tail, (a, r) => r)` -- into the flat C#-equivalent `X.SelectMany(a => a.grp.DefaultIfEmpty(), (a, x) => pair(a, x)).GroupJoin(...).tail`, so the leading `DefaultIfEmpty` becomes a LEFT JOIN rather than a correlated subquery rendered as INNER JOIN LATERAL (silently dropping rows). The pair type is re-closed from the two-argument `AnonymousObject` definition (F# widens to arity 4, 6, ... for later joins). Hoisted `Enumerable.*` tail operators (`SelectMany`, `GroupJoin`, `Select`, `Where`) are re-expressed as `Queryable.*`; the visitor reprocesses the result so N chained joins normalize recursively. If the flattened tree still references the outer element `a` beyond the flat SelectMany's own lambdas (correlated inner sequence or tail, #5790), the private `FlattenInvariantException` is raised on purpose rather than falling back to the un-flattened shape. The surrounding `try` stays broad, so other exceptions decline silently.
- **`VisitMethodCall`** (line 388) order: quotation reduction, then group-join flatten, then base visit followed by the `Update` rewrite for `UpdateSetter` / `UpdatePredicateSetter`.
- **`VisitExtension`** (line 133) returns the node unchanged -- the base `ExpressionVisitor` would call `VisitChildren` on a non-reducible linq2db extension node and throw; F# constructs handled here only appear in the raw standard-node tree.
- Any shape `RewriteUpdate` doesn't recognize (non-record setter, no constructor map, multi-param setter) falls back to the original, unrewritten `Update` call with no diagnostic (`FSharpQueryExpressionInterceptor.fs:68-128`).

## Key types

| Type | File | Role |
|---|---|---|
| `Methods` (extension class) | `DataOptionsExtensions.fs` | Exposes `UseFSharp()` on `DataOptions`; holds the shared `fsharpMappingSchema` |
| `FSharpEntityBindingInterceptor` | `FSharpEntityBindingInterceptor.fs` | `IEntityBindingInterceptor`; rewrites `SqlGenericConstructorExpression` for F# records |
| `FSharpQueryExpressionInterceptor` | `FSharpQueryExpressionInterceptor.fs` | `IQueryExpressionInterceptor`; rewrites F# block/record-copy-update/quotation/group-join shapes |
| `FSharpOptionSupport` | `FSharpOptionSupport.fs` | Builds/caches `IValueConverter` for option / voption (incl. options over single-case unions) |
| `FSharpOptionMetadataReader` | `FSharpOptionSupport.fs` | `IMetadataReader`; supplies column + value-converter attributes for scalar-option members |
| `FSharpSingleCaseUnionSupport` | `FSharpSingleCaseUnionSupport.fs` | Builds/caches `IValueConverter` for single-case scalar unions |
| `FSharpSingleCaseUnionMetadataReader` | `FSharpSingleCaseUnionSupport.fs` | `IMetadataReader`; scalar-type + value-converter attributes for union members |
| `FSharpMemberTranslator` | `FSharpMemberTranslator.fs` | `MemberTranslatorBase`; option `IsSome`/`IsNone`/`Value` -> SQL |

## Files (Tier 1 / Tier 2)

**Tier 1** (all 8 files; area is small enough that all are pinned):

| File | Notes |
|---|---|
| `Source/LinqToDB.FSharp/LinqToDB.FSharp.fsproj` | Package identity, TFM, compile order (EntityBinding, QueryExpression, SingleCaseUnion, Option, MemberTranslator, DataOptions) |
| `Source/LinqToDB.FSharp/DataOptionsExtensions.fs` | Entry-point extension method |
| `Source/LinqToDB.FSharp/FSharpEntityBindingInterceptor.fs` | Core interceptor implementation |
| `Source/LinqToDB.FSharp/FSharpQueryExpressionInterceptor.fs` | Expression-tree interceptor: block inlining, record-copy `Update` rewrite, quotation reduction, group-join flatten |
| `Source/LinqToDB.FSharp/FSharpOptionSupport.fs` | F# option/voption value-converter + metadata reader |
| `Source/LinqToDB.FSharp/FSharpSingleCaseUnionSupport.fs` | Single-case scalar union value-converter + metadata reader |
| `Source/LinqToDB.FSharp/FSharpMemberTranslator.fs` | Option member access translation |
| `Source/LinqToDB.FSharp/readme.md` | NuGet readme; documents `UseFSharp()` |

**Tier 2**: none -- all 8 on-disk files are Tier 1.

## Inbound / outbound dependencies

**Outbound (this package depends on):**
- `LinqToDB` core project (`LinqToDB.csproj`) -- `DataOptions`, `TypeAccessor`, `MemberAccessor`, `EntityBindingInterceptor`, `IEntityBindingInterceptor`, `SqlGenericConstructorExpression`, `MappingSchema`, `DefaultValue`.
- `LinqToDB` core project, expression-interception and option-mapping surface -- `IQueryExpressionInterceptor`, `QueryExpressionArgs`, `IMetadataReader`, `IValueConverter`/`ValueConverter<,>`, `ScalarTypeAttribute`, `ColumnAttribute`, `ValueConverterAttribute`, `MappingSchema.CombineSchemas`, `Methods.LinqToDB.Update.*`, `Methods.Queryable.*` / `Methods.Enumerable.*` (`LinqToDB.Internal.Reflection`).
- `LinqToDB` core translation surface -- `MemberTranslatorBase`, `ITranslationContext`, `TranslationFlags`, `SqlPlaceholderExpression`, `DataOptions.UseMemberTranslator` (`LinqToDB.Linq.Translation`, `LinqToDB.Internal.DataProvider.Translation`).
- `FSharp.Core` (explicit package ref on `net462`; SDK-provided on netstandard2.0+).

**Inbound (depends on this package):**
- Consumer applications that call `.UseFSharp()` on `DataOptions`. Nothing in the main linq2db solution depends on this package.

**Cross-area links:**
- [INTERCEPTORS](../INTERCEPTORS/INDEX.md) -- provides `EntityBindingInterceptor` base class, `IEntityBindingInterceptor`, `IQueryExpressionInterceptor`, `QueryExpressionArgs`.
- [CORE](../CORE/INDEX.md) -- provides `DataOptions`, `TypeAccessor`, `MappingSchema`, `IMetadataReader`, `IValueConverter`.

## Known issues / debt

- Record types, F# option/voption columns and single-case scalar discriminated unions are handled; multi-case unions and F# collection types (`list`, `seq`) are still not addressed. The readme acknowledges this ("More features planned for future releases").
- Option and union scalar detection uses `MappingSchema.Default.IsScalarType` (TODO referencing #5675) because metadata readers are not yet schema-aware; scalar types registered only on the context's own schema are missed.
- `CLIMutable` detection (`isRecord`) uses `AttributesExtensions.HasAttribute<CLIMutableAttribute>` which returns `bool?` -- the `= true` comparison is explicit and intentional, treating `null` as false.
- `FSharpRewriteVisitor.RewriteUpdate` silently falls back to the original, unrewritten `Update` call for any shape it doesn't recognize (non-record setter, no matching constructor map, multi-param setter) -- no diagnostic surfaces, so an F# record-copy `Update` outside the handled shape just runs as a full column-list update with no visible signal that the optimization didn't apply.
- `TryFlattenNestedGroupJoin` keeps a broad `try ... with _ -> None`: a genuine rewrite bug other than `FlattenInvariantException` falls back to the un-flattened INNER JOIN LATERAL shape (silent row loss); the code comments flag this.
- A `[<Struct>]` single-case union reads NULL as the union wrapping the element default (cannot be `null`); option is the documented workaround.

## See also

- [INTERCEPTORS area index](../INTERCEPTORS/INDEX.md)
- `Source/LinqToDB/Internal/Interceptors/IEntityBindingInterceptor.cs` -- interface contract
- `Source/LinqToDB/Internal/Expressions/SqlGenericConstructorExpression.cs` -- expression type being rewritten
- `Source/LinqToDB/Interceptors/IQueryExpressionInterceptor.cs` -- interface contract for `FSharpQueryExpressionInterceptor`
- `Source/LinqToDB/Metadata/IMetadataReader.cs` -- interface contract for `FSharpOptionMetadataReader`
- `Source/LinqToDB/Mapping/IValueConverter.cs`, `Source/LinqToDB/Mapping/ValueConverter.cs` -- converter types used by `FSharpOptionSupport`

<details><summary>Coverage</summary>

Tier 1 (4/4 read): `LinqToDB.FSharp.fsproj`, `DataOptionsExtensions.fs`, `FSharpEntityBindingInterceptor.fs`, `readme.md` -- read in full.

Tier 2: none. Tier 3: none.

Cross-area reads (dependency verification, not counted): `Internal/Interceptors/IEntityBindingInterceptor.cs`, `Internal/Interceptors/EntityBindingInterceptor.cs`.

Read (this run -- delta):
- `Source/LinqToDB.FSharp/FSharpExpressionInterceptor.fs` (DELETED) -- file is absent from disk and from any compile reference in the FSharp project; no replacement found via Glob or Grep; the prior INDEX.md did not track this file (it was not listed in the Tier-1 table or Key types). On-disk file count remains 4; coverage_tier_1 unchanged at 4/4.

Read (this run -- delta):
- `Source/LinqToDB.FSharp/LinqToDB.FSharp.fsproj` -- compile-item list grew from 2 to 4 entries: added `FSharpQueryExpressionInterceptor.fs` and `FSharpOptionSupport.fs` (both now Tier 1). Resolves the prior run's dangling reference: `FSharpQueryExpressionInterceptor.fs` is the replacement for the `FSharpExpressionInterceptor.fs` file noted deleted above (different name, expression-interceptor role retained).
- `Source/LinqToDB.FSharp/DataOptionsExtensions.fs` -- `UseFSharp()` now also registers `FSharpQueryExpressionInterceptor.Instance` and combines an option-mapping `MappingSchema` (`optionMappingSchema`) into the caller's schema via `MappingSchema.CombineSchemas`, added as a lower-priority fallback.
- `Source/LinqToDB.FSharp/FSharpOptionSupport.fs` (NEW) -- adds `FSharpOptionSupport` (builds/caches `IValueConverter` for `'T option`/`'T voption`, wrapping non-nullable value elements in `Nullable<'a>` so `None` stores as `NULL`, fixing issue #4646) and `FSharpOptionMetadataReader` (`IMetadataReader` supplying `ScalarTypeAttribute` + `ColumnAttribute(CanBeNull = true)` + `ValueConverterAttribute` for scalar-option members; DB type left unset to preserve provider facets, fixing issue #5645).
- `Source/LinqToDB.FSharp/FSharpQueryExpressionInterceptor.fs` (NEW) -- adds `FSharpQueryExpressionInterceptor` (`IQueryExpressionInterceptor`) and the private `FSharpRewriteVisitor`, which inlines F# record-construction blocks and rewrites F# record-copy `Update` calls into targeted `Where(...).Set(...).Update()` chains.
- `Source/LinqToDB.FSharp/readme.md` -- documents the new automatic F# `option`/`voption` column mapping alongside the existing record-type support.

coverage_tier_1 increased from 4/4 to 6/6 (2 new Tier-1 files: `FSharpQueryExpressionInterceptor.fs`, `FSharpOptionSupport.fs`). All 6 Tier-1 files read in full this run or a prior run (`FSharpEntityBindingInterceptor.fs` unchanged since the last run, previously read in full).

Read (this run -- delta):
- `Source/LinqToDB.FSharp/FSharpMemberTranslator.fs` (A) -- `FSharpMemberTranslator` translating option/voption `IsSome`/`IsNone`/`Value` (property, getter-method and module-function forms) to `IS [NOT] NULL` / the column; registered by `UseFSharp()` via `UseMemberTranslator`.
- `Source/LinqToDB.FSharp/FSharpSingleCaseUnionSupport.fs` (A) -- `FSharpSingleCaseUnionSupport` + `FSharpSingleCaseUnionMetadataReader` for single-case scalar discriminated unions (`handlesNulls=false` converter).
- `Source/LinqToDB.FSharp/FSharpOptionSupport.fs` (M) -- `IsScalarOption` accepts options over scalar single-case unions; `build` unwraps/reconstructs the union; Nullable wrap decision driven by the wrapped scalar.
- `Source/LinqToDB.FSharp/FSharpQueryExpressionInterceptor.fs` (M) -- added `TryReduceFSharpQuotation` (quotation-captured lambda reduction), `TryFlattenNestedGroupJoin` (chained group-join flatten, #1813/#5790), `FreeVarMarker`, `FlattenInvariantException`.
- `Source/LinqToDB.FSharp/DataOptionsExtensions.fs` (M) -- shared static `fsharpMappingSchema` with both metadata readers; registers `FSharpMemberTranslator.Instance`.
- `Source/LinqToDB.FSharp/LinqToDB.FSharp.fsproj` (M) -- compile list now 6 entries (added `FSharpSingleCaseUnionSupport.fs`, `FSharpMemberTranslator.fs`).
- `Source/LinqToDB.FSharp/readme.md` (M) -- documents option member translation and single-case union mapping incl. struct-union NULL behavior.

coverage_tier_1 increased from 6/6 to 8/8 (2 new Tier-1 files: `FSharpMemberTranslator.fs`, `FSharpSingleCaseUnionSupport.fs`). `FSharpEntityBindingInterceptor.fs` not in this delta; its prior full read stands.
</details>
