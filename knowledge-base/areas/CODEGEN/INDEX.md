---
area: CODEGEN
kind: area-index
sources: [code]
confidence: high
last_verified: 2026-10-10
last_verified_sha: 05150894edc2511f0dd0bc7829b2a309cec36ec9
coverage_tier_1: 6/6
coverage_tier_2: 2/2
---

# CODEGEN — Roslyn Source Generator and Internal Analyzers

Standalone Roslyn project (`Source/CodeGenerators/`) hosting (a) an incremental source generator that produces `ExpressionBuilder.g.cs` at compile time, replacing a hand-maintained dispatch table inside `ExpressionBuilder.FindBuilderImpl` with a generated `switch` over `ExpressionType` and `MethodInfo.Name`, and (b) three repo-internal `DiagnosticAnalyzer` classes (`LINQ2DB0001`..`LINQ2DB0006`) guarding linq2db's own source invariants. The analyzers ship in no package (`IsPackable=false`). The user-facing analyzer family (`L2DB1xxx`) lives in `Source/LinqToDB.Analyzers` (see [ANALYZERS](../ANALYZERS/INDEX.md)). The area also owns the analyzer test project `Tests/Tests.Analyzers.Internal/` (currently covering `LINQ2DB0004`..`0006`).

## Subsystems

**Attribute scanning.** `BuildersGenerator.Initialize` (`BuildersGenerator.cs:17`) registers three `ForAttributeWithMetadataName` syntax providers — one per attribute:

- `BuildsAnyAttribute` → `TransformBuildsAny` → `BuilderNode` with `BuilderKind.Any`
- `BuildsExpressionAttribute` → `TransformBuildsExpression` → `EquatableReadOnlyList<BuilderNode>` with `BuilderKind.Expr`
- `BuildsMethodCallAttribute` → `TransformBuildsMethodCall` → `EquatableReadOnlyList<BuilderNode>` with `BuilderKind.Call`

All three streams are `Collect()`-ed and combined via `Combine` before being fed to `RegisterImplementationSourceOutput` (`BuildersGenerator.cs:45–56`).

**Parameter reflection.** `GetMethodParameters` (`BuildersGenerator.cs:109`) inspects the `CanBuild`/`CanBuildMethod` method on each decorated type and records which of `(MethodCallExpression/Expression, BuildInfo, ExpressionBuilder)` the method expects. This is encoded as a `CallParams` flags enum (`BuildersGenerator.Models.cs:12`) so the renderer can emit exactly the right call signature without runtime overhead.

**Code emission.** `GenerateCode` (`BuildersGenerator.cs:165`) emits a single source file `ExpressionBuilder.g.cs` containing a `partial class ExpressionBuilder` with a `private static partial ISequenceBuilder? FindBuilderImpl(BuildInfo, ExpressionBuilder)`. The body is a three-level dispatch: `switch (expr.NodeType)` → `case ExpressionType.Call: switch (call.Method.Name)` → per-builder `CanBuildMethod(call[, info][, builder])` guards. The `Any`-kind builders fall outside the switch and are tried unconditionally after all typed cases.

**Internal analyzers.** Three `[DiagnosticAnalyzer(LanguageNames.CSharp)]` classes in namespace `CodeGenerators`, wired into `LinqToDB.csproj` the same way as the generator (`OutputItemType="Analyzer"`). Rule ids are tracked in `AnalyzerReleases.Unshipped.md` (all `Usage`, `Warning`). `AnalyzerReleases.Shipped.md` is the shipped counterpart. Both are registered as `AdditionalFiles` in `CodeGenerators.csproj`.

