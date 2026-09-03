## Test review checklist

Specific test-quality traps that the abstract "is there a test? does it cover the edge cases?" framing in [`code-reviewer.md`](../agents/code-reviewer.md) rule 6 misses in practice. Apply every item below to every test added or modified by a PR — most apply only when the test was added specifically as a regression test for the PR's fix.

### Substring SQL assertion must reject the bug, not just accept the fix

When a new/modified test calls `LastQuery.ShouldContain("X")` / `Assert.That(LastQuery, Does.Contain("X"))` / similar, mentally compute the **buggy SQL** (what was emitted before this PR's fix) and check whether the assertion *also* passes against that buggy form. If yes, the assertion is too weak:

- `Contains.Substring("FINAL")` passes against the buggy `mtFINAL` (no space) — should be `" FINAL"` or `"FINAL "`.
- `Does.Contain("now()")` passes against the buggy `timezone('UTC', now())` — should be `"timezone('UTC'"` or `Does.Not.Contain("timezone(")`.

Tighten the substring, anchor it (`StartsWith` / `EndsWith`), or invert (`Should.NotContain(<buggy-substring>)`). Flag as MAJ when the test was added specifically to prevent the regression this PR fixes — the test isn't doing its job.

### A baseline file is not an assertion

When a test's only pin on the SQL it generates is the captured baseline, nothing in the test *fails* if the SQL turns out wrong — the baseline simply records whatever was emitted and a reviewer has to notice. That is a weak pin in two specific ways: a value-only assertion frequently passes for SQL that is wrong (`Assert.That(result, Is.EqualTo("123"))` holds for `varchar(4)`, `nvarchar(10)` and `varchar(max)` alike), and a wrong baseline that was captured wrong *from the start* looks like the expected value forever after.

**Two mechanical facts settle the "but the baseline pins it" rebuttal** — which is what a reviewer reaches for when waving a weak assertion through, and it is wrong twice over. `BaselinesPath` is set only in the CI connection strings (see [`testing.md`](testing.md) → *How CI resolves test config*), so a **local** run captures and compares nothing: outside CI there is no pin at all. And on CI a changed baseline is a review signal on the baselines PR, not a failing test — someone has to notice it. So "the baseline captures this SQL" is never equivalent to "the test asserts this SQL", and a weak-assertion finding does not become void because a `.sql` file exists. (Surfaced on #5766: a review pass ruled a weak-assertion lead *checked-clean* on the reasoning that "the emitted SQL **is** pinned by the repo's standard mechanism… a wrong-table resolution therefore surfaces as a baseline diff" — the section above already forbids that inference, but not in terms that answered the rebuttal.)

Flag it when a test exists specifically to exercise how something renders — a type, a function, a hint, a dialect construct — but asserts only the round-tripped value. The fix is a `db.LastQuery!.ShouldContain(...)` on the part that matters, subject to the substring rule above. Assert the *distinguishing fragment* rather than the whole statement, so the assertion doesn't couple to per-provider rendering of the surrounding value.

(Surfaced on #5614: `SqlServerFunctionsTests.ConvertTest3/4` + `ConvertWithStyleTest4` had recorded a sibling test's `SqlType` on 20 of 22 SqlServer configurations, on `master`, for as long as the baselines existed — every assert was `Is.EqualTo("123")`, which passes for any string type, so nothing caught it. The maintainer's framing: *"as now it baselines-only source of truth"*.)

### `LastQuery` capture point

`DataConnection.LastQuery` updates on every `BeforeExecute`, including auxiliary `CreateLocalTable` / `AssertQuery` calls that materialize sources to memory or roundtrip data. If the test executes the target query *after* `AssertQuery` (or any helper that runs its own query), `LastQuery` will hold the last auxiliary query, not the target. The fix is to capture before the auxiliary call or to use a code path that runs only the target query (e.g. `.ToArray()` directly without `AssertQuery`).

### `context.IsAnyOf(ProviderName.X)` against versioned context strings

`ProviderName.MySql` etc. are bare names; the actual test context strings are versioned (`MySql.5.7`, `PostgreSQL.16`, `SQLite.Classic`, `ClickHouse.Octonica`). `IsAnyOf` is exact-match, so a check like `context.IsAnyOf(ProviderName.MySql)` will never fire — the test always falls through to the else branch silently. Use the `TestProvName.All<Provider>` aggregates instead (e.g. `TestProvName.AllMySql`), or list the specific versioned context names. Flag at the comparison site.

### Coverage matches the issue's reported provider

Cross-check the linked issue's reported provider against the test's `[DataSources(...)]` / `[IncludeDataSources(...)]` / `[ExcludeDataSources(...)]` filter. If the issue is reported for provider P and P is excluded (or not included), flag as MAJ regardless of whether the test passes in CI — the regression test isn't covering the regression's actual platform. Same applies when the issue's repro pattern (e.g. `OrderBy + GroupBy` or `Sum + nullable`) is missing from the test method body.

Extend the same cross-check to the **PR body's own enumerated claims**: when it states that several distinct code paths are affected, each needs a test that actually constructs it. The added **baselines are the cheapest evidence of which paths the tests reach** — a path the body claims is affected but that appears in none of the new `.sql` files is uncovered, however green the suite is. Weight it by symptom severity rather than by path count: the uncovered path is often the worse one. (Surfaced on #5801: the body stated *"Both the eager-load command and the main query's `EXISTS` are affected"*, but the main query in all 32 added baselines was a bare `SELECT … FROM [MainItem]` with no `EXISTS` — none of the four new tests carried a parent-level predicate over the association, which is both the issue's own repro shape and the direction whose pre-fix symptom was total row loss (`WHERE 1 = 0`) rather than merely wrong child rows. A probe test built from that shape was red on master and green at PR HEAD.)

### "Fails on provider X's CI leg" needs proof X actually runs

Before flagging that a `[DataSources]`/`[IncludeDataSources]`-parameterized test will fail on — or must exclude — provider X, confirm X is *actually exercised* in CI (or locally), not merely listed in `DataProviders.json`. A listing is not an active test leg: a provider can be present in the file but never run, so a "this `ShouldBe(1)` breaks the X leg, add X to the exclusion list" finding is moot — and worse, adding the exclusion disables a case that was silently passing. Verify the leg runs before raising the MAJ. (Surfaced on PR #5493: a "native Informix isn't excluded → red CI leg" MAJ was rejected — Informix/IDS isn't run on CI or locally.)

### Test member matches its name

When the test is named `TrimEndN` / `OrderByDesc` / `XyzAsync`, the LINQ projection inside should actually call `TrimEnd` / `OrderByDescending` / the `Async` variant. Mismatches make the test pass while not exercising the new path. Read the test body and confirm the method-under-test name appears at least once.

### `[DataSources]` parameter on regression tests

A regression test for a cross-provider bug needs a `[DataSources]` (or `[IncludeDataSources(...)]`) parameter, otherwise it runs against the default provider only and misses the providers where the bug actually manifests. New tests using `GetDataConnection()` / `GetDataContext()` without a `context` parameter are a red flag — read the surrounding fixture for the convention.

**Having a provider parameter is not enough — the gate has to match the defect's breadth.** An `[IncludeDataSources(...)]` whitelist on a bug that lives in *shared* code (expression building, the SQL AST, mapping) under-covers by construction, and it reads as deliberate because it names providers. Three checks, all cheap:

- **Compare against the neighbours.** When the same fixture region runs `[DataSources]` over the same model and the same `CreateLocalTable`, a new test in it wants the same, and a narrower gate needs a stated reason.
- **Prefer an existing capability attribute to a hand-written list.** `[InsertOrUpdateDataSources]` (all sources minus ClickHouse / YDB) and the `Tests/Base/Attributes/FeatureSources/` family already encode what a feature needs; a per-file `Feature*` constant, as `Tests/Linq/Update/*WithOutputTests.cs` uses, is the next choice. A bespoke include-list is the last.
- **Read the constant, don't infer it from its name.** `TestProvName.AllSqlServer2016` is *exactly* SQL Server 2016 ([`TestProvName.cs:166`](../../Tests/Base/TestProvName.cs)); the version-floor constant is `AllSqlServer2016Plus` (`:180`). The same `X` / `XPlus` / `XMinus` trap exists for every version-gated family.

Flag `MIN` with the wider gate named. (Surfaced twice on [#5840](https://github.com/linq2db/linq2db/pull/5840): six regression tests for a shared expression-building defect all carried `[IncludeDataSources(true, AllSQLite, AllSqlServer2016)]` — the plan had even instructed the `Feature*` pattern verbatim and it wasn't followed. Round 1's review flagged it and it went unapplied; round 2 re-found it and widening the gates to `[DataSources]` / `[InsertOrUpdateDataSources]` took the suite from 13 cases to 122 across nine providers — which is also what surfaced a PK self-assignment in the setters that YDB rejects outright.)

### A new exact-value test whose provider set spans flavors the author didn't verify

When a PR adds a test asserting *exact* types or literal strings per provider (a reader/type matrix, provider-specific formatting) and its `[IncludeDataSources(...)]` set spans distinct engine *flavors* — `MySql*` + `MariaDB`, `AllFirebird`, `AllSqlServer` across the MS/System providers, `ClickHouse` across its three drivers — check the PR body's "verified locally against …" list against that set. Flavors present in the attribute but absent from the verified list are an untested assertion, not coverage: same-family engines diverge on reader metadata even for identical SQL. Flag as MIN with the unverified flavor named.

Softer evidence than code, so keep it at MIN: the author may have verified more than they wrote down.

(Surfaced on #5678: `MySqlConnectorProviderSpecificReadMatrix` included `AllMariaDB` while the body listed only Oracle/DB2/PostgreSQL/DuckDB/Access as verified; MariaDB narrows `CAST(x AS SIGNED)` to `INT` where MySQL reports `BIGINT`, so two rows were wrong and the MariaDB leg was the build's only red job.)

### Time-based assertions / DB-server-vs-runner timezone

`Sql.GetDate()` / server-side `NOW()` / `CURRENT_TIMESTAMP` returns the DB server's local time, which may differ from the runner's `DateTime.Now` by hours when the DB runs in Docker or on a remote host. Assertions on:

- the wall-clock difference between server now and `DateTime.Now` (`Math.Abs((sqlNow - DateTime.Now).TotalSeconds) < N`)
- `result.Offset == DateTime.Now.Offset` for a `DateTimeOffset` round-tripped through the server
- equality of a stripped-TZ value to the original UTC value

are flaky in those setups. Flag and propose either a server-side-only comparison (`server local vs server UTC in one query`) or restriction to providers / contexts where the timezone is guaranteed to match.

### Identifier-length limits for `CreateLocalTable("name-with-guid")`

Firebird v3 caps identifiers at 31 characters; Oracle at 30 / 128 depending on version; SQL Server at 128. A test-name + GUID combination longer than the smallest provider's limit will fail at table creation on that provider. Either use `TestUtils.GetNext()` for short unique suffixes or let `CreateLocalTable` generate the name (no explicit name argument).

**But not in a test that captures baselines.** `TestUtils.GetNext()` is a process-wide counter, so the number it returns depends on how many other tests called it first. When the generated name reaches captured output — DDL in a schema-provider test, a table name in emitted SQL — that makes the baseline a function of execution order, and it drifts whenever the order changes (a new test, a reordering, parallel execution). Use a fixed per-test suffix instead: within one fixture the tests already differ by prefix, so a literal number per test gives all the uniqueness needed and is identical on every run. `GetNext()` stays correct when the name never reaches a baseline. (Surfaced on #5614: the five `Issue5628` PostgreSQL schema tests moved 62 baseline files purely because their sequence/table suffixes shifted from `_19` to `_109`.)

### `query.ToSqlQuery()` vs the SQL of an *aggregate* call

`IQueryable.ToSqlQuery()` returns the SQL of the non-terminal sequence — it doesn't include the terminal aggregate's wrapping. To assert SQL emitted by `query.Sum()` / `query.Count()` / `query.Min()`, capture from `db.LastQuery` *after* the terminal aggregate call, not via `query.ToSqlQuery()`. The latter will assert against the wrong SQL and pass for the wrong reason.

### `[TestFixture]` doubled on a partial class

A `[TestFixture]` attribute on the same partial class declared in two files runs the fixture's tests twice (or NUnit complains, depending on version). When the diff adds a new partial of an existing fixture, the new file should not re-declare `[TestFixture]`. Flag at the new attribute.

### Async test pattern

A test of an `Async` method that doesn't `await` the call (or doesn't return `Task` / `ValueTask`) exercises the synchronous fallback, not the async path. When the PR fixes an async-specific issue, confirm the test actually awaits.

### Inline per-provider gating where a FeatureSource attribute fits

When tests gate provider support *inline* — repeated `[DataSources(false, ProviderName.X, …)]` / `[ExcludeDataSources(...)]` skip-lists, or `context.IsAnyOf(...)` branches — scattered across many tests for the **same** feature, check whether `Tests/Base/Attributes/FeatureSources/` already has (or warrants) a feature-based context-source attribute for it: `SupportsAnalyticFunctionsContextAttribute` (window / analytic functions), `MergeDataContextSourceAttribute`, `CteContextSourceAttribute`, `RecursiveCteContextSourceAttribute`, `AllJoinsSourceAttribute`, and peers. Repeating the provider skip-list per test is the trap — it drifts as providers gain support, and it buries which providers genuinely lack the feature behind boilerplate. Flag `MIN` and point at the matching feature-source attribute; when none fits, suggest introducing one alongside the existing family rather than inlining the gate. (Surfaced on PR #5468 — window-function tests inline-gated providers instead of using a feature-source attribute, despite `SupportsAnalyticFunctionsContextAttribute` already existing.)

### Numeric assertions on sample statistical aggregates (STDDEV / VARIANCE) must relax the single-row window

When a test asserts the *value* of a sample stddev/variance window aggregate (`Sql.Window.StdDev`/`Variance`/`StdDevSamp`/`VarSamp`) across providers, the **single-row-window** result is engine-defined and not part of the sample-vs-population contract: it comes back NULL on PostgreSQL/DuckDB, `0` on Oracle/MySQL/SAP HANA/Informix, and `NaN` on ClickHouse. Asserting a fixed value (e.g. NULL) for the single-row case produces **false failures that fail fast on the first row and mask the real multi-row divergence** the test is meant to catch. Relax the n=1 case (accept null / ~0 / NaN) and assert strictly only for windows of **≥2 rows**, where sample (÷ n−1) and population (÷ n) genuinely differ — that is what discriminates a provider silently returning the population statistic for the documented-sample API. (Surfaced on PR #5468: an n=1-strict assertion flagged Oracle/SAP HANA as wrong when only their single-row convention differed; relaxing n=1 cleared them and pinned the real population bug to MySQL/MariaDB/DB2/Informix.)

### Execution-only test (`ToList()` / `_ =`) can't catch a wrong result

A test that only materializes the query (`_ = query.ToList()`, `.ToArray()` with no assertion) proves the SQL *executes*, not that the result is *correct*. When the feature under test has observable runtime semantics — row ordering, NULLS FIRST/LAST placement, rank/dense-rank values, aggregate values, filtered/partitioned counts — the test passes even when a provider's emulation produces the wrong rows. Flag `MAJ` when the test was added for a feature whose correctness is the point (a wrong emulation goes undetected), `MIN` otherwise; propose asserting the expected values against the materialized result, and confirm the seed data actually exercises the edge (e.g. a NULL in the ordering key for a NULLS-placement test). (Surfaced on PR #5468: the `*WithNulls` window tests set a `Sql.NullsPosition` and had a NULL-key seed row but only called `ToList()`, so a wrong per-provider NULLS emulation would not fail — result assertions were added and confirmed correct across ClickHouse/DuckDB/YDB/SQLite.)

### NUnit `Assert.*` in a new/modified test → prefer Shouldly

The repo standardizes on Shouldly for assertions (`AGENTS.md` → Tests; "Use **Shouldly**, not NUnit `Assert`"). Flag any new or modified test that uses `Assert.That` / `Assert.AreEqual` / `Assert.IsTrue` / `Assert.IsFalse` / etc. as `MIN`, and propose the Shouldly equivalent (`ShouldBe` / `ShouldBeFalse` / `ShouldBeTrue` / `ShouldContain` / …) plus `using Shouldly;` if the file doesn't already import it. Mixing styles in new coverage is the trap — it reads inconsistently and loses Shouldly's clearer failure messages. (Surfaced on PR #5468: `WindowFunctionsTests.RowNumber`/`Equality` shipped `Assert.That` and only an external bot flagged it; this checklist had no rule.)

### Process-global cache / state assertions need `[NonParallelizable]`

A test that asserts **process-global query-cache state** — an exact parameter count via `query.ToSqlQuery().Parameters`, a `Query<T>.CacheMissCount` / `GetCacheMissCount` delta, a compilation count — or that otherwise mutates/reads shared static state (clears the query cache, flips a static `Configuration.*` toggle) must carry `[Test, NonParallelizable]` so the parallel test dispatcher runs it on the exclusive write-lock lane. Without it a concurrent lane's query compilation perturbs the shared cache and the count assertion flakes intermittently — green locally / on a filtered run, red on the full parallel CI leg. Flag `MAJ` (it reddens CI non-deterministically). The cache-counter tests already carrying `[Test, NonParallelizable]` in `ParameterTests` (each with a one-line "relies on process-global query-cache state" comment) are the pattern to match. (Surfaced on PR #5614 build 22305: `ParameterTests.Caching` asserted a cache-derived parameter count — `ToSqlQuery().Parameters.Count.ShouldBe(1)` — but was the one such test missing the attribute, so a parallel lane promoted its cached plan to 2 parameters.)

### Shared mutable fixture/static state across concurrent invocations → per-invocation locals (not `[NonParallelizable]`)

Distinct from the cache-assertion rule above, and with a **different fix**. When a test **mutates and reads** a shared instance field (or static) that the fixture reuses across cases, and those cases run concurrently — either a `[DataSources]` / `[IncludeDataSources]` test whose provider contexts run in parallel, or a single test that itself spawns `Task.Run` workers — the shared field is a **data race**, not a cache flake. NUnit reuses one fixture instance across all its cases, so parallel contexts (and worker tasks) write each other's slots between a write and its read → corrupted, wrong-value results. `[NonParallelizable]` does **not** fix it (NUnit runs the non-parallel queue concurrently with `ParallelScope.All` workers, and sibling contexts of the same fixture still overlap); the fix is to make the state **per-invocation local**, threaded through the helper methods, so the test touches no shared instance state. Flag `MAJ` — it corrupts results non-deterministically on the parallel CI leg while passing filtered / local runs. (Recurring: the `Issue822Tests` / `Issue1373Tests` / `MappingSchemaTests.DoNotUseComplexAttributes` fields→locals offloads, and PR #5614's `ParameterTests.TestIQueryableParameterEvaluationMultiThreaded`, whose fixture `_params[thread]` array + `_cnt` counters were clobbered across concurrent SqlServer contexts → `Count 1 ≠ 3` on the EXTRAS leg, build 22320.)

**Exception — state that is shared *by design*: lock + publish-last, not locals.** Per-invocation locals are the fix when the sharing is accidental. When the shared field is an intentional **cache** that the fixture's cases are meant to reuse (an expensive one-time load amortised across every test in the fixture), locals would rebuild it per case and are the wrong answer. Then the requirement is that the cache be built and published **atomically**: take a lock around the whole lazy-init, build into locals, and assign the field(s) **last** — never publish a half-initialised object graph. The classic break is a multi-step init that assigns the field first and then keeps mutating what it points at, so a concurrent case sees "non-null, therefore ready" and reads a partially-wired graph. `??=` on several related fields has the same flaw: two cases can both see `null`, both build, and last-writer-wins leaves the fields mutually inconsistent. **Detector:** a fixture field assigned inside an `if (field == null)` / `??=` block that is followed by further mutation, and consumers comparing **by reference** (`a == b` on entity types with no `operator ==`) — reference comparison is what turns a torn init into a wrong result rather than a benign one. Flag `MAJ`. (PR #5614: `OrmBattleTests.Setup` published `Order` before wiring `o.Customer` / `o.Employee`, and `ComplexAllTest` — the only case in the fixture comparing navigation properties by reference — failed on both SQLite contexts with `expected.Except(result).Count() == 111`, build 22850.)

### Shared state keyed more coarsely than the test's lane

Both rules above assume the shared thing is a field of the *test*. The third shape is state a test reaches **through the context** — which reads like per-test state and isn't. The dispatcher serializes by **configuration** (`DatabaseLaneStrategy` keys the lane on the provider context), so anything keyed more coarsely than that, or reached by a path the classifier cannot see, is **not** protected by the lane and `[NonParallelizable]` is scheduling around it rather than fixing it. Flag `MAJ`. Two confirmed shapes:

- **Coarser key.** `db.DataProvider.SqlProviderFlags` is not per-context: provider instances are `static readonly Lazy<IDataProvider>` keyed by **(ADO provider, version)** (`SqlServerProviderDetector.cs`), so `SqlServer.Contained.MS`, `SqlServer.SA.MS` and `SqlServer.2019.MS` are three lanes sharing **one** flags object. Fix: construct a dedicated provider instance and set the flag in its ctor — the `LimitedColumnsSQLiteProvider` pattern in `EagerLoadingStrategyUnionTests`, used via `new DataOptions().UseConnectionString(dataProvider, GetConnectionString(context))`. (PR #5614: `Issue228Tests` set `MaxInListValuesCount = 1` around one query, and concurrent tests on sibling SQL Server configs rendered `x IN (1) OR x IN (2)` instead of `x IN (1, 2)` — 30 baseline files across two configs, present in one leg run and gone in the next.)
- **Invisible path.** Classification comes from the *parameter value* (`NUnitUtils.GetContext`), so a test taking `[DataSources(false)]` and then building `GetDataContext(context + LinqServiceSuffix)` in its body runs without the remote secondary mutex while writing the shared LinqService host state. Fix: `[UsesRemoteContext]`, now asserted at `ServerContainerBase.CreateContext`. (PR #5614: `AsyncTests.Test`/`Test1`/`TestForEach` — a remote test on another provider's lane lost a test-registered enum converter and read a `VarChar` column as numeric, failing once on `Firebird.3.LinqService` in build 22972.)

**Detector:** in test code, a write through `db.DataProvider.` or any `*Tools.GetDataProvider(...)` result; and `LinqServiceSuffix` appended inside a body whose parameter attribute is the non-remote overload. **Diagnostic signature** when it has already shipped: a *semantically neutral* difference (same results, different SQL), scattered across unrelated tests sharing only one construct, present in one run of a leg and absent the next — check the baseline file's own history on the branch before hunting for a source change.

---

Apply this checklist whenever rule 6 of `code-reviewer.md` fires — i.e. on any test file added or modified by the PR. Findings from this checklist go in the regular `findings[]` stream with severity per the per-item guidance (most are MAJ when the test fails to exercise its named purpose, MIN otherwise).
