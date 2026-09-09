# Per-package update rules and release-notes URLs

Accrued across releases by [`release-deps`](../../skills/release-deps/SKILL.md). One entry per package that has a non-default update rule, a known release-notes URL, or a documented gotcha.

## Schema

Each entry is a heading + bullet list:

```markdown
## <PackageId>

- **Release notes URL:** <url>  <!-- omit if unknown -->
- **Update rule:** <terse rule, e.g. "always pin to .NET 8.0.0 unless flagged vulnerable" or "bump requires regenerating T4 templates in Tests.T4">
- **Co-bump:** <other-package-ids that must move together>  <!-- omit if not applicable -->
- **Last verified:** <iso-date> on release <version>
```

When a rule is added or amended, the modifying skill prompts session-reload.

## Categories

- **Shipping runtime packages:** `Microsoft.Extensions.*`, `System.*` referenced by published linq2db assemblies. Default rule: pin to the initial .NET version (e.g. 8.0.0 / 9.0.0); only bump if flagged vulnerable.
- **Test-only references:** opposite rule — latest stable is always proposed.
  - **A test-only pin must be *scoped*, never global.** When the tests need a version *below* latest (a driver regression that only the test corpus provokes, say), do **not** lower the shared `<PackageVersion>` — several package ids are referenced by both the test projects and shipping ones (`System.Data.OleDb` / `System.Data.Odbc` by `Tests/linq2db.Providers.props`, `Source/LinqToDB.CLI` and `Source/LinqToDB.LINQPad*`), and a `PackAsTool` package like `linq2db.cli` carries its dependencies *inside* the package, so a global pin ships the downgrade to users who have no control over it. That is the case `Directory.Packages.props`'s own header comment warns about. Instead: keep `<PackageVersion>` on the shared/latest value, add a `$(<Pkg>TestsVersion)` property beside the other *"used by VersionOverride in project files"* properties carrying the rationale + the revert condition, and apply it via `VersionOverride="$(…)"` on the test-side `PackageReference` only. Verify the split by restoring both sides and grepping the resolved id in each `project.assets.json`. (Maintainer, on #5761: *"tests and linqpad/cli must use different versions"*.)
- **Analyzers:** prerelease versions allowed (analyzers are dev-time only, not transitively visible to consumers). Two obligations apply to *every* analyzer-package bump, regardless of package:
  - **Rule-catalog catch-up** before the build (`/release-deps` step 4a) — new rules get a severity decision each. Render each rule id as a link to its doc page, not a bare id.
  - **Post-build profiling pass** after the build is clean (`/release-verify` step 3 → `/profile-analyzers`) — measures what the newly-enabled rules actually cost, diffs already-enabled rules against `analyzer-perf-baseline.json` to catch regressions introduced by the bump alone, and yields an explicit disable-candidate list. A severity decision taken from a changelog is not a cost decision; the cost verdict is deferred to this pass, never skipped.
- **Database providers:** per-provider rules vary widely (some providers have schema-init compatibility quirks tied to specific versions). Capture each as a row when encountered.
- **Self-references:** `linq2db.t4models` is bumped post-release by `/release-postpublish` step 4 to the just-released version; not by `/release-deps`.
- **`*LatestForNuget` / `*LatestNuget` MSBuild properties** (e.g. `$(Net8LatestForNuget)`, `$(EF3LatestNuget)`): contain the **lowest** / initial version of a .NET-X / EF-X line, used by published nuspec contracts. **Always pinned at `X.0.0` (or for EF: at the lowest supported minor, e.g. `3.1.0` for EF Core 3.1).** Do **not** ask per-package for any `<PackageVersion>` whose `Version="$(*LatestForNuget|*LatestNuget)"`. Only change when the pinned version becomes unlisted on nuget.org or is flagged vulnerable — in that case bump to the next stable X.0.y.
- **`*Latest` MSBuild properties** (suffix `Latest` without `Nuget`, e.g. `$(Net8Latest)`, `$(Net9Latest)`, `$(Net10Latest)`, `$(EF3Latest)`): contain the **newest** stable version of the corresponding .NET-X / EF-X line. **Always update to the latest stable X.0.y (or for EF: highest supported X.M.y) without asking per package.** The bump is delivered by editing the property value in `Directory.Packages.props`; downstream `<PackageVersion ... Version="$(NetXLatest)" />` entries pick it up automatically.
- **Multi-row packages (TFM-conditional + `VersionOverride` sites):** ask **once per package** rather than once per row. The single decision applies to all of that package's conditional `<PackageVersion>` rows + every `VersionOverride` site referencing the same id.

## Cross-package procedures

### Fuget API-diff procedure

Some packages are flagged with this procedure (see per-package entries) — typically database clients and other shipping deps where surface change matters.

The bulk fetcher lives at [`fuget-api-diff.ps1`](../../scripts/fuget-api-diff.ps1). It accepts a manifest of `{id, old, new}` tuples + a fuget base URL, fetches every TFM diff in parallel, parses additions / removals from the `<span class="diff-Add|diff-Remove">` markers, and merges per package. Wall-clock ≈ 30-60s for the first uncached run on a package; second runs are faster.

On every bump:
1. Run `fuget-api-diff.ps1 -Action diff -ManifestFile <json> -FugetBase <url>` for all flagged packages of the release in one batch. Override `-FugetBase` with the user's self-hosted fuget URL (recorded in [`external-repos.md`](./external-repos.md) → user-specific paths); default is the public https://www.fuget.org.
2. **Apply universal filters** (always-on, applied during rendering, not in the script — see *Universal API-diff filters* below):
   - **Drop `protected` members.** They aren't public surface and only matter if linq2db subclasses, which is rare for transitive deps.
   - **Reconcile `diff-Update` double-counting.** When a member's signature changes, fuget renders it as both a removal (old sig) and an addition (new sig) inside a single `diff-Update` parent. After parsing, compute "real removals" = items in `mergedRemovals` that don't have an equivalent entry in `mergedAdditions`. The script does **not** do this normalisation today — the agent does it post-render.
3. **Apply per-package diff exclusions** (see *API-diff exclusion list* below) — namespaces / types the user has marked as not relevant for future reviews.
4. Show the filtered diff to the user before committing the bump — they decide whether to absorb the API change, revert the bump, or add new exclusions.
5. After the user has reviewed, ask whether any new namespaces/types should be added to the package's exclusion list (record under the package's entry as `**API-diff exclusions:**`).
6. The procedure is opt-in per package; the package's own entry above lists it as an update rule.

### Universal API-diff filters

