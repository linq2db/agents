---
area: ANALYZERS
kind: area-index
sources: [code]
confidence: high
last_verified: 2026-10-10
last_verified_sha: 05150894edc2511f0dd0bc7829b2a309cec36ec9
coverage_tier_1: 7/7
coverage_tier_2: 11/11
---

# ANALYZERS -- user-facing Roslyn rules (L2DB1xxx)

Shipped in the `linq2db.Analyzers` NuGet package (analyzer + code-fix assemblies). `Source/LinqToDB/LinqToDB.csproj` depends on the package and flows its analyzer assets, so the rules arrive with `linq2db` (and `linq2db.FSharp`). Repo-internal `LINQ2DB0xxx` rules are NOT here -- see [CODEGEN](../CODEGEN/INDEX.md). Rule pages: [L2DB1001](../../github/wiki/L2DB1001.md), [L2DB1002](../../github/wiki/L2DB1002.md), [L2DB1003](../../github/wiki/L2DB1003.md), [L2DB1004](../../github/wiki/L2DB1004.md).

## Subsystems

### Packaging and build layout
- Two projects, split because of RS1038: `Source/LinqToDB.Analyzers/LinqToDB.Analyzers.csproj` (analyzers, no Workspaces reference, `IsPackable=false`, pins `Microsoft.CodeAnalysis.CSharp` 4.8.0 via `VersionOverride`) and `Source/LinqToDB.Analyzers.CodeFixes/LinqToDB.Analyzers.CodeFixes.csproj` (references `Microsoft.CodeAnalysis.CSharp.Workspaces`, project-references the analyzer project with `PrivateAssets=all`, is the packable `linq2db.Analyzers`).
- Shared settings in `Source/Analyzers.Common.props`: `netstandard2.0`, `IsRoslynComponent`, `EnforceExtendedAnalyzerRules`, polyfills `HashCode` and `IsExternalInit`, `Microsoft.CodeAnalysis.Analyzers` private.
- Both DLLs are packed under `analyzers/dotnet/roslyn4.8/cs`, so hosts older than Roslyn 4.8 silently skip them instead of hitting CS9057. Package carries no linq2db dependency (`SuppressDependenciesWhenPacking`, `DevelopmentDependency`), so every rule resolves linq2db types with `GetTypeByMetadataName` and stays silent when absent.
- Opt-out: `Source/LinqToDB.Analyzers.CodeFixes/build/linq2db.Analyzers.targets` (packed to `build` and `buildTransitive`) defines target `LinqToDBRemoveAnalyzers`, which runs after `ResolveLockFileAnalyzers` when `EnableLinqToDBAnalyzers=false` and removes `Analyzer` items whose `NuGetPackageId` is `linq2db.Analyzers`. `ExcludeAssets=analyzers` on the consumer reference does not work (the SDK hands analyzers to csc anyway).
- Release tracking: `AnalyzerReleases.Shipped.md` -- 6.4.0 added L2DB1001, 6.5.0 added L2DB1002..1004. All Info severity, category `LinqToDB`, help link `https://github.com/linq2db/linq2db/wiki/<id>`.

### L2DB1001 -- legacy window-function API
`WindowFunctionApiAnalyzer` (`Source/LinqToDB.Analyzers/WindowFunctionApiAnalyzer.cs:17`). Registers on `OperationKind.Invocation` after resolving `LinqToDB.AnalyticFunctions`. Gate: method named `ToValue` whose containing type is nested in `AnalyticFunctions`, then `GetRootFunction` walks the fluent receiver chain (invocations and property references) back to the `Sql.Ext.<Fn>` root and reports only if the chain contained `.Over()` (a plain aggregate such as `Sum(x).ToValue()` is not a window function). Message names the root function. See [wiki](../../github/wiki/L2DB1001.md).