- `SqlBuilderAliasAnalyzer` (`LINQ2DB0001`). Inside a `BasicSqlBuilder`-derived type (`LinqToDB.Internal.SqlProvider.BasicSqlBuilder`), flags *reads* of node-held names that must be resolved through `AliasesContext`: `SqlColumn.Alias` → `GetColumnAlias`, `SqlTableSource.Alias` → `GetTableAlias`, `SqlCteTableField.Name` and `SqlCteField.Name` → `GetFieldName` (the `Guards` array). Registers an `OperationKind.PropertyReference` action. Assignments to the property are skipped, and `DerivesFrom` walks the enclosing type's base chain. `SqlTable.Alias` and `SqlField.PhysicalName` are deliberately unguarded (source of truth on the node, PhysicalName is also used verbatim in DDL). `RawAlias` is the escape hatch. Generated code is not analyzed (`GeneratedCodeAnalysisFlags.None`). Rationale: non-mutating aliasing keeps final names off cached AST nodes so statements can be aliased and rendered concurrently.
- `ServerSideOnlyContractAnalyzer` (`LINQ2DB0002` and `LINQ2DB0003`). 0002: throw-only stub with no server-side-only declaration. 0003: declared server-side-only member whose stub throws something other than `ServerSideOnlyException`. A member counts as declared via `[ServerSideOnly]`, an `Sql.Expression`-derived attribute with effective `ServerSideOnly` (all `Sql.Extension` ctors), an `Sql.TableFunction`-derived attribute, or `[ExpressionMethod]`. Detection logic is `ServerSideOnlyContract` (`Symbols.TryCreate`, `TryGetStub`, `Classify`, `Options`), **linked** from `Source/LinqToDB.Analyzers/ServerSideOnlyContract.cs` (csproj `Compile Include` + `Link`) so the shipped `L2DB1003`/`L2DB1004` decide identical cases (two Roslyn components cannot reference each other). Exception sets are hardcoded to `ServerSideOnlyException` (no knobs, unlike the shipped twin). Unlike the twin it analyzes generated code (`Analyze | ReportDiagnostics`) because checked-in generated files such as `Sql.Row.generated.cs` carry the defects. Uses `RegisterOperationBlockAction`.
- `ProjectFlagsAnalyzer` (`LINQ2DB0004` never true here, `LINQ2DB0005` always true here, `LINQ2DB0006` model unreadable). Guards the invariant that `ProjectFlags` (`LinqToDB.Internal.Linq.Builder`) mixes a mutually-exclusive build purpose with independent modifiers while `ProjectFlagExtensions` exposes flat `Is*()` predicates, so impossible conjunctions look idiomatic. The model is **derived, not hardcoded**: `FlagModel.Read` parses `ExpressionBuildVisitor.GetProjectFlags` (an unconditional `flags |= X` per switch section is the purpose, a conditional add in a section is an optional modifier, a conditional add after the switch is a free modifier, and `ReadDomain` enumerates purpose x optional subsets x free subsets into the reachable `Domain`) and the single-expression bodies of `ProjectFlagExtensions` predicates (`ReadPredicates`: `HasFlag(X)` becomes an all-of `Atom`, `(flags & mask) != 0` an any-of `Atom`). Any shape it cannot parse yields `LINQ2DB0006` (reported from the declaring type, visitor or extensions) and an underivable domain disables 0004/0005 for the compilation. Analysis: per operation block containing a recognised atom (`RegisterOperationBlockStartAction` gate), `CollectTrackedSymbols` picks parameters/locals of the flags type that are never written (fields and properties are never tracked), builds the Roslyn `ControlFlowGraph`, runs a forward may-analysis (`AnalyzeGraph`, join = union, `Filter` uses three-valued `Evaluate` where null = unknown), then `ReportBooleans`/`ReportConstants` report the outermost constant sub-expression, with `ClimbNegations` recovering the author's `!` text. Local functions and lambdas are analyzed recursively. Active only when `ProjectFlags` resolves in the *source assembly* (zero cost for consumers). If the enum exists but `ProjectFlagExtensions` or `ExpressionBuildVisitor` is missing it reports 0006. Out of scope by design: flag composition (`SQL | Expression`, `SQL | Subquery` in `ExprCacheKey`), with a local `#pragma warning disable` as the escape hatch. Constraint: list patterns are unavailable in this project (no `System.Index` polyfill).

