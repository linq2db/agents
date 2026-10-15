# Work plan: infra-mysql-createdatabase-self-heal — MySQL CreateDatabase self-healing

**Tier:** M  ·  **Status:** approved  ·  **Approved-at:** 2026-10-15 (user)  ·  **Branch:** infra/mysql-createdatabase-self-heal
**Schema:** `.claude/docs/work-plan.md`  ·  **Gates:** `.claude/docs/definition-of-done.md`

Tier M rather than S: a one-file defect fix, but it has a plausible second location (patch the connection the script runs on vs. pre-create the database), which `work-plan.md` → *Tiers* routes to M.

## P1 Problem

`a_CreateData.RunScript` (`Tests/Linq/Create/CreateData.cs:60,69`) opens a connection with the config's own connection string, which names the database (`Database=testdata` / `testdataconnector`, `DataProviders.json:114-118,173-177`). `Data/Create Scripts/MySql.sql:1` is `DROP SCHEMA IF EXISTS \`{DBNAME}\``; the database comes back only at `:3` (`CREATE SCHEMA`). A run interrupted between those batches (measured by peer session linq2db-claude-e3, 2026-10-15, MySQL 8 container `mysql`: a ~34 s command timeout, `Connection must be Open; current state is Broken` after a 22 s DROP, container OOM-killed with exit 137) leaves the database missing, and every later `CreateData.CreateDatabase` on that provider fails at `db.OpenDbConnection()` with MySQL `1049 Unknown database 'testdata'` / `'testdataconnector'` — before the script that would recreate it runs. Recovery today is a manual `CREATE DATABASE` or the setup script.

## P2 Success criteria

- SC-1 With the configured database dropped, `CreateData.CreateDatabase` on a MySQL-family provider passes and leaves the database present and populated (a follow-up test on that provider passes).  → TO-1
- SC-2 With the database present, `CreateData.CreateDatabase` behaves as before: passes, same script, same session.  → TO-2
- SC-3 Non-MySQL providers' `CreateDatabase` paths are untouched (no edit outside the `AllMySql` case).  → TO-3

## P3 Constraints & anti-goals (M/L)

- `RunScript` and `Data/Create Scripts/MySql.sql` stay byte-identical: the script keeps running on a connection to the configured database, so the bulk-copy inserts and `{DBNAME}` resolution are unchanged.
- No change to `Build/Azure/scripts/mysql.sh` or `Data/Setup Scripts/*`; CI pre-creates the databases, and the new step is a no-op there.
- No change to Sybase (`Sybase.sql:1-3` has the same shape — see P7, deferred).
- Not a goal: surviving an interruption *within* the same run. The run that is interrupted still fails; the next `CreateDatabase` heals it.
- No new committed test: a regression test would have to drop a shared database mid-session, racing the concurrent lanes on the same server (`testing.md` → *`CreateDatabase` runs on an ungated lane*). Proof is a recorded manual probe (P8).

## P4 Unknowns (M/L)