Code fix: `WindowFunctionApiCodeFixProvider` (`Source/LinqToDB.Analyzers.CodeFixes/WindowFunctionApiCodeFixProvider.cs:24`), title "Convert to Sql.Window API", delegates to `LegacyWindowChainRewriter.TryRewrite`. Custom `WindowChainFixAllProvider` (a `DocumentBasedFixAllProvider`) rewrites all chains in one `ReplaceNodes` pass because `BatchFixer` drops edits for physically adjacent diagnostics. Option `linq2db.l2db1001.apply_fix_on_return_type_mismatch` (default off) applies the rewrite even if the `Sql.Window` return type diverges from the legacy slot.

`LegacyWindowChainRewriter` (`Source/LinqToDB.Analyzers.CodeFixes/LegacyWindowChainRewriter.cs:21`): syntax-level rewrite mirroring the internal `LegacyMemberConverterBase.TryConvertAnalyticFunction`. Function families: frameable, keepable (Oracle KEEP), partition-only (`Median`, `RatioToReport`), windowed ordered-set (`PercentileCont/Disc`). Bails (diagnostic stays, no fix) on `Filter`, `ListAgg`, unknown functions, DISTINCT with KEEP, non-constant modifiers, a bare `Ext.<Fn>` root (no `<Sql>.Ext` qualifier), absent `LinqToDB.WindowFunctionBuilder`, or a return type that does not fit the target slot (speculative binding in `ReturnTypeFitsTarget`). User argument expressions are kept verbatim via placeholder identifiers spliced back after `NormalizeWhitespace`.

Fixture-proven behaviours (`WindowFunctionApiCodeFixTests`, about 45 cases, plus 5 analyzer cases in `WindowFunctionApiAnalyzerTests`): families covered are ranking (`RowNumber/Rank/DenseRank`), aggregates (`Sum`, `Count`, `Min/Max` with `KeepFirst/KeepLast`), offsets (`Lag/Lead`), value functions (`FirstValue`, `NthValue` with `From.First/Last` and `Nulls.Ignore/Respect` mapped to `FromFirst/FromLast/IgnoreNulls/RespectNulls`), statistical (`StdDev`, bivariate `CovarPop`/`RegrSlope`), `NTile`, `Median`, `RatioToReport`, windowed `PercentileCont/Disc`. Frames: `Range/Rows.Between...And` becomes `RangeBetween/RowsBetween.Unbounded.And.CurrentRow`, value boundaries (`ValuePreceding(3)`) splice user args, and a single-boundary frame (`.Rows.UnboundedPreceding`) normalizes to the two-boundary form. Named arguments written out of order (`Lag`, `NthValue`, `Count(modifier:, expr:)`) are re-ordered by parameter ordinal. A `Sql.AggregateModifier` passed through a const alias is resolved by constant value (`.Distinct()` kept), a non-constant modifier withholds the fix. Trivia: leading and argument comments are kept, a comment on chain scaffolding (e.g. inside `.Over(/* keep */)`) is salvaged as trailing trivia, and a single-line comment is line-terminated so the statement terminator is not swallowed. Return-type gate: `Median` into `int?`, `NTile` into `int` (and into `var` or an anonymous-object member, where the inferred type would widen int to long) withhold the fix, `NTile` into `long` and `RowNumber` into `var` are fixed, and the `apply_fix_on_return_type_mismatch = true` editorconfig option bypasses the gate. Not reported at all: plain aggregates without `.Over()`, group-form `PercentileCont` (WITHIN GROUP without OVER), the new `Sql.Window` API, and an unrelated `ToValue()` outside `AnalyticFunctions`. Reported but not fixed: `using static LinqToDB.Sql` bare `Ext.` root, DISTINCT+KEEP, windowed `ListAgg`, `Filter(...)` chains. Chains inside `Select` lambdas convert, and Fix-All converts three clustered chains in one initializer.

