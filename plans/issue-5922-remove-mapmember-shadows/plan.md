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
- SC-4 `LINQ2DB0009` reports model drift (no entries collected, an entry whose section cannot be resolved, (A-7) no registrations collected or the attribute type not found, (A-8) a table entry keyed by a held expression or a `Register*` pattern naming no member) instead of going silent. → TO-4
- SC-5 Before any removal, a Release build of the real `Source/LinqToDB` reports exactly the 16 `LINQ2DB0007` and 4 `LINQ2DB0008` sites in `P1`, and no `LINQ2DB0009`. After the change the build is clean. → TO-5
- SC-6 `Math.Pow` routes through `MathMemberTranslatorBase.cs:104` only, with no result change and an unchanged SQL baseline. → TO-6
- SC-7 `Sql.Round*` / `Sql.RoundToEven*` results on each provider are unchanged by the port. Firebird, PostgreSQL and SapHana keep their `decimal` round-trip for `double`, now produced by the `Sql`-specific override. On binary-exact inputs (±0.5, ±2.5, ±3.5, 0.125 @2, -0.375 @2, nulls), every provider equals the client `Sql.*` body (`Sql.cs:1137-1168`), with two exceptions. Access `Sql.Round*` moves to the corrected semantics (SC-9). Access `Sql.RoundToEven*` keeps native `Round` (the map's semantics): it is asserted equal to the client only if TO-10 shows native `Round` is banker's on both drivers; otherwise it is asserted equal to master and recorded in P10. → TO-7, TO-8, TO-9
- SC-8 `Math.Round(double…)` results and SQL do not change because of the `Sql.Round*` port: the virtuals it reaches are unchanged except for the SC-9 / SC-10 / SC-15 fixes. → TO-9, TO-16
- SC-9 Access `Math.Round(x, AwayFromZero)` and `Sql.Round*` are sign-symmetric, and Access `Sql.RoundToEven*` keeps the map's native `Round(v[,p])` semantics. → TO-10
- SC-10 Base `TranslateRoundToEven` rounds negative midpoints to even: -2.5→-2, -0.5→0, -3.5→-4. → TO-11
- SC-11 `Sql.Right` is translator-only, with no attribute, builder or map entry left. Every provider equals the client for in-range and null inputs: 0 ≤ n ≤ len, a null string, a null length, trailing blanks. On Oracle, n = 0 yields NULL, because Oracle stores `''` as NULL. Out-of-range n (n < 0, n > len) keeps each provider's current answer, an error included, except Oracle and SQLite (A-5) n ≥ len+2. Against master's effective Oracle path, the map formula `Substr(s, len-n+1, n)` at `Expressions.cs:759` (not the dead builder), the clamp changes only that cell, `('John',6)`: `'n'` → `'John'`; SQLite's `SUBSTRING(s, LENGTH(s) - n + 1)` gives the same `'n'` and is clamped the same way (A-5). On Ydb a NULL n yields NULL (A-5). → TO-12, TO-13
- SC-12 `Sql.Truncate(decimal?)` / `(double?)` are translator-only and equal the client for positive and negative fractions and null on every provider, with no attribute or map entry left. → TO-14, TO-15
- SC-13 Column-argument SQL is unchanged wherever no defect is fixed. That covers `Sql.Right` on generic-RIGHT / ClickHouse / PostgreSQL / Informix / SqlCe, and on Ydb for a non-nullable length (A-5: SQLite gains the `MAX(…, 1)` clamp on every call, Ydb a `CASE WHEN n IS NULL` for a nullable length) and `Sql.Round*` on Firebird / PostgreSQL / SapHana. `Sql.Truncate` over a column keeps its results but not its SQL text (A-7, measured on the baselines branch). → TO-16
- SC-14 `Sql.Stuff` / `string.Insert` / `string.Remove` (via `AltStuff` → `Sql.Right`) keep their results on all providers. → TO-17
- SC-15 (A-1, A-2) On MySQL, ClickHouse and DB2, `Math.Round(double, AwayFromZero)` and `Sql.Round(double…)` round a midpoint away from zero (master: to even). Residue doubles keep C#'s answer, and a precision < 0 or ≥ 10 keeps master's native `ROUND(v, p)` answer. → TO-7, TO-9, TO-19, TO-16 (f)
- SC-16 (A-3) The base precision-null ToEven emulation keeps a `decimal` exact above 2^53: no arm leaves the value's type. → TO-18

## P3 Constraints & anti-goals (M/L)

**Must not change:**
- **Results of any query that is correct today.** SQL text may change only where `P5` says so: the Access and base-ToEven defect fixes, the MySQL / ClickHouse / DB2 double AwayFromZero fix (A-1, A-2), the Oracle `Right` fix, the constant-argument policy of D-6, and the `Sql.Right` / `Sql.Truncate` providers whose emulation moves. The last keep their results; their SQL text is scoped by SC-13 and TO-16 (A-7).
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
- U-11 Access native `Round` midpoint semantics — resolved-by probe (A-1): native `Round` is banker's on ACE OleDb and ODBC (master's `Math.Round` ToEven rows were correct on both), so the Access ToEven override emits native `Round`. Original framing: the map's `Sql.RoundToEven*` → `AccessRound` → `Round(v[,p])` is ported as-is into the `Sql`-specific override, so it is unchanged whatever `Round` does. For `Math.Round(…, ToEven)`, the Access override emits native `Round` only if TO-10's master run shows banker's rounding on ACE OleDb and ODBC. Otherwise it emits the corrected CASE spelled with `Int` instead of `FLOOR`: Access has no `FLOOR`, and its convert visitor renames only `%` → `MOD` (`AccessSqlExpressionConvertVisitor.cs:531`), as the existing override already does at `AccessMemberTranslator.cs:273`.
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
    - Access `TranslateRoundAwayFromZero` becomes sign-symmetric. As shipped (A-5): with `m = Abs(v)*10^p`, `Sgn(v)*(Int(m) + Int((m - Int(m))*2))/10^p`, without the `/10^p` at p=0. `Int(m + 0.5)` rounds in the addition for doubles, and the base's exact-midpoint test does not port, because Access compares a double with the literal `0.5` imprecisely (measured, A-5).
    - Access `TranslateRoundToEven` follows U-11 and drops the dead `IIf` (`:237`).
    - Base `TranslateRoundToEven`, precision-null branch, as shipped (A-2, A-3): `CASE WHEN v - FLOOR(v) = 0.5 THEN ROUND(v * 0.5, 0) * 2 ELSE ROUND(v, 0) END`. Half a midpoint is never a midpoint, so the arm needs no tie rule and no `MOD` (Sybase's decimal `FLOOR(v) % 2` was wrong for -4). It multiplies rather than divides, because DuckDB divides a DECIMAL into a DOUBLE (measured, A-3).
    - MySQL, ClickHouse and DB2 (A-1, A-2): their `ROUND` on a double rounds a midpoint to even (measured), so the shared `TranslateRoundAwayFromZero` override emits `sign(v) * floor(abs(v) * power(10, p) + 0.5) / power(10, p)` (`RoundAwayFromZeroByMagnitude`) for a non-`decimal` CLR value. `Math.Round` gets it as a defect fix; `Sql.Round*` inherits it through the default `TranslateSqlRoundAwayFromZero` delegation.
  - Delete the map entries `:791-792,818-820,904-923,944-945`.
- **rejected:** port the round-trips into the shared virtuals. That also moves `Math.Round(double…)` to decimal semantics and adds Firebird's 1e8 overflow to it. (A-6: the "1.15 @1 AwayFromZero: C# 1.1, decimal 1.2" example was false. .NET scales 1.15 to the exact tie 11.5 and returns 1.2. On PostgreSQL's away-from-zero path the cast changes nothing either, because `POWER(10, p)` returns a double.)
- **rejected:** a `methodCall.Method` check inside the shared virtuals. Same effect as separate virtuals, but hidden from providers and reviewers.
- **rejected:** delete the maps without porting. That changes `Sql.Round*(double)` results on Firebird / PostgreSQL / SapHana.
- **why this:** the user's diagnosis. Separate virtuals make the semantics split explicit, faithful ports keep every `Sql.Round*` result, and `Math.Round` changes only through the stated defect fixes.
- **failure mode of the choice:** two virtuals per mode is new surface (`PublicAPI.Unshipped.txt`), and a provider that overrides only the shared virtual silently changes both paths, as today. Also, `Sql.RoundToEven(double)` on Firebird keeps the map's `Decimal(18,10)` range (U-9), which is pre-existing. The MySQL / ClickHouse / DB2 override gates on the CLR type, not the stored type (P10).

### D-6 — `Sql.Right` / `Sql.Truncate`: base registration + virtual + per-provider override, attribute semantics preserved

- **chosen:**
  - `StringMemberTranslatorBase` registers `Sql.Right(string?,int?)`, and `MathMemberTranslatorBase` registers both `Sql.Truncate` overloads. Each dispatches to a new protected virtual, `TranslateRight` / `TranslateTruncate`.
  - The base virtuals emit what the default attributes emitted: `RIGHT(s,n)` and `Truncate(x)`, via `factory.Function` typed from the CLR return type (U-7).
  - **Right overrides:**
    - SQLite, ClickHouse and Ydb reproduce their attributes (`Sql.cs:636,637,640`), with two defect fixes (A-5): SQLite clamps the start, `SUBSTRING(s, MAX(LENGTH(s) - n + 1, 1))`, and Ydb returns NULL for a NULL length, because `Unicode::Substring` reads a NULL count as "to the end".
    - SqlCe, Informix and PostgreSQL port the map formula (U-10).
    - Oracle ports it with a clamped start (U-10).
  - **Truncate overrides:**
    - Ydb, SqlServer, DB2, Informix, Oracle, Firebird, DuckDB, MySql, SqlCe and SapHana reproduce their attributes.
    - PostgreSQL reproduces its decimal attribute and keeps map `:826`'s `double`→`decimal` cast for `double`.
    - SQLite, Sybase and Access reproduce the Floor/Ceiling maps (`:841-842,874-875,928-929`).
    - New math translators for SQLite, Informix, DuckDB and MySql.
  - **Client-evaluation policy:**
    - The `Sql.Right` handler has **no** client-evaluable guard, so it always goes to SQL, mirroring `PreferServerSide=true` (U-6) as `TranslateAbsMethod` does (`MathMemberTranslatorBase.cs:141-152`). An argument it cannot translate returns null rather than an error expression, keeping the attribute path's client fallback (A-4).
    - The `Sql.Truncate` handler returns null whenever `CanBeEvaluatedOnClient(methodCall)`, in every translation mode. That deliberately deviates from its siblings, which gate on `TranslationFlags.Expression &&` (`MathMemberTranslatorBase.cs:200,255,289,323`): it mirrors `HandleExtension`'s unconditional back-off for `PreferServerSide=false` (`ExpressionBuildVisitor.cs:1246`). The handler gets a one-line comment saying so.
  - Delete every `Sql.Right` / `Sql.Truncate` attribute (`Sql.cs:635-640,1199-1227`), `OracleRightBuilder` / `SqlCeRightBuilder` (`:592-633`), and the maps `:689,723,759,813,826,841-842,874-875,928-929`.
