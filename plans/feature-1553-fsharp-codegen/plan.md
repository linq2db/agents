# Work plan: feature-1553-fsharp-codegen — Language capability flags instead of F# identity checks

**Tier:** L  ·  **Status:** approved  ·  **Approved-at:** 2026-10-11 (E-1..E-16, after critic round 2 `holds`)  ·  **Branch:** feature/1553-fsharp-codegen
**Schema:** `.claude/docs/work-plan.md`  ·  **Gates:** `.claude/docs/definition-of-done.md`

Scope note: this plan covers one late addition to PR #5707 (out-of-scope review item 1, user decision 2026-10-11:
"introduce capability members on `ILanguageProvider` in this PR", shape = one `[Flags]` enum + one interface property,
breaking interface addition accepted for 6.6.0, CLI forced settings derived from capabilities). The rest of the
branch (the F# scaffolder itself) predates this plan and is not described here.

## P1 Problem

The data-model generator decides F#-specific AST shapes by object identity with the built-in F# provider, not by any
property of the provider: 9 sites spell `ReferenceEquals(<provider>, LanguageProviders.FSharp)`
(`DataModelGenerator.cs:92`, `DataModelGenerator.Schemas.cs:42`, `DataModelGenerator.Entities.cs:50` and `:155`,
`DataModelGenerator.DataContext.cs:135`, `DataModelGenerator.Functions.Procedures.cs:375`, `:480`, `:681`,
`CodeModel/Visitors/ImportsCollector.cs:58`). Observable consequence: any `ILanguageProvider` other than the singleton
`LanguageProviders.FSharp` instance — e.g. a provider that delegates every member to the F# one — gets the C# AST
shapes (no records, `this.Equals` recursion shape, no option unwrapping, no explicit `QueryProc<T>`), which the F#
renderer cannot render correctly.

Second, the settings F# output requires are forced only in the CLI (`ScaffoldCommand.Execute.cs:72-93`, a
`language == LanguageProviders.FSharp` block). A library caller of `new Scaffolder(LanguageProviders.FSharp, …,
ScaffoldOptions.Default(), …)` gets silently broken F#: one file per class with a `namespace rec` each
(`ClassPerFile` default true), TAB indentation (FS1161), `static do this.StaticInitDataContext()` when the static
init method is enabled, and the data context's typed-options/configuration constructors silently dropped (only the
first constructor becomes the primary one, `FSharpCodeGenerator.cs:873-887`). `Tests/Linq/Scaffold/FSharpCodeGenerationTests.cs:115-133`
`FSharpOptions()` hand-copies the CLI list to work around it. The CLI also only replaces an indent that is exactly
`"\t"` (`Execute.cs:77`), so `--indent "\t\t"` still emits tabs.

## P2 Success criteria

- SC-1 A provider that delegates every `ILanguageProvider` member (including the new `Features`) to `LanguageProviders.FSharp` produces byte-identical generated code to `LanguageProviders.FSharp` itself, over the SqlServer test DB and over SQLite with fluent metadata. → TO-1a, TO-1b
- SC-2 No `ReferenceEquals(…, LanguageProviders.FSharp)` / `LanguageProviders.CSharp` identity check remains in `Source/LinqToDB.Scaffold`; the CLI's forced-settings block is gone. → TO-6
- SC-3 A library caller using `Scaffolder` with `LanguageProviders.FSharp` and un-adjusted `ScaffoldOptions.Default()` gets one file, no TAB characters in indentation, and the single typed-options primary constructor. → TO-2
- SC-4 An indent containing tabs other than exactly `"\t"` is converted for F# too. → TO-3
- SC-5 Generated code is unchanged for every existing input: F# goldens and C# CLI baselines regenerate with no diff. → TO-4, TO-5
- SC-6 The two built-in providers report the intended feature sets. → TO-7

## P3 Constraints & anti-goals

