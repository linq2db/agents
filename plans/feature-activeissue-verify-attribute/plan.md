# Work plan: feature-activeissue-verify-attribute — Run-and-verify replacement for [ActiveIssue] (EF Core pilot)

**Tier:** L  ·  **Status:** amended — phase 1–2 approved & shipped, phase 3 authored and unapproved (critic pending)  ·  **Approved-at:** 2026-09-05 (phase 1–2, user, after critic verdict `weak` folded in)  ·  **Branch:** feature/activeissue-verify-attribute
**Schema:** `.claude/docs/work-plan.md`  ·  **Gates:** `.claude/docs/definition-of-done.md`

Scope of *this branch*, as amended 2026-09-07 (`A-7`):

- **Phase 1–2 — shipped** (`4ba34efcc`…`ec83f3556`, PR [#5882](https://github.com/linq2db/linq2db/pull/5882),
  milestone 6.6.0): the new attribute + the EF Core pilot's 24 gates.
- **Phase 3 — this amendment**: the remaining **302 live `Tests/Linq` gates**, the **12 self-test fixtures**,
  and the **cutover** that renames `ActiveIssueNew` to `ActiveIssue` and deletes the old attribute.

One branch and one PR for all of it, by user decision — the "separate branch" adjudication in `P10` is
reversed, and `P3`'s first constraint with it.

## P1 Problem

`Tests/Base/Attributes/ActiveIssueAttribute.cs:134` sets `RunState.Explicit`, so a gated test is
**excluded from discovery, not skipped** — it appears in neither the run count nor the skip count
(`.claude/docs/testing.md:60`). 340 application sites across 105 files, of which 315 are
`Tests/Linq` and 25 are `Tests/EntityFrameworkCore`. Three falsifiable defects follow:

1. **Two issues on one test cannot be expressed.** `[AttributeUsage(…, AllowMultiple = false)]`
   (`ActiveIssueAttribute.cs:17`). A test broken on Oracle for issue A and ClickHouse for issue B
   must merge both into one `Configurations` list under one issue reference, losing the attribution.
2. **A fixed issue is never detected.** The gate's only output is the category written at
   `ActiveIssueAttribute.cs:135`; searched across `.github/`, `Build/`, `*.props`, `*.targets`,
   `*.ps1`, `*.sh`, `*.runsettings` and `Tests/` — **written and never read**. The only CI category
   expression is `TestCategory != SkipCI` (`Build/CI/run-provider-tests.sh:130`). A gate therefore
   survives its own fix indefinitely and nothing reports it.
3. **The resulting rot is already present and invisible.** `Tests/EntityFrameworkCore/Tests/IssueTests.cs:232`
   (`Issue4333Test`) and `:1110` (`TempTableSurvivesAcrossCommands`) are written
   `[ActiveIssue(TestProvName.AllPostgreSQL)]`, which binds `ActiveIssueAttribute(string issue)`
   (`:38`) — `TestProvName.AllPostgreSQL` is a `const string` (`TestProvName.cs:101`), **not** the
   `Configuration` property. `Configurations` stays null, `runTest` stays false for every provider
   (`:116-121`), and the test is gated on SQLite, SQL Server and MySQL too — while the comment at
   `IssueTests.cs:1109` says the limitation is PostgreSQL-only.

## P2 Success criteria

- SC-1 A test carrying the new attribute that **passes** is decided `Failure` naming the issue → TO-1
- SC-2 A test that fails with the **declared** error is decided `Inconclusive` → TO-2
- SC-3 A test that fails with a **different** error is decided `Failure` naming expected and actual → TO-3
- SC-3b An inner `Skipped` / `Ignored` / `Inconclusive` / `Warning` result is **passed through unchanged** → TO-3
- SC-4 Two instances on **one method** with disjoint provider targeting each govern their own provider — the capability `AllowMultiple=false` denies today → TO-4
- SC-5 The `--test-progress` heartbeat exposes an `inconclusive` bucket surviving a repeat/retry re-book, and `test-status.ps1` prints it → TO-5
- SC-6 All 24 live EF gates are triaged: `git grep -c "\[ActiveIssue[(\]]" -- Tests/EntityFrameworkCore` returns **0** (the pattern must exclude `[ActiveIssueNew(`, which a bare `\[ActiveIssue` prefix match would count; assumes E-12 removes the dead `FSharpTests.cs:55` gate rather than leaving it), and all four EF suites report zero `Failure` → TO-6
- SC-7 The sentinel formatter emits one parsable ASCII line for a message containing `|`, `%`, a newline and a non-ASCII char → TO-7

- SC-8 (phase 3) **The old attribute is gone** — the census reports 0 sites bound to `ActiveIssueAttribute`'s old semantics, `Tests/Base/Attributes/ActiveIssueAttribute.cs` holds the *new* implementation, and `ActiveIssueNew` appears nowhere in `Tests/` → TO-11
- SC-9 (phase 3) **Every migrated gate declares what it observed** — each site carries `ErrorType`/`ErrorTypeName` or `ErrorMessage`, except sites on `A-8`'s waiver list naming the provider and what was tried; a bare gate matches *any* failure, the masking risk Copilot raised on the pilot ([comment 3943935534](https://github.com/linq2db/linq2db/pull/5882#discussion_r3943935534)) → TO-8
- SC-10 (phase 3) **A full CI run reports zero `[ActiveIssue]`-attributed Failures** — every governed case lands Inconclusive, so each leg's population sits in the *skipped* column and the leg stays green → TO-12
- SC-11 (phase 3) **No case is decided by two result-rewriting wrappers** — where a `Throws*` attribute and an `ActiveIssue` gate sit on one method (13 methods, `P7`), exactly one governs any given case (`D-10`) → TO-9
- SC-12 (phase 3) The force-fail sweep instrument is absent from the final diff — `git diff HEAD` on the last commit shows no modification to the attribute's decision path, and `D-11`'s sweep mode is off by default → TO-13
- SC-13 (phase 3) The 12 self-test fixtures' coverage is preserved under the new attribute or explicitly retired with its replacement named → TO-10
- SC-14 (phase 3) **Every gate names its issue explicitly** — the `int` constructor for a linq2db issue (including the **4** sites that pass linq2db's own tracker as a string: 2 positionally at `EagerLoadingTests.cs:757,823` and 2 inside `Details` at `OracleTests.cs:4481` / `FluentMappingExpressionMethodTests.cs:47`), a URL only for a genuinely external tracker; a reference existing only in the test name, in the sibling `[Test(Description)]`, or nowhere is resolved or waived with an `E-35` marker. The accepted set is **closed**: `explicit`, `external-url`, or marker-carrying — every `recoverable-from-*` class is a *finding*, not a pass. Scope is every gate under `Tests/`, both attribute names, the 39 migrated pilot sites included → TO-14
- SC-15 (phase 3) **Every gate's test is validated against its issue before migration** — the harvested failure is the *defect* the issue reports, the assertion fails because of that defect rather than because the test itself is wrong, and the gate's provider scope matches the issue's; a site that fails the check is fixed, re-attributed, converted to the artifact its real cause deserves, or removed — never migrated as a silent known-issue, since a run-and-verify gate over an invalid assertion freezes that assertion as expected behaviour in green → TO-15
- SC-15b (phase 3) **A site that cannot be validated is visibly unvalidated, not quietly migrated** — where `D-16` returns `needs-investigation` the gate carries the distinct `Details = "unvalidated: …"` marker, the census counts those sites, and the count is reported on the PR rather than absorbed; `SC-15`'s "never migrated" is otherwise unsatisfiable, because `SC-8` deletes the old attribute out from under any site held back → TO-15

## P3 Constraints & anti-goals (M/L)

- ~~**No behaviour change for the 315 `Tests/Linq` gates on this branch.**~~ **Void** as of `A-7` — phase 3 is
  precisely that behaviour change. What survives of it: **the branch must be green at every commit**, so a
  batch of sites is migrated only once its evidence is harvested, and the force-fail instrument is never
  committed (`D-6`, unchanged).
- **The cutover is the last commit set, not the first.** Renaming before every site is migrated would leave
  sites bound to a type that no longer has the old semantics.
- **No `Source/` change of any kind.** No public API, no `PublicAPI.*`, no `CompatibilitySuppressions.xml`.
- **No CI yml change on this branch** (`.github/workflows/**`, `Build/Azure/**`, `Build/CI/**`).
- **No edit to the primary clone's `UserDataProviders.json`.** The pilot's provider set is seeded in
  the worktree's own copy (U-8), leaving the user's main-test environment untouched.
- **`ThrowsWhen` family semantics unchanged** — `ThrowsForProvider` (509 uses) and subclasses.
  `MessageMatches` is *read*, never modified. **Narrowed by `A-7`:** no change to what `ThrowsWhenCommand`
  *decides* or when it rewrites; `D-10` may add a read-only `internal` predicate exposing the governs-this-case
  question the command already answers privately (`ThrowsWhenAttribute.cs:98-150`), and nothing else.
- No reformatting / renaming of lines the change does not already touch.
- The force-fail edit (E-2) is **never committed** on this branch.

## P4 Unknowns (M/L)

- U-1 Does anything still hold the tests back once `RunState.Explicit` is removed? — resolved-by scout: no. Zero `ActiveIssue` hits across `.github/`, `Build/`, `*.ps1`, `*.sh`, `*.runsettings`, `*.props`.
- U-2 Do two `IWrapSetUpTearDown` wrappers on one method nest correctly under the deferral protocol? — resolved-by scout: yes, depth-counted (`TestProgressState.cs:120-129`, `:164`), pinned by `TestProgressStateTests.NestedWrappersBookOnceWithTheOutermostVerdict:121`.
- U-3 Is `Inconclusive` treated as a failure by any script or workflow? — resolved-by scout + probe: `grep -rni "inconclusive"` over `.github/`, `Build/`, `.claude/` → zero hits; and `Build/CI/report-trx.ps1:122` fails the step only on `Failed > 0`, reading the trx `passed`/`failed` counters only (`:56-57`), where `inconclusive` is a separate counter.
- U-4 Can the EF corpus exercise the LinqService branch of the match rule? — resolved-by scout: **no**. Both EF data-source attributes pass `includeLinqService: false`. Covered by unit tests instead (TO-4).
- U-5 Can a newly-enabled EF test hang the pilot? — resolved-by scout: yes. `IssueTests.cs:96` `Issue4603Test` and `:179` `Issue4012Test` are recursive `GetCte<Parent>` queries; `.runsettings` sets no `DefaultTimeout`, none of the 24 carries `[Timeout]`, Npgsql's `CommandTimeout` is infinite when unset and SQLite has none. Mitigated by D-5.
- U-6 Is `FSharpTests.cs:55` a live gate? — resolved-by probe: **no**. `FSharpTests.cs:1` is `#if EF8`; `EF8` is defined only at `Source/LinqToDB.EntityFrameworkCore/LinqToDB.EntityFrameworkCore.EF8.csproj:10`, and `DefineConstants` do not cross a `ProjectReference` — only `Tests.EntityFrameworkCore.EF10.csproj:7` defines anything (`EF10`). **24 live gates, not 25.**
- U-7 What happens when the test is not provider-parameterized (`provider == null`)? — resolved-by reading `ActiveIssueAttribute.cs:114-121`: the gate applies unconditionally even when `Configurations` is set. The new attribute preserves this (D-1's failure mode).
- U-8 Which config file does a worktree run read? — resolved-by probe: **none today**. `C:\Worktrees\linq2db\activeissue-triage\UserDataProviders.json` does not exist, the worktree is **not nested** under the primary clone, and `TestConfiguration.GetFilePath` walks ancestors only — so it climbs from `.build/bin` to `C:\` and finds nothing. The pilot must seed a worktree-local copy (`.claude/docs/worktree.md` → *`UserDataProviders.json` in a worktree*). Sibling worktrees carry one for exactly this reason.
- U-9 Do the six MySQL-scoped gates get local evidence? — resolved-by critic: **partially, and the gap is accepted**. CI runs the EF suite on `MySqlConnector.5.7`, `MySqlConnector.8.0` **and** `MariaDB.11` (`Build/Azure/net80/mysql.json:3-9`, `test-matrix.yml:378-388`), three servers with different error wording. The pilot enables all three locally (containers `mysql`, `mysql57`, `mariadb` all exist and are stopped) so an `ErrorMessage` harvested on one is not silently generalised to the others. Affected sites: `ToolsTests.cs:271,305,320,337,352,702` and `IssueTests.cs:792`.
- U-10 How do MTP + NUnit3TestAdapter 6.2.0 map `Inconclusive` to a run exit code and to the console summary? — **resolved-by probe** (2026-09-05, standalone NUnit 4.6.1 / NUnit3TestAdapter 6.2.0 / MTP 2.3.3 project, one passing + one `Assert.Inconclusive` test): the runner prints `skipped Inconclusive (77ms)`, summarises `total: 2 / failed: 0 / succeeded: 1 / skipped: 1`, reports `Test run summary: Passed!` and **exits 0**. So an inconclusive result does not fail a run (D-3 is sound), and it is folded into the **skipped** bucket — the critic's expectation, confirmed. Consequence: on CI, where no `--test-progress` is passed, the `ActiveIssueNew` population is indistinguishable from genuinely skipped tests, so D-4's heartbeat bucket is the only local counter and Phase 3 needs its own.
- U-11 What does the wrapper do with an inner `Ignored` / `Warning` result? — resolved-by critic: the copied pattern gets it wrong. `ThrowsWhenAttribute.cs:165-176` reports an inner `Ignored` result as `Failure` quoting the ignore reason. Not reachable in the pilot (no gated EF test calls `Assert.Ignore`/`Inconclusive`; `IdTests.cs:44,75,…` do but are ungated), live at Phase 3 — so E-1 defines pass-through explicitly (SC-3b) rather than inheriting the bug.

### Phase 3

- U-12 **How many sites are there, and how expensive is each one's evidence?** — resolved-by census
  (`E-19`, run 2026-09-07 against `ec83f3556`): **314** attribute sites in `Tests/Linq` — 302 live + 12
  self-test — across 103 files. `TestProvName.All*` are interpolated `const string`s over `ProviderName.*`,
  so the provider set each gate names resolves statically, giving the cost ladder:
  **133** name no configuration (every provider), **79** name 1, **23** name 2, **17** name 3, **17** name 4–6,
  **6** name 7–12, **27** name 13+. Independently corroborated: a scout counting `\[ActiveIssue` under
  `Tests/Linq` reached 314 real sites after discarding the same string literal at
  `TestProgressStateTests.cs:274`.
- U-13 Is the 1–3-provider batch reachable on this machine? — resolved-by probe (`docker ps -a` + a read of the primary clone's `UserDataProviders.json`, 2026-09-07): yes on both axes. Containers exist for every family needing one — YDB 35 (`ydb`), ClickHouse 32 (`clickhouse`, image 26.5.1, below the AVX2 floor that stops ≥26.6 here), Sybase 12 (`sybase`), Oracle-21-Devart 10 (`oracle21`), DB2 8 (`db2`), Informix 6 (`informix14`), SAP HANA 2 (`hana2`), MySQL/MariaDB 2 — and Access-ODBC 5, SQLite 3, SqlCe 2, DuckDB 1 need none; connection strings for all of them are defined (`YDB`:795, `ClickHouse.Octonica/Driver/MySql`:782-790, `Sybase(.Managed)`:543-547, `DB2`:665, `Informix(.DB2)`:670-675, `SapHana.Native/Odbc`:776-780, `Oracle.21.Devart.Direct`:755, `Access.*.Odbc`:815-819, `SqlCe`:822, `SQLite.Classic.MP*`:828-832, `Northwind.SQLite(.MS)`:848-852, `MariaDB.11`:484, `DuckDB`:860). Two caveats: the worktree had **no** `UserDataProviders.json` at all (seeded by copy 2026-09-07, since `TestConfiguration` only walks ancestors and the worktree is not nested), and `--provider Informix` resolved to **zero cases on net10.0** when last measured (2026-08-27), so Informix's 6 sites need `--list-tests` confirmation before a leg is spent on them.
- U-14 Does a `TestCategory=ActiveIssue`-filtered sweep produce the same outcome a full run would? — **no, and it cannot be made to**; resolved-by A-1's measurement in the pilot (`TestGlobalQueryFilters` passes in a fixture run and fails solo, masked by one specific earlier test), so a filtered sweep is a *third* in-process state distinct from both — contained rather than removed by `D-9`'s rule that every `PASSED` cell is re-run solo, that being the only cell class where the difference changes the verdict.
- U-15 Can two result-rewriting wrappers collide? — resolved-by census + critic, and the collision surface is **one site, not seven**: 13 methods carry both a gate and a `Throws*` attribute (`P7`), `ThrowsWhenCommand` rewrites unconditionally with no marker guard (`ThrowsWhenAttribute.cs:163-187`) while `ActiveIssueNewCommand`'s guard recognises only its own marker (`ActiveIssueNewAttribute.cs:291-294`), and nothing in the repo documents NUnit's nesting order for two `IWrapSetUpTearDown` attributes (`TestProgressState.cs:24-26` says the code deliberately does not rely on one) — but all 13 target sets resolve from source once the subclass defaults are read (`ThrowsRequiresCorrelatedSubqueryAttribute.cs:13-15` → `AllYdb`, plus `AllClickHouse` when `simple:false`; `IntervalTranslationTests.cs:220-234` → Access, Informix, SqlServer≤2014), and exactly **one overlaps**: `IntervalTranslationTests.Queries.cs:435`, whose gate names no configuration and therefore governs every provider its two `ThrowsForProvider` attributes target — made safe by `D-10`.
- U-16b Was the census's own overlap check trustworthy? — resolved-by critic, and **no, it produced a false clean on precisely that site**: it computed overlap as a set intersection, so an unconditional gate (empty provider set) intersected to zero, and an unresolvable `Throws*` target set was indistinguishable from a disjoint one. Fixed 2026-09-07 — an unconditional gate now reports `ALL`, an unresolved target set reports `UNRESOLVED`, and re-running flags `Queries.cs:435` as `ALL` and six sites as `UNRESOLVED` for hand resolution. `TO-8` makes this script a gate, so the fix precedes the gate.
- U-21 How much attribution work is there, and how much of it is mechanical? — resolved-by census (`E-33`, run 2026-09-07, after the first dry run added a recovery source the first count missed): of the 302 live gates, **59** name a linq2db issue through the `int` constructor (28 distinct issues), **35** carry an external tracker URL (9 distinct targets, mostly `Octonica/ClickHouseClient`), **80** carry an exact issue URL in the sibling `[Test(Description = …)]`, **35** more only have `IssueNNNN` in the method or fixture name, and **93** have nothing recoverable. So 174 of 302 already hold an *exact* reference somewhere on the method and only need it moved into the attribute; 35 rest on the naming convention; 93 need a tracker search or a filing decision. Two of the 35 "external" URLs are linq2db's own tracker passed as a string (`EagerLoadingTests.cs:757,823`) and must become `int`, leaving 33 genuinely external; two more hide an exact issue URL inside their own `Details` (`OracleTests.cs:4481`, `FluentMappingExpressionMethodTests.cs:47`), a sixth recovery source, which takes the unattributed residue to **91**. **Add the pilot:** the census now reads both attribute names and sees 39 migrated sites, 4 of them prose (`ToolsTests.cs:702,704,708,710`) — `SC-14` covers those too. **Cost, stated honestly:** issue reads amortize across sites (~130 distinct issues), but V2 does not — it is one test body per gate, so the floor is **302 test-body reads plus ~130 issue reads**, and that is the size of requirement 2.
- U-23 What is the *unattributed* population actually made of — bugs awaiting a number, or something else? — resolved-by reading all **81** prose-carrying gates (2026-09-07). Provisional classification, and deliberately labelled so because `D-16` treats the prose as untrusted: roughly **45** describe a **limitation** nobody intends to fix now (15 of them one YDB temporary-table gap across `TableOptionsTests`/`CreateTempTableTests`, plus "Functionality not implemented yet", "Waiting for SqlClient support", "not supported by Access", "we don't plan to do anything about it for now"), about **16** describe our **environment** or flakiness (8 × "Used docker image needs locale configuration", "Fails on CI", "Error from Azure runs (db encoding issue?)", "Bad database data", "Unstable, depends on metadata selection order", "ASE is terminating this process"), and only about **17** read as a product **bug** that could carry an issue number. The consequence for `A-10` requirement 1 is real: for the majority of the unattributed residue there is no issue to name, so `SC-14` must accept `D-16`'s `limitation` / `environment` dispositions instead of demanding a number — which is what the user's own "when … issue known" qualifier allows.
- U-22 Can a gate's reference be recovered from the name safely? — resolved-by probe (2026-09-07): **54** sites carry both a name-derived number and a `[Test(Description = …)]` issue URL, and they agree on **all 54** — zero disagreements — so the convention is corroborated rather than assumed at the scale where it can be checked. `D-15` still ranks the URL above the name and still has `D-16` V1 confirm per site, but the bulk risk is measured, not feared.
- U-24 Can every gate's failing set be expressed by the new attribute's targeting? — **no, and batch A's first six sites already contain a counter-example.** `SQLiteTests.cs:799` `Issue3766Test2` is gated `Configuration = AllSQLiteClassic` and parameterised `[Values] bool inline`; swept 2026-09-08, its `inline: True` cases **pass** on all three Classic providers (direct and LinqService) while its `inline: False` cases fail `Expected: 1 But was: 0`. `AppliesTo` keys on provider and transport only (`ActiveIssueNewAttribute.cs:146-161`), so a faithful migration would mark six passing cases and report each as "test passed but is marked" — turning a green leg red. The old attribute hid the whole method from discovery, which is exactly why nobody could see that half its cases pass. Resolved-by `D-17`; the population is unknown until each parameterised gate is swept, so `D-9`'s per-site record must capture *which cases* failed, not merely that the site failed.
- U-25 What happens when a gated test does not fail but **hangs**? — resolved-by probe, and it is the sharpest blocker found so far: the first cohort-wide YDB sweep died on `AssociationTests.GroupBy1("YDB")`, stuck with no progress until `--hangdump-timeout 5m` killed the process (`linq2db.Tests_38432_hang.log`: `[00:05:02] GroupBy1("YDB")`). `U-16` anticipated hang-prone sites from *reading*; this one was not on that list, which is the point — the reading found MARS and retry-policy candidates and missed the actual one. The consequence is worse than `U-24`'s: a migrated gate whose test reddens a leg costs a red build, but a migrated gate whose test **hangs** costs the *whole leg*, since CI runs the same `--hangdump --hangdump-timeout 5m` and the process is killed. So a hang-prone site cannot be migrated as-is under any declaration — `ActiveIssueNew` decides an outcome, and a test that never returns produces none. Its candidate dispositions are a provider exclusion (drop the provider from the test's data sources, which is what "this provider cannot run this" actually means), or fixing the hang; both are the user's call under `A-12`, and the sweep procedure must additionally isolate a discovered hanger before re-running the cohort, per `D-5`.
- U-27 Is the ClickHouse cohort's local evidence admissible? — resolved-by probe 2026-09-08, and **only for two of its three providers**. `ClickHouse.Driver` and `ClickHouse.MySql` swept cleanly. `ClickHouse.Octonica` did not: the combined run died with an access violation (`U-26`), the isolated run hung on the MARS family that `U-16` predicted, and excluding MARS left 126 failures of which many read `Octonica.ClickHouseClient.Exceptions.ClickHouseException : The connection is closed. ErrorCode: 3` — on a defensive `DROP TABLE` or a plain `SELECT`, i.e. not the defect any of those gates claims. That looked like a poisoned-connection cascade, but running `CreateTableWithEnum` **alone** reproduces it on its first statement, so the connection is unusable for that workload from the start while 55 other tests in the same run pass. This is `A-15`'s rule firing exactly as written — a failure naming a *client driver* connection error quarantines the provider — and it is the second instance of the `A-13` shape, where a local driver defect masquerades as the product's. **Settled after two wrong turns; the accurate account is third.** `Build/Azure/scripts/clickhouse.sh:20` patches the server's `users.xml` before CI runs anything, setting `join_use_nulls=1`, `mutations_sync=1`, `allow_experimental_object_type/geo_types/json_type=1`, `allow_experimental_correlated_subqueries=1`, `enable_analyzer=1`, `enable_materialized_cte=1`, and — per its own comment, explicitly to work around **Octonica.ClickHouseClient 4.1.4** advertising protocol revision 54483 and then failing on features that revision permits — `enable_producing_buckets_out_of_order_in_aggregation=0` and `allow_special_serialization_kinds_in_output_formats=0`. The local container turned out to carry **eight of the ten** already — an older revision of the same script, applied whenever it was built — and to be missing exactly the two Octonica protocol workarounds, which were added to the script later. That is the whole explanation for this cohort: `Driver` and `MySql` were always running with `join_use_nulls`/`enable_analyzer` set as CI sets them, so **their evidence was valid**, and Octonica failed because the two settings written specifically to keep client 4.1.4 alive were absent. Both intermediate conclusions were wrong and are recorded as such — first "Octonica's driver is unreliable" (true symptom, wrong cause), then "the whole cohort is inadmissible because the container is unpatched" (wrong premise: it was patched, just not currently). The container now carries the current ten settings exactly once, verified through `system.settings`, and the cohort is re-swept against it. **And the resolution was cheaper than any of it: read the issue the gate cites.** After the patch, the `The connection is closed. ErrorCode: 3` failures persisted **unchanged** — so the two workaround settings were not their cause either (they target out-of-order buckets and replicated serialization, different symptoms). One lookup finished it: the gates on those sites cite **Octonica/ClickHouseClient#58**, whose title is *"`The connection is closed.` exception on next command after failed command"* — verbatim the observed failure. The evidence was admissible from the start; what was wrong was three successive guesses at a cause that the cited reference already named. `AGENTS.md` → *a cited external precedent is a claim too* is about verifying references others cite; the inverse is the rule this cost: **when a gate names an upstream issue, read that issue before theorising about the failure it produces.** Method note that survives regardless: **verify a container's configuration against the repo's provisioning script before trusting evidence from it**, and check for a *partial* match rather than presence-or-absence — a half-patched server is the case that produces plausible results. Applying the patch blind also broke the server (duplicate keys → `Setting join_use_nulls[1] is neither a builtin setting`, exit 91), which is its own argument for reading the current state first.
- U-28 Were the ClickHouse "stale" verdicts sound? — resolved-by solo re-run: **no, and the defect was in my analysis, not the data** (2026-09-08). The cohort summary reported a per-test outcome by sampling `Group[0]`, the first case of each test name, so a test whose cases disagree was rendered as whichever case happened to come first. Solo re-runs under `A-1` disagreed with it: `AllNullsEnum` and `AllNullsCEnum` **pass** for `(provider, True)` on all three providers and both transports, and **fail** for `(provider, False)` with `Shouldly.ShouldAssertException : count should be 0 but was 1`. They are not stale at all — they are two more instances of `U-24`/`D-17`, failing on one value of a `[Values]` axis. Only `TestCteInvalidMappingUnion` passes across all six cases. Two lessons: a per-test summary over parameterized tests must **aggregate** every case rather than sample one, and `A-1`'s solo re-run earns its place a second time — it was written to catch a suite-masked *pass*, and here it caught a summary-masked one. The YDB figures are unaffected: those were counted per case and every annotation was verified by re-running to Inconclusive.
- U-26 Can a gated test take down the **host process** rather than merely failing? — resolved-by probe, 2026-09-08: yes, and it cost a whole cohort's harvest. The first ClickHouse sweep, run across `Octonica`/`Driver`/`MySql` in one invocation, died with exit **-1073741819 (0xC0000005, access violation)** in a `SocketAsyncEventArgs` IO-completion callback — a native crash, not a test failure. No `.trx` was finalised, so every result from that run was lost (only MTP's streaming `trx-stream-*.bin` survived). Same consequence class as `U-25`'s hang and the same conclusion for migration — a crashing case yields no outcome for the attribute to rewrite, and on CI it kills the leg — but a different procedural lesson: **partition a sweep by provider**, because one provider's crash otherwise destroys the evidence gathered for all of them. Re-run per provider to isolate which one crashes.
- U-20 Does MTP write an NUnit `Inconclusive` result to the trx as `Inconclusive` (which `report-trx.ps1:77-80` counts as **failed**) or as `NotExecuted` (skipped)? — **resolved-by probe, 2026-09-07**: ran the already-built EF10 test assembly in the worktree against the migrated gate `Issue3174Test("SQLite.MS")`, which failed as declared and was rewritten to Inconclusive; the runner printed `skipped … total: 1 / failed: 0 / succeeded: 0 / skipped: 1` and the emitted trx carries **`outcome="NotExecuted"`**. So a migrated gate cannot redden a leg through `report-trx.ps1`, and `SC-10` does not depend on a `Build/CI/` change that `P3` forbids. The prior reasoning from the pilot's green Azure legs was insufficient — `PublishTestResults@2` has no `failTaskOnFailedTests`, so Azure green said nothing about the outcome string.
- U-16 **Which un-gated tests can hang, and which can poison the shared database?** — resolved-by scout.
  Hang candidates: `RetryPolicyTest.cs:263,279` (`Issue3431Test1/2`, deliberately bad connection string, one
  retry) and the ten MARS tests in `DataConnectionTests.cs:939-1407`, gated on `ClickHouse.Octonica` for
  [ClickHouseClient#59](https://github.com/Octonica/ClickHouseClient/issues/59) — a second reader opened on a
  live command against a driver that may not fail fast. Corruption candidates: `CreateTableTests.cs:277`
  (`CreateTableWithEnum` creates `TestEnumTable` without `using`, drops it on the last line, and already
  carries a defensive pre-drop) and `DeleteTests.cs:172` (`DeleteMany2` inserts nine rows into the shared
  `Parent`/`Child`/`GrandChild` tables *outside* the `try` whose `finally` cleans them up). Handled by `D-9`'s
  batch isolation.
- U-17 **Does the migration produce a baselines flood?** — resolved-by reading + the pilot's own CI.
  `BaselinesManager.Dump` returns early when `TestContext.CurrentContext.Result.FailCount > 0`
  (`BaselinesManager.cs:31`), and `[TearDown]` runs *inside* the wrapper, so it observes the pre-rewrite
  result: a gate that still fails writes nothing. Only a **surprise pass** emits a baseline it never had.
  The pilot is the control — 206 added baseline files, every one attributable to a test that started passing
  (`G-02`). Scale for phase 3 is therefore bounded by the number of `remove` verdicts, not by 302.
- U-18 **Do the F# gates need F# attribute work?** — resolved-by scout: **no**. `Tests/FSharp/*.fs` carries no
  NUnit attributes at all — its two `[ActiveIssue]` mentions are prose in comments (`OptionTypes.fs:134`,
  `Issue1813.fs:491`), and the functions are plain `let`s called from a C# fixture. The real gates are C#
  (`Tests/Linq/Linq/FSharpTests.cs:167,450,458`), so the `Configurations = [| … |]` form F# has never used in
  this repo is never needed.
- U-19 **How does a CI sweep hand its evidence back?** — resolved-by scout, and the path is narrow. No
  entrypoint exposes a filter override (`--filter "TestCategory != SkipCI"` is hardcoded at
  `run-provider-tests.sh:130`, `test-workflow-linux.yml:148,152,157`, `test-workflow-windows.yml:233,237,242`,
  `build.yml:245`), and no provider leg publishes a raw log or `.trx` artifact. The sentinel already accounts
  for this — it rides the **failure message** into the trx (`ActiveIssueSentinel.cs:7-9`), which
  `report-trx.ps1:73` reads. Two amplifiers to design around: MTP's `--retry-failed-tests-max-tests 5` turns
  retry off entirely once more than five tests fail, while Azure's `retryCountOnTaskFailure: 2` still re-runs
  the whole main-suite step three times on the Access and Oracle legs.

## P5 Decisions (M/L; rejected alternatives mandatory at L)

### D-1 — Targeting is decided at runtime inside the command, not at build time

- **chosen:** the wrapper calls `NUnitUtils.GetContext(context.CurrentTest)` (`Tests/Base/NUnitUtils.cs:50`) for `(provider, isLinqService)` and decides applicability per test case.
- **rejected:** mirror the old attribute's `CombiningStrategyAttribute` + `ITestBuilder` shape (`ActiveIssueAttribute.cs:18,97`) — two `ITestBuilder`s on one method build the case list **twice**, which is exactly why the old attribute is `AllowMultiple = false`. Keeping it forfeits the headline requirement.
- **why this:** `ThrowsWhenAttribute` proves the pattern at scale — `AllowMultiple = true`, reads `context.CurrentTest.Arguments` at execution time, 864 combined uses across its subclasses. The critic's consumer sweep confirmed `GetContext` resolves a provider for **every** EF case.
- **failure mode of the choice:** a test with no `DataSourcesBaseAttribute`-carrying parameter yields `provider == null` and the instance applies unconditionally, silently ignoring a `Configuration =` the author wrote. Detected by TO-4's null-provider case.

### D-2 — `ErrorMessage` is matched with `ThrowsWhenAttribute.MessageMatches`

- **chosen:** reuse the existing `internal static bool MessageMatches(string actual, string expected)`, which treats `{0}`-style placeholders as patterns and otherwise does `actual.Contains(expected)`.
- **rejected:** a private `Contains` — loses placeholder handling the repo added deliberately so a test can name an `ErrorHelper` format-string constant instead of copying its wording with arguments substituted (the copy is what rots).
- **why this:** the repo's own idiom for this exact question, already handling multi-line messages via `RegexOptions.Singleline`.
- **failure mode of the choice:** an expected message legitimately containing a literal `{0}` is silently treated as a pattern. Inherited, not introduced.

### D-3 — "Still broken" reports `Inconclusive`

- **chosen:** matched failure → `ResultState.Inconclusive`.
- **rejected:** `Success`, which is what `ThrowsWhenCommand` does for an expected throw (`ThrowsWhenAttribute.cs:186`) — it would put a known-broken test in the pass count, reintroducing `P1` defect 2.
- **rejected:** `Skipped` — the test really ran and its outcome is meaningful.
- **why this:** the only NUnit state that is neither pass nor fail, so CI stays green while the population stays countable.
- **failure mode of the choice:** **CI passes no `--test-progress`** (`test-workflow-linux.yml:157`, `run-provider-tests.sh:128-135`), so "the population stays countable" holds for *local* sweeps only; on CI the population is folded into whatever the platform maps Inconclusive to (U-10). Phase 3 must add its own count.

### D-4 — Add a real `inconclusive` bucket to the heartbeat, in `Book` **and** `Unbook`, and surface it

- **chosen:** `_inconclusive` field + `Inconclusive` property + a `case` in both `TestProgressState.Book` (`:222-234`) and `Unbook` (`:251-266`), the JSON line in `TestProgressReporter.Write` (`:269`), **and** the `test-status.ps1` output line (E-14).
- **rejected:** leaving it in the existing `default:` arm — counted in `_completed` but no bucket.
- **rejected:** editing `Book` only — `Unbook` exists so a `[Repeat]`/`[Retry]` re-book does not double-count; an asymmetric pair leaks a count on every re-booked inconclusive case.
- **why this:** it is the local sweep's primary metric. E-14 is what makes the motivation true: without it the JSON carries the bucket and the tool the plan names still prints only pass/fail/skip.
- **failure mode of the choice:** `TestProgressStateTests.cs:226` asserts `Passed + Failed + Skipped == units`; a fourth partition member changes that invariant and the `Recorder` write-tuple (`:277`,`:284`) needs a seventh field. Both in E-5.

### D-5 — The pilot is bounded by two filtered runs per provider, not by test ordering

- **chosen:** per provider, run the 22 safe gates first, then a second filtered run containing only `Issue4603Test` and `Issue4012Test` (U-5), with `--hangdump --hangdump-timeout 5m` on both.
- **rejected:** `[Order]` on the two CTE tests — a change to tests under triage, which is the contamination argument used to reject `[Timeout]` below; and NUnit's default alphabetical order puts `Issue4012Test`/`Issue4603Test` *before* the rest, so a hangdump kill would lose every later case in that run.
- **rejected:** `[Timeout]` / `CancelAfter` — NUnit 4's `CancelAfter` requires the test to take a `CancellationToken`, i.e. changing the signature of a test we are trying to observe.
- **rejected:** provider `CommandTimeout` — infinite for Npgsql when unset, absent for SQLite, so exactly the two providers that can hang are the two that are unbounded.
- **why this:** isolates the only two known-unbounded tests into a run whose loss costs nothing else, using the same `--hangdump` convention as CI.
- **failure mode of the choice:** `--hangdump-timeout` is a **per-test inactivity** guard, not a run budget, so a query making slow steady progress is not caught — visible as a run exceeding its expected wall-clock, not automatically.

### D-6 — The force-fail edit is applied locally and never committed on this branch

- **chosen:** E-2 is applied to the working tree for each sweep and reverted before commit.
- **rejected:** committing it now — it turns all 315 `Tests/Linq` gates red, so the branch could not be merged and every concurrent PR would have to distinguish its own failures from the noise.
- **why this:** the EF triage completes in-session, so the force-fail state only has to exist while sweeping.
- **failure mode of the choice:** an uncommitted edit is lost to a `git stash`/`reset`, and `git apply` **stages**, so `git checkout -- <path>` silently does not revert it. Revert with `git checkout HEAD -- <path>` and prove it with `git diff HEAD`. The 12 untouched self-test fixtures (D-8) are the tripwire if a revert is missed.

### D-7 — The sentinel formatter is committed `Tests/Base` code; only its caller is temporary

- **chosen:** a committed `ActiveIssueSentinel` static in `Tests/Base` owning `Format(...)` and `TryParse(...)`; E-2 (uncommitted) only calls `Format`. Line shape:
  `##L2DB-AI|1|<FullName>|<provider|->|<0|1>|<PASSED|FAILED>|<errorType|->|<message>`, `|`/`%`/newlines escaped, message capped ~500 chars, no stack trace.
- **rejected:** putting the formatter inside E-2 — it would be uncommitted, so nothing could test it and TO-7 could not exist as an obligation at all.
- **rejected:** a side-channel file per case — provider lanes run in parallel since #5614, so an unlocked `File.AppendAllText` throws `IOException` *inside the code under test* and fails the test it is instrumenting.
- **rejected:** relying on the trx `testName` alone — it carries no class name (that lives on `TestMethod/@className`, joinable only by `testId`), and cannot express "this test actually passed" once force-fail has rewritten every outcome to `Failure`.
- **why this:** makes the format testable and gives the `.ps1` parser (E-9) a C# `TryParse` to mirror.
- **failure mode of the choice:** the message is also what a human reads; capping it at one line discards the assertion diff, so a wrong-results case must be re-run locally to see what differed.

### D-8 — The 12 existing self-test fixtures are left untouched

- **chosen:** `ActiveIssueConfigurationTests.cs` (7) and `ActiveIssueGenericTests.cs` (5) keep their current bodies and their `[ActiveIssue]` attributes. New-attribute tests go in E-8 instead.
- **rejected:** rewriting them into unit tests of the new `AppliesTo` (the original plan) — their bodies `Assert.Fail("This test should be available only for explicit run")`, so they fail loudly the moment the **old** gate stops applying. That is precisely the guard `P3`'s first constraint needs while E-2 is hand-applied and hand-reverted on every sweep, and D-6 names a botched revert as its own failure mode.
- **why this:** deleting a tripwire at the moment it is most load-bearing is a bad trade for a tidier diff; it also shrinks `P6`.
- **failure mode of the choice:** the new attribute's targeting logic gets no *migrated* coverage, so E-8 must re-derive the 7 permutations from scratch rather than porting them.

### D-9 — Phase 3 sweeps by provider, narrowest-first, locally; CI only for what local cannot reach

- **the per-provider run needs the force-fail edit; no filter can substitute for it** (measured 2026-09-08,
  correcting this decision's original wording). Three filter forms were tried against the YDB population:
  `--filter "Name~A|Name~B"` ran 21 tests, **none of them the gated ones**, because the expression form does
  not explicitly select an `Explicit` test — and `Name~FluentMappingTest` silently matched a whole unrelated
  *class*; `--filter "TestCategory=ActiveIssue"` **discovered 158 and executed 4**, reporting `skipped: 154`
  and **exit 0**, a green run that measured nothing; only a **bare substring matching the test name**
  (`--filter "IsTemporary"` → 8 run, 8 failed) executes them. So a name-selected sweep costs one run per
  test-name group — ~27 for YDB alone — while `E-2`'s force-fail edit restores the single per-provider run
  this decision assumes. Use force-fail for a cohort, bare names for a handful, and never a category or
  expression filter, whose failure mode is a confident green.
- **chosen:** batch the sweep by **provider**, in ascending order of how many providers a gate names. Batch A
  is the 119 sites naming 1–3 providers, run as 12 filtered runs (one per provider family, `U-13`); batch B is
  the 23 sites naming 4–12; batch C is the 133 unconditional plus the 27 naming 13+, which need a CI sweep.
  Batches A and B start now; C waits for a free CI and a separate go-ahead (user, 2026-09-07: *"ci busy right
  now, so first try to sweep tests that have 1-3 providers with active issue"*).
- **batch C runs on a throwaway ref, never on the PR branch.** The critic showed the original wording was
  unsatisfiable: `P3` requires evidence before migration, `D-6` keeps the force-fail edit uncommitted, and
  `D-11` puts sweep mode in the *new* attribute — so a CI-observable batch-C site would have to be migrated
  before its evidence existed. It also has nowhere to read a switch from: `tests.yml:12-51` exposes only
  surface/full_run/ref/baselines/pr, and `run-provider-tests.sh:126-135` plus
  `test-workflow-{linux,windows}.yml` hardcode their arguments. So batch C is a **scratch branch** carrying
  the force-fail edit *and* whatever workflow change feeds the sweep switch — neither of which `P3` forbids
  there, because nothing on that ref is ever merged. Harvest from its logs, delete the ref, then migrate the
  sites on the PR branch from evidence already in hand.
- **rejected:** file-by-file, the order the diff will eventually read in — a file's gates span unrelated
  providers, so it multiplies the number of runs by the number of files rather than the number of providers.
- **rejected:** CI-first for everything, as the pilot's `P10` assumed — CI is busy, has no filter hook
  (`U-19`), and would spend a full 44 k-test leg per provider to observe 302 tests.
- **why this:** the sweep's cost is *runs*, not tests; one filtered run per provider is the minimum, and the
  narrow batch is the part where one run settles the whole site rather than one cell of it.
- **a provider's sweep output is rejected wholesale unless its `CreateDatabase` case passed in the same run.**
  `TestConfiguration.cs:91` warns that a `--provider` with no connection string "will fail to connect", and
  under the sweep that connection error is recorded as *the* observed failure of every gated case on that
  provider — a full set of confident, uniform, wrong annotations. `E-9` gains the check; the tell is that
  every cell for one provider carries the same error.
- **failure mode of the choice:** a filtered run is its own in-process state (`U-14`), so a `PASSED` cell can
  be masking. Every `PASSED` cell is re-run solo before any `remove` verdict (`A-1`), and `A-2`'s bisect
  corroboration still gates the removal itself. Second-order: local ClickHouse is pinned at 26.5.1 by the
  AVX2 floor while CI runs the latest image (`Build/Azure/README.md:132-135`), so a message harvested here for
  any of the 32 ClickHouse sites may not match on CI.

### D-10 — A `Throws*` attribute wins the case; the gate defers to it

- **chosen:** when a `Throws*` attribute governs the case being decided, `ActiveIssueNew` leaves the result
  alone. Implemented by asking the `Throws*` family the question its own command already answers privately —
  a read-only `internal` predicate over `ParameterName` + `ExpectsException` (`ThrowsWhenAttribute.cs:98-150`)
  — so the answer cannot drift from the one the other wrapper acts on.
- **rejected:** giving `ThrowsWhenCommand` the same marker guard `ActiveIssueNewCommand` has. It is the larger
  change (509 call sites downstream of it) and it only makes the collision *order-dependent* rather than
  wrong: whichever wrapper lands innermost still decides.
- **rejected:** a static census rule forbidding the combination. It cannot see the seven sites whose `Throws*`
  target set is computed inside the attribute (`U-15`), so it would report a clean sweep over exactly the
  cases it cannot analyse — a gate that measures nothing.
- **why this:** the two attributes make different claims. `Throws*` says *this provider is expected to reject
  this query* — a supported limitation, asserted as such. `ActiveIssue` says *this is a bug*. Where both
  apply, the limitation is the more specific statement and the one already carrying an assertion.
- **remedy when the deferred-to expectation is itself wrong:** at `IntervalTranslationTests.Queries.cs:435` —
  the one genuine overlap (`U-15`) — the gate's `RunState.Explicit` has meant those cells never ran, so the two
  `ThrowsForProvider` expectations on Access, Informix and SqlServer≤2014 have **never been exercised on CI**.
  If one of them is wrong, the case goes red and no `ActiveIssue` declaration can express it, because the gate
  defers by design. The fix is then that site's `Throws*` provider list, in a file `E-22` already opens — not
  a wider change to `D-10`.
- **failure mode of the choice:** a genuine bug on a provider that also has a `Throws*` limitation goes
  unrecorded, because the case never reaches the gate. Detected by the census listing the 13 co-sited methods
  (`TO-9`) for a human read, rather than by the runtime.

### D-11 — Sweep mode lives in the new attribute, off by default, read from the environment

- **chosen:** the new attribute gains a sweep mode, enabled by an environment variable, that emits the
  `ActiveIssueSentinel` record as the result message and reports `Failure` instead of rewriting. Off, it is
  exactly today's behaviour.
- **rejected:** keeping the pilot's approach — a temporary hand-edit to the attribute (`E-2`) — as the only
  instrument. It worked for 24 EF gates in one session; for 302 sites over 12+ local runs and a later CI
  sweep it has to be applied and reverted by hand every time, and `D-6` already names a botched revert as its
  own failure mode.
- **rejected:** always emitting the sentinel, so re-triage is free forever. It puts a 500-char machine record
  into the message of every known-issue case on every run, for a benefit only a sweep consumes.
- **why this:** it makes a sweep repeatable without a hand-edit-and-revert cycle per run, and it is the form a
  scratch-ref CI sweep can switch on (`D-9` batch C). It does **not** reach the PR branch's CI by itself — the
  critic established there is no env input on `tests.yml` and no unhardcoded argument on either platform, so
  the switch travels with the scratch ref's own workflow change or not at all. Read the variable through
  `TestEnvironment.IsEnabled` (`Tests/Base/TestEnvironment.cs:35`), the idiom already in the tree.
- **failure mode of the choice:** a variable left set locally turns an ordinary run's known-issue cases red.
  The mode announces itself once per run in the console header so the state is visible in any log.

### D-12 — The 12 self-test fixtures are retired at cutover, not migrated

- **chosen:** delete `ActiveIssueConfigurationTests.cs` and `ActiveIssueGenericTests.cs` in the cutover
  commit, having first confirmed that `ActiveIssueNewTests`' `AppliesTo` matrix covers each of the seven
  targeting permutations they encode.
- **rejected:** flipping them to the new attribute with the rest. Their bodies are
  `Assert.Fail("This test should be available only for explicit run")` — an assertion *about* `RunState.Explicit`,
  the one behaviour the new attribute deliberately does not have. Flipped, they would pass as Inconclusive
  while testing nothing.
- **why this:** their subject ceases to exist at the cutover. Until then they stay exactly as they are —
  `D-8`'s tripwire argument holds for the whole sweep, and they are the thing that goes red if a force-fail
  revert is missed.
- **failure mode of the choice:** the seven permutations were characterization-tested against the *old*
  attribute; if `ActiveIssueNewTests` reproduces them incorrectly, deleting the originals removes the only
  cross-check. `TO-10` compares the two matrices before the delete rather than after.

### D-13 — The cutover is one scripted mechanical rename, verified by build and census

- **chosen:** a single scripted pass renames `ActiveIssueNew` → `ActiveIssue` across every site, deletes the
  old attribute file, and renames the new type and its file; verified by a Release build on all four TFMs plus
  a census run asserting zero occurrences of the old name. Its own commit, last.
- **rejected:** hand-editing the sites as each batch is migrated, so the rename lands incrementally. 300+
  near-identical hand edits is the shape `AGENTS.md` → *fix the loop, not each instance* exists to forbid, and
  it would leave the tree in a half-renamed state at every intermediate commit.
- **why this:** the rename is textual and total, so a script plus an objective gate is strictly better than
  review attention spent on 300 identical hunks.
- **failure mode of the choice:** the script also rewrites the *string* occurrences a compiler cannot catch —
  `ActiveIssueNewAttribute.Marker`, doc comments, the census script's own patterns. The census is run before
  and after and the two outputs compared, so a changed count is visible rather than inferred.

### D-14 — A gate whose evidence cannot be harvested is migrated bare, onto a named waiver list

- **chosen:** where neither a local run nor CI can produce the failure (a provider on no reachable leg, a
  `#if`-conditioned gate for a TFM not built here), migrate the site with whatever is provable — often just
  the provider scope — and mark it at the site with `E-35`'s `no-declaration:` prefix (which implies
  `unvalidated:`, since V1 has no harvested failure to match), with the full reasoning in `E-34`'s committed
  ledger. **`P11` is not the waiver list** — an earlier draft said it was, which left
  two homes and nothing machine-checkable; the marker is the gate's input and the ledger is the audit trail.
- **rejected:** leaving such sites on the old attribute. It keeps two mechanisms alive forever and blocks
  `SC-8`.
- **rejected:** guessing the error text from the issue or the surrounding comment. `AGENTS.md` →
  *Issue-proposed fix details are written from memory* applies exactly: a copied message that never matched
  turns the gate into an unconditional Failure the day the test runs.
- **why this:** a bare gate is what exists today, so it is not a regression; an unreviewable *list* of them
  would be. The waiver list is what keeps the count small and visible.
- **failure mode of the choice:** a bare gate masks an unrelated regression on that provider — the exact
  Copilot finding from the pilot. Bounded by keeping the list short and naming each entry.

### D-15 — Every gate carries a resolved issue reference; the recovery order is fixed and the residue is listed

- **chosen:** resolve each site's reference in precedence order — an existing `int` wins; an existing external
  URL stays a URL (`ProviderName`-style trackers are not linq2db issues and the `int` ctor would fabricate a
  link); then the **exact issue URL in the sibling `[Test(Description = …)]`**, which 80 sites already carry
  and which is a reference rather than a convention; then the `IssueNNNN` in the method or fixture name as a
  **candidate** confirmed under `D-16` V1; then a tracker search by symptom and test name. Anything still
  unresolved keeps its prose as `Details` and carries the waiver marker (`E-34`) naming the search terms.
- **the `[Test(Description)]` source was found by executing the protocol, not by designing it.** The first
  dry-run site (`SQLiteTests.cs:799`) was classified `recoverable-from-name` by the census and turned out to
  carry `[Test(Description = "https://github.com/linq2db/linq2db/issues/3766")]` two lines below the gate. The
  census now reads it, which moved 80 sites out of the unattributed column in one change.
- **rejected:** promoting the name-derived number straight into the attribute. The name records what the test
  was *written* for; the gate may have been added later for something else (`U-22`), and a wrong number is
  worse than none — it sends the next reader to an unrelated issue and makes `/enable-disabled-test` un-gate on
  the wrong close event.
- **rejected:** filing a fresh issue for each of the 122 unattributed sites. Most will resolve to an existing
  issue once searched, and a burst of ~100 new issues is noise the tracker cannot absorb; filing is the answer
  only where the search comes back genuinely empty *and* `D-16` says the failure is real.
- **why this:** it is the only part of the gate a machine can check, and it is what makes the whole population
  queryable — "what is still broken because of issue N" is unanswerable today for 122 of 302 gates.
- **failure mode of the choice:** the search step is judgement, so a site can be attributed to a
  plausible-but-wrong issue. The ledger records the search terms and the confirming quote, so the claim is
  reviewable rather than implicit.

### D-16 — A gate is only migrated once its test has been validated against the issue

- **chosen:** at annotation time each site gets a recorded verdict from four bounded checks, made against the
  **issue text and the test body only**: V1 *defect match* — the harvested failure is the defect the issue
  reports, which is **not** the same as matching its error string (see the dry run below); V2 *assertion
  integrity* — the assertion fails because of that defect, not because the expected value, the SQL-string
  comparison or the ordering assumption in the test is itself wrong; V3 *path match* — the test exercises the
  construct the issue names; V4 *scope match* — the gate's provider scope matches the scope the issue states,
  which is the check that catches the `P1` defect-3 class of mis-scoping. Verdicts: `matches` → migrate with the declaration;
  `test-defect` → fix the test, then re-sweep that site (passes ⇒ remove the gate under `A-1`/`A-2`; still
  fails ⇒ migrate with the corrected observation); `wrong-issue` → re-attribute under `D-15`; `no-issue` →
  file one, or record why not; `needs-investigation` → migrate but carry `SC-15b`'s `unvalidated:` marker,
  never silently. Plus three verdicts for the population that is **not a bug with an issue**, which the prose
  sites show is substantial (~45 of 81 prose gates, `U-23`): `limitation` — the provider cannot do it and
  nobody intends to (`WhereTests.cs:1676,1696` "we don't plan to do anything about it",
  `PostgreSQLTests.cs:1387,1407` "not implemented yet", `SqlServerTypeTests.cs:134` "Waiting for SqlClient
  support") → **the disposition is the user's, taken per case in batches** (user, 2026-09-08: *"I need to
  decide per-case in batches"*), so the sweep's job is to group the candidates and present them with the
  evidence, not to convert them to `Throws*` on its own authority; `environment` — the failure is our test
  environment, not the product → **verify locally and try to fix it** (user: *"as we use same image locally -
  makes sense to verify locally and see if it can be fixed"*), which for the eight Informix locale gates means
  reproducing the `DB_LOCALE=en_us.utf8` gap against the local `informix14` container before any of them is
  written off; `flaky` / `bad-test-data` (`SchemaProviderTests.cs:353` "Unstable",
  `OrmBattleTests.cs:668` "Bad database data") → their own disposition, not a known-issue gate.
- **`environment` is not hypothetical, and it is where a name-derived number does real damage.** Measured
  2026-09-07: `Issue1307Tests.cs:169-211` carries four gates reading "Used docker image needs locale
  configuration", with a comment above them naming `DB_LOCALE=en_us.utf8`; the census labels them
  `recoverable-from-name` → 1307. Issue **1307 is CLOSED, `resolution: external`** — an Informix driver
  truncation report. Promoting that number would assert a closed external issue is still failing, on four
  tests that fail because of our container. `D-15`'s candidate-only rule is what stops it; this verdict is
  what the sites actually need.
- **a `PASSED` cell or a `V1` mismatch triggers a solo re-run before the verdict is recorded.** The four
  static checks read the issue and the test body, and this decision's own motivating failure — `A-1`'s
  `TestGlobalQueryFilters`, which passes in a suite and fails alone — is invisible to every one of them.
- **rejected:** root-causing the product per site. Unbounded across 302 sites, and the wrong target — the
  question is whether the *test* is honest, not why the engine is wrong.
- **rejected:** trusting the gate's existing prose. That prose is precisely what rotted: 49 sites carry a
  description in place of a reference, and two pilot gates turned out to be mis-scoped to every provider
  (`P1` defect 3).
- **why this:** the new attribute *defends* whatever a gate declares — a still-failing test is reported as
  expected, forever, in green. Migrating a test that fails for an invalid reason converts a latent bad test
  into a permanent assertion that the bad behaviour is correct. The pilot already produced one instance:
  `ToolsTests.TestGlobalQueryFilters` could never have served as a regression test (`A-1`), and only running it
  solo exposed that.
- **run once before being written down** (`SQLiteTests.cs:799` `Issue3766Test2` vs issue 3766, 2026-09-07,
  two reads): V1 needed rewording as a result. The issue reports `UNIQUE constraint failed` from
  `InsertOrReplace` over a `DateTimeOffset` primary key on SQLite.Classic; this test does `Insert` then
  `Update` and asserts one row affected, so its *error string* will not resemble the issue's at all while its
  *defect* — the key value not round-tripping on that provider — is identical. A V1 phrased as "the message
  matches the issue" would have produced a `wrong-issue` verdict on a correctly-attributed site. V2 passes
  (`cnt == 1` after an update by primary key is neither vacuous nor over-specific), V3 passes (Classic
  provider, `DateTimeOffset` key, plus an inline-parameters axis), and V4 passes and is *informative*: the
  gate names `AllSQLiteClassic` while the test runs on `AllSQLite`, matching the issue's own "when using the
  MS implementation this is not a problem". Verdict `matches`. Cost: two reads.
- **failure mode of the choice:** V1–V4 are judgement calls and 302 of them will not be uniformly good. The
  per-site record keeps the reasoning and the confirming quote, so a reviewer can overturn one without
  re-deriving it, and `TO-15` samples them rather than asserting they are all right.

### D-17 — A gate that fails for only some values of a non-provider parameter is split, not expressed

- **chosen:** where a swept site fails for some values of a `[Values]`-style axis and passes for others
  (`U-24`), split the test: the existing body becomes a plain method and two **thin proxies** carry the
  `[Test]` attributes, one per value, so a provider-scoped gate lands on the failing proxy alone (user,
  2026-09-08: *"new tests could just be thin proxies to main method"*).
- **rejected:** giving `ActiveIssueNew` a value-targeting dimension, as `ThrowsWhenAttribute` already has
  (`parameterName` + `ExpectedValue`, `ThrowsWhenAttribute.cs:14-30`). The precedent and the argument lookup
  both exist, so this was the cheaper-looking option — but it widens `AppliesTo` to a second axis, and every
  site that uses it hides the split from the test list rather than making it visible.
- **rejected:** leaving such sites on the old attribute. It blocks `SC-8` and keeps `ActiveIssueAttribute`
  alive past the cutover, which is the whole point of the phase.
- **why this:** the two halves *are* different tests — one is a known defect, the other is passing coverage —
  and splitting says so in the test list, where a reader sees it. The proxy keeps the body single-sourced.
- **failure mode of the choice:** the affected population is unknown until each parameterised gate is swept,
  so the split work cannot be estimated up front, and each split renames a test — orphaning its baselines,
  which the release flow regenerates (`P10`).

## P6 Edit-points

- E-1 `Tests/Base/Attributes/ActiveIssueNewAttribute.cs` (new) — `NUnitAttribute, IApplyToTest, IWrapSetUpTearDown`, `AllowMultiple = true`; ctors `()`/`(int)`/`(string)`; `Details`/`Configuration`/`Configurations`/`SkipForLinqService`/`SkipForNonLinqService`; `ErrorType`/`ErrorTypeName`/`ErrorMessage`; pure statics `AppliesTo`, `Matches` and **`Decide(innerState, innerMessage, winner, isRemote) → (state, message)?`**; nested `DelegatingTestCommand` reduced to a thin shell over `Decide` under `BeginDeferred`/`CommitDeferred`
- E-2 `Tests/Base/Attributes/ActiveIssueAttribute.cs:106-137` — force-fail mode: drop the `RunState.Explicit` write, add `IWrapSetUpTearDown` calling `ActiveIssueSentinel.Format`. **Applied locally, never committed** (D-6)
- E-3 `Tests/Base/TestProgressState.cs:46-82,203-267` — `_inconclusive` field, `Inconclusive` property, `case` in `Book` and `Unbook`
- E-4 `Tests/Base/TestProgressReporter.cs:258-285` — emit `inconclusive` in the heartbeat JSON
- E-5 `Tests/Linq/Infrastructure/TestProgressStateTests.cs:226,273-288` — inconclusive booking + re-book cases; partition invariant and `Recorder` tuple updated
- E-8 `Tests/Linq/Infrastructure/ActiveIssueNewTests.cs` (new) — `Decide` matrix (SC-1/2/3/3b), `AppliesTo` matrix incl. LinqService and null-provider, precedence/overlap, `ActiveIssueSentinel` round-trip
- E-9 `.claude/scripts/active-issue-triage.ps1` (new, corpus) — sentinel parser mirroring `TryParse`, per-site grouping, suggested annotation
- E-10 `Tests/EntityFrameworkCore/Tests/IssueTests.cs` — 18 gates triaged
- E-11 `Tests/EntityFrameworkCore/Tests/ToolsTests.cs` — 6 gates triaged; the `TestGlobalQueryFilters` gate at `:270-272` sits inside `#if NET8_0_OR_GREATER` and the condition must be preserved
- E-12 `Tests/EntityFrameworkCore/Tests/FSharpTests.cs:55` — dead gate (U-6); removed so SC-6 can reach 0
- E-13 `.claude/docs/testing.md:60,62,64,148` (corpus) — gate semantics and the heartbeat field list, falsified by E-1/E-4
- E-14 `.claude/scripts/test-status.ps1:83` (corpus) — print the `inconclusive` bucket in the one-line summary
- E-15 `Tests/Base/ActiveIssueSentinel.cs` (new) — committed `Format`/`TryParse` (D-7)
- E-16 (procedure, no file) — solo re-run plus bisect corroboration before any removal verdict (A-1, A-2)
- E-17 `Tests/EntityFrameworkCore/Models/Northwind/NorthwindContext.cs:ConfigureEntityFilter` — predicate reads the context property directly instead of a null local (A-4)
- E-18 `Tests/EntityFrameworkCore/Tests/CustomContextIssueTests.cs` — `Issue4669QueryFilterTest` + `Issue4669Context`, a deterministic #4669 repro on an isolated model (A-5)

### Phase 3

- E-19 `.claude/scripts/activeissue-census.ps1` (new, corpus) — resolves `TestProvName.All*`/`ProviderName.*`
  statically, classifies every site by the provider set it names, flags `Throws*` siblings and their overlap,
  and is the gate for `SC-8`/`SC-9`. Prototyped this session at `.build/.agents/activeissue-census.ps1`
- E-20 `Tests/Base/Attributes/ActiveIssueNewAttribute.cs` — sweep mode (`D-11`); `Throws*` deference (`D-10`);
  at cutover, renamed to `ActiveIssueAttribute` in a file of that name (`D-13`)
- E-21 `Tests/Base/Attributes/ThrowsWhenAttribute.cs` — one read-only `internal` predicate answering
  "does this instance govern the current case", extracted from the logic already at `:98-150` (`D-10`).
  No change to `ExecuteInner`'s decisions
- E-22 `Tests/Linq/Linq/**` — 166 sites / 46 files, the largest area; includes the 21 in `CteTests.cs`, the 10
  in `DateTimeOffsetTests.cs` and the three F#-backed gates in `FSharpTests.cs:167,450,458` (`U-18`)
- E-23 `Tests/Linq/DataProvider/**` — 60 sites / 19 files, incl. `OracleTests.cs` (13) and the per-type
  fixtures under `Types/`
- E-24 `Tests/Linq/Update/**` — 37 sites / 13 files; `CreateTableTests.cs:277` and `DeleteTests.cs:172` are the
  two cleanup hazards from `U-16`
- E-25 `Tests/Linq/UserTests/**` (16 / 12), `Tests/Linq/Data/**` (14 / 3, incl. the ten MARS gates),
  `Tests/Linq/Mapping/**` (5 / 3), and one each in `Extensions/`, `SchemaProvider/`, `Scaffold/`, `OrmBattle/`
- E-26 `Tests/Linq/Infrastructure/ActiveIssueConfigurationTests.cs` + `ActiveIssueGenericTests.cs` — deleted in
  the cutover commit (`D-12`), untouched before it
- E-27 `Tests/Base/Attributes/ActiveIssueAttribute.cs` — deleted at cutover (`D-13`)
- E-28 `Tests/Linq/Infrastructure/ActiveIssueNewTests.cs` — renamed with the type; gains the `D-10` deference
  matrix and, before `E-26`'s delete, whatever of the seven characterization permutations it does not already
  reproduce (`TO-10`)
- E-29 `.claude/docs/testing.md:64,66,68,85` (corpus) — the gate no longer hides a test from discovery, so all
  four claims are falsified: filter-by-fixture, gate-state reading, `AllowMultiple=false`, and the
  runtime-exclusion list
- E-30 `.claude/skills/enable-disabled-test/SKILL.md` (corpus) — the skill's premise is that a fixed issue's
  gate must be *found*; after the cutover a fixed issue announces itself as a Failure naming the site, which
  changes the skill's entry condition and most of its bisect rationale
- E-31 `.claude/agents/code-reviewer.md:175,235`, `.claude/docs/bug-investigation.md:401,405-420,424`,
  `.claude/AGENTS.md:86`, `.claude/docs/agent-rules.md:257,278`, `.claude/docs/kb-areas.md:63` (corpus) —
  each describes gating semantics that the cutover changes
- E-32 `.claude/scripts/active-issue-triage.ps1:286,323` (corpus) — emits `[ActiveIssueNew(` suggestions;
  renamed with the attribute
- E-33 `.claude/scripts/activeissue-census.ps1` (corpus, same file as E-19) — issue-attribution classification
  across seven classes (`int` / external URL / **linq2db URL as string** / `Details` URL / `[Test(Description)]`
  URL / name-only / unattributed), the closed-set `SC-14` gate over it, **`Details`-text parsing with a count
  per `E-35` prefix** (which is what makes `SC-15b`'s "the census counts those sites" an obligation rather than
  a wish — it read `Details` as a boolean before), and a cross-check that the migrated-site set equals `E-34`'s
  ledger key set, so a site with no ledger row cannot hide from `TO-15`'s sample. Prototyped and measured
  2026-09-07/08 (`U-21`, `U-23`)
- E-34 `.claude/plans/feature-activeissue-verify-attribute/ledger.json` (new, corpus) — the per-site audit
  record `D-15` and `D-16` both stake their failure-mode mitigation on: resolved reference and how, harvested
  failure, verdict, confirming quote. **Committed**, because the reviewer those decisions promise cannot open
  a gitignored `.build/.agents/` file on my machine — the corpus is the plan's own home and is where a
  reviewer already looks. The attribute stays the *runtime* truth; the ledger is the *audit* trail, and the
  two consumers are not the same. Sweep-time scratch still lands under `.build/.agents/`
- E-35 marker grammar in `Details`, since one string now carries several things — existing prose (27 sites), an
  `SC-9` waiver, an `SC-14` waiver, an `SC-15b` flag. **Three** prefixes, anchored at the start and
  **chainable**: `no-declaration:` (no failure could be harvested), `unvalidated:` (a `D-16` check could not be
  decided), `no-issue:` (searched, none exists — a *decided* verdict, so it must not be spelled `unvalidated:`).
  `no-declaration:` implies `unvalidated:` on V1, since there is no harvested failure to match, so the two
  co-occur and the census counts **per prefix**, not per site. Keep them terse:
  `ActiveIssueNewAttribute.cs:115-123` folds `Details` into `Reference`, echoed into every message the
  attribute writes (`:201,206,208`), so a search-term dump would surface in test output
- E-37 `Tests/Base/TestEnvironment.cs` — `ActiveIssueSweepVariable` / `ActiveIssueSweep`, the opt-in flag that puts
  `ActiveIssueNewAttribute`'s command into `E-2`'s sweep mode. Two lines beside the file's existing `IsEnabled`
  pattern; the sweep itself is `E-2`, which `P6` already authorizes
- E-38 `Tests/Linq/Data/DataConnectionTests.cs` — the ten Octonica MARS gates (`A-22`). Not covered by
  `Tests/Linq/Linq/**`, because `Data/` is a sibling directory; the change is to the tests' data-source lists
  rather than to an attribute, so it lands outside every other gate-bearing pattern in this block
- E-39 `Tests/Linq/OrmBattle/OrmBattleTests.cs` — `OrderByDistinctTest`, migrated in batch A (`A-17`); same
  reason as `E-38`, `OrmBattle/` is its own directory under `Tests/Linq/`
- E-36 `Tests/EntityFrameworkCore/Tests/FSharpTests.cs:55-58` — the pilot's deliberately bare gate records its
  rationale as a **comment**, which no gate can read; it needs `E-35`'s marker or `SC-9`/`SC-14` must be
  scoped to exclude it. Listing it here because `A-8` pre-seeded it as a waiver while `P6` did not authorize
  the file

## P7 Impact map (M/L)

- `Build/CI/run-provider-tests.sh:130`, `.github/workflows/build.yml:233`, `Build/Azure/pipelines/templates/test-workflow-{linux,windows}.yml`, `.runsettings` — searched `TestCategory` and `ActiveIssue` repo-wide: the only category expression is `!= SkipCI`; `"ActiveIssue"` is written (`ActiveIssueAttribute.cs:135`) and read nowhere — out-of-scope on this branch because E-2 is never committed (D-6).
- `Tests/Base/Attributes/SkipCategoryAttribute.cs:28,33` — searched `RunState` across `Tests/` (5 sites; critic's independent sweep agrees). The only other writer of `RunState.Explicit`; its guard short-circuits when `ActiveIssue` already set it. Zero `[SkipCategory(` usage sites exist — deferred: the guard's meaning changes only once E-2 is committed, i.e. on the `Tests/Linq` branch.
- NUnit `[Explicit]` — searched `\bExplicit\b` across `Tests/`: 6 sites, **none** overlapping an `[ActiveIssue]`. `ActiveIssueAttribute.cs:108`'s `RunState != Runnable` early-out is a read and stays — out-of-scope.
- `Tests/Base/TestProgressState.cs:226` `Book` / `:251` `Unbook` — mirrored pair; searched `TestStatus.` across `Tests/Base`. `Unbook` exists solely to reverse `Book`. Covered by E-3 (both arms).
- `TestStatus.|ResultState.|.Outcome|Result.Status` across `Tests/**/*.cs` (critic's sweep) — consumers are `ThrowsWhenAttribute`, `TestProgressState.Book/Unbook`, `TestProgressReporter:100,133`, `TestProgressStateTests`, `ExpectedExceptionAttribute` (0 usages). **No type-keyed helper or lookup keyed on status outside E-3's pair.** Covered by E-3.
- `BaselinesManager.cs:31` / `TestBase.cs:236` `FailCount` readers — searched `FailCount`. Both run in `[TearDown]`, i.e. *inside* the wrapper, so they observe the pre-rewrite result and a rewritten-to-Inconclusive test still skips its baseline dump — out-of-scope: existing behaviour, and the one we want.
- `.claude/scripts/test-status.ps1:83`, `.claude/skills/test-progress/SKILL.md:28`, `.claude/docs/testing.md:148`, `.claude/agents/test-runner.md:102,111` — searched `test-progress|passed|failed|skipped|completed` across `.claude/`. All parse JSON into a `PSCustomObject` or are prose, so an added field breaks nothing; `testing.md:148` enumerates the schema and becomes wrong — covered by E-13; `test-status.ps1` prints only three buckets — covered by E-14.
- `Tests/EntityFrameworkCore/Tests/CustomContextIssueTests.cs:26-32` — searched `EnsureDeleted|LastContexts` across the EF subtree. It **overrides `GetConnectionString` and calls `TestContextTracker.LastContexts.Remove(connectionString)`** with the comment *"as test corrupts database, we should mark it non-created for other fixtures"*, so the next fixture re-inits correctly. Out-of-scope — the earlier claim that it desynchronises the tracker was **false** and the sharding rule it justified has been withdrawn.
- `Parallelizable|LevelOfParallelism|NonParallelizable` across `Tests/EntityFrameworkCore` — none; `ResourceLaneDispatcherInstaller.TryInstall` is called only from `Tests/Linq/TestsInitialization.cs:225`. Localized — searched the EF subtree and `Tests/Base`: **the EF assembly runs sequentially**, so no interleaving hazard between EF fixtures.
- `Tests/EntityFrameworkCore/ContextTestBase.cs:53-66,102-103` + `TestBase.cs:168-238` — searched `EnsureDeleted|EnsureCreated|DB_SUFFIX`. One database per (provider, EF TFM) shared by all 14 fixtures, re-inited on fixture switch. Six of the 24 gated tests insert into shared pre-seeded tables with no cleanup then assert `.Single()`, so a *second* sweep of the same fixture without an intervening fixture switch is untrustworthy — deferred: a sweep-procedure constraint with no code change; enforced by TO-6's re-init rule.
- `ThrowsForProvider|ThrowsWhen|ThrowsFor` across `Tests/EntityFrameworkCore` — Localized — searched the whole EF subtree: **zero matches**, so the new attribute cannot collide with the throws-family in the pilot.
- Reflection consumers of the attribute type — Localized — searched `typeof(ActiveIssue|nameof(ActiveIssue|GetCustomAttributes<ActiveIssue` across the worktree (critic's independent sweep agrees): none anywhere in `Tests/`; hits only in KB prose.

### Phase 3 (searched 2026-09-07 against `ec83f3556` in the worktree, not the primary clone)

- Non-source references to either attribute — Localized — searched `ActiveIssue` restricted to `.csproj`, `.props`, `.targets`, `.yml`, `.yaml`, `.sh`, `.ps1`, `.runsettings`, `.editorconfig`, `.md` across the worktree: **zero matches**, so the rename is a `.cs`-only change inside the repo and every non-source consumer sits in the corpus — covered by E-29…E-32.
- Reflection consumers of either type — Localized — searched `typeof\(ActiveIssue|nameof\(ActiveIssue|GetCustomAttribute(s)?\s*<\s*ActiveIssue`: one hit, `ActiveIssueNewAttribute.cs:233`, the attribute reflecting for itself; nothing external binds either type by name — out-of-scope.
- The `"ActiveIssue"` NUnit category — Localized — searched `PropertyNames.Category|"ActiveIssue"|TestCategory` across `Build/`, `.github/`, `.runsettings` and `Tests/`: written at `ActiveIssueAttribute.cs:135` and `ActiveIssueNewAttribute.cs:36,222`, read only by the double-add guard at `ActiveIssueNewAttribute.cs:221`; every CI filter is `TestCategory != SkipCI` and `.runsettings` has no category filter, so the category is free for `D-9` to use as the local sweep filter — covered by E-19.
- `Tests/Base/Attributes/SkipCategoryAttribute.cs:28` — its `RunState.Explicit` guard means an `[ActiveIssue]` gate today silently suppresses a `[SkipCategory]` on the same test, and the cutover ends that suppression; searched `\[SkipCategory\(` across `Tests/`: **zero usage sites**, so the interaction is dormant in both directions — out-of-scope, recorded because the guard reads as load-bearing and is not.
- `RunState.` writers — Localized — searched `RunState\.` across `Tests/`: five sites, `ActiveIssueAttribute.cs:108` (read) and `:134` (write), `SkipCategoryAttribute.cs:28` (read) and `:33` (write), and `Tests/Linq/DataProvider/PostgreSQLTests.cs:199` (`RunState.Ignored` in a bespoke per-type `ITestBuilder`, unrelated); the cutover removes two of the five and nothing reads what they wrote — covered by E-27.
- `Throws*` co-sited with a gate — 13 methods, from the census's attribute-block scan cross-checked against an independent scout sweep: `AllAnyTests.cs:322`, `CteTests.cs:543,566`, `DateTimeFunctionsTests.cs:1484,1509`, `IntervalTranslationTests.Difference.cs:27,88,157`, `IntervalTranslationTests.Queries.cs:435`, `JoinTests.cs:3041`, `SelectQueryTests.cs:50`, `Update/DeleteTests.cs:590`, `Update/UpdateFromTests.cs:710` — six resolve provider sets on both sides with no overlap, seven use a subclass whose target set is computed internally and is unmeasured — covered by E-20/E-21 and TO-9.
- Other result-rewriting wrappers — Localized — searched `IWrapSetUpTearDown|IWrapTestMethod|DelegatingTestCommand|:\s*TestCommand` across `Tests/`: three, being `ActiveIssueNewAttribute:28`, the `ThrowsWhen` family (`ThrowsWhenAttribute.cs:12` + `ThrowsForProvider` → `ThrowsRequiresCorrelatedSubquery`/`ThrowsRequiredOuterJoins`/`ThrowsCannotBeConverted`), and `Tests/Linq/ExpectedExceptionAttribute.cs:11`, which is `IWrapTestMethod` and therefore nests *inside* both — it decides first and cannot be shadowed, and searching `\[ExpectedException` against the gate list found no co-siting — out-of-scope.
- `[TearDown]` observers of the pre-rewrite result — `TestBase.cs:236-243` **appends** the captured trace (`Message + "\r\n" + trace`), so a declared `ErrorTypeName` still matches by `StartsWith`, a declared `ErrorMessage` still matches by `Contains`, and the sentinel's 500-char cap keeps the head that carries both; `BaselinesManager.cs:31` reads `FailCount`, which is `U-17`'s basis; `TestProgressReporter.cs:98-100` is already deferral-aware (`TestProgressState.cs:164-179`) — out-of-scope, no change needed.
- Gates inside `#if` — searched `#if \w+` immediately preceding an attribute across `Tests/Linq`: four shapes, `Update/InsertTests.cs:27,69` and `Linq/MathFunctionTests.cs:248,330` (`#if AZURE`, attribute only), `DataProvider/SqlCeTests.cs:606` (`#if NETFRAMEWORK`), `Linq/ArrayTests.cs:164` (`#if SUPPORTS_DATEONLY`, whole test); the EF pilot already ships `[ActiveIssueNew]` inside `#if` (`IssueTests.cs:758,836`) so the form is proven, and an `#if AZURE` gate is unsweepable locally by construction (D-14, A-8) — covered by E-24 and E-22.
- Gates on abstract fixtures or overridden methods — Localized — searched the 103 gate files for `abstract class` and for an attribute immediately preceding an `override`/`virtual` declaration: no matches, and the one abstract fixture base `DataProvider/Types/TypeTestsBase.cs:18` carries no `[Test]` and no gate, so no site's targeting is inherited — out-of-scope.

## P8 Test obligations (M/L)

- TO-1 (SC-1) `ActiveIssueNewTests.Decide_PassingTest_IsFailure` — calls the pure `Decide` with an inner `ResultState.Success`; asserts `Failure` and that the message names the issue reference. Proof: **red→green against a named mutant** — `Decide` returning `null` for a Success input (equivalently `Wrap` returning `command` unchanged) must make it fail. A compile-red on a not-yet-existing file is *not* the red.
- TO-2 (SC-2) `…Decide_DeclaredError_IsInconclusive` — inner `Failure`/`Error` whose message matches `ErrorType` + `ErrorMessage`; asserts `Inconclusive`. Proof: **red→green** against the same named mutant.
- TO-3 (SC-3, SC-3b) `…Decide_DifferentError_IsFailure` plus `…Decide_InnerSkippedIgnoredWarning_PassesThrough` — the second asserts `Decide` returns `null` for each of `Skipped`, `Ignored`, `Inconclusive`, `Warning`. Proof: **control** — the same inner result is rewritten under TO-2's declaration and passed through here, so a `Decide` that rewrites unconditionally fails one of the two.
- TO-4 (SC-4) `…AppliesTo` matrix — the 7 targeting permutations re-derived (D-8 keeps the originals in place, so these are new), **plus** `SkipForLinqService`/`SkipForNonLinqService` (unreachable from EF, U-4) **plus** `provider == null` (D-1's failure mode) **plus** two-instance precedence and the equally-specific overlap case. Proof: **red→green** for the two-instance case; **characterization** for the 7 permutations, which must reproduce the old attribute's answers exactly.
- TO-5 (SC-5) `TestProgressStateTests.InconclusiveIsBookedInItsOwnBucket` **and** `…IsUnbookedOnRepeat` — the second is the symmetry guard on the unchanged `Unbook` path and must fail against a `Book`-only implementation, which is how D-4's rejected variant is shown wrong rather than argued wrong. Proof: **red→green**.
- TO-6 (SC-6) The EF sweep. **Inventory first** (U-8/U-9): seed the worktree's `UserDataProviders.json`; enable `SQLite.MS`, `PostgreSQL.16`, `SqlServer.2022.MS`, `MySqlConnector.8.0`, `MySqlConnector.5.7`, `MariaDB.11` in `NETFX`/`NET80`/`NET90`/`NET100`; start `pgsql16`, `sql2022`, `mysql`, `mysql57`, `mariadb`. Cells = provider × {EF3, EF8, EF9, EF10}, minus MySQL on EF10 (`#if !NET10_0`). Each run **asserts a non-zero discovered case count** — a bucket with no enabled provider yields zero EF cases and reports as a pass, which is the vacuous green this obligation exists to exclude. Then per site: run, harvest, annotate, re-run after an intervening fixture switch. Proof: **red→green** per site.
- TO-7 (SC-7) `…SentinelRoundTrip` — `ActiveIssueSentinel.Format` fed a message containing `|`, `%`, CRLF and a non-ASCII char, asserting a single line out and `TryParse` recovering every field. Proof: **control** — the same assertion must fail against an unescaped formatter. This is testable only because D-7 moved the formatter into committed code (E-15).

### Phase 3

- TO-8 (SC-9) The census becomes the gate — `E-19` grows two assertions (zero old-attribute sites; every gate carrying an error declaration or `E-35`'s anchored `no-declaration:` marker) and exits non-zero on either, so the exemption is machine-checkable at the site. Proof: **red→green against a mutant inserted into the real tree** — a hand-added bare gate with no declaration and no waiver must make it exit non-zero and removing it must make it exit 0, because a green run over a corpus assembled by hand proves nothing.
- TO-14 (SC-14) `E-33`'s attribution gate over **both** attribute names, with a **closed accepted set** — `attribution ∈ {explicit, external-url}` or `Details` opens with an `E-35` prefix; every `recoverable-from-*` and `unknown` row exits non-zero. Proof: **red→green against four named mutants**, one per classifier arm the gate must catch — a bare `[ActiveIssue]`, a prose string with no marker, a linq2db tracker URL passed positionally (`EagerLoadingTests.cs:757,823`), and a linq2db URL one field over in `Details` (`OracleTests.cs:4481`); three of the four passed the pre-repair gate, and the accepted set has to be stated as closed or the fourth still would. Baseline, whole-corpus and measured 2026-09-08: 353 sites = 94 explicit / 35 external-url / 2 linq2db-url-needs-int / 81 description / 2 details-URL / 35 name-only / 104 unattributed; of the 302 live old-attribute sites in `Tests/Linq` that is 59 / 33 / 2 / 80 / 2 / 35 / 91.
- TO-15 (SC-15, SC-15b) The `D-16` verdict is recorded for every site in `E-34`, and a sample is **re-derived by a different model** — the mechanism `P12` already relies on — reading the issue and the test but not the recorded reasoning. Sample is **stratified**: per *issue* for V1/V3/V4, which are properties of the issue-to-test relationship and would otherwise over-sample #3015's 21 `CteTests` sites and miss every single-site issue, and per *site* for V2, which is a property of one assertion. Proof: **control with a declared threshold** — ≥ 2 disagreements in a 20-item sample sends the whole batch back for re-derivation rather than being reported and absorbed; the pair the control needs is the recorded verdict against the blind one, and the run says which.
- TO-9 (SC-11) `ActiveIssueNewTests.Defers_ToGoverningThrowsAttribute` — the `D-10` matrix: `Throws*` governs and the gate applies (gate defers), `Throws*` does not govern (gate decides), neither applies, both apply on *different* providers. Proof: **red→green** against a build without the deference check, which must decide the first case as `Failure` ("test passed but is marked") because the `Throws*` wrapper rewrote the inner failure to Success — plus an end-to-end **control** on `IntervalTranslationTests.Queries.cs:435`, the one site where the two attributes actually contend (`U-15`), because a control on a disjoint pair such as `SelectQueryTests.cs:50` produces identical results in both builds and therefore measures nothing. **The unit half is done** (2026-09-08): `Decide_ThrowsAttributeGoverns_*` pass, and building the mutant — `if (false && throwsGoverns)`, since a bare `if (false)` is `CS0162` under warnings-as-errors — reddened those two tests and **only** those two, out of 31. The e2e half is **blocked on a provider**: that site's `Throws*` targets Access, Informix and SqlServer≤2014, of which Informix is the ACP-broken client (`A-13`), SqlServer 2014 has no container here, and Access is netfx/ODBC — so it lands with that site's migration or on CI, not before.
- TO-10 (SC-13) Before `E-26`'s delete, each permutation the two self-test fixtures encode is named against the `ActiveIssueNewTests` case reproducing it and any gap is filled first — `ActiveIssueConfigurationTests`' seven targeting permutations (which the critic mapped 1:1 onto the existing `AppliesTo_*` cases) **and** `ActiveIssueGenericTests.cs:7-40`'s five constructor/`Reference` permutations (none/int/string × `Details`), which the current matrix exercises only through the single `"1234"` case at `:43`. Proof: **characterization** — each must return the answer computed from `ActiveIssueAttribute.cs:114-121,126-130`, not the answer the new implementation happens to give.
- TO-11 (SC-8) The cutover's objective gate — a Release build of `Tests.Base`, `Tests.Linq` and the four EF projects on every TFM they target, plus a census run before and after the rename. Proof: **control** — the two census outputs differ only in the attribute-name field, so a count that moves means the script rewrote something it should not have.
- TO-12 (SC-10) A full CI run on the branch once every batch has landed: zero `[ActiveIssue]`-attributed Failures on any leg. Proof: **control** — `U-20`'s measured trx (`outcome="NotExecuted"`) is the mechanism, and the pilot's 24 migrated gates running green on every leg is the corpus-scale reference. Permission-gated (`D-9` batch C).
- TO-13 (SC-12) A unit test in `E-28` asserting sweep mode is off when its variable is unset and naming the variable, plus `git show HEAD -- Tests/Base/Attributes/` read against `P6`. Proof: **red→green** — the test must fail against a build whose sweep mode defaults on. The phase-2 formulation (`git diff HEAD` plus a clean `git status`) cannot say no: a clean tree makes the diff empty by construction, so it would pass whatever the committed default is.

## P9 Verification gates

- G-01: **pass** — per obligation:
  - TO-1 `Decide_PassingTest_IsFailure` — proof observed: with MUTANT-A (`Decide` returns `null` for `TestStatus.Passed`) built in, this test and only this test went red; reverted, green again.
  - TO-2 `Decide_DeclaredError_IsInconclusive`, `…WithMessageFragment…` — green; same mutant build discriminates.
  - TO-3 `Decide_DifferentErrorType_IsFailure`, `…DifferentErrorMessage…`, `Decide_InnerNonVerdictOutcome_PassesThrough` (4 cases) — control satisfied: the same inner result is rewritten under TO-2's declaration and passed through here.
  - TO-4 `AppliesTo_*` (7) + `SelectGoverning_*` (3), incl. LinqService both directions and the null-provider case.
  - TO-5 `InconclusiveIsBookedInItsOwnBucket` + `InconclusiveIsUnbookedOnRepeat` — proof observed: MUTANT-B (Inconclusive case removed from `Unbook`) reddened the second and only the second, which is what shows D-4's rejected Book-only variant wrong by measurement rather than by argument.
  - TO-6 **pass** — 24/24 live EF gates triaged; `git grep -c "\[ActiveIssue[(\]]" -- Tests/EntityFrameworkCore` returns 0. Post-annotation run: EF10 62 cases 0 failed / 51 inconclusive, EF8 102/0/82, EF9 102/0/82, EF3 95/13/67 where all 13 failures are `SQLite.MS`, the documented net462 `e_sqlite3` gap (memory `reference_ef3_net462_sqlite_native`), not a mismatch. Non-zero case counts observed per leg, so no leg reported a vacuous green.
  - TO-7 `Sentinel_RoundTripsAwkwardCharacters`, `…AbsentProviderAndTypeRoundTripAsNull`, `…LongMessageIsCapped`, `…RejectsForeignLines`, `…ExtractsExceptionTypeButNotAssertionProse`.
- G-02: **corrected — it was never `n/a`.** The gate originally read *"EF tests do not write `linq2db.baselines` SQL files … the EF projects produced no baseline output during any sweep"*. False: CI produced [linq2db.baselines#2108](https://github.com/linq2db/linq2db.baselines/pull/2108), 959 files under EF configuration directories (`SQLite.MS.EF8/`, `SqlServer.2019.MS.EF10/`, `PostgreSQL.13.EF10/`, …). **206 added**, all attributable to tests that now run: `Issue4662Test` (59), `Issue4669QueryFilterTest` (53, new), `Issue4333Test` (38) and `TempTableSurvivesAcrossCommands` (38) from the re-scope, `TestGlobalQueryFilters` (12), `Issue4643Test` (6). **753 modified**, all `enableFilter`-parameterised Northwind tests (`TestContinuousQueries`, `TestEager`, `TestInclude`, `TestIncludeString`, `TestLoadFilter`, `TestNestingFunctions`, `TestGlobalQueryFilters`, `NavigationProperties`) — the A-4 fix. Sampled `TestGlobalQueryFilters(PostgreSQL.13,True)`: +2/−2, the never-assigned local's redundant third filter parameter `@ef_filter__p7` collapsing into the existing `@ef_filter__p5`. Every change reconciles to an intended one.
- G-03: n/a — no new public surface; `Tests/**` ships in no package
- G-04: n/a — no `Source/` change, so no ApiCompat baseline movement
- G-05: **pass** — `Tests.Base` built clean on `net462` and `net10.0` explicitly, and via the EF projects on `net8.0` (EF8) and `net9.0` (EF9) — all four TFMs it targets.
- G-06: **pass** — `git diff HEAD --stat` covers 6 files, all in `P6`; no reformatting of untouched lines. `ActiveIssueAttribute.cs` is absent from the diff, which is the proof that the force-fail edit (E-2, D-6) was reverted against HEAD rather than against the index.
- G-07: n/a — no playground involvement

### Phase 3 — all pending

- G-01: **blocked** — depends on TO-8…TO-13; no phase-3 code is written yet, and TO-12 additionally depends on a free CI plus a separate go-ahead
- G-02: **blocked** — depends on the sweep's `remove` verdicts; `U-17` bounds the diff to surprise-passes rather than 302 sites, with the pilot's 206 files as the reference shape
- G-03: n/a — `Tests/**` ships in no package
- G-04: n/a — no `Source/` change
- G-05: **blocked** — depends on the cutover commit; the four-TFM Release build is TO-11
- G-06: **blocked** — depends on the final commit; TO-13
- G-07: n/a — no playground involvement

## P10 Adjudicated (M/L)

- ~~**The 315 `Tests/Linq` gates are out of scope for this branch.**~~ **Reversed 2026-09-07** by user
  decision — *"just use 5882 branch, no need multiple branches for same task"*, with the cutover explicitly
  included. The original reasoning (committing `E-2` reddens every gate) still holds and is why `E-2` is still
  never committed and `D-11` replaces it with an off-by-default mode. Reviewers of #5882 should expect the
  attribute, the EF pilot, 302 migrated `Tests/Linq` gates and the rename in one PR.
- **Both `ActiveIssueAttribute` and `ActiveIssueNewAttribute` exist simultaneously after this branch,** with duplicated targeting logic. The rename/delete is the final cutover and needs all 340 sites migrated first.
- **`ActiveIssueNew` is a deliberately ugly name** — the user specified it, to be renamed at cutover.
- **The 12 self-test fixtures keep their `[ActiveIssue]`** (D-8) — they are the tripwire for a missed force-fail revert, not oversight.
- **The MySQL gates' CI-vs-local wording gap is accepted** (U-9): the pilot enables all three MySQL servers locally so an `ErrorMessage` is not generalised across them from a single observation.
- **Over-baselining is not a problem** — the release flow resets `linq2db.baselines` to the anchor commit.
- **#4643 and #4662 are closed, milestoned 6.2.0, citing #5393.** Bisected to `aae685c02` ("Added TypeMapping
  conversion usage", 2026-03-04) against its parent `4c1f1988a` (#5392) — adjacent commits, so the transition
  is pinned. Both failed at introduction (`b7de32bf4`) with issue-specific errors, so the gates were justified
  when written and the removals are correct.
- **Two #4669 tests are deliberately left ungated: `ToolsTests.TestGlobalQueryFilters` and
  `IssueTests.Issue4669Test`.** Both fail only in isolation and pass in any full run, so an `ActiveIssueNew`
  would report "test passed but is marked" and turn CI red. `CustomContextIssueTests.Issue4669QueryFilterTest`
  (E-18) carries the regression coverage instead, and is gated. Do not flag the two ungated ones as missing
  gates.
- **#4669 is not fixed and is not a bisect candidate.** Root cause measured: EF Core's own
  `RelationalSqlTranslatingExpressionVisitor.VisitUnary` on a query filter reading a shadow property via
  `EF.Property`; no linq2db frame in the stack. Scope measured across six providers: MySqlConnector 5.7/8.0
  and MariaDB.11 fail, SQLite / PostgreSQL 13,14,16 / SqlServer 2022 pass — so the original `AllMySql` scope
  was correct.
- **Phase-3 CI facts are stale and must be re-derived.** `.github/workflows/{build,tests,tests-comment}.yml`
  exist on this base; the Azure-only picture recorded above predates them.
- **Phase-3 CI facts, recorded now because they were measured now:** both CIs run tests on this base and a `/azp run` comment starts both, duplicating the 15 Linux legs; Azure is authoritative for Windows/netfx/x86. No per-test artifact is published for the provider suites — the only `.trx` artifact is `cli-test-results-*` (`build.yml:237-242`) and `Tests/LinqToDB.CLI` has zero gates. `Build/CI/report-trx.ps1:86-96` writes one markdown line per failed test into `$GITHUB_STEP_SUMMARY` **uncapped** (only the `::error::` annotations are capped, at 10), so ~1200 failures will approach GitHub's 1 MiB limit. `retryCountOnTaskFailure: 2` plus `run-provider-tests.sh:140`'s `attempts=3` are uncapped by failure count and will re-run guaranteed-red Oracle/Access legs three times against a 180-minute timeout. **CI passes no `--test-progress`**, so the heartbeat bucket is a local-sweep instrument only.

## P11 Amendments (M/L)

- A-1 **A `PASSED` cell is not evidence until the test has also been run in isolation.** The sweep ran a
  filtered subset (`TestCategory=ActiveIssue`), and in-process state left by earlier tests can hide a
  failure: `ToolsTests.TestGlobalQueryFilters` passes in a 64-test fixture run and fails solo with
  `System.Diagnostics.UnreachableException`, masked by `NavigationProperties` alone (bisected from 46
  candidates; `TestToList`, `TestAssociations`, `TestInclude` do not mask it). Every `remove` verdict and
  every provider listed under `passesOn` therefore needs a solo re-run before it is acted on. Applied
  retroactively: `Issue4643Test` and `Issue4662Test` were re-checked solo and hold.
- A-2 **A `remove` verdict must be corroborated by a bisect that finds a fail→pass commit.** If no such
  commit exists, the gate never demonstrated the issue and the test is the defect, not the product. Adds
  `E-16` (no code change; a procedure step recorded in `P8`/`TO-6`).
- A-3 **A gate that is inert today is migrated, not deleted.** The four `#if EF10` filter gates in
  `ToolsTests` were removed as "structurally dead" because EF10 excludes MySQL, then restored as
  `ActiveIssueNew`: the exclusion is `#if !NET10_0` with the comment *"provider need update for v10"*, so it
  is temporary, and deleting the gate would leave the tests unguarded the moment MySQL returns to net10.0.
- A-4 **`Tests/EntityFrameworkCore/Models/Northwind/NorthwindContext.cs:ConfigureEntityFilter` added to
  `P6` as E-17.** Its predicate read `IsSoftDeleteFilterEnabled` through a local initialised to `null` and
  never assigned, so the `enableFilter` parameter every `NorthwindContextTestBase` test passes was inert.
  Fixed to reference the context property directly, matching the `IsFilterProducts` filters in the same
  file. Approved by the user; `ToolsTests` is 64/0 green with it. Independent of #4669, which reproduces
  with or without it.
- A-5 **`Tests/EntityFrameworkCore/Tests/CustomContextIssueTests.cs` added to `P6` as E-18** — a
  deterministic #4669 regression test on its own `DbContext`. The shared-model test cannot serve as one
  (see A-1). Minimal trigger, established empirically: a **shadow** property (`e.Property<bool>("IsDeleted")`)
  reached through `EF.Property` in a `HasQueryFilter`. An earlier attempt using `EF.Property` against a real
  CLR property did **not** reproduce. No joins, no soft-delete machinery and no Northwind model needed.

- A-6 **"No baseline output observed" is not evidence that a suite writes no baselines — check that capture
  was on.** `BaselinesManager` writes nothing when `BaselinesPath` is unset or its directory is absent, and it
  fails silently, so a local sweep reports exactly what a genuinely non-emitting suite reports. G-02's original
  `n/a` came from sweeps run before that directory existed on this machine; CI, where capture is always on,
  produced 959 files. Load-bearing for the `Tests/Linq` phase: 315 gates, and every one that starts passing
  emits baselines it has never emitted, so that branch must confirm capture is live **before** reading a
  no-output result as a verdict.

- A-7 **Phase 3 folded into this branch, cutover included** (user, 2026-09-07). Three decisions taken in one
  exchange: the work stays on `feature/activeissue-verify-attribute` rather than getting its own branch off
  master; the scope is *all* remaining sites **plus** the rename/delete cutover; and the sweep starts with the
  gates naming 1–3 providers because CI is busy — *"ci busy right now, so first try to sweep tests that have
  1-3 providers with active issue"*. Adds `SC-8`…`SC-13`, `U-12`…`U-19`, `D-9`…`D-14`, `E-19`…`E-32`,
  `TO-8`…`TO-13`, and a phase-3 `P7`. **The 2026-09-05 approval covers phase 1–2 only; phase 3 is unapproved
  until the critic has run on the delta and the user has seen the verdict.**
- A-8 **Waiver list (`D-14`) — one pre-seeded entry, and it is not in `Tests/Linq`.** `Tests/EntityFrameworkCore/Tests/FSharpTests.cs:58` already carries a bare `[ActiveIssueNew(4646)]`, deliberately and with its reasoning at the site: the file is behind `#if EF8`, `EF8` is defined only in `Source/LinqToDB.EntityFrameworkCore.EF8.csproj`, `DefineConstants` do not cross a `ProjectReference`, so it compiles into no assembly and has never been observed running. That rationale is a **comment**, which no gate can read — so the site needs `E-35`'s marker (now `E-36`) or `SC-9`/`SC-14` must be scoped to exclude it; as drafted, `TO-8` went red on it. Corrects `E-12`, which records this gate as *removed*; it was **converted** in `7f5b6182d`. The four `#if AZURE` gates (`Update/InsertTests.cs:27,69`, `Linq/MathFunctionTests.cs:248,330`) are **not** waiver candidates — `Tests/Directory.Build.props:16-18` defines `AZURE` for `Configuration == 'Azure'`, which both CIs build (`tests.yml:64`), so they are producible on CI and belong to batch C.
- A-10 **Two requirements added by the user on reading the phase-3 draft (2026-09-07), with the rest approved.** (1) *"each test attributed to existing issue explicitly using attribute parameter, when it not so and issue known, e.g. from test/fixture name"* → `SC-14`, `D-15`, `E-33`, `TO-14`, sized by `U-21`. (2) *"test logic should be checked to make sense and to match issue report, because it is possible to have test that is fail (or pass) only because it is an invalid test/assert"* → `SC-15`, `D-16`, `TO-15`. The second is the larger of the two by far and changes what phase 3 *is*: not a mechanical migration but a per-site audit of ~87 known issues plus whatever the 122 unattributed sites resolve to, with the migration as its output. It is also the requirement that makes the new attribute safe — a gate that defends an invalid assertion in green is worse than the discovery-hiding it replaces.
- A-16 **Derive an `ErrorMessage` fragment from the raw message, never from a rendered one — batch A, 2026-09-08.** Both SqlCe gates were annotated `ErrorMessage = "should be 0 but was 1"`, read off a `-replace '\s+',' '` view of the trx. Shouldly renders the expectation over four lines — `should be` / `0` / `but was` / `1` — so that fragment appears nowhere in the real message and both sites came back `Failure: Expected … but found …` on the confirming run. Fixed with the placeholder form the repo already supports (`ThrowsWhenAttribute.MessageMatches` turns `{0}` into `.*?` under `RegexOptions.Singleline`): `"should be{0}0{1}but was{2}1"`. Two procedural consequences: read the fragment out of the trx's raw `ErrorInfo/Message`, and prefer placeholders wherever an assertion library wraps. **Recurrence, ClickHouse cohort:** this rule was written down and then violated three more times in one batch — `count should be…` (the real text breaks after `count`), `Expected Was !` (breaks after `Was`), and `Code: 60. DB::Exception: Unknown` (Octonica omits the code prefix the other two clients keep). Every one came from reading a `-replace '\s+',' '` rendering, which is the *default* shape of my extraction. The rule is therefore not "remember to check the raw text" but **the extraction itself must not collapse whitespace when its output will become a declaration** — a habit cannot beat a default. **A third form, from the YDB cohort:** derive the fragment from *every* observed case, not one, because the direct and remote runs can differ in **content** and not merely in wrapping — `DeleteMany2` reports `Constraint violated. Table: \`/local/GrandChild\`` directly and `…Table: \`/local/Parent\`` over LinqService, so a fragment naming the table matched one transport and failed the other. The stable part was the failure mode (`Conflict with existing key.`), which is the right thing to pin anyway. The confirming re-run is what caught it, which is `TO-6`'s per-site red→green doing its job rather than a lucky glance.
- A-17 **Batch A closed: six sites, six outcomes, loop proven.** `Issue3766Test2` split under `D-17` and gated on the failing proxy; `Fts3SegDirTableQuery` and `OrderByDistinctTest` migrated with observed declarations and `no-issue:` markers, both queued for the per-case batch (`A-12`); `LetTest1`'s gate **removed** as stale; both SqlCe sites migrated against #3444. Census after: old-attribute sites 314 → **308**, migrated 39 → **44**, `SC-9`/`SC-14` violations **0**, markers 1 `no-declaration` / 6 `no-issue`. All six re-run green (four Inconclusive, two passing ungated). One unexplained event, recorded rather than chased: `Explicit_Contains` exited `-532462766` (unhandled CLR exception) once, immediately after another SqlCe run in the same loop, and did not reproduce — most likely two runs against one `.sdf` file, and unrelated to the annotation, which the re-run then verified.
- A-13 **The `environment` verification ran, and it split the population it was supposed to confirm (2026-09-08, `informix14` + `Informix.DB2` on net10.0).** Of the eight "Used docker image needs locale configuration" gates, six do fail on codepage conversion — `IBM.Data.Db2.DB2Exception : ERROR [IX000] A codepage conversion problem occurred creating this message` — so the claim holds for them; but `BulkCopyAllTypesProviderSpecific` and its async twin fail on `Assert.That(list, Has.Count.EqualTo(…)) Expected: 2 But was: 1`, **silent row loss in provider-specific bulk copy**, which is not a locale symptom at all and is a candidate product defect. Two consequences. First, `D-16`'s V1 earns its place on the first population it was pointed at: a shared prose string covered two unrelated failures, and only running them separated the two. Second, the codepage message is the driver failing to render *the server's own error text*, so the real underlying failure is masked — fixing the locale is a prerequisite for learning what these tests actually hit. `DB2CODEPAGE=1208`, the documented fix for DB2 proper on this machine, changes nothing here (measured, identical failures). **Nor does the fix the gate itself prescribes, in any of four spellings.** `informix14` was recreated from `Data/Setup Scripts/informix14.cmd` — databases re-created by `informix_init.sql` under the server locale each time — as: (a) stock, no locale env; (b) `DB_LOCALE=en_us.utf8 CLIENT_LOCALE=en_us.utf8`; (c) the same plus `LANG=en_US.utf8`, which the image cannot resolve (`locale: Cannot set LC_CTYPE to default locale`); (d) `DB_LOCALE=en_US.utf8 CLIENT_LOCALE=en_US.utf8 LANG=C.UTF-8 LC_ALL=C.UTF-8`, where the locale *does* resolve (`LC_CTYPE="C.UTF-8"`). All four produce byte-identical failures, as does client-side `DB2CODEPAGE=1208`. **Root-caused, and it is neither the container nor the product.** The client driver's own `db2diag.log` (`C:\ProgramData\IBM\DB2\C_Worktrees_…_clidriver\db2diag.log`, written by the failing run) records `CLI_utlConvertCP` failing with `sqlcode: -332`, `sqlstate: 57017`, `sqlerrmc: 65001 1202` — no conversion available between code page **65001 (UTF-8)** and **1202 (UTF-16)** — and no other SQLCODE appears anywhere in the log, so there is no masked server error behind it. This machine has the Windows "use UTF-8 for worldwide language support" option enabled: `ACP=65001`, `OEMCP=65001`. The DB2 CLI driver takes the system ACP as its application code page and cannot convert it to UTF-16, which is a known incompatibility of that driver with the UTF-8 ACP setting. So the eight gates blame a docker image for a **defect of this workstation's locale configuration**, and their local failure says nothing about whether the tests pass anywhere else. `DisableUnicode=1`, the CLI keyword aimed at exactly this, is not settable on the connection string — the driver rejects it with `ArgumentException: Invalid argument` and the connection dies before any test logic runs. It belongs in `db2cli.ini` inside the `Net.IBM.Data.Db2` NuGet cache, which is machine-global and shared with every other build on the box, so it is out of scope to touch. Consequence for `D-9`: **these eight sites must be swept on CI, not here**, and their local result is inadmissible.
- A-15 **`D-9`'s negative control is too weak, shown by `A-13`.** The control rejects a provider's sweep output unless that provider's `CreateDatabase` case passed in the same run. On the Informix ACP failure `CreateDatabase` **passed**, and 252 `TestDateTime` cases passed with it, while a specific data path failed for a reason that has nothing to do with the product — so the control would have admitted eight worthless annotations. A per-provider smoke test cannot detect a per-data-path client defect. Strengthen it to: any provider whose sweep produces a failure whose text names a *client driver* conversion, locale or codepage error is quarantined for CI, not annotated locally. So the gate's prose is not merely imprecise, it is **unactionable as written**: the configuration it names is now in place and the tests still fail. All eight are `needs-investigation` rather than `environment`. The two row-loss ones were written up here as "a product defect unrelated to any locale" — **withdraw that**: once the root cause turned out to be a client-side UTF-8↔UTF-16 conversion gap, silent loss of the one row carrying non-convertible data is a plausible second face of the *same* defect, and nothing measured separates the two hypotheses on this machine. Worth noting what *does* pass on that container — `CreateDatabase` and 252 `TestDateTime` cases — so this is specific to these tests' data, not a broken provider.
- A-14 **How to make a gated test actually run, measured 2026-09-08 — and a correction to my own first reading of it.** Filtering `--filter "Issue1307Tests"` ran 252 `TestDateTime` cases and **none** of that fixture's four gated tests, a green run that says nothing; `--filter "Test_Insert"` and `--filter "BulkCopyAllTypes"` ran them and failed as expected. I first wrote this up as `testing.md:64` being backwards. It is not: that entry documents the same asymmetry correctly and prescribes the fixture filter for the *opposite* goal — confirming a gate **skips** — while explicitly stating that naming the test forces `RunState.Explicit` tests to run. The error was mine, applying skip-confirmation advice to a harvest. What `E-29` owes the doc is therefore an **addition**, not a fix: the sweep direction — harvesting a gated test's real failure requires selecting it **by name**, which is what makes a local batch sweep possible without the force-fail edit at all. One further measured caveat: `--list-tests` *does* list gated tests under a fixture filter, so a listing is not evidence that a run will execute them.
- A-12 **Dispositions the user took on the measured population, 2026-09-08.** The ~45 `limitation` sites are **not** auto-converted: *"I need to decide per-case in batches"* — so `D-16` presents grouped candidates with their evidence and the call is the user's, which also keeps `D-10`'s `Throws*` route from being applied wholesale by a sweep. The ~16 `environment` sites get a **repair attempt before a write-off**: *"as we use same image locally - makes sense to verify locally and see if it can be fixed"*, and the local `informix14` container is the same image the eight locale gates blame, so the check is available here. Both change `D-16`'s routes, not its checks.
- A-11 **Second critic round, on `A-10`'s two requirements only — verdict `refuted`, 2026-09-07.** Three positive disproofs, each conceded and fixed: `TO-14` could not fail on the shape `SC-14` singles out, because the classifier called any URL external and two sites pass *linq2db's own* tracker as a string; `D-16`'s `needs-investigation` arm accepted a state `SC-15` forbids, with nothing committed to distinguish it (now `SC-15b`); and `D-15`/`D-16` both promised a reviewer a ledger that `E-34` had made gitignored (now committed to the corpus). The weakening objections produced the `limitation`/`environment`/`flaky`/`bad-test-data` verdicts, the run-based arm, `TO-15`'s threshold and stratification, `E-35`'s marker grammar, `E-36`, and an honest cost line. Four census defects it found are fixed and re-measured: the missing host check, the positional-argument heuristic that mis-read prose containing `=`, blindness to the 39 already-migrated pilot sites, and two false positives from the attribute's own message literals. Its reconciliation of my attribution figures — 59/35/35/80/93 across live sites — matched mine independently.
- A-18 **A fourth disposition arrived with the Sybase batch: *provider-specific assert* (user, 2026-09-08).** Asked to dispose of five Sybase groups, the user answered `provider-specific assert` twice, `activeissue` twice and *"check if assert correct and if so - activeissue"* once. It is not one of `A-12`'s routes and it is the strongest of them: where a provider's answer is *settled and known*, the test states that answer instead of being gated, so the case keeps running. Six gates went this way — the four `CharAsSqlParameter*` (Sybase cuts a parameter at the first 0x00 **and** returns the empty remainder as a single space, so the round trip yields `"0 "` / `" "` / `' '`) and the two `StringInterpolation*` (a null `MiddleName`'s `?? ""` slot reads as `" "`). Add it to `D-16`'s routes. **The second pair cost more than it looks:** the substitution cannot be hoisted into a variable, because that makes it a parameter, linq2db sizes a string parameter from its value, and ASE types `COALESCE` by the parameter's declared length — so `"Ko"` came back as `"K"`. Both fallbacks have to stay literals and the expected rows are rebuilt over a `Person` sequence that already reads the Sybase way. Verified green on `Sybase.Managed` with `SQLite.MS`/`SQLite.Classic` as controls.
- A-19 **`D-16` V1 earns its keep again: two Sybase gates named a cause that measurement refutes, and both hide a product defect.** `JoinTests.cs::SqlLinqCrossJoinSubQuery` and `MergeTests.Operations.Insert.cs::CrossJoinedSourceWithSingleFieldSelection` both said *"Cross-join doesn't work in Sybase"*, the second cross-referencing the first. A playground probe (`Sybase.Managed`, `SQLite.MS` control) measured the same cross join with `Take(10)` on both sides, neither, left only and right only: **119 / 119** without a `Take` — the cross join is fine, 7 × 17 — and **exactly 10** in all three arms that carry one. So ASE applies a derived table's `TOP` to the **outer** result, and any linq2db query with a `Take` inside a derived table silently returns at most *n* rows on Sybase. linq2db sets `IsSubQueryTakeSupported` and `IsCorrelatedSubQueryTakeSupported` false for Sybase but leaves `IsDerivedTableTakeSupported` at the base default of `true`; **flipping it was probed and is not the fix** — the query then fails to translate at all (`The LINQ expression could not be converted to SQL.`), because `IsWindowFunctionsSupported` is false so there is no `ROW_NUMBER` to emulate the paging with. The merge test is a *different* defect: it carries no `Take`, and the same cross-joined single-field projection run as a plain query answers 119 correctly, so the two rows are lost inside Sybase's `Merge` emulation — mechanism unidentified, hence `unvalidated:`. Both need issues; neither is in scope on this branch (`P3` forbids `Source/`).
- A-20 **Oracle-Devart (9 sites) is unmeasurable on this machine, like Informix's eight.** `CreateDatabase("Oracle.21.Devart.Direct")` fails with `Devart.Common.LicenseException : The license key is missing or not set up correctly`, so the whole cohort joins `A-13`'s CI-sweep bucket. Access, by contrast, turned out *fully* measurable in both driver families — `Access.Ace.Odbc` and `Access.Ace.OleDb` both initialise here — so seven Access gates were resolved on measured evidence, with only the two Jet halves (no DSN; Jet OLEDB 4.0 is 32-bit-only) reasoned from the same provider-level mechanism.
- A-21 **Two census defects found while wiring `TO-15`'s ledger cross-check, both silent.** The member scanner skipped lines starting with `[`, which is not the same as skipping an *attribute* — a sibling attribute wrapped over two lines left the scanner on its continuation, so three `ToolsTests.cs` sites were keyed `::ErrorTypeName = "Npgsql.PostgresException", …`; it also walked into a `/* */` block and keyed a `SchemaProviderTests.cs` site `::/*`. Now tracked by bracket depth with a block-comment arm. Separately the cross-check keyed the ledger by `file:line` while `E-34`'s schema says `file::member` — so it reported **every** migrated site missing, which reads as "the ledger is empty" rather than "the key is wrong". Keyed by member now, de-duplicated, since `AllowMultiple` means one method can carry several attributes and they share one audit row. Ledger after the Access and Sybase batches: **93 rows, 8 families, `ledgerMissing` 0**.
- A-22 **`U-25`/`U-26`'s blocker is resolved: the eleven hang sites are provider-excluded, on the user's call (2026-09-08).** `U-25` established that a hanging gate cannot be migrated under any declaration and left the disposition open; asked, the user answered *"H: yes, exclude"*. Ten Octonica MARS tests in `DataConnectionTests.cs` (Octonica/ClickHouseClient#59) and YDB's `AssociationTests.cs::GroupBy1` (#5597) now drop the provider from their data sources instead. **The mechanical shape is not uniform and the split is easy to get backwards:** five MARS tests take `[IncludeDataSources(...)]`, whose list *names* the providers to run, so the Octonica entry is commented out; the other five take `[DataSources(false, ...)]`, whose list is an **exclusion** list, so the entry is *added*. The file's own idiom sanctions it — `//ProviderName.ClickHouseDriver` already sits commented out of several of the same lists. Verified in both directions per the runtime-guard rule: `--provider ClickHouse.Octonica` now resolves **zero** MARS cases and returns in 8 s instead of hanging, and a control run on `ClickHouse.MySql` + `SQLite.MS` still executes all ten, 12/12 green. `GroupBy1` likewise resolves no YDB case and the run returns. Each site keeps its reference in a comment so the gap stays recorded.
- A-23 **`A-18`'s new disposition applied a third time, and `D-16` V1 caught another refuted gate.** `Issue2832Tests.cs::TestIssue2832` was gated `5590` with *"YDB does not support correlated subqueries … surfaces as a generic conversion error"*. Measured, there is no conversion error and **the query is never executed** — the test only builds SQL and counts accessible sources, asserting `sourcesCount <= 2`; YDB gives 5. So the cited issue (the YDB "could not be converted to SQL" one) does not apply, though the named *cause* does: `IsSupportedSimpleCorrelatedSubqueries` is false there, so the optimizer cannot collapse the subqueries. Resolved as *provider-specific assert* (user: *"Y: assert"*) — the bound is 5 on YDB and 2 elsewhere. Green on YDB direct and remote. Third gate this session whose prose the measurement refuted, after `A-19`'s pair; the running count is what makes `D-16` V1 worth its cost rather than a formality.
- A-24 **Three files were edited outside `P6` before `-Action reconcile` was run, now authorized as `E-37`–`E-39`.** `TestEnvironment.cs` (the sweep-mode flag), `Tests/Linq/Data/DataConnectionTests.cs` (the MARS exclusions) and `Tests/Linq/OrmBattle/OrmBattleTests.cs` (batch A). All three are the same oversight: `P6`'s directory globs are `Tests/Linq/{Linq,DataProvider,Update,UserTests}/**`, and `Tests/Linq/` has **more** subdirectories than those four — `Data/`, `OrmBattle/`, `Mapping/`, `SchemaProvider/` all carry gates. The glob list was written from where the *first* batches' sites happened to live, not from an enumeration of gate-bearing directories, so it will keep under-covering as the sweep moves outward. Reconcile after each batch rather than at the end. This amendment voids that part of the approval.
- A-9 **Critic round on the phase-3 delta, 2026-09-07 — verdict `weak`, nine objections, all folded in above.** Four changed the design: batch C moved to a scratch ref (`D-9`) after the critic showed the original wording was unsatisfiable against `P3`+`D-6`+`D-11`; `TO-9`'s end-to-end control moved off a disjoint site that could not have failed; `D-10` gained the remedy for a never-exercised `Throws*` expectation; `TO-13`'s instrument was replaced because it could not say no. Three were factual corrections I verified at source: `ThrowsRequiresCorrelatedSubqueryAttribute.cs:13-15` (all 13 co-sited sets resolve, one overlaps), `Tests/Directory.Build.props:16-18` (`#if AZURE` is CI-producible), `FSharpTests.cs:58` (converted, not removed). One prompted a probe that **refuted** the objection's premise while confirming its method — `U-20`. One found a defect in the census script itself, fixed before it becomes `TO-8`'s gate (`U-16b`).

## P12 Critic verdict (M/L)

**weak** — `plan-critic` on Fable, one pass. Nine objections; the design survived, the test plan did not.

**Accepted and fixed:**

1. *SC-6's metric matches the migrated sites* — `\[ActiveIssue` is a prefix match that counts `[ActiveIssueNew(`, so the criterion could never reach 0. Now `\[ActiveIssue[(\]]`, with E-12's outcome stated. (This error was mine and was also in the census command.)
2. *The `CustomContextIssueTests` `P7` row was false* — verified against `CustomContextIssueTests.cs:26-32`: it **does** clear `TestContextTracker.LastContexts`. Row corrected, TO-6's sharding rule withdrawn.
3. *TO-1..3 had no mechanism* — a gated test that passes is `Failure` by construction so it cannot sit green in the suite, and a nested `NUnitTestAssemblyRunner` shares the static tracker and would fire `MarkDone` on the outer run. Resolved by extracting a pure `Decide` (E-1) and testing at that level, with the `Wrap`-pass-through mutant named as the red.
4. *TO-7 could not exist* — its subject lived in never-committed code with no Pester harness. Resolved by D-7/E-15 moving the formatter into committed `Tests/Base`.
5. *The pilot's runnable cells were not inventoried* — TO-6 now carries the full setup list plus a non-zero-case-count assertion. The critic also surfaced that CI runs EF MySQL on **three** servers (5.7, 8.0, MariaDB 11), so U-9 enables all three locally.
6. *D-5's mitigation named no mechanism* and the natural one (`[Order]`) violates D-5's own contamination argument — now two filtered runs per provider.
7. *E-6/E-7 removed the only guard on `P3`'s first constraint* — the 12 fixtures fail loudly when the old gate stops applying, which is exactly what a botched E-2 revert looks like. Now D-8: leave them untouched; `P6` lost two edit-points.
8. *No arm for an inner Skipped/Ignored/Warning result* — the copied pattern reports Ignored as Failure. Now SC-3b + U-11 + TO-3's second case.
9. *D-4's motivation was not delivered by `P6`* — `test-status.ps1` still printed only pass/fail/skip. Now E-14. The critic also established that **CI passes no `--test-progress`**, which narrows D-3's claim to local runs.

**Carried forward unresolved:** U-10 — the MTP/NUnit3TestAdapter mapping of `Inconclusive` to exit code and summary bucket is still `reasoned, unprobed`; the critic could not check it either (no adapter source on disk). It is now a probe scheduled **before** E-1 is written, and the branch's mergeability depends on it.

**Critic's own strongest finding in favour:** D-1's runtime targeting survived every consumer sweep — no type-keyed helper, no second wrapper, no reflection reader — and `P1` defect 3 is real and cited.

### Phase 3 delta

**weak** — `plan-critic` on Fable, one pass, 2026-09-07. Nine objections; the design survives, four of its
mechanisms did not survive unchanged. Reconciliation is `A-9`; the objections are folded into the blocks they
attack rather than summarised here, per the amendment they produced.

What the critic searched, so a later round does not re-derive it: all five `Tests/Base/Attributes/Throws*.cs`
and each of the 13 co-sited methods at its cited line, resolving `UnsupportedDifferenceProviders` /
`NoTickTotalProviders` (`IntervalTranslationTests.cs:220-234`) and the `TestProvName.All*` sets by hand;
`report-trx.ps1` and `run-provider-tests.sh` in full plus `tests.yml:1-70,340-399`,
`test-workflow-linux.yml:160-185`, `default.yml:1-45` (establishing that `pr:` covers `release` only, so a
batch push does not auto-run CI); `\[(Retry|Repeat)\(` and `\[ExpectedException` across `Tests/`;
`class ActiveIssue\w*` for a rename collision (none); `GetEnvironmentVariable` across `Tests/Base`, which is
where `D-11`'s `TestEnvironment.IsEnabled` idiom came from; the census prototype in full; and a 1:1 mapping of
`ActiveIssueNewTests`' `AppliesTo_*` cases onto `ActiveIssueConfigurationTests`' seven permutations.

**Its strongest finding in favour:** `D-10`'s deference rule is correct under **either** NUnit nesting order —
traced against `ThrowsWhenAttribute.cs:163-187` and `ActiveIssueNewAttribute.cs:287-319` — which is what makes
`U-15`'s undocumented ordering a non-issue rather than a gamble.

### `A-10` requirements delta — two rounds

Standing verdict: **weak** (round 2, on the revision). Round 1 was `refuted` — three positive disproofs,
reconciled in `A-11`. Round 2 found all three answered, with three accounting defects left, each fixed in
place: `TO-14`'s accepted set was implied rather
than stated as closed and had no mutant for a linq2db URL sitting in `Details` (a fourth such site the earlier
count missed, so `SC-14`'s "2 sites" was really 4); `E-35`'s two start-anchored prefixes could not co-occur
although `D-14`'s own population needs both, and it mislabelled a *decided* `no-issue` verdict as
`unvalidated:`; and `SC-15b`'s "the census counts those sites" named no edit-point, the script reading
`Details` as a boolean. The critic's own whole-corpus attribution count — 104/94/81/35/35/2/2 = 353 — matches
the instrument's output exactly, which is the second time its independent count has corroborated mine.

**Where I did not accept it:** the objection that `SC-10`/`TO-12` rests on an unprobed trx mapping was right
that my evidence (green Azure legs) could not support the claim, and wrong that the claim was doubtful. Its own
recommended probe settled it in one run — `U-20`, `outcome="NotExecuted"` — so the mapping is now measured and
`report-trx.ps1` stays out of scope.