- U-1 Every MySQL-family connection string spells the database key as `Database=` — resolved-by scout: `DataProviders.json:114-118,173-177` and the local `UserDataProviders.json:468-487` all use `Database=`; the generic `DbConnectionStringBuilder` is case-insensitive, and `Initial Catalog` is removed too as the only other alias both drivers accept for a server-level string. A config using another alias keeps today's behaviour (the open still fails with 1049), no worse than now.
- U-2 Both MySql.Data and MySqlConnector open a connection whose string has no `Database` key — resolved-by probe: TO-1's green run on MySql.8.0 and MySqlConnector.8.0 exercises exactly that open; recorded in P9.
- U-3 `CREATE DATABASE IF NOT EXISTS` is accepted by MySQL 5.7, 8.x and MariaDB — resolved-by probe: TO-1 runs it on MySQL 8; MySQL 5.7 and MariaDB are covered by CI's MySQL job (all five lanes, `mysql.sh:4-9`) unless those containers exist locally, and P9 records which.
- U-4 Two lanes on one server (MySql.8.0 + MySqlConnector.8.0) run the new step concurrently — resolved-by scout: each creates its own database name (`testdata` vs `testdataconnector`), and `IF NOT EXISTS` makes a concurrent duplicate a no-op.
- U-6 Does the ensure step change which provider a config resolves to? — resolved-by scout (critic, verified): via the configuration it would, for `MariaDB.11` (`MySqlProviderDetector.cs:55-86`, `DataConnection.Configuration.cs:127`); D-2 avoids the configuration entirely. `GetConnectionString(configString)` reads only `ConfigurationInfo.ConnectionString` (`DataConnection.Configuration.cs:430-433`), not `DataProvider`. TO-1b checks the resolved provider.
- U-5 Docker Desktop's engine returned HTTP 500 on `docker ps` at plan time — resolved-by probe: TO-1/TO-2 are blocked until it recovers; P9 records `blocked` until then, never a pass. Later: engine recovered; `mysql` up, `mysql57` / `mariadb` exist but are stopped (`docker ps -a`).

## P5 Decisions (M/L; rejected alternatives mandatory at L)

### D-1 — Pre-create the database from a server-level session before `RunScript`

