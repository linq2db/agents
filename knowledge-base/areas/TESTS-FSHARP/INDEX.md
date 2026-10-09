---
area: TESTS-FSHARP
kind: area-index
sources: [code]
confidence: high
last_verified: 2026-10-09
last_verified_sha: 05150894edc2511f0dd0bc7829b2a309cec36ec9
coverage_tier_1: 0/0
coverage_tier_2: 23/23
---

# TESTS-FSHARP

Two F# test projects that validate linq2db's F# language integration and the EFCore F# bridge. Neither project defines NUnit `[<TestFixture>]` classes directly; instead each `.fs` module exposes plain functions that are called from a C# test fixture in the consumer project (TESTS-EFCORE calls into `FSharpTestMethods`; the core F# tests are presumably wired from a C# fixture in `Tests.Base` or a companion project not in this area).

## Subsystems

### Tests/FSharp -- core linq2db F# tests (`linq2db.Tests.FSharp`, F# LangVersion 9)

References `Tests.Base.csproj`, `LinqToDB.FSharp.fsproj`, `FSharp.Core`, and `Npgsql.NodaTime`. No TFM constraint in the fsproj itself (inherits from `Directory.Build.props`). F# compilation order (order-sensitive):

`Issue4851.fs` -> `Issue2678.fs` -> `Models.fs` -> `Issue3357.fs` -> `WhereTest.fs` -> `SelectTest.fs` -> `InsertTest.fs` -> `MappingSchema.fs` -> `Issue3743.fs` -> `Issue4132.fs` -> `Issue5598.fs` -> `Issue1813.fs` -> `Issue5428.fs` -> `Issue4646.fs` -> `OptionMappingPrecedence.fs` -> `OptionTypes.fs` -> `OptionQueryTests.fs` -> `DuQueryTests.fs`

`Models.fs` must precede all test modules because the entity types are `open`ed by them. `Issue5598.fs` compiles directly after `Issue4132.fs` because it does `open Tests.FSharp.Issue4132` to reuse `Issue4132Table`. `Issue4646.fs`, `OptionMappingPrecedence.fs`, `OptionTypes.fs`, `OptionQueryTests.fs`, `DuQueryTests.fs` are self-contained (no cross-module `open`), which is why they sit at the tail of the compile list instead of needing to follow `Models.fs`.

`Issue5428.fs`'s `dateIntervalContains` / `MapMember` mapping is scoped to a dedicated `CONFIG = "Issue5428"` `MappingSchema` rather than the global `""` config, so it stays local to the test and doesn't leak into the process-wide registry.

A second, independent option-type auto-mapping subsystem is exercised by `Issue4646.fs`, `OptionMappingPrecedence.fs`, and `OptionTypes.fs`: `UseFSharp()` itself derives a `ColumnAttribute`/`ValueConverter` for scalar-element `'T option` (and `'T voption`) members with no per-test `MappingSchema.Initialize()` call, as a lower-priority schema combined under the user's own mapping schema. This is distinct from the older `PersonWithOptions` path (`Tests/FSharp/MappingSchema.fs`'s `Initialize()`), which predates the automatic combine and still requires an explicit call.

A third subsystem covers **query translation over option and single-case-union members** (`OptionQueryTests.fs`, `DuQueryTests.fs`): the tests go beyond column round-trips and assert that F# option/union member access inside LINQ predicates and projections is translated to SQL (`IS NULL` / `IS NOT NULL`, comparison on the underlying column) rather than evaluated client-side. Both modules take an `IDataContext`, create local tables via `CreateLocalTable`, and return plain values (counts, arrays, `struct (result, lastQuery)`) for the C# caller to assert on. `OptionQueryTests.lastQuery` reads `DataConnection.LastQuery` inside the test function (the local table's DROP would otherwise overwrite it) and returns null for a remote context.

### Tests/EntityFrameworkCore.FSharp -- EFCore F# bridge (`Tests.EntityFrameworkCore.FSharp`, F# LangVersion 9)