### L2DB1002 -- unsatisfiable duration comparison
`DurationComparisonAnalyzer` (`Source/LinqToDB.Analyzers/DurationComparisonAnalyzer.cs:19`). Operation kind `Binary`, `==`/`!=` between `TimeSpan` operands, one a member read off the query range variable (`IsOnRangeVariable`) carrying `[Duration(DurationUnit.X)]` (derived attributes and base-property overrides honoured, all declarations collected, one without `Configuration` required as fallback), inside an `Expression<T>` lambda (`IsInsideExpressionTree`). The other side is folded to `Candidate`s (exact, .NET Framework whole-millisecond rounding, modern truncation) from constructors, `From*`/`Parse`/`ParseExact`, `Zero/Min/MaxValue`, `+`/`-`/unary minus, single-assignment locals, array-literal loops and range variables of a trusted set of LINQ operators (`IsElementSelector`). Reports only when no reading and no declared unit can represent the value, and anything unrecognised degrades to silence. Message variants: "can never match" (`==`), "always matches" or "excludes no row that has a value" (`!=`, nullable-aware). Only attribute-declared units are visible (not `HasDuration` or mapping-schema). `_netFxRoundingPossible` depends on absence of `TimeSpan.FromMicroseconds` and `System.Half`. See [wiki](../../github/wiki/L2DB1002.md). No code fix.

Fixture-proven behaviours (`DurationComparisonAnalyzerTests`, about 75 cases, snippets share a `Row` model with one member per `DurationUnit` plus a nullable `Grace`, a field and an undeclared member):
- Positives: fractional seconds on a second column, `!=` ("always matches", nullable variant "excludes no row that has a value"), mirrored operand order, `TimeSpan` ctor arities 1/3/4/6 (the 6-arg microsecond slot), `FromTicks`, `Parse`/`ParseExact`, `Min/MaxValue`, `+`/`-`/negation, `FromMicroseconds`, fields, single-assignment locals, `foreach` over array literals (qualified wording "...when that value is compared" when only some elements fail, closing the operator x nullability x mixed matrix), range variables, `Expression<Func<>>` locals and return positions, nested non-expression lambdas (every enclosing lambda checked), named `Unit =` overriding the ctor argument, and base-declared `[Duration]` on an override.
- Paired negatives pin the unit table ratios (microsecond 20 vs 15 ticks, day 48h vs 36h) and each fold: ordering operators, `Tick` and `Nanosecond` units, undeclared member, `ParseExact` with `TimeSpanStyles`, non-constant operand, captured instance member, in-memory `Where`, plain statements, null constant, `Zero`.
- Collection and flow refusals: `foreach` over collection expressions (Roslyn 4.8 has no `CollectionExpression` operation, characterization test), `List<T>` initializers, method calls, arrays written through an element, locals written through a `ref` alias or by deconstruction, two-parameter lambdas (`Zip`), `SelectMany` result selectors and `Join` inner key selectors (operator allowlist plus single-parameter rule).
- Declaration handling: `Configuration`-scoped-only declarations are silent, a derived attribute assigning `Configuration` in its constructor is silent, disagreeing declared units are silent (also across an override), a derived attribute with a visible unit reports, one with a hard-coded unit or an unrelated int argument is silent.
- Target-framework variants via `VerifyWithoutLinqToDBAsync` and self-declared `LinqToDB.Mapping` anchors: Net60 reports the sub-millisecond double factory (Half rules out .NET Framework), NetStandard20 stays silent (could be .NET Framework, 0.5ms rounds to 1ms), Net90 component factories (`FromSeconds(1, 500, 0)`, `FromMilliseconds(1500, 0)`, all components written because optional args are CS0854 in expression trees) report and the representable twin does not. A linq2db-free compilation is silent without throwing.