- Generated output for both languages must not change (SC-5). This is a refactoring of how decisions are made, not of
  what is generated.
- CLI option gating by `TargetLanguages` (`ScaffoldCommand.Execute.cs:50-64`, the per-option `Languages` property,
  help output `HelpCommand.cs:312-318`) stays per-language — explicitly out of scope by user decision.
- The CLI's F#-vs-T4 rejection (`Execute.cs:42-47`) and target-language selection (`Execute.cs:39`) stay.
- Renderer-internal language logic inside `FSharpCodeGenerator` / `CSharpCodeGenerator` stays (it is already
  language-specific by construction).
- No change to `CompatibilitySuppressions.xml` by hand; `PublicAPI.Unshipped.txt` gets the new entries.
- Not in scope: `WellKnownTypes.cs:28` parsing well-known types with the C# parser; the LINQPad driver's hard-coded
  `LanguageProviders.CSharp` (`DynamicSchemaGenerator.cs:145`); direct `DataModelLoader`/`DataModelGenerator` callers
  that bypass `Scaffolder` (see P10).

## P4 Unknowns

- U-1 Can anyone outside the assembly implement `ILanguageProvider` today (i.e. is the interface addition actually breaking for someone)? — resolved-by scout: no. `ASTBuilder` returns `CodeBuilder`, a `public sealed` class with an `internal` ctor (`CodeModel/Builders/CodeBuilder.cs:9,13`), and `TypeParser` is `internal sealed` (`CodeModel/Types/Parser/TypeParser.cs:8`), so an external type can only implement it by delegating to a built-in provider. Only implementers: `CSharpLanguageProvider.cs:10`, `FSharpLanguageProvider.cs:10`, both `internal sealed` singletons. No test doubles anywhere in Source/Tests/Examples (searched `ILanguageProvider`).
- U-2 Is the delegating-provider test (TO-1) able to fail for the right reason before the change? — resolved-by reasoning, to be confirmed by probe at implementation (TO-1 red run): `Scaffolder` passes its `Language` (the wrapper) to `DataModelLoader`/`DataModelGenerator`/`ImportsCollector`, so every identity check sees the wrapper and takes the C# arm; the F# renderer comes from the wrapped provider's `GetCodeGenerator`, so output differs (or the renderer throws on a C# shape). Either is the right reason (provider not recognised as F#); an unrelated failure (wrapper construction, schema load) is not and would void the red.
- U-3 Which existing goldens exercise each identity-check site, so characterization (TO-4) actually covers it? — resolved-by measured grep over `Tests/FSharp.Scaffold/SqlServer/TestDataDB.fs`: `module` 1 (schema wrapper), `QueryProc<` 16, `QueryProcAsync<` 16, `: List<` 16 (async result `Result` property, line 1495), `interface IEquatable` 28, `Option.toNullable` 90, `Option.ofNullable` 28, `Func<DbDataReader` 8, `InitSchemas` 0; and `Unchecked.nonNull(options` appears only in `SQLiteFluent`, `PostgreSQL`, `NoNrt/PostgreSQL` goldens (1 each). Records: every golden. So SqlServer + SQLiteFluent cover all 9 sites.
- U-4 Do any forced settings have a user-settable CLI option for F#, i.e. does moving the forcing into the library change CLI behaviour? — resolved-by scout: all forced settings except `Indent` map to options marked `Languages = TargetLanguages.CSharp` (`ScaffoldCommand.Options.cs:318,535,681,696,711,726,741,756,846`), so the CLI rejects them for F# before forcing; only 5 values actually change from `ScaffoldOptions.Default()` (`ClassPerFile`, `Indent`, `GenerateInitDataContextMethod`, `HasDefaultConstructor`, `HasConfigurationConstructor`). `--indent` is open to F# and is where SC-4 changes CLI behaviour (tabs beyond exact `"\t"` now converted). Second CLI-visible change (critic round 1): a user interceptor's `ctor(ScaffoldOptions)` now sees un-forced values and cannot override the derivation — see D-3.
- U-5 Does mutating the caller's `ScaffoldOptions` inside `Scaffolder` affect a caller that reuses one options object across languages? — resolved-by scout (callers): CLI builds a fresh settings object per run (`ScaffoldCommand.Configuration.cs:30`); LINQPad is C#-only; tests build per test. A reusing library caller would see the F# adjustments persist; documented on the `options` parameter (D-3).