- **chosen:** in `CreateDatabase`'s `AllMySql` case, call a new `EnsureMySqlDatabase(context)` before `RunScript`: read the database name from the connection string, open a connection with the `Database` key removed, run `CREATE DATABASE IF NOT EXISTS \`<name>\``. Then `RunScript` runs unchanged.
- **rejected:** run the whole script on the server-level connection (the peer's suggested direction) — it changes the session the 300-line script and five `BulkCopy` calls run in, relying on the script's `USE` (`MySql.sql:7`) for every unqualified name, and `{DBNAME}` would also have to come from the builder. Same healing property (the next run opens without a database), larger surface. No reachable input separates the two on SC-1; the choice rests on the smaller blast radius.
- **rejected:** edit `MySql.sql` (e.g. drop tables instead of the schema) — the open fails before any script line runs, so no script change can heal; and the `DROP SCHEMA` reset is what clears leftover objects from other tests.
- **why this:** heals at the only point that can — before the open — and leaves the script path byte-identical.
- **failure mode of the choice:** a connection string whose database key is an alias other than `Database` / `Initial Catalog` (none known for either driver, so believed unreachable) keeps the key in the "server-level" string, so the ensure-open itself fails with 1049 — CreateDatabase then fails exactly as today, now from the new step. A string with neither key makes the helper return without doing anything (such a config already has no database to heal).

### D-2 — Ensure step runs over raw ADO on an explicitly chosen provider, never through the configuration

- **chosen:** `MySqlTools.GetDataProvider(MySqlVersion.MySql57, <driver>)` with `<driver>` = `MySqlProvider.MySqlData` for `TestProvName.AllMySqlData`, else `MySqlProvider.MySqlConnector`; `provider.CreateConnection(serverLevelString)`, `Open`, one `ExecuteNonQuery`. The dialect version is irrelevant to a single `CREATE DATABASE IF NOT EXISTS`, and passing it explicitly means no server-version detection runs.
- **rejected:** `GetDataProvider(configString)` (the first sketch) — critic-refuted: it resolves and caches the configuration's provider (`DataConnection.Configuration.cs:127`, `field ??=`) while the database is missing; for `MariaDB.11` (`Provider: "MySqlConnector"`, no version shortcut at `MySqlProviderDetector.cs:58-70`) detection opens the configured string, gets 1049, swallows it (`:80-83`) and caches the `MySql57` fallback (`:86`) for every later `MariaDB.11` test in the process.
- **rejected:** `DataConnection.GetDataProvider(providerName, configString, serverLevelString)` (`:314`) — correct detection, but needs the config's provider name, which the tests register differently on netfx and core (`TestConfiguration.cs:121,136`); and a `DataConnection` over it would trace a differently-headed statement into five `a_CreateData.CreateDatabase(<cfg>)` baselines.
- **why this:** touches neither the configuration's cached provider nor the baseline sink (raw ADO is not traced by linq2db), so `RunScript` sees exactly the state it sees today once the database exists.
- **failure mode of the choice:** the driver split keys on `TestProvName.AllMySqlData`; a future MySQL-family config whose driver is not MySql.Data and is not listed there falls to MySqlConnector — wrong only if that config uses a third driver, which none does today (`TestProvName.cs:44,48`).

## P6 Edit-points

- E-1 `Tests/Linq/Create/CreateData.cs:CreateDatabase` — `AllMySql` case calls `EnsureMySqlDatabase(context)` before `RunScript`.
- E-1b `Tests/Linq/Create/CreateData.cs:EnsureMySqlDatabase` — new private static helper as in D-1.

## P7 Impact map (M/L)

- `Tests/Linq/Create/CreateData.cs:27,246` `RunScript` callers — searched `\bRunScript\(` across `Tests/`: only `CreateData.cs` (the `CreateDatabase` switch and the `CreateDataScript` overload). RunScript itself is not edited — covered by E-1
- `Tests/Base/TestProvName.cs:44,48,52` `AllMySql` = MySql.5.7, MySql.8.0, MySqlConnector.5.7, MySqlConnector.8.0, MariaDB.11 — all five reach the edited case, so MySQL 5.7 and MariaDB get the same treatment with no extra site — covered by E-1
- `ClickHouse.MySql` (local `UserDataProviders.json:790`, MySqlConnector provider) — routed by `AllClickHouse` to `ClickHouse.sql` at `CreateData.cs:275`, not the MySql case — out-of-scope
- `Data/Create Scripts/Sybase.sql:1-3` — searched `(?i)drop\s+(database|schema)` across `Data/Create Scripts/`: `USE master` then `DROP DATABASE {DBNAME}` while the config connects with `Database=TestData` (`DataProviders.json:163-164`) — same interrupted-run shape — deferred: different provider, ASE behaviour when the login database is missing is unprobed and no Sybase container was measured; reported to the requester
- `Data/Create Scripts/MySql.sql:324-330` `test_schema_{DBNAME}` — a separate database the session is not connected to; an interruption there is healed by the script's own `DROP … IF EXISTS` next run — out-of-scope
- Other scripts from the same sweep (`SqlServer.sql:1104`, `PostgreSQL.sql:457,647`, `DuckDB.sql:1`) drop a schema *inside* the connected database, not the database — out-of-scope
- `Tests/Base/Interceptors/CustomizationSupportInterceptor.cs:58` `InterceptCreateData` — custom scripts go through the `default` arm, not the `AllMySql` case — out-of-scope
- `Build/Azure/scripts/mysql.sh:23-53` pre-creates both databases on all three servers — the new step is a no-op on CI — out-of-scope
- `.claude/docs/testing.md:399` describes `RunScript`'s `{DBNAME}` replace from `db.OpenDbConnection().Database` — still true, RunScript unchanged — out-of-scope

## P8 Test obligations (M/L)

- TO-1 Discriminating input: the configured database dropped (via a throwaway server-level probe, not committed). Unfixed code: `CreateDatabase` on MySqlConnector.8.0 and MySql.8.0 fails with `1049 Unknown database`; fixed code: passes, then a follow-up test on the same provider passes against the recreated database — providers: MySqlConnector.8.0, MySql.8.0 — proof: red→green
- TO-1b Discriminating input: `testdata` dropped on the `mariadb` container by raw ADO in a separate `dotnet test` process; the healing run is a fresh process in which nothing resolves `MariaDB.11` before `CreateDatabase` (otherwise the correct provider is cached while the database exists and the mutant stays green). After the healing `CreateDatabase(MariaDB.11)`, a probe in the same process asserts `DataConnection.GetDataProvider("MariaDB.11").Name == ProviderName.MariaDB10MySqlConnector`, and a CTE test (`AllMySql8Plus`-gated, includes MariaDB) passes. Mutation that turns it red: resolve the ensure step's provider via `GetDataProvider(configString)` (the rejected D-2 sketch) — providers: MariaDB.11 — proof: control
- TO-2 Database present: `CreateDatabase` passes with the fix — providers: MySql.8.0, MySqlConnector.8.0, plus MySql.5.7, MySqlConnector.5.7, MariaDB.11 where a local container exists (else CI's MySQL job) — proof: characterization
- TO-3 `git diff origin/master` touches only `CreateData.cs`'s `AllMySql` case and the new helper — providers: none (diff check) — proof: characterization

## P9 Verification gates

- G-01: — (pending) TO-1 red then green on MySqlConnector.8.0 and MySql.8.0; TO-2 on every MySQL-family provider with a local container
- G-01b: — (pending) Azure MySQL job (all five lanes) observed green on the branch head — run id recorded here; covers TO-2 for MySql.5.7 / MySqlConnector.5.7 / MariaDB.11 if their containers are not run locally
- G-02: — (pending) expectation: zero change to the five `a_CreateData.CreateDatabase(<cfg>)` baselines (`c:\GitHub\linq2db.bls\<cfg>\a_CreateData\`) — the ensure step is raw ADO, untraced (D-2)
- G-06: — (pending)
- G-07: — (pending)
- G-09: — (pending)
- extra: — (pending) `dotnet build Tests/Linq/Tests.csproj -c Release -f net10.0` — analyzers are Release-only and the test project is analyzed

## P10 Adjudicated (M/L)

- If TO-1's green arm fails with a non-1049 error (e.g. `Connection must be Open; current state is Broken`, measured by peer at low load ~2.5 min into the MySqlConnector.8.0 script), G-01 is recorded `blocked`, the first swallowed command error is captured from the `TraceError` output (`RunScript` keeps only the first, `CreateData.cs:95-123`; the uncaught `BulkCopy` at `:131` shows only the symptom), and the cause is filed separately. SC-1 is not loosened. Reason: that failure leaves the database present, so it is outside this branch's defect (`P3`).

## P11 Amendments (M/L)

_None._

## P12 Critic verdict (M/L)

Round 1 (`plan-critic`, model `fable`): **refuted.** Objections: (1) the sketch's `GetDataProvider(configString)` caches a `MySql57` fallback provider for `MariaDB.11` when its database is missing — verified against `MySqlProviderDetector.cs:55-86` and `DataConnection.Configuration.cs:127`; answered by D-2, U-6, TO-1b. (2) G-02 hedged on a settled fact — baselines are recorded for `CreateDatabase`; answered by D-2 (raw ADO, untraced) and a definite G-02 expectation. (3) CI coverage of the 5.7 / MariaDB lanes had no gate — added G-01b. (4) Minor: D-1's failure-mode line misdescribed the no-key case — corrected. Critic searched: the create-script drop sweep, `AllMySql` / `AllClickHouse` routing, `IsAnyOf`, `TestBase.Context.cs` helpers, `UseConnectionString` overloads, MySQL provider on-open hooks, `AutoDetectProvider` in `Tests/`, local `UserDataProviders.json`; not checked: the netfx registration path, MariaDB 1049-on-open behaviour, `DbConnectionStringBuilder` key casing.

Round 2 (same critic, on the revision): **weak.** D-2 held — verified that explicit version + driver opens no connection (`MySqlProviderDetector.cs:92-107,150-151`), raw ADO bypasses the baseline sink (`TestBase.cs:69-75`), `CA2100` is off (`.editorconfig:578`). Objections, all folded in: (1) TO-1b's control is vacuous unless the drop and the healing run are separate processes — added to TO-1b; (2) no rule for a non-1049 failure on TO-1's green arm — added to P10; (3) D-1's `Schema` alias example uncited — removed. Not checked: netfx registration path, MariaDB / MySql.Data 1049-on-open, `DbConnectionStringBuilder` casing; `mysql57` / `mariadb` stopped, so TO-1b / TO-2 on them stay `blocked` until started.