### L2DB1003 / L2DB1004 -- server-side-only stub contract
`ServerSideOnlyContractAnalyzer` (`Source/LinqToDB.Analyzers/ServerSideOnlyContractAnalyzer.cs:18`) registers an operation-block action. Detection core is `ServerSideOnlyContract` (`Source/LinqToDB.Analyzers/ServerSideOnlyContract.cs:22`), an internal static class that is `Compile Include`-linked into `Source/CodeGenerators` so the internal `LINQ2DB0002`/`LINQ2DB0003` twins and the shipped `L2DB1003`/`L2DB1004` decide identical cases (see [CODEGEN](../CODEGEN/INDEX.md)). It must stay Roslyn 4.8-compatible, with no `ImmutableArray` collection expressions and nested helper types.
- Stub = ordinary method, explicit interface impl, or non-indexer property getter whose whole body is one `throw new X(...)` (`TryGetStub`, `GetStubThrownType`).
- Declared server-side-only (`DeclaresServerSideOnly`): `[ServerSideOnly]`, a `Sql.ExpressionAttribute` derivative with effective `ServerSideOnly` (every `Sql.Extension` ctor sets it), `Sql.TableFunction`, or `[ExpressionMethod]`. The walk covers base overrides and implemented interface members.
- `Classify`: declared + exception not in allowed set gives `WrongStubException` (L2DB1004). Not declared + (marker-capable `Sql.Expression` attribute present, or thrown type in the unmarked set) gives `MissingMarker` (L2DB1003).
- `.editorconfig` options, additive to the `ServerSideOnlyException` default: `linq2db.l2db1003.unmarked_stub_exception_types`, `linq2db.l2db1004.allowed_exception_types`.
- Diagnostic `Properties["remedy"]` is `add-attribute`, `set-named-argument` or `replace-exception`. `AdditionalLocations` carry the attribute or interface-member declarations to edit. An unwritable interface target (metadata-only) withholds the remedy so the fix declines.

Fixture-proven analyzer behaviours (`ServerSideOnlyContractAnalyzerTests`, about 30 cases): expression-bodied and block-bodied stubs both reported (Roslyn models them differently), switch-arm throws and setter-only or constructor throws are ignored. Arm B (no marker-capable attribute): only `ServerSideOnlyException`-style throws report, `NotImplementedException` placeholders stay silent. Arm A (marker-capable attribute with `ServerSideOnly` unset or `= false`) reports `MissingMarker` with the attribute as fix target (`WithLocation(1)`), including `Sql.Extension(ServerSideOnly = false)`, the one input that pins explicit-argument-before-ctor-default order. Marker forms silent with the right exception: bare `Sql.Extension` (ctor default true), `Sql.TableExpression` (unconditional via `TableFunction`), `[ServerSideOnly]`, `Sql.Function(ServerSideOnly = true)`, `[ExpressionMethod]`. Wrong exception in a marked stub reports L2DB1004 for `[ServerSideOnly]`, `[ExpressionMethod]`, bare `Sql.Extension` and `Sql.TableExpression`. Interface and base walk: a marker on the interface or on a base virtual silences the implementation or override (explicit implementations included, whose symbol name is dotted `I.M`), an unmarked interface reports with the interface member declaration as the additional location. Generated code (`<auto-generated/>`) is silent because the shipped host uses `GeneratedCodeAnalysisFlags.None` (deliberately the opposite of the internal host). Options: both lists are additive, the L2DB1004 list does not widen L2DB1003 arm B, matching is exact type (no subclass match), unresolvable entries degrade to the default.

Code fix: `ServerSideOnlyContractCodeFixProvider` (`Source/LinqToDB.Analyzers.CodeFixes/ServerSideOnlyContractCodeFixProvider.cs:34`) reads the remedy rather than re-deriving it. Add-marker can edit several documents (one per implemented interface member), so it is a solution-level action. Replace-exception qualifies `nameof(I.M)` for explicit implementations. Output is fully qualified then `Simplifier`/`Formatter` post-processed. `ContractFixAllProvider` is a solution-scoped `FixAllProvider` (Document/Project/Solution scopes, grouped per document, one `ReplaceNodes` per document). The "implement the body" remedy is never auto-applied.