- **rejected:** a virtual that returns null by default, so non-overriding providers fall through to their attributes. It leaves both mechanisms per member (user decision 3).
- **rejected:** registering only in provider translators — a new pattern (U-2).
- **rejected:** a full client contract for out-of-range `n` on every provider. It changes `RIGHT` SQL on every engine for inputs nobody reported (`P3` anti-goal).
- **why this:** follows the #5544 / #5515 precedent (`5999b4f4e`, `c35da70f6`), and keeps column-argument results; the SQL text changes as TO-16 records (A-7: the original "byte-identical" claim was unmeasured and false for `Sql.Truncate`).
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
- E-11 `Source/LinqToDB/Internal/DataProvider/Access/Translation/AccessMemberTranslator.cs` — `TranslateSqlRoundToEven` (native `Round`); fix `TranslateRoundAwayFromZero` (A-5: `Int(m) + Int((m - Int(m)) * 2)`) / `TranslateRoundToEven`; `TranslateTruncate` (Floor/Ceiling).
- E-12 `Source/LinqToDB/Internal/DataProvider/Oracle/Translation/OracleMemberTranslator.cs` — `TranslateRight` (clamped formula), `TranslateTruncate`.
- E-13 `Source/LinqToDB/Internal/DataProvider/SqlCe/Translation/SqlCeMemberTranslator.cs` — `TranslateRight` (map formula over the string-length node), `TranslateTruncate`.
- E-14 `Source/LinqToDB/Internal/DataProvider/Informix/Translation/InformixMemberTranslator.cs` — `TranslateRight`; new math translator with `TranslateTruncate`.
- E-15 `Source/LinqToDB/Internal/DataProvider/SQLite/Translation/SQLiteMemberTranslator.cs` — `TranslateRight` (A-5: start clamped with `MAX(…, 1)`); new math translator with `TranslateTruncate`.
- E-16 `Source/LinqToDB/Internal/DataProvider/ClickHouse/Translation/ClickHouseMemberTranslator.cs` — `TranslateRight` (`rightUTF8`); `TranslateRoundAwayFromZero` sign-symmetric for non-decimal values (A-1).
- E-17 `Source/LinqToDB/Internal/DataProvider/Ydb/Translation/YdbMemberTranslator.cs` — `TranslateRight` (A-5: NULL for a NULL length), `TranslateTruncate`.
- E-18 `Source/LinqToDB/Internal/DataProvider/SqlServer/Translation/SqlServerMemberTranslator.cs` — `TranslateTruncate` (`Round(x,0,1)`).
- E-19 `Source/LinqToDB/Internal/DataProvider/DB2/Translation/DB2MemberTranslator.cs` — `TranslateTruncate`; `TranslateRoundAwayFromZero` sign-symmetric for non-decimal values (A-2).
- E-20 `Source/LinqToDB/Internal/DataProvider/DuckDB/Translation/DuckDBMemberTranslator.cs` — new math translator with `TranslateTruncate`.
- E-21 `Source/LinqToDB/Internal/DataProvider/MySql/Translation/MySqlMemberTranslator.cs` — new math translator with `TranslateTruncate`, and `TranslateRoundAwayFromZero` sign-symmetric for non-decimal values (A-1).
- E-22 `Source/LinqToDB/Internal/DataProvider/Sybase/Translation/SybaseMemberTranslator.cs` — `TranslateTruncate` (Floor/Ceiling).
- E-23 `Source/LinqToDB/PublicAPI/PublicAPI.Unshipped.txt` — rows for the new virtuals, overrides and nested translator classes.
- E-24 `Tests/Linq/Linq/MathFunctionTests.cs` — new Round / RoundToEven / Truncate tests (TO-7..TO-11, TO-14, TO-15, TO-18, TO-19); A-5: `SqlRoundDoubleWidePrecision` widened to AllAccess, `SqlRoundDecimalOverloads` gated `[ActiveIssue(6055)]` on `YDB.LinqService`.
- E-25 `Tests/Linq/Linq/StringFunctionTests.cs` — new Right tests (TO-12, TO-13, TO-20); A-5: `RightLongerThanString` widened to AllSQLite.
- E-26 `Tests/Model/*` — a shared rounding / string-edge values model and table, only if no existing model carries negative / tie / null `decimal`+`double` values (`test-writer` picks the existing one first).
- E-27 `Source/LinqToDB/Internal/DataProvider/ClickHouse/Translation/ClickHouseMemberTranslator.cs`, `Source/LinqToDB/Internal/DataProvider/Ydb/Translation/YdbMemberTranslator.cs` — conditional: their own ToEven overrides, fixed here only if TO-11's master run reddens there (`P7` row).

## P7 Impact map (M/L)

- `Expressions.cs` registry shadows (9 keys / 16 lines, `P1`) — searched `Register(Method|Member|Constructor|Replacement|Binary|Unary)` and `\.Register…\s*<` across `Source/**/*.cs`, keyed per U-1; critic re-derived 16/9 — covered by E-4, E-6, E-8, E-9, E-10, E-11
- `Expressions.cs` attribute shadows (4, `P1`) — searched every mapped member's `ExpressionAttribute`-derived attributes against section configs; critic re-derived 4 — covered by E-4, E-5
- Shared Round virtuals and their two caller families: `Math.Round` → `TranslateMathRoundMethod` (`MathMemberTranslatorBase.cs:198-251` → `:240,:243`) and `Sql.Round*` → `:253`, `:287` (`→ :279, :313`) — covered by E-6 (split per D-5)
- Provider overrides of the shared Round virtuals: PostgreSQL `:273,297`; Access `:216,254`; SqlServer `:196`, SqlCe `:253`, Sybase `:212-219` (all `base.`-reaching); ClickHouse `:261-277` and Ydb `:723-725` (own implementations) — searched `override .*TranslateRound(ToEven|AwayFromZero)` across `Source/` — PostgreSQL/Access covered by E-8/E-11; SqlServer/SqlCe/Sybase reach the base fix through `base.` (TO-11 covers them); ClickHouse/Ydb covered by E-27 if red, else characterization. New `TranslateRoundAwayFromZero` overrides on MySQL, ClickHouse and DB2 (A-1, A-2) call `RoundAwayFromZeroByMagnitude` for non-`decimal` values and `base.` otherwise — covered by E-16, E-19, E-21 (TO-7, TO-9, TO-19, `Round6`)
- `Sql.Right` / `Sql.Truncate` producers: `AltStuff` (`Expressions.cs:550`) → `Sql.Right`; `Math.Truncate` (`:642-643`) → `Sql.Truncate`; nothing else in `Source/` (searched `Sql\.Right`, `Sql\.Truncate`, `"RIGHT"`) — covered by E-6, E-7 (+ TO-14, TO-17)
- `Sql.Stuff` → `AltStuff` chain on nine providers (`Expressions.cs:707,724,760,781,800,814,834,883,946`) — covered by E-4 (`AltStuff` entry kept) + TO-17
- Removed-attribute flag consumers (`ExpressionBuildVisitor.cs:937,1246,2374,2383-2386,3082`; `ExpressionTreeOptimizationContext.cs:404-405`; `ExpressionBuilder.QueryBuilder.cs:529-597`) — covered by E-6, E-7 (D-6 policy); residue in P10
- `TranslatePow` overrides newly reached by `Math.Pow`: Access `AccessMemberTranslator.cs:316`, Ydb `YdbMemberTranslator.cs:683` — covered by E-4 + TO-6 (they already serve `Sql.Power`)
- `Expressions.AccessRound` ×2 (`Expressions.cs:1186,1200`; shipped `PublicAPI.Shipped.txt:15016-15017`) — searched `AccessRound|AccessInt` across `Source/`: only callers are the deleted `:904-905,920-923` — out-of-scope (shipped public API kept; P10)
- Remote/LinqService translator activation (`LinqService.cs:94`, `RemoteDataContextBase.cs:157-165`) — out-of-scope (unchanged mechanism; new translators keep parameterless ctors; `[DataSources]` runs `.LinqService` contexts)
- Tests that narrow providers on the touched paths: `Round6` (`[DataSources(AllClickHouse)]`, `MathFunctionTests.cs:319`, "Double use bankers rounding" — the defect SC-15 fixes; exclusion dropped in A-3), `Round9` / `Round12` (`AllSQLite`, `:346,380`), `PowDecimal*` (`AllSybase`, `:248,1600,1623`) — searched `DataSources\(` in `MathFunctionTests.cs` / `StringFunctionTests.cs` — covered by E-24 (re-run each excluded provider after the fix; drop or re-justify per `testing.md` → *A narrowed provider set is a claim*)
- Existing `Math.Truncate` / `Sql.Right` consumers: `MathFunctionTests.cs:1821-1836`, `StringFunctionTests.cs:972-985,1016-1089`, `OrmBattleTests.cs:1730-1736` (WHERE, column arg) — covered by E-24, E-25 (TO-14, TO-16, TO-17 re-run them)
- (A-5) Existing consumers whose SQLite / Ydb `Sql.Right` SQL now moves: `StringFunctionTests.Right` (`:970`, WHERE), `RightInSelect` (`:978`), and the `AltStuff` → `Sql.Right` chain behind `Stuff1` (`:1123`), `Insert` (`:1175`) and `Remove` (`:1183,1191`) on the providers whose `Sql.Stuff` map reaches `AltStuff`. Searched `git grep -n -E "Sql\.Right|\.Insert\(|\.Remove\(|Sql\.Stuff" origin/pr/6151 -- Tests/Linq/Linq/StringFunctionTests.cs`. Covered by E-15, E-17 plus TO-16 (c) and TO-17. The Ydb CASE appears only for a nullable length, and every listed call passes a constant or a non-nullable length (reasoned from the call sites).
- KB tables (`CODEGEN/INDEX.md:50-52,78-80,102,159`; `PROV-ACCESS/INDEX.md:254`) — deferred: KB is skill-driven (`/kb-refresh`)
- `.claude/docs/analyzer-own-perf-baseline.json` — deferred: refreshed by `/profile-analyzers rules`
- `PublicAPI.Shipped.txt` existing virtual rows (`:16347`, `:16392`) — covered by E-23 (Unshipped only)