## P5 Decisions

### D-1 — Capability shape: `[Flags] public enum LanguageFeatures` + `LanguageFeatures ILanguageProvider.Features { get; }`

- **chosen:** one flags enum in `LinqToDB.CodeModel` (`CodeModel/Languages/LanguageFeatures.cs`), hex literals and
  `None = 0` per the `Modifiers`/`FindTypes` convention (`Modifiers.cs`), one new interface property. Flags name what
  the target language **and its code generator** support, so C# carries most flags and F# lacks them; two flags
  describe generation choices only F# makes.
- **rejected:** one `bool` per capability (like `NRTSupported`) — every future capability re-breaks the interface (user
  decision). Internal capability interface — leaves a delegating provider on the C# path, i.e. does not fix P1 (user
  decision).
- **why this:** single interface break now; later capabilities are additive enum members.
- **failure mode of the choice:** a flag named as a pure *language* feature when it is really a *generator* limitation
  (e.g. F# has secondary constructors but our F# generator does not emit them) misleads a reader; mitigated by the
  enum's summary stating both and per-flag docs naming which.

### D-2 — Flag set (one flag per distinct decision; C# = all "language has" flags, F# = the two generation flags)

| Flag | Value | Set for | Consumer site(s) |
|---|---|---|---|
| `NestedTypes` | 0x0001 | C# | `DataModelGenerator.Schemas.cs:42` (absent → schema wrapper `Modifiers.Module`) |
| `NullableFlowAnalysis` | 0x0002 | C# | `DataModelGenerator.DataContext.cs:135` (absent → `SuppressNull` on re-accessed schema) |
| `LambdaReturnTypeInference` | 0x0004 | C# | `DataModelGenerator.Functions.Procedures.cs:375` (absent → explicit `QueryProc<T>`) |
| `ImplicitUpcast` | 0x0008 | C# | `…Procedures.cs:480` (absent → async result property typed `List<T>`) |
| `ImplicitInterfaceImplementation` | 0x0010 | C# | `DataModelGenerator.Entities.cs:155` (absent → `object.Equals` calls the comparer) |
| `ImplicitDelegateConversion` | 0x0020 | C# | `ImportsCollector.cs:58` (absent → collect lambda `TargetType` imports) |
| `ConstructorPropertyInitialization` | 0x0040 | C# | `DataModelGenerator.cs:92` (absent → computed schema properties, no `InitSchemas`) |
| `PartialTypes` | 0x0080 | C# | settings: `EntityClassIsPartial` |
| `PartialMethods` | 0x0100 | C# | settings: `GenerateInitDataContextMethod`, `GenerateStaticInitDataContextMethod` |
| `MultipleConstructors` | 0x0200 | C# | settings: constructor flags → only `HasTypedOptionsConstructor` |
| `TabIndentation` | 0x0400 | C# | settings: `Indent` (tabs → 4 spaces each) |
| `MultipleFiles` | 0x0800 | C# | settings: `ClassPerFile` |
| `RecordEntities` | 0x1000 | F# | `DataModelGenerator.Entities.cs:50` (`Modifiers.Record`); settings: `GenerateAssociationExtensions` off |
| `OptionTypes` | 0x2000 | F# | `…Procedures.cs:681` `GetFSharpOptionMethod` (nullable scalars as `option`) |

- **chosen:** the table above. `GenerateAssociationExtensions` is tied to `RecordEntities` because the extension
  member would share the association record field's name (scout: `DataModelLoader.Entities.cs:275-288`, F# callers
  resolve the field).