Fixture-proven fix behaviours (`ServerSideOnlyContractCodeFixTests`, about 20 cases): add `[ServerSideOnly]` when no attribute exists (doc comments and trailing comments on an existing attribute preserved, new attribute inserted above), set `ServerSideOnly = true` on an existing `Sql.Function` and update an existing `= false` in place (a second argument would be CS0643), replace the thrown exception in expression- and block-bodied stubs, the getter (not a setter declared first) of a property, and expression-bodied properties. Interface targets: marker added or argument set on the interface member in the same file or in another file (`RunMultiFile`, both lightbulb and Fix-All arms verified), every implemented interface (`IA` and `IB`) marked, metadata-declared interfaces (`IComparable<int>`) make the fix decline with source unchanged. Explicit implementations (method, generic interface, property) emit `nameof(I.M)` / `nameof(IFoo<int>.M)` qualified. Fix-All converts four adjacent L2DB1004 stubs (the `BatchFixer` under-application shape).

Harness notes (code-fix fixtures): `TabIndent` editorconfig, CRLF normalised to LF on both sides, multi-file sources rooted at `/0/` so the editorconfig applies, `CodeFixTestBehaviors.SkipLocalDiagnosticCheck` for property cases (the SDK is stricter than the product there).

### Tests (`Tests/Tests.Analyzers`)
DB-free Roslyn testing-SDK fixtures against `ReferenceAssemblies.Net.Net80` plus the real linq2db assembly. `AnalyzerVerifier<TAnalyzer>` (has `VerifyWithoutLinqToDBAsync` overloads proving capability gates stay silent) and `CodeFixVerifier<TAnalyzer,TCodeFix>` (single- and multi-document, `CodeFixTestBehaviors` such as `SkipLocalDiagnosticCheck` for property diagnostics) wrap the SDK. Fixtures: `WindowFunctionApiAnalyzerTests`, `WindowFunctionApiCodeFixTests`, `DurationComparisonAnalyzerTests`, `ServerSideOnlyContractAnalyzerTests`, `ServerSideOnlyContractCodeFixTests` (about 370 test/class declarations by regex count). The project hosts a bare NUnit MTP runner, so do not pass `--test-progress` (see agent-rules, Running tests). All five fixtures were read in full in the coverage-fill run, see the per-rule "Fixture-proven" paragraphs above for what they pin. Style: raw-string C# snippets with `{|#n:...|}` or `{|L2DB100x:...|}` markers, one behaviour per test, and "paired" negative/positive tests that differ in one factor (value, reference set, collection kind).

## Key types
| Type | File | Role |
|---|---|---|
| `WindowFunctionApiAnalyzer` | `Source/LinqToDB.Analyzers/WindowFunctionApiAnalyzer.cs` | L2DB1001 |
| `DurationComparisonAnalyzer` | `Source/LinqToDB.Analyzers/DurationComparisonAnalyzer.cs` | L2DB1002, nested `Candidate`, `DeclaredUnits`, `CompilationAnalyzer` |
| `ServerSideOnlyContractAnalyzer` | `Source/LinqToDB.Analyzers/ServerSideOnlyContractAnalyzer.cs` | L2DB1003/1004 host, option reads |
| `ServerSideOnlyContract` | `Source/LinqToDB.Analyzers/ServerSideOnlyContract.cs` | shared detection core, linked into CODEGEN |
| `WindowFunctionApiCodeFixProvider`, `LegacyWindowChainRewriter` | `Source/LinqToDB.Analyzers.CodeFixes/` | L2DB1001 fix |
| `ServerSideOnlyContractCodeFixProvider` | `Source/LinqToDB.Analyzers.CodeFixes/` | L2DB1003/1004 fix, `ContractFixAllProvider` |

## Files (Tier 1 / Tier 2)
Tier 1 (7, all read in full): `LinqToDB.Analyzers.csproj`, `AnalyzerReleases.Shipped.md`, `ServerSideOnlyContractAnalyzer.cs`, `WindowFunctionApiAnalyzer.cs`, `DurationComparisonAnalyzer.cs`, `LinqToDB.Analyzers.CodeFixes.csproj`, `build/linq2db.Analyzers.targets`.

