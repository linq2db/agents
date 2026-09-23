# Work plan: feature-access-libred-dialect — LibRed extended SQL dialect

**Tier:** L  ·  **Status:** approved  ·  **Approved-at:** 2026-09-23 (E-1..E-14, after critic round 1)  ·  **Branch:** feature/access-libred-dialect
**Schema:** `.claude/docs/work-plan.md`  ·  **Gates:** `.claude/docs/definition-of-done.md`

Base: `origin/feature/access-libred` @ `3b6b73ba7` (#5956). Child PR, draft, base `feature/access-libred`, milestone `6.x`.

## P1 Problem

#5956 ships LibRed (`Access.LibRed`, configs `Access.LibRed.Mdb` / `Access.LibRed.Accdb`) as a third
`AccessProvider` flavour on the unchanged Access dialect. Two consequences, both measurable:

1. **Tests.** `TestProvName.AllAccess` = `AllNativeAccess` + `AllAccessLibRed` (`Tests/Base/TestProvName.cs`), and
   provider matching is exact-name (`Tests/Base/ProviderNameHelpers.cs:17-27`, `DataSourcesBaseAttribute.cs:61`), so
   every one of ~387 exclusion-form `[DataSources(... AllAccess ...)]` sites, the exclusion feature sources
   `MergeDataContextSourceAttribute.cs:14` (190 uses) / `SupportsAnalyticFunctionsContextAttribute.cs:17` (195) /
   `SupportsDateTimeOffsetContextAttribute.cs:24` (3) and ~115 `Throws*` attributes also exclude LibRed. None of
   these tests has ever executed on LibRed.
2. **SQL.** LibRed's engine accepts window functions, CROSS/OUTER APPLY, CROSS JOIN, FULL JOIN, OFFSET/FETCH,
   `TOP @p`, INTERSECT/EXCEPT, CASE, VALUES as a table source, TRUE/FALSE (grammar `AccessSql.g4` @
   `v11.0.0-alpha.3`), but linq2db emits none of it for LibRed: all flags in `AccessDataProvider.cs:42-73` are
   flavour-independent except `IsParameterOrderDependent`, `AccessSqlBuilderBase.cs:141-149` lowers CASE to IIF,
   `FirstFormat` is `TOP {0}` only (`:70`), `AccessWindowFunctionsMemberTranslator.IsWindowFunctionsSupported =>
   false` (`Translation/AccessMemberTranslator.cs:458`), `IsSkipSupported = false` (`AccessDataProvider.cs:46`).
   A `Skip`/`Take` page, a window function or an APPLY on LibRed is therefore rejected or evaluated client-side
   where the engine could run it.

## P2 Success criteria

- SC-1 Every test excluded for Access by a *dialect* exclusion runs on both LibRed configs, unless LibRed does not advertise the feature (then excluded again by name, `TestProvName.AllAccessLibRed`) → TO-1
- SC-2 For each advertised feature enabled, LibRed emits the extended form and that feature's tests pass on both LibRed configs → TO-2, TO-3, TO-4, TO-5, TO-6, TO-7, TO-8, TO-9
- SC-3 Native Access flavours unchanged: `Access.Ace.OleDb` full suite has the base failure set (`TestExpressionVisitorHops(10)` only) and byte-identical baselines to a base capture → TO-10
- SC-4 Full suite on both LibRed configs ends with 0 unexplained failures — each red fixed, re-excluded (not advertised) or `[ActiveIssue]`-gated on `AllAccessLibRed` (advertised but defective, recorded in `plans/feature-access-libred/findings.md`) → TO-11

## P3 Constraints & anti-goals (M/L)

- `TestProvName.AllAccess` keeps its definition (native + LibRed) — user direction. No new constants unless one is
  needed for a recurring LibRed-feature list.
- Native flavours' SQL and flags do not change (SC-3). Every provider-side change is a LibRed-only arm.
- No change to SQL AST, `IDataProvider`, translator interfaces, `BasicSqlBuilder` or `BasicSqlOptimizer`. If a
  failure seems to need one, stop and raise it.
- No public API outside `LinqToDB.Internal.*`.
- Not in scope: CTE, MERGE, OUTPUT/RETURNING, CAST, IS DISTINCT FROM, LATERAL, INTERSECT/EXCEPT ALL, ROLLUP,
  NULLS FIRST/LAST, LIKE ESCAPE, UPDATE…FROM — LibRed's grammar has none of them.
- Provider-specific Access tests (`[IncludeDataSources]` naming Access) are not retargeted.

## P4 Unknowns (M/L)

- U-1 Does `LibRedSqlMode` gate the engine? — no: it lives only in `LibRed.EFCore` (`LibRed.EFCore/Infrastructure/LibRedSqlMode.cs`); README: "The mode changes what the provider generates, not what the engine accepts" — resolved-by scout (upstream source @ v11.0.0-alpha.3)
- U-2 Which features does LibRed advertise? — supported: window functions (+ frames, LAG/LEAD, aggregate OVER at alpha.3), CROSS/OUTER APPLY, CROSS JOIN, FULL JOIN, OFFSET/FETCH (skip-only, expression counts), `TOP @p`, INTERSECT/EXCEPT (distinct), CASE, COALESCE/NULLIF, GREATEST/LEAST, VALUES table source, TRUE/FALSE, STRING_AGG; not: CTE, MERGE, OUTPUT, CAST, IS DISTINCT FROM, LATERAL, set-op ALL except UNION, ROLLUP, NULLS FIRST/LAST, LIKE ESCAPE — grammar rules `offsetFetchClause`, `joinClause # CrossApply/# OuterApply`, `joinType # FullJoin`, `setOperator`, `caseExpression`, `queryTerm # ValuesTerm`, `windowFrame` — resolved-by scout
- U-3 Grammar acceptance ≠ correct semantics. — each enabled feature is proven by running its existing tests on both LibRed configs (TO-2..TO-9); a wrong-result defect gets an `[ActiveIssue]` on `AllAccessLibRed` rather than a disabled feature, unless it makes the feature unusable (then the flag stays off and P10 records the measurement) — resolved-by probe (per-bucket runs)
- U-4 COUNT(DISTINCT x) / aggregate DISTINCT (`AccessMemberTranslator.cs:452-453` false) — not in the grammar survey; decided by probe in the aggregate bucket; stays false if the probe rejects — resolved-by probe
- U-5 Does the Linux CI leg `z_Access_LibRed` pass on the base? — #5956's run 35801786703 failed on `\` paths; `3b6b73ba7` fixed them; a green base run is a precondition for using CI as the full-suite gate, otherwise the full suite runs locally on Windows (17 min measured on #5956) — resolved-by probe (CI dispatch on the base before TO-11)
- U-6 Do `IsAnyOf(AllAccess)` runtime branches (~19, e.g. `TakeSkipTests.cs:751`, `MergeTests.Types.cs:387`) mis-handle LibRed once features are on? — left as is; changed only where a failing test points at one — resolved-by user answer (plan approval: "if needed - add AllAccessLibRed")
- U-7 Harness capability for TO-1: running the full suite restricted to two providers — `--provider` per run is supported (`.claude/docs/testing.md` → *Scoping a run to specific providers*), and `/test` forwards it in worktree mode — resolved-by scout

## P5 Decisions (M/L; rejected alternatives mandatory at L)

### D-1 — How LibRed gets back into dialect-excluded tests

- **chosen:** script-rewrite `TestProvName.AllAccess` → `TestProvName.AllNativeAccess` at exclusion-form sites only
  (`[DataSources]` exclusion lists incl. multi-line, shared exclusion constants, `Issue269Tests`
  `TestDataContextSourceAttribute`, the three exclusion feature sources, `Throws*` attributes, `[ActiveIssue]`
  configurations); then re-add `TestProvName.AllAccessLibRed` beside `AllNativeAccess` at sites where triage shows
  LibRed also lacks the feature.
- **rejected:** redefine `AllAccess` as native-only — user rejected it; it would also silently drop LibRed from the
  ~68 `[IncludeDataSources]` Access tests.
- **rejected:** hand-edit each site — ~500 near-identical edits, unreviewable (AGENTS.md → *fix the loop*).
- **why this:** keeps `AllAccess` semantics, makes the enablement one reviewable transformation, and every
  re-exclusion is a visible, named `AllAccessLibRed` token that says "LibRed doesn't advertise this".
- **failure mode of the choice:** the rewrite also narrows sites whose exclusion is *not* dialect (a transport or
  schema trait); those surface as LibRed failures in triage and get `AllAccessLibRed` re-added, so the cost is
  triage time, not silent coverage loss. A test that passes on LibRed for the wrong reason is not caught — same
  risk as any provider enablement.

### D-2 — Re-exclusion spelling

- **chosen:** `TestProvName.AllNativeAccess, TestProvName.AllAccessLibRed` — never revert to `AllAccess`.
- **rejected:** revert the site to `AllAccess` — reads cleaner but erases the fact that LibRed was evaluated.
- **why this:** after this branch, a bare `AllAccess` in an exclusion means "not yet evaluated for LibRed"; the
  two-token form means "evaluated, LibRed lacks it too".
- **failure mode of the choice:** longer attribute lines; column alignment in multi-line lists has to be kept.

### D-3 — Where the LibRed dialect lives

- **chosen:** LibRed-only arms in the existing flavour seams: flags in the `AccessDataProvider` ctor under
  `if (provider == AccessProvider.LibRed)`; SQL rendering in `AccessLibRedSqlBuilder`; a new
  `AccessLibRedMemberTranslator : AccessMemberTranslator` selected in `CreateMemberTranslator` by `Provider`;
  a new `AccessLibRedSqlOptimizer : AccessSqlOptimizer` (with `AccessLibRedSqlExpressionConvertVisitor` if needed)
  selected in the ctor by `Provider`.
- **rejected:** `if (Provider == LibRed)` inside shared `AccessSqlBuilderBase` / `AccessSqlOptimizer` /
  convert visitor — the optimizer and visitor are constructed without the provider today, and branching inside
  shared code puts native SQL at risk (SC-3).
- **rejected:** a separate provider family beside Access — duplicates every `ProviderName.Access`-keyed `Sql.*`
  registration and mapping schema; #5956 chose the flavour shape for that reason.
- **why this:** mirrors how #5956 already split the builder and schema provider; native code paths are untouched
  by construction.
- **constraint (remote):** `RemoteDataContextBase.cs:524,537` builds the optimizer by reflection from a public
  `(SqlProviderFlags)` / `(SqlProviderFlags, DataOptions)` ctor, `:164` the member translator from a public
  parameterless ctor, and `:498` passes `provider: null` to the builder. So the new types are public and take no
  `AccessProvider` argument — selection happens in `AccessDataProvider`, never inside the types.
- **failure mode of the choice:** some Access restrictions live in private members of the shared optimizer
  (`CorrectInnerJoins`, `CorrectExistsAndIn` at `AccessSqlOptimizer.cs:88,154`); making them skippable needs a
  `protected virtual` hook on the shared type — an edit to a shared Access file, allowed as long as the native
  path keeps today's behaviour (TO-10).

### D-4 — Paging syntax

- **chosen:** SqlCe shape — builder `SqlCeSqlBuilder.cs:31-46` (`TOP ({0})` when no skip, else `OFFSET {0} ROWS` +
  `FETCH NEXT {0} ROWS ONLY`, `OffsetFirst = true`) **plus** its optimizer half, `SqlCeSqlOptimizer.CorrectSkipAndColumns`
  (`SqlCeSqlOptimizer.cs:107-141`, injects ORDER BY when `SkipValue != null && OrderBy.IsEmpty`; SQL Server 2012's
  twin is `AddOrderByForSkip`, `SqlServer2012SqlOptimizer.cs:39-56`) in E-7. Flags `IsSkipSupported`,
  `AcceptsTakeAsParameter` true for LibRed; `IsSubQuerySkipSupported` only once a derived-table OFFSET is probed.
- **rejected:** `TOP` + client-side skip (today's behaviour) — defeats the purpose.
- **why this:** grammar `offsetFetchClause` accepts skip-only and expression counts; SqlCe is the in-repo precedent.
- **failure mode of the choice:** the ORDER BY injection is unnecessary if LibRed's `offsetFetchClause` does not
  hang off ORDER BY (not recorded in U-2) — a harmless extra ORDER BY, same as SqlCe; OFFSET inside a derived
  table is unprobed, hence `IsSubQuerySkipSupported` is gated on a probe.

## P6 Edit-points

- E-1 `Tests/**/*.cs` (exclusion-form sites, per D-1) — `AllAccess` → `AllNativeAccess`, by script `.build/.agents/libred-narrow-exclusions.ps1`
- E-2 `Tests/Base/Attributes/FeatureSources/MergeDataContextSourceAttribute.cs`, `SupportsAnalyticFunctionsContextAttribute.cs` — same narrowing (the E-1 script). `SupportsDateTimeOffsetContextAttribute` is **not** narrowed: `AccessDataProvider.cs:158-159` strips the offset for every flavour, so it is not a dialect exclusion
- E-3 `Tests/**/*.cs` — re-add `TestProvName.AllAccessLibRed` (D-2) / `[ActiveIssue]` on `AllAccessLibRed` / per-flavour `ThrowsForProvider`, per triage; and, decided up front, the assertion-skipping `IsAnyOf(AllAccess)` sites `ConvertExpressionTests.cs:399,442` and `WhereTests.cs:1483-1490` narrow to `AllNativeAccess` so LibRed runs the assertions (a skip there can never surface as a failure)
- E-4 `Tests/Base/TestProvName.cs:WithApplyJoin,WithWindowFunctions` and `Tests/Base/Attributes/FeatureSources/AllJoinsSourceAttribute.cs` — add `AllAccessLibRed` once the feature is on
- E-5 `Source/LinqToDB/Internal/DataProvider/Access/AccessDataProvider.cs:.ctor,CreateMemberTranslator` — LibRed flag arm; optimizer + member-translator selection by `Provider`
- E-6 `Source/LinqToDB/Internal/DataProvider/Access/AccessLibRedSqlBuilder.cs` — paging (D-4), native CASE, join rendering, `IsValuesSyntaxSupported`, set operators, as the flags require
- E-7 `Source/LinqToDB/Internal/DataProvider/Access/AccessLibRedSqlOptimizer.cs` (new) — skip Jet-only rewrites per D-3
- E-8 `Source/LinqToDB/Internal/DataProvider/Access/AccessSqlOptimizer.cs` — `protected virtual` hooks for the rewrites E-7 skips; native behaviour unchanged
- E-9 `Source/LinqToDB/Internal/DataProvider/Access/Translation/AccessLibRedMemberTranslator.cs` (new) — window functions on, STRING_AGG for `string.Join`, aggregate DISTINCT per U-4
- E-10 `Source/LinqToDB/Internal/DataProvider/Access/AccessSqlExpressionConvertVisitor.cs`, `AccessLibRedSqlExpressionConvertVisitor.cs` (new) — only if a bucket needs NULLIF / COALESCE / CASE conversion off for LibRed
- E-11 `Source/LinqToDB/PublicAPI/PublicAPI.Unshipped.txt` — entries for any new public type in `LinqToDB.Internal.DataProvider.Access`
- E-12 `.claude/plans/feature-access-libred/findings.md` — new LibRed defects found in advertised features
- E-13 `Source/LinqToDB/Internal/DataProvider/Access/AccessSqlBuilderBase.cs:BuildSqlCaseExpression,BuildSqlConditionExpression` — a `protected virtual bool` toggle (native default = IIF) so `AccessLibRedSqlBuilder` falls through to the `BasicSqlBuilder` CASE bodies (`BasicSqlBuilder.cs:3997-4027,4046-4082`) instead of duplicating them
- E-14 `Source/LinqToDB/Sql/WindowFunctions.FeatureMatrix.md:23` — Access row split: LibRed supports window functions

## P7 Impact map (M/L)

- `Tests/Base/TestConfiguration.cs:218,277` — `TestProvName.AllAccess` in the `Providers` **inclusion** list feeding `GetCreateDatabaseProviders` (`:246-258`); textually like a multi-line exclusion row, so the E-1 script recognises sites by enclosing attribute (`DataSources*` / `Throws*` / `ActiveIssue` / the named constants), not by line, and this file is its negative control — out-of-scope
- `Tests/Base/ProviderNameHelpers.cs:17-27` — `IsAnyOf` is exact-name on comma-split lists; searched `bool IsAnyOf` in `Tests/Base` — rewrite semantics hold — covered by E-1
- `Tests/Base/Attributes/DataSourcesBaseAttribute.cs:61` — providers split on `,` and trimmed; searched `Split(','` in `Tests/Base/Attributes` — `AllNativeAccess` expands correctly — covered by E-1
- ~387 exclusion sites (195 `[DataSources(`, 79 `(true,`, 18 `(false,` single-line + ~95 multi-line, e.g. `JoinTests.cs:1451-1846`, `AnalyticTests.cs:1312-1909`, `UpdateTests.cs:1551-1679`) — searched `git grep -E "AllAccess\b"` over `Tests/` at `3b6b73ba7` with an attribute-context script — covered by E-1
- shared exclusion constants `TagTests.cs:18`, `NullableBoolTests.cs:26`, `DateOnlyFunctionTests.cs:42`, `IntervalTranslationTests.cs:185/197/234`, `StringTrimTests.cs:40`; `Issue269Tests.cs:14-18` — same search — covered by E-1
- `IdlTests.cs:21-29` `IdlProvidersAttribute : IncludeDataSourcesAttribute` lists `AllAccess` as *supported* — inclusion, not narrowed — out-of-scope
- ~68 `[IncludeDataSources]` naming Access (55 Access-only, 13 mixed, e.g. `TakeSkipTests.cs:673/687/796`, `Issue4415Tests.cs:22`) — LibRed already included via `AllAccess` — out-of-scope
- 115 `Throws*` attributes (66 `ThrowsForProvider`, 44 `ThrowsCannotBeConverted`, 5 `ThrowsRequiredOuterJoins`); 26 of the `ThrowsForProvider` in `PredicateTests.cs:172-656` are already per-flavour — narrowing makes LibRed run the non-throw path; failing ones get LibRed re-added — covered by E-1, E-3
- 27 `[ActiveIssue]` naming Access (5 `AllAccess` per critic re-count, e.g. `DataTypesTests.cs:269`, `MappingTests.cs:1435`, `SelectQueryTests.cs:284`, `InsertTests.cs:2421`, `L2SAttributeTests.cs:74`; `UpdateFromTests.cs:713` already reads `AllNativeAccess`) — run-and-verify attribute reports a LibRed pass as a failure — covered by E-1, E-3
- 55 `IsAnyOf(...)` runtime sites naming Access (30 `AllAccess` per critic re-count: 28 in `Tests/Linq` + `TestBase.Identity.cs:30,155`) — input-changing sites (e.g. `TakeSkipTests.cs:751`) unchanged unless a failure points there (U-6); assertion-skipping sites pre-decided in E-3 — covered by E-3
- inclusion feature sources `AllJoinsSourceAttribute` (8 uses), `CteContextSourceAttribute` (41), `RecursiveCteContextSourceAttribute` (40), `IdentityInsertMergeDataContextSourceAttribute` (7), `MergeNotMatchedBySourceDataContextSourceAttribute` (42) — Access absent; CTE/MERGE not advertised — `AllJoinsSource` covered by E-4, rest out-of-scope
- `TestProvName.cs` `WithApplyJoin` (8 `IncludeDataSources` uses: `CountByMethodTests.cs:108/122`, `ExceptByMethodTests.cs:51/66`, `IndexMethodTests.cs:69/83`, `IntersectByMethodTests.cs:51/66`), `WithWindowFunctions` (0 uses) — covered by E-4
- 19 `ErrorHelper.Error_OUTER_Joins` expectations (`GroupByTests.cs:899…`, `JoinTests.cs:405…`, `JoinToLimitedTests.cs:180…`, `SelectTests.cs:1396…`, `ElementOperationTests.cs:163`), 4 `Error_Skip_in_Subquery` (`DistinctTests.cs:614/652`, `EagerLoadingTests.cs:3310`, `SubQueryTests.cs:203`), 3 `Error_RowNumber` (`EagerLoadingTests.cs:1237/1270`) keyed on `AllAccess` — flip when apply/skip/window flags go on — covered by E-1, E-3
- `AccessDataProvider.cs:36-100` — one ctor sets flags for all five flavours; only `IsParameterOrderDependent` (`:61`) and the char-field reader (`:80`) are LibRed-aware; `_sqlOptimizer = new AccessSqlOptimizer(SqlProviderFlags)` (`:99`) — covered by E-5
- `AccessDataProvider.cs:107-112` `CreateMemberTranslator` picks by `Version` only; LibRed is `AccessVersion.Ace` (`:31`) — covered by E-5, E-9
- `AccessSqlBuilderBase.cs:54-77,141-149,228-230` — nested joins off, VALUES off, `TOP {0}`, CASE→IIF, MERGE throws; `AccessLibRedSqlBuilder.cs` overrides only `BuildObjectName` — covered by E-6
- `AccessSqlOptimizer.cs:21-34` — `CorrectMultiTableQueries`, `CorrectInnerJoins` (`:88`), `CorrectExistsAndIn` (`:154`), alternative DELETE, `CorrectAccessUpdate`; `Finalize` → `WrapParameters` (ODBC workaround, applies to all) — covered by E-7, E-8
- `AccessSqlExpressionConvertVisitor.cs:236,263,345` — `SupportsNullIf` false, LIKE escape throws, COALESCE→IIF — covered by E-10 (only if a bucket needs it)
- `Translation/AccessMemberTranslator.cs:452-461` — aggregate DISTINCT off, window functions off — covered by E-9
- `SqlCeSqlBuilder.cs:31-46` + `SqlCeSqlOptimizer.cs:107-141` — OFFSET/FETCH precedent, builder and ORDER BY injection — covered by E-6, E-7
- `Internal/Linq/QueryRunner.cs:442-457` (client-side Skip when unsupported), `Internal/Linq/Builder/SetOperationBuilder.cs:55-57` (Intersect/Except emulated when `IsDistinctSetOperationsSupported` is false) — the base already passes those tests, so their proof is SQL shape (TO-2, TO-7) — covered by E-5
- `BasicSqlOptimizer.cs:2502-2564` `CorrectMultiTableQueries` — only half flag-driven; E-7 decides whether LibRed skips it — covered by E-7
- `Remote/RemoteDataContextBase.cs:164,498,524,537` — reflection ctors for translator / optimizer, `provider: null` builder — covered by E-7, E-9 (D-3 constraint)
- `Source/LinqToDB/Sql/WindowFunctions.FeatureMatrix.md:23`, cited from `SupportsAnalyticFunctionsContextAttribute.cs:10` — Access listed as having no window functions — covered by E-14
- `Build/Azure/pipelines/templates/test-matrix.yml:493-503`, `Build/Azure/configs/access.libred.json` — CI leg is Linux, net11.0 only — out-of-scope (bounds TO-11)
- `Source/LinqToDB/Sql/Sql.cs` / `Linq/Expressions.cs` `ProviderName.Access`-keyed registrations reach LibRed through the mapping-schema chain (#5956 plan P7) — unaffected — out-of-scope

## P8 Test obligations (M/L)

- TO-1 After E-1/E-2 alone (no provider change), full suite on `Access.LibRed.Mdb` + `Access.LibRed.Accdb`: the failure list is captured and every failure is bucketed by cause; at the end of triage no failure remains unbucketed — proof: characterization (the pre-change list is the inventory; it proves coverage, not behaviour)
- TO-2 Paging: the base already passes `TakeSkipTests` via client-side skip (`QueryRunner.cs:442-457`), so the observable is SQL shape — LibRed baselines for `TakeSkipTests` contain `OFFSET … ROWS` where the base capture has none (named baseline diff). The `Error_Skip_in_Subquery` sites (`DistinctTests.cs:614/652`, `SubQueryTests.cs:203`, `EagerLoadingTests.cs:3310`) are red only **after** E-1 narrows their `Throws*` attribute, then green with D-4 — proof: red→green (post-E-1) + baseline diff
- TO-3 Paging without ORDER BY: an existing `Skip`-without-`OrderBy` test in `TakeSkipTests` on LibRed emits an injected ORDER BY (E-7) and returns the same rows — proof: characterization + baseline diff
- TO-4 Window functions: `WindowFunctionsTests`, `AnalyticTests` (via `SupportsAnalyticFunctionsContextAttribute`), `Error_RowNumber` sites (incl. the `*ByMethodTests` `[ThrowsCannotBeConverted]` rows) — red only after E-1/E-2 narrow them, green with E-5/E-9 — proof: red→green (post-E-1)
- TO-5 APPLY: the 19 `Error_OUTER_Joins` sites + `WithApplyJoin` tests — red only after E-1 narrows them, execute with `IsApplyJoinSupported` — proof: red→green (post-E-1)
- TO-6 CROSS / FULL JOIN: `AllJoinsSourceAttribute` tests + `JoinTests` full-join cases — proof: red→green
- TO-7 INTERSECT / EXCEPT: the base emulates them (`SetOperationBuilder.cs:55-57`) and passes, so the observable is SQL shape — LibRed baselines of the `ConcatUnionTests` Intersect/Except cases contain `INTERSECT`/`EXCEPT` where the base capture has the emulation, with equal results (duplicate rows on both sides); `*All` variants and the 5 `Union5x` exclusions (`ConcatUnionTests.cs:486-535`) decided by triage — proof: characterization (observable: baseline diff)
- TO-8 CASE: LibRed baselines of a `Select` ternary / `switch` test contain `CASE WHEN` where the base capture has `IIF(`, rows equal; `Access.Ace.OleDb` baselines still `IIF(` (TO-10) — proof: control (observable: baseline diff)
- TO-9 VALUES table source, STRING_AGG (`StringJoinTests`), aggregate DISTINCT (U-4) — each only if its bucket enables it; else the bucket's re-exclusion is the obligation — proof: red→green per enabled feature
- TO-10 Symmetry guard on the unchanged path: `Access.Ace.OleDb` full suite (own host) = base failure set; its baselines byte-identical to a base capture — proof: characterization
- TO-11 Full suite on both LibRed configs after triage: 0 unexplained failures (SC-4); on CI leg `z_Access_LibRed` if U-5 is green, else locally — proof: characterization

## P9 Verification gates

- G-01: — (pending)
- G-02: — (pending)
- G-03: — (pending)
- G-04: — (pending)
- G-05: — (pending)
- G-06: — (pending)
- G-07: — (pending)
- G-08: — (pending)
- G-09: — (pending)

## P10 Adjudicated (M/L)

_None yet._

## P11 Amendments (M/L)

_None._

## P12 Critic verdict (M/L)

weak — round 1, `plan-critic` on **fable**. The stored `criticModel: opus` is the author's own family and the skill
requires a different one, so fable was passed explicitly on the dispatch. Objections and responses:

- E-6 native CASE is unreachable from the grandchild builder → added E-13 (`protected virtual` toggle in `AccessSqlBuilderBase`).
- P7 missed the `TestConfiguration.cs:218` inclusion list → row added; the E-1 recogniser is attribute-context, with this file as its negative control.
- D-4 half-cited SqlCe (no ORDER BY injection) → D-4 now cites `SqlCeSqlOptimizer.cs:107-141` / `SqlServer2012SqlOptimizer.cs:39-56`, the injection is in E-7, `IsSubQuerySkipSupported` is gated on a probe, TO-3 rewritten.
- TO-2/TO-7/TO-8 are not red on the base (client skip, set-op emulation) → rewritten around SQL-shape baseline observables; TO-2/4/5 state their reds exist only after E-1.
- Remote reflection-ctor constraint → recorded in D-3.
- Census numbers (`IsAnyOf` 30 not 19, `ActiveIssue` 5 not 7; `UpdateFromTests.cs:713` already native) → P7 corrected; the FeatureMatrix doc added as E-14.
- U-6 is blind at assertion-skipping sites → `ConvertExpressionTests.cs:399,442`, `WhereTests.cs:1483-1490` pre-decided in E-3.
- `SupportsDateTimeOffsetContextAttribute` is not a dialect exclusion → dropped from E-2.

What the critic searched: `AllAccess\b` across `Tests` (all file kinds), `IsAnyOf` / `ActiveIssue` regexes,
`WithApplyJoin`, the Remote reflection ctors, `IsWindowFunctionsSupported`, set-op / skip / join flags, the SqlCe
and SqlServer ORDER BY precedents, PublicAPI, the CI leg. Not checkable by it: the grammar itself,
OFFSET-under-ORDER-BY, OFFSET / VALUES inside derived tables, aggregate DISTINCT — left to per-bucket probes (U-3,
U-4). No second round: every objection was accepted as stated, none disputed.