These filters apply to **every** package's fuget API-diff render (they're not per-package). Recorded here so the agent knows to apply them automatically.

- **Protected members** (`protected\s+\w+`, `protected\s+(virtual|abstract|override|sealed)\s+\w+`, `protected\s+(static|async)\s+\w+`) — drop. Reason: not consumable except by subclassing, which the linq2db codebase rarely does for these dep packages.
- **`diff-Update` re-emissions** — drop entries from `mergedRemovals` whose signature also appears in `mergedAdditions`. They represent a member whose signature changed (typically nullable annotation, parameter rename, default-value change), not a removed-and-replaced API.

### EF Core provider packages — pin within EF major

EF Core provider packages (Pomelo.EntityFrameworkCore.MySql, Npgsql.EntityFrameworkCore.PostgreSQL.NodaTime, Microsoft.EntityFrameworkCore.Sqlite/SqlServer/InMemory, etc.) **must update only within the same EF Core major** that pairs with each TFM:

| linq2db TFM | EF Core major | Provider major to use |
|---|---|---|
| `net462` | EF Core 3.1 | provider 3.x line _(some providers use a different but stable mapping — Pomelo: `3.2.x` for EF 3.1)_ |
| `net8.0` | EF Core 8.x | provider 8.0.x |
| `net9.0` | EF Core 9.x | provider 9.0.x |
| `net10.0` | EF Core 10.x | provider 10.0.x _(if released; otherwise stay on 9.0.x)_ |

For each provider's TFM-conditional row, find the latest stable in the matching X.M.x line and bump only within that line. Cross-major bumps break EF Core API compatibility on the affected TFM.

### Prefer the version whose dependencies the repo's pins already satisfy

Within the allowed line, "newest published" is **not** the default — the default is the newest version whose own dependency ranges are already met by what `Directory.Packages.props` pins today. A newer one that requires more silently drags a *transitive* package ahead of every sibling: `CentralPackageTransitivePinningEnabled` is `false` here, so nothing errors, nothing warns, and the mismatch only shows up in `project.assets.json`.

Read the candidate's dependency groups off the published nuspec (`.claude/scripts/inspect-nupkg.ps1 -Id <id> -Version <v>`) and compare each against the corresponding pin before choosing. When a newer version needs more than the repo pins, the honest options are *hold at the matching version* or *bump the pins too as a deliberate, separate decision* — *not* "take the newest and note the drift in passing".