**Internal analyzer tests** (`Tests/Tests.Analyzers.Internal/`). DB-free, provider-independent NUnit project (`linq2db.Tests.Analyzers.Internal`, `OutputType=Exe`, `EnableNUnitRunner`), single TFM `net10.0` (`TargetFrameworks` cleared to override the Tests-wide multi-TFM). It references `CodeGenerators.csproj` as a plain `ProjectReference` **without** `OutputItemType="Analyzer"` (`Tests.Analyzers.Internal.csproj:35`), so the rules run only against the snippets the harness compiles, never against the test project itself. It references no linq2db assembly: every snippet declares its own miniature of the model under analysis. `Microsoft.CodeAnalysis.CSharp.Workspaces` is pinned via `VersionOverride="5.9.0"` because `CodeGenerators` compiles against Roslyn 5.9.0 and cannot load in the 4.8 host that `Tests.Analyzers` uses (that 4.8 pin is the shipped package consumer floor, so `Directory.Packages.props` is left alone). `..\BannedSymbols.txt` is removed from `AdditionalFiles`. Being a bare NUnit MTP host, it does not accept `--test-progress` (see the analyzer-test notes in `.claude/docs/testing.md`).

- `AnalyzerVerifier<TAnalyzer>` (`AnalyzerVerifier.cs:13`): thin wrapper over `CSharpAnalyzerTest<TAnalyzer, DefaultVerifier>` with `ReferenceAssemblies.Net.Net80`. `VerifyAsync(source, params DiagnosticResult[])` is the only entry point. Unlike the `Tests.Analyzers` verifier it adds no linq2db reference.
- `ProjectFlagsAnalyzerTests` (`ProjectFlagsAnalyzerTests.cs:13`): 46 `[Test]` fixtures for `LINQ2DB0004`..`0006`. The `Model` const (`:18`) is a faithful miniature of production (`ProjectFlags`, `BuildPurpose`, `BuildFlags`, `ProjectFlagExtensions` with both statement- and expression-bodied predicates, and `ExpressionBuildVisitor.GetProjectFlags` with two free modifiers so the powerset step is exercised) and is prepended to every snippet by `Consumer(body)` / `Verify`. Groups: impossible or redundant conjunctions (`KeysWithExpandIsNeverTrue`, the #5727 shape, plus parameter vs local receivers, negations, `HasFlag` and `SqlOrExpression` atoms), control-flow cases (early return, try/catch, dead code, hoisted tests, opaque calls, reassigned flags not tracked, lambdas and local functions), drift fixtures that mutate `Model` (switch shape, seed, return, accumulator target, empty or two-purpose arms, renamed visitor type, foreign mask, wrong predicate value) proving the condition rules go silent and `LINQ2DB0006` is raised, and negative fixtures (`AnUnrelatedFlagsEnumWithTheSamePredicateShapeIsNotMatched`, `ModelDefinitionSitesAreNotFlagged`). `NeverTrue(clause, reason)` pins the message reason argument against `ExcludedEarlier` / `UniformOverDomain`. No fixtures exist yet for `LINQ2DB0001`..`0003`.

## Key types

| Type | File | Role |
|---|---|---|
| `BuildersGenerator` | `BuildersGenerator.cs` | `[Generator]` / `IIncrementalGenerator` entry point |
| `BuilderNode` | `BuildersGenerator.Models.cs:14` | Sealed record: fully-qualified builder class name, dispatch key (method name or `ExpressionType` string), `BuilderKind`, check-method name, `CallParams` bitmask |
| `BuilderKind` | `BuildersGenerator.Models.cs:9` | `Any`, `Expr`, `AnyCall`, `Call` — dispatch tier |
| `CallParams` | `BuildersGenerator.Models.cs:12` | `[Flags]` bitmask: `Call=1`, `Info=2`, `Builder=4`, drives which overload the renderer emits |
| `EquatableReadOnlyList<T>` | `EquatableReadOnlyList.cs:22` | Value-equality `IReadOnlyList<T>` wrapper, required for incremental SG cache stability (plain `List<T>` breaks caching) |
| `SqlBuilderAliasAnalyzer` | `SqlBuilderAliasAnalyzer.cs` | `LINQ2DB0001`: SQL builders must read finalized aliases via `AliasesContext` |
| `ServerSideOnlyContractAnalyzer` | `ServerSideOnlyContractAnalyzer.cs` | `LINQ2DB0002`/`0003`: server-side-only declaration vs stub body agreement |
| `ProjectFlagsAnalyzer` | `ProjectFlagsAnalyzer.cs` | `LINQ2DB0004`/`0005`/`0006`: impossible or redundant `ProjectFlags` tests, flow-sensitive, model derived from `GetProjectFlags` |
| `ProjectFlagsAnalyzer.FlagModel` / `Atom` | `ProjectFlagsAnalyzer.cs` | Derived reachable-value `Domain`, predicate atoms, three-valued `Evaluate`/`Explain` |
| `AnalyzerVerifier<TAnalyzer>` | `Tests/Tests.Analyzers.Internal/AnalyzerVerifier.cs:13` | Test harness over the Roslyn testing SDK for internal analyzers |
| `ProjectFlagsAnalyzerTests` | `Tests/Tests.Analyzers.Internal/ProjectFlagsAnalyzerTests.cs:13` | NUnit fixture, 46 tests for `LINQ2DB0004`..`0006` |

## Generator pipeline

```
SyntaxProvider.ForAttributeWithMetadataName(BuildsAny/Expression/MethodCall)
  → Transform* (symbol → BuilderNode / EquatableReadOnlyList<BuilderNode>)
  → .Collect()
  → .Combine(…)
  → RegisterImplementationSourceOutput → GenerateCode → ExpressionBuilder.g.cs
```

The `EquatableReadOnlyList<T>` wrapper (`EquatableReadOnlyList.cs:28–30`) is what allows the incremental engine to skip re-generation when the builder list has not changed — standard `ImmutableArray<T>` is used after `Collect()`, but the pre-collect transform step returns `EquatableReadOnlyList<T>` so the pipeline equality check is meaningful.

## Files (Tier 1 / Tier 2)

**Tier 1 (all read):**

| File | Role |
|---|---|
| `BuildersGenerator.cs` | Generator entry point, all transform and render methods |
| `BuildersGenerator.Models.cs` | Internal enums and `BuilderNode` record |
| `EquatableReadOnlyList.cs` | Value-equality list wrapper |
| `SqlBuilderAliasAnalyzer.cs` | `LINQ2DB0001` analyzer |
| `ServerSideOnlyContractAnalyzer.cs` | `LINQ2DB0002`/`0003` analyzer (detection core linked from `LinqToDB.Analyzers`) |
| `ProjectFlagsAnalyzer.cs` | `LINQ2DB0004`/`0005`/`0006` flow analyzer |

**Tier 2 (all read, 2/2; the `Tests/Tests.Analyzers.Internal/**` files owned since the kb-areas row was extended):**

| File | Role |
|---|---|
| `Tests/Tests.Analyzers.Internal/AnalyzerVerifier.cs` | Roslyn test-SDK wrapper |
| `Tests/Tests.Analyzers.Internal/ProjectFlagsAnalyzerTests.cs` | 46 fixtures for `LINQ2DB0004`..`0006` |

All `Source/CodeGenerators` `.cs` files are Tier 1.

**Tier 3 (counted, not read):** `CodeGenerators.csproj`, `AnalyzerReleases.Shipped.md`, `AnalyzerReleases.Unshipped.md`, `Directory.Build.props` — project metadata. The csproj and Unshipped release file were read this delta for hook-in verification. `Tests/Tests.Analyzers.Internal/Tests.Analyzers.Internal.csproj` is project metadata (read for the Subsystems note, not counted).

## Project configuration

`CodeGenerators.csproj` (`Source/CodeGenerators/CodeGenerators.csproj:3–8`):
- `TargetFramework`: `netstandard2.0` — Roslyn SG requirement.
- `IsRoslynComponent`: `true` — enables Roslyn-component analyzer rules.
- `EnforceExtendedAnalyzerRules`: `true`.
- `IsPackable`: `false` — never shipped as a NuGet package directly.
- References: `Microsoft.CodeAnalysis.CSharp`, `Microsoft.CodeAnalysis.Analyzers`, `Meziantou.Polyfill` (polyfills `System.HashCode` and `IsExternalInit` for netstandard2.0 targets).
- Linked source: `LinqToDB.Analyzers/ServerSideOnlyContract.cs` (`Compile Include` + `Link`, same idiom as `LinqToDB.Compat`).
- `AdditionalFiles`: `AnalyzerReleases.Shipped.md`, `AnalyzerReleases.Unshipped.md` (release tracking for `LINQ2DB0001`..`0006`, all `Usage`/`Warning`).

Hook-in from `LinqToDB.csproj` (`Source/LinqToDB/LinqToDB.csproj:26`):

```xml
<ProjectReference Include="../CodeGenerators/CodeGenerators.csproj"
    OutputItemType="Analyzer"
    ReferenceOutputAssembly="false" />
```

`OutputItemType="Analyzer"` registers the project as a source generator and analyzer host, `ReferenceOutputAssembly="false"` ensures `CodeGenerators.dll` is not part of the `LinqToDB` public API surface. Because the analyzers run inside the `LinqToDB` compilation, `TreatWarningsAsErrors` turns their warnings into build errors.

`Directory.Build.props` overrides: enables `RunAnalyzersDuringBuild`, `EnforceCodeStyleInBuild`, `AnalysisLevel=preview-All`, `TreatWarningsAsErrors`, `Nullable=enable`, `LangVersion=14` — stricter than the repo root defaults to keep the generator itself clean. Does **not** suppress anything.

## Inbound / outbound dependencies

**Consumed by:** `LinqToDB.csproj` (via `OutputItemType="Analyzer"`) — the generator runs during the `LinqToDB` build and injects `ExpressionBuilder.g.cs` into the `LinqToDB.Internal.Linq.Builder` namespace, and the three analyzers inspect `LinqToDB` source. `Tests/Tests.Analyzers.Internal` consumes `CodeGenerators.csproj` as a plain project reference (analyzers under test, not applied to the test project itself).

**Reads at compile time:** every class in `Source/LinqToDB/Internal/Linq/Builder/` that carries `[BuildsAnyAttribute]`, `[BuildsExpressionAttribute]`, or `[BuildsMethodCallAttribute]` — see [EXPR-TRANS](../EXPR-TRANS/INDEX.md). The analyzers additionally couple to by-name symbols: `BasicSqlBuilder`, `SqlColumn`, `SqlTableSource`, `SqlCteTableField`, `SqlCteField` (SQL AST, see [SQL-AST](../SQL-AST/INDEX.md)), `ProjectFlags`, `ProjectFlagExtensions`, `ExpressionBuildVisitor.GetProjectFlags` (EXPR-TRANS), and `ServerSideOnlyException` plus the `[ServerSideOnly]`/`Sql.*` attributes. Renaming or reshaping any of these changes analyzer behaviour (`ProjectFlagsAnalyzer` fails loudly with `LINQ2DB0006`). The `Model` const in `ProjectFlagsAnalyzerTests` mirrors the production `ProjectFlags` shape and must be updated by hand if the real model structure changes meaningfully.

**Shares code with:** `Source/LinqToDB.Analyzers` (`ServerSideOnlyContract.cs` linked file). User-facing `L2DB1xxx` rules and their tests: [ANALYZERS](../ANALYZERS/INDEX.md).

**NuGet dependency:** `Microsoft.CodeAnalysis.CSharp` (Roslyn SDK, `PrivateAssets="all"`, never transitive).

## Known issues / debt

None identified. Generator is self-contained, adding a new builder requires only decorating the class with the appropriate attribute — no manual registration step. `ProjectFlagsAnalyzer` is tightly coupled to the syntactic shape of `GetProjectFlags` and the `ProjectFlagExtensions` predicate bodies (by design, drift is reported as `LINQ2DB0006`). Test gap: `LINQ2DB0001`..`0003` have no fixtures in `Tests.Analyzers.Internal` (only `ProjectFlagsAnalyzerTests` exists).

## See also

- [EXPR-TRANS area](../EXPR-TRANS/INDEX.md) — `ExpressionBuilder` and the builder registry that this generator populates, plus `ProjectFlags`.
- [ANALYZERS area](../ANALYZERS/INDEX.md) — user-facing `L2DB1xxx` analyzers (`Source/LinqToDB.Analyzers`) and their tests.
- `Source/LinqToDB/Internal/Linq/Builder/ExpressionBuilder.cs` — declares `partial ISequenceBuilder? FindBuilderImpl` that the generator implements.
- `Source/LinqToDB.Analyzers/ServerSideOnlyContract.cs` — shared detection core for `LINQ2DB0002`/`0003` and `L2DB1003`/`L2DB1004`.

<details><summary>Coverage</summary>

Tier 1 (6/6 read):
- `Source/CodeGenerators/BuildersGenerator.cs` — generator entry point, all render methods
- `Source/CodeGenerators/BuildersGenerator.Models.cs` — enums and BuilderNode record
- `Source/CodeGenerators/EquatableReadOnlyList.cs` — value-equality list wrapper
- `Source/CodeGenerators/SqlBuilderAliasAnalyzer.cs` — LINQ2DB0001 (read this delta)
- `Source/CodeGenerators/ServerSideOnlyContractAnalyzer.cs` — LINQ2DB0002/0003 (read this delta)
- `Source/CodeGenerators/ProjectFlagsAnalyzer.cs` — LINQ2DB0004/0005/0006 (read this delta)

Tier 2: 0 files (all .cs files promoted to Tier 1).

Tier 3 (counted, not read):
- `Source/CodeGenerators/CodeGenerators.csproj` — project metadata (read for hook-in verification, excluded from coverage count per Tier-3 rule)
- `Source/CodeGenerators/Directory.Build.props` — build overrides (same)
- `Source/CodeGenerators/AnalyzerReleases.Shipped.md`, `AnalyzerReleases.Unshipped.md` — analyzer release tracking

Cross-area read (hook-in verification):
- `Source/LinqToDB/LinqToDB.csproj:26` — confirms `OutputItemType="Analyzer"` reference

Read (this run -- delta):
- `Source/CodeGenerators/AnalyzerReleases.Shipped.md` (A) — new release-tracking file
- `Source/CodeGenerators/AnalyzerReleases.Unshipped.md` (A) — lists LINQ2DB0001..0006 as Usage/Warning
- `Source/CodeGenerators/CodeGenerators.csproj` (M) — added linked `ServerSideOnlyContract.cs` and `AdditionalFiles` release files
- `Source/CodeGenerators/ProjectFlagsAnalyzer.cs` (A) — LINQ2DB0004/0005/0006, derived-model flow analyzer
- `Source/CodeGenerators/ServerSideOnlyContractAnalyzer.cs` (A) — LINQ2DB0002/0003, uses linked ServerSideOnlyContract
- `Source/CodeGenerators/SqlBuilderAliasAnalyzer.cs` (A) — LINQ2DB0001, AliasesContext read guard

Read (this run -- delta, internal-analyzer tests; Tier 2 now 2/2, Tier 1 list reconciled with the extended kb-areas row, still 6/6):
- `Tests/Tests.Analyzers.Internal/AnalyzerVerifier.cs` (A) — Roslyn test-SDK wrapper, net80 reference assemblies, no linq2db reference
- `Tests/Tests.Analyzers.Internal/ProjectFlagsAnalyzerTests.cs` (A) — Model const plus 46 fixtures for LINQ2DB0004..0006 (header, helpers and full test inventory read)
- `Tests/Tests.Analyzers.Internal/Tests.Analyzers.Internal.csproj` (A) — Tier 3 metadata: net10.0 only, plain ProjectReference to CodeGenerators, Workspaces 5.9.0 override

</details>
