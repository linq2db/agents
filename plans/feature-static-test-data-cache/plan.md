# Work plan: feature-static-test-data-cache — Static, run-wide snapshot of TestBase reference data

**Tier:** M  ·  **Status:** approved  ·  **Approved-at:** 2026-11-01 (after critic round 1)  ·  **Branch:** feature/static-test-data-cache
**Schema:** `.claude/docs/work-plan.md`  ·  **Gates:** `.claude/docs/definition-of-done.md`

## P1 Problem

GitHub run [41327800429](https://github.com/linq2db/linq2db/actions/runs/41327800429), leg `tests / Lin s_SQLite` (PR #6186 head 545a3505c, a PR with no `Parent` writes): 32 failures, all `Tests.Linq.InheritanceTests` (`Cast2`, `Test1`, `Test2`, `Test7`) on all 8 SQLite contexts, each `Expected: property Count equal to 8 / But was: 7` on `SELECT … FROM [Parent]` (log `.build/.agents/gh-41327800429/tests-Lin-s_SQLite.log:188078`). The expected side is the in-memory `Parent` cache; the database had the standard 7 rows.

Mechanism (code read, the race itself not reproduced):

- `TestBase`'s reference-data caches are **instance** fields (`Tests/Base/TestBase.Tables.cs:22-50,53-96,110-192,197-262,471-492`), so every fixture class loads its own copy from the **default** configuration (`new TestDataConnection()` → `DataConnection.DefaultConfiguration` = `SQLite.MS`, `DataProviders.json:26`) on first use — hundreds of loads per run.
- Under parallel lanes (#5614, `Tests/Base/DatabaseLaneStrategy.cs:14-28`) the load runs on whichever lane the triggering case is on, unsynchronised with the default provider's lane and with unkeyed (GatedInline) tests. Any default-DB writer that is mid-flight when a load runs — even one with `finally` cleanup — is captured into that fixture's expected data for the rest of the run. One bad snapshot fails every context of that fixture, matching the 32-failure shape.
- The row shape is pinned by which tests failed (measured, log grep `failed\S* (Test\d+|Cast\d+)\(`): only the unfiltered comparisons `Cast2`, `Test1`, `Test2`, `Test7` are red; `Test3` / `Test4` / `Test5` / `Test8` (filtered by `ParentInheritance1` / `!ParentInheritanceNull` / `ParentInheritanceValue`, `InheritanceTests.cs:35-86`) are not. A non-null `Value1` would have reddened `Test4`/`Test5` (classification at `TestBase.Tables.cs:236-240`), so the extra row had `Value1 = null` — consistent with a lane-keyed `SQLite.MS` writer such as `DeleteTests.cs:150,183,226` (`new Parent { ParentID = 1001 }`), `BulkCopyTests.cs:299` or `BatchTests.cs:33`, racing a load from another lane. The specific test is not identifiable (the log lists failures only).
- A second, unkeyed exposure of the same kind: `MappingTests.MyType3/4/5` (`Tests/Linq/Linq/MappingTests.cs:283-326`) insert `Parent` 1001 (`Value1 = 1001`) into the default DB and delete `>= 1000` in `finally`, running GatedInline concurrently with every lane and ignoring every latch. Not this incident's row (non-null `Value1`), but the same window.
- The loads also race the default provider's own `CreateDatabase` (it drops/recreates the tables; other lanes do not wait on its latch, `Tests/Base/TestBase.cs:189-193`), and `EnsureModel` writes cross-lane (`db.Child.Delete(c => c.ParentID >= 1000)`, `TestBase.Tables.cs:127`).

## P2 Success criteria

- SC-1 Reference data is loaded once per test process, not once per fixture instance: a second `TestBase` instance created after a transient extra `Parent` row exists in the default DB still sees the original row set. → TO-1
- SC-2 In a parallel `Tests` run where the default provider's `a_CreateData.CreateDatabase` runs, the reference data is captured exactly once, by that test, after its scripts finish and before its readiness latch is signalled; no getter loads lazily. → TO-2
- SC-3 Cache readers on other lanes do not read the default DB before that capture (they wait on the default provider's latch). → TO-2
- SC-4 Runs without the capture (serial run, `CreateDatabase` filtered out, `Tests.T4` / `Tests.Wasm` / `Tests.FSharp` hosts) still get the reference data via a locked lazy load. → TO-3
- SC-5 (hardening, not this incident's cause) `MappingTests.MyType3/4/5` no longer write the default DB from outside a lane; they still pass. → TO-4
- SC-6 `DataOptionsTests.OnTraceTest` / `OnTraceTest2` no longer write a cache backing field and still pass. → TO-5
- SC-7 No regression in tests consuming the caches. → TO-6

## P3 Constraints & anti-goals (M/L)

- Test infrastructure only: no change under `Source/`, no public API, no emitted-SQL text change. Baseline *keys* of `MyType3/4/5` move (default context → per-SQLite-context), see G-02.
- Do not change the dispatcher (`Tests/Base/Parallelization/*`), lane classification or readiness-latch semantics (`CustomTestContext`), or `GetCreateDatabaseProviders`.
- Keep the protected getter names and types on `TestBase` (`Types`, `Types2`, `Person`, `Patient`, `Doctor`, `Parent`, `Parent1`, `Parent4`, `Parent5`, `Child`, `GrandChild`, `GrandChild1`, `InheritanceParent`, `InheritanceChild`, `ParentInheritance*`) so no consumer edits.
- Out of scope: the per-context `DataCache<T>` / `GetTypes(context)` (`TestBase.Tables.cs:17-20,494+`) and `TestBaseNorthwind` (per context, read in that context's own lane); other unkeyed default-DB readers.
- Anti-goal: hand-fixing the ~11 files of lane-keyed `Parent` writers — they are serialized with their own lane and are not the defect.

## P4 Unknowns (M/L)

- U-1 Does any test mutate the cached lists or their elements (a static cache would leak it across fixtures)? — resolved-by scout: none; list mutators, indexer writes, element property writes, write-backs all 0 hits outside `TestBase.Tables.cs` (12 patterns + per-local 60-line scans over `Tests/**`). Only `DataOptionsTests.cs:69,79,92,104` assign the protected `_child` field.
- U-2 Does anything shadow the cached members or touch their backing fields elsewhere? — resolved-by scout: no `new`/same-name members in `TestBase` subclasses; backing fields referenced only by `DataOptionsTests` (above); no reflection.
- U-3 Which hosts run `TestBase` with the parallel dispatcher? — resolved-by scout: only `Tests/Linq` and `Tests/Tests.Playground` (links `TestsInitialization.cs` and `Create/CreateData.cs`, `Tests.Playground.csproj:11-12`). `Tests.T4`, `Tests.Wasm`, `Tests.FSharp` use `Tests.Base` without a SetUpFixture/dispatcher; `Tests/EntityFrameworkCore` has its own `TestBase`. Static fields are per process.
- U-4 Does the default provider always get a `CreateDatabase` case, and with what spelling? — resolved-by scout: `TestConfiguration.GetCreateDatabaseProviders` adds `DefaultProvider` first when not a user provider (`TestConfiguration.cs:252-253`); the case argument is the raw string, no remote variant (`CreateDatabaseSourcesAttribute.cs:10`). Edge: a user provider spelled with different case drops the default case entirely (`:255` is case-sensitive) — then no capture and SC-4's lazy path applies. Compare with `OrdinalIgnoreCase`.
- U-5 Is the moment between the default `CreateDatabase`'s last script and `MarkDatabaseReady` quiet for the default DB? — resolved-by scout: only for default-lane tests. Other lanes' cache getters (no wait today), unkeyed tests (`MappingTests.MyType3/4/5` writes; zero-row `ColumnAliasTests.AliasTest2`, `UpdateTests.CompiledUpdate`), and exclusive-lane `DataContextTests.TestNullConfiguration_*` (nulls `DataConnection.DefaultConfiguration`, `DataContextTests.cs:25-55`) can overlap. → D-2, D-3, D-4.
- U-6 Can a getter waiting on the default latch deadlock? — resolved-by scout + code read: `CreateDatabase` runs on an ungated lane holding no gate, throttle or mutex (`ResourceLaneDispatcher.cs:131-150,386-394`), so a waiter holding a read lock / throttle permit / the write lock cannot block it; `a_CreateData.RunScript` reads no cache getter. Wait is bounded (2 min, `CustomTestContext.cs:86`) with the same backstop `OnBeforeTest` uses.
- U-7 Does `AssertState` (opt-in, `TestBase.Asserts.cs:211-243`) still work? — resolved-by code read: it reads the same getters; it now compares against the run-wide snapshot, which is its intent (detect tests leaving shared tables changed). No edit.
- U-8 Do `MyType3/4/5` keep their meaning when keyed on a context? — resolved-by code read: they test `MyInt` ↔ `int` conversion on insert via `MyMappingSchema`; nothing depends on the default configuration specifically. On master they ran on `SQLite.MS` only. `[IncludeDataSources]` intersects with `UserProviders` (`IncludeDataSourcesAttribute.cs:24`), so a leg with no SQLite user provider no longer runs them (P10).

## P5 Decisions (M/L; rejected alternatives mandatory at L)

### D-1 — One static, immutable reference-data snapshot

- **chosen:** a private nested `ReferenceData` class built in one `Load(configuration)` call (all lists, association wiring, and the derived `Parent1/4/5`, `ParentInheritance*` lists computed eagerly), published through one `static volatile` field; every protected getter reads from it. Replaces `EnsureModel`, `InitPatientPerson`, the per-getter lazy fields, `_modelSync`, `_modelLoaded`.
- **rejected:** make each existing field `static` in place — keeps eleven independent unsynchronised lazy loads (`Types`, `Doctor`, `InitPatientPerson` have no lock today; `Person`/`Patient` can be wired from two different loads), and still loads at an arbitrary moment.
- **rejected:** per-lane item lock exposed by the dispatcher (option B offered to the user) — user chose the static snapshot.
- **why this:** one load per process, one publication point, no partially-built graph observable; user decision.
- **failure mode of the choice:** a test that mutates a cached object now corrupts every later fixture (U-1 found none; nothing prevents a future one). Eager load means a missing table in a custom default configuration fails the capture instead of only the getter that needs it.

### D-2 — Capture at the end of the default provider's `a_CreateData.CreateDatabase` body

- **chosen:** `a_CreateData.CreateDatabase` calls a new `protected static void CaptureReferenceData(string context)` on `TestBase` after its `switch`; it is a no-op unless `context` equals `TestConfiguration.DefaultProvider` (`OrdinalIgnoreCase`). The capture replaces any earlier snapshot.
- **rejected:** hook in `TestBase.OnAfterTest` before `MarkDatabaseReady` — fires for any `IsCreateDatabase` match (`NUnitUtils.cs:12-22` matches by parameter attribute, incl. `ParallelExecutionTests.CreateDatabaseTestIsClassifiedUngated`), runs even after a failed create, and an exception there would have to be kept from skipping `MarkDatabaseReady`.
- **rejected:** capture in assembly `OneTimeSetUp` — the in-memory default DB is preloaded there (`TestsInitialization.cs:247,372-423`) but `CreateDatabase` then drops and re-seeds it.
- **why this:** the body runs exactly once per provider, before `OnAfterTest` signals the latch, so default-lane tests are still blocked; a failed capture fails the `CreateDatabase` test visibly; a failed script skips the capture (lazy fallback).
- **failure mode of the choice:** unkeyed and exclusive-lane tests are not held back by the latch and can still write the default DB during the capture. The only unkeyed reference-row writers found (`MyType3/4/5`) are moved into lanes by D-4; any new unkeyed default-DB writer reopens the window. The incident's lane-keyed writer is closed by D-3, not here.

### D-3 — Getters wait for the capture, then fall back to a locked lazy load

- **chosen:** getter path: snapshot non-null → return. Else, when `ParallelExecutionEnabled` and `DefaultProvider` is set → `CustomTestContext.AwaitDatabaseReady(DefaultProvider)` (on timeout `MarkDatabaseReady`, mirroring `TestBase.cs:197-198`), re-check. Else / still null → `lock` + double-check + `Load`.
- **rejected:** lazy load only (no wait) — a once-per-run load still races the default `CreateDatabase` and default-lane writers; it only lowers the odds.
- **why this:** in-run, every other-lane reader is ordered after the capture; outside the parallel `Tests` host the old lazy behaviour remains.
- **failure mode of the choice:** when the default `CreateDatabase` is filtered out of a parallel run, the first getter on a non-default lane pays the 2-minute latch timeout once (default-lane tests already pay it today).

### D-4 — Key `MappingTests.MyType3/4/5` on SQLite contexts

- **chosen:** `[IncludeDataSources(TestProvName.AllSQLite)] string context` + `GetDataConnection(context)`; body otherwise unchanged. They then run in their provider's lane after its `CreateDatabase`, serialized with that DB's other tests.
- **rejected:** `[NonParallelizable]` — the exclusive lane still overlaps the ungated `CreateDatabase` (U-5), i.e. the capture.
- **rejected:** insert into a `CreateLocalTable` — still DDL + writes on the default DB from outside every lane.
- **rejected:** `[DataSources]` (all providers) — widens the matrix beyond what master ran; unmeasured on other providers.
- **why this:** hardening — removes the only unkeyed writers that can overlap D-2's capture (they are not this incident's row, see P1). The standard pattern for a shared-table writer; same provider family as master.
- **failure mode of the choice:** legs without a SQLite user provider stop running these three tests.

### D-5 — Connection names the configuration

- **chosen:** `Load` opens `new TestDataConnection(configuration)` with `TestConfiguration.DefaultProvider` (falls back to the parameterless ctor only if it is null).
- **why this:** `DataContextTests.TestNullConfiguration_*` null `DataConnection.DefaultConfiguration` on the exclusive lane, which can overlap the capture (U-5).
- **failure mode of the choice:** none known for named resolution. `DataContextTests.cs:43-44` also nulls `DefaultSettings` (non-netfx), but the setter's `Configuration.EnsureInit()` is a no-op on null (`Source/LinqToDB/Data/DataConnection.Configuration.cs:27-34,48-54`), so registered entries survive and `GetConfigurationInfo("SQLite.MS")` (`:348-358`) still resolves (code read by the critic, unprobed).

### D-6 — Keep `Child.Delete(c => c.ParentID >= 1000)` inside `Load`

- **chosen:** keep as the first statement of `Load`.
- **why this:** preserves master's leftover cleanup for file-based local DBs on the lazy path; at capture time it is a no-op on a freshly created DB. Removing it is a behaviour change nobody asked for.
- **failure mode of the choice:** on the lazy path it remains a write from an arbitrary lane — now at most once per process instead of once per fixture.

## P6 Edit-points

- E-1 `Tests/Base/TestBase.Tables.cs:ReferenceData` — new private nested immutable `ReferenceData` class + `Load(string? configuration)`; static volatile snapshot field + lock; `CaptureReferenceData(string context)`; all reference getters (`Types`, `Types2`, `Person`, `Patient`, `Doctor`, `Parent`, `Parent1`, `Parent4`, `Parent5`, `Child`, `GrandChild`, `GrandChild1`, `InheritanceParent`, `InheritanceChild`, `ParentInheritance`, `ParentInheritanceValue`, `ParentInheritance1`, `ParentInheritance4`) read the snapshot; remove the instance backing fields, `EnsureModel`, `InitPatientPerson`, `_modelSync`, `_modelLoaded` (incl. the now-stale comment block at `:101-109`).
- E-2 `Tests/Linq/Create/CreateData.cs:a_CreateData.CreateDatabase` — call `CaptureReferenceData(context)` after the `switch`.
- E-3 `Tests/Linq/Linq/MappingTests.cs:MyType3` — key on `[IncludeDataSources(TestProvName.AllSQLite)] string context`, `GetDataConnection(context)`; same for `MyType4`, `MyType5` (same file).
- E-4 `Tests/Linq/Infrastructure/DataOptionsTests.cs:OnTraceTest` — `_child = …` → `_ = …` (lines 69, 79, 92, 104; also `OnTraceTest2`).
- E-5 `Tests/Linq/Infrastructure/ReferenceDataTests.cs:ReferenceDataTests` — new fixture with the TO-1 test. Invariant the test must keep: the first getter read happens **before** the insert (that read waits for the capture under D-3), so the `[NonParallelizable]` insert can never overlap the ungated default `CreateDatabase` — the overlap D-4 rejects `[NonParallelizable]` for. Stated in a one-line comment at the read.

## P7 Impact map (M/L)

- `Tests/Base/TestBase.Tables.cs` backing fields / `EnsureModel` / `InitPatientPerson` outside the file — searched `\b(_types2?|_person|_patient|_doctor|_parent[0-9]?|_child|_grandChild1?|_inheritanceParent|_inheritanceChild|_parentInheritance\w*|_modelSync|_modelLoaded|EnsureModel|InitPatientPerson)\b` over `Tests/**/*.cs`: only `Tests/Linq/Infrastructure/DataOptionsTests.cs:69,79,92,104` — covered by E-4. (Same-named private fields in `AssociationTests.cs:626,662` and `DynamicColumnsWithoutStoreTests.cs:33-37` are unrelated entity members — out-of-scope.)
- Members shadowing the getters in `TestBase` subclasses — searched `new`-modifier and same-name member declarations over `Tests/**` (excluding generated/model): none in a `TestBase` subclass — out-of-scope.
- Mutations of cached lists/elements — 12 patterns (list mutators, indexer writes, element property writes, casts, write-back calls, statement lambdas) + per-local 60-line scans: 0 hits — out-of-scope (D-1 failure mode).
- Unkeyed default-DB writers to reference tables — searched every `new TestDataConnection()` / `new DataConnection()` / `GetDataConnection()` / `GetDataContext()` default-config shape (12 patterns) and read each candidate: `Tests/Linq/Linq/MappingTests.cs:289,305,320` (real `Parent` inserts) — covered by E-3.
- `Tests/Linq/Linq/ColumnAliasTests.cs:39-45` (`AliasTest2`, UPDATE with an unsatisfiable WHERE) — out-of-scope: changes no rows.
- `Tests/Linq/Update/UpdateTests.cs:917-922` (`CompiledUpdate`, UPDATE Person ID 12345, absent from reference data) — out-of-scope: changes no rows.
- `Tests/Linq/Update/InsertTests.cs:1158-1165` (`InsertOrReplaceWithIdentity`) — out-of-scope: throws during query build, no SQL reaches the DB.
- Lane-keyed `Parent` writers (`InsertTests`, `DeleteTests`, `UpdateTests`, `BatchTests`, `TransactionTests`, `IdlTests`, `CommonTests`, `MySqlTests`, `SqlServerFunctionsTests`, …) — searched `(db|dc|ctx)\.Parent\s*\.\s*(Insert|Update|Delete|Merge)|Into\(…Parent\)|\.Insert…\(new Parent\b` over `Tests/Linq`: 11 files — out-of-scope: serialized in their own lane; after D-3 no other-lane cache read reaches the default DB.
- `Tests/Base/TestBase.Asserts.cs:211-243` `AssertState` — reads the getters — out-of-scope: behaviour as intended (U-7).
- `Tests/Base/TestBase.cs:189-198,214-215` readiness wait / signal — reused, not changed — out-of-scope.
- `Tests/Linq/Infrastructure/ParallelExecutionTests.cs:48-66,119-125` — not a `TestBase`, does not touch `GetCreateDatabaseProviders` or pre-marking — out-of-scope.
- `Tests/Tests.Playground/Tests.Playground.csproj:11-12` links `TestsInitialization.cs` and `Create/CreateData.cs` — picks up E-2 automatically — out-of-scope (no csproj edit).
- Hosts without the dispatcher (`Tests/Tests.T4`, `Tests/Tests.Wasm`, `Tests/FSharp`) — searched `SetUpFixture|ParallelExecutionEnabled|ResourceLaneDispatcher` per project: none — covered by E-1 (lazy path, SC-4).
- `Tests/EntityFrameworkCore/TestBase.cs` — separate `TestBase`, does not use `Tests.Base` caches — out-of-scope.
- Case-insensitive default provider spelling dropping the default `CreateDatabase` case (`TestConfiguration.cs:252-255`) — deferred: pre-existing; E-1's lazy path covers it.

## P8 Test obligations (M/L)

- TO-1 `ReferenceDataTests` (new, `[NonParallelizable]`, unkeyed): read `Parent` count through a probe `TestBase` instance; insert `Parent` 1001 into the default DB; read `Parent` count through a **second, fresh** probe instance and assert it equals the first; `finally` delete `ParentID >= 1000`. Discriminating input: a fresh fixture instance created while the extra row exists — master reloads per instance (8 ≠ 7), the branch returns the snapshot (7). — providers: default configuration (`SQLite.MS`) — proof: red→green
- TO-2 Temporary, uncommitted instrumentation (a counter + `TestContext.Progress` line per `Load` call naming the caller path: capture / lazy, and whether `CustomTestContext.IsDatabaseReady(DefaultProvider)` was already true) on a parallel filtered run of `CreateData.CreateDatabase|InheritanceTests|MappingTests|JoinTests` on `SQLite.MS,SQLite.Classic`: expect exactly one `Load`, from the capture, with the latch not yet ready. Control: remove the E-2 call and re-run — expect one lazy `Load` instead. — providers: SQLite.MS, SQLite.Classic — proof: control
- TO-3 `Tests.T4` or `Tests.FSharp` host (no dispatcher) exercising a cache getter — lazy path; CI legs cover it. Locally: the TO-2 instrumentation with `CreateDatabase` filtered out shows one lazy `Load`. — providers: SQLite.MS — proof: characterization
- TO-4 `MappingTests.MyType3/4/5` pass on every SQLite context. — providers: SQLite.Classic, SQLite.Classic.MPU, SQLite.Classic.MPM, SQLite.MS — proof: characterization
- TO-5 `DataOptionsTests.OnTraceTest`, `OnTraceTest2` pass. — providers: default configuration — proof: characterization
- TO-6 Filtered regression run (≤ 1000 tests) of cache-heavy fixtures — `InheritanceTests`, `JoinTests`, `AssociationTests`, `SelectTests`, `SetTests`, `WhereTests` — on `SQLite.MS,SQLite.Classic`, same pass/fail set as master; full matrix on CI. — providers: SQLite.MS, SQLite.Classic — proof: characterization

## P9 Verification gates

- G-01: — (pending) — TO-1 red on master then green; TO-2 control observed both arms; TO-4..TO-6 via `/test`; plus `dotnet build Tests/Linq/Tests.csproj -c Release -f net10.0` (analyzers / XML docs on test edits) and `-f net462` (TFM API availability for the test projects).
- G-02: — (pending) — expect no baseline change; MyType3/4/5 baselines move from the default context to per-SQLite-context keys (review, not regenerate).
- G-06: — (pending)
- G-07: — (pending)
- G-09: — (pending)

## P10 Adjudicated (M/L)

- `MappingTests.MyType3/4/5` no longer run on legs without a SQLite user provider (`IncludeDataSources` intersects `UserProviders`). They exercise mapping-schema conversion, not a provider feature; every SQLite leg and the default local setup still run them.
- In a parallel run with the default `CreateDatabase` filtered out, the first non-default-lane getter pays the existing 2-minute latch timeout once (D-3), unless a default-provider test in the run already backstopped it. `/test` always injects the `CreateDatabase` filter. The case that does hit it: CI's MTP retry child (`.github/workflows/tests.yml:82`, `--retry-failed-tests 2`) re-runs failed tests by name without `CreateDatabase` — bound ≤ +2 min per retry child (≤ +4 min per red leg), on top of the per-lane 2-minute wait it already pays (`TestBase.cs:189-199`). Accepted: only red legs pay it, and pre-marking the latch would need run-filter introspection the harness lacks.
- Unkeyed / exclusive-lane tests are still not ordered after the capture. Only `MyType3/4/5` write reference rows (P7 sweep); zero-row UPDATEs are accepted.
- Shared cached objects across fixtures (D-1): no mutating consumer exists (U-1).

## P11 Amendments (M/L)

_None._

## P12 Critic verdict (M/L)

- Round 1 (2026-11-01, `plan-critic` on `fable`; fable contributed no design input in this session): **weak**.
  - Objection 1 — P1's named culprit contradicted by the log: `Test3/4/5/8/Cast1` absent from the 32 reds, so the extra row had `Value1 = null`, not `MyType3/4/5`'s `1001`. Verified by me (log grep + `InheritanceTests.cs:35-86`). Response: P1 / SC-5 / D-2 / D-4 re-attributed; D-4 kept as hardening; the incident's path is closed by D-3.
  - Objection 2 — P10 omitted the CI retry child (`tests.yml:82`). Response: listed with its bound in P10; accepted, not mitigated.
  - Objection 3 — TO-1 is a `[NonParallelizable]` default-DB writer, safe only by read-before-insert ordering. Response: invariant recorded in E-5, to be stated at the read.
  - Objection 4 — D-5's hedge settled by code (`EnsureInit` no-op on null `DefaultSettings`). Response: D-5 failure mode rewritten with the mechanism (still unprobed).
  - Minor — P3 vs G-02 on baselines. Response: P3 now says no emitted-SQL text change, keys move.
  - Critic searched: CI log reds by test, backing-field and mutation sweeps over `Tests/**`, every default-config connection site + writes in those files, `OneTimeSetUp` sites, `IncludeDataSourcesAttribute` / `GetDataConnection` remote handling, `DataProviders.json` in-memory names, `a_CreateData.RunScript` getter reads, dispatcher gating (`ResourceLaneDispatcher.cs:147-150,382-394`). Not checked by it: TO-1 red on master, retry-child cost on a real run, `BaselinesManager.Dump` for `provider == null`.
  - Strongest point per critic: capture inside the ungated default `CreateDatabase` + other-lane getters waiting on the same latch gives cross-lane happens-before with no new primitive, and closes the lane-keyed cause.