Worked example (2026-09-06, [#5885](https://github.com/linq2db/linq2db/pull/5885)): `Microting.EntityFrameworkCore.MySql` 10.0.11 needs Relational `[10.0.11, …]` + MySqlConnector `2.6.2`, against `$(Net10Latest)` = 10.0.10 and MySqlConnector `2.6.1`; 10.0.10 needs exactly those two pins. 10.0.11 was offered as a live option with the mismatch noted as a trade-off, and the maintainer's call was *"as dependency not satisfied yet, use 10.0.10"*. Picking 10.0.10 moved no package in the restore graph at all.

### Lowest-supported-TFM detection

Some package bumps **raise the lowest .NET TFM** the package supports (e.g. `Net.IBM.Data.Db2` 9.x supported `net8.0` but 10.x dropped down to `net10.0` only). Bumping such a package without action **breaks the build** for projects targeting the dropped TFMs.

**Detection (per bump, today manual):** before applying, read the target version's `<dependencies>` group on nuget.org for the per-TFM target frameworks listed; compare against linq2db's supported TFMs (per `CLAUDE.md`: `net462, netstandard2.0, net8.0–net10.0`). If any supported TFM is no longer listed, the package raised its lowest TFM.

**When raised, ask the user the resolution:**

1. **Drop the lower TFMs from linq2db's matrix** (rare — only when the user is OK with it).
2. **Pin the package per-TFM** — add a TFM-conditional `<PackageVersion>` entry for the new version targeting the higher TFM only, and add an inverse `Condition` to the existing entry so it stays the active row for the lower TFMs. Apply the same edit to the central `Directory.Packages.props` and to any `Tests/Tests.T4.Nugets/Directory.Packages.props` site.

The script does not yet auto-detect this — TODO: extend `release-deps-discover.ps1` to query the registration leaf's `dependencyGroups[].targetFramework` and surface a `tfmRaised` flag per row.

### API-diff exclusion list

Per-package list of namespaces / types that should be **stripped from fuget API-diff output** before the user reviews. Captured in each package's own entry as a bullet:

```
- **API-diff exclusions:** <namespace-or-type-pattern> ; <another-pattern>
```

Patterns are wildcard-friendly (`Internal.*`, `*.Internal.*`, `Foo.Bar.IBaz`). The fuget-diff renderer applies them before showing the user, so noise from auto-generated / internal / explicitly-deprecated surface stays out of the review window.

## Entries

<!-- entries below this line are appended by `release-deps` on first encounter -->

## Ydb.Sdk

- **Release notes URL:** https://github.com/ydb-platform/ydb-dotnet-sdk/releases
- **Update rule:** **Public-API surface diff via fuget** (see *Fuget API-diff procedure*) — show diff to user before committing.
- **API-diff exclusions:** `Ydb.Sdk.Services.*` (the high-level Query / Table services namespace; linq2db consumes only the lower-level `Ydb.Sdk.Ado` ADO.NET surface).
- **Last verified:** 2026-05-15 on release 6.3.0

## ClickHouse.Driver

- **Release notes URL:** https://github.com/ClickHouse/clickhouse-cs/releases
- **Update rule:** On every bump:
  1. **TFM support cap:** version `0.9.0` is the last release that supports `net462`. The net462 conditional row (the `!net8+` split) **must stay at `0.9.0`** unless / until linq2db drops net462 or ClickHouse re-adds netfx support.
  2. **Public-API surface diff via fuget** (see *Fuget API-diff procedure* category note). Show the diff to the user before committing the bump.
- **Last verified:** 2026-05-15 on release 6.3.0

## System.Data.SQLite

- **Release notes URL:** https://system.data.sqlite.org/home/doc/trunk/www/news.md
- **Update rule:** **Public-API surface diff via fuget** (see *Fuget API-diff procedure*) — show diff to user before committing.
- **Also:** subject to the *SQLite version-assert sync* rule below.
- **Last verified:** 2026-05-15 on release 6.3.0

## SourceGear.sqlite3 (and the SQLite version-assert sync rule)

- **What it is:** supplies the patched native `e_sqlite3.dll` for **CVE-2025-6965 / GHSA-2m69-gcr7-jv3q** (SQLite < 3.50.2), because `SQLitePCLRaw.lib.e_sqlite3` (<= 2.1.11, pulled via `Microsoft.Data.Sqlite` / `Microsoft.EntityFrameworkCore.Sqlite`) has no patched release. Rationale is recorded in `Directory.Packages.props` near the entry. Deployed by `SQLite.Runtime.props` into `sds/runtimes/`; consumed by tests (`Tests/linq2db.Providers.props`), `NuGet/NuGet.csproj`, and the LINQPad driver.
- **Update rule — run the version-assert test locally BEFORE pushing.** Whenever **SQLite itself or any SQLite provider** moves — `SourceGear.sqlite3`, `System.Data.SQLite`, `Microsoft.Data.Sqlite` (note: it rides `$(Net10Latest)`, so it moves *silently* with that property), or `Microsoft.EntityFrameworkCore.Sqlite` — the asserted SQLite version can change. Run `TestDbVersion` (`Tests/Linq/DataProvider/SQLiteTests.cs`) locally, read the actual `select sqlite_version()` results, and update the expectations. **The test is `[Explicit]`, so a normal test run and CI both skip it** — it must be selected deliberately, which is exactly why a stale assert otherwise survives until it wastes a CI run.
- **Two files to update together** (the test's own comment names the second one):
  1. `Tests/Linq/DataProvider/SQLiteTests.cs` — the `expectedVersion` switch: one arm for `SQLiteClassic` + the two MiniProfiler variants, one for `SQLiteMS`. **Both arms currently resolve to the same version** (measured 6.4.0: both `3.53.4`), because `TestsInitialization` points the native runtimes folder at `SourceGear.sqlite3`'s `e_sqlite3` via `PreLoadSQLite_BaseDirectory`, so Microsoft.Data.Sqlite loads that binary rather than its own SQLitePCLRaw bundle. Keep the arms separate anyway — they diverge again if MDS migrates to its own runtimes nuget, which is what the test's `[Explicit]` reason is waiting on. (Before 6.4.0 they *did* differ — 3.50.4 vs 3.46.1 — so don't assume either shape; read the actual values from the failure.)
     `TestDbVersion2` just delegates to `TestDbVersion`, so there is only one switch to edit.
  2. `Build/Azure/README.md` — the SQLite test-matrix rows hardcode both the version **and** a `https://www.sqlite.org/releaselog/<v_v_v>.html` link, so each needs the number *and* the URL slug updated (underscores, e.g. `3_53_4`).
- **Last verified:** 2026-08-03 on release 6.4.0 (SourceGear.sqlite3 3.50.4.5 -> 3.53.4; asserts were `SQLiteClassic` "3.50.4" / `SQLiteMS` "3.46.1")

## dotMorten.Microsoft.SqlServer.Types

- **Update rule:** This package is a side-package coupled to the SqlClient line:
  - `1.x` line pairs with **System.Data.SqlClient** (legacy)
  - `2.x` line pairs with **Microsoft.Data.SqlClient**
  Do **not** cross-bump majors unless the corresponding SqlClient package is also moved across the `System.Data.SqlClient → Microsoft.Data.SqlClient` boundary in the same place. Today the references in `Directory.Packages.props` and `Tests/Tests.T4.Nugets/Directory.Packages.props` should stay on `1.x`.
- **Last verified:** 2026-05-15 on release 6.3.0

## Devart.Data.Oracle

- **Release notes URL:** https://www.devart.com/dotconnect/oracle/revision_history.html
- **Update rule:** **Public-API surface diff via fuget** (see *Fuget API-diff procedure*) — show diff to user before committing.
- **API-diff exclusions:** the **whole `net20` asset**. linq2db binds Devart only through `netstandard2.0` / `netstandard2.1`, and the net20 asset carries netfx-CAS-era surface (`OraclePermission`, `OraclePermissionAttribute`, `OracleDataSetToolboxItem`, `HandleRef GetNativeHandle()`) that can never be consumable from those TFMs — so it shows up as pure noise on every bump. Maintainer's call on 6.5.0 prep was to exclude the TFM rather than name the types.
- **Integration shape (why most removals are harmless):** the provider is reached entirely through reflection-mapped wrappers in `OracleProviderAdapter.CreateDevartAdapter()` — `OracleConnection`, `OracleParameter`, `OracleCommand`, `OracleDataReader`, `OracleTimeStamp`, `OracleNumber`, `OracleLoader*`. Nothing subclasses Devart types and nothing binds `OracleColumn` / `DbColumnBase` / `GetColumnSchema` / `DeriveParameters`. Grep the removal list against `Source/` + `Tests/` rather than reading the diff as breakage.
- **Last verified:** 2026-09-09 on release 6.5.0 prep (11.1.123 → 11.2.192: 8 removals, all verified unreferenced)

## Meziantou.Polyfill

- **Release notes URL:** _none — package does not publish release notes; the list of polyfilled APIs lives in the repo README at https://github.com/meziantou/Meziantou.Polyfill/blob/main/README.md_
- **The repo publishes no tags or releases, so "compare the README at the two tags" does not work.** `gh api repos/meziantou/Meziantou.Polyfill/tags` and `.../releases` both return empty, and a ref like `1.0.158` 404s. Diff the **README embedded in the two nupkgs** instead — it is the generated API list and it is versioned with the package: `inspect-nupkg.ps1 -Id Meziantou.Polyfill -Version <v> -OutDir <dir>` for each, then compare the `` - `…` `` bullets between the `<!-- begin_polyfills -->` / `<!-- end_polyfills -->` markers.
- **The `<Polyfill>` list in `Directory.Build.props` is an explicit allowlist (`MeziantouPolyfill_IncludedPolyfills`), so newly-supported APIs are inert until opted in.** That makes the *removal* half of the diff the part that can actually regress the build; a bump with zero removals cannot change generated output at all, whatever its addition count.
- **Update rule:** On every bump:
  1. Pull the README diff between the current and target version (per the nupkg method above) to extract the **list of newly polyfilled APIs**.
  2. For each new API, search the linq2db codebase for our own polyfill or conditional-build (`#if`) implementing the same API. If found, propose to **delete** our copy and rely on Meziantou.Polyfill instead.
  3. **Always show the full list of new APIs to the user for review**, even if no internal duplicates are found — the user may want to start using one of the new polyfills somewhere.
- **Last verified:** 2026-09-09 on release 6.5.0 prep (1.0.158 → 1.0.165: 1350 → 1355 polyfills, **0 removals**, no internal duplicate to delete; `RuntimeHelpers.GetSubArray<T>` offered and declined — it would enable array range-slicing on net462/netstandard2.0 next to the existing `Index`/`Range` polyfills, but has no current caller)

## Oracle.ManagedDataAccess.Core

- **Release notes URL:** _none — README in the nupkg on nuget.org (https://www.nuget.org/packages/Oracle.ManagedDataAccess.Core#readme-body-tab)_
- **Update rule:** **Public-API surface diff via fuget** (see *Fuget API-diff procedure*) — show diff to user before committing.
- **Last verified:** 2026-05-15 on release 6.3.0

## Microsoft.Extensions.Logging.Console

- **Update rule:** The `!net9+` conditional row stays on a literal version (today `8.0.1`). **Do not switch this row to `$(Net8Latest)`** — the package's 8.0.x line shipped only `8.0.0` + `8.0.1` and then jumped straight to 9.0.x; `$(Net8Latest)` (which tracks the latest .NET 8 patch like `8.0.27` for EF.Core / runtime libs) has no matching `Microsoft.Extensions.Logging.Console` release. Future bumps for this row are **capped at the 8.0.x line** of this specific package — i.e. only viable if Microsoft ever re-opens 8.0.x patches for it.
- **Last verified:** 2026-05-15 on release 6.3.0

## Microsoft.NET.Test.Sdk

- **Release notes URL:** https://github.com/microsoft/vstest/releases
- **Last verified:** 2026-05-15 on release 6.3.0

## NUnit

- **Release notes URL:** https://docs.nunit.org/articles/nunit/release-notes/framework.html
- **Last verified:** 2026-05-15 on release 6.3.0

## NUnit.Analyzers

- **Release notes URL:** https://github.com/nunit/nunit.analyzers/blob/master/CHANGES.md
- **Last verified:** 2026-05-15 on release 6.3.0

## Pomelo.EntityFrameworkCore.MySql

- **Release notes URL:** https://github.com/PomeloFoundation/Pomelo.EntityFrameworkCore.MySql/releases
- **Update rule:** Per *EF Core provider packages — pin within EF major* (cross-package procedure). Pomelo's mapping is **EF 3.1 → 3.2.x**, EF 8 → 8.0.x, EF 9 → 9.0.x. Update each TFM-conditional row only within its own major.
- **Last verified:** 2026-05-15 on release 6.3.0

## Npgsql

- **Release notes URL:** https://github.com/npgsql/npgsql/releases
- **Update rule:** Multiple rows pin different majors per TFM:
  - `!net8+` row → 8.0.x line (npgsql majors aligned with .NET LTS pairings).
  - `net8+` row → 10.0.x line.
  - `Tests/Tests.T4.Nugets/Directory.Packages.props` → matches the net8+ row's major.
  - `VersionOverride` site referencing `$(EF3NpgsqlVersion)` → pinned at `4.1.14` (last npgsql 4.1.x — paired with EF Core 3.1).
  Update each row only within its own major.
- **API surface diff via fuget** (see *Fuget API-diff procedure*) — apply per row that bumps.
- **API-diff exclusions:** `Npgsql.Internal.*` (driver-internal surface, not a consumer contract; linq2db references none of it — verified by grep on 6.4.0 prep when `Npgsql.Internal.Postgres.DataTypeName.FromDisplayName` was removed in 10.0.3).
- **Last verified:** 2026-08-03 on release 6.4.0

## Newtonsoft.Json

- **Update rule:** **Pinned at the current shipping version** (`Directory.Packages.props` is authoritative — `13.0.3` as of 6.4.0 prep; this doc previously recorded `13.0.1`, so read the props file rather than trusting the version quoted here). Do not bump even when newer 13.0.x is available, unless flagged vulnerable. Reasoning: shipping with the lowest stable 13.0.x version keeps downstream consumers free of transitive constraints (same intent as runtime-pin policy, but for Newtonsoft specifically since it is referenced from shipping projects). The pin having moved 13.0.1 → 13.0.3 is consistent with the "unless flagged vulnerable" carve-out; the raise itself isn't a rule change.
- **How to discharge the "unless flagged vulnerable" carve-out cheaply:** `gh api 'advisories?ecosystem=nuget&affects=Newtonsoft.Json' --jq '…'`. On 6.5.0 prep the only advisories were `GHSA-5crp-9r3c-p9vr` / `GHSA-8rfx-6mr3-5jh3`, both ranged `< 13.0.1` and therefore already satisfied by the 13.0.3 pin — so 13.0.4 was **held** with no user decision needed. Run the query rather than asking; it turns a judgement call into a lookup.
- **Last verified:** 2026-09-09 on release 6.5.0 prep (held at 13.0.3; 13.0.4 available but no advisory above 13.0.1)

## NUnit3TestAdapter

- **Release notes URL:** https://docs.nunit.org/articles/vs-test-adapter/AdapterV4-Release-Notes
- **Last verified:** 2026-05-15 on release 6.3.0

## Microsoft.AspNetCore.OData

- **Release notes URL:** https://github.com/OData/AspNetCoreOData/releases
- **Update rule:** Package is **only used by .NET-targeted projects** (not netfx/netstandard). The `!net8+` conditional `<PackageVersion>` entry is dead code from the pre-net8 era — keep only the unconditional entry.
- **Last verified:** 2026-05-15 on release 6.3.0

## FSharp.Core

- **Release notes URL:** https://github.com/dotnet/fsharp/releases
- **Update rule:** Same cleanup pattern as `Microsoft.AspNetCore.OData` — historical TFM split (net462 / net8+) is dead post-TFM-migration. Collapse to a single unconditional entry. Pinned at the latest 10.x line for net8+. If a downstream project actually requires the older line, the build will fail and the conditional entry can be re-added with documentation explaining why.
- **Last verified:** 2026-05-15 on release 6.3.0

## NodaTime

- **Release notes URL:** https://github.com/nodatime/nodatime/releases
- **Last verified:** 2026-05-15 on release 6.3.0

## System.Text.Json

- **Update rule:** Pinned to the **lowest non-vulnerable version of the lowest non-EOL .NET major** the package supports. Today that floor is `8.0.5` (versions before 8.0.5 carry CVEs we don't want to ship; the lowest non-EOL major is .NET 8, since older majors are EOL). Hold this row at `8.0.5` until either (a) a new CVE forces another bump, or (b) .NET 8 goes EOL and the floor moves to the next non-EOL major. Distinct from `$(Net8LatestForNuget)` (which is 8.0.0) — the literal here is intentionally higher.
- **Last verified:** 2026-05-15 on release 6.3.0

## System.Linq.Dynamic.Core

- **Release notes URL:** https://github.com/zzzprojects/System.Linq.Dynamic.Core/blob/master/CHANGELOG.md
- **Last verified:** 2026-05-15 on release 6.3.0

## MySql.Data

- **Release notes URL:** https://dev.mysql.com/doc/relnotes/connector-net/en/
- **Update rule:** **Public-API surface diff via fuget** (see *Fuget API-diff procedure*) — show diff to user before committing.
- **Last verified:** 2026-05-15 on release 6.3.0

## Net.IBM.Data.Db2 (and `-lnx`, `-osx` platform variants)

- **Release notes URL:** _none — README in the nupkg on nuget.org (https://www.nuget.org/packages/Net.IBM.Data.Db2#readme-body-tab)_
- **Update rule:**
  1. **TFM split required for 9.x → 10.x.** The 10.x line dropped `net8.0` support. We **do not** drop net8 from CI. Apply per-TFM-conditional split in `Directory.Packages.props`:
     ```xml
     <PackageVersion Include="Net.IBM.Data.Db2"     Version="9.0.0.400"   Condition="!$([MSBuild]::IsTargetFrameworkCompatible('$(TargetFramework)', 'net10.0'))" />
     <PackageVersion Include="Net.IBM.Data.Db2"     Version="10.0.0.100"  Condition="'$(TargetFramework)'=='net10.0'" />
     ```
     Same pattern for `-lnx` and `-osx`. Apply on every X.x → (X+1).x bump that drops a supported TFM.
  2. **CI install scripts must be kept in sync — one branch per TFM.** Versions are pinned in `Build/Azure/scripts/db2.provider.sh` (lnx) and `Build/Azure/scripts/mac.db2.provider.sh` (osx). Both now carry the *same* TFM conditional as `Directory.Packages.props` (`if [ "$TFM" = "net10.0" ]` → 10.x, else → 9.x) and state `MUST match Net.IBM.Data.Db2-<plat> in Directory.Packages.props for this TFM` in a comment. So **every bump of either row updates the matching script branch**: bumping the net10 row bumps `DB2_PKG_VERSION` in the `net10.0` branch of both scripts; bumping the lower row bumps the `else` branch. Note both scripts also back the **informix** CI legs (`test-matrix.yml` `script_linux_local` / `script_macos_local`), not just db2, so a wrong version there breaks two providers.
     - *(Superseded rule, kept for context: this entry previously said "do not update these scripts when adding a TFM-conditional entry — CI runs the lower-TFM matrix and needs the older client." That predated the scripts gaining their own TFM conditional; since then, leaving them alone silently pins CI to a stale client. Corrected 2026-08-03 during 6.4.0 prep.)*
  3. **The LINQPad driver is a third consumer of these rows, and it ships the version to users.** `Source/LinqToDB.LINQPad` compiles the ids *and versions* into a generated `NuGetPackageVersions` class (the `GenerateNuGetPackageVersions` target in `LinqToDB.LINQPad.csproj`) and hands them to LINQPad, which downloads that client per connection. The item transforms expand against the **driver's own** TFM, `net8.0-windows7.0`, so only the **lower** row of the split above is ever picked up — bumping the `net10.0` row alone leaves every user's LINQPad downloading the old client, and nothing in the build says so. This one is *correct* as it stands (10.x ships a net10.0-only dependency group and the driver assembly is `lib/net8.0`), so the action is to **confirm it deliberately** on each bump rather than to sync it: if the driver should follow, the lower row has to move too. The csproj target carries the same warning at the resolution site.
  4. **API-surface diff via fuget** (see *Fuget API-diff procedure*) — diff between the previous active version and the new active version, reviewed by the user before commit.
- **Per-platform availability:** versions may differ across `-lnx` / `-osx` / windows variants. Update each to whatever's available; don't force them to the same version if one platform's release lags.
- **macOS natives are arm64-only, and that is the right match** — checked on `-osx` 9.0.0.400, which carries a single unqualified `buildTransitive/clidriver/` tree (no `runtimes/` folder) whose Mach-O headers are thin `arm64`. Not a gap: LINQPad 9 for macOS ships **Apple Silicon only** (linqpad.net offers `X64 + X86 + ARM64` for Windows but a single "for Apple silicon" macOS build), so the driver never runs on an Intel Mac. Don't add an architecture gate for this; re-check only if LINQPad ever ships an Intel macOS build.
- **Last verified:** 2026-08-19 on release 6.5.0 prep (PR #5786 review)

## Oracle.ManagedDataAccess

- **Release notes URL:** _none — release notes ship in the package README on nuget.org (https://www.nuget.org/packages/Oracle.ManagedDataAccess#readme-body-tab)_
- **Update rule:** Two version sites with **different ceilings**:
  1. The plain `<PackageVersion Include="Oracle.ManagedDataAccess" />` entry in `Directory.Packages.props` is **capped at the latest 21.x** stable. Versions 23.x produce test failures in linq2db (currently). Do not bump past 21.x without an explicit retest pass.
     - **"Capped at 21.x" means bump to the newest 21.x — not hold at the current value.** The discovery plan's `latestRelease` is the absolute latest (a 23.x), so this row needs the in-line maximum computed from the version cache (`.build/.agents/release-<ver>-deps-cache/oracle.manageddataaccess.json`, filter `21.*`, exclude prerelease). Reading only `latestRelease` makes the row look policy-blocked with no action, which silently skips real 21.x patches. (Caught by the user on 6.4.0 prep: proposed "no change" at 21.21.0 when 21.22.0 and 21.23.0 were both available.)
  2. The `$(OracleManagedLinqPadVersion)` property (referenced by the LINQPad-side `VersionOverride` site) **may be bumped to the latest stable** of the 23.x line. Updating the property cascades to every site that references it.
- **API surface diff via fuget** (see *Fuget API-diff procedure*) — apply on every bump of either site.
- **Last verified:** 2026-05-15 on release 6.3.0

## linq2db4iSeries

- **Release notes URL:** https://github.com/LinqToDB4iSeries/Linq2DB4iSeries/releases
- **Update rule:** Third-party DB2-iSeries provider that **mirrors the linq2db version** it's built against. Important for LINQPad support: if linq2db has any provider-API breaking change (public **or** internal) between the version this package targets and the linq2db version we're releasing, the package may not work in LINQPad. **Alert the user** before merging when the linq2db4iSeries version lags behind the about-to-be-released linq2db version, with a one-line note about which provider-API surface area changed.
- **Last verified:** 2026-05-15 on release 6.3.0

## Microsoft.Data.SqlClient

- **Release notes URL:** https://github.com/dotnet/SqlClient/blob/main/release-notes/README.md
- **Update rule:** **Public-API surface diff via fuget** (see *Fuget API-diff procedure*) — show diff to user before committing.
- **Last verified:** 2026-05-15 on release 6.3.0

## Meziantou.Analyzer

- **Release notes URL:** https://github.com/meziantou/Meziantou.Analyzer/releases
- **Rule catalog diff (cheapest reliable method):** the release notes span dozens of point releases, so don't read them serially. Diff the rule *docs* between the two tags — `gh api repos/meziantou/Meziantou.Analyzer/git/trees/<ver>?recursive=1` filtered to `^docs/Rules/MA[0-9]+[.]md$` gives the full catalog per version, and the set difference is the new-rule list. For new **options** on existing rules, use `gh api repos/meziantou/Meziantou.Analyzer/compare/<old>...<new>` filtered to the same path and read added lines matching `MA0\d{3}\.` — an option change shows as a doc edit on an existing rule. Default severities come from the README rule table (`Id|Category|Description|Severity|Is enabled|Code fix|Configurable`), not the per-rule docs.
- **Rendering:** present each rule as a markdown link to `https://github.com/meziantou/Meziantou.Analyzer/blob/main/docs/Rules/<ID>.md`, never as a bare `MAxxxx` — the user opens the doc per rule to decide severity.
- **Update rule:** On every bump:
  1. Diff the rule catalog per the method above. Identify new rules (`MAxxxx`) and new rule options.
  2. Enable each new rule as **error** severity in the repo `.editorconfig`. For new rule **options** (not new rules), ask the user before enabling.
     - An option on a rule that is currently `severity = none` is a **no-op** — say so when proposing it, and ask whether the user also wants the rule re-enabled (which may carry a large build cost) or just the option line recorded for later.
  3. After update + verification Release build, observe which new rules raised errors. For each rule that raised errors, ask the user: fix the errors, or disable the rule (set severity = none in `.editorconfig`).
  4. **Once the build is clean**, run the profiling pass (`/release-verify` step 3) — Meziantou is historically the dominant analyzer cost in this repo (6.3.0 prep disabled `MA0002` at ~995s/build and `MA0182` at ~1233s/build purely on cost), so both newly-enabled rules and regressions on existing ones need measuring before the release ships.
  5. **First-time-this-rule update only:** also catch up on previously-missed rules — audit the analyzer's full rule catalog at the target version against the current `.editorconfig` and enable any missing rules using the same procedure. Do **not** touch rules that were already explicitly enabled or disabled in `.editorconfig`.
- **Last verified:** 2026-09-09 on release 6.5.0 prep (3.0.138 → 3.0.231: 13 new rules MA0213-MA0225; ~14 existing rules gained options, **all of them no-ops or default-preserving** — 7 landed on rules the repo holds at `severity = none`, the rest default to current behaviour, and `MA0007.ignore_catch_all_arm` / `MA0115.report_pascal_case_unmatched_parameter` are renames of existing options). Previously 2026-08-03 on 6.4.0 (3.0.85 → 3.0.138: 12 new rules MA0201-MA0212, 8 rules gained options).
- **Check reachability before assigning severity — several MA rules are structurally dead here.** On the 3.0.231 walk, 5 of 13 new rules had provably zero findings (`MA0216` no union types, `MA0218` no `language=` attributes, `MA0220` no `*_regex` options in `.editorconfig`, `MA0222`/`MA0223` no `JsonSourceGenerationOptions` anywhere), which makes them free to enable as `error`. Two more were decided on *reach*, not taste: `MA0221` had exactly one site, and `MA0224`/`MA0225` had four `JsonSerializerOptions` construction sites whose fix is a **deserialization behaviour change** to user-facing CLI/LINQPad config JSON — held at `none` as out-of-scope for release prep. A grep per rule is cheaper than a build cycle.
- **Watch for mutually-inverse rule pairs.** `MA0214` ("use await instead of returning the task") and `MA0215` ("return the task instead of awaiting it") contradict each other; enabling both makes every call site wrong either way. linq2db returns the task directly wherever possible, so `MA0215` = error and `MA0214` = none. The blanket "enable each new rule as error" step must not be applied mechanically across such a pair.

## Microsoft.CodeAnalysis.CSharp (the central runtime pin, **not** the 4.8.0 analyzer floor)

- **Release notes URL:** _none per package version — `dotnet/roslyn` versions its releases by `dev17.x`/`dev18.x` branches that do not map to the 4.x/5.x package numbers, and `dotnet/roslyn-analyzers` tags stop at `v3.11.0`._
- **Three separate consumers, and they straddle the TFM boundary:** `Source/CodeGenerators` (netstandard2.0, `PrivateAssets=all`), `Source/LinqToDB.CLI` (net8.0/net9.0/net10.0, **`PackAsTool` so it bundles what it resolves**), and the **net472 lpx** build of `Source/LinqToDB.LINQPad` (line ~49; the *nuget* driver at line ~72 is pinned separately to `$(RoslynLinqPadVersion)` and is not affected). `Source/LinqToDB.Analyzers` overrides to 4.8.0 and is likewise unaffected.
- **Update rule — read the *asset* groups, not just the version.** `5.9.0` **dropped the `lib/net8.0` asset** that `5.6.0` shipped (`5.6.0`: net10.0 + net8.0 + netstandard2.0; `5.9.0`: net10.0 + netstandard2.0). Nothing fails — net8.0/net9.0 silently fall back to `lib/netstandard2.0`, whose dependency group drags in `System.Buffers`, `System.Memory`, `System.Numerics.Vectors`, `System.Runtime.CompilerServices.Unsafe`, `System.Text.Encoding.CodePages`, `System.Threading.Tasks.Extensions`, all in-box on .NET 8+ — and the packed CLI then **ships** them. Compare `<group targetFramework=…>` between the current and target nuspec on every bump (`inspect-nupkg.ps1`).
- **Resolution adopted on 6.5.0 prep — a TFM split keyed on the *gap*, not on a compatibility floor:**
  ```xml
  <PackageVersion Include="Microsoft.CodeAnalysis.CSharp" Version="5.6.0" Condition=" '$(TargetFramework)' == 'net8.0' or '$(TargetFramework)' == 'net9.0' "   />
  <PackageVersion Include="Microsoft.CodeAnalysis.CSharp" Version="5.9.0" Condition=" '$(TargetFramework)' != 'net8.0' and '$(TargetFramework)' != 'net9.0' " />
  ```
  Only net8.0/net9.0 lose a native asset, so only they hold back; `netstandard2.0` and `net472` already resolve the netstandard2.0 asset and get 5.9.0 for free. Confirmed empirically by the notices harvest, which reported `Microsoft.CodeAnalysis.CSharp` moving on `net10.0` and `net472` only, with **no new bundled packages**.
- **Co-bump constraint:** `5.9.0` requires `Microsoft.CodeAnalysis.Analyzers >= 5.9.0-1.26328.17` (up from 5.3.0). `Source/CodeGenerators` references *both* directly, so once its branch resolves 5.9.0 the `Analyzers` pin **must** move to stable 5.9.0 or restore fails **NU1605** under `TreatWarningsAsErrors`. Stable `5.9.0` sorts above the prerelease floor, so it satisfies it.
- **Downstream obligation:** the vendored docfx build in `linq2db/docs` tracks this version — bumping it books a rebuild + re-vendor of the `MaceWindu/docfx` fork (`custom/linq2db`) before `/release-postpublish`'s docs PR. See [`external-repos.md`](./external-repos.md).
- **Also update** `Tests/Tests.Analyzers.Internal`'s `Microsoft.CodeAnalysis.CSharp.Workspaces` `VersionOverride`, which is *defined* as matching the Roslyn `CodeGenerators` builds against — and `CodeGenerators` is netstandard2.0, so under the split above it follows the **upper** branch. (Its inline comment says "4.8 host"; the project itself targets `net10.0`.)
- **Last verified:** 2026-09-09 on release 6.5.0 prep (5.6.0 → conditional 5.6.0/5.9.0)

## Microsoft.CodeAnalysis.Analyzers

- **Release notes URL:** _none obtainable per version._ The RS1xxx/RS2xxx catalog cannot be diffed cheaply: `dotnet/roslyn-analyzers` tags stop at `v3.11.0`, the source has since moved into `dotnet/roslyn` (which versions by `dev18.x` branches), and the package ships no rule manifest. **A raw byte-scan of the analyzer assemblies for `RS\d{4}` is unreliable — do not use it**: on 6.5.0 prep it "reported" RS1001/RS1003/RS2001 as *added* in 5.9.0, which are among the oldest rules in the package (the scan aliases across the string heaps).
- **Update rule:** bump freely and let `/release-verify`'s reactive walk surface new diagnostics. Blast radius is small and never shipped: `PrivateAssets="all"` in `Source/Analyzers.Common.props` (→ `LinqToDB.Analyzers` + `.CodeFixes`) and `Source/CodeGenerators` — all netstandard2.0, so a TFM-conditional split on this id would be a **dead row**. Package shape is stable (5.6.0 and 5.9.0 both have no dependency groups and the same 30 assemblies).
- **Last verified:** 2026-09-09 on release 6.5.0 prep (5.6.0 → 5.9.0, forced by the Roslyn co-bump constraint above)

## protobuf-net / protobuf-net.Grpc / protobuf-net.Grpc.AspNetCore

- **Release notes URL:** https://github.com/protobuf-net/protobuf-net/releases and https://github.com/protobuf-net/protobuf-net.Grpc/releases
- **`protobuf-net` is safe to track;** 3.2.56 → 3.4.21 had **0 additions and 0 removals** across all four TFMs (net462, net8.0, netstandard2.0, netstandard2.1) with unchanged dependency groups. Verify via fuget rather than assuming a 3.2→3.4 jump is risky.
- **`protobuf-net.Grpc` 1.3.x dropped net462 and raised its compat floors — the whole line, not just the newest.** 1.3.0, 1.3.6 and 1.3.14 all ship `.NETFramework4.7.2` (was `4.6.2`) and require `Microsoft.Bcl.AsyncInterfaces` / `System.IO.Pipelines` / `System.Threading.Channels` at **10.0.8** (was 8.0.0), plus `Grpc.Core.Api` 2.80.0. There is no intermediate version that avoids either — check 1.3.0 before proposing a split.
- **Why that matters:** `Source/LinqToDB.Remote.Grpc` declares no TFMs and so inherits `net462;netstandard2.0;net8.0;net9.0;net10.0` from `Directory.Build.props`. Restore does not fail (net462 falls back to the netstandard2.0 asset), but the shipped `linq2db.Remote.Grpc` then imposes `Microsoft.Bcl.AsyncInterfaces >= 10.0.8` on consumers, against a central pin deliberately held at 8.0.0 by the [#3953](https://github.com/linq2db/linq2db/issues/3953) runtime-pin policy. It does **not** affect the bundled-notices manifest, because Remote.Grpc is not one of the three bundling projects.
- **Decision on 6.5.0 prep:** maintainer accepted the bump and the constraint escalation (all three ids to 1.3.14), with the standing question of whether net462 is still worth supporting on the gRPC remote package left open. `protobuf-net.Grpc.AspNetCore`'s `Tests/Base` reference sits inside a `'$(TargetFramework)' != 'net462'` ItemGroup, so only `LinqToDB.Remote.Grpc` is exposed to the netfx half.
- **Last verified:** 2026-09-09 on release 6.5.0 prep

## ModelContextProtocol (+ .Core)

- **Release notes URL:** https://github.com/modelcontextprotocol/csharp-sdk/releases
- **Update rule:** shipped inside `linq2db.cli` (the MCP server), so diff the API surface via fuget before taking a minor bump — the CLI is published to the MCP Registry, so a breaking change there is consumer-visible. `.Core` is pinned exactly (`[<version>]`) by the metapackage, so the two always move together.
- **Last verified:** 2026-09-09 on release 6.5.0 prep (2.0.0 → 2.2.0: **0 removals**, 4 additions, all TFM groups intact — the whole delta is a new `SubscriptionsListenHandler` / `WithSubscriptionsListenHandler` capability)

## Microsoft.Testing.Platform + Microsoft.Testing.Extensions.\* (`$(MicrosoftTestingVersion)`)

- **Release notes URL:** _none per MTP version._ `microsoft/testfx` hosts the code but tags **MSTest** versions (3.x/4.x), not MTP's 2.x line, so there is no release body to read for a 2.3.3 → 2.4.0 bump.
- **Risk surface is this repo's own MTP extension, not the runner itself.** `Tests/Base/TestProgressReporter.cs`, `TestProgressState.cs`, `TestRunCommandLineProvider.cs` and `TestCommandLine.cs` implement the `--test-progress` heartbeat that every test run in this workflow depends on, registered per-assembly via three `AssemblyInfo.TestProgress.cs` files. An MTP minor can move `ITestApplicationBuilder` / `IDataConsumer`, which shows up as a `Tests.Base` compile error — or, worse, as a silently missing heartbeat. Nothing shipped is affected.
- **All five rows move together** via the shared property; check that every `Microsoft.Testing.Extensions.*` id has the target version published, not just `Microsoft.Testing.Platform`.
- **Last verified:** 2026-09-09 on release 6.5.0 prep (2.3.3 → 2.4.0)

## Microting.EntityFrameworkCore.MySql

- **Release notes URL:** https://github.com/microting/EntityFrameworkCore.MySql/releases
- **Update rule:** EF Core 10 fork of Pomelo (whose own newest line is EF Core 9). Its versions track EF Core patch numbers 1:1, so keep it in step with `$(Net10Latest)` — but when Microting lags, take **the newest release whose own dependency floors `$(Net10Latest)` already satisfies**, per *Prefer the version whose dependencies the repo's pins already satisfy*. Do not hold at an older version merely because the numbers no longer match exactly.
- **Worked history:** on [#5885](https://github.com/linq2db/linq2db/pull/5885) (2026-09-06) 10.0.11 was **declined** — it needs Relational `[10.0.11, …]` + MySqlConnector `2.6.2` against pins of 10.0.10 / 2.6.1 ("as dependency not satisfied yet, use 10.0.10"). On 6.5.0 prep the same version was **taken**, because `$(Net10Latest)` → 10.0.12 and MySqlConnector → 2.6.2 satisfied both floors. Same package, opposite answer, decided purely by the pins around it.
- **Last verified:** 2026-09-09 on release 6.5.0 prep (10.0.10 → 10.0.11, while `$(Net10Latest)` went to 10.0.12)

## Microsoft.SourceLink.GitHub

- **Release notes URL:** https://github.com/dotnet/sourcelink/releases
- **Last verified:** 2026-09-09 on release 6.5.0 prep (10.0.303 → 10.0.401)

## Microsoft.SqlServer.TransactSql.ScriptDom

- **Release notes URL:** https://github.com/microsoft/SqlScriptDOM/blob/main/release-notes/ (root; per-version pages sit under it, e.g. `release-notes/180/180.102.0.md`)
- **Last verified:** 2026-09-09 on release 6.5.0 prep (180.78.1 → 180.102.0)

## MySqlConnector

- **Release notes URL:** https://mysqlconnector.net/overview/version-history/
- **Co-bump:** gates `Microting.EntityFrameworkCore.MySql` (see its entry) — 10.0.11 requires MySqlConnector 2.6.2.
- **Last verified:** 2026-09-09 on release 6.5.0 prep (2.6.1 → 2.6.2)

## OpenTelemetry / OpenTelemetry.Exporter.Console (`$(OpenTelemetryVersion)`)

- **Release notes URL:** https://github.com/open-telemetry/opentelemetry-dotnet/releases
- **Update rule:** both ids move together via the shared property; Examples-only, nothing shipped.
- **Last verified:** 2026-09-09 on release 6.5.0 prep (1.17.0 → 1.18.0)

## `$(AspNetCoreLegacyVersion)` / `$(SignalRLegacyVersion)` — the ASP.NET Core 2.x-era rows

- **Release notes URL:** https://github.com/dotnet/aspnetcore/releases
- **Update rule:** these lines (`Microsoft.AspNetCore` + `Kestrel.Core` at 2.3.x; `Microsoft.AspNetCore.SignalR` + `SignalR.Client` + `SignalR.Core` at 1.2.x) are long out of support and only ever get security republishes, so track the newest patch within the line. **`$(SignalRLegacyVersion)` is not test-only** — `SignalR.Core` and the `!net8+` branch of `SignalR.Client` are shipping rows, so treat it as a consumer-visible bump and check advisories (`gh api 'advisories?ecosystem=nuget&affects=<id>'`) rather than assuming a netfx-only blast radius.
- **Last verified:** 2026-09-09 on release 6.5.0 prep (2.3.11 → 2.3.13, 1.2.11 → 1.2.13; no advisories on either)

## `$(Net8Latest)` / `$(Net9Latest)` / `$(Net10Latest)` — the .NET patch-line properties

- **Release notes URL:** https://github.com/dotnet/core/tree/main/release-notes
- **Update rule:** auto-bump to the newest stable patch of the line without asking (per the *`*Latest` MSBuild properties* category). **But verify the target exists for every consuming id, not just one** — these properties feed 20+ rows across unrelated packages, and the .NET libraries do not all ship the same patch numbers (`Microsoft.Extensions.Logging.Console` has no 8.0.x beyond 8.0.1; `System.Data.Odbc`/`OleDb` stop at 8.0.1; `Microsoft.Bcl.Memory` has no 8.0.x at all). Compute the per-line maximum per id from the deps cache before editing.
- **`$(Net10Latest)` has two non-obvious couplings:** it drives `Microsoft.Data.Sqlite`, which (a) triggers the *SQLite version-assert sync* rule under `SourceGear.sqlite3`, and (b) determines the transitive `SQLitePCLRaw.*` version — at 10.0.12 that became **2.1.12**, moving the graph above `GHSA-2m69-gcr7-jv3q`'s `<= 2.1.11` range for the first time. It also gates `Microting.EntityFrameworkCore.MySql`.
- **Last verified:** 2026-09-09 on release 6.5.0 prep (8.0.29 → 8.0.31, 9.0.18 → 9.0.20, 10.0.10 → 10.0.12)

## Microsoft.CodeAnalysis.CSharp.Workspaces (+ Microsoft.CodeAnalysis.CSharp for the analyzer project)

- **Update rule:** Roslyn baseline for the **shipped** `linq2db.Analyzers` package (NOT the internal 5.3.0 `Microsoft.CodeAnalysis.CSharp` runtime pin used by the linq2db library). **Track the Roslyn bundled with the lowest supported .NET SDK** — today .NET 8 → **4.8.0**. It sets the minimum VS / .NET SDK a consumer needs for the analyzer + code fix to load, so keep it low for IDE reach (mirrors NUnit.Analyzers' broad-reach approach). Only raise it when the lowest supported SDK is dropped; downgrade in a later release if users report their IDE/SDK is too old. Referenced via `VersionOverride` / a dedicated central `<PackageVersion>`, `PrivateAssets="all"`; `CentralPackageTransitivePinningEnabled=false` keeps its transitive CodeAnalysis assemblies from clashing with the 5.3.0 runtime pin. See [`authoring-analyzers.md`](../authoring-analyzers.md).
- **Last verified:** 2026-07-10 on the linq2db.Analyzers package work