Fixed to `net8.0`. References `LinqToDB.EntityFrameworkCore.EF8.csproj`, `LinqToDB.FSharp.fsproj`, `EntityFrameworkCore.FSharp` (community package), and `FSharp.Core`. Compilation order: `FSharpExtensions.fs` -> `FSharpContext.fs` -> `FSharpTestMethods.fs`.

## Key types

**`Tests/FSharp/Models.fs`** -- entity record types used across all core F# tests:
- `Person` / `Patient` -- mutually recursive F# records (no `[<CLIMutable>]`); use `[<PrimaryKey>]`, `[<Column>]`, `[<Association>]`, `[<SequenceName>]` from `LinqToDB.Mapping`. `Person.Gender` is a discriminated union with `[<MapValue>]` attributes.
- `PersonCLIMutable` / `PatientCLIMutable` -- same schema as `Person`/`Patient` but `[<CLIMutable>]`; validates the two materialization paths (`FSharpEntityBindingInterceptor` vs. standard property-setter path).
- `ComplexPerson` / `ComplexPersonRecord` / `DeeplyComplexPerson` -- nested-record mapping tests: `FullName`, `NestedFullName`, `LastName` show flat-column-to-nested-field mapping via table-level `[<Column("col", "path.field")>]`.
- `PersonWithOptions` -- uses `string option` fields; requires `MappingSchema.Initialize()` to register option converters before use.
- `PersonConflictingNamesRecord` / `NameConflictingNamesRecord` -- deliberately conflicting case-only field names (`id`, `Id`, `iD`) to test F# record constructor parameter matching.
- `Child` / `Parent` -- simple two-field records reused across join tests.

**`Tests/FSharp/MappingSchema.fs`** -- `Initialize()` function that adds `string option` scalar type and a `SetConvertExpression` for `Option<_>`. Must be called before any `PersonWithOptions` test.

**`Tests/FSharp/Issue4132.fs`** -- `Issue4132Table` record (`Id`/`Number`/`Text`), `Issue4132Test1`/`Issue4132Test2` covering `table.Insert(fun () -> {...})` and `table.Update(predicate, setter)` F# lambda syntax. `Issue4132Table` is now also reused by `Issue5598.fs`.

**`Tests/FSharp/Issue5598.fs`** -- `setClauseOf` (string helper isolating the SET-clause text before `WHERE`) plus `UpdateSetsOnlyChangedColumn`, `UpdateSetsOnlyChangedColumnAsync`, `UpdateSetsOnlyChangedColumnNoPredicate`, `UpdateNoOpExcludesPrimaryKey` -- regression functions proving an F# record-copy `{ row with Text = v }` Update emits SET for only the changed column, never the PK or untouched columns, across predicate/no-predicate/async/no-op-copy shapes. Reuses `Issue4132Table` from `Issue4132.fs`.

**`Tests/FSharp/Issue4646.fs`** -- `OptionRow` record (`[<Table("Issue4646Table", IsColumnAttributeRequired = false)>]`, `int option`/`string option` columns) and `TestOptionRoundtrip`, asserting `None` reads back as `None` (not `Some 0`) using only `UseFSharp()`'s automatic option mapping, no manual `MappingSchema.Initialize()`. Distinct from `Tests/EntityFrameworkCore.FSharp/FSharpContext.fs`'s `Issue4646Table` `DbSet` -- same physical table name, different project/connection, no runtime interaction, but worth noting for anyone searching the KB by table name.