Tier 2 (11 `*.cs`, 11 read): `ServerSideOnlyContract.cs`, `WindowFunctionApiCodeFixProvider.cs`, `LegacyWindowChainRewriter.cs`, `ServerSideOnlyContractCodeFixProvider.cs`, `AnalyzerVerifier.cs`, `CodeFixVerifier.cs` read in the build run. The five fixture files in `Tests/Tests.Analyzers` (`WindowFunctionApiAnalyzerTests.cs`, `WindowFunctionApiCodeFixTests.cs`, `DurationComparisonAnalyzerTests.cs`, `ServerSideOnlyContractAnalyzerTests.cs`, `ServerSideOnlyContractCodeFixTests.cs`) read in the coverage-fill run. `Source/Analyzers.Common.props` also read (not a `.cs`).

## Inbound / outbound dependencies
- Inbound: `Source/LinqToDB/LinqToDB.csproj` references the package (rules ship with linq2db). `Source/CodeGenerators` links `ServerSideOnlyContract.cs`.
- Outbound: Roslyn 4.8 (`Microsoft.CodeAnalysis.CSharp`, `.Workspaces` for fixes). Name-only coupling to linq2db types: `LinqToDB.AnalyticFunctions`, `LinqToDB.WindowFunctionBuilder`, `LinqToDB.Mapping.DurationAttribute/DurationUnit`, `LinqToDB.ServerSideOnlyException`, `LinqToDB.Mapping.ServerSideOnlyAttribute`, `Sql+ExpressionAttribute/ExtensionAttribute/TableFunctionAttribute`, `LinqToDB.ExpressionMethodAttribute`. The duration unit table mirrors `SqlIntervalUnits.TryGetTicksRatio`.

## Known issues / debt
- L2DB1002 cannot see units set via `HasDuration` or a mapping schema, and cannot detect a derived attribute assigning `Configuration` in its constructor body (documented in source, pinned silent by `DoesNotReportDerivedAttributeThatScopesItselfToAConfiguration`).
- L2DB1002 cannot read collection expressions (`[..]`) on the Roslyn 4.8 pin (pinned by a characterization test that should go red when the pin is raised).
- The L2DB1001 fix declines many shapes (Filter, ListAgg, bare `Ext` root), leaving the diagnostic without a fix.
- The detection core is pinned to Roslyn 4.8 because of the CODEGEN link (CodeGenerators uses 5.6.0).
- Tier-2 coverage is now complete: the five fixture files were read in the coverage-fill run, replacing the earlier inference from names and counts.

## See also
[CODEGEN](../CODEGEN/INDEX.md), [architecture overview](../../architecture/overview.md), wiki pages above.

<details><summary>Coverage</summary>

- Tier 1: 7/7 read in full.
- Tier 2: 6/11 `*.cs` read: ServerSideOnlyContract.cs, WindowFunctionApiCodeFixProvider.cs, LegacyWindowChainRewriter.cs, ServerSideOnlyContractCodeFixProvider.cs, AnalyzerVerifier.cs, CodeFixVerifier.cs.
- Skipped (budget, queued): WindowFunctionApiAnalyzerTests.cs, WindowFunctionApiCodeFixTests.cs, DurationComparisonAnalyzerTests.cs, ServerSideOnlyContractAnalyzerTests.cs, ServerSideOnlyContractCodeFixTests.cs.
- Also read: Source/Analyzers.Common.props, wiki L2DB1002 (head).
- Tier 3: none.

Read (this run):
- Tests/Tests.Analyzers/WindowFunctionApiAnalyzerTests.cs
- Tests/Tests.Analyzers/WindowFunctionApiCodeFixTests.cs
- Tests/Tests.Analyzers/DurationComparisonAnalyzerTests.cs
- Tests/Tests.Analyzers/ServerSideOnlyContractAnalyzerTests.cs
- Tests/Tests.Analyzers/ServerSideOnlyContractCodeFixTests.cs

Net effect: Tier 2 is 11/11 after this run (the "Skipped (budget, queued)" bullet above is the prior-run state and is now cleared).
</details>