- **rejected:** a single `FSharpStyle`-like flag — that is the identity check renamed; deriving `MultipleFiles` from
  something else — F# order-dependent compilation is its own constraint.
- **why this:** each flag maps 1:1 to one AST or settings decision, so a future language picks per decision.
- **failure mode of the choice:** two sites tied to one flag can diverge later (`PartialMethods` covers two settings;
  `RecordEntities` covers a site and a setting) — acceptable, they share the same root cause today.

### D-3 — Where the forced settings live: applied inside `Scaffolder`'s constructor from `Language.Features`

- **chosen:** an internal static helper (e.g. `ScaffoldOptions` adjustment in `Scaffold/Scaffolder.cs` or a new
  internal `LanguageFeaturesExtensions`) called from the `Scaffolder` constructor, mutating the passed options per the
  D-2 settings rows; CLI block `ScaffoldCommand.Execute.cs:71-94` deleted (the CLI always goes through `Scaffolder`,
  `Execute.cs:193`). `FSharpCodeGenerationTests.FSharpOptions()` drops the copies (keeps `ContextClassName`,
  `GenerateIEquatable`, which the CLI never forced).
- **rejected:** keep the block in the CLI but key it on `Features` — fixes the identity check but leaves library callers
  broken (P1 second half). Fail-fast in `Scaffolder` on incompatible settings — every caller (CLI included) would have
  to replicate the derivation. A public `ScaffoldOptions.ApplyLanguageFeatures(...)` helper — extra public surface for
  no caller that needs it.
- **why this:** one derivation, reached by every `Scaffolder` caller.
- **failure mode of the choice:** silently mutates a caller-owned object (U-5); documented on the `options` param.
  Callers that bypass `Scaffolder` (public `DataModelLoader`/`DataModelGenerator` ctors) still get no adjustment (P10).
