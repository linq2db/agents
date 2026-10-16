# Work plan: feature-access-libred-dialect — LibRed extended SQL dialect

**Tier:** L  ·  **Status:** approved  ·  **Approved-at:** 2026-09-23 (E-1..E-14, after critic round 1); 2026-10-16 (A-6, E-20..E-25, after critic round 4)  ·  **Branch:** feature/access-libred-dialect
**Schema:** `.claude/docs/work-plan.md`  ·  **Gates:** `.claude/docs/definition-of-done.md`

Base: `origin/feature/access-libred` @ `3b6b73ba7` (#5956). Child PR, draft, base `feature/access-libred`, milestone `6.x`.

## Resuming (2026-09-24)

**Where things are.** Draft PR **#5969** (base `feature/access-libred`, milestone `6.x`), branch
`feature/access-libred-dialect` pushed with its own upstream — two commits, `02960914f` (provider) and `60f299542`
(tests). The worktree was removed at session end; recreate with `git worktree add
C:/Worktrees/linq2db/access-libred-dialect origin/feature/access-libred-dialect` (then bootstrap `.claude/` by
`git clone --reference`, as the post-checkout hook does not fire from this primary clone) — cold `Tests/Linq`
net11.0 build ≈ 6 min. Local runs use `Access.LibRed.Mdb` only (user: both configs on CI only).

**Measured trajectory** (full `Access.LibRed.Mdb` suite, net11.0 Debug build of `Tests/Linq`): 1227 → 340 → 109 → 36 →
2 (run 5) → 10 (run 6). Run 5's two: `TestExpressionVisitorHops(10)` (provider-independent, pre-existing) and
`LeftJoinSubqueryDoNotOptimize` (LinqService only, red in every run — not investigated).

**Open — in order:**
1. **Boolean sort keys — DONE locally (2026-09-24, uncommitted in the worktree), after ChrisJollyAU's
   [#5969 comment](https://github.com/linq2db/linq2db/pull/5969#issuecomment-5810265686) ("just use NOT / unary minus").**
   OLE DB probe (`.build/.agents/probe-bool-sortkey-oledb.ps1`): `NOT b` / `-b` sort correctly, but any expression key
   under DISTINCT is still rejected, while `ORDER BY (b) DESC` is accepted. Shipped: `AccessBooleanSortKeyLoweringVisitor`
   deleted; `AccessSqlExpressionConvertVisitor` order/window items — non-nullable key → flipped direction, wrapped in an
   int-typed `({0})`; nullable key → int-typed unary minus. The int type makes it idempotent — the remote path converts
   on the client *and* the server (`RemoteDataContextBase.QueryRunner`, `isAlreadyOptimizedAndConverted: true`), and a
   bare flip was undone there (LinqService-only reds). 33/33 on OleDb + LibRed.Mdb incl. LinqService. Residual: a
   *nullable* key under DISTINCT on native Jet is still rejected (engine limit).
   Previous state, kept for the record: **Boolean sort keys (A-1/A-4) were half-done.** Probe proved the critic right: with the render-time rewrite, native
   `Access.Ace.OleDb` fails `DistinctTests.DistinctOrderByBoolean` with *"ORDER BY clause (IIf([t].[BoolValue]=-1,1,0))
   conflicts with DISTINCT"*. The relocated pre-`base.Finalize` pass (`AccessBooleanSortKeyLoweringVisitor`) does
   **not** fix it — DISTINCT and ORDER BY already sit on one `SelectQuery` there, so a derived key under DISTINCT still
   needs a wrap-in-subquery (or must be left alone) — and it **regressed** the window keys (run 6: `Issue2842Test1`,
   `Issue5123Test`, `PercentileDiscWithBooleanOrderBy`, `RowNumberWithBooleanComputedValues`, all ×2): window
   `ORDER BY`/`WITHIN GROUP` items are not reached before optimization. Next: put the window-item rewrite back in the
   convert visitor (no select-list constraint there — the code removed in A-4 is in this conversation's history and
   in `.build/.agents/probe-old-sortkey.ps1`), and decide the DISTINCT case in the pre-pass: wrap the query, or skip a
   key that is not already in the DISTINCT projection. Re-run the two new `DistinctTests` on OleDb + LibRed.
2. **Native crash is NOT from this branch (measured 2026-09-24).** Head `d2f8dd89e`: `0xC0000005` in
   `ICommandText.Execute` after 2097 results, in `ConvertTests.ConvertFromOneToAnother` (passes when run alone). Base
   `3b6b73ba7` (#5956, worktree `C:/Worktrees/linq2db/access-libred-base`): same `0xC0000005` after 5030 results, in
   `InheritanceTests.TestInsertIssue2`. Different test and count each run → cumulative native ACE state, pre-existing — a known OLE DB driver issue (user, 2026-09-24); closed, base worktree removed.
   Recovered results: the only failure on both is `TestExpressionVisitorHops(10)`. Logs `.build/.agents/oledb-e7.*`,
   `oledb-base.*`. Earlier note, kept: **Native control never completed.** `Access.Ace.OleDb` full suite crashed twice with `0xC0000005` inside
   `ICommandText.Execute`, at ~2120 results both times (logs `.build/.agents/oledb-e5.log`, `oledb-e6.log`); the
   faulting statement is not logged. Establish whether the base branch crashes at the same point (build the base in a
   second worktree, or bisect the shared-file edits) before calling it the #5956 driver flake.
3. **CASE for conditions (A-4)**: in run 6; the three `Sum*SubqueryEmpty` R13 gates did **not** fail as "passed but
   gated", so check whether they still fail as gated or pass — then drop or keep the gates.
4. **Critic round 3** on A-4 once 1–3 are measured (one round, `plan-critic` on fable — config says opus = author).
5. Then: Release build `Source/LinqToDB -c Release -f net10.0` and `-f netstandard2.0` (G-05, analyzers, XML docs);
   `/api-baselines` is a release task (memory) — PublicAPI.Unshipped already hand-listed (91 entries); commit in
   logical chunks per user preference; push; draft PR on `feature/access-libred`; CI both LibRed configs
   (`gh workflow run tests.yml --ref feature/access-libred-dialect -f surface='[access.all]'`).

**Scripts** (all under `.build/.agents/`): `libred-narrow-exclusions.ps1` (E-1, applied), `libred-reexclude.ps1`
(`File.cs:Method` specs, `-Token`), `libred-add-throws.ps1`, `trx-buckets.ps1`, `trx-reasons.ps1`,
`libred-access-census.ps1`, `probe-old-sortkey.ps1` (`-Restore` already run).

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
- SC-3 Native Access flavours unchanged except boolean sort keys (A-1: direction flip / unary minus, OleDb and ODBC): `Access.Ace.OleDb` suite, run in chunks (P10), has the base failure set (`TestExpressionVisitorHops(10)` only) and baselines identical to a base capture outside that delta → TO-10
- SC-4 Full suite on both LibRed configs ends with 0 unexplained failures — each red fixed, re-excluded (not advertised) or `[ActiveIssue]`-gated on `AllAccessLibRed` (advertised but defective, recorded in `plans/feature-access-libred/findings.md`) → TO-11

## P3 Constraints & anti-goals (M/L)

- `TestProvName.AllAccess` keeps its definition (native + LibRed) — user direction. No new constants unless one is
  needed for a recurring LibRed-feature list.
- Native flavours' SQL and flags do not change (SC-3). Every provider-side change is a LibRed-only arm.
- No change to SQL AST, `IDataProvider`, translator interfaces, `BasicSqlBuilder` or `BasicSqlOptimizer`. If a
  failure seems to need one, stop and raise it.
- No public API outside `LinqToDB.Internal.*`.
- Not in scope: CTE, MERGE, OUTPUT/RETURNING, CAST, LATERAL, INTERSECT/EXCEPT ALL, ROLLUP,
  NULLS FIRST/LAST, LIKE ESCAPE, UPDATE…FROM — LibRed's grammar has none of them (`IS DISTINCT FROM` moved in
  scope by A-6, alpha.4).
- Provider-specific Access tests (`[IncludeDataSources]` naming Access) are not retargeted — except where the test
  asserts a Jet limit LibRed lifts by design (A-3: the two second-resolution tests in
  `IntervalTranslationTests.Difference.cs`, narrowed to `AllNativeAccess`).

## P4 Unknowns (M/L)

- U-1 Does `LibRedSqlMode` gate the engine? — no: it lives only in `LibRed.EFCore` (`LibRed.EFCore/Infrastructure/LibRedSqlMode.cs`); README: "The mode changes what the provider generates, not what the engine accepts" — resolved-by scout (upstream source @ v11.0.0-alpha.3)
- U-2 Which features does LibRed advertise? — supported: window functions (+ frames, LAG/LEAD, aggregate OVER at alpha.3), CROSS/OUTER APPLY, CROSS JOIN, FULL JOIN, OFFSET/FETCH (skip-only, expression counts), `TOP @p`, INTERSECT/EXCEPT (distinct), CASE, COALESCE/NULLIF, GREATEST/LEAST, VALUES table source, TRUE/FALSE, STRING_AGG; not: CTE, MERGE, OUTPUT, CAST, IS DISTINCT FROM, LATERAL, set-op ALL except UNION, ROLLUP, NULLS FIRST/LAST, LIKE ESCAPE — grammar rules `offsetFetchClause`, `joinClause # CrossApply/# OuterApply`, `joinType # FullJoin`, `setOperator`, `caseExpression`, `queryTerm # ValuesTerm`, `windowFrame` — resolved-by scout
- U-3 Grammar acceptance ≠ correct semantics. — each enabled feature is proven by running its existing tests on both LibRed configs (TO-2..TO-9); a wrong-result defect gets an `[ActiveIssue]` on `AllAccessLibRed` rather than a disabled feature, unless it makes the feature unusable (then the flag stays off and P10 records the measurement) — resolved-by probe (per-bucket runs)
- U-4 COUNT(DISTINCT x) / aggregate DISTINCT (`AccessMemberTranslator.cs:452-453` false) — not in the grammar survey; decided by probe in the aggregate bucket; stays false if the probe rejects — resolved-by probe
- U-5 Does the Linux CI leg `z_Access_LibRed` pass on the base? — #5956's run 35801786703 failed on `\` paths; `3b6b73ba7` fixed them; a green base run is a precondition for using CI as the full-suite gate, otherwise the full suite runs locally on Windows (17 min measured on #5956) — resolved-by probe (CI dispatch on the base before TO-11)
- U-6 Do `IsAnyOf(AllAccess)` runtime branches (~19, e.g. `TakeSkipTests.cs:751`, `MergeTests.Types.cs:387`) mis-handle LibRed once features are on? — left as is; changed only where a failing test points at one — resolved-by user answer (plan approval: "if needed - add AllAccessLibRed")
- U-7 Harness capability for TO-1: running the full suite restricted to two providers — `--provider` per run is supported (`.claude/docs/testing.md` → *Scoping a run to specific providers*), and `/test` forwards it in worktree mode — resolved-by scout
- U-8 (A-6) Which of the alpha.4 syntax additions does the engine accept, with what semantics? — measured on both containers (raw ADO, `.build/.agents/libred-a4-probe`, identical on `.mdb` and `.accdb`): `TOP 2 WITH TIES` / `TOP 50 PERCENT WITH TIES` / `TOP @p WITH TIES` / `OFFSET … FETCH NEXT 2 ROWS WITH TIES` return the tie rows (3, where plain `TOP 2` returns 2); `(VALUES (1,'x'),(2,'y')) [AS] [v]([a],[b])` with literals and with parameters, and as a `JOIN` source, return typed columns; FROM-less `SELECT NULL AS [a] WHERE 1 = 0` works; `(SELECT …) AS [q]([x],[y])` works; `IS [NOT] DISTINCT FROM` with a column, a parameter, a `NULL` parameter and a `NULL` literal, also under `IIF` and `NOT`, returns the standard results; `IS [NOT] TRUE` parses and evaluates; `CONCAT_WS` skips `NULL` items (`'a',NULL,'c'` → `a-c`, all-`NULL` → empty string, SQL Server semantics); `TRANSLATE` works; `Nz([N], 0)` is typed `String` and returns text; `GETUTCDATE()` / `SYSUTCDATETIME()` equal the client's `DateTime.UtcNow` to the second and `SYSDATETIME()` equals local `Now()` — resolved-by probe
- U-9 (A-6) Is there a seam for emitting `IS [NOT] TRUE`? — no: `SqlPredicate.IsTrue.Reduce` (`SqlPredicate.cs:874-894`) always lowers it to `expr = TrueValue` (+ `IS NULL` arm), the builder always optimizes with `reducePredicates: true` (`BasicSqlBuilder.cs:932,3168,3182`), and `BuildPredicate` has no `IsTruePredicate` case (`:2789-2890`); enabling it is a change to cross-cutting core, which P3 forbids — resolved-by scout
- U-10 (A-6) Does a `NULL` in the first `VALUES` row break column typing? — measured: `(VALUES (NULL), (2)) [v]([a])` declares `a` as `Object`/`VarChar` and returns `Int32` for row 2; linq2db's materializer reads by the mapped type, not the declared one, so this is expected to be harmless, and TO-13 is the measurement; `IsSqlValuesTableValueTypeRequired` (`BasicSqlBuilder.Merge.cs:281`) is the lever if it is not — resolved-by probe (engine side), TO-13 (linq2db side)
- U-12 (A-6, critic round 4) What do the cells round 4 found unmeasured do? — measured (`accdb3.txt:150-182`): a `NULL` **parameter** in row 1, `(VALUES (@p1 = NULL, 'x'), (2, NULL)) [v]([a],[b])`, declares `a` `Object`/`VarChar` and returns `Int32` for row 2 (same as the literal case); `CAST(NULL AS INT)` → `SqlParseException` (no `CAST` in the grammar, P3), while `SELECT NULL AS [a] WHERE 1 = 0 … [v]([a])` works; `CONCAT_WS('', 'a', NULL, 'c')` → `ac`; a `''` item keeps its separator (`CONCAT_WS(', ', '', 'M')` → `, M`, also through `IIF`/`COALESCE`), as .NET's `string.Join` does; **`SYSUTCDATETIME()` reads back `Kind=Utc`** (full tick precision), **`GETUTCDATE()` `Kind=Unspecified`** (millisecond precision), `Now()` `Kind=Local` — resolved-by probe
- U-11 (A-6) Does LibRed run under `InvariantGlobalization`? — measured **no**: with `<InvariantGlobalization>true</InvariantGlobalization>` the probe got `TypeInitializationException` from `LibRed.Engine.Execution.ExpressionEvaluator`'s static ctor on the first query that reached it, and every later query through it failed the same way; with the property removed all 44 statements ran. The test projects do not set it, so the suite is unaffected; it is an upstream report (E-25) — resolved-by probe

## P5 Decisions (M/L; rejected alternatives mandatory at L)

### D-1 — How LibRed gets back into dialect-excluded tests

- **chosen:** script-rewrite `TestProvName.AllAccess` → `TestProvName.AllNativeAccess` at exclusion-form sites only
  (`[DataSources]` exclusion lists incl. multi-line, shared exclusion constants, `Issue269Tests`
  `TestDataContextSourceAttribute`, the three exclusion feature sources, `Throws*` attributes, `[ActiveIssue]`
  configurations); then restore `TestProvName.AllAccess` (D-2) at sites where triage shows
  LibRed also lacks the feature.
- **rejected:** redefine `AllAccess` as native-only — user rejected it; it would also silently drop LibRed from the
  ~68 `[IncludeDataSources]` Access tests.
- **rejected:** hand-edit each site — ~500 near-identical edits, unreviewable (AGENTS.md → *fix the loop*).
- **why this:** keeps `AllAccess` semantics and makes the enablement one reviewable transformation.
- **failure mode of the choice:** the rewrite also narrows sites whose exclusion is *not* dialect (a transport or
  schema trait); those surface as LibRed failures in triage and get `AllAccessLibRed` re-added, so the cost is
  triage time, not silent coverage loss. A test that passes on LibRed for the wrong reason is not caught — same
  risk as any provider enablement.

### D-2 — Re-exclusion spelling

- **chosen:** revert the site to `TestProvName.AllAccess` (user, 2026-09-24) — it is the same provider set.
- **rejected:** `TestProvName.AllNativeAccess, TestProvName.AllAccessLibRed` — used first as an "evaluated for LibRed"
  marker, but the marker lived only in this plan; in code it is a redundant spelling of `AllAccess`. Collapsed by
  `.build/.agents/libred-collapse-allaccess.ps1` (59 sites, 29 files).
- **failure mode of the choice:** an exclusion no longer shows whether LibRed was evaluated for it; the triage record
  is the branch history.

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

- E-1 `Tests/*` (exclusion-form `.cs` sites, per D-1) — `AllAccess` → `AllNativeAccess`, by script `.build/.agents/libred-narrow-exclusions.ps1`
- E-2 `Tests/Base/Attributes/FeatureSources/MergeDataContextSourceAttribute.cs`, `SupportsAnalyticFunctionsContextAttribute.cs` — same narrowing (the E-1 script). `SupportsDateTimeOffsetContextAttribute` is **not** narrowed: `AccessDataProvider.cs:158-159` strips the offset for every flavour, so it is not a dialect exclusion
- E-3 `Tests/*` — re-add `TestProvName.AllAccessLibRed` (D-2) / `[ActiveIssue]` on `AllAccessLibRed` / per-flavour `ThrowsForProvider`, per triage; and, decided up front, the assertion-skipping `IsAnyOf(AllAccess)` sites `ConvertExpressionTests.cs:399,442` and `WhereTests.cs:1483-1490` narrow to `AllNativeAccess` so LibRed runs the assertions (a skip there can never surface as a failure)
- E-4 `Tests/Base/TestProvName.cs:WithApplyJoin,WithWindowFunctions` and `Tests/Base/Attributes/FeatureSources/AllJoinsSourceAttribute.cs` — add `AllAccessLibRed` once the feature is on
- E-5 `Source/LinqToDB/Internal/DataProvider/Access/AccessDataProvider.cs:.ctor,CreateMemberTranslator` — LibRed flag arm; optimizer + member-translator selection by `Provider`
- E-6 `Source/LinqToDB/Internal/DataProvider/Access/AccessLibRedSqlBuilder.cs` — paging (D-4), native CASE, join rendering, `IsValuesSyntaxSupported`, set operators, as the flags require
- E-7 `Source/LinqToDB/Internal/DataProvider/Access/AccessLibRedSqlOptimizer.cs` (new) — skip Jet-only rewrites per D-3
- E-8 `Source/LinqToDB/Internal/DataProvider/Access/AccessSqlOptimizer.cs` — `protected virtual` hooks for the rewrites E-7 skips; native behaviour unchanged
- E-9 `Source/LinqToDB/Internal/DataProvider/Access/Translation/AccessLibRedMemberTranslator.cs` (new) — window functions on, STRING_AGG for `string.Join`, aggregate DISTINCT per U-4
- E-10 `Source/LinqToDB/Internal/DataProvider/Access/AccessSqlExpressionConvertVisitor.cs`, `AccessLibRedSqlExpressionConvertVisitor.cs` (new) — the shared visitor carries the boolean sort-key rewrite for all flavours (A-1); the LibRed one only what a bucket needs (NULLIF / COALESCE / CASE conversion off)
- E-11 `Source/LinqToDB/PublicAPI/PublicAPI.Unshipped.txt` — entries for any new public type in `LinqToDB.Internal.DataProvider.Access`
- E-12 `.claude/plans/feature-access-libred/findings.md` — new LibRed defects found in advertised features
- E-13 `Source/LinqToDB/Internal/DataProvider/Access/AccessSqlBuilderBase.cs:BuildSqlCaseExpression,BuildSqlConditionExpression` — a `protected virtual bool` toggle (native default = IIF) so `AccessLibRedSqlBuilder` falls through to the `BasicSqlBuilder` CASE bodies (`BasicSqlBuilder.cs:3997-4027,4046-4082`) instead of duplicating them
- E-14 `Source/LinqToDB/Sql/WindowFunctions.FeatureMatrix.md:23` — Access row split: LibRed supports window functions
- E-15 `Source/LinqToDB/Sql/Sql.cs:Reverse` — LibRed `StrReverse` mapping (A-2)
- E-16 `Source/LinqToDB/Internal/DataProvider/Access/AccessLibRedSqlExpressionConvertVisitor.cs` (new) — LibRed convert visitor (A-2, A-3)
- E-17 `Source/LinqToDB/Sql/Sql.DateTime.cs:DateDiffBuilderAccessLibRed` — LibRed `DateDiff` builder + registration (A-3)
- E-17b `Source/LinqToDB/Sql/Sql.DateOnly.cs:DateDiff` — registration (A-3)
- E-17c `Source/LinqToDB/Sql/Sql.DateTimeOffset.cs:DateDiff` — registration (A-3)
- E-18 `Source/LinqToDB/Internal/DataProvider/Access/Translation/AccessMemberTranslator.cs:MathMemberTranslator.Power` — power helper (A-3)
- E-19 ~~`AccessBooleanSortKeyLoweringVisitor.cs`~~ — deleted in `10f517d5f`; the boolean sort-key rewrite lives in E-10 (`AccessSqlExpressionConvertVisitor`, all flavours)
- E-20 (A-6) `Source/LinqToDB/Internal/DataProvider/Access/AccessDataProvider.cs:.ctor` — LibRed block (`:76-86`): `IsDistinctFromSupported = true`; `TakeHintsSupported = TakeHints.Percent | TakeHints.WithTies` (shared value at `:53` is `Percent`)
- E-21 (A-6) `Source/LinqToDB/Internal/DataProvider/Access/AccessLibRedSqlBuilder.cs` — `BuildIsDistinctPredicate` override emitting the standard `IS [NOT] DISTINCT FROM` (the `SqlServer2022SqlBuilder.cs:26-31` shape, since `AccessSqlBuilderBase.cs:118-131` overrides it with IIF); `IsValuesSyntaxSupported => true`, `SupportsColumnAliasesInSource => true` (shared `false` at `AccessSqlBuilderBase.cs:56-57`)
- E-22 (A-6) `Source/LinqToDB/Internal/DataProvider/Access/Translation/AccessLibRedMemberTranslator.cs` — string translator: **only the separator branch** of the item form of `TranslateStringJoin` (`:160-167`) uses `ConfigureConcatWs` (native `CONCAT_WS`) instead of the `Mid` emulation; the `withoutSeparator` branch (`:156`, reached by `string.Concat(IEnumerable)`) stays on `ConfigureConcat` — unlike `SqlServer2017MemberTranslator.cs:111`, which routes both; date translator: `TranslateUtcNow` → `GETUTCDATE()` (U-12: `SYSUTCDATETIME()` reads back `Kind=Utc`, which `DateTimeFunctionsTests.cs:197-200` rejects); `TranslateZonedUtcNow` is not overridden, so the base fallback (`DateFunctionsTranslatorBase.cs:1986-2015`) routes `DateTimeOffset.UtcNow` to it as well, as `TranslateZonedNow` → `Now` already does for Access
- E-23 (A-6) `Source/LinqToDB/PublicAPI/PublicAPI.Unshipped.txt` — the new overrides on public `LinqToDB.Internal.*` types
- E-24 (A-6) `Tests/Linq/Linq/TakeSkipTests.cs:TakeWithTies,TakeWithTies2`, `Tests/Linq/Linq/CachingTests.cs:TakeHint` — add `TestProvName.AllAccessLibRed` to the inclusion lists; `Tests/Linq/Linq/DateTimeFunctionsTests.cs:CurrentTimestampUtc` — `AllAccess` → `AllNativeAccess` in the exclusion; `Tests/Linq/Linq/EnumerableSourceTests.cs` — one new test, a local collection whose **first** row has a `NULL` in a nullable column (TO-13's U-10/U-12 cell, absent from the corpus); plus whatever TO-12..TO-16 triage needs (re-exclusion / gate per D-1/D-2)
- E-25 (A-6) `.claude/plans/feature-access-libred/findings.md` — the `InvariantGlobalization` failure (U-11)

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
- (A-6) `SqlProviderFlags.cs:541` `IsDistinctFromSupported` (serialized, `[DataMember(Order = 59)]`, in hash/equality `:833,917`); its only gate is `SqlExpressionConvertVisitor.cs:346-366`, which otherwise expands to `IS NULL`/`<>` (`:368-392`) — searched `IsDistinctFrom|DistinctFromSupported` over `Source/LinqToDB` — covered by E-20, TO-12 (LinqService cases carry the flag through the remote contract)
- (A-6) `AccessSqlBuilderBase.cs:118-131` overrides `BuildIsDistinctPredicate` with an IIF form that is dead today (the visitor expands first) and would become LibRed's output if only the flag were set; `SqlServer2022SqlBuilder.cs:26-31` is the re-implement-the-standard-text precedent — searched `BuildIsDistinctPredicate` — covered by E-21
- (A-6) `SqlProviderFlags.cs:66,762-767` `TakeHintsSupported` / `GetIsTakeHintsSupported`, checked only at build time (`ExpressionBuilder.SqlBuilder.cs:109-113,130-131`, hints and Skip mutually exclusive); rendered only on the TOP path, `BasicSqlBuilder.cs:2646-2682` (`BuildSkipFirst` → `BuildTakeHints`), never by `BuildOffsetLimit` (`:2684-2719`); `AccessLibRedSqlBuilder.cs:33-37` calls base `BuildSkipFirst` exactly when `SkipValue == null` — searched `TakeHints|WithTies|TakeHintsSupported` — covered by E-20, TO-14
- (A-6) hint queries opt out of `ReplaceTakeSkipWithRowNumber` (`BasicSqlOptimizer.cs:2382`) and of sub-query merging (`SelectQueryOptimizerVisitor.cs:1523-1526,2524-2525`) — LibRed reaches these opt-outs for the first time — searched same — covered by E-20 (measured by TO-14)
- (A-6) `BasicSqlBuilder.cs:2084-2134` `BuildSqlValuesTable`: `IsValuesSyntaxSupported` picks `BuildValues` over the FROM-less `BuildValuesAsSelectsUnion` (`BasicSqlBuilder.Merge.cs:283-343`, `FakeTable` null for Access); an empty source → `BuildEmptyValues` (`:2161-2181`) regardless of the flag, which emits `CAST(NULL AS …)` through the base `BuildTypedExpression` (`:2170,4268-4275`, no Access override) — `CAST` does not parse on LibRed (U-12), the path is unchanged by A-6 except for the alias list, and its tests keep their `AllAccess` exclusion (TO-13) — searched `IsValuesSyntaxSupported|SupportsColumnAliasesInSource|FakeTable` over `Internal/DataProvider`, `BuildTypedExpression` under `Internal/DataProvider/Access` — covered by E-21, TO-13
- (A-6) `SupportsColumnAliasesInScalarSource` defaults to `SupportsColumnAliasesInSource` (`BasicSqlBuilder.Merge.cs:21`), so a raw-SQL **scalar** source (`FromSqlScalar`) gains an `alias(col)` list on LibRed too (`BasicSqlBuilder.cs:2071-2079`) — measured accepted for a derived SELECT (U-8) — covered by E-21, TO-13
- (A-6) `SqlValuesTable` producers reaching LibRed: local-collection sources (`EnumerableSourceTests`), the KeyedQuery eager-load VALUES join (`ExpressionBuilder.EagerLoadKeyedQuery.cs:250-289`); MERGE sources throw on Access (`AccessSqlBuilderBase.cs:237-240`) — searched `AsQueryable|EnumerableContext` in the eager-load builder — covered by E-21 (measured by TO-13)
- (A-6) `StringMemberTranslatorBase.cs:603-673` `ConfigureConcatWs` (NULL items wrapped in `Coalesce(v,'')` when null-as-empty, `:643-645`); LibRed item form today `AccessLibRedMemberTranslator.cs:153-170` (Mid emulation); `string.Join` / `Sql.ConcatStrings` / `ConcatStringsNullable` / `string.Concat(IEnumerable)` all reach it (`:59-88`) — searched `CONCAT_WS|ConcatWithSeparator|ConcatStrings` — covered by E-22, TO-15
- (A-6) `DateFunctionsTranslatorBase.cs:71-72,1986-2015`: `DateTime.UtcNow` and `Sql.CurrentTimestampUtc` route to `TranslateUtcNow` (base null → client-side), and `TranslateZonedUtcNow` **falls back to `TranslateUtcNow`**, so `DateTimeOffset.UtcNow` also goes server-side on LibRed (Access's `TranslateZonedNow` → `Now`, `AccessMemberTranslator.cs:196-211`, is the precedent for a DateTime-valued offset member) — searched `TranslateUtcNow|CurrentTimestampUtc|UtcNow` — covered by E-22, TO-16
- (A-6) tests opting LibRed out of the newly advertised features: `TakeSkipTests.cs:700,715` and `CachingTests.cs:213` (inclusion lists without Access), `DateTimeFunctionsTests.cs:180` (`AllAccess` exclusion), `Issue5935Tests.cs:194-284` (already `AllNativeAccess`); `TakeSkipTests.cs:673,687` `TakeWithPercent*` already include `AllAccess` — searched `TakeHints\.|CurrentTimestampUtc|FROM-less` under `Tests` — covered by E-24

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
- TO-10 Symmetry guard on the unchanged path: `Access.Ace.OleDb` suite in chunks (fresh process each; union = full suite) = base failure set; its baselines identical to a base capture except the boolean sort-key delta — proof: characterization
- TO-11 Full suite on both LibRed configs after triage: 0 unexplained failures (SC-4); on CI leg `z_Access_LibRed` if U-5 is green, else locally — proof: characterization
- TO-12 (A-6) `IsDistinctFromTests` on both LibRed configs: rows unchanged, LibRed baselines contain `IS DISTINCT FROM` / `IS NOT DISTINCT FROM` where the pre-A-6 capture has the `IS NULL` / `<>` expansion; `Access.Ace.OleDb` baselines of the fixture unchanged — proof: characterization (observable: baseline diff)
- TO-13 (A-6) `EnumerableSourceTests` (both partials) and the KeyedQuery eager-load tests (`EagerLoadingStrategyKeyedQueryTests`, `Issue5935Tests`) on both LibRed configs: pass, and LibRed baselines contain `(VALUES …) [alias](cols)` where the pre-A-6 capture has the FROM-less `UNION ALL`; the new E-24 test (`NULL` parameter in row 1 of a nullable column — U-10/U-12's `Object`-typed column through linq2db's reader, `ConvertFromDataReaderExpression.cs:223,265,298`) passes on both LibRed configs (native Access, DB2 and Informix excluded as for its `EnumerableSourceTests` siblings; measured on native Access: 4/4 OleDb/ODBC cases reject the FROM-less `UNION ALL` source with "Query input must contain at least one table or query"); the scalar-source alias list through `SelectQueryTests.Issue2779Test1` / `Issue2779Test4` (`SelectQueryTests.cs:256-270,310-326`, LibRed already included) — `FromSqlTests` scalar cases exclude `AllAccess` and do not reach it. The empty-source path (`BuildEmptyValues` → `BuildTypedExpression` `CAST`, `BasicSqlBuilder.cs:2170,4268-4275`) stays unreachable on LibRed: `CAST` does not parse (U-12) and `EnumerableSourceTests.EmptyValues*` / `EmptySubQuery` (`:771,791,837`) keep their `AllAccess` exclusion — proof: characterization (observable: baseline diff) + the new test
- TO-14 (A-6) `TakeSkipTests.TakeWithTies` / `TakeWithTies2` and `CachingTests.TakeHint` with LibRed added to their inclusion: red before E-20 (`LinqToDBException: TakeHints are … not supported`, `ExpressionBuilder.SqlBuilder.cs:109-110`), green after, with `TOP … WITH TIES` in the LibRed baseline — proof: red→green
- TO-15 (A-6) `StringJoinTests` item-form cases (separator, `null` items, and the `''`-item cell at `StringJoinTests.cs:401`) on both LibRed configs: rows unchanged, LibRed baselines contain `CONCAT_WS(` where the pre-A-6 capture has `Mid(`; the aggregate STRING_AGG cases and the `withoutSeparator` cases of `StringConcatTests` (`:217,443,461`) unchanged — proof: characterization (observable: baseline diff)
- TO-16 (A-6) `DateTimeFunctionsTests.CurrentTimestampUtc` (narrowed by E-24) green on LibRed with `GETUTCDATE()` (its `Kind == Unspecified` assertion at `:197-200` holds, U-12); `UtcNow`, `DateTimeOffsetNowUtc` (`AllAccess` in the `Full.DateTime` branch, `:302-311`), `NullabilityCheck` stay green server-side — proof: red→green for `CurrentTimestampUtc` only if it is red with the narrowing alone, else characterization
- TO-17 (A-6) Symmetry guard: the TO-12..TO-16 fixtures on `Access.Ace.OleDb` — results and baselines identical to the pre-A-6 capture — proof: characterization

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

- Critic round 3 (refuted, 2026-09-24) — boolean sort keys, all accepted and fixed on this branch:
  - nullable key under DISTINCT → the unary-minus form is rejected by native Jet. **Decision:** under DISTINCT always
    flip (`(key) DESC`). Trade-off: a NULL key sorts last instead of first there; reachable only through an outer
    join or a computed key, since no Access flavour stores a NULL boolean (`NullableBoolTests`,
    `ProvidersThatDoNotSupportNullableBool` = `AllAccess`). Accepted over a hard failure.
  - a `bool` mapped to a non-Yes/No column (value converter, `DataType.Char` / `Int16`) already sorts in CLR order →
    `IsBooleanSortKey` skips a key with a `ValueConverter` or a `DataType` other than `Boolean` / `Undefined`.
  - missing obligations → `DistinctTests.DistinctOrderByNullableBoolean` / `GroupByNullableBooleanOrderByKey` /
    `ConcatOrderByBoolean`, `ValueConversionTests.Issue3830OrderByTest`,
    `WindowFunctionsTests.RowNumberWithNullableBooleanOrderBy`; `RowNumberWithBooleanColumn` un-gated for LibRed
    (its NULL-partition assertion skipped for Access — no NULL booleans).
  - TO-10 cannot complete as one run (known ACE OLE DB `0xC0000005`, see Resuming item 2) → run it in chunks
    (per namespace / fixture, fresh process each) whose union covers the suite.
  - **Shared-engine fix carried in-branch — #5970, ported to its own PR before merge (release-blocking).**
    `JoinTests.LeftJoinSubqueryDoNotOptimize` failed on LibRed LinqService (CI run 35991422429). Root cause, measured
    with stage dumps: `SqlExpressionConvertVisitor.Optimize` (`:302`) passed `OptimizationContext.TransformationInfo`
    to the nested optimizer, while the convert pass registers its own Transform-mode replacements (a rebuilt
    sub-query `t139 → t143`) in `TransformationInfoConvert`; the nullability lookup could not map the rebuilt LEFT JOIN
    source back and folded `x IS NULL` to false. Affects every provider on remote and on direct parameter-dependent
    queries; Access hits it on plain `??` (COALESCE → IS NULL condition). Fix: pass `TransformationInfoConvert`.
    Rejected: also attaching it in `Convert` — measured no effect. Test: `JoinTests.Issue5970Test` (explicit IS NULL,
    `[Values] parameterDependent`, all providers but native Access) — red 7/14 → green 14/14 on SQLite + LibRed.
    **Ported (2026-09-24): [#5971](https://github.com/linq2db/linq2db/pull/5971)**, draft, branch
    `issue/5970-fix-transform-isnull-leftjoin` off `master`, milestone 6.5.1; `Issue5970Test` red 3/4 → green on
    `master` (SQLite, net10.0). #5969 keeps its identical copy (user: "leave") — no rebase, since its base chain is the
    .NET 11 stack; the duplicate becomes a no-op once `master` flows up.
  - a second double-convert path exists besides remote: a non-`optimizeAndConvertAll` query re-runs
    `OptimizeAndConvert` on the ORDER BY at build time (`BasicSqlBuilder.cs:2566` → `OptimizationContext.cs:167-176`);
    the int-typed key covers it too.

## P11 Amendments (M/L)

- A-1 (2026-09-23, user: "b, but here") — boolean sort keys. Jet/ACE stores True as -1, so a boolean `ORDER BY` /
  window `ORDER BY` / `WITHIN GROUP` key sorts True first, reversing CLR order; surfaced by the window-function
  tests (`RankOverPredicate`-style `Issue2842Test1`, `RowNumberWithBoolean*`, `Issue5123Test`,
  `PercentileDiscWithBooleanOrderBy`). The shared precedent (`SqlExpressionConvertVisitor.VisitSqlOrderByItem` /
  `VisitSqlWindowOrderItem` → `WrapBooleanExpression`) wraps predicates only when `SupportsBooleanType` is false
  and re-emits `true`/`false`, which Access renders as -1/0 again, and never wraps fields. Fix: E-10 in the
  **shared** `AccessSqlExpressionConvertVisitor` (all five flavours) — non-constant bool keys become
  `IIF(p, 1, 0)` / nullable `IIF(p, 1, IIF(NOT p, 0, NULL))`; positioned items untouched. **SC-3 changes:** native
  Access baselines move for boolean sort keys (expected, the only native delta); TO-10 compares everything else
  byte-identical and lists that delta. Approval for E-10's widened scope: user, this turn.
- A-2 (2026-09-23) — surface found during triage, all LibRed-only:
  - new E-15 `Source/LinqToDB/Sql/Sql.cs:Reverse` — `[Function(PN.AccessLibRed, "StrReverse")]`; `LastIndexOf`
    expands through `Sql.Reverse` (`Linq/Expressions.cs:515-524`), so one attribute covers both.
  - E-13 widened: `AccessSqlBuilderBase` also gets `IsCommentSupported` (native `false`, LibRed `true`); LibRed's
    lexer skips `--` / `/* */` (`AccessSql.g4:749-750`). `FirstFormat` stays non-nullable (shipped signature):
    paging suppresses `TOP` by overriding `BuildSkipFirst` instead.
  - E-9 widened: LibRed date translator (`DatePart`/`DateAdd` `'ms'`), string translator (`LTrim`/`RTrim` with a
    character set; `STRING_AGG` for the aggregate `string.Join`/`Concat`, item form keeps the Access `Mid`
    emulation), window translator family flags + `VarianceFunctionName => "Var"` (measured: `VARIANCE` →
    `NotSupportedException`, `Var` → 18/18).
  - E-7/E-10: `AccessLibRedSqlOptimizer` + `AccessLibRedSqlExpressionConvertVisitor` exist for
    `EscapeLikeCharacters` via `REPLACE`.
  - E-3 kinds used so far: D-2 re-exclusion on not-advertised features (MERGE, MERGE-lowered Upsert, UPDATE/DELETE
    Take/Skip, RETURNING, COLLATE, CheckExistence, DateTimeOffset/Blob columns, nullable bool, sub-ms DateTime,
    KeepIdentity row-by-row, KEEP / hypothetical-set / MEDIAN); `AccessLibRedMdb`-only on
    seven tests needing an ACE-only type; LibRed added to the MARS `_NotSupported` complements (the narrowing was
    wrong there — they mirror `_Supported` lists that already include `AllAccess`); LibRed added to
    `PredicateTests.AssertIntersect`'s native-INTERSECT `IsAnyOf` list.
- A-3 (2026-09-23, user: "a" — implement LibRed interval arithmetic here rather than exclude) — plus the shared-file
  edits triage forced after A-2:
  - D-5 (new) **interval arithmetic for LibRed.** chosen: reuse the base day-anchored `ElapsedTicks` /
    `LowerTemporalArithmetic` through one `AccessSqlExpressionConvertVisitor.IsTickArithmeticSupported` switch
    (native `false`, so native keeps returning null); LibRed sets `FinestDateUnit`/`IntervalResolution` to
    Millisecond, `CanLowerIntervalDifference`/`CanMeasureDifferenceInTicks`/`CanLowerIntervalShift` true, counts with
    `DateDiff_Big` (Int64) for every unit incl. `'ms'` and shifts with `DateAdd('ms')`; members keep Access's
    corrected per-unit counting (`ElapsedTicksResolveMembers` stays false). rejected: a LibRed-specific tick formula
    — duplicates the base's overflow reasoning; rejected: excluding the ~15 tests — user chose to implement.
    failure mode: a declared duration is still CURRENCY via the shared `Access` column configuration, so combining
    one is correctly refused by `CarriesWholeTicks` — asserted through new `DeclaredMoneyDurationProviders`.
    Measured: interval + math + date fixtures 531/0 on `Access.LibRed.Mdb`.
  - E-17 `Source/LinqToDB/Sql/Sql.DateTime.cs`, `Sql.DateOnly.cs`, `Sql.DateTimeOffset.cs:DateDiff` —
    `DateDiffBuilderAccessLibRed` registered under `PN.AccessLibRed` (`'ms'`); Access body shared via `BuildAccess`.
  - E-8 used: `AccessSqlOptimizer.CorrectExistsAndIn` → `protected virtual`; LibRed skips the `COUNT(*) > 0`
    rewrite.
  - E-9 widened: `AccessMemberTranslator.MathMemberTranslator.Power` helper (native `x ^ y`, unchanged SQL); LibRed
    emits `Power(x, y)` because `^` becomes `BXOR` in the LibRed visitor — measured regression when missed: `Pow`,
    `Round9`, `Round12` computed XOR.
  - E-13 fix: `AccessSqlBuilderBase.BuildUpdateClause` rewrites `FROM`→`UPDATE` at the position `FROM` was written,
    not at 0 — a tagged UPDATE on LibRed (comments on) produced `UPDATEy …`; native is at 0 either way.
  - E-3 corrections of the E-1 narrowing, measured: `WhereTests.cs:1483` skip restored for LibRed (NULL bool stored
    as False, same as Jet); MARS `_NotSupported` complements; two alignment fixes. Access-only `IncludeDataSources`
    narrowed to `AllNativeAccess` where the test asserts Jet's second resolution (two in
    `IntervalTranslationTests.Difference.cs`) — LibRed now resolves milliseconds by design.
  - E-12: findings R13 (`IIF` typed by taken branch) and R14 (`NTH_VALUE` ignores default frame).
- A-4 (2026-09-24) — response to critic round 2 (`refuted`, see P12):
  - A-1 relocated. The boolean sort-key lowering moves out of `AccessSqlExpressionConvertVisitor` (render time,
    after `SelectQueryOptimizerVisitor.cs:2427` has merged a DISTINCT sub-query on a plain-column key) into new
    internal E-19 `Source/LinqToDB/Internal/DataProvider/Access/AccessBooleanSortKeyLoweringVisitor.cs`, run from
    `AccessSqlOptimizer.Finalize` before `base.Finalize` — the `SqlNullsOrderingLoweringVisitor` position. Field keys
    become predicates through `SqlPredicate.IsTrue`. New tests `DistinctTests.DistinctOrderByBoolean` /
    `GroupByBooleanOrderByKey` pin the shape the corpus lacked; run on `Access.Ace.OleDb` and LibRed.
  - E-13 now also toggles `BuildSqlConditionExpression` under `IsCaseExpressionSupported`: LibRed documents that `CASE`
    unifies branch types, which is the R13 mechanism; the three `Sum*SubqueryEmpty` gates are re-measured and
    removed if they pass.
  - `DatePartName` is a `protected virtual` on the Access visitor; the LibRed `ShiftDate` copy is gone.
  - Noted, not changed: `Sql.DateDiff(Millisecond)` on LibRed is 32-bit `DATEDIFF('ms')`, SQL Server parity.
- A-5 (2026-09-28, ChrisJollyAU on #5969) — windowed percentiles are advertised at `v11.0.0-alpha.3` (`README.md:203`,
  grammar `functionCall` takes `withinGroup` before `OVER`, `WindowFunctions.cs:103-105`); the D-2 re-exclusion was
  wrong. `IsOrderedSetWindowedSupported => true` on the LibRed window translator; `AllAccessLibRed` dropped from
  `PercentileContWindowed` / `PercentileDiscWindowed`.
- A-6 (2026-10-16, user: "enable alpha.4 syntax") — `LibRed.Ado` 11.0.0-alpha.4 (#5956 `0e931586c`) adds syntax this
  plan's P3 listed as out of scope only because alpha.3's grammar lacked it. **The approval of record is void for
  E-20..E-25 and must be re-earned.** Re-earned 2026-10-16 after critic round 4 (user: "yes"). P3's "Not in scope" line now reads minus `IS DISTINCT FROM`; everything else
  in it stands.
  - D-6 (new) **which alpha.4 additions LibRed emits.** chosen, all LibRed-only per D-3: `IS [NOT] DISTINCT FROM`
    (flag + builder text, E-20/E-21); `TOP n [PERCENT] WITH TIES` through the existing TOP path — the hint builder
    forbids Skip with hints (`ExpressionBuilder.SqlBuilder.cs:112-113,130-131`), so `FETCH … WITH TIES` is never
    reached and needs no rendering (E-20); `VALUES` table source with a column alias list, replacing the FROM-less
    `UNION ALL` (E-21); `CONCAT_WS` for the `string.Join` item form (E-22); `SYSUTCDATETIME()` for
    `DateTime.UtcNow` / `Sql.CurrentTimestampUtc` — `GETUTCDATE()` (E-22).
  - rejected: `IS [NOT] TRUE/FALSE` — no seam short of core (U-9). rejected: `Nz` — always a Variant, measured
    typed `String` (U-8), and COALESCE-shaped null handling already exists. rejected: `TRANSLATE` — no linq2db member
    maps to it outside the SQL Server-only `SqlFn.Translate` (`SqlFn.cs:3212-3213`), so there is nothing to
    route. rejected: derived-SELECT column lists — linq2db emits `(SELECT …) AS t(a, b)` for no source but a raw
    scalar one (`BasicSqlBuilder.cs:2071-2079`); the VALUES list is the only reachable form. rejected:
    `SYSUTCDATETIME()` (the SQL Server 2008+ choice, `SqlServer2008MemberTranslator.cs:40-53`) — LibRed returns it
    `Kind=Utc` (U-12), which changes the materialized `DateTime.Kind` against every other provider and fails
    `DateTimeFunctionsTests.cs:197-200`; `GETUTCDATE()` is `Kind=Unspecified` at millisecond precision, the base
    SQL Server translator's choice (`SqlServerMemberTranslator.cs:173-184`). (This line was the reverse before critic
    round 4; the probe overturned it.) rejected: moving the `withoutSeparator` branch to `CONCAT_WS('', …)` — it
    works (U-12) but changes `string.Concat` SQL for no gain; scoped out of E-22.
  - why: every enabled form is measured in U-8/U-12 in the shape linq2db emits, and each lands in an existing
    LibRed seam with no shared-file edit.
  - failure mode: VALUES changes the SQL of every query that sources a local collection on LibRed — the widest
    baseline churn of the five; TO-13 bounds it. `CONCAT_WS` changes only where the item form had a separator.
  - re-derives: P3 (scope line); SC-2 (its enabled-feature set gains the five forms, each with a `TO-n`); P4 U-8,
    U-9, U-10, U-11, U-12 (new); P7 the eleven A-6 rows (new); P8 TO-12..TO-17 (new); TO-9 (its VALUES branch is now
    decided — TO-13 carries it); TO-11 (the full-suite gate now includes the A-6 shapes); TO-10 / SC-3 unchanged —
    every A-6 edit is LibRed-only, which TO-17 checks on `Access.Ace.OleDb`.

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

refuted — round 2 (delta A-1..A-3), `plan-critic` on **fable**. Objections and responses (A-4):

- A-1 at the wrong altitude: rewriting sort keys at render time defeats the DISTINCT sub-query guard
  (`SelectQueryOptimizerVisitor.cs:2420-2431`), which only sees a plain column; the codebase lowers NULLS keys
  pre-optimization for this reason (`BasicSqlOptimizer.cs:59-64`) → relocated to a pre-`base.Finalize` visitor.
  The Jet runtime consequence was the critic's recollection, unprobed; the new `DistinctTests` cases measure it.
- TO-10 blind to the shape (no corpus test) → two new tests.
- E-13 promised CASE for conditions, code toggled only `SqlCaseExpression` → conditions toggled; R13 re-measured.
- D-5 verbatim `DatePartName`/`ShiftDate` twin → `DatePartName` virtual.
- P3 exception unrecorded → P3 line added.
- Note: `Sql.DateDiff(Millisecond)` 32-bit → recorded, unchanged.

Critic searched: the full `Source` delta, every `SqlBinaryExpression("^")` producer (only CLR XOR and the new `Power`
helper — native byte-identical verified by reading), `SupportsBooleanType`, `WithinGroup` visiting,
`SqlNullsOrderingLoweringVisitor` call site, `TransformStatement` call site, `BuildSqlComment`/`BuildTag`,
skip/take builder path, LibRed mapping-schema precedence, base interval lowering, PublicAPI entry-for-member
count. Round 3 (the revision) pending.

weak — round 4 (delta A-6), `plan-critic` on **fable**, 2026-10-16. Objections and responses (folded into A-6 / U-12 /
E-22 / E-24 / TO-13 / TO-15 / TO-16 the same day, each answered by a new probe cell, `accdb3.txt:150-182`):

- TO-13 cited fixtures that cannot observe its claims: `FromSqlTests` scalar cases exclude `AllAccess` → cites
  `SelectQueryTests.Issue2779Test1/Test4` instead; no corpus case has a `NULL` first row and the probe had measured a
  literal, not a parameter → U-12 measures the parameter, E-24 adds a test; the empty-source path emits
  `CAST(NULL AS …)`, not the probed bare `NULL` → measured `CAST` does not parse, path dispositioned as unreachable
  (its tests keep the `AllAccess` exclusion), P7 row corrected.
- E-22's range spanned the `withoutSeparator` branch too, which the cited precedent also moves → scoped to the
  separator branch only; `CONCAT_WS('', …)` probed anyway; the `''`-item cell probed and `StringJoinTests.cs:401`
  named in TO-15.
- lead: `SYSUTCDATETIME()`'s `Kind` unrecorded → measured `Kind=Utc`; **design changed to `GETUTCDATE()`**
  (`Kind=Unspecified`). The critic's lead was right.
- lead (minor): `CachingTests.TakeHint` shape (WITH TIES inside a cross-join sub-source) unprobed → kept; TO-14's
  "green after" is a prediction, not a measurement.

Critic searched: the `IsDistinctFromSupported` gate and every `SqlPredicate.IsDistinct` producer, every
`BuildIsDistinctPredicate`, `TakeHints*` across `Source`, the VALUES / column-alias builder consumers incl. MERGE,
`TranslateUtcNow` / `CurrentTimestampUtc`, `WrapParameters`, `InvariantGlobalization` across the worktree, the reader
keying in `ConvertFromDataReaderExpression`. Not checkable by it: the alpha.4 release notes. No round 5 — every
objection accepted as stated and answered by measurement, none disputed.