## P8 Test obligations (M/L)

- TO-1 `MemberMapShadowAnalyzerTests`: exact `Math.Pow` mirror (common `M` + base `RegisterMethod`) → 0007 on the `M(...)` span; positive arms for `RegisterMember` (property), `RegisterConstructor`, `RegisterReplacement` (A-4), an instance receiver type, and `isGenericTypeMatch: true` vs a constructed generic entry; silent controls for a different overload (`Math.Round(decimal)` registered, `Math.Round(double)` mapped), the `string.Compare`→`CompareTo` and `ConvertTo<string>.From(Guid)`→`ToString` chains, an unrelated `M`, and an unrelated `RegisterMethod` in another namespace — providers: n/a (analyzer) — proof: red→green (fixtures first; an empty analyzer fails every positive arm)
- TO-2 Section scoping: provider entry vs base-namespace registration → 0007; vs own `…DataProvider.<P>` registration → 0007; vs another provider's → silent; `SQLite.MS` entry vs `…DataProvider.SQLite` registration → 0007; field-initializer entry paired by `{ "", field }` → common — providers: n/a — proof: red→green
- TO-3 0008: provider entry vs same-config attribute → 0008; vs `P.sub` config → 0008; vs generic and vs other-provider attribute → silent; common entry vs generic attribute → 0008 — providers: n/a — proof: red→green
- TO-4 0009: an `M(...)` inside a helper method (section unresolvable) → 0009; an `Expressions` type with no entries → 0009; a `Register*` pattern held in a variable → 0009, while a forwarding helper inside `TranslationRegistrationExtensions` stays silent (A-4); (A-7) no registrations, a renamed `TranslationRegistrationExtensions` and a renamed `Sql.ExpressionAttribute` → 0009; (A-8) a table entry keyed by a held expression and a `Register*` lambda naming no member → 0009, and a parameterless `Expression<Action>` pattern is read as a registration (0007) — providers: n/a — proof: red→green
- TO-5 Real tree: Release build of `Source/LinqToDB` (or `-c Testing -p:RunAnalyzersDuringBuild=true`) **before** E-4..E-22 reports exactly the 16 + 4 sites of `P1` and no 0009, recorded verbatim in P9 G-02; after the change, clean — providers: n/a — proof: red→green
- TO-6 `MathFunctionTests.Pow` (`MathFunctionTests.cs:238`, `[DataSources]`): unchanged result and unchanged SQL baseline — providers: all — proof: characterization
- TO-7 `Sql.Round*` / `Sql.RoundToEven*` binary-exact matrix, all eight overloads (`decimal?`/`double?` × with/without precision × Round/RoundToEven), over server-side column values {2.5, 3.5, -2.5, -3.5, -0.5, 0.125 @2, -0.375 @2, 2.4, -2.4, null value, null precision — a NULL **column** cell, never a literal `null`, which both wrappers coerce to no-precision (`MathMemberTranslatorBase.cs:276-277,310-311`)}; expected = client `Sql.*` bodies (`Sql.cs:1137-1168`); separates: the base ToEven bug (-2.5, -0.5 on base providers), Access AwayFromZero (-2.4) and the MySQL / ClickHouse / DB2 double midpoint (2.5, 0.125 @2) from correct emulations — providers: all `[DataSources]`; Access drops its null-value and null-precision rows (P10); DuckDB's decimal column-precision cell is a throws gate (P10) — proof: red→green on Access, the base-ToEven providers (14/16 measured, all but Access and ClickHouse) and the MySQL / ClickHouse / DB2 double cells; characterization elsewhere
- TO-8 Port faithfulness: on TO-7's values plus residue doubles {1.15 @1, 2.675 @2}, results are identical before (map) and after (`Sql`-specific override) — and SQL too, except the precision-null `Sql.RoundToEven(double?)` on Firebird / SapHana, whose cast-wrapped value now passes through the rewritten base CASE (TO-16 (b) owns that SQL) — for `Sql.RoundToEven(double?)` and `Sql.RoundToEven(double?,int?)` on Firebird / PostgreSQL / SapHana / Access, for `Sql.Round(double?,int?)` on PostgreSQL, and for the unmapped 1-arg `Sql.Round(double?)` on PostgreSQL (which must stay on float8). The residue rows assert the **master** result, not C#. Access `Sql.Round*` is not here: it changes by design (TO-7 / TO-10) — providers: AllFirebird, AllPostgreSQL, AllSapHana, AllAccess — proof: characterization
- TO-9 `Math.Round` isolation: `Math.Round(double, int, AwayFromZero)` and `Math.Round(double, int)` over residue doubles {1.15 @1, 2.675 @2} return C#'s result (the port must not reach `Math.Round`, and the magnitude formula of SC-15 must not turn a scaled residue into a tie) — providers: as implemented, `MathRoundResidueDoubleKeepsDoubleRoute` on AllPostgreSQL (the mutation target) and AllMySql / AllClickHouse / AllDB2 (the magnitude providers, A-3) — proof: characterization (A-6). The planned control cannot be built. With `Math.Round` routed through `TranslateSqlRoundAwayFromZero`, the PostgreSQL SQL carries `r."F"::decimal`, yet `FLOOR(v * POWER(10, p) + 0.5) / POWER(10, p)` is computed in double, because `POWER(10, int)` resolves to `power(double precision, double precision)`. The mutant was measured green on PostgreSQL.18 with the rows {1.15 @1, 2.675 @2, 1.005 @2}. As shipped, `MathRoundResidueDoubleKeepsDoubleRoute` checks the away-from-zero agreement with C#, and `MathRoundResidueDoubleToEven` the to-even agreement, gated on #6263 for DB2 (split in A-8). (A-7) Those three rows were a sample: TO-21 is the separating control.
- TO-10 Access: `Math.Round(x, MidpointRounding.AwayFromZero)` and `Sql.Round(x)` over {-2.4, -2.0, -2.5, -3.5}; and `Math.Round(x, ToEven)` over {2.5, 3.5, -2.5}, asserting native `Round`'s banker's rounding, which the master run measured on ACE OleDb and ODBC (U-11) — providers: AllAccess — proof: red→green (master's `Int(v-0.5)` gives -3 for -2.4 and -2.0)
- TO-11 Base ToEven negatives: `Math.Round(x)` and `Math.Round(x, MidpointRounding.ToEven)` over {-2.5→-2, -0.5→0, -3.5→-4, -1.5→-2} — providers: all — proof: red→green on base / SqlServer / SqlCe / Sybase paths; characterization on ClickHouse / Ydb unless red, in which case E-27 applies
- TO-12 `Sql.Right` matrix, **one query per row**, in a projection and in WHERE over server-side columns. In-range rows {("John",0), ("John",3), ("John",4), ("ab  ",2), (null,2), ("John",null)} expect the client value (`Sql.cs:641-648`), except Oracle ("John",0) → NULL. Out-of-range rows {("John",5), ("John",6)} are carried only by `RightLongerThanString` on Oracle and SQLite. The planned ("John",-1) row and the other providers' out-of-range cells were not written (critic round 4; P10). Where present, they expect the provider's master result, except Oracle and SQLite ("John",6) → "John" (master: "n"; SQLite added by A-5, `RightLongerThanString`). Rows left out, each for a measured engine answer (P10): ("John",0) on Oracle, Sybase and Informix (NULL), and the null rows on Access — providers: all — proof: characterization on the in-range and out-of-range rows; red→green on Oracle and SQLite ("John",6), on Ydb ("John",null) (A-5: whole string before the fix, measured on `adf38a6a5` in both YDB contexts; master's attribute emitted the same `Unicode::Substring`, unprobed), and on any in-range row the master run shows wrong
- TO-13 `Sql.Right("John", 3)` constant-argument projection still emits SQL, as on master (PreferServerSide preserved, D-6) — providers: all — proof: control (mutation: adding a `CanBeEvaluatedOnClient` guard to the handler moves it client-side and the SQL assertion fails)
- TO-14 `Sql.Truncate(decimal?)` / `(double?)` and `Math.Truncate` over {2.7, -2.7, 0.5, -0.5, null}, plus `OrmBattleTests.MathTruncateTest` (`OrmBattleTests.cs:1730`) — providers: all — proof: characterization (SQLite/Sybase/Access emulation and PostgreSQL double move into translators; results must not change)
- TO-15 `Sql.Truncate(2.7m)` with constant arguments, in a projection and in WHERE: the projection evaluates client-side, and the WHERE carries a parameter where master inlined a literal (P10). Assert the results, and assert the SQL in both cells — providers: all — proof: control (mutation: removing the guard emits `Truncate` SQL in the projection). (A-6) The WHERE cell has no SQL assertion, and none can discriminate. With the guard removed, the SQL is still `WHERE [p].[PersonID] = 1` (measured, SQLite.MS): the comparison `Sql.Truncate(2.7m) == 2m` is folded on the client before any translator runs. So P10's "the WHERE carries a parameter" holds only where the call is not folded away whole.
- TO-16 Baselines diff scoping. SQL may change only for (a) Access Round; (b) every precision-null `Math.Round` / `Sql.RoundToEven` on every provider that reaches the base precision-null branch, directly or through `base.` (SqlServer / SqlCe / Sybase and all providers without an override); the CASE text changes whether or not the data hits the bug, so `Round1` / `Round2` / `Round7` / `Round8` (`MathFunctionTests.cs:257-272,328-343`) diff there; (c) Oracle and SQLite `Sql.Right` over a column, which includes `Right`, `RightInSelect`, `RightInRange` and `RightLongerThanString` there, and on SQLite also the `AltStuff` consumers `Stuff1`, `Insert` and `Remove2` (A-5; critic round 4; A-7 drops `Remove1`, measured unmodified). Ydb `Sql.Right` moves only with a nullable length (A-5). (d) `Sql.Truncate` constant-argument WHERE; (e) the new tests; (f) double `Math.Round(…, AwayFromZero)` / `Sql.Round(double…)` on MySQL / ClickHouse / DB2 (SC-15), which includes `Round6` there — the only pre-existing double-AwayFromZero test, now also run on ClickHouse. (g) (A-7) Column-argument `Truncate1` / `Truncate2` on every provider: alias `Value_1` → `c1` (118 files), MySQL-family `Truncate2` also loses parentheses (5), PostgreSQL `Truncate2` becomes a derived table with a `::Float` projection (13); results unchanged. (h) (A-8) Oracle decimal precision-null to-even: `0.5D` → `0.5` in each decimal cell (`ConvertTests.ConvertTo*`, decimal `Round1` / `Round7`, the `D` column of `MathRoundNegativeMidpoints`, `SqlRoundDecimalOverloads`, `MathRoundDecimalHeadroom`); double cells keep `0.5D`. (A-9) DuckDB's decimal precision-null to-even cells take the floor-parity form. Zero diff for `Pow`, `Right` / `RightInSelect` off Oracle and SQLite, the precision forms of `Round3`..`Round15`, and Firebird / PostgreSQL / SapHana `Sql.Round*` — providers: all (CI test-all) — proof: characterization
- TO-17 `StringFunctionTests.Stuff1` (`StringFunctionTests.cs:1016`) plus the existing `string.Insert` / `string.Remove` tests unchanged on all providers — providers: all — proof: characterization
- TO-18 (A-3) `MathRoundDecimalHeadroom`: `Math.Round(d)`, `Sql.RoundToEven(d)` and `Math.Round(d, AwayFromZero)` over a `decimal(18,1)` column {12345678901234567.3, 12345678901234565.5, 12345678901234566.5}; separates: a division in the midpoint arm (DuckDB DOUBLE) from an exact one — the `Away` column, which never divides, is the in-run control — providers: all but AllSQLite (REAL storage) and AllAccess (`Round` / `Int` return Double; master emits the same functions) — proof: red→green on DuckDB (measured: `12345678901234600` before the `* 0.5` change, exact after)
- TO-19 (A-3, A-4) `SqlRoundDoubleWidePrecision`: `Sql.Round(F, P)` over {(1234.5678, -1) → 1230, (1234.5678, 10) → 1234.5678, (0.5, 12) → 0.5, (0.49999999999999994, 0) → 0, (2^52 + 1, 0) → 2^52 + 1, (-2.5, 0) → -3}, expected values stated because the client cannot round to a negative precision; separates: an integer-typed `power(10, p)` (overflow at p ≥ 10, zero at p < 0) from a double one, and an exact midpoint test from `floor(m + 0.5)`, whose addition rounds the two edge rows — providers: AllMySql, AllClickHouse, AllDB2, AllAccess (A-5: Access's `Int(m + 0.5)` moved both edge rows, per `bdc4a2ff7`'s message; the imprecise `< 0.5` comparison was probed on ACE OLE DB and ODBC) — proof: characterization against master's native `ROUND(v, p)`; red→green on any of the three that fails before the base is typed, and on Access for the two edge rows
- TO-20 (A-4) `RightUntranslatableArgumentIsClientSide`: a projected `Sql.Right` whose value or length argument is a local method over a column returns the client result — providers: all `[DataSources]` — proof: red→green (master SQLite.MS / SqlServer.2022 pass; the branch before A-4 threw "could not be converted to SQL" on SQLite.MS, SqlServer.2022, Oracle.23)
- TO-22 (A-8) `ConvertToInt32NegativeMidpointsRoundToEven`: `Convert.ToInt32(decimal)` and `(double)` over {-2.5, -0.5, -3.5} equal .NET — providers: all — proof: control (mutation: the base to-even midpoint arm removed)
- TO-23 (A-8) `MathRoundToEvenStaysOffDecimal`: `Math.Round(1.49999999999)` answers 1; separates: the decimal route of `Sql.RoundToEven(double)` at scale 10 makes it a midpoint — providers: AllFirebird, AllSapHana — proof: control (mutation: `TranslateMathRoundMethod` calling `TranslateSqlRoundToEven`; red on Firebird, green on HANA)
- TO-21 (A-7) `MathRoundAwayFromZeroStaysOffNumeric`: `Math.Round(F, P, AwayFromZero)` over `{ 1.4999999999999998, 0 }` answers 1 as C# does; separates: PostgreSQL's float8-to-numeric cast keeps 15 significant digits, so the value becomes 1.5 on the numeric route and answers 2 — providers: AllPostgreSQL — proof: control (mutation: `TranslateMathRoundMethod` calling `TranslateSqlRoundAwayFromZero` instead of `TranslateRoundAwayFromZero`)

Members not separately exercised: a direct `Sql.Power(double?,double?)` call — reached via `Math.Pow` in TO-6; its path is unchanged.

## P9 Verification gates

- G-01: passed (2026-10-26, after A-4, Debug net10.0). `Tests.Analyzers.Internal` 71/71 (Release). `MathFunctionTests` + `StringFunctionTests.Right*` per provider:
  - Green on all 16 local providers: SQLite.Classic / .MS, SqlCe, DuckDB, Access.Ace.OleDb / .Odbc, MySqlConnector.8.0, ClickHouse.Driver, DB2, Firebird.5, PostgreSQL.18, SapHana.Odbc, SqlServer.2022, Oracle.23.Managed, Sybase.Managed, Informix.DB2. TO-20 passed on every one, both cases.
  - The only residue is an environment fault: a HANA connect timeout in `Exp` teardown, a test the branch does not touch.
  - The first pass also had reds that a rerun cleared: a MySQL connect timeout right after container start, and Firebird / ClickHouse tests that overtook a slow `CreateDatabase` (7m on Firebird). Reran with `CreateDatabase` as its own step: green.
  - YDB is CI-only.
  - Per obligation (pass on the run above unless the row says otherwise):
    - TO-1 `MemberMapShadowAnalyzerTests`: `PowMirrorIsReported`, `RegisteredPropertyIsReported`, `RegisteredConstructorIsReported`, `RegisteredReplacementIsReported`, `GenericMatchRegistrationCoversOtherInstantiations`, `ExactRegistrationDoesNotCoverOtherInstantiations`, `DifferentOverloadIsNotReported`, `CooperativeChainsAreNotReported`, `SameNameOnAnotherReceiverIsNotReported`, `ForeignLookAlikesAreNotMatched`, `CleanModelIsNotReported` — pass
    - TO-2: `ProviderEntryAgainstBaseRegistrationIsReported`, `ProviderEntryAgainstItsOwnProviderRegistrationIsReported`, `ProviderEntryAgainstAnotherProviderRegistrationIsNotReported`, `DottedSectionResolvesToItsProviderRoot`, `CommonEntryAgainstProviderRegistrationIsReported` — pass
    - TO-3: `ProviderEntryKillsSameConfigurationAttribute`, `ConfigurationSetByPropertyIsRead`, `ProviderEntryKillsSubConfigurationAttribute`, `ProviderEntryLeavesOtherAttributesLive`, `CommonEntryKillsUnconfiguredAttribute` — pass
    - TO-4: `EntryOutsideAnInitializerIsDrift`, `EntryWithoutAMemberIsDrift`, `EmptyModelIsDrift`, `NonLambdaRegistrationPatternIsDrift` — pass; (A-7) `NoRegistrationsIsDrift`, `RenamedRegistrationExtensionsIsDrift`, `RenamedExpressionAttributeIsDrift` — 3 red on the unfixed analyzer (73 of 76 green), then 77/77 with `CompilationWithoutTheMapIsNotReported` — pass
    - TO-5: Release build of `Source/LinqToDB` — 16 × 0007 / 4 × 0008 / 0 × 0009 on master (A-1), clean after (G-09) — pass. (A-8) That master count was taken with the reader that dropped parameterless registrations, so the "before" census is re-derived rather than re-measured; the clean build with those registrations read is measured
    - TO-6: `MathFunctionTests.Pow` — pass (SQL baseline: G-02)
    - TO-7: `SqlRoundDecimalOverloads`, `SqlRoundDoubleOverloads` — pass; A-5: `SqlRoundDecimalOverloads` gated on #6055 for `YDB.LinqService`
    - TO-8: `SqlRoundDoubleOverloads`, `SqlRoundDoubleOverloadsOnClient` — pass
    - TO-9: `MathRoundResidueDoubleKeepsDoubleRoute` — pass; the mutation run is not recorded in this plan
    - TO-10: `MathRoundNegativeMidpoints` (AllAccess rows) — pass; A-5 changed the Access formula, re-run on Access not recorded here
    - TO-11: `MathRoundNegativeMidpoints` — pass
    - TO-12: `RightInRange`, `RightLongerThanString` — pass; A-5: YDB `RightInRange` and SQLite `RightLongerThanString` green per the 2026-11-07 review at `c48ec1c74` / `e683491b4`
    - TO-13: `RightConstantArgumentIsServerSide` — pass; (A-7) red on its mutant (`CanBeEvaluatedOnClient` guard added to `TranslateSqlRight`) on `SQLite.MS` and `SQLite.MS.LinqService`: the SQL is `SELECT 1`
    - TO-14: `SqlTruncateOverloads`, existing `Truncate1` / `Truncate2` — pass; `OrmBattleTests.MathTruncateTest` not in a recorded run (CI)
    - TO-15: `SqlTruncateConstantArgumentIsClientSide` — pass; (A-7) red on its mutant (guard removed from `TranslateTruncateMethod`) on `PostgreSQL.18` and `PostgreSQL.18.LinqService`: `SELECT Trunc(2.7, 0)`. The mutant stays green on `SQLite.MS`, so the control discriminates only where the provider's form keeps the literal. Critic round 5 reads SQLite's emulation as an all-constant conditional evaluated on the client (reasoned, unprobed)
    - TO-16 baselines scoping — blocked on G-02 (CI on `99c200db6` in flight)
    - TO-17: `StringFunctionTests.Stuff1`, the `string.Insert` / `string.Remove` tests — pass
    - TO-18: `MathRoundDecimalHeadroom` — pass
    - TO-19: `SqlRoundDoubleWidePrecision` — pass on MySQL / ClickHouse / DB2; A-5 Access rows: not in a recorded run
    - TO-20: `RightUntranslatableArgumentIsClientSide` — pass
    - TO-21 (A-7): `MathRoundAwayFromZeroStaysOffNumeric` — green on `PostgreSQL.18` and `.LinqService`; red on its mutant on both: `{ Id = 1, Away = 1 } <> { Id = 1, Away = 2 }`
    - TO-22 (A-8): `ConvertToInt32NegativeMidpointsRoundToEven` — green; red with the midpoint arm removed on PostgreSQL.18, SQLite.MS, Firebird.5 and SapHana.Native, direct and remote: -2.5 → -3 and -0.5 → -1
    - TO-23 (A-8): `MathRoundToEvenStaysOffDecimal` over `1.49999999999` — green on Firebird.5, SapHana.Native and SapHana.Odbc; red on Firebird.5 and its remote context with `Math.Round` routed through `TranslateSqlRoundToEven`; green on that mutant on SapHana.Native, so it does not separate on HANA. `1.4999999999999998` was tried first: Firebird's own double route answers 2 for it, so it separates nothing there
    - TO-18 (A-8): `MathRoundDecimalHeadroom` with the `20000000000000001.5` row — red on Oracle.23.Managed before the fix, green after; `MathFunctionTests` whole on Oracle.23.Managed, Firebird.5, PostgreSQL.18, SQLite.MS (480/482, the 2 reds being TO-23's first value), SapHana.Native 126/126, SapHana.Odbc 126/126
    - Analyzer (A-8): 80/80 in Release; fixtures for the two silent paths and the `Expression<Action>` pattern red first
    - TO-18 on DuckDB (A-9): red in CI [42503303638](https://github.com/linq2db/linq2db/actions/runs/42503303638) on the `20000000000000001.5` row (DECIMAL(18) overflow); green after the override. `MathFunctionTests`, `ConvertTests` and `PreferClientCalculationTests` on DuckDB and DuckDB.LinqService, 355/355 with CreateDatabase
  - (A-7) Analyzer census of `MemberMapShadowAnalyzer`: 45 branches, 11 uncovered by a fixture. Two are unreachable defensive arms (`argument.Parameter` null, `pattern == null` in `CollectRegistration`). One is a silent drift path, open with the user: a `Register*` lambda naming no member returns without a failure (`CollectRegistration`). A second silent path sits on a covered branch (critic round 5): `CollectEntry`'s non-lambda exit, needed for the `MapMember` forwarders, also swallows a table entry `{ M(field), N(...) }`. Eight are read-side arms with no fixture: an `Add` outside an initializer, a table in a local (`ResolveSection`'s `_ => null`), a multi-statement lambda, an `Expression<Action>` pattern, the field arm of `ResolveMember`, a namespace outside `DataProvider.`, a provider namespace without a trailing segment (`ProviderOf`), and an attribute not derived from `Sql.ExpressionAttribute`.
  - (A-7) Release: `Source/LinqToDB` and `Tests/Linq` `-f net10.0`, 0 warnings, on the working tree.
  - (A-7) test-diff-sweep on the implemented tree (`-IncludeWorkingTree`): 1 one-line chain (`MemberMapShadowAnalyzerTests.cs:318` — fixture source text, not test code), 0 nested chains, 5 narrowed sets, each with its reason on the line above (`MathFunctionTests.cs:1992`, `:2029`, `:2056`, `:2081`, `StringFunctionTests.cs:1029`). The earlier `RoundValuesData.Where(...).ToArray()` hit was fixed in `0889eb1a3`.
  - A-5 delta not re-run locally in a recorded run; CI `test-all` [25367](https://dev.azure.com/linq2db/linq2db/_build/results?buildId=25367) and GH [42412211228](https://github.com/linq2db/linq2db/actions/runs/42412211228) on `99c200db6` are in flight and are the run of record.
  - test-diff-sweep (2026-11-07, `origin/master...origin/pr/6151`): 2 one-line chains (`MathFunctionTests.cs:1867` `RoundValuesData.Where(...).ToArray()` — fixed in `0889eb1a3`; `MemberMapShadowAnalyzerTests.cs:299` — fixture source text, not test code), 0 nested chains, 4 narrowed sets, each with its reason on the line above (`:1990`, `:2027`, `:2053`, `StringFunctionTests.cs:1029`).
- G-02: passed (2026-11-08, `/review-pr 6151` round 2, branch tip `42af7654a8f` rebased on baselines master): 749 A / 1003 M / 0 D, 0 inherited. The modified files follow TO-16's mechanisms as corrected by A-7, which adds the `Truncate1` / `Truncate2` movement and drops SQLite `Remove1`. TO-16 (b) names only `Round1/2/7/8`, but the same base branch also moves 531 files through `Convert.ToXxx` (critic round 5): `ConvertTests.ConvertTo*`, `PreferClientCalculationTests` and `OrmBattleTests.ConvertToInt32`. SQL Server 2005–2016 run on Azure only and their baselines date from `adf38a6a5` (2026-10-26). TO-5's real-tree site list is in its G-01 row. A-8 changes Oracle's decimal cells after this snapshot (TO-16 (h)): to re-check on the baselines from `test-all` [25400](https://dev.azure.com/linq2db/linq2db/_build/results?buildId=25400), which also carries A-9's DuckDB cells.
- G-03: — (pending) `PublicAPI.Unshipped.txt` rows for new virtuals / overrides / nested classes (E-23); XML docs on new public members
- G-04: — (pending) `/api-baselines` only if a non-Internal surface moves — expected n/a (attribute removal changes no signature)
- G-05: passed (2026-10-25, after A-4) — Release `Source/LinqToDB` netstandard2.0 and net462, 0 warnings
- G-06: — (pending)
- G-07: — (pending)
- G-08: — (pending) base `TranslateRoundToEven` fix, the `Sql.Round*` virtual split and the base `Right`/`Truncate` registrations proven by TO-7, TO-9, TO-11, TO-12, TO-14 across all providers (CI test-all)
- G-09: passed (2026-10-25) — `/code-review` walk dispositioned and applied (A-4). Release `Source/LinqToDB -f net10.0`, `Tests/Linq -f net10.0` and `Tests/Tests.Analyzers.Internal`: 0 warnings, no LINQ2DB0007-0009 on the real tables

## P10 Adjudicated (M/L)

- `Sql.RoundToEven(double)` on Firebird keeps the map's `Decimal(18,10)` range (`|v| ≥ 1e8` may overflow) — pre-existing behaviour, preserved by the faithful port (D-5, U-9).
- `Math.Round(double, p)` ToEven on PostgreSQL keeps its `decimal` cast (`PostgreSQLMemberTranslator.cs:273-295`) and therefore decimal semantics on residue doubles — pre-existing; required because PostgreSQL has no `round(double precision, int)` (documented, unprobed); TO-9 records the master value.
- `Sql.Right` with n < 0 or n > len keeps each engine's own answer on providers whose emulation is not rewritten (generic RIGHT, ClickHouse, Ydb), and the map formula's answer on SqlCe / Informix / PostgreSQL — pre-existing. Only Oracle and SQLite (`RightLongerThanString`, n ∈ {5, 6}) carry an out-of-range test. No test carries n < 0, and none covers SqlCe / Informix / PostgreSQL out of range, so on those three the "map formula's answer" over the new translator code is reasoned, unprobed (critic round 4). SQLite is no longer in this list: A-5 clamps its start like Oracle's.
- `CollectEntry`'s non-lambda exemption is keyed on section resolution, so a helper inside `Expressions` forwarding a caller's key into a table stays silent — no such helper exists today; user decision 2026-11-08 (critic round 6, objection 5), kept as a known limit.
- Firebird's native `ROUND` over a double moves a value just below a midpoint up (`1.4999999999999998` → 2; C# 1). Measured on master with a raw `ROUND(v, 0)`, so pre-existing and from the engine; filed as #6273. TO-23 uses `1.49999999999`, which this behaviour does not reach.
- `MathRoundResidueDoubleToEven` is gated `[ActiveIssue(6263)]` on AllDB2 (A-6; split from `MathRoundResidueDoubleKeepsDoubleRoute` in A-8). DB2's native `ROUND(1.15, 1)` on a DOUBLE returns 1.1, while .NET returns 1.2. This is pre-existing: DB2 has no rounding override on master, and the to-even precision branch is master's SQL. Measured on `DB2` and `DB2.LinqService`; PostgreSQL.18, MySqlConnector.8.0 and ClickHouse.Driver agree with C#.
- `SqlRoundDecimalOverloads` is gated `[ActiveIssue(6055)]` on `YDB.LinqService` only (A-5): `LinqServiceSerializer` drops the computed decimal's precision / scale, the server folds the narrowing casts, and YQL rejects the `If` branches. #6055 (open) is the existing remote-serializer issue, already gating `Round29`–`Round35` in the same file. Measured in CI and by the reviewer's local YDB run (gate message matches, direct YDB green); TO-7's decimal cells are therefore unasserted on `YDB.LinqService`.
- `Sql.Truncate` client-evaluable constant calls become a parameter instead of an inlined literal (WHERE), and `LinqOptions.PreferClientCalculation` no longer pulls `Sql.Truncate` client-side — inherent to translator-only members (U-6); same trade-off as #5544 / #5515; pinned by TO-15.
- `Expressions.AccessRound(double?,int?)` / `(decimal?,int?)` become unused internally but are shipped public API (`PublicAPI.Shipped.txt:15016-15017`) and stay.
- `Math.Round` SQL changes on Access and on base-ToEven providers (precision-null branch) — intended defect fixes (D-5, user decision 5).
- `analyzer-own-perf-baseline.json` and KB tables are not updated on this branch — skill-driven artifacts.
- `Sql.Right(s, 0)` returns NULL on Sybase and Informix (measured), as on Oracle — engine semantics; TO-12 leaves the row out there.
- DuckDB rejects `ROUND(DECIMAL, <column>)` ("with non-constant precision is not supported", measured) — engine limit; `SqlRoundDecimalOverloads` carries a `ThrowsForProvider` gate for DuckDB.
- Access fails on a function result over a NULL argument (OleDb "could not determine the value", ODBC "data type mismatch"), measured identical on master. Which construct fails — the `Round` / `Int` call or the reader's typing of the NULL result — is not isolated; the null rows of the Round and Right tests are left out on Access, so SC-7's and SC-11's null cells are unasserted there.
- The MySQL / ClickHouse / DB2 AwayFromZero override gates on the CLR type: a `decimal` member stored as a double keeps native half-to-even `ROUND` (pre-existing, unchanged), and a `double` stored as a decimal takes the magnitude formula (correct in either case).
- A `decimal` above 2^53 loses digits under every rounding path on SQLite (REAL storage) and Access (`Round` / `Int` return Double) — pre-existing; TO-18 leaves them out.

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
  - re-derives: P6 (E-19), P7 (shared Round override row: the new DB2 `TranslateRoundAwayFromZero`), P10 (Informix / Access lines)
  - conventions: `testing.md` → *Test layout* and *A narrowed provider set is a claim*, re-embedded. Each new narrowing carries its measured reason at the data. Swept `git diff origin/master -- Tests/`, with the new tests in the working tree: each narrowing carries a measured reason (`RightLongerThanString` Oracle-only = the clamp; `MathRoundResidueDoubleKeepsDoubleRoute` PostgreSQL-only = the mutation target; DuckDB throws gate = engine limit).

- A-3 (2026-10-25, critic round 3 on A-1 / A-2; both leads probed)
  - **DuckDB decimal headroom, measured red.** The A-2 midpoint arm `ROUND(v / 2, 0) * 2` made DuckDB's whole CASE DOUBLE: `Math.Round(d)` and `Sql.RoundToEven(d)` over `12345678901234567.3` returned `12345678901234600`, while the `Away` path, which never divides, stayed exact in the same run. Fixed: the arm is now `ROUND(v * 0.5, 0) * 2`, which keeps a decimal a decimal; DuckDB is green. New TO-18, SC-16. SQLite and Access lose these digits on every path, `Away` included, so they are left out (P10).
  - **DB2 integer `POWER`, measured red.** `SqlRoundDoubleWidePrecision` failed with SQLSTATE 22012 (division by zero) at precision -1: `POWER(10, -1)` over two integers is 0. Fixed: `RoundAwayFromZeroByMagnitude` takes the base from the caller, and DB2 passes `CAST(10 AS DOUBLE)`. MySQL and ClickHouse keep the `10` literal: their `POWER` / `pow` already return a float, and a blanket cast would need `CAST(… AS DOUBLE)`, which MySQL 5.7 lacks. New TO-19.
  - `Round6`'s ClickHouse exclusion ("Double use bankers rounding") dropped: SC-15 fixes exactly that, and `Round6` passes on ClickHouse. TO-16 (f) owns its SQL on MySQL / ClickHouse / DB2.
  - `MathRoundResidueDoubleKeepsDoubleRoute` widened to AllMySql / AllClickHouse / AllDB2 (TO-9); green.
  - Rewritten in place, as A-1 / A-2's `re-derives:` lines claimed: U-11, D-5 (base ToEven as shipped, MySQL / ClickHouse / DB2 arm, CLR-type gating), SC-8, new SC-15 / SC-16, the P3 may-change list, TO-7, TO-8 (Firebird / SapHana precision-null SQL now owned by TO-16 (b)), TO-9, TO-10, TO-12, TO-16 (f), and six P10 lines (Sybase / Informix `Right(s, 0)`, DuckDB column-precision gate, Access null rows with the construct stated as unisolated, CLR-type gating, SQLite / Access headroom).
  - Result: `MathFunctionTests` green on all 16 local providers after the change (DB2 and ClickHouse after one transient `CreateDatabase` failure, re-run green). YDB is CI-only.
  - re-derives: P2 (SC-8, SC-15, SC-16), P3, P4 (U-11), P5 (D-5), P6 (E-6, E-16, E-19, E-21, E-24: same files, no new edit-point), P7 (`Round6` row), P8 (TO-7..TO-10, TO-12, TO-16, TO-18, TO-19), P10
  - conventions: `testing.md` → *Test layout* and *A narrowed provider set is a claim*, re-embedded. Each new narrowing carries its measured reason at the data: `MathRoundDecimalHeadroom` excludes SQLite and Access (pre-existing engine digit loss), and `SqlRoundDoubleWidePrecision` covers only the three magnitude providers, because those are the only ones whose `ROUND` the branch replaces.

- A-4 (2026-10-25, `/code-review` walk on the branch diff; user dispositions)
  - **Applied:**
    - `RoundAwayFromZeroByMagnitude`: `floor(m + 0.5)` replaced by `CASE WHEN m - FLOOR(m) = 0.5 THEN FLOOR(m) + 1 ELSE ROUND(m, 0) END`. In double the addition itself rounds: `0.49999999999999994 + 0.5` is `1.0`, and above 2^52 an odd integer lands on an even neighbour. TO-19 gains the edge rows.
    - Analyzer: `RegisterReplacement` is collected as a registration, and a `Register*` pattern that is not a lambda written in place reports 0009, except inside `TranslationRegistrationExtensions`, whose helpers forward their caller's pattern. TO-1 and TO-4 gain fixtures.
    - `RoundThroughDecimal` (protected static, `MathMemberTranslatorBase`) replaces the cast-round-cast copies in Firebird / SapHana `TranslateSqlRoundToEven` and PostgreSQL `TranslateSqlRoundAwayFromZero`. No SQL change. The MySQL / ClickHouse / DB2 guard trio is left as is.
    - `Sql.Right` over an untranslatable argument: a measured regression. Master evaluates it on the client (SQLite.MS, SqlServer.2022 green), while the branch threw "could not be converted to SQL" (SQLite.MS, SqlServer.2022, Oracle.23). `TranslateSqlRight` now returns null on either argument (D-6), so the call falls back to the client. The sibling convention is split: the Math handlers return null, while most String handlers return an error expression. New TO-20.
  - **Dropped:** re-translation inside `TranslateRightAsSubstring` / `TranslateTruncateAsFloorOrCeiling`; the Access `Round(v, p)` / `Fix()` collapse. Also dropped as already adjudicated: `Right` out of range on SQLite / YDB (P10), Firebird `DECIMAL(18,10)` (U-9), the `Sql.Round` doc level (A-1).
  - Result: `Tests.Analyzers.Internal` 71/71 (Release). Release builds of `Source/LinqToDB` (net10.0, netstandard2.0, net462) and `Tests/Linq` (net10.0) are clean, with no LINQ2DB0007-0009 on the real tables. Provider runs: see G-01. Commits: `a7ec6809f` (midpoint), `baa0860a5` (`Sql.Right`), `01c9d6ab4` (`RoundThroughDecimal`), `9d9e666c3` (analyzer). These are pre-rebase ids; the branch was rebased onto `origin/master` `4e6f16bb3`.
  - re-derives: P5 (D-6 client-evaluation policy), P6 (E-1, E-3, E-6, E-7, E-8, E-9, E-10, E-23, E-24, E-25: same files, no new edit-point), P8 (TO-1, TO-4, TO-19, TO-20)
  - conventions: `testing.md` → *Test layout* and *A narrowed provider set is a claim*, re-embedded. The new test carries no `Issue<N>` name and no provider narrowing.

- A-5 (2026-11-07, reconcile before `/review-pr 6151`; adopts the commits that answered igor-tkachev's agentic reviews of 2026-10-29 and 2026-11-07, made without an amendment)
  - **The approval of record is void for the rows below** and is re-earned on this amendment; the critic round on this delta is round 4 in P12.
  - `c48ec1c74` — **YDB `Sql.Right`, NULL length.** `Unicode::Substring` reads a NULL count as "to the end", so `Sql.Right(s, null)` returned the whole string. Reported by the reviewer, who measured `RightInRange` red on `YDB` and `YDB.LinqService` at `adf38a6a5`. Fix: `CASE WHEN n IS NULL THEN NULL ELSE Unicode::Substring(…) END`. Per the reviewer's re-run, the CASE appears only for a nullable length, and `Sql.Right(s, 3)` / a non-nullable column keep the plain form. Changes D-6 (Ydb no longer reproduces its attribute verbatim), SC-11, SC-13 and TO-12. Master's `Sql.Right` attribute on Ydb (`Sql.cs:640`) emitted the same `Unicode::Substring`, so master is presumed to have had the same defect; reasoned, unprobed (YDB is CI-only here).
  - `c48ec1c74` — **gate.** `SqlRoundDecimalOverloads` gets `[ActiveIssue(6055, Configuration = AllYdb, SkipForNonLinqService = true)]` with the error type and message pinned. #6055 is open and already gates `Round29`–`Round35`. The gate narrows TO-7's decimal cells on `YDB.LinqService`. Measured: the reviewer's YDB run reports the test "still failing as expected" with a matching message, and the direct YDB arm passes. It has never been proven on a local run, because YDB cannot run locally here. P10 has a line for it.
  - `e683491b4` — **SQLite `Sql.Right` longer than the string.** `SUBSTRING(s, LENGTH(s) - n + 1)` counts a negative start from the right, so `('John', 6)` gave `'n'`. Measured by the reviewer on SQLite MS and Classic. It is the defect this branch fixes for Oracle, and the reviewer filed it as MIN002. Fix: the start becomes `MAX(LENGTH(s) - n + 1, 1)`. SQLite's two-argument `MAX` returns NULL for a NULL argument, so a NULL length still gives NULL (reasoned from SQLite's documented scalar `max()`; `RightInRange`'s null row is the check). `RightLongerThanString` is widened to AllSQLite. Changes D-6, SC-11, SC-13, P10 (SQLite dropped from the "engine's own answer" list), TO-12 and TO-16 (c). Every SQLite `Sql.Right` baseline moves.
  - `bdc4a2ff7` — **Access AwayFromZero double edges.** The reviewer asked why `Int(m + 0.5)` was kept after A-4 had replaced it in `RoundAwayFromZeroByMagnitude`. In double arithmetic the addition itself rounds (`0.49999999999999994` → 1, `2^52 + 1` moves). The A-4 midpoint test does not port: Access compares a double with the literal `0.5` imprecisely, and `0.49999999999999994 < 0.5` is false (probed on ACE OLE DB and ODBC, per the commit). Fix: `Int(m) + Int((m - Int(m)) * 2)`. The author argues the fraction and its doubling are exact; that is reasoned, unprobed beyond the TO-19 rows. `SqlRoundDoubleWidePrecision` is widened to AllAccess. Changes D-5, E-11 and TO-19. The `decimal` path takes the same formula (the CLR type is not gated on Access); reasoned, unprobed.
  - `830482c37` / `99c200db6` — the analyzer ids were renumbered to 0008–0010 and then reverted, so there is no net change to E-1 / E-2. The id clash with #6145 (`LINQ2DB0007 | BuildContextMappingSchemaAnalyzer`) is to be resolved on #6145, which moves to 0010–0011. At #6145's head `de450862a` it still claims 0007 (checked 2026-11-07). Whichever PR merges second keeps both `AnalyzerReleases.Unshipped.md` blocks in id order.
  - G-01 now has one row per TO-n, plus the sweep counts on the implemented tree.
  - re-derives: P2 (SC-11, SC-13), P5 (D-5 Access line, D-6 Right overrides), P7 (new A-5 consumer row), P6 (E-11, E-15, E-17, E-24, E-25 re-worded; no new file), P8 (TO-12, TO-16, TO-19), P9 (G-01), P10 (Right out-of-range line, new #6055 line)
  - conventions: `testing.md` → *Test layout*, *A narrowed provider set is a claim* and *Gating an assertion failure*, embedded after the code (these are adopted commits). `test-diff-sweep.ps1 -Ref origin/pr/6151` over `origin/master...origin/pr/6151 -- Tests/` found 2 one-line chains, 0 nested chains and 4 narrowed sets. Dispositions: `MathFunctionTests.cs:1867` (`RoundValuesData.Where(…).ToArray()` in a ternary arm) is a review item. `MemberMapShadowAnalyzerTests.cs:299` is fixture source text, so it is not a layout hit. All 4 narrowed sets carry their measured reason on the line above. The two A-5 widenings each cite their measured failure. The #6055 gate pins `ErrorTypeName` and `ErrorMessage`, and the message is a driver message, not a Shouldly one. It is proven only in CI, because YDB has no local leg here.

- A-6 (2026-11-08, `/review-pr 6151` round 1 walk; user dispositions; test-only, no `P6` row added)
  - **Fixed on the branch:**
    - `MathRoundResidueDoubleKeepsDoubleRoute`: adds the `1.005 @2` row and a to-even column, rewrites the comment, and gates DB2 on #6263 (new P10 line). TO-9 becomes characterization.
    - `MemberMapShadowAnalyzerTests`: two fixtures, `UnregisteredFieldTableIsDrift` and `SectionKeyMatchesProviderNamespaceIgnoringCase` (a `YDB` section against a `…DataProvider.Ydb` registration). Each goes red against its mutant (0009 arm silenced; `Ordinal` instead of `OrdinalIgnoreCase`); measured 27/27 green on the fixed analyzer and 25/27 on the mutant.
    - `MemberMapShadowAnalyzer.Report`: parameter column alignment. `RoundValuesFor`: one call per line.
  - **Dropped after probing:**
    - Oracle `0.5D` in the to-even midpoint arm. The SQL carries it, but `MathRoundDecimalHeadroom` and `Math.Round(d) / 3` stay exact on Oracle.23.Managed; other Oracle versions were not probed.
    - DB2 `v * 0.5` overflow near DECIMAL(31). This is not a regression: master's `Int(FLOOR(v))` overflows from `3000000000.5`, where the branch answers. Both fail at `2e20 + 0.5`.
    - Access `Sql.Round(decimal, p)` scaled by a Double `10 ^ p`. Measured exact on ACE OLE DB and ODBC.
    - The TO-15 WHERE-cell SQL assertion (refuted; see TO-15).
  - **Filed:** #6262 (YDB `Unicode::Substring` NULL count in `Sql.Substring` / `Sql.Left` / `Sql.Stuff`, from critic round 4) and #6263 (DB2 to-even residue).
  - **Re-run of the A-5 delta (critic round 4, objection 2), measured at `99c200db6`:** `MathFunctionTests` and `StringFunctionTests.Right*` are green on Access.Ace.OleDb 125/125, Access.Ace.Odbc 125/125, SQLite.Classic 121/121 and SQLite.MS 118/118. Oracle.23.Managed is 8/8 on `MathRoundDecimalHeadroom`, `SqlRoundDecimalOverloads` and `MathRoundNegativeMidpoints`.
  - re-derives: P5 (D-5's rejected-alternative example), P8 (TO-9, TO-15), P10 (new #6263 line)
  - conventions: `testing.md` → *Test layout*, *A narrowed provider set is a claim* and *Gating an assertion failure*, embedded. The new gate follows the file's existing `Assert.That(exceptExpected, Is.Zero)` gate on DB2 (`Round*` precedent at `MathFunctionTests.cs:297`) and was measured on both DB2 contexts. The new fixture text is source code inside a raw string literal, not test code.
- A-7 (2026-11-08, `/review-pr 6151` round 2 walk; user dispositions; all edits inside existing `P6` rows)
  - **E-1 (analyzer, MIN005):** `Report` emits `LINQ2DB0009` when no registration was collected and when `Sql+ExpressionAttribute` does not resolve, so a renamed extensions type, renamed `Register*` methods or a renamed attribute no longer leave a clean build. The diagnostic title and message now say "member map model".
  - **E-3 (analyzer fixtures, MIN005 and census):** a sentinel registration in the miniature model, three red→green drift fixtures, and `CompilationWithoutTheMapIsNotReported`. TO-4 and SC-4 widen to match.
  - **Tests (`MathFunctionTests`, SUG002 and NIT003):** TO-21 added. The `SqlTruncateOverloads` cells are renamed to `SqlDecimalNoAsSql` / `SqlDoubleNoAsSql`. TO-9's false `separates:` clause and the test comment's "cannot separate" sentence are removed.
  - **Corrected by measurement (MIN004):** SC-13 and TO-16 claimed zero diff for `Truncate1` / `Truncate2`; all 136 files moved. TO-16 (c) claimed SQLite `Remove1` moves; it does not. The results are unchanged, and the PR body's list is extended.
  - **Filed:** #6266 (PostgreSQL double away-from-zero `FLOOR(v + 0.5)`, measured on PostgreSQL.18, pre-existing).
  - **Measured controls:** TO-13, TO-15 and TO-21 mutants, recorded in G-01. All mutations are reverted.
  - re-derives: P2 (SC-4, SC-13), P3 (results clause), P5 (D-6 "why this"), P8 (TO-4, TO-9, TO-16, TO-21), P9 (G-01, G-02)
  - conventions: `testing.md` → *Test layout* and *A narrowed provider set is a claim*, embedded; no new gate was added. `test-diff-sweep.ps1 -IncludeWorkingTree` on the implemented tree: counts in G-01. `authoring-analyzers.md` → *Designing a "read X, not Y" rule* read for E-1.
- A-8 (2026-11-08, critic round 5 dispositions by the user; all edits inside existing `P6` rows)
  - **E-1 (analyzer, both silent paths):** `CollectEntry` reports 0009 for a table entry whose key is not a lambda written in place; `CollectRegistration` reports 0009 for a pattern naming no member. New fixtures `TableEntryWithoutALambdaIsDrift` and `RegistrationWithoutAMemberIsDrift`, both red first.
  - **E-1 (a bug the check exposed):** the first real-tree build reported 150 `LINQ2DB0009`. A parameterless pattern binds to `Expression<Action>`, whose lambda body ends in an implicit return, so `ResolveMember` returned null and every such registration was silently dropped: LINQ2DB0007 could not see them, and SC-5's 16 + 4 census was taken without them. `ResolveMember` now skips that return; `ActionPatternRegistrationIsReported` was red first. The Release build with the 150 registrations collected reports no new shadow, so the census stands.
  - **E-6 (`TranslateRoundToEven`, Oracle):** the critic's lead reproduced. On Oracle.23.Managed `20000000000000001.5` came back `20000000000000000` through `Math.Round` and `Sql.RoundToEven` (C# `…002`), because the midpoint arm's CLR-double `0.5` renders as `0.5D`. A decimal value now gets a decimal literal; SC-16 holds on Oracle. Row added to TO-18.
  - **Tests:** `ConvertToInt32NegativeMidpointsRoundToEven` (TO-22), `MathRoundToEvenStaysOffDecimal` (TO-23), and TO-9's to-even column split into the gated `MathRoundResidueDoubleToEven`, so `Away` stays asserted on DB2.
  - re-derives: P2 (SC-4, SC-5, SC-16), P8 (TO-4, TO-9, TO-16, TO-18, TO-22, TO-23), P9 (G-01, G-02), P10 (the #6263 line now names the split test; #6273 added)
  - conventions: `testing.md` → *Test layout* and *A narrowed provider set is a claim*, embedded; TO-23's set is narrowed to the two providers with a decimal route, and the gate moved with its column.
- A-9 (2026-11-08, `test-all` 25394 triage; user dispositions; existing `P6` row for the DuckDB translator)
  - **The DuckDB translator (decimal precision-null to-even):** TO-18's `20000000000000001.5` row failed on DuckDB in CI with `Overflow in multiplication of DECIMAL(18)`, the base form's `value * 0.5`. Probed locally: `round_even` returns DOUBLE for a DECIMAL (`12345678901234567.3` → `1.2345678901234568e+16`), so it is not usable. The override uses a parity test on `FLOOR(value)`, with no multiplication. Double values and non-zero precision stay on the base form.
  - **Test comment (critic round 6, objection 1):** `MathRoundToEvenStaysOffDecimal` now names Firebird only.
  - **Not attributed to this PR:** `DB2Tests.BulkCopyProviderSpecificAsync` (`SQL0964C`, transaction log full) and `DB2Tests.TestDataTypes` (identity 183642) on the same leg.
  - re-derives: P3 (DuckDB's decimal to-even SQL may change), P5 (D-5's "multiplies" rationale no longer holds on DuckDB's decimal route), P7 (DuckDB joins the `TranslateRoundToEven` overriders), P2 (SC-16 holds on DuckDB through the override), P8 (TO-16 (h) gains DuckDB's decimal cells, TO-18), P9 (G-01, G-02, G-03), P10 (known limit on `CollectEntry`)
  - conventions: no new test; the sweep counts in G-01 stand.
  - measured: `MathFunctionTests`, `ConvertTests` and `PreferClientCalculationTests` on DuckDB and DuckDB.LinqService, recorded in G-01.

## P12 Critic verdict (M/L)

**Current verdict: weak** — round 7 (delta on A-9).

Round 7 (`plan-critic`, model `fable`, 2026-11-08, delta on A-9): **weak**. The critic read the override, the base form, every `TranslateRoundToEven` overrider, master's branch and the local DuckDB captures. It ran nothing. Objections:
1. **Lead: DuckDB's precision form has the same two defects.** The base branch builds `value * 2` and `ROUND(value / 2, p) * 2`, so `Math.Round(decimal, p >= 1)` should overflow and go through DOUBLE. Pre-existing and unprobed. Open with the user.
2. **A-9's `re-derives:` was incomplete.** Extended; G-02 now names the run of record.
3. **Commit `39f22fe62` and the PR body said "about 1.8e17"; the failing row is 2e16.** Corrected in the PR body.
4. **Minor: no obligation reaches the override's `SqlValue { Value: 0 }` clause.** It mirrors the base's gate. Recorded, not acted on.


Round 6 (`plan-critic`, model `fable`, 2026-11-08, delta on A-8): **weak**. The critic read the five A-8 commits, every `TranslateRoundToEven` override, each provider's double and decimal literal writers, `ConvertMemberTranslatorDefault.cs:609-738` and the Oracle baselines. It ran nothing. It found E-6's blast radius to be Oracle only: every other base-branch provider already renders `0.5` as an exact literal. Objections:
1. **`MathRoundToEvenStaysOffDecimal`'s comment says HANA's decimal route makes the value a midpoint, which G-01's green mutant on HANA refutes.** Open: a code change.
2. **A-8 changes Oracle SQL after G-02 was recorded.** Fixed in the plan: TO-16 (h) added, G-02 reopened for the Oracle cells, A-8's `re-derives:` extended.
3. **TO-4, TO-9, SC-4 and TO-5's G-01 row lag A-8.** Fixed in the plan.
4. **The Firebird double divergence had no issue or P10 line.** Filed as #6273; P10 line added.
5. **`CollectEntry`'s exemption is keyed on section resolution, while `CollectRegistration`'s is keyed on the containing type,** so a helper in `Expressions` forwarding a caller's key into a table stays silent. No such helper exists today. Open.


Round 5 (`plan-critic`, model `fable`, 2026-11-08, delta on A-6 and A-7): **weak**. The critic read the analyzer, `MathMemberTranslatorBase.cs:200-540`, the Firebird / SapHana / Oracle translators, the commits since round 4 and the scoped baselines delta. It ran nothing. Objections, and where each stands (open items await the user's dispositions):
1. **`Convert.ToXxx` is a third caller of the base to-even branch.** `ConvertMemberTranslatorDefault.cs:609-738` wraps its argument in `Math.Round`, so 531 baselines (`ConvertTests.ConvertTo*`, `PreferClientCalculationTests`, `OrmBattleTests.ConvertToInt32`) move, and `Convert.ToInt32(-2.5m)` goes from -3 to -2 (reasoned), matching .NET. Wrapper sites verified; no obligation witnesses the result. G-02 restated. Open.
2. **A-6's DB2 gate blinds TO-9's `Away` column:** the gate matches `Assert.That(exceptExpected, Is.Zero)`, which an `Away` regression also produces (`ActiveIssueAttribute.cs:149,236`, verified). Open.
3. **Lead: A-6's Oracle `0.5D` drop rests on rows that cannot separate NUMBER from BINARY_DOUBLE.** `MathRoundDecimalHeadroom`'s values sit in [2^53, 2^54), where a double lands on the even neighbour anyway. A row at or above 2^54 would separate them. Unprobed. Open.
4. **TO-21 controls only the AwayFromZero clause of D-5;** Firebird / SapHana `TranslateSqlRoundToEven` has no control. Lead, unprobed. Open.
5. **A-7 did not re-derive P3 and D-6.** Fixed: both now match SC-13 as amended.
6. **`CollectEntry`'s non-lambda exit also swallows a table entry `{ M(field), N(...) }`,** a second silent path beside `CollectRegistration`'s. Added to G-01's census. Open.
7. **Note:** TO-15's SQLite blindness is read as the emulation's all-constant conditional being evaluated on the client (reasoned, unprobed). Recorded on TO-15's G-01 row.

Resolved by A-8 (user dispositions): objections 1, 2, 3 (reproduced on Oracle.23.Managed, fixed), 4 (Firebird control measured, HANA does not separate) and 6. A-8 has had no critic round of its own.


Round 4 (`plan-critic`, model `fable`, 2026-11-07, delta on A-5): **weak**. What the critic searched:
- `git show` of `c48ec1c74`, `e683491b4` and `bdc4a2ff7`.
- The branch diff over the Access / Math translators, `Sql.cs` and both test files.
- `git grep` for `"MAX"` in `Source/LinqToDB` (SQLite's scalar `MAX` is not misclassified as an aggregate), for `Unicode::Substring`, for `AltStuff` sections (Ydb is not among the nine), and for `6055` / `ActiveIssueAttribute`.
- The baselines clone `HEAD` for SQLite `Right` / `Stuff1` / `Insert` / `Remove*`.
- An IEEE arithmetic check of the Access formula at every TO-19 / TO-7 / TO-10 value. It could not dent it.

It could not run anything. Objections and dispositions:
1. **TO-16 (c) contradicted its own zero-diff list** for `Right` / `RightInSelect`, and missed the SQLite `AltStuff` consumers. Fixed in place in TO-16.
2. **G-01 rows covering A-5 are unrun**, and three of the four are locally runnable: Access TO-7 / TO-10 / TO-19 cells, and the SQLite TO-12 null row through `MAX`. Open: the local re-run is offered at the review's scope gate. The YDB rows wait for CI.
3. **TO-12 / P10 claimed out-of-range records no test carries** (n = -1; SqlCe / Informix / PostgreSQL). Trimmed in TO-12 and P10 to what the tests carry.
4. **Lead: the Ydb NULL-count class is wider than `Sql.Right`.** The surviving Ydb attributes on `Sql.Substring` (`Sql.cs:450`), `Sql.Left` (`:582`) and `Sql.Stuff` (`:604,621`) pass a possibly-NULL count to `Unicode::Substring`. It is out of `P3` scope. Open: P10 line or filed issue, the user's call.
5. **Outside A-5: TO-9's residue rows cannot separate the routes** (reasoned from IEEE arithmetic). `1.15 × 10` and `2.675 × 100` are exact ties after the scaling .NET's `Math.Round(…, AwayFromZero)` performs, so C# answers 1.2 / 2.68, the same as the decimal route. The test comment and D-5's "C# 1.1, decimal 1.2" would then be false, and TO-9's mutation would stay green. A separating row lands below the tie, e.g. 1.005 @2. **Measured 2026-11-07 (`dotnet fsi`, .NET 10):** `Math.Round(1.15, 1, AwayFromZero)` = 1.2, `Math.Round(2.675, 2, AwayFromZero)` = 2.68, `Math.Round(1.15, 1)` = 1.2, `Math.Round(1.005, 2, AwayFromZero)` = 1, and `1.15 * 10.0` = 11.5. The objection holds: TO-9 does not separate. Open: carried into `/review-pr 6151` as a finding.

Round 3 verdict, kept for the record: **weak**. Both leads were probed and both were red; the fixes and the plan rewrites are A-3, which does not widen `P6` and was not re-attacked before round 4.

Round 3 (`plan-critic`, model `fable`, 2026-10-25, delta on A-1 / A-2): **weak**. The critic searched `git diff origin/master...HEAD` over the math translators and both test files, every `TranslateRound*` override under `Internal/DataProvider`, `ValueToSqlConverter` double rendering, DB2's literal handling, the negative-precision tests in `Tests/`, `Round6`, and `work-plan.md`'s amend rule. It could not run anything. What it found could not be dented: "half a midpoint is never a midpoint" holds for both signs under every tie rule. Objections, and what changed (A-3):
1. **DuckDB DECIMAL / 2 → DOUBLE.** Probed, red. Fixed with `* 0.5`; TO-18.
2. **DB2 `POWER(10, p)` integer-typed.** Probed, red (22012). Fixed with a typed base; TO-19.
3. **`Round6` ClickHouse narrowing left stale.** Dropped; TO-16 (f).
4. **The rows named in `re-derives:` were never rewritten,** so SC-8 / P3 did not authorise the MySQL / ClickHouse / DB2 fix. Rewritten; SC-15 added.
5. **TO-9 never observed the magnitude route on residue doubles.** Widened; green.
6. **The Access null-row exclusion named a symptom.** The construct is not isolated; P10 now says so, and that SC-7 / SC-11 null cells go unasserted on Access.
7. **TO-8 claimed identical SQL for Firebird / SapHana precision-null `Sql.RoundToEven(double?)`.** Narrowed; TO-16 (b) owns it.
8. **CLR-type gating mirror cell.** P10 line added.

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
