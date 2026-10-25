# Work plan: issue-5922-remove-mapmember-shadows — Detect and remove MapMember shadows; move Right/Truncate/Round emulations to translators

**Tier:** L  ·  **Status:** approved  ·  **Approved-at:** 2026-10-24 (round-2 fixes included, unattacked) ·  **Branch:** issue/5922-remove-mapmember-shadows
**Schema:** `.claude/docs/work-plan.md`  ·  **Gates:** `.claude/docs/definition-of-done.md`

Issue: [#5922](https://github.com/linq2db/linq2db/issues/5922), milestone 6.6.0. All `file:line` references are against `origin/master` at `fd999f689` (worktree `C:\Worktrees\linq2db\5922-mapmember-shadows`).

**Tier rationale:** edit-points under `Source/LinqToDB/**/Translation/**` (cross-cutting-core `paths:`), plus ≥2 KB areas — `CODEGEN` (analyzer), translators, `CORE` (`Sql.cs`, `Expressions.cs`), and nine `PROV-*` areas.

**User decisions this plan executes** (2026-10-24, this session):
1. Analyzer first; the real `Math.Pow` shadow is its proving case, then removed.
2. Report shadows in common **and** provider sections, and remove every reported **map entry**. Provider emulations are ported into provider translators, not just deleted.
3. Attribute shadows are in scope. Attribute builders and member mapping are mechanisms linq2db wants to retire, so `Sql.Right` and `Sql.Truncate` are **fully converted** to translators: every attribute, builder and map entry for them goes.
4. Round ports: port everywhere. Then, after the critic's residue-double objection: *"this sounds like incorrect translators configuration where Math.Round (C# semantics) and Sql.Round — db-specific semantics — are mapped to the same translator when they differ."* Hence D-5: `Sql.Round*` and `Math.Round` get separate virtuals.
5. Access Round overrides are fixed. The base `TranslateRoundToEven` negative-midpoint bug is fixed here.
6. Analyzer only, no code fix. The "re-register for providers without translator" requirement is dropped.
7. Every affected member gets test coverage, existing or new.

## P1 Problem

Map entries in `Source/LinqToDB/Linq/Expressions.cs` are applied in the expose pass (`ExposeExpressionVisitor.VisitMethodCall` → `ConvertMethod`, `ExposeExpressionVisitor.cs:154,395-414`; section lookup over `MappingSchema.ConfigurationList`, then `""`, `Expressions.cs:306-334`). That happens before `ExpressionBuildVisitor.VisitMethodCall` reaches `TranslateMember` (`ExpressionBuildVisitor.cs:939`) or `HandleExtension` (`:944`). A mapped member therefore never reaches its registry handler or its `[Sql.*]` attribute for the configurations the map covers. Both are dead code that reads as live, and nothing prevents the next one.

Measured by scout on this base (and independently re-derived by the critic):
- **Registry shadows: 9 member keys on 16 map lines**, all against `MathMemberTranslatorBase` registrations, which every provider inherits.
  - `Math.Pow(double,double)`: common `:626` vs registration `:104`.
  - `Sql.RoundToEven(double?)` and `(double?,int?)`: Firebird `:791-792`, PostgreSQL `:819-820`, Access `:921,923`, SapHana `:944-945` vs `:78-79`.
  - `Sql.Round(double?,int?)`: PostgreSQL `:818`, Access `:913` vs `:81`.
  - `Sql.Round(double?)` / `(decimal?)` / `(decimal?,int?)` and `Sql.RoundToEven(decimal?)` / `(decimal?,int?)`: Access `:904-906,920,922` vs `:80,98,99,96,97`.
- **Attribute shadows: 4.**
  - `Sql.Right`: the Oracle `[Extension]`/`OracleRightBuilder` (`Sql.cs:638,592`) and the SqlCe one (`:639,611`), behind map `:759` and `:689`.
  - `Sql.Truncate(double?)`: the PostgreSQL `Trunc({0}, 0)` (`Sql.cs:1222`), behind `:826`.
  - `Expressions.AltStuff`: its own `[Sql.Function]` (`Expressions.cs:1083`), behind common `:550`.
- **A semantics conflation the shadows hide.** The same virtuals `TranslateRoundToEven` / `TranslateRoundAwayFromZero` (`MathMemberTranslatorBase.cs:342,406`) serve both `Math.Round` (C# semantics, via `TranslateMathRoundMethod` `:198-251`) and `Sql.Round*` (database semantics, via `:253`, `:287`). The provider maps were the only place `Sql.Round*` got provider-specific semantics. Porting them into the shared virtuals would change `Math.Round`.
- **Defects in the code that becomes reachable** (by reading):
  - The Access overrides use floor-based `Int(v-0.5)` for negatives (`AccessMemberTranslator.cs:254-311`).
  - The Access `TranslateRoundToEven` `IIf` compares `Mod(..)` with `2` (`:237`), so it never fires.
  - The base `TranslateRoundToEven` (`MathMemberTranslatorBase.cs:366-374`) sends a negative midpoint with an odd floor to `ROUND`, so -2.5→-3 and -0.5→-1, through `Math.Round` on every base-using provider.
  - `OracleRightBuilder` emits `substr(s,-n)`, wrong for n=0, n<0 and n>len.
  - `SqlCeRightBuilder` uses raw `LEN`, which drops trailing blanks.

## P2 Success criteria

- SC-1 A new internal analyzer reports `LINQ2DB0007` on a map entry whose member key a covering `Register*` also names. On the miniature model it reports the `Math.Pow` mirror and does not report the cooperative chains, other overloads or foreign look-alikes. → TO-1
- SC-2 Section scoping: a provider-section entry is reported against a base (`…DataProvider.Translation`) registration or its own provider namespace's registration, and not against another provider's. `SQLite.MS` resolves to `SQLite`. → TO-2
- SC-3 `LINQ2DB0008` reports a map entry that makes an `Sql.ExpressionAttribute`-derived attribute dead (common entry vs any attribute; provider `P` vs config `P` or `P.*`), and nothing else. → TO-3
- SC-4 `LINQ2DB0009` reports model drift (no entries collected, or an entry whose section cannot be resolved) instead of going silent. → TO-4
- SC-5 Before any removal, a Release build of the real `Source/LinqToDB` reports exactly the 16 `LINQ2DB0007` and 4 `LINQ2DB0008` sites in `P1`, and no `LINQ2DB0009`. After the change the build is clean. → TO-5
- SC-6 `Math.Pow` routes through `MathMemberTranslatorBase.cs:104` only, with no result change and an unchanged SQL baseline. → TO-6
- SC-7 `Sql.Round*` / `Sql.RoundToEven*` results on each provider are unchanged by the port. Firebird, PostgreSQL and SapHana keep their `decimal` round-trip for `double`, now produced by the `Sql`-specific override. On binary-exact inputs (±0.5, ±2.5, ±3.5, 0.125 @2, -0.375 @2, nulls), every provider equals the client `Sql.*` body (`Sql.cs:1137-1168`), with two exceptions. Access `Sql.Round*` moves to the corrected semantics (SC-9). Access `Sql.RoundToEven*` keeps native `Round` (the map's semantics): it is asserted equal to the client only if TO-10 shows native `Round` is banker's on both drivers; otherwise it is asserted equal to master and recorded in P10. → TO-7, TO-8, TO-9
- SC-8 `Math.Round(double…)` results and SQL do not change because of the `Sql.Round*` port: the virtuals it reaches are unchanged except for SC-9 / SC-10 fixes. → TO-9, TO-16
- SC-9 Access `Math.Round(x, AwayFromZero)` and `Sql.Round*` are sign-symmetric, and Access `Sql.RoundToEven*` keeps the map's native `Round(v[,p])` semantics. → TO-10
- SC-10 Base `TranslateRoundToEven` rounds negative midpoints to even: -2.5→-2, -0.5→0, -3.5→-4. → TO-11
- SC-11 `Sql.Right` is translator-only, with no attribute, builder or map entry left. Every provider equals the client for in-range and null inputs: 0 ≤ n ≤ len, a null string, a null length, trailing blanks. On Oracle, n = 0 yields NULL, because Oracle stores `''` as NULL. Out-of-range n (n < 0, n > len) keeps each provider's current answer, an error included, except Oracle n ≥ len+2. Against master's effective Oracle path, the map formula `Substr(s, len-n+1, n)` at `Expressions.cs:759` (not the dead builder), the clamp changes only that cell, `('John',6)`: `'n'` → `'John'`. → TO-12, TO-13
- SC-12 `Sql.Truncate(decimal?)` / `(double?)` are translator-only and equal the client for positive and negative fractions and null on every provider, with no attribute or map entry left. → TO-14, TO-15
- SC-13 Column-argument SQL is unchanged wherever no defect is fixed. That covers `Sql.Right` on generic-RIGHT / SQLite / ClickHouse / Ydb / PostgreSQL / Informix / SqlCe, `Sql.Truncate` on every provider, and `Sql.Round*` on Firebird / PostgreSQL / SapHana. → TO-16
- SC-14 `Sql.Stuff` / `string.Insert` / `string.Remove` (via `AltStuff` → `Sql.Right`) keep their results on all providers. → TO-17

## P3 Constraints & anti-goals (M/L)

**Must not change:**
- **Results of any query that is correct today.** SQL text may change only where `P5` says so: the Access and base-ToEven defect fixes, the Oracle `Right` fix, the constant-argument policy of D-6, and the `Sql.Right` / `Sql.Truncate` providers whose emulation moves. The last must stay SQL-identical by SC-13.
- **Public API outside `LinqToDB.Internal.*`.** Removing attributes from public `Sql.Right` / `Sql.Truncate` changes no signature. New protected virtuals and nested translator classes are in `LinqToDB.Internal.DataProvider.*` and need `PublicAPI.Unshipped.txt` rows (`PublicAPI.Shipped.txt:16347` shows the base virtuals are tracked).
- **Shipped public members that become unused stay.** `Expressions.AccessRound(double?,int?)` / `(decimal?,int?)` (`Expressions.cs:1186,1200`; `PublicAPI.Shipped.txt:15016-15017`) lose their only callers (`:904-905,920-923`). See `P10`.
- **`CompatibilitySuppressions.xml`:** never hand-edited, and not expected to change.
- **The common-map cooperative chains:** `string.Compare` / `CompareOrdinal` → `CompareTo`, `ConvertTo<string>.From(Guid)` → `ToString`, `T.Parse` → `ConvertTo`, and `Math.Truncate` → `Sql.Truncate` (`Expressions.cs:642-643`). `Math.Truncate` is unregistered, so it is no shadow.
- **`Expressions.MapMember` public API and runtime user registrations.**

**Anti-goals:**
- No code fix (user decision 6; `authoring-analyzers.md:30`).
- No conversion of other members' attributes, e.g. `Sql.Left` (`Sql.cs:579-583`; maps `:688,722,758,812`), which is unregistered and so no shadow.
- No `LinqToDB.EntityFrameworkCore` change: `LinqToDBForEFTools.Mapping.cs:9` (`DbFunctions.Like`) is unregistered and in another compilation.
- No change to PostgreSQL's shared `TranslateRoundToEven` `decimal` cast (`PostgreSQLMemberTranslator.cs:273-295`), which `Math.Round` reaches too. PostgreSQL documents `round(numeric, int)` but no `round(double precision, int)` overload, so the cast is a necessity for the precision form (documented, unprobed), not an `Sql`-semantics leak. TO-9 records its residue behaviour.
- No out-of-range `Sql.Right` contract (n < 0, n > len) on providers whose emulation is not being rewritten. The answer there is engine semantics, recorded in `P10`.

**Build constraints for the analyzer** (`Source/CodeGenerators/Directory.Build.props:10-20`; `.editorconfig` RS rules, per the #5814 plan's `P3` table):
- RS1030 bans `GetSemanticModel`, so semantics come from `IOperation`s.
- RS1037 requires the `CompilationEnd` custom tag on compilation-end diagnostics.
- RS1008 forbids per-compilation state in fields.
- RS1024 requires comparisons through `SymbolEqualityComparer`.
- RS1025 / RS1026 require configuring generated-code analysis and concurrent execution.
- RS2000 / RS2001 require release-tracking rows.
- XML docs and `TreatWarningsAsErrors` apply in every configuration.

On `Source/LinqToDB` the analyzer runs in **Release only** (`Directory.Build.props:120-122`), or with `-p:RunAnalyzersDuringBuild=true`.

## P4 Unknowns (M/L)

- U-1 Do map and registry use the same member key? — resolved-by scout: yes. The map uses `NormalizeMemeberInfo(GetMemberInfoWithType)` (`Expressions.cs:40-49`); the registry uses `MemberHelper.GetMemberInfoWithType` (`TranslationRegistration.cs:37-50`); `MemberInfoWithType.Equals` compares type + member (`MemberHelper.cs:23-26`). Generic-match registrations use the method definition (`TranslationRegistration.cs:45-48`).
- U-2 Where are `Register*` calls? — resolved-by scout: only in base classes under `Internal/DataProvider/Translation/` plus `Linq/Translation/WindowFunctionsMemberTranslator.cs`, which names no mapped member. No provider class calls `Register*`. No caller exists outside `Source/LinqToDB`. `Expressions.M(` has no call site outside the `Expressions` type.
- U-3 Overload binding of registration lambdas — resolved-by scout: `Sql.Round*` exists for `decimal?` / `double?` only (`Sql.cs:1137-1168`). `(float v)` binds `double?`, so `MathMemberTranslatorBase.cs:87-90` duplicate `:78-81`.
- U-4 Can the analyzer read lambda bodies without a semantic model? — resolved-by scout: yes, via `RegisterOperationAction(OperationKind.Invocation)`. `IInvocationOperation.Arguments[0]` → `IDelegateCreationOperation` → `IAnonymousFunctionOperation.Body`. Cross-file joining needs compilation-end aggregation (D-1).
- U-5 Which providers have math translators? — resolved-by scout: SQLite, Informix, Firebird, DuckDB and MySql have none (`ProviderMemberTranslatorDefault.cs:24-27` base). SapHana (`SapHanaMemberTranslator.cs:278`), PostgreSQL (`:271`), Access (`:214`), Oracle, SqlCe, Sybase, DB2, SqlServer (+2022), ClickHouse and Ydb have one. Every provider has a string translator.
- U-6 How do attribute flags act outside extension building? `PreferServerSide=true` on `Sql.Right` stops `HandleExtension` backing off for client-evaluable calls (`ExpressionBuildVisitor.cs:1246`), so constant-argument `Sql.Right` emits SQL today; `Sql.Truncate`'s attributes (`PreferServerSide=false, IsPure=true`) make constant calls immutable (`ExpressionTreeOptimizationContext.cs:404-405`, so literals) and let `LinqOptions.PreferClientCalculation` pull them client-side (`ExpressionBuildVisitor.cs:937`, `:2383-2386`); a translator-only member loses both, which drives D-6 — resolved-by scout
- U-7 SQL-node flags in a translator — resolved-by scout: `factory.Function(type, name, args)` is pure with `IfAnyParameterNullable`, which matches the attributes (`SqlFunction.cs:11-15`; `Sql.FunctionAttribute.cs:106` types from `GetDbDataType(expression.Type)`). `factory.Expression(...)` is **not** pure, with Undefined nullability (`SqlExpressionFactoryExtensions.cs:26-59`). Template SQL needs `new SqlExpression(type, text, precedence, SqlFlags.IsPure, ParametersNullabilityType.IfAnyParameterNullable, …)`. The result type must be the CLR return type (`GetDbDataType(methodCall.Type)`) to keep column-arg SQL identical.
- U-8 Do translators run for remote contexts? — resolved-by scout: yes. The server sends its concrete translator type (`LinqService.cs:94`); the client activates it (`RemoteDataContextBase.cs:157-165,261-262`). Parameterless constructors are required, and every translator has one.
- U-9 Firebird / SapHana `decimal` range on the ported `Sql.RoundToEven(double)` path — resolved-by scout, by reading: `Decimal(18,10)` on Firebird (`FirebirdMappingSchema.cs:33`), `Decimal(38,10)` on SapHana (`SapHanaMappingSchema.cs:34`). The range limit is the map's today, and the port keeps it on the `Sql` path only, so `Math.Round` is unaffected (D-5).
- U-10 How do the four rewritten `Sql.Right` emulations behave? SqlCe, Informix and PostgreSQL port the map formula `Substring(s, Length(s) - n + 1, n)` (`Expressions.cs:689,723,813`), with `Length(s)` built as the same string-length SQL node `string.Length` translates to, so each provider's convert visitor applies its own rewrite (SqlCe `LEN(s + '.') - 1`, `SqlCeSqlExpressionConvertVisitor.cs:172-185`) and trailing blanks and SQL stay as on the map path; Oracle ports it with the start clamped, `Greatest(Length(s) - n + 1, 1)`, because Oracle counts a negative start from the right (`'John', 6` → `'n'`, documented, unprobed); TO-12's master run records every provider's current edge answers and decides the per-provider proof label — resolved-by design
- U-11 Access native `Round` midpoint semantics — resolved-by design + probe. The map's `Sql.RoundToEven*` → `AccessRound` → `Round(v[,p])` is ported as-is into the `Sql`-specific override, so it is unchanged whatever `Round` does. For `Math.Round(…, ToEven)`, the Access override emits native `Round` only if TO-10's master run shows banker's rounding on ACE OleDb and ODBC. Otherwise it emits the corrected CASE spelled with `Int` instead of `FLOOR`: Access has no `FLOOR`, and its convert visitor renames only `%` → `MOD` (`AccessSqlExpressionConvertVisitor.cs:531`), as the existing override already does at `AccessMemberTranslator.cs:273`.
- U-12 Is the `AltStuff` `[Sql.Function]` reachable anywhere? — resolved-by scout: no. `AltStuff` is in the `LinqToDB` namespace and mapped under `""`, so the common entry always wins (`Expressions.cs:292-309`). The map entry *is* its implementation, reached from `Sql.Stuff` maps on nine providers (`:707,724,760,781,800,814,834,883,946`).
- U-13 Does the base TranslateRoundToEven bug reach Math.Round today? — resolved-by scout: yes, through `TranslateMathRoundMethod` → `:240` for every provider whose override reaches the base precision-null branch. That is the base users, and SqlServer / SqlCe / Sybase through `base.` (`SqlServerMemberTranslator.cs:196`, `SqlCeMemberTranslator.cs:253`, `SybaseMemberTranslator.cs:219`). ClickHouse (`roundBankers`, `ClickHouseMemberTranslator.cs:261-277`) and Ydb (`Math::NearbyInt`, `YdbMemberTranslator.cs:723-725`) never reach it. Current tests never use negatives (`CreateData.cs:136-147`).

## P5 Decisions (M/L; rejected alternatives mandatory at L)

### D-1 — Analyzer collects through operations and reports at compilation end

- **chosen:** `MemberMapShadowAnalyzer` in `Source/CodeGenerators`.
  - At `CompilationStart`, resolve `LinqToDB.Linq.Expressions`, `TranslationRegistrationExtensions` and `Sql.ExpressionAttribute` via `Compilation.Assembly.GetTypeByMetadataName` (source assembly, as `ProjectFlagsAnalyzer.cs:88-94`). Return silently if `Expressions` is absent.
  - `RegisterOperationAction(Invocation)` collects into closure-held concurrent bags (a) `Expressions.M` calls and (b) `TranslationRegistrationExtensions.RegisterMethod/RegisterMember/RegisterConstructor` calls, each keyed per U-1.
  - `RegisterCompilationEndAction` joins the two and reports 0007/0008/0009. Each descriptor carries `WellKnownDiagnosticTags.CompilationEnd`.
- **rejected:** syntax-only reading, the #5814 D-2 approach. Overload binding through implicit conversions (U-3) and receiver types cannot be decided from syntax.
- **rejected:** per-operation reporting with one side precomputed at start. The registrations are in other files and need semantics; RS1030 forbids `GetSemanticModel`.
- **why this:** the only RS1030-clean way to get semantics on both sides; the issue's own proposed shape.
- **failure mode of the choice:** compilation-end diagnostics show in the IDE only under full-solution analysis, so enforcement is the Release build and CI's Release legs (`.github/workflows/build.yml:93-113`).

### D-2 — Section is resolved by structure, not by field or method name

- **chosen:** walk the `M(...)` invocation's `Parent` chain to the enclosing collection-initializer `Add(key, value)` and then to its `IObjectCreationOperation`. If that creation is a field initializer, record field→entries. If it is the `value` of an outer `Add(key, value)`, the section is `key`'s constant string. Separately, record every outer `Add(constKey, fieldReference)` as field→key (`{ "", _commonMembers }`, `Expressions.cs:668`). Any `M(...)` whose section cannot be resolved is `LINQ2DB0009`.
- **rejected:** match `_commonMembers` / `LoadMembers` by name — a rename silently retires the rule.
- **why this:** survives renames and reorderings, and turns a structural change into a loud 0009.
- **failure mode of the choice:** an entry added through a helper method reads as unresolved → 0009 on legitimate code; a refactor tax by design.

### D-3 — Registration scope by namespace; attribute deadness by configuration

- **chosen:**
  - A registration in `LinqToDB.Internal.DataProvider.Translation` or `LinqToDB.Linq.Translation` covers every section.
  - A registration in `LinqToDB.Internal.DataProvider.<P>[.…]` covers sections whose provider root (key up to the first `.`) equals `<P>`, case-insensitive.
  - Common `""` is covered by any registration.
  - 0008: a common entry kills every attribute on the member; a provider entry `P` kills attributes whose `Configuration` equals `P` or starts with `P.`.
- **rejected:** "any registration covers any section" (the issue's literal rule). It would false-positive once a provider-local registration appears.
- **rejected:** resolving the provider → translator chain through `CreateMemberTranslator` overrides — a whole-program reading for no existing case.
- **why this:** cheap, decidable, correct for every case in U-2 (critic re-derived: no false positive on the kept chains).
- **failure mode of the choice:** a translator class outside the namespace convention would be scoped wrong. TO-2 pins the convention.

### D-4 — Remove the map entry; the registry/attribute side stays — except `AltStuff`

- **chosen:** delete every reported entry (user decision 2), porting provider emulations first (D-5, D-6). `AltStuff`'s `[Sql.Function]` (`Expressions.cs:1083`) is deleted instead, because its map entry is its implementation (U-12).
- **rejected:** delete `AltStuff`'s map entry. `Sql.Stuff` on nine providers would then emit an `AltStuff(...)` SQL call.
- **why this:** honours the direction while keeping the one entry that is a chain, not a shadow.
- **failure mode of the choice:** none known. TO-17 guards the chain.

### D-5 — `Sql.Round*` gets its own virtuals; map emulations are ported there; `Math.Round` keeps the shared ones

- **chosen:**
  - **New virtuals.** `MathMemberTranslatorBase` adds `protected virtual TranslateSqlRoundToEven(ctx, call, value, precision)` and `TranslateSqlRoundAwayFromZero(...)`. Their base bodies return `TranslateRoundToEven(...)` / `TranslateRoundAwayFromZero(...)`, so behaviour is unchanged for every provider that does not override them.
  - **Rewired registrations.** The `Sql.Round*` / `Sql.RoundToEven*` registrations (`:78-81,87-90,96-99`) dispatch through these. The `Math.Round` registrations (`:74-77,83-86,92-95` → `TranslateMathRoundMethod`) are untouched.
  - **Ports into the new overrides, faithful to the map:**
    - Firebird and SapHana: `TranslateSqlRoundToEven` casts a non-decimal value to the schema `decimal`, calls `base`, and casts back. This mirrors `:791-792` and `:944-945`. Firebird needs a new `MathMemberTranslator` and a `CreateMathMemberTranslator` override; its version subclasses inherit it.
    - PostgreSQL: `TranslateSqlRoundAwayFromZero` applies the same cast for a non-decimal value **only when the call has a precision argument** (`methodCall.Arguments.Count > 1`), mirroring `:818`, which maps only `Sql.Round(double?, int?)`. The 1-arg `Sql.Round(double?)` is unmapped today and keeps the float8 override route (`PostgreSQLMemberTranslator.cs:304-315`). `:819-820` need no port, because the shared ToEven override already casts.
    - Access: `TranslateSqlRoundToEven` emits native `Round(v, p)`, with `Round(v, 0)` when precision is null, exactly what `:920-923` → `AccessRound(v, 0|p)` → `[Sql.Function("Round", 0, 1)]` produced (`Expressions.cs:1185-1200`). `Sql.Round*` uses the corrected shared `TranslateRoundAwayFromZero`; the map's `:904-919` form is not ported, since it is wrong for negatives and for any p outside 1..6 (`P1`, user decision 5).
  - **Defect fixes in the shared virtuals:**
    - Access `TranslateRoundAwayFromZero` becomes sign-symmetric: `Sgn(v)*Int(Abs(v)*10^p+0.5)/10^p`, without the `/10^p` at p=0.
    - Access `TranslateRoundToEven` follows U-11 and drops the dead `IIf` (`:237`).
    - Base `TranslateRoundToEven`, precision-null branch: a midpoint with an even floor gives `FLOOR`, a midpoint with an odd floor gives `FLOOR+1`, anything else gives `ROUND`.
  - Delete the map entries `:791-792,818-820,904-923,944-945`.
- **rejected:** port the round-trips into the shared virtuals. That also moves `Math.Round(double…)` to decimal semantics (1.15 @1 AwayFromZero: C# 1.1, decimal 1.2) and adds Firebird's 1e8 overflow to it.
- **rejected:** a `methodCall.Method` check inside the shared virtuals. Same effect as separate virtuals, but hidden from providers and reviewers.
- **rejected:** delete the maps without porting. That changes `Sql.Round*(double)` results on Firebird / PostgreSQL / SapHana.
- **why this:** the user's diagnosis. Separate virtuals make the semantics split explicit, faithful ports keep every `Sql.Round*` result, and `Math.Round` changes only through the stated defect fixes.
- **failure mode of the choice:** two virtuals per mode is new surface (`PublicAPI.Unshipped.txt`), and a provider that overrides only the shared virtual silently changes both paths, as today. Also, `Sql.RoundToEven(double)` on Firebird keeps the map's `Decimal(18,10)` range (U-9), which is pre-existing.

### D-6 — `Sql.Right` / `Sql.Truncate`: base registration + virtual + per-provider override, attribute semantics preserved

- **chosen:**
  - `StringMemberTranslatorBase` registers `Sql.Right(string?,int?)`, and `MathMemberTranslatorBase` registers both `Sql.Truncate` overloads. Each dispatches to a new protected virtual, `TranslateRight` / `TranslateTruncate`.
  - The base virtuals emit what the default attributes emitted: `RIGHT(s,n)` and `Truncate(x)`, via `factory.Function` typed from the CLR return type (U-7).
  - **Right overrides:**
    - SQLite, ClickHouse and Ydb reproduce their attributes (`Sql.cs:636,637,640`).
    - SqlCe, Informix and PostgreSQL port the map formula (U-10).
    - Oracle ports it with a clamped start (U-10).
  - **Truncate overrides:**
    - Ydb, SqlServer, DB2, Informix, Oracle, Firebird, DuckDB, MySql, SqlCe and SapHana reproduce their attributes.
    - PostgreSQL reproduces its decimal attribute and keeps map `:826`'s `double`→`decimal` cast for `double`.
    - SQLite, Sybase and Access reproduce the Floor/Ceiling maps (`:841-842,874-875,928-929`).
    - New math translators for SQLite, Informix, DuckDB and MySql.
  - **Client-evaluation policy:**
    - The `Sql.Right` handler has **no** client-evaluable guard, so it always goes to SQL, mirroring `PreferServerSide=true` (U-6) as `TranslateAbsMethod` does (`MathMemberTranslatorBase.cs:141-152`).
    - The `Sql.Truncate` handler returns null whenever `CanBeEvaluatedOnClient(methodCall)`, in every translation mode. That deliberately deviates from its siblings, which gate on `TranslationFlags.Expression &&` (`MathMemberTranslatorBase.cs:200,255,289,323`): it mirrors `HandleExtension`'s unconditional back-off for `PreferServerSide=false` (`ExpressionBuildVisitor.cs:1246`). The handler gets a one-line comment saying so.
  - Delete every `Sql.Right` / `Sql.Truncate` attribute (`Sql.cs:635-640,1199-1227`), `OracleRightBuilder` / `SqlCeRightBuilder` (`:592-633`), and the maps `:689,723,759,813,826,841-842,874-875,928-929`.
- **rejected:** a virtual that returns null by default, so non-overriding providers fall through to their attributes. It leaves both mechanisms per member (user decision 3).
- **rejected:** registering only in provider translators — a new pattern (U-2).
- **rejected:** a full client contract for out-of-range `n` on every provider. It changes `RIGHT` SQL on every engine for inputs nobody reported (`P3` anti-goal).
- **why this:** follows the #5544 / #5515 precedent (`5999b4f4e`, `c35da70f6`), and keeps column-argument SQL byte-identical except for Oracle's clamp.
- **failure mode of the choice:** two attribute semantics cannot be reproduced for `Sql.Truncate` (U-6). A client-evaluated constant call becomes a parameter instead of an inlined literal, which is visible in WHERE. And `LinqOptions.PreferClientCalculation` no longer pulls it client-side. Both are recorded in `P10` and pinned by TO-15.

## P6 Edit-points

- E-1 `Source/CodeGenerators/MemberMapShadowAnalyzer.cs` (new) — LINQ2DB0007, 0008 and 0009 analyzer per D-1..D-3.
- E-2 `Source/CodeGenerators/AnalyzerReleases.Unshipped.md` — rows for 0007, 0008, 0009 (Usage, Warning, `MemberMapShadowAnalyzer`).
- E-3 `Tests/Tests.Analyzers.Internal/MemberMapShadowAnalyzerTests.cs` (new) — miniature-model fixtures TO-1..TO-4.
- E-4 `Source/LinqToDB/Linq/Expressions.cs:_commonMembers,LoadMembers,AltStuff` — delete `:626`; `:791-792,818-820,904-923,944-945`; `:689,723,759,813,826,841-842,874-875,928-929`; drop `AltStuff`'s `[Sql.Function]` (`:1083`).
- E-5 `Source/LinqToDB/Sql/Sql.cs:Right,Truncate,OracleRightBuilder,SqlCeRightBuilder` — delete all attributes on `Right` / both `Truncate`s and the two builder classes.
- E-6 `Source/LinqToDB/Internal/DataProvider/Translation/MathMemberTranslatorBase.cs` — add `TranslateSqlRoundToEven` / `TranslateSqlRoundAwayFromZero` and rewire the `Sql.Round*` registrations to them; register `Sql.Truncate` ×2 + `TranslateTruncate`; fix the `TranslateRoundToEven` precision-null branch (`:363-374`).
- E-7 `Source/LinqToDB/Internal/DataProvider/Translation/StringMemberTranslatorBase.cs` — register `Sql.Right`, add `TranslateRight` virtual.
- E-8 `Source/LinqToDB/Internal/DataProvider/PostgreSQL/Translation/PostgreSQLMemberTranslator.cs` — `TranslateSqlRoundAwayFromZero` cast; `TranslateTruncate` (decimal cast for double); `TranslateRight` (map formula).
- E-9 `Source/LinqToDB/Internal/DataProvider/Firebird/Translation/FirebirdMemberTranslator.cs` — new math translator: `TranslateSqlRoundToEven` cast, `TranslateTruncate`.
- E-10 `Source/LinqToDB/Internal/DataProvider/SapHana/Translation/SapHanaMemberTranslator.cs` — `SapHanaMathMemberTranslator.TranslateSqlRoundToEven` cast, `TranslateTruncate`.
- E-11 `Source/LinqToDB/Internal/DataProvider/Access/Translation/AccessMemberTranslator.cs` — `TranslateSqlRoundToEven` (native `Round`); fix `TranslateRoundAwayFromZero` / `TranslateRoundToEven`; `TranslateTruncate` (Floor/Ceiling).
- E-12 `Source/LinqToDB/Internal/DataProvider/Oracle/Translation/OracleMemberTranslator.cs` — `TranslateRight` (clamped formula), `TranslateTruncate`.
- E-13 `Source/LinqToDB/Internal/DataProvider/SqlCe/Translation/SqlCeMemberTranslator.cs` — `TranslateRight` (map formula over the string-length node), `TranslateTruncate`.
- E-14 `Source/LinqToDB/Internal/DataProvider/Informix/Translation/InformixMemberTranslator.cs` — `TranslateRight`; new math translator with `TranslateTruncate`.
- E-15 `Source/LinqToDB/Internal/DataProvider/SQLite/Translation/SQLiteMemberTranslator.cs` — `TranslateRight`; new math translator with `TranslateTruncate`.
- E-16 `Source/LinqToDB/Internal/DataProvider/ClickHouse/Translation/ClickHouseMemberTranslator.cs` — `TranslateRight` (`rightUTF8`); `TranslateRoundAwayFromZero` sign-symmetric for non-decimal values (A-1).
- E-17 `Source/LinqToDB/Internal/DataProvider/Ydb/Translation/YdbMemberTranslator.cs` — `TranslateRight`, `TranslateTruncate`.
- E-18 `Source/LinqToDB/Internal/DataProvider/SqlServer/Translation/SqlServerMemberTranslator.cs` — `TranslateTruncate` (`Round(x,0,1)`).
- E-19 `Source/LinqToDB/Internal/DataProvider/DB2/Translation/DB2MemberTranslator.cs` — `TranslateTruncate`; `TranslateRoundAwayFromZero` sign-symmetric for non-decimal values (A-2).
- E-20 `Source/LinqToDB/Internal/DataProvider/DuckDB/Translation/DuckDBMemberTranslator.cs` — new math translator with `TranslateTruncate`.
- E-21 `Source/LinqToDB/Internal/DataProvider/MySql/Translation/MySqlMemberTranslator.cs` — new math translator with `TranslateTruncate`, and `TranslateRoundAwayFromZero` sign-symmetric for non-decimal values (A-1).
- E-22 `Source/LinqToDB/Internal/DataProvider/Sybase/Translation/SybaseMemberTranslator.cs` — `TranslateTruncate` (Floor/Ceiling).
- E-23 `Source/LinqToDB/PublicAPI/PublicAPI.Unshipped.txt` — rows for the new virtuals, overrides and nested translator classes.
- E-24 `Tests/Linq/Linq/MathFunctionTests.cs` — new Round / RoundToEven / Truncate tests (TO-7..TO-11, TO-14, TO-15).
- E-25 `Tests/Linq/Linq/StringFunctionTests.cs` — new Right tests (TO-12, TO-13).
- E-26 `Tests/Model/*` — a shared rounding / string-edge values model and table, only if no existing model carries negative / tie / null `decimal`+`double` values (`test-writer` picks the existing one first).
- E-27 `Source/LinqToDB/Internal/DataProvider/ClickHouse/Translation/ClickHouseMemberTranslator.cs`, `Source/LinqToDB/Internal/DataProvider/Ydb/Translation/YdbMemberTranslator.cs` — conditional: their own ToEven overrides, fixed here only if TO-11's master run reddens there (`P7` row).

## P7 Impact map (M/L)

- `Expressions.cs` registry shadows (9 keys / 16 lines, `P1`) — searched `Register(Method|Member|Constructor|Replacement|Binary|Unary)` and `\.Register…\s*<` across `Source/**/*.cs`, keyed per U-1; critic re-derived 16/9 — covered by E-4, E-6, E-8, E-9, E-10, E-11
- `Expressions.cs` attribute shadows (4, `P1`) — searched every mapped member's `ExpressionAttribute`-derived attributes against section configs; critic re-derived 4 — covered by E-4, E-5
- Shared Round virtuals and their two caller families: `Math.Round` → `TranslateMathRoundMethod` (`MathMemberTranslatorBase.cs:198-251` → `:240,:243`) and `Sql.Round*` → `:253`, `:287` (`→ :279, :313`) — covered by E-6 (split per D-5)
- Provider overrides of the shared Round virtuals: PostgreSQL `:273,297`; Access `:216,254`; SqlServer `:196`, SqlCe `:253`, Sybase `:212-219` (all `base.`-reaching); ClickHouse `:261-277` and Ydb `:723-725` (own implementations) — searched `override .*TranslateRound(ToEven|AwayFromZero)` across `Source/` — PostgreSQL/Access covered by E-8/E-11; SqlServer/SqlCe/Sybase reach the base fix through `base.` (TO-11 covers them); ClickHouse/Ydb covered by E-27 if red, else characterization
- `Sql.Right` / `Sql.Truncate` producers: `AltStuff` (`Expressions.cs:550`) → `Sql.Right`; `Math.Truncate` (`:642-643`) → `Sql.Truncate`; nothing else in `Source/` (searched `Sql\.Right`, `Sql\.Truncate`, `"RIGHT"`) — covered by E-6, E-7 (+ TO-14, TO-17)
- `Sql.Stuff` → `AltStuff` chain on nine providers (`Expressions.cs:707,724,760,781,800,814,834,883,946`) — covered by E-4 (`AltStuff` entry kept) + TO-17
- Removed-attribute flag consumers (`ExpressionBuildVisitor.cs:937,1246,2374,2383-2386,3082`; `ExpressionTreeOptimizationContext.cs:404-405`; `ExpressionBuilder.QueryBuilder.cs:529-597`) — covered by E-6, E-7 (D-6 policy); residue in P10
- `TranslatePow` overrides newly reached by `Math.Pow`: Access `AccessMemberTranslator.cs:316`, Ydb `YdbMemberTranslator.cs:683` — covered by E-4 + TO-6 (they already serve `Sql.Power`)
- `Expressions.AccessRound` ×2 (`Expressions.cs:1186,1200`; shipped `PublicAPI.Shipped.txt:15016-15017`) — searched `AccessRound|AccessInt` across `Source/`: only callers are the deleted `:904-905,920-923` — out-of-scope (shipped public API kept; P10)
- Remote/LinqService translator activation (`LinqService.cs:94`, `RemoteDataContextBase.cs:157-165`) — out-of-scope (unchanged mechanism; new translators keep parameterless ctors; `[DataSources]` runs `.LinqService` contexts)
- Tests that narrow providers on the touched paths: `Round6` (`[DataSources(AllClickHouse)]`, `MathFunctionTests.cs:319`), `Round9` / `Round12` (`AllSQLite`, `:346,380`), `PowDecimal*` (`AllSybase`, `:248,1600,1623`) — searched `DataSources\(` in `MathFunctionTests.cs` / `StringFunctionTests.cs` — covered by E-24 (re-run each excluded provider after the fix; drop or re-justify per `testing.md` → *A narrowed provider set is a claim*)
- Existing `Math.Truncate` / `Sql.Right` consumers: `MathFunctionTests.cs:1821-1836`, `StringFunctionTests.cs:972-985,1016-1089`, `OrmBattleTests.cs:1730-1736` (WHERE, column arg) — covered by E-24, E-25 (TO-14, TO-16, TO-17 re-run them)
- KB tables (`CODEGEN/INDEX.md:50-52,78-80,102,159`; `PROV-ACCESS/INDEX.md:254`) — deferred: KB is skill-driven (`/kb-refresh`)
- `.claude/docs/analyzer-own-perf-baseline.json` — deferred: refreshed by `/profile-analyzers rules`
- `PublicAPI.Shipped.txt` existing virtual rows (`:16347`, `:16392`) — covered by E-23 (Unshipped only)

## P8 Test obligations (M/L)

- TO-1 `MemberMapShadowAnalyzerTests`: exact `Math.Pow` mirror (common `M` + base `RegisterMethod`) → 0007 on the `M(...)` span; positive arms for `RegisterMember` (property), `RegisterConstructor`, an instance receiver type, and `isGenericTypeMatch: true` vs a constructed generic entry; silent controls for a different overload (`Math.Round(decimal)` registered, `Math.Round(double)` mapped), the `string.Compare`→`CompareTo` and `ConvertTo<string>.From(Guid)`→`ToString` chains, an unrelated `M`, and an unrelated `RegisterMethod` in another namespace — providers: n/a (analyzer) — proof: red→green (fixtures first; an empty analyzer fails every positive arm)
- TO-2 Section scoping: provider entry vs base-namespace registration → 0007; vs own `…DataProvider.<P>` registration → 0007; vs another provider's → silent; `SQLite.MS` entry vs `…DataProvider.SQLite` registration → 0007; field-initializer entry paired by `{ "", field }` → common — providers: n/a — proof: red→green
- TO-3 0008: provider entry vs same-config attribute → 0008; vs `P.sub` config → 0008; vs generic and vs other-provider attribute → silent; common entry vs generic attribute → 0008 — providers: n/a — proof: red→green
- TO-4 0009: an `M(...)` inside a helper method (section unresolvable) → 0009; an `Expressions` type with no entries → 0009 — providers: n/a — proof: red→green
- TO-5 Real tree: Release build of `Source/LinqToDB` (or `-c Testing -p:RunAnalyzersDuringBuild=true`) **before** E-4..E-22 reports exactly the 16 + 4 sites of `P1` and no 0009, recorded verbatim in P9 G-02; after the change, clean — providers: n/a — proof: red→green
- TO-6 `MathFunctionTests.Pow` (`MathFunctionTests.cs:238`, `[DataSources]`): unchanged result and unchanged SQL baseline — providers: all — proof: characterization
- TO-7 `Sql.Round*` / `Sql.RoundToEven*` binary-exact matrix, all eight overloads (`decimal?`/`double?` × with/without precision × Round/RoundToEven), over server-side column values {2.5, 3.5, -2.5, -3.5, -0.5, 0.125 @2, -0.375 @2, 2.4, -2.4, null value, null precision — a NULL **column** cell, never a literal `null`, which both wrappers coerce to no-precision (`MathMemberTranslatorBase.cs:276-277,310-311`)}; expected = client `Sql.*` bodies (`Sql.cs:1137-1168`); separates: the base ToEven bug (-2.5, -0.5 on base providers) and Access AwayFromZero (-2.4) from correct emulations — providers: all `[DataSources]` — proof: red→green on Access and base-ToEven providers (the master run records which), characterization elsewhere
- TO-8 Port faithfulness: on TO-7's values plus residue doubles {1.15 @1, 2.675 @2}, results **and SQL** are identical before (map) and after (`Sql`-specific override) for `Sql.RoundToEven(double?)` and `Sql.RoundToEven(double?,int?)` on Firebird / PostgreSQL / SapHana / Access, for `Sql.Round(double?,int?)` on PostgreSQL, and for the unmapped 1-arg `Sql.Round(double?)` on PostgreSQL (which must stay on float8). The residue rows assert the **master** result, not C#. Access `Sql.Round*` is not here: it changes by design (TO-7 / TO-10) — providers: AllFirebird, AllPostgreSQL, AllSapHana, AllAccess — proof: characterization
- TO-9 `Math.Round` isolation: `Math.Round(double, int, AwayFromZero)` and `Math.Round(double, int)` over residue doubles {1.15 @1, 2.675 @2} return the master result on every provider (the port must not reach `Math.Round`); separates: a port wrongly placed in the shared virtual flips 1.15 @1 AwayFromZero on PostgreSQL from 1.1 to 1.2 — providers: all — proof: control (mutation: move E-8's cast into the shared `TranslateRoundAwayFromZero` → PostgreSQL row reddens)
- TO-10 Access: `Math.Round(x, MidpointRounding.AwayFromZero)` and `Sql.Round(x)` over {-2.4, -2.0, -2.5, -3.5}; and `Math.Round(x, ToEven)` over {2.5, 3.5, -2.5}, recording native `Round` midpoint behaviour on ACE OleDb and ODBC (U-11) — providers: AllAccess — proof: red→green (master's `Int(v-0.5)` gives -3 for -2.4 and -2.0)
- TO-11 Base ToEven negatives: `Math.Round(x)` and `Math.Round(x, MidpointRounding.ToEven)` over {-2.5→-2, -0.5→0, -3.5→-4, -1.5→-2} — providers: all — proof: red→green on base / SqlServer / SqlCe / Sybase paths; characterization on ClickHouse / Ydb unless red, in which case E-27 applies
- TO-12 `Sql.Right` matrix, **one query per row**, in a projection and in WHERE over server-side columns. In-range rows {("John",0), ("John",3), ("John",4), ("ab  ",2), (null,2), ("John",null)} expect the client value (`Sql.cs:641-648`), except Oracle ("John",0) → NULL. Out-of-range rows {("John",5), ("John",6), ("John",-1)} expect each provider's master result, a thrown error included (PostgreSQL `substring(s, 6, -1)` rejects a negative length — documented, unprobed), except Oracle ("John",6) → "John" (master: "n") — providers: all — proof: characterization on the in-range and out-of-range rows; red→green on Oracle ("John",6) and on any in-range row the master run shows wrong
- TO-13 `Sql.Right("John", 3)` constant-argument projection still emits SQL, as on master (PreferServerSide preserved, D-6) — providers: all — proof: control (mutation: adding a `CanBeEvaluatedOnClient` guard to the handler moves it client-side and the SQL assertion fails)
- TO-14 `Sql.Truncate(decimal?)` / `(double?)` and `Math.Truncate` over {2.7, -2.7, 0.5, -0.5, null}, plus `OrmBattleTests.MathTruncateTest` (`OrmBattleTests.cs:1730`) — providers: all — proof: characterization (SQLite/Sybase/Access emulation and PostgreSQL double move into translators; results must not change)
- TO-15 `Sql.Truncate(2.7m)` with constant arguments, in a projection and in WHERE: the projection evaluates client-side, and the WHERE carries a parameter where master inlined a literal (P10). Assert the results, and assert the SQL in both cells — providers: all — proof: control (mutation: removing the guard emits `Truncate` SQL in the projection)
- TO-16 Baselines diff scoping. SQL may change only for (a) Access Round; (b) every precision-null `Math.Round` / `Sql.RoundToEven` on every provider that reaches the base precision-null branch, directly or through `base.` (SqlServer / SqlCe / Sybase and all providers without an override); the CASE text changes whether or not the data hits the bug, so `Round1` / `Round2` / `Round7` / `Round8` (`MathFunctionTests.cs:257-272,328-343`) diff there; (c) Oracle `Sql.Right`; (d) `Sql.Truncate` constant-argument WHERE; (e) the new tests. Zero diff for `Pow`, `Truncate1` / `Truncate2`, `Right` / `RightInSelect`, the precision forms of `Round3`..`Round15`, and Firebird / PostgreSQL / SapHana `Sql.Round*` — providers: all (CI test-all) — proof: characterization
- TO-17 `StringFunctionTests.Stuff1` (`StringFunctionTests.cs:1016`) plus the existing `string.Insert` / `string.Remove` tests unchanged on all providers — providers: all — proof: characterization

Members not separately exercised: a direct `Sql.Power(double?,double?)` call — reached via `Math.Pow` in TO-6; its path is unchanged.

## P9 Verification gates

- G-01: — (pending) `/test` runs of TO-1..TO-4 (Tests.Analyzers.Internal) and TO-6..TO-17 (local: SQLite, Firebird, PostgreSQL, Oracle, SqlCe, Access, DuckDB, MySql, SqlServer — each ≤1000 tests; containers started only after asking), with red runs on master recorded before each fix
- G-02: — (pending) baselines diff reviewed against TO-16's scoping; TO-5's real-tree site list recorded here
- G-03: — (pending) `PublicAPI.Unshipped.txt` rows for new virtuals / overrides / nested classes (E-23); XML docs on new public members
- G-04: — (pending) `/api-baselines` only if a non-Internal surface moves — expected n/a (attribute removal changes no signature)
- G-05: — (pending) `dotnet build Source/LinqToDB/LinqToDB.csproj -c Release -f netstandard2.0` and `-f net462`
- G-06: — (pending)
- G-07: — (pending)
- G-08: — (pending) base `TranslateRoundToEven` fix, the `Sql.Round*` virtual split and the base `Right`/`Truncate` registrations proven by TO-7, TO-9, TO-11, TO-12, TO-14 across all providers (CI test-all)
- G-09: — (pending) `/code-review` or `/review-pr` on the branch diff before the PR opens; plus Release builds of `Source/LinqToDB -f net10.0` and `Tests/Tests.Analyzers.Internal` (analyzers, XML docs)

## P10 Adjudicated (M/L)

- `Sql.RoundToEven(double)` on Firebird keeps the map's `Decimal(18,10)` range (`|v| ≥ 1e8` may overflow) — pre-existing behaviour, preserved by the faithful port (D-5, U-9).
- `Math.Round(double, p)` ToEven on PostgreSQL keeps its `decimal` cast (`PostgreSQLMemberTranslator.cs:273-295`) and therefore decimal semantics on residue doubles — pre-existing; required because PostgreSQL has no `round(double precision, int)` (documented, unprobed); TO-9 records the master value.
- `Sql.Right` with n < 0 or n > len keeps each engine's own answer on providers whose emulation is not rewritten (generic RIGHT, SQLite, ClickHouse, Ydb), and the map formula's answer on SqlCe / Informix / PostgreSQL — pre-existing; TO-12 records the values.
- `Sql.Truncate` client-evaluable constant calls become a parameter instead of an inlined literal (WHERE), and `LinqOptions.PreferClientCalculation` no longer pulls `Sql.Truncate` client-side — inherent to translator-only members (U-6); same trade-off as #5544 / #5515; pinned by TO-15.
- `Expressions.AccessRound(double?,int?)` / `(decimal?,int?)` become unused internally but are shipped public API (`PublicAPI.Shipped.txt:15016-15017`) and stay.
- `Math.Round` SQL changes on Access and on base-ToEven providers (precision-null branch) — intended defect fixes (D-5, user decision 5).
- `analyzer-own-perf-baseline.json` and KB tables are not updated on this branch — skill-driven artifacts.

## P11 Amendments (M/L)

- A-1 (2026-10-25, master measurements + user decisions)
  - **Measured on master** (16 providers, YDB unavailable locally: port 2136 blocked).
    - TO-5's real-tree build reports exactly the predicted 16 × 0007 and 4 × 0008, and no 0009.
    - Projected `Math.Round` / `Sql.Round*` over columns are mostly evaluated on the client unless wrapped in `Sql.AsSql`, so the new server-translation tests wrap every call. Separate "on client" cells cover the client path.
    - Confirmed: the base ToEven precision-null bug (-2.5 → -3, -0.5 → -1) on 14/16 providers, all but Access and ClickHouse.
    - Confirmed: the Access AwayFromZero `Int` bug (-2.4 / -2.0 → -3).
    - Confirmed: the Oracle `Right('John', 6)` → `'n'`.
    - New defect: on the client path, the map expansions `(decimal)v!` crash for null inputs — `Sql.RoundToEven(double?)` on Firebird / PostgreSQL / SapHana and `Sql.Truncate(double?)` on PostgreSQL. The port fixes it, and `SqlRoundDoubleOverloadsOnClient` plus `SqlTruncateOverloads`' client cells are red→green.
    - New, pre-existing: MySQL and ClickHouse round doubles half-to-even (2.5 → 2), so `Math.Round(double, AwayFromZero)` and `Sql.Round(double)` are wrong there.
    - New, engine limit: DuckDB rejects `ROUND(DECIMAL, <column>)`.
    - Engine semantics: Sybase `RIGHT(s, 0)` returns NULL.
    - `AssertQuery`'s expected side applies the provider's map expansions too, so Right/Round master reds on mapped providers are partly expected-side artifacts.
  - **User decisions:**
    - Fix MySQL / ClickHouse double AwayFromZero here: a sign-symmetric `SIGN(v) * FLOOR(ABS(v) * 10^p + 0.5) / 10^p` for non-decimal values, in the shared `TranslateRoundAwayFromZero` override. `Sql.Round*` inherits it through the D-5 default delegation.
    - Gate DuckDB's column-precision decimal cell with a throws gate.
    - Treat Sybase `n = 0` as engine semantics: the row is left out for Sybase, as for Oracle.
    - U-11 is resolved by the master run: Access native `Round` is banker's (`Math.Round` ToEven rows were correct on both drivers), so Access ToEven emits native `Round`.
  - re-derives: P4 (U-11), P5 (D-5: MySQL / ClickHouse arm), P6 (E-16, E-21 widened; E-24, E-25 test shapes), P8 (TO-7, TO-8, TO-9, TO-10, TO-11, TO-12, TO-14), P10 (Sybase / DuckDB lines)
  - conventions (A-1): `testing.md` → *Test layout* and *A narrowed provider set is a claim*, embedded.
- A-2 (2026-10-25, post-change runs; user accepted all three items below)
  - The base ToEven midpoint now uses `ROUND(v / 2, 0) * 2` instead of a MOD-based branch. Measured: Sybase decimal `FLOOR(v) % 2 = 0` was false for -4, and master had hidden it behind `ROUND`.
  - DB2 rounds doubles half-to-even too (0.125 @2 → 0.12, measured), so it gets the same magnitude override as MySQL / ClickHouse, adding a `TranslateRoundAwayFromZero` override to E-19.
  - Informix `RIGHT(s, 0)` returns NULL: engine semantics, so the row is left out, as for Oracle / Sybase.
  - Access cannot type a function result over a NULL argument (OleDb "could not determine the value", ODBC "data type mismatch"; master the same): its null rows are left out of the Round and Right tests.
  - Result: 16 local providers green on `MathFunctionTests` plus the `StringFunctionTests` Right / Stuff / Insert / Remove tests (2195 runs, 0 failures; YDB not local). Release `Source/LinqToDB -f net10.0`: clean, no LINQ2DB0007-0009. Commits `486aa1257`, `b36dfaaa9`, `7e1c4293f` (local, unpushed).
  - re-derives: P6 (E-19), P10 (Informix / Access lines)
  - conventions: `testing.md` → *Test layout* and *A narrowed provider set is a claim*, re-embedded. Each new narrowing carries its measured reason at the data. Swept `git diff origin/master -- Tests/`, with the new tests in the working tree: each narrowing carries a measured reason (`RightLongerThanString` Oracle-only = the clamp; `MathRoundResidueDoubleKeepsDoubleRoute` PostgreSQL-only = the mutation target; DuckDB throws gate = engine limit).

## P12 Critic verdict (M/L)

**Current verdict: weak** — round 2. Its seven objections are addressed in place and have not been re-attacked since.

Round 1 (`plan-critic`, model `fable`, 2026-10-24): **refuted**. The census stands: the critic independently re-derived 16 map lines / 9 keys of registry overlap and 4 attribute shadows, and found no false positive on the kept chains. Its objections, and what changed:
1. **SC-9 (Right client contract on every provider) contradicted D-6 / SC-11 (unchanged SQL).**
   - Generic `RIGHT`, SQLite and Ydb cannot give client answers for n<0 / n>len.
   - Fixed: SC-11 now scopes the client contract to in-range and null inputs. Out-of-range rows assert the master result (P10), except the Oracle clamp.
2. **D-5's PostgreSQL AwayFromZero port would move float8-correct `Math.Round` onto numeric** (1.15 @1: C# 1.1, numeric 1.2), and TO-8's values could not separate the routes.
   - Escalated to the user, whose diagnosis was that `Math.Round` (C#) and `Sql.Round` (database) are conflated in one virtual.
   - Fixed: D-5 now splits the virtuals and ports into the `Sql`-specific ones.
   - TO-8 asserts port faithfulness, including residue rows.
   - TO-9 is a new control that `Math.Round` is untouched, with a `separates:` line.
3. **U-10's formula with SqlCe raw `LEN` reproduced the trailing-blank defect.** Fixed: U-10 builds the length from the same node `string.Length` produces, so SqlCe's visitor rewrites it to `LEN(s+'.')-1`, as the map path does today.
4. **`Expressions.AccessRound` becomes dead shipped API.** Fixed: added a P7 row and a P10 line.
5. **The P7 claim about the base ToEven fix reaching overrides only via `base.` was false for ClickHouse / Ydb.** Fixed: the P7 row now names both, and E-27 is a conditional edit-point if TO-11 reddens there.
6. **The `Sql.Truncate` guard deviates from its siblings unannounced, and TO-15 lacked a WHERE cell.** Fixed: D-6 states the deviation and its reason, and TO-15 has projection and WHERE cells. `OrmBattleTests.MathTruncateTest` was added to TO-14.

Round 2 (same critic, same model): **weak**. The D-5 split survived. In the critic's words, the base-forwarding `TranslateSql*` virtuals leave every non-overriding provider byte-identical, and TO-9's mutation is a real separator. Seven objections; all addressed in place, **unattacked since**:
1. **Oracle `Sql.Right` expectations.** The critic computed "master" from `OracleRightBuilder`, but that builder is dead: master's effective Oracle path is the map formula at `:759`. Against that, the clamp changes only ("John",6), which is now stated in SC-11. Its valid half is taken: Oracle n=0 yields NULL (`''` is NULL), now explicit in SC-11 and TO-12.
2. **TO-16's zero-diff list claimed `Round1`..`Round15`.** The base precision-null CASE text changes on every provider that reaches it. TO-16 is rescoped: (b) now names all base-path providers and `Round1` / `2` / `7` / `8`.
3. **The PostgreSQL `TranslateSqlRoundAwayFromZero` cast would also move the unmapped 1-arg `Sql.Round(double?)`.** The cast now applies only with a precision argument, and TO-8 adds the 1-arg row.
4. **TO-8's Access `Sql.Round(double?,int?)` cell contradicted D-5,** and the Access ToEven port was ambiguous for null precision. The cell is dropped. The port is specified as `Round(v, 0)` for null precision, as `AccessRound` produced.
5. **U-11's fallback spelled `FLOOR`, which Access lacks.** It now spells `Int`. SC-7 now says what holds if native `Round` is not banker's.
6. **TO-12's PostgreSQL n<0 row throws.** TO-12 is now one query per row, and records an error as the master answer.
7. **TO-7's null-precision row must come from a column cell,** because a literal is coerced away. Now explicit.
