# Work plan: fix-deterministic-baseline-capture — make SQL baselines agree between the release and PR pipelines

**Tier:** L  ·  **Status:** approved  ·  **Approved-at:** 2026-09-12 (user, post-critic, on the four-edit-point surface below)  ·  **Branch:** fix/deterministic-baseline-capture
**Schema:** `.claude/docs/work-plan.md`  ·  **Gates:** `.claude/docs/definition-of-done.md`

## P1 Problem

The first ordinary PR after every release carries a baselines diff it did not cause. After 6.5.0 that was [linq2db.baselines#2118](https://github.com/linq2db/linq2db.baselines/pull/2118) — 21 files, none related to [#5912](https://github.com/linq2db/linq2db/pull/5912). `baselines/pr_5913`, an unrelated later PR, reproduces 20 of the same 21 with byte-identical content, so it is systematic, not flaky.

A baseline's path carries the **provider and nothing else** — no TFM, no OS, no CI host (`Tests/Base/BaselinesWriter.cs:35-42`) — and `Build/CI/push-baselines.ps1:110` resolves the cross-leg race with `git rebase -X theirs`, so the last leg to push wins. The release pipeline (`Build/Azure/pipelines/default.yml:46`, `full_run: true`) runs strictly more legs than a PR pipeline (`testing.yml:37`, `full_run: false`), and `/release-publish` resets baselines master to the anchor, so the whole corpus is release-pipeline output.

**M1 — a release-only netfx leg overwrites the net10 one.** 1 file. `test-matrix.yml:349-363` gives `m_SqlServer2022_2025` `win_efcore_only: true` plus a Linux leg, so `test-jobs.yml:143-150` forces `net80/90/100: false` on its Windows leg — netfx-only — and `test-workflow-windows.yml:238` runs its main suite only when `full_run`. Measured via the installed ref packs:

| runtime | `(SqlDbType)35` | `(SqlDbType)36` |
|---|---|---|
| .NET Framework 4.8 | *no name → `"35"`* | *no name* |
| .NET 8 | absent | absent |
| .NET 9 | `Json` | absent |
| .NET 10 | `Json` | `Vector` |

```diff
-DECLARE @Column 35(3) -- String      netfx, release run only
+DECLARE @Column Json(3) -- String    net10, every run
```

**M2 — captured SQL encodes live database state.** 19 files. Reproduced end-to-end for DB2: a first suite pass emits `TABSCHEMA IN ('SYSIBM','SYSCAT',…)` (13 schemas); `TableOptionsTests.DB2TableOptionsTest` then runs `CREATE GLOBAL TEMPORARY TABLE SESSION."TestTable"` — a *catalogued* CGTT, where a `DECLARE GLOBAL TEMPORARY TABLE` is probed-and-negative; a second pass emits 14 schemas including `SESSION` and is **byte-identical to the release baseline**, differing from the PR-run baseline. The 18 PostgreSQL files are the same *class* — `PostgreSQLSchemaProvider.cs:806` `GetProcedures` has no `ORDER BY` in either version branch, so probe order is whatever the server returns — but see U-7: what perturbed it on CI is **not** established, and the "extra TFM passes" story does not by itself explain the PG evidence.

**M3 — the baseline capture loses an append.** 1 file. `Issue1174Tests.TestConcurrentSelect` recorded the statement twice in the release run and once in the PR run (14 vs 7 lines). The two captured blocks are **byte-identical**, so order is irrelevant; only the *count* varies. `BaselinesManager.LogQuery` (`Tests/Base/BaselinesManager.cs:9-24`) lazily creates a `StringBuilder` and appends with no lock, while `TestBase.cs:74` calls it from the trace sink on whatever thread ran the query. Because `CreateLocalTable` is `DisableBaseline`-wrapped (`Tests/Base/TestUtils.cs:281,299,326`), the two concurrent `FirstAsync` traces are the *first* appends of the test, so both threads see `null` and each creates a builder — `ctx.Set` is last-writer-wins and one builder is dropped whole, which is why a complete 7-line block disappears rather than a line tearing.

## P2 Success criteria

- SC-1 On a runtime whose BCL `SqlDbType` lacks member 35, a JSON parameter prints `Json`, not `35` — netfx/net8 and net10 emit identical SQL for `SqlServerTypeTests.TestJSONType`. → TO-1
- SC-2 `PostgreSQLSchemaProvider.GetProcedures` returns a total, server-order-independent sequence, so probe order cannot vary whatever the catalog does. → TO-2
- SC-3 `DB2Tests.Issue2763Test`'s captured SQL is identical on a first and a second suite pass against one container — the comparison that currently fails. → TO-3
- SC-4 `Issue1174Tests.TestConcurrentSelect` captures **both** statements on every run, so its baseline is stable and its regression coverage is retained. → TO-4
- SC-5 Two concurrent `LogQuery` callers in one test cannot lose an append or a whole builder. → TO-5

## P3 Constraints & anti-goals (M/L)

- **No CI change.** The user chose determinism-at-source over a CI kill-switch. `Build/Azure/**` and `Build/CI/**` are out of scope.
- **No public API outside `LinqToDB.Internal.*`.**
- **Do not change emitted SQL for providers this does not target.** E-1 is guarded on the SQL Server adapter; E-2 is PostgreSQL-only (zero subclasses — P7).
- **Do not widen into the unsorted-schema-filter defect** (`DB2LUWSchemaProvider.cs:578/585`, `SchemaProviderBase.BuildSchemaFilter:77`). Separable → own issue (P10).
- **Accept one-time baseline churn.** E-2 rewrites 332 PostgreSQL baseline files; E-3 rewrites one DB2 file. That is the cost of the fix.

## P4 Unknowns (M/L)

- U-1 Does another provider share M1's shape? — resolved-by scout: no. The only two synthetic casts tree-wide are `SqlServerProviderAdapter.cs:174,178`; every other provider's type enum is linq2db-declared and TFM-invariant. `SqlCeSqlBuilder.cs:186` is the only other BCL-`SqlDbType` consumer and receives no synthetic value — latent only.
- U-2 Is the missing `ORDER BY` an omission or house style? — resolved-by scout: a split. SQL Server, Oracle, DB2 LUW and Firebird order their procedure list; PostgreSQL, MySQL, DB2 z/OS, SAP HANA, Sybase and Access do not. E-2 follows the existing precedent.
- U-3 Does unordered `GetProcedures` affect anything beyond baselines? — resolved-by scout, narrowed: the CLI/scaffold path already sorts (`DataModelLoader.cs:170-171`), so only the legacy/T4 path (`LegacySchemaProvider.cs:102,735`) is exposed. My initial "stabilises scaffolding output" was too broad.
- U-4 Will the committed generated model files change? — resolved-by scout, deferred: 9 files under `Tests/Tests.T4/` reference `TestTableFunction`; the 4 `Cli/*` go through the sort and should not move, the 5 `Databases/*`/`Default/*` may. Regenerated manually in the release test-matrix → P10.
- U-5 Would locking `LogQuery` alone make `TestConcurrentSelect` deterministic? — **resolved-by critic, against my initial answer: yes it would.** I claimed order made suppression necessary; the critic read the actual artifact and the two captured blocks are byte-identical, so order cannot flip it. The only variance is count, which the lock closes. The `DisableBaseline` wrap I had planned is therefore dropped.
- U-6 Freeze or suppress? — resolved-by corpus doctrine (`.claude/docs/bug-investigation.md:433-435`): freeze the source; reach for `DisableBaseline` only when the value must be runtime. Both remaining cases are freezable, so neither gets a suppression.
- U-7 What perturbed PostgreSQL's probe order on CI? — **resolved-by critic as unexplained, and recorded as such.** No in-tree statement mutates `pg_proc` for these functions (searched `(CREATE OR REPLACE|ALTER|GRANT|DROP).*TestTableFunction` tree-wide: only `Data/Create Scripts/PostgreSQL.sql:7,575,583,587`), and the swap is confined to PostgreSQL **17 and 18** while 13–19 all run in one job with identical TFM passes and no test gated to exactly {17,18}. E-2 is justified as *determinism by construction*, not as a fix for a diagnosed trigger. TO-2 is labelled accordingly.
- U-8 Is `GetProcedureParameters` a second ordering source? — resolved-by own search: no. Its two queries (`PostgreSQLSchemaProvider.cs:947,975`) are unordered, but parameters are keyed by `ProcedureID` and re-sorted downstream by `orderby pr.Ordinal` (`SchemaProviderBase.cs:289`); the result parameter is Ordinal 0 and PostgreSQL parameters start at 1, so no ties. Only the static query text reaches the baseline.
- U-9 Which DB2 schemas actually return tables? — **resolved-by probe** against the live container: `SYSCAT`(6)=200, `SYSIBMADM`(9)=78, `SYSIBM`(6)=37, `DB2INST1`(8)=18, `SYSSTAT`(7)=14, `SYSTOOLS`(8)=1; `SYSIBMINTERNAL`(14)=**0** and `SYSPUBLIC`(9)=**0**. The list I had proposed in D-3 would have failed the test's own assertion.

## P5 Decisions (M/L; rejected alternatives mandatory at L)

### D-1 — Fix M1 in the SQL Server builder, not by changing the cast

- **chosen:** add a `JsonDbType` branch to `SqlServerSqlBuilder.GetProviderTypeName` beside the Vector branch at `:431`, guarded identically on `Adapter.SqlJsonType is not null`, returning `"Json"`.
- **rejected:** name the BCL member — impossible on net462/netstandard2.0/net8.0, which is why the cast exists.
- **rejected:** handle unknown enum values in `BasicSqlBuilder.PrintParameterType` — 11 other overrides render linq2db-declared enums that are already safe; far wider blast radius for no gain.
- **why this:** the Vector branch two lines above already answers this exact question in this exact file.
- **failure mode of the choice:** the `SqlJsonType is not null` guard is load-bearing — when it *is* null `JsonDbType` returns `SqlDbType.NVarChar`, so an unguarded equality prints `Json` for every ordinary `NVarChar` parameter on every pre-2025 SQL Server. TO-1 must cover that arm.

### D-2 — Order `GetProcedures` in SQL, in both version branches, on a name key

- **chosen:** `ORDER BY r.SPECIFIC_SCHEMA, r.ROUTINE_NAME, r.SPECIFIC_NAME` appended to both the `< v11` (~:846-862) and `11+` (~:898-913) queries.
- **rejected:** `ORDER BY SPECIFIC_CATALOG, SPECIFIC_SCHEMA, SPECIFIC_NAME` (my first choice) — total, but `SPECIFIC_NAME` is `proname_oid`, so under a glibc collation that ignores `_` at primary strength the tie between `TestTableFunction` and `TestTableFunction1` is decided by **oid digits**. Deterministic per container but perturbed by any create-script change that shifts oids — which is precisely the class of instability being removed. Critic's refinement, accepted.
- **rejected:** sort client-side in `SchemaProviderBase` — changes all providers including the six that deliberately do not order, and lands in shared code the constraints exclude.
- **why this:** `ROUTINE_NAME` is the semantic key; `SPECIFIC_NAME` remains as the total-order tie-break for real overloads (`Data/Create Scripts/PostgreSQL.sql:701,709,717`).
- **failure mode of the choice:** if only one branch is ordered the captured query text diverges across the 13 PostgreSQL configurations — visible and ugly rather than silent, but both branches go in one edit.

### D-3 — Freeze the DB2 schema list to a measured pair

- **chosen:** `Issue2763Test` passes a fixed `["SYSCAT", "SYSSTAT"]` instead of the live `SYSCAT.SCHEMATA` result. Both are core DB2 catalog schemas present in every DB2 database, both were **measured** to return tables (200 and 14), and their name lengths differ (6 vs 7), which is what makes DB2 pad `TABSCHEMA` — the actual subject of issue 2763.
- **rejected:** `SYSCAT`/`SYSIBMINTERNAL`/`SYSPUBLIC` — my first proposal, refuted by probe: the latter two return **zero** tables, so the test's `:1014` assertion would have had tables from one schema only.
- **rejected:** `DisableBaseline` — the value is freezable, so doctrine says freeze; suppressing also loses the trimming regression coverage the baseline provides.
- **rejected:** sort the live list — fixes order but not membership; `SESSION` still comes and goes.
- **why this:** `PostgreSQLSchemaProviderTests.cs:472-478` is a near-verbatim precedent, comment included.
- **failure mode of the choice:** with a constant array the `Assert.Inconclusive` length-diversity guard at `:996-997` becomes dead code. It is **removed**, and replaced by an assertion that both schemas returned tables — the real precondition, which the constant list makes checkable rather than hopeful.

### D-4 — Fix the concurrent capture rather than suppress it

- **chosen:** close the race in `LogQuery` and keep `TestConcurrentSelect`'s baseline.
- **rejected:** wrap it in `DisableBaseline("Multi-threading")` — my original plan, and what 13 sibling tests do. Dropped because the critic showed the premise was false: the two captured blocks are byte-identical, so the lock alone yields a deterministic baseline, and suppression would discard regression coverage for no benefit.
- **why this:** it fixes the defect instead of hiding it, and matches the same doctrine as D-3.
- **failure mode of the choice:** if the two statements ever stop being byte-identical (a provider where `FirstAsync` renders differently per connection), order *would* start mattering and this test would flake again. TO-4 asserts the count, so that regression surfaces as a failure rather than as silent churn.

### D-5 — Patch `LogQuery` only; do not unify with the trace builder

- **chosen:** the lock goes in `BaselinesManager.LogQuery`.
- **rejected:** route both the BASELINE and TRACE builders through one `GetOrCreate` helper on `CustomTestContext` — `TestBase.cs:80-89` `GetTraceBuilder` has the *same* unguarded get-or-create and locks only its append (`:94`), so the twin defect is real.
- **why this:** the trace builder feeds diagnostic output, not assertions; the baseline builder feeds `GetCurrentBaselines()` and ~80 assertion sites. Only the latter has an observed failure. Unifying touches a third file for a defect nothing has attributed a failure to.
- **failure mode of the choice:** a reader who notices the twin will reasonably ask why only one was fixed. P10 records it with the file:line so the answer is on the page, and it rides the follow-up issue with the reader-side race.

## P6 Edit-points

- E-1 `Source/LinqToDB/Internal/DataProvider/SqlServer/SqlServerSqlBuilder.cs:GetProviderTypeName` — add a `JsonDbType` branch guarded on `Adapter.SqlJsonType is not null`, returning `"Json"`, beside the Vector branch at `:431`.
- E-2 `Source/LinqToDB/Internal/DataProvider/PostgreSQL/PostgreSQLSchemaProvider.cs:GetProcedures` — append `ORDER BY r.SPECIFIC_SCHEMA, r.ROUTINE_NAME, r.SPECIFIC_NAME` to **both** version branches.
- E-3 `Tests/Linq/DataProvider/DB2Tests.cs:Issue2763Test` — replace the live `SYSCAT.SCHEMATA` result with `["SYSCAT", "SYSSTAT"]`; drop the now-dead `Assert.Inconclusive` guard and assert instead that both schemas contributed tables.
- E-4 `Tests/Base/BaselinesManager.cs:LogQuery` — take a static lock across the get-or-create **and** the append, closing both the lost-builder and torn-append races.
- E-5 `Tests/Linq/**` — add the N-thread `LogQuery` hammer that discharges TO-5. Added by amendment A-1; see P11.
- E-6 `Tests/Linq/DataProvider/Types/SqlServerTypeTests.cs:TestJSONParameterTypeName` — assert the declared parameter type name for both adapter arms, giving TO-1 a committed carrier. Added by amendment A-2; see P11.

## P7 Impact map (M/L)

- `Source/LinqToDB/Internal/DataProvider/SqlServer/SqlServerProviderAdapter.cs:174,178` — the only two synthetic enum casts tree-wide; searched `\([A-Za-z_][A-Za-z0-9_.]*(DbType|Type)\)\s*-?\d+` over `Source/` — covered by E-1
- `Source/LinqToDB/Internal/DataProvider/**/*SqlBuilder.cs` — 13 `GetProviderTypeName` overrides; searched `GetProviderTypeName` tree-wide, cross-checked against `PublicAPI.Shipped.txt`. 11 render linq2db-declared mirror enums; `SqlCeSqlBuilder.cs:186` is the only other BCL-`SqlDbType` consumer and gets no synthetic value — out-of-scope (latent)
- `Source/LinqToDB/Internal/SqlProvider/BasicSqlBuilder.cs:4897` — the single call site of `GetProviderTypeName`; searched `GetProviderTypeName` — covered by E-1
- `Source/LinqToDB/Data/TraceInfo.cs:145` — the production route by which `"35"` reaches trace output and baselines; searched `PrintParameters` — covered by E-1 (confirms E-1 sits on the only path)
- `Source/LinqToDB/Internal/DataProvider/SqlServer/SqlServerDataProvider.cs:624` — `DataType.Json` selected only when `Version >= v2025`; searched `JsonDbType` — covered by E-1's guard
- `Source/LinqToDB/Internal/SchemaProvider/SchemaProviderBase.cs:256-308,322-334` — preserves `GetProcedures` order into `DatabaseSchema.Procedures` and appends table-function schemas into `Tables` in that order; searched `GetProcedures|OrderBy|\.Sort\(|GroupBy` in-file — covered by E-2
- `Source/LinqToDB/Internal/DataProvider/PostgreSQL/PostgreSQLSchemaProvider.cs:947,975` — `GetProcedureParameters`' two unordered queries; searched `SPECIFIC_NAME` in-file. Parameters are re-sorted downstream (`SchemaProviderBase.cs:289`) and only static query text reaches the baseline — out-of-scope (U-8)
- `Source/LinqToDB.Scaffold/Scaffold/DataModel/DataModelLoader.cs:170-171` — CLI/scaffold sorts procedures itself; searched `OrderBy.*SqlObjectNameComparer` — out-of-scope
- `Source/LinqToDB.Scaffold/Schema/LegacySchemaProvider.cs:102,735` — legacy/T4 path preserves provider order, so E-2 does change it; searched `foreach.*schema\.Procedures` — deferred: regenerated manually in the release test-matrix, which this branch cannot run (P10)
- `Source/LinqToDB/Internal/DataProvider/PostgreSQL/PostgreSQLSchemaProvider.cs:23,35` + `PostgreSQLDataProvider.cs:280` — derives from `SchemaProviderBase`, **zero** subclasses; searched `:\s*PostgreSQLSchemaProvider` over `Source Tests Build` — covered by E-2 (containment evidence: E-2 cannot reach another provider)
- `linq2db.baselines origin/master` PostgreSQL dirs — 332 files carry the captured `GetProcedures` text and the 4 probes; `git grep -l -F ROUTINE_CATALOG` and `git grep -l -E 'SELECT \* FROM testdata\.'` return identical sets across 13 dirs, zero outside — covered by E-2
- `Tests/Tests.T4/{Cli,Databases,Default}/**` — 9 generated model files reference `TestTableFunction`; `git grep -c "TestTableFunction" -- Tests/Tests.T4` — deferred: regenerated manually against live databases in the release test-matrix (U-4, P10)
- `Tests/Base/TestBase.cs:74` — trace sink calling `LogQuery` on the query's thread; searched `LogQuery` tree-wide: 1 off-thread caller here, 1 at `Tests/EntityFrameworkCore/Logging/TestLogger.cs:83-97`, ~25 on-test-thread callers — covered by E-4
- `Tests/Base/TestBase.cs:80-89,94` — `GetTraceBuilder`'s identical unguarded get-or-create, append-only lock; searched `GetTraceBuilder` — out-of-scope by D-5, recorded in P10
- `Tests/Base/CustomTestContext.cs:23-43` — static `ConcurrentDictionary` keyed by NUnit test id; the map is thread-safe, the stored builder is not — covered by E-4
- `Tests/Base/TestUtils.cs:281,299,326` — `CreateLocalTable` is `DisableBaseline`-wrapped, which is why the two concurrent traces are the test's *first* appends and both see a null builder; searched `DisableBaseline` in-file — explains M3's reachability, covered by E-4
- `Tests/Base/TestBase.Utils.cs:200-203` — `GetCurrentBaselines()` reads the live builder unsynchronised, feeding ~80 assertion sites; searched `GetCurrentBaselines` — deferred: E-4 fixes the writer side only, and locking the reader touches ~80 call sites' timing for a defect nothing has attributed a failure to (P10)
- `Tests/Linq/**` concurrent-query tests — 13 already `DisableBaseline`-wrapped; searched `Task\.WhenAll|Parallel\.|Task\.Run|new Thread\(` plus the deferred-await shape — out-of-scope (E-4 fixes the mechanism for all of them)
- `Source/LinqToDB/Internal/DataProvider/DB2/DB2LUWSchemaProvider.cs:578,585`, `SchemaProviderBase.cs:77` — emit `IN (...)` from an unsorted `HashSet` while `PostgreSQLSchemaProvider.cs:272,279` sorts; searched `OrderBy|Sort\(` per file — out-of-scope (own issue, P10). Note SC-3 relies on `HashSet` insertion-order enumeration, the same implementation detail the current code already depends on.
- `Tests/Linq/SchemaProvider/SchemaProviderTests.cs:264` — same live-list-into-SQL shape, already carries a DB2-conditional `DisableBaseline` with a TODO; searched `IncludedSchemas|ExcludedSchemas` over `Tests/` — out-of-scope (already mitigated)

## P8 Test obligations (M/L)

- TO-1 `SqlServerTypeTests.TestJSONType` against the local `sql2025` container, run **on net8.0** — the TFM where the unfixed code prints `35`. On net10.0 the unfixed code already prints `Json`, so a net10-only run is green-on-unfixed and proves nothing. **Symmetry guard on the unchanged path:** a pre-2025 SQL Server parameter still prints `NVarChar`, covering D-1's failure mode where `SqlJsonType is null` makes `JsonDbType == NVarChar`. — proof: red→green on net8.0, plus a control on the `SqlJsonType is null` arm
- TO-2 Two consecutive `PostgreSQLSchemaProviderTests` runs emit identical probe order, and the order matches the `ORDER BY` key. This is **characterization**, not red→green: U-7 records that no in-tree trigger for the CI reordering was found, so a red cannot be manufactured honestly. What it proves is that the output is now fixed by construction. — proof: characterization (stated plainly: it does not reproduce the original flip)
- TO-3 Two consecutive `DB2Tests.Issue2763Test` captures against one container are byte-identical, with `SESSION` creation in between. — proof: red→green (red already observed: run A vs run B differ by `'SESSION', ` × 7, and run B is byte-identical to the release baseline)
- TO-4 `TestConcurrentSelect` captures exactly 2 statements on every one of N consecutive runs. — proof: red→green on the real path (the release-vs-PR artifacts are 14 vs 7 lines, so the red exists in the wild; N runs against ClickHouse.MySql should reproduce a 1-statement capture pre-fix)
- TO-5 Concurrent `LogQuery` calls lose neither an append nor a builder, under a direct N-thread hammer that does not depend on provider timing. — proof: red→green

## P9 Verification gates

Derived from P6 via `work-plan.ps1 -Action gates`.

- G-01: **pass** — every TO-n discharged at its declared proof mode, 2026-09-12, against the worktree build.
  - **TO-1 red→green on net8.0** (`sql2025` container, `--provider SqlServer.2025.MS`). Red, with E-1 stashed: **28** `DECLARE @x 35`, **0** `Json`. Green: **0** `35`, **28** `Json`. 56 differing lines = 28+28, the same `+28/-28` shape [linq2db.baselines#2118](https://github.com/linq2db/linq2db.baselines/pull/2118) carries. Run on net10.0 would have been green-on-unfixed, which is why the TFM is pinned.
  - **TO-2 characterization** (`pgsql17`). Two runs byte-identical; probe order is now the `ORDER BY` key — `GetParentByID`, `TestTableFunction`, `TestTableFunction1`, `TestTableFunctionSchema`. As U-7 records, this does **not** reproduce the original CI flip; it shows the output is fixed by construction.
  - **TO-3 red→green** (`db2`). Red observed pre-fix earlier the same day: two passes over one container differed by `'SESSION', ` × 7, and pass 2 was byte-identical to the release baseline. Green: two passes byte-identical (1862 bytes), captured filter exactly `IN ('SYSCAT', 'SYSSTAT')`, **zero** occurrences of any other schema — including `SESSION`, which is still present in that database. `Is.EquivalentTo` also confirms both frozen schemas contributed tables, which is what U-9's probe was for.
  - **TO-4 red→green** (`clickhouse`). Red is the in-the-wild artifact (release 14 lines vs PR-run 7). Green: 5/5 consecutive runs captured exactly 2 statements. The local red was **not** reproduced — the race is timing-dependent, and TO-5 reproduces the same mechanism deterministically instead.
  - **TO-5 red→green**, provider-free. Red 3/3 with E-4 stashed: `ArgumentException` from `StringBuilder.AppendWithExpansion`, stack at `BaselinesManager.cs:22` — the unsynchronised `AppendLine` corrupting the builder. Green 1/1.
- G-02: **blocked** — needs the CI baselines PR, which only exists once this branch is pushed. Locally verified the direction for all four affected files; the 332-file PostgreSQL regeneration cannot be produced on one machine. Unverified until then: that nothing outside the 13 PostgreSQL dirs and the one DB2 file moves. Expected to move: 332 PostgreSQL files (query text always; probe order only where the current order already differs from the sorted one — for PG 17/18 the current order *is* the sorted order, so those 18 change in query text only), and the one DB2 file (E-3 changes the captured `IN (...)` list by design). `SqlServer.2025.MS/TestJSONType` will **not** move on a PR run, because the Linux net10 leg already prints `Json` — its fix is only visible on a `full_run`. `ClickHouse.MySql/TestConcurrentSelect` should settle at 2 statements.
- G-05: **pass, after an initial miss that CI caught.** `dotnet build Source/LinqToDB/LinqToDB.csproj -c Release -f netstandard2.0` → exit 0, and `-f net462` → exit 0. Release, so analyzers and banned-API checks ran. Load-bearing here because E-1 exists precisely for the TFMs where the BCL enum lacks member 35.
  **The gate as first run was scoped too narrowly and the plan wrote it that way.** It named only `Source/LinqToDB`, so the *test* project was built on net10.0 and net8.0 only — and `Tests/Linq` also targets **net462**, where `string.Split(char, StringSplitOptions)` does not exist. E-5 used that overload and the Release solution build failed on both CIs with `CS1503` (GitHub `Build and pack`, Azure build 23601 — one error, same cause, nothing else). Fixed with the `char[]` overload and re-verified by `dotnet build Tests/Linq/Tests.csproj -c Debug -f net462` → exit 0, which is the build that should have run before the push. The TFM-availability rule applies to `Tests/` as much as to `Source/`; a future plan touching a test project should say so in this gate.
- G-06: **pass** — whole-branch diff is 4 modified files, **+23/-10**, plus one added fixture. `git diff` reviewed line by line: two one-line SQL additions at the existing `WHERE` indentation, one two-line builder branch beside its Vector sibling, one re-indented block under a new `lock`, and the DB2 test's substitution. No reformatting, no renames, no touched neighbours.
- G-07: **pass** — `git status` in the worktree shows nothing under `Tests/Tests.Playground/`. The two DB2 probes this session wrote there were in the **primary clone** and are both reverted; that tree is back to the three modifications that predate the session. The worktree's `UserDataProviders.json` is seeded for baseline capture but is gitignored (`.gitignore:17`), confirmed with `git check-ignore -v`.
- G-08: **pass** — `SchemaProviderBase.cs:256-308,322-334` consumes `GetProcedures` order-preservingly, which is the shared-engine surface E-2 moves. Proven by TO-2's two identical runs rather than asserted; the impact map additionally establishes zero subclasses, so the blast radius is the 13 PostgreSQL configurations and nothing else.
- G-09: **blocked** — no PR exists yet and none has been requested. The design got an adversarial read (`plan-critic`, `weak`, seven objections folded in); the **diff** has not.

## P10 Adjudicated (M/L)

- **332 PostgreSQL baseline files will change once.** Measured, not estimated. Intended consequence of E-2; reviewers should not flag the volume.
- **The DB2 baseline changes by design** (E-3 rewrites the captured `IN (...)` list). Not churn.
- **`SqlServer.2025.MS/TestJSONType` will not move on this PR's CI run.** The PR pipeline's Linux net10 leg already emits `Json`; E-1's effect is only observable on netfx, which runs the main suite only on a `full_run`. Absence of a diff here is expected, not evidence the fix did nothing — TO-1 is what proves it.
- **The 9 `Tests/Tests.T4/**` generated model files are not regenerated here.** Produced manually during the release test-matrix against live databases. The `Cli/*` four should be unaffected (`DataModelLoader` sorts); `Databases/*` and `Default/*` may reorder. Flagged for the next release test-matrix.
- **PostgreSQL's CI reordering trigger is unexplained** (U-7). E-2 is justified as determinism-by-construction. The 17/18-only confinement is not accounted for and is honestly recorded rather than explained away.
- **The unsorted `IN (...)` schema filter is not fixed here** (`DB2LUWSchemaProvider.cs:578/585`, `SchemaProviderBase.BuildSchemaFilter:77`; PostgreSQL already sorts). Separable → own issue with this evidence.
- **`GetTraceBuilder`'s twin race is not fixed here** (`TestBase.cs:80-89`, D-5), nor is `GetCurrentBaselines()`'s reader-side race (`TestBase.Utils.cs:200-203`). Both ride the follow-up issue.
- **The CI mechanism is left alone.** The user chose determinism-at-source; the CI kill-switch remains available as a separate PR.

## P11 Amendments (M/L)

- A-2 (2026-09-13, user-approved, from review finding MIN001) — **adds E-6.** TO-1 was discharged by a *manual* red→green run, so nothing committed reproduced it: E-1's only standing guard was `TestJSONType`'s captured baseline, and a baseline is not an assertion (`BaselinesPath` is CI-only, and on CI a changed baseline is a review signal, not a red test). E-1's failure mode is also the hardest of the four to notice — invisible on the PR pipeline, visible only on the release-only netfx leg — so a regression would resurface as precisely the artifact this branch removes. The new test covers both adapter arms, which also gives D-1's stated failure mode (an unguarded comparison printing `Json` for every `NVarChar`) a standing control. Verified red on net8.0 with E-1 reverted (`DECLARE @p 35(16)`) and green with it.
  Two process notes from producing that red, both worth carrying: the first attempt asserted on `LastQuery`, which holds the command text **without** the parameter declarations — the declarations are in the captured trace, which `GetCurrentBaselines()` exposes. And the first "red" arm was a false negative: `git stash push -- <path>` silently did nothing because the change was already **committed**, so the arm ran against fixed code and passed. Reverting a committed edit-point needs `git checkout <commit>^ -- <path>`, and a red that passes is the signal to check the revert, not the test.
- A-1 (2026-09-12, user-approved) — **adds E-5.** TO-5 was authored as an obligation without a carrier: every other TO-n rides an existing test, but the N-thread `LogQuery` hammer does not exist, so discharging TO-5 requires a new test and therefore a fifth edit-point the original P6 did not authorize. Raised before writing it rather than after. E-4's own subject — the lost-builder race — is otherwise proven only indirectly, through TO-4's timing-dependent ClickHouse run, so the alternative was shipping a lock whose deterministic proof was missing. The approval of the E-1…E-4 surface is unaffected; this adds to it rather than changing it.

## P12 Critic verdict (M/L)

**`weak`** — `plan-critic` on `fable`, dispatched with every measurement forwarded and each fact labelled measured / reasoned-unprobed. Objections are carried visibly rather than absorbed.

What it searched: the 21-file diff `99e78a8803f..e315bec8acd` and each per-file diff; `merge-base` plus the `pr_5913` delta; the next baselines commit (to check for a re-flip); `git grep -l -F ROUTINE_CATALOG` → 332 across 13 dirs; the `GetProviderTypeName` inventory and its single call site; `PostgreSQLSchemaProvider` subclass check; `GetProcedures` in `LinqToDB.CLI`; `full_run`/`win_efcore_only` across `Build/Azure`; `LogQuery` in `Tests/EntityFrameworkCore`; whether any test asserts on procedure order (none); `IncludedSchemas`/`GetHashSet`; `docker ps -a`.

Objections and disposition:

1. **U-5/D-4 rested on a false premise — accepted, design changed.** The two captured blocks are byte-identical, so order cannot flip that baseline; only count varies, and E-4 closes it. The `DisableBaseline` wrap is dropped and SC-4 now keeps the coverage. *This objection changed the plan.*
2. **TO-2 could not be discharged as written, and the PG M2 attribution is under-evidenced — accepted.** No in-tree trigger exists, and the 17/18-only confinement is unexplained given 13–19 share a job. TO-2 relabelled characterization; U-7 and P10 record the gap honestly.
3. **TO-1's proof mode was inconsistent and its red unreachable on the default config — accepted.** TFM named (net8.0), label reconciled, G-01 updated.
4. **D-3's schema list was a hypothesis — accepted and probed.** Measured against the live container: `SYSIBMINTERNAL` and `SYSPUBLIC` return **zero** tables, so my proposed list would have failed the test's own `:1014` assertion. Replaced with the measured `SYSCAT`/`SYSSTAT`, and the now-dead `Inconclusive` guard is removed knowingly.
5. **G-02's expectation was wrong on its face — accepted.** Corrected: the DB2 file moves by design, `SqlServer.2025.MS` does not move on a PR run, and PG 17/18 change in query text only because their current order already equals the sorted order.
6. **E-5's cited precedent has the same hole it closes — accepted, decision added.** `GetTraceBuilder` shares the unguarded get-or-create; D-5 now decides patch-over-unify explicitly and P10 records the twin.
7. **E-2's ordering key was fragile on PG < 12 — accepted, key changed.** `SPECIFIC_NAME` is `proname_oid`, so under a glibc collation ignoring `_` the tie is decided by oid digits. Key is now `SPECIFIC_SCHEMA, ROUTINE_NAME, SPECIFIC_NAME`.

Not re-dispatched: every objection was accepted and folded in, so there is no contested residue for a second round. The critic's own summary of what holds — M1 end-to-end, and the 332-file / 13-dir / zero-subclass impact map — is unchanged by the revisions.
