# Work plan: feature-access-libred-dialect — LibRed extended SQL dialect

**Tier:** L  ·  **Status:** approved  ·  **Approved-at:** 2026-09-23 (E-1..E-14, after critic round 1); 2026-10-16 (A-6, E-20..E-25, after critic round 4); 2026-11-15 (A-8, A-9 / E-30, after critic rounds 6–7, verdict weak)  ·  **Branch:** feature/access-libred-dialect
**Schema:** `.claude/docs/work-plan.md`  ·  **Gates:** `.claude/docs/definition-of-done.md`

Base: `origin/master` (since 2026-11-15, A-8; originally `origin/feature/access-libred` @ `3b6b73ba7`, #5956, squash-merged as `d5f5c9378`). PR #5969, draft, base `master`, milestone `6.6.0`. Head `cd009d488` (18 linear commits).

## Resuming (2026-11-15)

Branch rebased onto `master` after #5956 merged (A-8). No worktree. Review round 1 (`/review-pr 5969`) runs against
`cd009d488`; CI `test-all` 25696 / GitHub `tests [all]` 43718171491 were in flight at amendment time. The section
below is the 2026-09-24 state, kept for the record — its base, milestone and open items are superseded.

## Resuming — history (2026-09-24)

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
- SC-3 Native Access flavours unchanged except boolean sort keys (A-1: direction flip / unary minus, OleDb and ODBC) and `MOD` operand grouping (A-9: a `+`/`-` operand of `MOD` gains parentheses, a `MOD` operand of `+`/`-` loses redundant ones; A-10: a `*`/`/` operand of `MOD` gains them) and `^` operand grouping (A-11: every operator operand of `^` gains parentheses, a `^` operand of `*`/`/` loses redundant ones): `Access.Ace.OleDb` suite, run in chunks (P10), has the base failure set (`TestExpressionVisitorHops(10)` only) and baselines identical to a base capture outside that delta → TO-10
- SC-4 Full suite on both LibRed configs ends with 0 unexplained failures — each red fixed, re-excluded (not advertised) or `[ActiveIssue]`-gated on `AllAccessLibRed` (advertised but defective, recorded in `plans/feature-access-libred/findings.md`) → TO-11

## P3 Constraints & anti-goals (M/L)

- `TestProvName.AllAccess` keeps its definition (native + LibRed) — user direction. No new constants unless one is
  needed for a recurring LibRed-feature list.
- Native flavours' SQL and flags do not change (SC-3). Every provider-side change is a LibRed-only arm.
  Exceptions, each recorded: the boolean sort keys (A-1) and the `MOD` precedence fix (A-9, E-30, #6243 — a
  pre-existing wrong-result defect on every Access flavour, kept on this branch by user decision 2026-11-15).
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
- U-4 COUNT(DISTINCT x) / aggregate DISTINCT (`AccessMemberTranslator.cs:452-453` false) — not in the grammar survey; decided by probe in the aggregate bucket; stays false if the probe rejects — resolved-by probe. (A-10) Never decided until review round 1: LibRed baselines at `cd009d488` run `STRING_AGG(DISTINCT …)` and windowed `COUNT(DISTINCT …)` green, while the shared Access aggregate translator kept grouped DISTINCT off for LibRed; enabled by E-31, measured by TO-21
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
  twin is `AddOrderByForSkip`, `SqlServer2012SqlOptimizer.cs:39-56`) in E-7 (the optimizer half is superseded — rejected by A-10, see *amended* below). Flags `IsSkipSupported`,
  `AcceptsTakeAsParameter` true for LibRed; `IsSubQuerySkipSupported` only once a derived-table OFFSET is probed.