- **interceptor ordering (critic round 1):** the CLI hands `settings` to a user interceptor's `ctor(ScaffoldOptions)`
  (`ScaffoldCommand.Execute.cs:157` → `ScaffoldCommand.Interceptors.cs:197-205`) before `new Scaffolder`
  (`Execute.cs:193`). Decision: `Scaffolder` owns the derivation — an interceptor sees raw values and cannot re-enable
  a setting the language cannot render (each such value produces broken or silently-degraded F#, P1). F# is
  unreleased, so no shipped interceptor depends on seeing the forced values.

### D-4 — Consumers read `context.LanguageProvider.Features` directly

- **chosen:** `context.LanguageProvider.Features.HasFlag(...)` (or a small internal `Has` extension) at each site.
- **rejected:** copy flags onto `DatabaseModel` at load time like `NRTEnabled`/`DisableXmlDocWarnings`
  (`DataModelLoader.cs:68-69`) — those combine a capability with a *user option*; these have no user option, so a
  model copy adds state without combining anything.
- **why this:** no new model state; the provider is already in every context.
- **failure mode of the choice:** none beyond the HasFlag boxing cost on netstandard2.0 (negligible, generation-time).

## P6 Edit-points

- E-1 `Source/LinqToDB.Scaffold/CodeModel/Languages/LanguageFeatures.cs` (new) — the flags enum with XML docs.
- E-2 `Source/LinqToDB.Scaffold/CodeModel/Languages/ILanguageProvider.cs:ILanguageProvider` — `Features` property.
- E-3 `Source/LinqToDB.Scaffold/CodeModel/Languages/CSharp/CSharpLanguageProvider.cs` — C# feature set.
- E-4 `Source/LinqToDB.Scaffold/CodeModel/Languages/FSharp/FSharpLanguageProvider.cs` — F# feature set.
- E-5 `Source/LinqToDB.Scaffold/DataModel/DataModelGenerator.cs:BuildDataContext` — `ConstructorPropertyInitialization`.
- E-6 `Source/LinqToDB.Scaffold/DataModel/DataModelGenerator.Schemas.cs` — `NestedTypes`.
- E-7 `Source/LinqToDB.Scaffold/DataModel/DataModelGenerator.Entities.cs:BuildEntity,BuildEntityIEquatable` — `RecordEntities`, `ImplicitInterfaceImplementation`.
- E-8 `Source/LinqToDB.Scaffold/DataModel/DataModelGenerator.DataContext.cs` — `NullableFlowAnalysis`.
- E-9 `Source/LinqToDB.Scaffold/DataModel/DataModelGenerator.Functions.Procedures.cs` — `LambdaReturnTypeInference`, `ImplicitUpcast`, `OptionTypes`.
- E-10 `Source/LinqToDB.Scaffold/CodeModel/Visitors/ImportsCollector.cs` — `ImplicitDelegateConversion`.
- E-11 `Source/LinqToDB.Scaffold/Scaffold/Scaffolder.cs:Scaffolder` — apply settings rows of D-2 (+ helper; may be a new internal file under `Source/LinqToDB.Scaffold/Scaffold/`).
- E-12 `Source/LinqToDB.CLI/CommandLine/Commands/Scaffold/ScaffoldCommand.Execute.cs` — delete forced-settings block.
- E-13 `Source/LinqToDB.Scaffold/PublicAPI/PublicAPI.Unshipped.txt` — `LanguageFeatures` type + members, `ILanguageProvider.Features.get`, and the missing `Modifiers.Module = 32768` line (scout: absent from every PublicAPI file).
- E-14 `Tests/Linq/Scaffold/FSharpCodeGenerationTests.cs` — TO-1a/1b/2/3/7 tests, delegating provider, trimmed `FSharpOptions()`.
- E-15 `Source/LinqToDB.CLI/readme.md` / `Tests/FSharp.Scaffold/generate.ps1` comments — only if they describe the CLI-side forcing (verify at implementation; edit only stale prose).
- E-16 `Source/LinqToDB.Scaffold/CompatibilitySuppressions.xml` — regenerated via `/api-baselines` (never by hand) for the `CP0006` on `P:LinqToDB.CodeModel.ILanguageProvider.Features` the interface addition raises on every TFM.

## P7 Impact map

- `ILanguageProvider` implementers: `CSharpLanguageProvider.cs:10`, `FSharpLanguageProvider.cs:10` — covered by E-3, E-4. Searched `ILanguageProvider` across Source/Tests/Examples incl. `.tt/.ttinclude/.linq/.fs`: no other implementers.
- Identity-check sites (searched `LanguageProviders\.(FSharp|CSharp)`, `isFSharp`, `fsharp` in Scaffold/CLI/LINQPad/Templates): - `DataModelGenerator.cs:92` (+ uses :102, :126) — covered by E-5 - `DataModelGenerator.Schemas.cs:42` — covered by E-6 - `DataModelGenerator.Entities.cs:50`, `:155` — covered by E-7 - `DataModelGenerator.DataContext.cs:135` — covered by E-8 - `DataModelGenerator.Functions.Procedures.cs:375`, `:480`, `:681` (callers :643/:556, :657/:351/:619 inherit) — covered by E-9 - `ImportsCollector.cs:58` — covered by E-10 - `ScaffoldCommand.Execute.cs:39` (selection), `:42` (T4 rejection), `:50` (option gating) — out-of-scope (P3) - `ScaffoldCommand.Execute.cs:72` (forced settings) — covered by E-11, E-12
- Copies of the forced-settings list: `Tests/Linq/Scaffold/FSharpCodeGenerationTests.cs:115-133` — covered by E-14; LINQPad `DynamicSchemaGenerator.cs:97-123` sets a similar subset for its own C# reasons — out-of-scope (C# provider: D-2 settings rows are no-ops for C#, which has every "language has" flag).
- Settings consumers whose input changes for F# library callers: `ClassPerFile` (`DataModelLoader.Entities.cs:62`, `DataModelLoader.Functions.cs:366`), `Indent` (`Scaffolder.cs:150-160` → `GetCodeGenerator`), constructor flags (`DataModelGenerator.DataContext.cs:29/46/72/113`), init methods (`DataModelGenerator.DataContext.cs:164-180`, `DataModelGenerator.cs:157-166`), `EntityClassIsPartial` (`DataModelLoader.Entities.cs:67-68`), `GenerateAssociationExtensions` (`DataModelLoader.Entities.cs:275-288`) — covered by E-11 (behaviour now matches CLI).
- Renderer-internal `Modifiers.Record`/`Module` reads (`FSharpCodeGenerator.cs:160-170, :791-797, :1440`) and `GetAlias` checks — out-of-scope (renderer-internal, unchanged).
- `NRTSupported` precedent: single consumer `DataModelLoader.cs:68` — out-of-scope (unchanged; D-4 explains why not mirrored).
- Public surface: `PublicAPI.Unshipped.txt` (flat; per-TFM files hold only `#nullable enable`) — covered by E-13.
- Package validation (critic round 1, measured-by-proxy): `Directory.Build.props:111-112` `EnablePackageValidation=true` vs `BaselineVersion` 6.0.0 (`:11`); Azure packs on every PR build (`Build/Azure/pipelines/build.yml:5-10,22` `pr: '*'` + `with_nugets: true`, `templates/build-job.yml:241-248`; `default.yml` covers master/release pushes and PRs to `release` only) and GitHub `build.yml:118` runs `dotnet pack`. A member added to a shipped public interface is `CP0006`; precedent in this package: `Source/LinqToDB.Scaffold/CompatibilitySuppressions.xml:4-38` (five `CP0006` for `IProperty.IsNullable`). — covered by E-16 (falls under the "PR changes a member present in the baseline package" exception to the release-time-baselines rule).
- CLI settings readers between `ProcessScaffoldOptions` and `new Scaffolder`: `LegacySchemaProvider(dc, settings.Schema, …)` (`Execute.cs:182/188`, Schema options untouched by D-2) and the interceptor ctor (`Execute.cs:157` → `ScaffoldCommand.Interceptors.cs:197-205`) — covered by E-11 (decision recorded in D-3 interceptor-ordering line).
- CLI tests: `Tests/LinqToDB.CLI/ScaffoldTargetLanguageTests.cs:19-24` (option rejection) — out-of-scope (behaviour unchanged; run as TO-6).

## P8 Test obligations

- TO-1a (proof: red→green): `FSharpCodeGenerationTests` data-source test over SqlServer.2022 — scaffold the test DB with the generate.ps1 option set (procedures sync+async, find methods, equatable, schemas) twice, once with `LanguageProviders.FSharp`, once with a test-local `DelegatingLanguageProvider` that forwards every member; assert the two outputs are equal. Discriminating input: the DB's procedures, additional schema and PK tables — the C# arm emits no record / no `QueryProc<T>` / no module. Red: run on pre-change code (wrapper without `Features`) and record the failure reason (must be output mismatch or an F# renderer exception from a C# shape, not a setup error).
- TO-1b (proof: red→green): same over SQLite with `MetadataSource.FluentMapping` — discriminating input for `NullableFlowAnalysis` (`Unchecked.nonNull(options…` only emitted with a context mapping schema, U-3).
- TO-2 (proof: red→green): `Scaffolder(LanguageProviders.FSharp, …, ScaffoldOptions.Default() + ContextClassName)` over the in-test schema: exactly one generated file; no line starts with a TAB; the data context has the single `(options : DataOptions<TestDataContext>)` primary constructor. Red today: `ClassPerFile` default yields >1 file and `\t` indentation.
- TO-3 (proof: red→green): as TO-2 with `Indent = "\t\t"` → indentation of 8 spaces, no TAB.
- TO-4 (proof: characterization) (proves no new behaviour): `generate.ps1` regenerates all 7 F# goldens with empty `git diff`; both F# gate projects build; `FSharpTests.GeneratedCode*` runtime tests green on SQLite + SqlServer.2022.
- TO-5 (proof: characterization): `release-test-cli-scaffold.ps1 -Providers SQLite,SqlServer2025` (all templates) leaves `Tests/Tests.T4` with empty diff — covers the C# arm of every site (procedures need the SQL Server row).
- TO-6 (proof: control): `git grep "LanguageProviders.FSharp\|LanguageProviders.CSharp" -- Source/LinqToDB.Scaffold` returns only the two PublicAPI lines (`PublicAPI.Shipped.txt` `CSharp.get`, `PublicAPI.Unshipped.txt` `FSharp.get`) — any surviving identity check adds a `.cs` hit; CLI tests `Tests.LinqToDB.CLI` green (option rejection unchanged).
- TO-7 (proof: characterization): assert `LanguageProviders.CSharp.Features` and `LanguageProviders.FSharp.Features` equal the D-2 sets exactly (pins the mapping; a flag dropped from either side fails here before it reaches output).
- Flag checklist (D-2 table): sites NestedTypes, NullableFlowAnalysis, LambdaReturnTypeInference, ImplicitUpcast, ImplicitInterfaceImplementation, ImplicitDelegateConversion, ConstructorPropertyInitialization, RecordEntities, OptionTypes — exercised by TO-1a/1b (U-3 counts); settings flags PartialTypes, PartialMethods, MultipleConstructors, TabIndentation, MultipleFiles — TO-2/TO-3 assert ClassPerFile, Indent, constructors; `EntityClassIsPartial`, init methods and `GenerateAssociationExtensions` stay unexercised as library inputs (their CLI options are rejected for F#; covered only by TO-7 pinning the flags) — residual, named.

## P9 Verification gates

- G-01: pass — tests: TO-1a/TO-1b `FSharpCodeGenerationTests.DelegatingProviderMatchesFSharp` (SqlServer.2022.MS / SQLite.MS), TO-2 `DefaultOptionsAdjustedToLanguage`, TO-3 `TabIndentReplaced`, TO-7 `LanguageProviderFeatures`, TO-4 generate.ps1 + gates + `FSharpTests.GeneratedCode*`, TO-5 release-test-cli-scaffold, TO-6 grep + Tests.LinqToDB.CLI. TO-1a/1b red on pre-change code (wrapper without `Features`: output mismatch, imports differ — SQLite.MS length 33500 vs 37649, SqlServer.2022.MS 100281 vs 103278), green after; TO-2/TO-3 red under mutation (`ApplyLanguageFeatures` call commented out: 2 files, TAB indentation), green restored; worktree-test FSharpCodeGenerationTests + FSharpTests.GeneratedCode on SQLite.Classic/MS + SqlServer.2022/.MS: 20/20; TO-6 grep → only the two PublicAPI lines; Tests.LinqToDB.CLI 252/252
- G-02: pass — TO-4 generate.ps1 rewrote all 7 goldens (mtimes 16:56-16:57, after the run's first build at 16:56:22) with empty `git diff`; both F# gates build; TO-5 release-test-cli-scaffold SQLite+SqlServer2025, 11/11 OK, empty `git diff`/status under Tests/Tests.T4
- G-03: pass — PublicAPI.Unshipped.txt: `LanguageFeatures` type + 15 members, `ILanguageProvider.Features.get`, missing `Modifiers.Module`; XML docs on enum, members and property
- G-04: blocked — on the push (CI pack leg is the remaining measurement). Done so far: `/api-baselines` feature-PR path: regenerated `Source/LinqToDB.Scaffold/CompatibilitySuppressions.xml`, residual adds = 5× `CP0006 P:LinqToDB.CodeModel.ILanguageProvider.Features` (net10.0/net462/net8.0/net9.0/netstandard2.0), nothing else; CI pack leg not yet observed (needs push)
- G-05: pass — `dotnet build Source/LinqToDB.Scaffold/LinqToDB.Scaffold.csproj -c Release -f netstandard2.0` exit 0 (first attempt failed MA0154 on `<c>this</c>` in `LanguageFeatures.cs`, fixed to `<see langword="this"/>`); CLI Release net10.0 built by generate.ps1, exit 0
- G-06: pass — working-tree diff touches only E-1..E-14/E-16 files; `-Reconcile` "unplanned" list is the pre-plan branch diff vs origin/master (scope note), none modified by this change
- G-07: pass — no Tests/Tests.Playground changes
- G-09: skipped — no adversarial read of this diff yet; unverified until a review pass runs

## P10 Adjudicated

- Direct `DataModelLoader` / `DataModelGenerator` callers (public ctors) bypass `Scaffolder` and get no settings
  adjustment — deferred: no known caller; the CLI, tests and LINQPad all use `Scaffolder`.
- `WellKnownTypes.cs:28` parses well-known types with the C# provider's parser — pre-existing, out-of-scope.
- Breaking addition to shipped `ILanguageProvider` in 6.6.0 — user decision; no external implementer is possible (U-1).

## P11 Amendments

_None._

## P12 Critic verdict

**Round 1 (plan-critic, model fable): refuted.** Objections:
1. G-04/P7 deferred the `ILanguageProvider` addition to release-time ApiCompat, but package validation runs on every
   PR pack (`Directory.Build.props:111-112`, Azure `with_nugets: true`, GitHub `build.yml:118`), and an added
   interface member is `CP0006` (precedent `CompatibilitySuppressions.xml:4-38`). → added E-16 (`/api-baselines` on
   the PR) and rewrote G-04 to require the pack leg green; P7 row added. Accepted on the in-package precedent
   (measured-by-proxy; the pack itself is the G-04 measurement).
2. P7 missed the CLI interceptor ctor reading `settings` before `Scaffolder` (`Execute.cs:157` →
   `Interceptors.cs:197-205`). → D-3 records "Scaffolder owns the derivation"; U-4 and P7 updated.
3. TO-6 expected output misdescribed (`LanguageProviders.cs` has no literal hit; two PublicAPI hits). → TO-6 fixed.

Critic searched: `LanguageProviders\.(FSharp|CSharp)` and `ReferenceEquals` worktree-wide (same 9 sites);
`ILanguageProvider` (30 files, 2 implementers, no doubles, no `InternalsVisibleTo`); provider-keyed dictionaries (none);
read-verified U-2 (wrapper takes the C# arm, renders via F# generator), D-3 reach (`_options` read lazily), TO-2 red arm
(fails on assertions, not by exception), U-3 site preconditions against goldens, U-4 option gating, TO-5 script keys.
Strongest point per critic: mechanism verified end to end; 14 flags map 1:1 onto the 9 sites and 9 forced values.

**Round 2 (same critic, model fable): holds, no objections.** Re-verified objection 1 against pipeline triggers
(`build.yml:5-10` every-PR Azure pipeline; GitHub `build.yml:21-24,118`; package validation unaffected by the analyzer
switches; `EnablePackageValidation` unconditional in `Directory.Build.props:90-113`) so the round-1 objection was not
accepted wrongly; E-16 executable via `/api-baselines` feature-PR path (Scaffold file only, policy gate will ask —
`LinqToDB.CodeModel` is outside `Internal`); G-04 leg names correct; D-3 interceptor decision breaks nothing
(`ScaffoldInterceptors` has no options member); TO-6 control real. Imprecision fixed: `default.yml` does not pack on
every PR. Not checked by the critic (no capability): the actual `dotnet pack` output — G-04 is that measurement; the
"every TFM" count rests on the five TFMs the existing suppression file enumerates.