**`Tests/FSharp/OptionMappingPrecedence.fs`** -- `PrecedenceRow` (`Id`, `Note : string option` with an explicit `[<Column>]`) and `BuildExplicitSchema`/`VerifyExplicitDataTypePreserved`, guarding that `UseFSharp()`'s automatic option-column schema is combined at lower priority than a user's fluent `HasDataType(DataType.VarChar)` mapping on the same column (issue #195 follow-up).

**`Tests/FSharp/OptionTypes.fs`** -- six regression functions over five record types: `NullableElemRow` (`Nullable<int> option`, guards against `Nullable<Nullable<_>>` from `MakeGenericType`), `VOptionRow` (`int voption`/`string voption`, F# struct value-options), `DecimalOptionRow` (`decimal option` precision/scale preservation), `ComplexOptionRow`/`ComplexElem` (a complex-element option is *not* auto-scalarized, only a scalar-element option gets the converter), and `CustomScalarOptionRow`/`MyId` (a user-registered custom scalar type inside an option column -- currently **not** auto-mapped, see Known issues below).

**`Tests/FSharp/OptionQueryTests.fs`** -- `OptRow` (`Name : string option`, `Age : int option`) and `VOptRow` (`Name : string voption`), both `[<Table(IsColumnAttributeRequired = false)>]`. Functions assert SQL translation of option members: `IsSome`/`IsNone`/`Value`/`ValueProjection`/`IntValue` (the `Nullable<int>` provider-type re-type), `ValueOverNoneRow` (`.Value` on a NULL row yields the element default 0, no exception, like `Nullable<T>.Value`), `IsSomeProjection` (returns `struct (rows, lastQuery)` because a declined translation silently evaluates in memory and only the SQL text distinguishes them), the FSharp.Core module spellings (`ModuleIsSome`/`ModuleIsNone`/`ModuleGet`, `VOptionModule*` for `ValueOption.*`), voption members (`VOptionIsSome`/`VOptionIsNone`/`VOptionIsValueSome`/`VOptionIsValueNone`/`VOptionValue`), and `ParameterOperandIsRefused` (a captured voption forced into SQL via `Sql.AsSql` must be declined by the translator, since `IS NULL` on a boxed `ValueNone` parameter would fold to false and silently return no rows).

**`Tests/FSharp/DuQueryTests.fs`** -- single-case discriminated-union column auto-mapping (`#nowarn "3261"` for the nullable left-joined row). Types: `UserId = UserId of int` with `DuRow` (explicit `[<Column>]`) and `DuOuter` (outer side of a LEFT JOIN); `DuOptRow` (`Key : UserId option`, attribute-free); `[<Struct>] StructUserId` with `StructDuRow`/`StructDuOptRow`; `PrivateId = private PrivateId of int` with `PrivateDuRow`; `BoundaryRow` mixing claimed and unclaimed shapes (`Status` multi-case DU, `int list`, `Wrap of Inner` non-scalar wrapped field are *not* claimed). Functions: `EqualsLiteral`, `ReadBack`, `NullReadKey` (LEFT JOIN NULL read materializes as null, not a fabricated `UserId 0`), `OptionRoundTrip`, `OptionIsSome`/`OptionIsNone`/`OptionValueEquals`/`OptionEqualsSome`/`OptionValueProjection` (option-over-union composition: option converter's provider type is `Nullable<int>` while `.Value` re-types to `UserId`), `StructNullRead` (declared behaviour: unmatched LEFT JOIN row reads as `StructUserId 0`), `StructOptionRoundTrip` (the nullable spelling for a struct union), `PrivateRepresentationRoundTrip` (private case constructor reached by reflection -- `IsSingleCaseUnion` claims the type via `allowAccessToPrivateRepresentation`, so the mapping must work), and `MappingBoundary` (mapping-only: returns sorted `Member[:conv]` list of columns and which carry a `ValueConverter`).

**`Tests/FSharp/Issue1813.fs`** -- tables `Names`, `Addresses`, `TradeValid`, `NominationValid` plus private helpers `key`/`keyT` (null-safe id) and `encodeJoins` (sorted `trade-delivery-receipt` string for order-tolerant comparison). `Issue1813Test1`..`Issue1813Test11` cover groupJoin/leftOuterJoin/`.LeftJoin` chains: Test8 pins an interface-typed captured local (closure path, not a SubstHelper free variable), Test9 a `Nullable<int>` outer range variable, Test10 a string outer range variable (marker-call substitution), Test11 three chained groupJoin/DefaultIfEmpty blocks (F# widens the accumulated `AnonymousObject` from 2 to 4 type arguments). `Issue5794Test` (trailing inner `join` after two groupJoins, gated on #5794) and `Issue5790Test` (second groupJoin inner sequence correlated to the outer range variable, gated on #5790) are gated as noted in their comments (the gate lives at the C# caller). `Issue5790RefusalTest` pins that the flatten's fail-loud refusal throws `InvalidOperationException` mentioning "5790" (delete with the gate once #5790 is fixed). `VoidAction` is a private alias for parameterless `System.Action` working around FS1124 on net462.

**`Tests/EntityFrameworkCore.FSharp/FSharpContext.fs`** -- `AppDbContext : DbContext` with `WithIdentity : DbSet<WithIdentity>` and `Issue4646Table` (F# option columns `Value : int option`, `ValueN : Nullable<int> option` using EFCore `OptionConverter`). Issue 4646 tests cross-validate that EFCore and linq2db both handle F# option columns correctly.

**`Tests/EntityFrameworkCore.FSharp/FSharpExtensions.fs`** -- `WithFSharp(builder)` calls `builder.UseFSharpTypes()` (from `EntityFrameworkCore.FSharp` community package).

**`Tests/EntityFrameworkCore.FSharp/FSharpTestMethods.fs`** -- `TestLeftJoin`, `Issue4646TestEF`, `Issue4646TestLinqToDB` -- entry points called by TESTS-EFCORE's `FSharpTests` fixture.

## Issue regressions covered

| Module | Issue | Subject |
|---|---|---|
| `Issue1813.fs` | #1813 (+ #5794, #5790) | Complex `groupJoin`/`leftOuterJoin` combinations (11 numbered tests, multi-key tuples, captured-local and non-entity range variables, 3-level chain), plus gated #5794 / #5790 shapes and the #5790 refusal pin |
| `Issue2678.fs` | #2678 | Insert+select round-trip comparing F# class vs. `[<CLIMutable>]` record |
| `Issue3357.fs` | #3357 | `Union`/`Concat` of tuples, named records, and anonymous records in F# query expressions |
| `Issue3743.fs` | #3743 | Chained `.Join().LeftJoin()` via method syntax using tuples and anonymous records |
| `Issue4132.fs` | #4132 | `table.Insert(fun () -> ...)` and `table.Update(predicate, setter)` lambda syntax |
| `Issue4646.fs` | #4646 / #195 | F# `option` column round-trip via `UseFSharp()` automatic mapping, no manual `MappingSchema.Initialize()` |
| `Issue4851.fs` | #4851 | `(new DataOptions()).UseFSharp()` compiles without error (smoke) |
| `Issue5428.fs` | #5428 | `UseFSharp()` + NodaTime `LocalDate` + PostgreSQL `DateInterval`, CTE + window `Lead` |
| `Issue5598.fs` | #5598 | Record-copy `{ row with X = v }` Update emits SET only for the changed column, not the whole row |
| `OptionMappingPrecedence.fs` | #195 (follow-up) | Automatic option-column schema does not override an explicit fluent `DataType` |
| `OptionTypes.fs` | #195 | `Nullable<_> option`, `voption`, `decimal option`, complex-element and custom-scalar option edge cases |
| `OptionQueryTests.fs` | (no issue id) | SQL translation of option/voption members (`IsSome`/`IsNone`/`Value`, FSharp.Core module functions) in predicates and projections |
| `DuQueryTests.fs` | (no issue id) | Single-case DU (class, struct, private-representation) column auto-mapping, option-over-DU translation, mapping-boundary pins |

## Files (Tier 1 / Tier 2)

No files are currently designated Tier-1. All 23 files treated as Tier-2 and read in full.

| Tier | File |
|---|---|
| 2 | `Tests/FSharp/Tests.FSharp.fsproj` |
| 2 | `Tests/FSharp/Models.fs` |
| 2 | `Tests/FSharp/MappingSchema.fs` |
| 2 | `Tests/FSharp/SelectTest.fs` |
| 2 | `Tests/FSharp/WhereTest.fs` |
| 2 | `Tests/FSharp/InsertTest.fs` |
| 2 | `Tests/FSharp/Issue1813.fs` |
| 2 | `Tests/FSharp/Issue2678.fs` |
| 2 | `Tests/FSharp/Issue3357.fs` |
| 2 | `Tests/FSharp/Issue3743.fs` |
| 2 | `Tests/FSharp/Issue4132.fs` |
| 2 | `Tests/FSharp/Issue4851.fs` |
| 2 | `Tests/FSharp/Issue5428.fs` |
| 2 | `Tests/FSharp/Issue4646.fs` |
| 2 | `Tests/FSharp/Issue5598.fs` |
| 2 | `Tests/FSharp/OptionMappingPrecedence.fs` |
| 2 | `Tests/FSharp/OptionTypes.fs` |
| 2 | `Tests/FSharp/OptionQueryTests.fs` |
| 2 | `Tests/FSharp/DuQueryTests.fs` |
| 2 | `Tests/EntityFrameworkCore.FSharp/Tests.EntityFrameworkCore.FSharp.fsproj` |
| 2 | `Tests/EntityFrameworkCore.FSharp/FSharpContext.fs` |
| 2 | `Tests/EntityFrameworkCore.FSharp/FSharpExtensions.fs` |
| 2 | `Tests/EntityFrameworkCore.FSharp/FSharpTestMethods.fs` |

`Tests.FSharp.fsproj` does not include `Issue4851.fs` last despite its content being a standalone smoke test -- it is first in the fsproj `<Compile>` list (before `Models.fs`), which is valid because it has no dependency on `Models.fs`.

## Inbound / outbound dependencies

**Inbound:**
- TESTS-EFCORE: its `FSharpTests` C# fixture (`#if EF8`-gated) calls `FSharpTestMethods.TestLeftJoin`, `Issue4646TestEF`, `Issue4646TestLinqToDB`, and `WithFSharp`.
- Any C# fixture in `Tests.Base` / the main test project that wires the `Tests.FSharp.*` module functions as NUnit tests (not in this area -- the wrapper fixture is in the C# test project).

**Outbound:**
- **FSHARP** production area: `LinqToDB.FSharp.fsproj` -- `DataOptions.UseFSharp()`, `FSharpEntityBindingInterceptor` (exercised by non-`[<CLIMutable>]` record reads in `WhereTest.LoadSingle`, `SelectTest.SelectField`, etc.), the automatic scalar-`option`/`voption` schema combine exercised by `Issue4646.fs`/`OptionMappingPrecedence.fs`/`OptionTypes.fs`, and the option-member / single-case-union translators and converters exercised by `OptionQueryTests.fs`/`DuQueryTests.fs`.
- **EFCORE** production area: `LinqToDB.EntityFrameworkCore.EF8.csproj` -- `.ToLinqToDB()`, `CreateLinqToDBConnection()`.
- `Tests.Base.csproj` -- `Tests.Tools` module (used in `InsertTest`, `Issue1813`, `Issue4132`); `Tests` namespace open in issue modules.
- External: NUnit, `Npgsql.NodaTime` (Issue5428), `EntityFrameworkCore.FSharp` community package (EFCore project).

## Known issues / debt

- `Tests.FSharp.fsproj` carries no TFM override; it inherits from `Directory.Build.props`. The EFCore project is pinned to `net8.0` which limits it to EF8 and prevents testing EF9/EF10 F# scenarios.
- `Issue5428.fs` takes a raw `connectionString : string` parameter (no `IDataContext`), meaning it cannot be run by the standard NUnit DataContext fixture mechanism without a custom wrapper -- it is PostgreSQL-only and likely guarded by a provider skip in the C# caller.
- The `MappingSchema.Initialize()` function must be called before any `PersonWithOptions`-using test; there is no test-level `[<SetUp>]` enforcement visible in this area. This is separate from `UseFSharp()`'s own automatic scalar-`option` mapping (see `OptionTypes.fs`/`Issue4646.fs`), which needs no such call.
- `Issue5598.fs`'s `UpdateSetsOnlyChangedColumnAsync` now covers an async LINQ path (`task { ... }` / `UpdateAsync`); `IAsyncEnumerable` and `CancellationToken` paths are still not exercised by any F# test in this area.
- `OptionTypes.fs`'s `VerifyCustomScalarOptionMapped` documents an open gap: `IsScalarOption` (the gate deciding whether a `'T option` member gets an auto-mapped column/converter) consults `MappingSchema.Default` only, so a type made scalar solely via `AddScalarType` on a user's own (non-default) schema is not recognized -- the option member is silently left unmapped rather than getting a `ColumnAttribute`/`ValueConverter`. Comment marks it as gated pending a fix to the scalar gate.
- `Issue1813.fs` carries two known-broken shapes: `Issue5794Test` (groupJoin chain followed by a plain inner `join` re-projects the accumulated element, the flatten declines, the second `DefaultIfEmpty` becomes an INNER JOIN and drops rows -- gated on #5794) and `Issue5790Test` (groupJoin whose inner sequence is correlated to the outer range variable cannot be flattened -- gated on #5790). `Issue5790RefusalTest` runs un-gated to keep the fail-loud `InvalidOperationException` from regressing to a silent decline.
- `DuQueryTests.StructNullRead` pins a declared quirk rather than an ideal: a NULL read of a non-optional *struct* single-case union yields the union wrapping 0 (like a plain `int` member), so `StructUserId option` is the only way to express a nullable column of that type. In contrast the class-union `NullReadKey` expects a real null.

## See also

- [FSHARP area](../FSHARP/INDEX.md) -- production `linq2db.FSharp` package (`DataOptions.UseFSharp`, `FSharpEntityBindingInterceptor`)
- [TESTS-EFCORE area](../TESTS-EFCORE/INDEX.md) -- hosts the `FSharpTests` fixture that calls into this area
- [TESTS-INFRA area](../TESTS-INFRA/INDEX.md) -- `Tests.Base` / `Tests.Tools` depended on by `InsertTest`, `Issue*` modules

<details><summary>Coverage</summary>

Read (this run):
- `Tests/FSharp/Tests.FSharp.fsproj` -- project setup, TFMs, compile order, references
- `Tests/FSharp/Models.fs` -- all entity record types
- `Tests/FSharp/MappingSchema.fs` -- option-type mapping schema helper
- `Tests/FSharp/SelectTest.fs` -- select, left-join, group-join, record projection tests
- `Tests/FSharp/WhereTest.fs` -- where, LoadWith, ComplexPerson, option-type tests
- `Tests/FSharp/InsertTest.fs` -- insert Child and ComplexPerson tests
- `Tests/FSharp/Issue1813.fs` -- 7 groupJoin/leftOuterJoin regression tests
- `Tests/FSharp/Issue2678.fs` -- class vs CLIMutable record insert/select
- `Tests/FSharp/Issue3357.fs` -- Union/Concat of tuples, records, anon records
- `Tests/FSharp/Issue3743.fs` -- chained Join+LeftJoin method syntax
- `Tests/FSharp/Issue4132.fs` -- Insert/Update lambda syntax
- `Tests/FSharp/Issue4851.fs` -- DataOptions.UseFSharp() smoke test
- `Tests/FSharp/Issue5428.fs` -- UseFSharp + NodaTime + PostgreSQL DateInterval + CTE
- `Tests/EntityFrameworkCore.FSharp/Tests.EntityFrameworkCore.FSharp.fsproj` -- project setup, net8.0, references
- `Tests/EntityFrameworkCore.FSharp/FSharpContext.fs` -- AppDbContext, WithIdentity, Issue4646Table
- `Tests/EntityFrameworkCore.FSharp/FSharpExtensions.fs` -- WithFSharp helper
- `Tests/EntityFrameworkCore.FSharp/FSharpTestMethods.fs` -- TestLeftJoin, Issue4646 entry points

Tier-2 visited: 17/17 (.fs files) + 2/2 (.fsproj files) = 18/18 total. No skips.

Read (this run -- delta):
- `Tests/FSharp/Tests.FSharp.fsproj` -- compile order updated: `Issue5598.fs` inserted right after `Issue4132.fs`; `Issue4646.fs`, `OptionMappingPrecedence.fs`, `OptionTypes.fs` appended after `Issue5428.fs`. No new package/project references.
- `Tests/FSharp/Issue4132.fs` -- re-read, content unchanged; now also reused by `Issue5598.fs` via `open Tests.FSharp.Issue4132` for the shared `Issue4132Table`.
- `Tests/FSharp/Issue4646.fs` -- new module; `OptionRow` mapped to table `Issue4646Table`, `TestOptionRoundtrip` round-trips `int option`/`string option`, asserting `None` stays `None` under `UseFSharp()`'s automatic mapping (no `MappingSchema.Initialize()` call).
- `Tests/FSharp/Issue5428.fs` -- re-read, test bodies unchanged; a new comment documents that `dateIntervalContains`'s `MapMember` mapping is scoped to `CONFIG = "Issue5428"` instead of the global `""` schema, to avoid leaking into the process-wide registry.
- `Tests/FSharp/Issue5598.fs` -- new module; `setClauseOf` plus four regression functions proving F# record-copy `{ row with X = v }` Update emits SET only for the changed column (predicate, no-predicate, async, no-op-copy shapes), reusing `Issue4132Table`.
- `Tests/FSharp/Models.fs` -- re-read in full; no new or changed record types found versus the previously documented set.
- `Tests/FSharp/OptionMappingPrecedence.fs` -- new module; `PrecedenceRow` regression guard that the automatic option-column schema combine is lower-priority than a user's explicit fluent `HasDataType` (issue #195 follow-up).
- `Tests/FSharp/OptionTypes.fs` -- new module; six regression functions over `Nullable<int> option`, `voption`, `decimal option` precision, complex-element option (not auto-scalarized), and a schema-only custom scalar type (`MyId`) inside an option column -- the last documents an open mapping gap (see Known issues).

Updated Tier-2 total (this run): 21/21. No skips.

Read (this run -- delta):
- `Tests/FSharp/DuQueryTests.fs` -- new module; single-case DU column auto-mapping (class, struct, private-representation), option-over-DU translation (`IsSome`/`IsNone`/`Value`/equality), LEFT JOIN NULL reads, and `MappingBoundary` pinning which shapes are claimed.
- `Tests/FSharp/OptionQueryTests.fs` -- new module; SQL translation of option/voption members and FSharp.Core module functions in predicates and projections, `IsSomeProjection` returning the captured SQL, and `ParameterOperandIsRefused` for parameter operands.
- `Tests/FSharp/Issue1813.fs` -- grew from 7 to 11 numbered tests (Test8 interface-typed captured local, Test9 `Nullable<int>` range variable, Test10 string range variable, Test11 three chained groupJoins), added `encodeJoins`/`key`/`keyT` helpers replacing positional asserts, added gated `Issue5794Test` / `Issue5790Test` and the un-gated `Issue5790RefusalTest`.
- `Tests/FSharp/Tests.FSharp.fsproj` -- compile list now ends `... OptionTypes.fs`, `OptionQueryTests.fs`, `DuQueryTests.fs`; no new package/project references.

Updated Tier-2 total (this run): 23/23. No skips.
</details>