- **rejected:** `TOP` + client-side skip (today's behaviour) — defeats the purpose.
- **why this:** grammar `offsetFetchClause` accepts skip-only and expression counts; SqlCe is the in-repo precedent.
- **failure mode of the choice:** the ORDER BY injection is unnecessary if LibRed's `offsetFetchClause` does not
  hang off ORDER BY (not recorded in U-2) — a harmless extra ORDER BY, same as SqlCe; OFFSET inside a derived
  table is unprobed, hence `IsSubQuerySkipSupported` is gated on a probe.
- **amended (A-10):** the optimizer half was never built, and is now rejected. LibRed accepts OFFSET without ORDER BY:
  `TakeSkipTests.SkipTake5` / `SkipCount` / `SkipTakeCount` / `ElementAtDefault2/4` / `TakeSkipJoin` emit
  `OFFSET … FETCH` with no ORDER BY at `cd009d488` and pass on CI `Lin zz_Access_LibRed`. SqlCe and SQL Server inject
  because their engines require it; injecting here would move every LibRed paging baseline to buy an order no other
  unordered-paging provider (SQLite, PostgreSQL) gives. Trade-off recorded in P10.

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
- E-26 (A-7) `Source/LinqToDB/Internal/DataProvider/Access/AccessSqlExpressionConvertVisitor.cs:VisitSqlOrderByItem` — `protected virtual bool CanNegateSortKeyUnderDistinct => false`, read where `flip` is decided (`:571`), so the DISTINCT flip-only rule is the native default; `AccessLibRedSqlExpressionConvertVisitor.cs` overrides it `true` (the `IsTickArithmeticSupported` shape, `:31`)
- E-27 (A-7) `Tests/Linq/Linq/DistinctTests.cs:DistinctOrderByOuterJoinedBooleanKey` — drop #5956's E-35 gate; the expected source reads LibRed's `NULL` for unmatched rows (`t?.BoolValue`) where Jet / ACE read `False`, and the comment says which engine does what. The projection is already `bool?` (`LinqDataTypes2.BoolValue`, `Tests/Model/LinqDataTypes.cs:96`), so the query side is untouched and ACE's SQL with it
- E-29 (A-7) `Tests/Linq/Linq/DistinctTests.cs:DistinctOrderByNullableBooleanSubQueryColumn` — the pinned flip order (`NULL` after `True`) is native-only; LibRed expects the .NET order, and the comment says so
- E-28 (A-7) `Source/LinqToDB/PublicAPI/PublicAPI.Unshipped.txt` — the new virtual and its override
- E-30 (A-9, re-worded by A-10) `Source/LinqToDB/Internal/DataProvider/Access/AccessSqlExpressionConvertVisitor.cs:ConvertSqlBinaryExpression` — `%` → `MOD` registered at `Precedence.Multiplicative` (A-9 had `Precedence.Subtraction + 1`; master `Precedence.Additive - 1`), all Access flavours; `Tests/Linq/Linq/MathFunctionTests.cs:ModuloOperandKeepsItsGrouping` — new bare-`[DataSources]` test, five arms
- E-31 (A-10) `Source/LinqToDB/Internal/DataProvider/Access/Translation/AccessLibRedMemberTranslator.cs:CreateAggregateFunctionsMemberTranslator` — new nested `AccessLibRedAggregateFunctionsMemberTranslator : AccessAggregateFunctionsMemberTranslator` with `IsCountDistinctSupported` / `IsAggregationDistinctSupported` true (D-3 shape)
- E-32 (A-10) `Source/LinqToDB/PublicAPI/PublicAPI.Unshipped.txt` — E-31's type, constructor and three overrides
- E-33 (A-10) `Tests/Linq/Linq/IntervalTranslationTests.Difference.cs:MillisecondComponentHoldsPastTheRangeOfItsCounter` — new test (TO-20); `Tests/Linq/UserTests/Issue4336Tests.cs:19` — gate `Details` re-stamped alpha.4 and beta.1; `Tests/Linq/Linq/WindowFunctionsTests.RowNumber.cs:175` — layout; `AccessLibRedSqlExpressionConvertVisitor.cs:26-27` — column alignment
- E-34 (A-11) `Source/LinqToDB/Internal/DataProvider/Access/Translation/AccessMemberTranslator.cs:MathMemberTranslator.Power` — native `^` registered at `Precedence.Unary + 1` (was `factory.Binary`'s `Precedence.Additive`), all native flavours; LibRed's override (`Power(x, y)` function) unchanged (A-12: deleted by E-37, LibRed now uses E-34)
- E-35 (A-11) `Source/LinqToDB/Internal/DataProvider/Translation/SqlExpressionFactoryExtensions.cs:Binary` — new overload taking `int precedence`; the existing overload delegates with `Precedence.Additive` (behaviour-identical); `PublicAPI.Unshipped.txt` line
- E-36 (A-12) `Source/LinqToDB/Internal/DataProvider/Access/AccessSqlExpressionConvertVisitor.cs:ConvertSqlBinaryExpression` — new arm: a C# XOR (`^` at `Precedence.Bitwise`) → `BXOR` at `Precedence.Bitwise - 2`, all Access flavours; a power `^` (E-34, `Unary + 1`) is not matched
- E-37 (A-12) `Source/LinqToDB/Internal/DataProvider/Access/AccessLibRedSqlExpressionConvertVisitor.cs` — E-16's `ConvertSqlBinaryExpression` override deleted (superseded by E-36); `Translation/AccessLibRedMemberTranslator.cs` — `CreateMathMemberTranslator` / `AccessLibRedMathMemberTranslator` (`Power(x, y)`) deleted, so LibRed renders a power as E-34's `x ^ y`; `PublicAPI.Unshipped.txt` — their four lines removed, `AccessLibRedWindowFunctionsMemberTranslator.IsOrderedSetWindowedSupported` added (A-5's missing line)
- E-38 (A-12) `Tests/Linq/Linq/WhereTests.cs` — `BinaryXor` / `BinaryAnd` / `BinaryOr` lose their `AllNativeAccess` exclusion; new `BinaryXorUnderOr` (`ID | (ID ^ 1)`) and `BinaryXorOverOr` (`(ID ^ 1) | 2`), bare `[DataSources]`; `BinaryXorUnderOr` gated `[ActiveIssue(6243)]` on `SqlCe` (T-SQL `|` / `^` one level, left to right)
- E-39 (A-12) `Tests/Linq/Linq/IntervalTranslationTests.Queries.cs:ContainsOverADifference` — LibRed gate pinned to `ErrorMessage = "should be{0}True{1}but was"`, `Details` re-measured (the IN-list half answers; the sequence `Contains` misses); `Tests/Base/Attributes/ActiveIssueAttribute.cs:ErrorType` — doc: a type-only Shouldly gate over more than one assertion also pins the expected value; `AccessSqlExpressionConvertVisitor.cs:ElapsedTicks` / `LowerTemporalArithmetic` — summaries scoped to Jet and ACE
- E-40 (A-12, critic round 10) `Source/LinqToDB/Internal/DataProvider/Access/Translation/AccessMemberTranslator.cs:MathMemberTranslator.Power` — a power as the exponent is wrapped in `({0})` at `Unary + 1`, so `Pow(a, Pow(b, c))` renders `a ^ (b ^ c)` on every Access flavour (A-11's known limit, now also LibRed's after E-37); `Tests/Linq/Linq/MathFunctionTests.cs:PowerOfPowerKeepsItsGrouping` — new, bare `[DataSources]`; `Tests/Linq/Linq/WhereTests.cs:BinaryAndLeftOfXor` / `BinaryAndRightOfXor` — new, `[IncludeDataSources(true, AllAccess)]` with a reason comment; `BinaryXorUnderOr`'s gate widened to `AllSqlServer`

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
- `SqlCeSqlBuilder.cs:31-46` + `SqlCeSqlOptimizer.cs:107-141` — OFFSET/FETCH precedent, builder and ORDER BY injection — covered by E-6 (builder); the injection half rejected by A-10 (D-4 amended)
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
- (A-7) `AccessSqlExpressionConvertVisitor.cs:571` (`VisitSqlOrderByItem`, the `flip` decision) is the only reader of `CanNegateSortKeyUnderDistinct`; declared `:580` (`false`), overridden only at `AccessLibRedSqlExpressionConvertVisitor.cs:33` (`true`); `VisitSqlWindowOrderItem` does not read it — searched `git grep -n CanNegateSortKeyUnderDistinct origin/pr/5969 -- Source` (2026-11-15, 5 hits incl. 2 `PublicAPI.Unshipped.txt`) — covered by E-26, E-28
- (A-10) E-31's gate is `AggregateFunctionsMemberTranslatorBase.cs:59` (`Count`, `AllowDistinct(IsCountDistinctSupported)`) and `:256` (`Min`/`Max`/`Sum`/`Average`, `AllowDistinct(IsAggregationDistinctSupported)`), grouped or not — it also reaches a `Distinct().<aggregate>` in a correlated scalar sub-query (`DistinctTests.DistinctWithAssociationInSubquery`, which on LibRed at `cd009d488` used the `SELECT COUNT(*) FROM (SELECT DISTINCT …)` emulation); window aggregates go through their own translator and already had DISTINCT (`IsAggregateDistinctSupported`). Only Access, SqlCe and the base define the two flags. Fixtures carrying `Distinct().<aggregate>` / `AggregateModifier.Distinct` that reach LibRed (critic round 8: 71 sites, 15 files) — run on `Access.LibRed.Mdb` after E-31: `GroupByTests`, `StringJoinTests`, `CountTests` 715/0/3 (with `MathFunctionTests`, `IntervalTranslationTests`), and `DistinctTests`, `InsertTests`, `ParameterTests`, `CteTests`, `Issue5719Tests`, `MicrosoftODataTests`, `DurationMappingTests` 498/0/6 — searched `IsCountDistinctSupported|IsAggregationDistinctSupported` over `Source/LinqToDB` and `Distinct\(\)\.(Sum|Average|Min|Max|Count|LongCount)\(|AggregateModifier\.Distinct` over `Tests/Linq` — covered by E-31, TO-21
- (A-9) `AccessSqlExpressionConvertVisitor.cs:537` is the only `MOD` producer for Access, and runs for all five flavours (the shared visitor; `AccessLibRedSqlExpressionConvertVisitor.cs:50-57` overrides `ConvertSqlBinaryExpression` for `^` → `BXOR` only and delegates `%` to the base arm — corrected after critic round 7; A-12 deleted that override, the `BXOR` arm is now E-36 in the shared visitor). LibRed's tick-arithmetic lowering (A-3) also emits `(a ± b) % c`: E-30 fixes `ShiftOverADateColumnMatchesClr` on LibRed *(PR body)*, a second observable, LibRed-only (native has no tick lowering). `Wrap` (`BasicSqlBuilder.cs:4709-4718`) parenthesizes an equal-precedence child only under `Subtraction` / `Multiplicative` / `LogicalNegation`, so a right-nested `a % (b % c)` rendered `a MOD b MOD c` at 71 as it did at 59 — measured wrong on native and LibRed in review round 1 and fixed by A-10's move to `Precedence.Multiplicative`, where `Wrap` parenthesizes every equal-precedence `MOD` / `*` / `/` child on both sides; `Precedence.cs` at the PR ref: Additive 60, Subtraction 70, Multiplicative 80, so `MOD` now sits above `+`/`-` and below `*`/`/`. Both directions move native SQL: `(a + b) MOD c` gains parentheses (the fix), `a + (b MOD c)` loses redundant ones (measured in the `Round16` baselines on all four native configs, `([p].[ID] MOD 2) + 2` → `[p].[ID] MOD 2 + 2`) — searched `git grep -n '"MOD"\|Precedence.Additive\|Precedence.Subtraction' origin/pr/5969 -- Source/LinqToDB/Internal/DataProvider/Access` (1 hit) and the native `MathFunctionTests` rows of `baselines/pr_5969` — covered by E-30, TO-19
- (A-11) E-34 operator table for native Access, `^` at `Precedence.Unary + 1` (91), `Wrap` = `BasicSqlBuilder.cs:4709-4718`; producers found by call shape (`factory.Binary(`, `new SqlBinaryExpression(`, `ConvertSqlBinaryExpression` arms, `SqlUnaryExpression`), critic round 9: unary `-` (90, every negation producer: `ExpressionBuildVisitor.cs:2788`, `SqlExpressionFactoryExtensions.cs:176`, `SqlExpressionConvertVisitor.cs:2695-2722`), `*` / `/` / `MOD` (80), binary `-` (70), `+` (60), comparison (50), `BAND`/`BOR`/`BXOR` (40/39/38, `BXOR` from A-12), concat (5) and precedence-0 expressions are all wrapped as an operand of `^` and leave a `^` operand bare, which Access's order (`^` > unary `-` > `*` `/` > `\` > `MOD` > `+` `-`) makes correct; functions, columns, parameters and elided casts (100) stay bare; a signed literal (`SqlValue` -2) renders `-2 ^ x` and Access reads it as `(-2) ^ x` (probed, A-11); `^` under `^` is bare both sides — right-nested wrong, the known limit. `Power` callers: `TranslatePow` (`Math.Pow`, both `Sql.Power`) and `TranslateRoundAwayFromZero` with a precision (`AccessMemberTranslator.cs:297,300,316`); the only other native `"^"` is CLR XOR at `Precedence.Bitwise` (`ExpressionBuildVisitor.cs:3903`) — untouched by A-11, rendered as a power on native until A-12's E-36 turned it into `BXOR` (38), which the power's `Unary + 1` guard keeps apart. Since A-12 (E-37) this table is LibRed's too. E-35 callers of `Binary`: `Power` and `MemberTranslatorTests.cs:35` (old overload, behaviour-identical). Native baselines carrying `^`: 7 on `Access.Ace.OleDb`; `Round9` / `Round12(AwayFromZero,1|2)` move, `Pow*` do not — covered by E-34, E-35 (TO-22).

## P8 Test obligations (M/L)

- TO-1 After E-1/E-2 alone (no provider change), full suite on `Access.LibRed.Mdb` + `Access.LibRed.Accdb`: the failure list is captured and every failure is bucketed by cause; at the end of triage no failure remains unbucketed — proof: characterization (the pre-change list is the inventory; it proves coverage, not behaviour)
- TO-2 Paging: the base already passes `TakeSkipTests` via client-side skip (`QueryRunner.cs:442-457`), so the observable is SQL shape — LibRed baselines for `TakeSkipTests` contain `OFFSET … ROWS` where the base capture has none (named baseline diff). The `Error_Skip_in_Subquery` sites (`DistinctTests.cs:614/652`, `SubQueryTests.cs:203`, `EagerLoadingTests.cs:3310`) are red only **after** E-1 narrows their `Throws*` attribute, then green with D-4 — proof: red→green (post-E-1) + baseline diff
- TO-3 Paging without ORDER BY (rewritten by A-10): an existing `Skip`-without-`OrderBy` test in `TakeSkipTests` on LibRed emits `OFFSET … ROWS FETCH NEXT … ROWS ONLY` with no ORDER BY (`SkipTake5(Access.LibRed.Mdb,False)` at `cd009d488`) and passes — no injection, per D-4 as amended — providers: `Access.LibRed.Mdb`, `Access.LibRed.Accdb` — proof: characterization + baseline diff
- TO-4 Window functions: `WindowFunctionsTests`, `AnalyticTests` (via `SupportsAnalyticFunctionsContextAttribute`), `Error_RowNumber` sites (incl. the `*ByMethodTests` `[ThrowsCannotBeConverted]` rows) — red only after E-1/E-2 narrow them, green with E-5/E-9 — proof: red→green (post-E-1)
- TO-5 APPLY: the 19 `Error_OUTER_Joins` sites + `WithApplyJoin` tests — red only after E-1 narrows them, execute with `IsApplyJoinSupported` — proof: red→green (post-E-1)
- TO-6 CROSS / FULL JOIN: `AllJoinsSourceAttribute` tests + `JoinTests` full-join cases — proof: red→green
- TO-7 INTERSECT / EXCEPT: the base emulates them (`SetOperationBuilder.cs:55-57`) and passes, so the observable is SQL shape — LibRed baselines of the `ConcatUnionTests` Intersect/Except cases contain `INTERSECT`/`EXCEPT` where the base capture has the emulation, with equal results (duplicate rows on both sides); `*All` variants and the 5 `Union5x` exclusions (`ConcatUnionTests.cs:486-535`) decided by triage — proof: characterization (observable: baseline diff)
- TO-8 CASE: LibRed baselines of a `Select` ternary / `switch` test contain `CASE WHEN` where the base capture has `IIF(`, rows equal; `Access.Ace.OleDb` baselines still `IIF(` (TO-10) — proof: control (observable: baseline diff)
- TO-9 VALUES table source, STRING_AGG (`StringJoinTests`), aggregate DISTINCT (U-4) — each only if its bucket enables it; else the bucket's re-exclusion is the obligation — proof: red→green per enabled feature
- TO-10 Symmetry guard on the unchanged path: `Access.Ace.OleDb` suite in chunks (fresh process each; union = full suite) = base failure set; its baselines identical to a base capture except the boolean sort-key delta and, since A-9, the `MOD` grouping delta (against `master`, which already carries the sort-key rewrite through #6203, the expected native delta is the `MOD` grouping only; since A-11 also the `^` grouping: `Round9` / `Round12` lose the parentheses in `* (10 ^ 1)` and `/ (10 ^ 1)`) — providers: `Access.Ace.OleDb` — proof: characterization
- TO-11 Full suite on both LibRed configs after triage: 0 unexplained failures (SC-4); on CI leg `z_Access_LibRed` if U-5 is green, else locally — proof: characterization
- TO-12 (A-6) `IsDistinctFromTests` on both LibRed configs: rows unchanged, LibRed baselines contain `IS DISTINCT FROM` / `IS NOT DISTINCT FROM` where the pre-A-6 capture has the `IS NULL` / `<>` expansion; `Access.Ace.OleDb` baselines of the fixture unchanged — proof: characterization (observable: baseline diff)
- TO-13 (A-6) `EnumerableSourceTests` (both partials) and the KeyedQuery eager-load tests (`EagerLoadingStrategyKeyedQueryTests`, `Issue5935Tests`) on both LibRed configs: pass, and LibRed baselines contain `(VALUES …) [alias](cols)` where the pre-A-6 capture has the FROM-less `UNION ALL`; the new E-24 test (`NULL` parameter in row 1 of a nullable column — U-10/U-12's `Object`-typed column through linq2db's reader, `ConvertFromDataReaderExpression.cs:223,265,298`) passes on both LibRed configs (native Access, DB2 and Informix excluded as for its `EnumerableSourceTests` siblings; measured on native Access: 4/4 OleDb/ODBC cases reject the FROM-less `UNION ALL` source with "Query input must contain at least one table or query"); the scalar-source alias list through `SelectQueryTests.Issue2779Test1` / `Issue2779Test4` (`SelectQueryTests.cs:256-270,310-326`, LibRed already included) — `FromSqlTests` scalar cases exclude `AllAccess` and do not reach it. The empty-source path (`BuildEmptyValues` → `BuildTypedExpression` `CAST`, `BasicSqlBuilder.cs:2170,4268-4275`) stays unreachable on LibRed: `CAST` does not parse (U-12) and `EnumerableSourceTests.EmptyValues*` / `EmptySubQuery` (`:771,791,837`) keep their `AllAccess` exclusion — proof: characterization (observable: baseline diff) + the new test
- TO-14 (A-6) `TakeSkipTests.TakeWithTies` / `TakeWithTies2` and `CachingTests.TakeHint` with LibRed added to their inclusion: red before E-20 (`LinqToDBException: TakeHints are … not supported`, `ExpressionBuilder.SqlBuilder.cs:109-110`), green after, with `TOP … WITH TIES` in the LibRed baseline — proof: red→green
- TO-15 (A-6) `StringJoinTests` item-form cases (separator, `null` items, and the `''`-item cell at `StringJoinTests.cs:401`) on both LibRed configs: rows unchanged, LibRed baselines contain `CONCAT_WS(` where the pre-A-6 capture has `Mid(`; the aggregate STRING_AGG cases and the `withoutSeparator` cases of `StringConcatTests` (`:217,443,461`) unchanged — proof: characterization (observable: baseline diff)
- TO-16 (A-6) `DateTimeFunctionsTests.CurrentTimestampUtc` (narrowed by E-24) green on LibRed with `GETUTCDATE()` (its `Kind == Unspecified` assertion at `:197-200` holds, U-12); `UtcNow`, `DateTimeOffsetNowUtc` (`AllAccess` in the `Full.DateTime` branch, `:302-311`), `NullabilityCheck` stay green server-side — proof: red→green for `CurrentTimestampUtc` only if it is red with the narrowing alone, else characterization
- TO-17 (A-6) Symmetry guard: the TO-12..TO-16 fixtures on `Access.Ace.OleDb` — results and baselines identical to the pre-A-6 capture (A-9: a `MOD` inside these fixtures may lose redundant parentheses; none is known to carry one; A-11: likewise a `^`, none known) — providers: `Access.Ace.OleDb` — proof: characterization
- TO-18 (A-7) `DistinctOrderByOuterJoinedBooleanKey` and `DistinctOrderByNullableBooleanSubQueryColumn` on `Access.LibRed.Mdb` and `.Accdb`, direct and `LinqService`: each red with E-35's gate removed and E-26 absent (NULLs on the wrong end; measured on #5956 2026-11-10 for the first, the flip for the second is master's pinned expectation), green after with `-[…]` under `SELECT DISTINCT` in the SQL; then the whole #6203 set — `DistinctTests` and `OrderByTests` — on both LibRed configs, direct and `LinqService` (the remote server re-runs the convert pass on an already-negated int key), 0 failures; control: the same two fixtures on `Access.Ace.OleDb`, unchanged — providers: `Access.LibRed.Mdb`, `Access.LibRed.Accdb` (direct + `.LinqService`), control `Access.Ace.OleDb` — proof: red→green + control
- TO-19 (A-9) `MathFunctionTests.ModuloOperandKeepsItsGrouping` (`(p.ID + 5) % 3`, `(100 - p.ID) % 3`, `AssertQuery` against the in-memory result): red without E-30 on native Access and LibRed (wrong values: `p.ID + (5 MOD 3)`), green with it; the existing `Round16` baselines move only by redundant parentheses around a `MOD` operand of `+` — providers: `Access.Ace.OleDb`, `Access.Ace.Odbc`, `Access.Jet.OleDb`, `Access.Jet.Odbc`, `Access.LibRed.Mdb`, `Access.LibRed.Accdb`, every other provider through the bare `[DataSources]` — proof: red→green. (A-10) Five arms: the two above, `100 - p.ID % 3` (a `MOD` operand of `-`), `(p.ID + 20) % ((p.ID * 5 + 3) % 5)` (right-nested `MOD`, divisor always 3) and `(p.ID + 20) % (p.ID * 3)` over `p.ID > 0` (a product as the right operand); the right-nested arm is red at `Subtraction + 1` (`MathFunctionTests.cs:492`) and green at `Multiplicative`. Arms 3 and 5 are controls, not red→green arms (critic round 8): arm 3 needs no parentheses at 71 or 80 and is wrapped at 59, and arm 5 is parenthesized at 80 by `Wrap`, so neither can go red under any of the three precedences, and arm 5 does not measure LibRed's own `MOD`-vs-`*` order — the engine never sees the ambiguous form; at `Subtraction + 1` arm 5 never executed, because arm 4 threw first
- TO-20 (A-10) `IntervalTranslationTests.MillisecondComponentHoldsPastTheRangeOfItsCounter`: the `Milliseconds` component over 32 days, 75 years and 125 s, both directions, equals the CLR value derived from the stored dates; native Access refuses it as its siblings do (`ComponentBelowResolution`) — providers: `Access.LibRed.Mdb`, `Access.Ace.OleDb` (refusal), `SQLite.MS`, every other provider through the bare `[DataSources]` — proof: characterization (it answers review MIN001, which predicted a >2^31 `DateAdd('ms')` shift fails; green on LibRed refutes it)
- TO-21 (A-10) Aggregate DISTINCT on LibRed, grouped and in correlated scalar sub-queries: `GroupByTests.CountInGroup` emits `COUNT(DISTINCT …)` where the `cd009d488` capture has correlated `SELECT COUNT(*) FROM (SELECT DISTINCT …)` sub-queries (measured: 6× `COUNT(DISTINCT`, 0× `SELECT DISTINCT`), rows unchanged; every fixture in the E-31 P7 row green — providers: `Access.LibRed.Mdb`, `Access.LibRed.Accdb` (CI) — proof: characterization (observable: baseline diff)
- TO-22 (A-11) A `MOD`, product or sum operand of native `^` keeps its grouping: `ModuloOperandKeepsItsGrouping` arms `Math.Pow(p.ID % 3, 2)` / `Math.Pow(2, p.ID % 3)` and new `PowerOperandKeepsItsGrouping` (`Math.Pow(p.ID * 2, 2)`, `Math.Pow(p.ID + 1, 2)`), bare `[DataSources]` — providers: `Access.Ace.OleDb` (red at `2d0ac39ad`: `ID MOD 9`, `(2 ^ ID) MOD 3`, `ID * 4`, `ID + 1`), `Access.LibRed.Mdb`, `SQLite.MS` (controls), rest on CI — proof: red→green (observable: values)
- TO-23 (A-12) A XOR operand of `BOR`, on either side, keeps its grouping on every Access flavour: `WhereTests.BinaryXorUnderOr` (`ID | (ID ^ 1)`, rows 1 and 3) and `BinaryXorOverOr` (`(ID ^ 1) | 2`, row 2) — red on `Access.LibRed.Mdb` at `203e2852d` (0 rows each, direct and remote); mutation "arm at `Bitwise - 1`" red on `Access.Ace.OleDb` and `Access.LibRed.Mdb` (both tests); green at `Bitwise - 2` on `Access.Ace.OleDb`, `Access.Ace.Odbc`, `Access.LibRed.Mdb`, `Access.LibRed.Accdb` — providers: those four, `Access.Jet.*` on CI (x86 only), every other provider through the bare `[DataSources]`, `SqlCe` gated — proof: red→green + mutation
- TO-24 (A-12) Native C# XOR renders `BXOR`, not a power: `WhereTests.BinaryXor` on native Access — mutation "drop E-36's arm" red on `Access.Ace.OleDb` and `Access.LibRed.Mdb` (all three XOR tests, direct and remote); green with it; `BinaryAnd` / `BinaryOr` green on `Access.Ace.OleDb` / `Access.Ace.Odbc` (their exclusion was stale) — providers: `Access.Ace.OleDb`, `Access.Ace.Odbc`, `Access.LibRed.Mdb`, `Access.Jet.*` on CI — proof: red→green (mutation) + characterization
- TO-25 (A-12) A power on LibRed renders `x ^ y` and keeps E-34's grouping: `MathFunctionTests` (whole fixture, incl. `Pow*`, `Round*`, `ModuloOperandKeepsItsGrouping`, `PowerOperandKeepsItsGrouping`) green on `Access.LibRed.Mdb` with no `Power(` in the SQL — providers: `Access.LibRed.Mdb`, `Access.LibRed.Accdb` on CI — proof: characterization (observable: baseline diff, `Power(x, y)` → `x ^ y` on LibRed)
- TO-26 (A-12, critic round 10) A power as the exponent keeps its grouping: `MathFunctionTests.PowerOfPowerKeepsItsGrouping` (`Math.Pow(2, Math.Pow(ID % 3 + 1, 2))`, and the left-nested `Math.Pow(Math.Pow(…, 2), 3)` as a control — Access evaluates `^` left to right, so the bare left-nested form is right) — red on `Access.Ace.OleDb`, `Access.Ace.Odbc`, `Access.LibRed.Mdb` with E-40 mutated off (64 for 512; direct and remote), green with it; `SQLite.MS` green both ways (control) — providers: `Access.Ace.OleDb`, `Access.Ace.Odbc`, `Access.LibRed.Mdb`, `SQLite.MS`, every other provider through the bare `[DataSources]` — proof: red→green (mutation) + control
- TO-27 (A-12, critic round 10) A `BAND` operand of `BXOR`, either side, is emitted bare and stays right because `BAND` binds tighter: `WhereTests.BinaryAndLeftOfXor` (`(ID & 3) ^ 1`) / `BinaryAndRightOfXor` (`ID ^ (ID & 1)`) — green on `Access.Ace.OleDb`, `.Odbc`, `Access.LibRed.Mdb` (`[PersonID] BAND 3 BXOR 1`, `[PersonID] BXOR [PersonID] BAND 1`); Access-only, other providers' bitwise grouping is #6243's — providers: `Access.Ace.OleDb`, `Access.Ace.Odbc`, `Access.LibRed.Mdb`, the rest of `AllAccess` on CI — proof: characterization (a guard: E-36 at 38 relies on `BAND` at 40)

## P9 Verification gates

All rows recorded 2026-11-15 against head `cd009d488` (A-8). Runs marked *(PR body)* were made by the author and are
recorded in the #5969 body; they are not re-run here.

- G-01: blocked — CI `test-all` 25696 and GitHub `tests [all]` 43718171491 at `cd009d488`, in flight at amendment time. Per obligation:
  - TO-1: characterization — the inventory is the trajectory in *Resuming — history*: 1227 → 340 → 109 → 36 → 2 → 10, each failure bucketed *(PR body / history)*.
  - TO-2..TO-9: covered by the full sweep below; per-bucket red→green was observed during triage but is not recorded per obligation.
  - TO-10: skipped — the `Access.Ace.OleDb` chunked symmetry run is not recorded; native coverage rests on CI's native Access legs (green at `817b052c2`, run 35991422429, *(PR body)*); SC-3 is unverified at this head until 25696 finishes.
  - TO-11: full local sweep on `Access.LibRed.Mdb`, net11.0, `LibRed.Ado` 11.0.0-beta.1: 10 748 tests, 0 failed, 162 skipped *(PR body; pre-rebase head, `range-diff` unchanged)*; `Access.LibRed.Accdb` full suite only on CI — blocked on 25696.
  - TO-12..TO-16: A-6 fixtures green on both LibRed configs *(PR body, at alpha.4)*; TO-14 red before the flag, 12/12 after *(PR body)*.
  - TO-17: same 12 fixtures on `Access.Ace.OleDb` with and without A-6, identical results, SQL differing only in `DateTime.Now` literals *(PR body)*.
  - TO-18: the two tests red 8/8 on LibRed without E-26, green with it; `DistinctTests` + `OrderByTests` green on both LibRed configs and on `Access.Ace.OleDb` after a re-run — the first `Access.Ace.OleDb` run had 7 gRPC transport failures, 14/14 on re-run *(PR body)*; the remote half's "0 failures" therefore rests on the re-run.
  - TO-19: red without E-30 on native Access and LibRed, green with it *(PR body, `02eb16f04` section)*; at this head the native `ModuloOperandKeepsItsGrouping` baselines are added on all four native configs and `Round16` moved only by parentheses (G-02); per-provider results blocked on 25696.
  - test-diff-sweep (`test-diff-sweep.ps1 -Repo . -Ref origin/pr/5969`, implemented tree) — the script reads only attributes whose provider token sits on the attribute's own line: 4 one-line chains (`DistinctTests.cs:361,362`; `WindowFunctionsTests.RowNumber.cs:183,213`), 3 nested chains (`MathFunctionTests.cs:469,470` — TO-19's test; `WindowFunctionsTests.RowNumber.cs:175`) — since resolved by A-10 (fixed or cleared, see its G-01 line below); 287 single-line narrowed sets, 262 without a reason line — E-1 `AllAccess` → `AllNativeAccess` widenings and E-24 LibRed additions (`CachingTests.cs:215`, `TakeSkipTests.cs:700,715`), except `Issue4336Tests.cs:21`, whose widening is paired with a new LibRed `[ActiveIssue]` (`:18-19`, E-3, A-8) and so adds no LibRed coverage.
  - continuation lines (the sweep's blind half, tallied separately: added `Tests/` lines carrying a provider token outside an attribute's opening line, `git diff -U0 origin/master...origin/pr/5969 -- Tests`): 103 lines — 91 `AllNativeAccess`, 8 `AllAccessLibRed`, 4 without an Access token (re-wrapped lines of shared constants and two `ThrowsForProvider` percentile lists whose Access token was removed by A-5); the seven A-8 sites are among the 91. No new narrowing among them; the 4 re-wrapped lines are classified by reading, not by a script.
  - A-10 (uncommitted worktree tree on `cd009d488`, 2026-11-15, net11.0): TO-19 red at `Subtraction + 1` on `Access.LibRed.Mdb` / `Access.Ace.OleDb` (right-nested arm, `MathFunctionTests.cs:492`), green at `Multiplicative`; Debug: LibRed `MathFunctionTests`+`IntervalTranslationTests`+`GroupByTests`+`StringJoinTests`+`CountTests` 715/0/3, Ace.OleDb `MathFunctionTests`+`IntervalTranslationTests` 284/0/1; Release: LibRed E-31 census fixtures 498/0/6, Ace.OleDb `ConvertTests` 132/0/2; TO-20 (after its 1/300 s fix) green on `SqlCe`, `Access.LibRed.Mdb`, `Access.Ace.OleDb`, `SQLite.MS` — its first SqlCe run failed 347 vs 346 because `.345` is not a 1/300 s step (test input, not product); TO-21 SQL captured (6× `COUNT(DISTINCT`). Release builds `LinqToDB` netstandard2.0 and `Tests/Linq` net11.0: 0 warnings. test-diff-sweep (`-IncludeWorkingTree`): 6 one-line chains — `DistinctTests.cs:361,362` and `WindowFunctionsTests.RowNumber.cs:185,215` cleared in the review walk (re-indents / no chain), `IntervalTranslationTests.Difference.cs:1034,1035` fixed (constructor form). Remote parity: no `BaselinesPath` in the worktree — `skipped`, left to CI.
  - A-11 (uncommitted worktree tree on `2d0ac39ad`, `C:/Worktrees/linq2db/5969-review-probe`, 2026-11-16, net10.0 Debug): TO-22 red per arm on `Access.Ace.OleDb` at Additive (6 of 7 arms; `-Math.Pow` is correct at every precedence) and at plain `Unary` (negation arm only), each as a separate scratch test, since removed; green at `Unary + 1` through `factory.Binary`: `ModuloOperandKeepsItsGrouping` + `PowerOperandKeepsItsGrouping` + `Pow*` + `Round*` on `Access.Ace.OleDb`, `Access.LibRed.Mdb`, `SQLite.MS`, direct and remote, 149/0. Release `LinqToDB` netstandard2.0: 0 warnings; Release `Tests/Linq` net10.0: 0 warnings, 0 errors.
  - A-12 (uncommitted worktree tree on `203e2852d`, `C:/Worktrees/linq2db/5969-libred-dialect`, 2026-11-16, net10.0 Debug): TO-23 red before on `Access.LibRed.Mdb`, direct and remote (`BinaryXorUnderOr` 0 of 2 rows, `BinaryXorOverOr` 0 of 1); mutation run (`mutation-run.ps1`, `Access.Ace.OleDb` + `Access.LibRed.Mdb`): "drop E-36's arm" 12/15 red (every XOR test, both providers, direct and remote — TO-24), "arm at `Bitwise - 1`" 8/15 red (`BinaryXorUnderOr` / `BinaryXorOverOr`, both providers — TO-23), files restored byte-exact. Green: `WhereTests.Binary*` + `MathFunctionTests` + `ContainsOverADifference` — `Access.LibRed.Mdb` 134/0/1 (the gated case reports "still failing as expected" with E-39's message), `Access.Ace.OleDb` 129/0, `Access.Ace.Odbc` 129/0; LibRed SQL has no `Power(` (TO-25); `WhereTests.Binary{Xor*,And,Or}` green on `SQLite.MS`, `SQLite.Classic`, `DuckDB`, `Access.LibRed.Accdb`; `SqlCe` `BinaryXorUnderOr` red (T-SQL, master's SQL), gated on #6243, gate verified direct and remote; `Access.Jet.OleDb` not runnable on this x64 host (driver not registered) — CI. Release `LinqToDB` netstandard2.0 and `Tests/Linq` net10.0: 0 warnings. test-diff-sweep (`-IncludeWorkingTree`): chains 4 (`DistinctTests.cs:361,362`, `WindowFunctionsTests.RowNumber.cs:185,215` — cleared in round 1), nestedChains 0, narrowedSets 284 (259 without a reason line; −3 from E-38), shouldlySubjectGates 0, typeOnlyShouldlyGates 0 (was 1, E-39), continuationIndents 0, unanchoredAssertionGates 0, narrowedContinuations 68, cacheMissOutsideQueryCacheTest 0.
  - A-12, critic round 10 responses (same tree, after E-40): probes on `Access.Ace.OleDb`, `.Odbc`, `Access.LibRed.Mdb` — right-nested power red (64 for 512) on all three before E-40, left-nested green; `BAND` either side of `BXOR` green; bool XOR green in `WHERE` and projection (scratch tests, removed or kept as TO-27). Mutation run (`pr5969-r3-mutations2.json`, OleDb / Odbc / LibRed.Mdb / SQLite.MS): green 24/24, "drop the exponent wrap" 6/24 red (`PowerOfPowerKeepsItsGrouping` on the three Access providers, direct and remote — TO-26), SQLite control green. Final: `MathFunctionTests` + `WhereTests.Binary*` + `ContainsOverADifference` — `Access.Ace.OleDb` 135/0, `Access.LibRed.Mdb` 140/0/1, `SqlCe` 134/0/3 (gates verified); LibRed renders `2 ^ (([ID] MOD 3 + 1) ^ 2)`.
- G-02: blocked — `baselines/pr_5969` is being rewritten by 25696; the Access legs (LibRed, Jet ODBC/OLEDB, ACE ODBC/OLEDB) committed for this head 13:38–13:47Z; reviewed in `/review-pr 5969` round 1 (Access subset). Native Access rows at this head (`baselines-pr-scan.ps1`, 2026-11-15): 2 files per native config — `Round16` modified (E-30: `([p].[ID] MOD 2) + 2` → `[p].[ID] MOD 2 + 2`, value-equal) and `ModuloOperandKeepsItsGrouping` added; no boolean sort-key delta (master's #6203 already carries it). SQL Server `Round4` / `Round4Sql` / `Round11` modifications are from the 2026-11-09 run (author date) and predate the rebase — not attributed to this branch until 25696's SQL Server legs rewrite them.
- G-03: pass — all new types and overrides are `LinqToDB.Internal.*` with `PublicAPI.Unshipped.txt` entries (e.g. `:390,424` for E-28); Release analyzers and XML docs: GitHub `Build and pack` green at `cd009d488` (run 43718131014).
- G-04: n/a — no shipped member removed or changed; ApiCompat runs in `Build and pack`, green at `cd009d488`.
- G-05: blocked — GitHub `Build and pack` (all TFMs, Release) green at `cd009d488` (run 43718131014); Azure `build` 25695 pending at amendment time.
- G-06: blocked — the round-1 review (G-09).
- G-07: pass — `git diff --name-only origin/master...origin/pr/5969 -- Tests/Tests.Playground` is empty.
- G-08: n/a — no SQL AST / `IDataProvider` / translator-interface / `BasicSqlBuilder` / `BasicSqlOptimizer` edit (P3); reconcile at `cd009d488`: 114 files covered, 0 unplanned — file-keyed, so it cannot see an unplanned hunk in a planned file (the E-30 hunk sat unrecorded in E-10's file until A-9); the shared hunks were enumerated by `git diff origin/master...origin/pr/5969 -- Source/LinqToDB` in critic rounds 6–7 (`Sql/*.cs`: LibRed-keyed attributes and a `DateDiffBuilderAccess` refactor passing `millisecondPart: null`), which reports the others as defaulted virtual switches; beside them, A-3's `BuildUpdateClause` position fix is a non-switch shared hunk recorded as native-equivalent (A-3: "native is at 0 either way"), so E-30 is the only shared hunk known to move native output.
- G-09: blocked — `/review-pr 5969` round 1 (2026-11-15) is the adversarial read.

## P10 Adjudicated (M/L)

- (A-12) The `MOD` / `^` precedence fixes (E-30, E-34, E-35) stay on this PR rather than a separate patch PR (AGENTS.md's separable-fix default; Igor Tkachev's review SUG002). Reason: user decision at A-9, re-confirmed in review round 3 — no 6.5.x milestone is open, so a split PR ships in 6.6.0 with this one, and E-34 depends on E-30's move.
- (A-12) A bool XOR (`(a == 1) ^ (b == 2)`) needs no arm of its own: its comparison operands reach `BXOR` already parenthesized (`([PersonID] = 1) BXOR ([PersonID] = 2)`), probed green in `WHERE` and in a projection on `Access.Ace.OleDb`, `.Odbc`, `Access.LibRed.Mdb` (critic round 10 lead). Reason: measured, no test kept.
- (A-12) `Access.Jet.OleDb` / `.Odbc`, YDB and Sybase are not measured for E-36..E-40 here (Jet's OLE DB driver is x86-only on this host; no YDB / Sybase / SQL Server container); their verdict is the CI run after the push, and a red there is fixed or gated with a per-leg `[ActiveIssue]` before merge. Reason: no local route; CI runs all of them.
- (A-12) `MathMemberTranslator.Power` stays `protected virtual` with no override left: it is the extension point a flavour with a different power operator would use, as LibRed's was. Reason: kept for symmetry with the other Access switches; costs nothing.
- (A-10) A `Skip` without `OrderBy` on LibRed pages an unordered result (no ORDER BY injected, D-4 amended). Reason:
  LibRed does not require one, linq2db promises no order without `OrderBy`, and SQLite / PostgreSQL behave the same.
- (A-10) `DateTimeOffset.UtcNow` on Access is one hour off as an instant on a +01:00 host, on LibRed (now `GETUTCDATE()`)
  and on native ACE (no translation: a parameter) alike — measured 60.0 min both, review round 1. Reason: Access has no
  offset-carrying type, so a value read back as `DateTimeOffset` takes the client's local offset whatever produced it;
  E-22's routing does not change the outcome. Already the documented expectation: `DateTimeFunctionsTests.DateTimeOffsetNowUtc`
  lists `TestProvName.AllAccess` in its wall-clock-only branch (`:290-299`; TO-16's `:302-311` cites the same branch's assertion).
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
- A-7 (2026-11-10, user: "a" — make LibRed work, split with #5956) — master's #6203 ported this plan's A-1 sort-key
  rewrite (the merged visitor equals this branch's) and brought `DistinctTests.DistinctOrderByOuterJoinedBooleanKey`,
  which #5956 gates on LibRed (its A-22 / E-35). **Measured on #5956:** LibRed returns `NULL` for the unmatched
  outer-join rows where Jet / ACE return `False`, and the DISTINCT flip (`AccessSqlExpressionConvertVisitor.cs:565`)
  then orders those NULLs against .NET (the flip is decided at `:571` at `cd009d488`); LibRed **accepts** `ORDER BY -[t].[BoolValue]` under `SELECT DISTINCT` and
  returns `null, False, True`, where ACE rejects it (*"conflicts with DISTINCT"*) — the engine limit the A-1 residual
  note (top of file, *Open* item 1) recorded for native Jet only.
  - decision: E-26 — the flip-only rule becomes a native default behind a virtual, overridden for LibRed, in the visitor
    that already carries this branch's LibRed-only overrides (D-3). E-27 — the test expects each engine's own
    unmatched-row value. rejected: wrapping the DISTINCT query in a sub-query so a native engine could negate too —
    changes SQL shape for every flavour, and A-1 / critic round 2 already measured that path as the one that regressed.
  - measured after critic round 5 (#5956 probe, LibRed.Mdb vs Ace.OleDb): LibRed accepts a negated key under
    `SELECT DISTINCT` for a select-list expression, a sub-query column and a key outside the select list, each in the
    .NET order; it rejects a negated alias, which linq2db never emits; ACE rejects all four. linq2db already wraps the
    expression shape (`… FROM (SELECT DISTINCT …) ORDER BY -[t1].[Value_1]`), so E-26 changes the SQL of the sub-query
    column and outer-join shapes only — hence E-29.
  - failure mode: E-26 also reaches window `ORDER BY` items? No — `VisitSqlWindowOrderItem` (`:576-586` when written; `:582-592` at `cd009d488`) has no
    DISTINCT input and is untouched; only `VisitSqlOrderByItem` reads the flag.
  - re-derives: A-1 (its DISTINCT residual is lifted for LibRed); P7 (new A-7 row: `CanNegateSortKeyUnderDistinct` has one reader, `:571`); P4: no new row — the engine behaviour is the measured A-7 bullet above; TO-10 / TO-17 (native symmetry — E-26's default keeps
    native output byte-identical, TO-18's control measures it).
  - conventions: (added by A-8, after the fact) `testing.md` → *Test layout*, *A narrowed provider set is a claim*; swept with `test-diff-sweep.ps1 -Repo . -Ref origin/pr/5969` at `cd009d488` — hits in E-27 / E-29 territory: `DistinctTests.cs:361,362` (one-line chains), open for the round-1 review walk; counts in G-01.
- A-8 (2026-11-15) — commits since A-6 that changed tests without an amendment, and the rebase. Widened after critic round 6, which found the 2026-11-09 commits between A-6 and A-7 un-amended too:
  - `3aeb1f887`: master-merge `AllAccess` exclusions narrowed to `AllNativeAccess` where LibRed passes — 24 lines in 11 files (`ConvertTests`, `DateTimeFunctionsTests`, `EagerLoadingStrategyKeyedQueryTests`, `ExpressionTests`, `FromSqlTests`, `JoinTests`, `LoadWithTests`, `ParameterTests`, `PreferClientCalculationTests`, `SelectTests`, `StringConcatTests`); E-1 instances.
  - `12f449283` (E-3 instances): `Issue4336Tests.cs:18-19` new `[ActiveIssue(Configuration = AllAccessLibRed, ErrorMessage = "Column 'vpcc.Id' was not found")]` — a LibRed join-key limitation, `no-issue:`, its `Details` stamped alpha.4 on a beta.1 branch (open for the review walk); `InsertTests` `DistinctInsert1/2` and `FunctionTests.NewGuid1` gain `NoBaselines` on `AllAccessLibRed` (client-side Guid generation); `DateTimeFunctionsTests` drops a LibRed `[ActiveIssue]` ("Function MAX is not supported") that the dialect now passes; `QueryGenerationTests.ToSqlQuery_IUpdatable_ClientIdentiy` re-excludes LibRed (`AllNativeAccess` → `AllAccess`, AutoNumber update).
  - `02eb16f04`: the `MOD` precedence fix — a native SQL change, recorded separately as A-9.
  - `6a83b4f37` (pre-rebase `92e49c09d`): master's incoming `FullJoinMethodTests` exclusion narrowed `AllAccess` → `AllNativeAccess`; 4 tests pass on both LibRed configs, direct and remote, 10/10 each *(PR body)*.
  - `cd009d488`: `FullJoinTupleOverload`, `FullJoinTupleOverloadComposed` (#6316) and `InlineArrayMinMax` (#6074) narrowed the same way; 8/8 each on both LibRed configs, direct and remote *(PR body)*. LibRed.Ado beta.1 sweep: 10 748 / 0 failed / 162 skipped on `Access.LibRed.Mdb`; no `[ActiveIssue]` gate passes, so none lifts.
  - Both are instances of E-1 (exclusion-form `AllAccess` → `AllNativeAccess`, measured per site) — no new `E-n`, so no P12 round is owed.
  - Rebase onto `master` after #5956 merged (`d5f5c9378`): the #5970 fix with its test-ordering follow-up and the positional-placeholder `FromSql` gate dropped as already on `master`; 11 duplicate `PublicAPI.Unshipped.txt` lines dropped (already in `Shipped`). The plan's header and *Resuming* updated (base `master`, milestone `6.6.0`); P10's "#5969 keeps its identical copy" of the #5970 fix is superseded — the branch no longer carries it.
  - P9 recorded for the first time (G-01..G-09), from CI evidence at `cd009d488` and the author's runs in the PR body; the open rows name their dependency.
  - re-derives: P7 (A-7 row added); P8 TO-18 (providers field); P9 (first record); P10 (the #5970 copy note).
  - conventions: `testing.md` → *Test layout*, *A narrowed provider set is a claim*; the A-8 sites are exclusion rewrites, each measured on both LibRed configs; whole-branch sweep counts in G-01 (single-line attributes by the script, continuation lines tallied separately).
- A-9 (2026-11-15, user: "a" — keep the `MOD` fix on #5969) — `02eb16f04` (2026-11-09) changed the shared `AccessSqlExpressionConvertVisitor`: `%` → `MOD` at `Precedence.Subtraction + 1`, was `Precedence.Additive - 1`. Access binds `MOD` tighter than `+`/`-`, so `(a + b) % c` rendered `a + b MOD c` and returned wrong values on every flavour. Pre-existing on `master`, recorded on #6243; whether the PR closes #6243 depends on that issue's scope, since a right-nested `a % (b % c)` stays unparenthesized (P7 A-9 row), and the body carries no `Fixes #6243` yet.
  - new E-30; P3 and SC-3 gain the exception; P7 row (A-9); TO-19.
  - rejected: port to its own PR off `master` (the #5970 precedent) — user chose to keep it; the fix is one line in a file this branch already edits and its test runs on every provider.
  - failure mode: the precedence also drops redundant parentheses around a `MOD` operand of `+`/`-` on every native flavour (`Round16`); value-equal because `MOD` now sits above `+`/`-`, and still below `*` / `/` (80), so `a * b MOD c` and `a MOD b * c` keep their former grouping — reasoned from `Precedence.cs`, unprobed for `*`/`/` mixes. (Superseded by A-10: at `Multiplicative`, `MOD` shares `*` / `/`'s level and `Wrap` parenthesizes every equal-precedence operand, so `[t].[MoneyValue] * 10 MOD 10`-shaped SQL now gains parentheses — value-equal.)
  - **The approval of record is void for E-30 and must be re-earned** (critic round 7, then the user).
  - re-derives: P3, SC-3 (the native-unchanged clause), P7 (A-9 row), P8 TO-10 / TO-17 (their "boolean sort-key delta only" now also admits the `MOD` grouping delta) and TO-19, P9 G-01 / G-02 / G-08.
  - conventions: `testing.md` → *Test layout*; `ModuloOperandKeepsItsGrouping` is bare `[DataSources]` and so reaches every provider; the sweep's nested-chain hits at `MathFunctionTests.cs:469,470` are its two `AssertQuery` lines — open for the review walk.
- A-10 (2026-11-15, review round 1 walk, user dispositions) — fixes from `/review-pr 5969` round 1, measured in worktree `C:/Worktrees/linq2db/5969-libred-dialect` (net11.0 Debug):
  - MIN003 → E-30 re-worded: `MOD` at `Precedence.Multiplicative`. Red first: TO-19's right-nested arm failed at `Subtraction + 1` on `Access.LibRed.Mdb` and `Access.Ace.OleDb`, direct and remote (`MathFunctionTests.cs:492`), other arms green; SQLite.MS green. After: `MathFunctionTests` + `IntervalTranslationTests` 284/0/1 on `Access.Ace.OleDb`; with `GroupByTests` / `StringJoinTests` / `CountTests` 715/0/3 on `Access.LibRed.Mdb`. Expected baseline churn: `(x * k) MOD k`-shaped Access SQL gains parentheses (value-equal), read on the CI baselines PR.
  - SUG001 / NIT002 → TO-19's third to fifth arms and one-call-per-line layout.
  - MIN001 refuted: TO-20 green on LibRed over 32 days and 75 years; `ALongSpanIsMeasuredWhereCountingAnswersIt` (`IntervalTranslationTests.Difference.cs:656`) already showed LibRed's `DateAdd('s', DateDiff_Big('s', …))` past 2^31. No code change; the test stays.
  - MIN002 → D-4 amended (injection rejected), TO-3 rewritten, P10 line. No code change.
  - Aggregate DISTINCT (out-of-scope observation, promoted) → E-31, E-32, U-4 resolved, TO-21. SQL captured (G-01).
  - `DateTimeOffset.UtcNow` (out-of-scope observation) → measured equal before and after (P10); the probe test was removed.
  - MIN004, NIT001, NIT003 → E-33. `Issue4336` recorded in `plans/feature-access-libred/findings.md` (beta.1 section).
  - Out-of-scope, probed: `|` / `^` at one bitwise level renders wrong values on SQLite (`a | b & c`) and LibRed (`a BOR b BXOR c`; E-16's `BXOR` at `Bitwise - 1`, A-3) → comment on umbrella #6243 (issuecomment-6901088207), with the `MOD` update; Access LIKE escaping of a closed bracket pair next to an unclosed `[` (pre-existing, all flavours) → #6334, Backlog.
  - Pushed as `d8051a1f9` (E-30, TO-19), `ce8d82288` (E-31, E-32), `e4b79f9ef` (TO-20), `2d0ac39ad` (E-33 rest); PR body *Follow-up commits* section appended.
  - **The approval of record is void for E-30 (re-worded), E-31..E-33 and must be re-earned** (critic round 8, then the user).
  - re-derives: P4 U-4; P5 D-4 (its "in E-7" sentence and the P7 SqlCe row's injection half, both marked superseded); P6 E-30..E-33; P7 (A-9 row: the right-nested case is now fixed; new E-31 row); P8 TO-3, TO-19 (arms 3 and 5 relabelled controls, critic round 8), TO-20, TO-21; P10 (two lines); P11 A-9's failure-mode line (`*` / `/` grouping, marked superseded); P9 G-01 / G-02 to re-record after the commit. Baseline churn expected from E-30: `ConvertTests.ConvertTo*` (`* 10 MOD 10`), `MathFunctionTests.Round1/2/7/8/15`, `IntervalTranslationTests` (`@Ticks * -1 MOD …`, `* 10000000 MOD …`), native and LibRed — parentheses only.
  - conventions: `testing.md` → *Test layout*, *A narrowed provider set is a claim* — TO-20 carries its siblings' measured gates (`ComponentBelowResolution` on `AllNativeAccess`, `UnsupportedDifferenceProviders`); test-diff-sweep re-runs on the implemented tree before the commit (G-01).
- A-11 (2026-11-16, review round 2 walk, user disposition "fix here") — MIN005 → MAJ, measured in worktree `C:/Worktrees/linq2db/5969-review-probe` (net10.0 Debug):
  - Defect: E-30 put native `MOD` (80) above native `^`, which `MathMemberTranslator.Power` built through `factory.Binary` at `Precedence.Additive` (60). `Wrap` parenthesises only a lower-precedence child, so a `MOD` operand of `^` lost its parentheses (master's `MOD` at 59 kept them). Access evaluates `^` first. Red on `Access.Ace.OleDb` at `2d0ac39ad`: `Math.Pow(ID % 3, 2)` returned `ID MOD 9`, `Math.Pow(2, ID % 3)` returned `(2 ^ ID) MOD 3` — regressions; `Math.Pow(ID * 2, 2)` returned `ID * 4` and `Math.Pow(ID + 1, 2)` returned `ID + 1` — pre-existing on master, same mechanism. Critic rounds 7–8's "no native `^` producer" was wrong.
  - Fix: E-34 (native `^` at `Precedence.Unary + 1`) through E-35 (`factory.Binary` overload with a precedence, per the user: use the factory, add the overload). Every operator-node operand of `^` is now wrapped (P7 E-34 operator table); a `^` operand of `*` / `/` / `+` / unary minus stays bare, which Access's order makes correct (unary-minus parent probed: `-Math.Pow(ID, 2)` renders `-[ID] ^ 2`, right values at HEAD and after).
  - Red per arm (critic round 9), each measured as its own scratch test on `Access.Ace.OleDb` so no arm masks another: at `2d0ac39ad`'s precedence (Additive) `MOD` left/right, product, sum, difference (`100 - ID^2`) and negation (`-(ID^2)`) all wrong; with `^` at plain `Precedence.Unary` only the negation arm is red — so the `+ 1` is load-bearing and pinned by TO-22's negation arm. A signed literal base, `Math.Pow(-2, ID)`, renders `-2 ^ [ID]` and Access returns `(-2) ^ ID` (right signs for odd and even `ID`) — critic round 9's lead refuted, no change.
  - Green: TO-22 (seven arms over the two tests) and `Pow*` / `Round*` / `ModuloOperandKeepsItsGrouping` on `Access.Ace.OleDb`, `Access.LibRed.Mdb`, `SQLite.MS`, direct and remote — 149/0 on the factory form (G-01). Release `LinqToDB` netstandard2.0: 0 warnings.
  - Expected baseline churn, native Access only: `MathFunctionTests.Round9` / `Round12(AwayFromZero,1|2)` lose the parentheses in `* (10 ^ 1)` and `/ (10 ^ 1)` (value-equal); `Pow*` baselines unchanged; the new test and the new `ModuloOperandKeepsItsGrouping` statements are added on every provider. TO-22's arms assert exact `double` equality under bare `[DataSources]`, unlike the sibling `Pow`'s `Math.Floor`; small-integer powers on providers beyond the three run are left to CI.
  - Known limit, unchanged from master (reasoned, unprobed): a right-nested `Pow(a, Pow(b, c))` renders `a ^ b ^ c`, which Access reads as `(a ^ b) ^ c`; `Wrap` parenthesises an equal-precedence right operand only for `-`, `*` and `NOT`. Belongs on umbrella #6243.
  - **The approval of record is void for E-34, E-35 and must be re-earned** (critic round 9, then the user).
  - re-derives: P2 SC-3 (native also changes for an operand of `^`; A-10 already left SC-3's `MOD` wording stale — the `*` operand of `MOD` gaining parentheses; both done), P6 E-34/E-35, P7 (new E-34 operator-table row), P8 TO-10 / TO-17 (the `^` delta) and TO-22, P9 G-01 (A-11 line) / G-02 (on the CI baselines PR after the push) / G-08 (E-35 is a shared-file edit: an additive overload, default unchanged; `MemberTranslatorTests.cs:35` is the only other caller), P12 round 9.
  - conventions: `testing.md` → *Test layout*; TO-22's tests follow `ModuloOperandKeepsItsGrouping`'s one-call-per-line form and the sibling `Pow`'s bare `[DataSources]`.
- A-12 (2026-11-16, review round 3 walk incl. Igor Tkachev's review at `2d0ac39ad`, user dispositions "fix here") — measured in worktree `C:/Worktrees/linq2db/5969-libred-dialect` (net10.0 Debug):
  - Defect (MAJ001, Igor's): E-16 registered LibRed's `BXOR` at `Precedence.Bitwise - 1`, `BOR`'s level. LibRed (grammar `v11.0.0-beta.1`: `AND|BAND` > `OR|BOR` > `XOR|BXOR`) and native Jet/ACE (measured by mutation) both rank `BXOR` below `BOR`, so `a | (b ^ c)` → `a BOR b BXOR c` read as `(a BOR b) BXOR c`, and `(a ^ b) | c` → `a BXOR b BOR c` read as `a BXOR (b BOR c)`. `findings.md:53`'s "one level, left to right" came from the first shape only, which both readings answer alike; corrected.
  - Defect (OBS-XOR, promoted): native Access rendered C# XOR as `^`, a power. E-16's comment "LibRed has the bitwise operator Jet lacks" was never probed; `Access.Ace.OleDb` and `.Odbc` accept `BXOR`, `BAND` and `BOR`.
  - Fix: E-36 (shared `BXOR` arm at `Bitwise - 2`, guarded to `Precedence.Bitwise` so E-34's power `^` passes through), E-37 (LibRed's binary override and `Power(x, y)` translator deleted — their only reason was the unguarded arm), E-38 / E-39 (tests, gates, docs).
  - Not this PR's, surfaced by TO-23: T-SQL `|` / `^` at one level — `SqlCe` red on `BinaryXorUnderOr` (`[PersonID] | [PersonID] ^ 1`); the test is new, the SQL is master's (no SqlCe edit). Gated on #6243 for `SqlCe`; the SQL Server / Sybase / PostgreSQL legs are left to CI and gated from its results.
  - Also: MIN006 (type-only Shouldly gate over three assertions; the gate hid that the IN-list half now answers on LibRed beta.1), NIT004 (two Jet/ACE-only summaries), Igor's MIN005 (missing `PublicAPI.Unshipped.txt` line). Igor's SUG002 (split the `MOD` fix): kept, see P10.
  - Expected baseline churn: LibRed `Pow*` / `Round*` / `*OperandKeepsItsGrouping` — `Power(x, y)` → `x ^ y`; native and LibRed `BinaryXor*` / `BinaryAnd` / `BinaryOr` added on native Access; `BinaryXorUnderOr` / `BinaryXorOverOr` / `PowerOfPowerKeepsItsGrouping` added on every provider, `BinaryAndLeftOfXor` / `BinaryAndRightOfXor` on Access.
  - Critic round 10 (weak), answered: E-40 fixes the right-nested power E-37 had regressed on LibRed (TO-26); `BinaryXorUnderOr`'s gate widened to `AllSqlServer` (no `|` / `^` arm, same SQL as SqlCe); `BAND` beside `BXOR` pinned (TO-27); bool XOR, Jet / YDB / Sybase and the `virtual` `Power` recorded in P10; P7 corrected (`BXOR` at 38, row 279).
  - **The approval of record is void for E-36..E-40 and must be re-earned** (critic round 10, then the user).
  - re-derives: P2 SC-3 (native Access also gains `BXOR` for C# XOR); P6 E-16 (superseded by E-36/E-37), E-34 (LibRed now uses it), E-36..E-39; P7 (E-34 operator table gains `BXOR` at 38 on every flavour and covers LibRed; row 279's LibRed-override note); P8 TO-23..TO-25; P9 G-01 (A-12 line) / G-02 (CI baselines after the push); P10 (SUG002 line); P12 round 10.
  - conventions: `testing.md` → *Test layout*, *Gating an assertion failure* (single-assertion criterion, `typeOnlyShouldlyGates` sweep category, NUnit `AreEqual` gates pin `ErrorMessage` only); new tests follow `BinaryOr`'s `AreEqual` form.

## P12 Critique

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

weak — round 5 (delta A-7), `plan-critic` on **fable**, 2026-11-10, dispatched jointly with #5956's A-22. Objections and
responses:

- P6 had no edit-point for `DistinctOrderByNullableBooleanSubQueryColumn`, whose pinned flip expectation E-26 changes
  on LibRed → E-29.
- E-27 underspecified on materialization → the projection is already `bool?` (`LinqDataTypes.cs:96`); E-27 says so.
- lead: the negated-key probe covered one shape → three more measured (A-7 bullet); the alias shape is rejected by
  LibRed and never emitted.
- TO-18's regression set was three tests while E-26 changes every nullable key under DISTINCT on LibRed → widened to
  the whole `DistinctTests` + `OrderByTests` set, direct and remote, with the native control.
- Stale line citations → corrected to this tree (`:571`, `:576-586`).

Critic checked and found sound: E-26 leaves native output unchanged by construction; window items never read the
DISTINCT state; the LibRed visitor wiring (`AccessDataProvider.cs:115`, `AccessLibRedSqlOptimizer.cs:15`); E-28 matches
the `IsTickArithmeticSupported` PublicAPI entries. Not checked by it: engine behaviour. No round 6: every objection
accepted and answered, none disputed.

refuted — round 6 (delta A-8 and the first P9 record), `plan-critic` on **fable**, 2026-11-15. Objections and responses:

- `02eb16f04` changes native SQL on every Access flavour (`MOD` precedence, shared visitor `:537`, both directions of
  the paren change) with no `E-n` / `A-n` / P7 / `TO-n`, against P3, SC-3 and A-7's "native byte-identical" → A-9
  (user: keep on this PR), E-30, P3 and SC-3 exceptions, P7 row, TO-19; G-02 records the native `Round16` delta.
- A-8's class was narrower than its own finding: `3aeb1f887` and `12f449283` (2026-11-09) were also un-amended →
  A-8 widened to both, sites listed.
- G-08's reconcile is file-keyed and could not see the unplanned hunk → G-08 says so and cites the hunk enumeration.
- G-01's sweep counts covered single-line attributes only, missing the seven A-8 sites → continuation lines tallied
  separately (103: 91 `AllNativeAccess`, 8 `AllAccessLibRed`, 4 re-wrapped).
- G-01's "every one widens" was false for `Issue4336Tests.cs:21` → excepted in G-01; its alpha.4 `Details` stamp left
  open for the review walk.
- TO-18 dropped the gRPC re-run qualifier → copied into G-01.
- G-05 "pass" with Azure `build` pending → `blocked`.
- Stale line refs in A-7 → current refs added beside them.

Critic found sound: the A-7 P7 row (5 hits, one subclass, window items do not read the flag); G-03's line refs; G-07;
A-8's account of `6a83b4f37` and `cd009d488` (7 pure token swaps). Searched: the 18 commits' `--stat`, both A-8
commits' full diffs, the Access `Source` diff, `Precedence.cs`, plan greps for every term above, the sweep JSON, the
continuation-line tally. Not checked by it: CI state, the author's local runs, native baselines (now read, G-02).
Revision goes to round 7.

weak — round 7 (revision of round 6: A-8 widened, A-9, E-30, TO-19, P9), `plan-critic` on **fable**, 2026-11-15. Every
round-6 objection answered; E-30 not disproved. Objections and responses:

- open — a right-nested `a % (b % c)` renders `a MOD b MOD c` at both 59 and 71 (`Wrap`, `BasicSqlBuilder.cs:4709-4718`,
  read and confirmed by the author); pre-existing, not fixed by E-30; TO-19 has no arm for it. Carried to the round-1
  review walk (fix here or track), and A-9's "closes #6243" scoped down. lead, unprobed: Access's left-associativity of
  `MOD`.
- open — the "loses redundant parentheses" direction is witnessed for `+` only (`Round16`); `a - b % c` is value-equal
  by reasoning. Carried to the review walk as a missing TO-19 arm.
- P7 (A-9) claimed LibRed does not override `ConvertSqlBinaryExpression` → corrected (`:50-57`, delegates `%`).
- P7 (A-9) omitted LibRed's tick-lowering consumer (`ShiftOverADateColumnMatchesClr`) → added.
- TO-10 / TO-17 named in `re-derives:` but unchanged → both texts updated.
- "this PR closes #6243" not reflected in the PR and #6243's scope unread → A-9 scoped to "recorded on".
- G-08's hunk enumeration path was Access-only → widened to `Source/LinqToDB`.

Critic found sound: `*` / `/` mixes render identically at 59 and 71 (walked every position through `Wrap`), so A-9's
unprobed claim holds by construction; at `Additive + 1` TO-19's second assert reddens, so its two asserts pin the
`Subtraction` bound; no other `MOD` producer; native baselines differ from `master` only in `Round16` and the new
test on all four configs; SQL Server 2017–2025 legs have landed with no `Round*` delta, supporting G-02's attribution
of the 2005–2016 residue. A-8's widened account matches the commits (the PR body's "25 lines" vs 24 measured).
Not checked: CI runs, the author's red→green runs, engine behaviour, #6243, TO-19's remote leg. No round 8: the cap
is one revision round; the two open items go to the review.

weak — round 8 (delta A-10, review round 1 walk), `plan-critic` on **fable**, 2026-11-15. The diff matched A-10's
records (E-30 one line, E-31 nested class + factory, E-32 five PublicAPI lines, E-33 test + re-stamp + two layout
touches); no edit-point refuted. Objections and responses:

- E-31's run set did not cover the shapes it opens (the `AllowDistinct` gate is not grouped-only;
  `DistinctWithAssociationInSubquery` is a correlated scalar sub-query) → the un-run fixtures were run on LibRed,
  498/0/6; P7 row for E-31 added with the census; TO-21 scoped to grouped and correlated sub-query shapes.
- TO-19 arm 5 has no observed red and cannot pin LibRed's `MOD`-vs-`*` order; arm 3 cannot go red → both relabelled
  controls in TO-19.
- Stale statements contradicting E-30 / D-4 (A-9's failure-mode line, the P7 SqlCe row, D-4's "in E-7") → marked
  superseded and named in A-10's `re-derives:`; churn fixtures listed; `ConvertTests` run on Ace.OleDb, 132/0/2.
- lead: TO-20 unrun beyond three providers; SqlCe / Sybase / SQL Server < 2016 have 32-bit `DATEDIFF` → run on SqlCe:
  red, 347 vs 346 — the test's `.345` ms is not a 1/300 s step, so the stored read-back and the server's count
  disagreed by rounding. Fixed in the test (multiples of 10 ms), green on SqlCe, LibRed, Ace.OleDb, SQLite.MS. Sybase
  and SQL Server < 2016 are left to CI.
- nit: two line cites for one `DateTimeOffsetNowUtc` branch → reconciled in P10.

Critic found sound: `Precedence.Multiplicative` against Access's grammar (every equal-precedence operand wrapped on
both sides, the unary-minus path stays grouped, no `\` or native `^` producer); D-4's amendment evidence
(`SkipTake5`, `SkipCount` baselines); the P10 UtcNow line. Not checked by it: CI, any run, LibRed's real `MOD` / `*`
precedence. No round 9: every objection answered by a run or a text fix, none disputed.
(Superseded: round 8's "no `\` or native `^` producer" contradicted E-18 and hid MIN005, review round 2; see A-11.)

weak — round 9 (delta A-11, review round 2 walk), `plan-critic` on **fable**, 2026-11-16. E-35 behaviour-identical
(old overload delegates with `Additive`, concat guard kept, `IDE0060` suppression on the overload that ignores
`factory`, `PublicAPI.Unshipped.txt` line present; only other caller `MemberTranslatorTests.cs:35`); the churn list
matches the `Access.Ace.OleDb` capture (7 `^` baselines, `Round9` / `Round12` move, `Pow*` do not). Objections and
responses:

- The `+ 1` and the "before negation" clause had no obligation: a `Precedence.Unary` mutant kept all four arms green
  → `Math.Pow(-p.ID, 2)` and `Math.Pow(100 - p.ID, 2)` arms added; the negation arm is red at Additive and at the
  plain-`Unary` mutant, the difference arm red at Additive (G-01, A-11).
- lead: a negative literal operand stays bare → probed: `Math.Pow(-2, ID)` renders `-2 ^ [ID]`, Access returns
  `(-2) ^ ID`; refuted, no change; A-11's "every arithmetic operand" narrowed to operator-node operands.
- `re-derives:` named edits the plan lacked (P7 E-34 row, SC-3, TO-10 / TO-17, the factory-form G-01 record) →
  all landed; P7 carries the operator table the critic built.
- "a `^` operand of unary minus stays bare" unprobed → `-Math.Pow(p.ID, 2)` arm added, right at every precedence.
- Churn wording missed `/ (10 ^ 1)` → added.
- Two arms at the end of `ModuloOperandKeepsItsGrouping` would mask each other → every red measured as a separate
  scratch test; the committed tests keep the file's one-test-many-arms form.
- lead: exact `double` equality on every provider under bare `[DataSources]` → recorded as left to CI in A-11.

Critic found sound: one precedence above `Unary` handles every operator-node position in both directions; the `-1 *`
path becomes a 90 unary before rendering; casts are elided, so operands reach `^` bare; no `\` producer; CLR XOR is
untouched. Not checked by it: any run (read-only round), remote serialization of the precedence (green remote run
since, G-01). No round 10: every objection answered by a run or a text fix, none disputed.

weak — round 10 (delta A-12, review round 3 walk), `plan-critic` on **fable**, 2026-11-16. Found sound by producer
census: two `^` producers at distinct precedences (CLR XOR at `Bitwise`, the power at `Unary + 1`), both preserved
through every rebuild and the remote serializer; a converted node is `BXOR`, so a second convert pass cannot re-match;
`Bitwise - 2` pinned by the mutation that reddens both new tests on ACE and LibRed. Objections and responses:

- `BinaryXorUnderOr`'s SqlCe-only gate is narrower than its mechanism; SQL Server has no `|` / `^` arm → widened to
  `AllSqlServer`; Sybase / YDB left to CI (P10).
- E-37 extends A-11's right-nested power limit to LibRed, a change against the PR head → probed: left-nested correct,
  right-nested red on ACE and LibRed (64 for 512); fixed by E-40 for every flavour, TO-26 (mutation red on three
  Access providers, SQLite control green).
- `BAND` beside `BXOR` had no obligation → TO-27, both sides green, Access-only.
- lead: bool XOR reaches `BXOR` with bare comparison operands → probed: comparisons arrive parenthesized; P10 line.
- lead: Jet legs unmeasured → P10 line, CI verdict.
- `re-derives:` claimed a P7 edit that was not made; "37" wrong (38); row 279 stale → all corrected.
- Minor: `Power` stays `virtual` with no override → P10 line.

No round 11: every objection answered by a run or a text fix, none disputed; E-40 was written in answer to this
round and carries its own red (TO-26).
