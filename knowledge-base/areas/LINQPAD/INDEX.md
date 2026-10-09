---
area: LINQPAD
kind: area-index
sources: [code]
confidence: high
last_verified: 2026-10-09
last_verified_sha: 05150894edc2511f0dd0bc7829b2a309cec36ec9
coverage_tier_1: 15/15
coverage_tier_2: 48/51
---

# LINQPAD

LINQPad driver for linq2db. Exposes two driver modes (dynamic and static) to LINQPad 5/6/7 via the `LINQPad.Extensibility.DataContext` SDK. TFMs: `net472` (LINQPad 5) and `net8.0-windows7.0` (LINQPad 8/9 NuGet driver, Windows and macOS). Assembly name: `linq2db.LINQPad`. Only the net472 build is now packed into an `.lpx` bundle (MSBuild `PostBuild2` target calls `NuGet/Pack.cmd`); the `.lpx6` pack step and its `PostBuild1` target were removed. NuGet packaging is handled by the dedicated sibling `LinqToDB.LINQPad.Pack.csproj` (see Subsystems -- Build / Packaging below). Database client packages are no longer static dependencies of the NuGet driver: LINQPad provisions them per connection (see Subsystems -- Per-connection client provisioning).

## Subsystems

### Driver layer (`Drivers/`)

Two public driver classes, both prefixed `LinqToDB` as required by the LINQPad SDK -- renaming them would break all existing saved connections:

- **`LinqToDBDriver`** (`DynamicLinqToDBDriver.cs`): subclasses `DynamicDataContextDriver`. Implements `GetSchemaAndBuildAssembly` -- queries the SCAFFOLD library via `DynamicSchemaGenerator.GetModel`, receives back a C# source string and an `ExplorerItem` tree, then Roslyn-compiles the generated source into the output assembly. On net8.0-windows it applies a runtime-token fallback to resolve provider assembly references; the token regex now accepts both `\` and `/` separators and the replacement uses `Path.DirectorySeparatorChar` (macOS paths). On non-NETFRAMEWORK it also overrides `OverrideDriverDependencies` and `TestConnectionCore`. `GetLastSchemaUpdate` failures are logged (not shown) because LINQPad calls it before the connection's client is downloaded.
- **`LinqToDBStaticDriver`** (`StaticLinqToDBDriver.cs`): subclasses `StaticDataContextDriver`. Implements `GetSchema` -- reflects the caller-supplied assembly type using `StaticSchemaGenerator.GetSchema`. On non-NETFRAMEWORK overrides `OverrideDriverDependencies` (`isDynamic: false`).
- **`DriverHelper`** (`Drivers/DriverHelper.cs`): `internal static` shared across both drivers. Handles `Init()`, `InitializeContext` (wires linq2db's `TraceInfo` to `QueryExecutionManager.SqlTranslationWriter`), `ShowConnectionDialog`, `HandleException`, `LogException`, `GetAssembliesToAdd`, `OverrideDriverDependencies`, `TestConnection`. `Init()` registers assembly resolvers for `Microsoft.Extensions.Logging.Abstractions`, `System.Collections.Immutable`, and now `System.Threading.Channels` (Npgsql 8.0.9 references 8.0.0.0) and `System.Reflection.Metadata` (needed again after the Roslyn 5.6 bump: .NET Framework binds by exact version, LINQPad 5 otherwise fails with `FileLoadException`). `ShowConnectionDialog` brackets the dialog with `Notification.BeginConnectionDialog()` / `EndConnectionDialog()`. `ClearConnectionPools` and `GetAssembliesToAdd` failures go to `LogException` (no dialog) because they can be called before the client is downloaded.
- **`PasswordManager`** (`Drivers/PasswordManager.cs`): resolves `{pm:name}` tokens via `LINQPad.Util.GetPassword`.
- **`ValueFormatter`** (`Drivers/ValueFormatter.cs`): converts provider-specific value types into LINQPad-renderable equivalents via three `FrozenDictionary` lookup tables. Provider-specific registrations (ClickHouse, Firebird, Sybase, MySql, Npgsql, Oracle) now live in separate `[MethodImpl(NoInlining)]` `Add*Converters` methods invoked through a `Register` wrapper that swallows `FileNotFoundException` / `FileLoadException` / `TypeLoadException` / `BadImageFormatException`, because the provider assembly loads when the method is JIT-compiled and only the connection's database client is provisioned. SQL Server spatial types (`SqlGeography`/`SqlGeometry`) and HANA/DB2 types are registered by type-name string in `byTypeNameConverters`; `IsNull` checks Oracle `INullable` via a name prefix plus a non-inlined `IsOracleNull`.

### Per-connection client provisioning (non-NETFRAMEWORK)

LINQPad downloads NuGet packages per connection via `DataContextDriver.OverrideDriverDependencies`. `DriverHelper.OverrideDriverDependencies(dependencyInfo, isDynamic)`:
- dynamic with a saved database + provider: `IDatabaseProvider.GetNuGetPackages(provider)` for the primary (and secondary) provider;
- static context with `StaticContextOptions.Database` set: `DatabaseProviders.GetNuGetPackages(provider)` (all providers of that database);
- otherwise (new connection, static context without a database): `DatabaseProviders.GetAllNuGetPackages()`, skipping providers where `IsPlatformSupported` is false.

`IDatabaseProvider.GetNuGetPackages` is `#if !NETFRAMEWORK`; `DatabaseProviderBase` defaults to empty. Versions come from the generated `NuGetPackageVersions` class (see Build / Packaging). Notable per-provider sets: Access (`System.Data.Odbc` for ODBC, else `System.Data.OleDb`), ClickHouse (`MySqlConnector` / `Octonica.ClickHouseClient` / `ClickHouse.Driver`), DB2 and Informix (`DB2Provider.ClientPackage`: `Net.IBM.Data.Db2` on Windows, `-osx` on macOS, `-lnx` otherwise), SQLite (`System.Data.SQLite` or `Microsoft.Data.Sqlite`, plus `SQLitePCLRaw.lib.e_sqlite3`), SQL Server (`Microsoft.Data.SqlClient` plus `Microsoft.SqlServer.Types` on Windows or `dotMorten.Microsoft.SqlServer.Types` elsewhere), SAP HANA (`System.Data.Odbc` only for ODBC; native assembly is user-supplied), plus single-package DuckDB / Firebird / MySql / Oracle / PostgreSQL (`Npgsql`) / Sybase ASE / YDB (`Ydb.Sdk`).

Because a client assembly loads when a method referencing its types is JIT-compiled, providers with several clients (Access, ClickHouse, SQLite, SapHanaProvider ODBC) touch each client from its own `[MethodImpl(NoInlining)]` method (`GetOdbcFactory`, `ReleaseOleDbPool`, `ClearMySqlPools`, ...).

`TestConnection`: the connection dialog runs in LINQPad's own process, which has only the driver's static dependencies. On NETFRAMEWORK the dialog opens the connection itself (`OpenConnections`); on net8.0-windows it calls `settings.Save(cxInfo)` then `DataContextDriver.TestConnection`, which runs `DriverHelper.TestConnection` (-> `OpenConnections`) in the driver process and returns the formatted message.

### Schema generation (`Drivers/DynamicSchemaGenerator.cs`, `Drivers/StaticSchemaGenerator.cs`, `Drivers/Scaffold/`)

- **`DynamicSchemaGenerator.GetModel`**: bridges `ConnectionSettings` to the SCAFFOLD library. Constructs a `ScaffoldOptions`, creates a `Scaffolder`, runs `LoadDataModel -> GenerateCodeModel -> GenerateSourceCode`. Injects `DataModelAugmentor` to add the three-parameter `LINQPadDataConnection` constructor to the generated context class.
- **`ModelProviderInterceptor`**: implements `ScaffoldInterceptors`. Accumulates the full logical model in `AfterSourceCodeGenerated`, then converts it to an `ExplorerItem` tree in `GetTree()`.
- **`DataModelAugmentor`**: `ConvertCodeModelVisitor` subclass. Identifies the generated `DataContext` class, injects a public `(string provider, string? assemblyPath, string connectionString)` constructor.
- **`StaticSchemaGenerator.GetSchema`**: reflects the custom context type's `IQueryable<T>` properties and reads `[Table]`/`[Column]`/`[Association]` attributes.

### Provider registry (`DatabaseProviders/`)

`DatabaseProviders` (static) holds two `FrozenDictionary` tables: `Providers` (keyed by `ProviderName` generic DB string) and `ProvidersByProviderName` (keyed by specific provider name string). On net8.0-windows, DB2 and Informix are registered only on 64-bit processes; `DuckDBProvider` and `YdbProvider` are registered unconditionally on net8.0-windows (outside the 64-bit guard, `DatabaseProviders.cs:36-37`); on net472 both DuckDB and YDB are absent (`YdbProvider.cs` is wrapped in `#if !NETFRAMEWORK`, matching `DuckDBProvider`). Two non-NETFRAMEWORK helpers were added: `GetAllNuGetPackages()` (all platform-supported providers) and `GetNuGetPackages(IDatabaseProvider)` (all providers of one database).

`IDatabaseProvider` defines the contract: `Database`, `Description`, `Providers`, `GetDataProvider`, `GetProviderFactory`, `GetAdditionalReferences`, `IsProviderPathSupported`, `RegisterProviderFactory`, `AutomaticProviderSelection`, `GetProviderByConnectionString`, `GetLastSchemaUpdate`, `ClearAllPools`, plus `IsPlatformSupported` and (non-NETFRAMEWORK) `GetNuGetPackages`.

`DatabaseProviderBase` provides virtual no-op defaults (`IsPlatformSupported => true`, `GetNuGetPackages => []`); concrete providers override only what they need.

`Platform` (`Platform.cs`, new): `internal static` host-OS checks (`IsWindows`, `IsMacOS`); folds to constants on net472 (Windows only), `System.OperatingSystem` on net8.0-windows. Replaces direct `OperatingSystem.IsWindows()` calls in providers.

15 concrete provider classes:
- `SqlServerProvider`: on net8.0-windows overrides `GetDataProvider` to hardcode `Microsoft.Data.SqlClient`. On non-NETFRAMEWORK the spatial-types assembly is no longer referenced statically: `GetAdditionalReferences` lazily loads `Microsoft.SqlServer.Types.dll` via `DataContextDriver.LoadAssemblySafely`, logging (and not caching) failures.
- `AccessProvider`: `AutomaticProviderSelection = true`; `SupportsSecondaryConnection = true`; `IsPlatformSupported => Platform.IsWindows` (OLE DB / Access ODBC unavailable elsewhere).
- `SqlCeProvider`: `IsPlatformSupported => Platform.IsWindows` (native engine).
- **`DuckDBProvider`**: net8.0-windows only (`#if !NETFRAMEWORK`). Single `ProviderInfo` entry (`ProviderName.DuckDB`, display name `"DuckDB"`, `IsDefault = true`). Overrides `GetProviderFactory` to return `DuckDBClientFactory.Instance`; `GetLastSchemaUpdate` returns `null`; `ClearAllPools` is a no-op.
- **`YdbProvider`** (`DatabaseProviders/YdbProvider.cs`): net8.0-windows only (`#if !NETFRAMEWORK`), same exemption from the 64-bit guard as `DuckDBProvider`. Single `ProviderInfo` entry (`ProviderName.Ydb`, display name `"YDB"`, `IsDefault = true`). `GetProviderFactory` returns `YdbProviderFactory.Instance`; `ClearAllPools` calls `YdbConnection.ClearAllPools().GetAwaiter().GetResult()` (async API bridged synchronously); `GetLastSchemaUpdate` returns `null` (unimplemented, same as DuckDB).
- **`PostgreSQLProvider`** (`DatabaseProviders/PostgreSQLProvider.cs`): exposes eight dialect-detection `ProviderInfo` entries -- `ProviderName.PostgreSQL` (auto-detect, default), `PostgreSQL92/93/95/13/15/18/19` (`PostgreSQL19` added in an earlier delta, `"PostgreSQL 19 Dialect"`, `PostgreSQLProvider.cs:20`). `GetProviderFactory` returns `NpgsqlFactory.Instance`; `ClearAllPools` calls `NpgsqlConnection.ClearAllPools()`; `GetLastSchemaUpdate` returns `null`.
- `SQLiteProvider`: static ctor now sets `PreLoadSQLite_BaseDirectory` to `AppDomain.CurrentDomain.BaseDirectory` (previously the `sds` subfolder of it); both clients are SQLitePCLRaw-based and share the `runtimes/` `e_sqlite3` native.

`ProviderInfo` record: `Name`, `DisplayName`, `IsDefault`, `IsHidden`, `Troubleshoot`.

### Configuration (`Configuration/`)

**`ConnectionSettings`**: root settings object, serialized as JSON inside LINQPad's `IConnectionInfo.DriverData`. Contains `ConnectionOptions`, `SchemaOptions`, `ScaffoldOptions`, `LinqToDbOptions`, `StaticContextOptions`. `Save` now restores the plain `SecondaryConnectionString` in a `finally` after encrypting it (the dialog saves before testing and again on OK, encrypting the live value twice corrupted it). `StaticContextOptions.Database` (new, `string?`) names the database a static context uses, only to limit which clients are provisioned.

`ConnectionOptions.ProviderPath` is computed: dispatches to `ProviderPathx86` or `ProviderPathx64` based on `IntPtr.Size`.

**`AppConfig`**: `ILinqToDBSettings` implementation. Parses `appsettings.json` or `app.config` XML.

### WPF UI (`UI/`)

Dialog hosted as `SettingsDialog` (XAML `Window`). `DataContext` is `SettingsModel`, which aggregates seven sub-models. `ModelBase` provides a pattern for raised-per-property static `PropertyChangedEventArgs` instances.

**`Notification`** (`UI/Notification.cs`): all driver errors are written to `linq2db.LINQPad.log` (`LogFileName`) through `DataContextDriver.WriteToLog` (`Log`, never throws). Message boxes are shown only when `CanShowMessageBox`: always on net472, and on net8.0-windows when on Windows or inside a connection dialog (thread-static `_connectionDialogScope` set by `BeginConnectionDialog`/`EndConnectionDialog`). Reason: on macOS LINQPad renders driver WPF through Avalonia XPF only during `ShowConnectionDialog`, touching `MessageBox` elsewhere fails to load `PresentationFramework`. The unowned `MessageBox.Show` lives in a separate non-inlined `ShowError`. API: `Error(Exception, context, title)`, `Error(string, title)`, `Error(Window, string|Exception, title)`, `FormatMessages(Exception)` (all inner messages), `Warning`, `YesNo`, `Info`. `Source/LinqToDB.LINQPad/BannedSymbols.txt` (new) bans `System.Windows.MessageBox` elsewhere (RS0030 suppressed per use in `Notification`).

**`AboutModel`** (`UI/Model/AboutModel.cs`): singleton (`Instance` property). Reads the driver version at runtime via `typeof(AboutModel).Assembly.GetName().Version` (three-part) -- no hardcoded version string. Constructs `Logo` from a `pack://` URI pointing to `Resources/Logo.png` embedded in the assembly; guards against `UriParser` initialization order with an `Application()` constructor call when `"pack"` is not yet a known scheme. Exposes `Project` (display string), `Copyright` (from `AssemblyCopyrightAttribute`), `RepositoryUri`, and `ReportsUri`. Bound by `AboutTab.xaml` (`UI/Settings/AboutTab.xaml`).

**`DynamicConnectionTab`** (`UI/Settings/DynamicConnectionTab.xaml`): `UserControl` with design-time `DataContext` of type `DynamicConnectionModel`. Renders: Database Type `ComboBox` (bound `Databases`/`Database`), Provider `ComboBox` (bound `Providers`/`Provider`, visibility-gated), provider-path `TextBox` + Select button (visibility-gated), connection string `TextBox` (multiline, with `{pm:name}` tooltip), secondary connection string panel (MS Access only, visibility-gated), Encrypt connection strings `CheckBox`, and command timeout `TextBox` (via `CommandTimeoutConverter`). `DynamicConnectionModel` now lists only `IsPlatformSupported` databases, except the one already configured (kept so the combo does not clear it).

**`StaticConnectionModel` / `StaticConnectionTab`**: new `Database` combo (`SelectedDatabase`, `DatabaseChoice` record, first entry `"(all databases)"` = null, list empty and `ClientDownloadVisibility` collapsed on net472) bound to `StaticContextOptions.Database`. The Context combo is now editable (`Text` binding). `StaticConnectionTab.LoadContextTypes` uses `assembly.GetTypes()` with `ReflectionTypeLoadException` handling and an `IsVisible` filter instead of `GetExportedTypes`; `ReportContextLoadFailure` logs when some context types were listed, shows a dialog only when the list is empty. `SettingsDialog.xaml.cs` now shows `Notification.FormatMessages(ex)` / `Notification.Error(this, ex, ...)`.

### Compat (`Compat/`)

`IReadOnlySet<T>`, `ReadOnlyHashSet<T>`, `ReadOnlySetExtensions` -- polyfills guarded with `#if NETFRAMEWORK`. On net8.0-windows the BCL's native `IReadOnlySet<T>` is used.

### Build / Packaging

Two project files govern the area:

- **`LinqToDB.LINQPad.csproj`** (`Microsoft.NET.Sdk.WindowsDesktop`): the WPF driver assembly, TFMs `net472` + `net8.0-windows7.0`. `UseWPF=true`, `IsPackable=false`. The `.lpx` is generated only for net472 by `PostBuild2` (now also copies `SQLitePCLRaw.lib.e_sqlite3` natives for win-x86/win-x64 only, removes `win-arm64`, drops `THIRD-PARTY-NOTICES.txt` into the output, then calls `Pack.cmd` unless `GenerateLpxArtifacts=false`). Page Update items for all nine XAML files are declared here. `Microsoft.CodeAnalysis.CSharp` is plain on net472 and uses `VersionOverride` of `RoslynLinqPadVersion` on non-net472 (host in-box `System.Collections.Immutable`/`System.Reflection.Metadata` win, floor 8.0.0); `System.Collections.Immutable` is pinned to `Net8LatestForNuget` (NU1605 suppressed, #5768). `Microsoft.SqlServer.Types` is referenced only on net472 so the .NET build never binds it at compile time. Non-net472 `GenerateNuGetPackageVersions` target (BeforeTargets=BeforeCompile) emits `NuGetPackageVersions.g.cs` (internal class, one const per client package, generated from central `PackageVersion` entries, errors if any id expands to an empty string). The net8.0 branch of a central version must be bumped alongside net10.0 entries for DB2 packages. PublicAPI baselines are removed, `BannedSymbols.txt` is registered as an `AdditionalFiles` item.
- **`LinqToDB.LINQPad.Pack.csproj`** (`Microsoft.NET.Sdk`): packaging-only, single TFM `net8.0`. Does NOT recompile the driver. References `LinqToDB.LINQPad.csproj` with `ReferenceOutputAssembly=false` for build ordering, then pulls the `net8.0-windows7.0` driver assembly into `lib/net8.0/` via the `_AddLinqPadDriverToPackage` MSBuild target (calls `GetTargetPath` on the sibling). Motivation: LINQPad on macOS/Linux rejected a `net8.0-windows7.0`-only package ("No compatible assemblies found", issue #5497); packing under plain `net8.0` restores the pre-#5279 layout. `EnableDefaultItems=false`, `IncludeBuildOutput=false`. Package dependencies are now only `LinqToDB.Scaffold`, `LINQPad.Reference`, `Microsoft.CodeAnalysis.CSharp` (`RoslynLinqPadVersion`) and conditional `linq2db4iSeries`; all database client `PackageReference`s (including `DuckDB.NET.Data.Full` and `Ydb.Sdk`) and the `SQLite.Runtime.props` import were removed. The Description element (line 40) now lists DuckDB and YDB.

## Key types

| Type | File | Role |
|---|---|---|
| `LinqToDBDriver` | `Drivers/DynamicLinqToDBDriver.cs` | Dynamic mode entry |
| `LinqToDBStaticDriver` | `Drivers/StaticLinqToDBDriver.cs` | Static mode entry |
| `LINQPadDataConnection` | `LINQPadDataConnection.cs` | Public `DataConnection` subclass for generated contexts |
| `DriverHelper` | `Drivers/DriverHelper.cs` | Shared driver logic, per-connection dependency override, connection test |
| `IDatabaseProvider` | `DatabaseProviders/IDatabaseProvider.cs` | Provider abstraction contract (`IsPlatformSupported`, `GetNuGetPackages`) |
| `DatabaseProviderBase` | `DatabaseProviders/DatabaseProviderBase.cs` | Default-virtual base |
| `DatabaseProviders` | `DatabaseProviders/DatabaseProviders.cs` | `FrozenDictionary`-backed static registry |
| `DuckDBProvider` | `DatabaseProviders/DuckDBProvider.cs` | net8.0-windows DuckDB provider |
| `YdbProvider` | `DatabaseProviders/YdbProvider.cs` | net8.0-windows YDB provider |
| `ProviderInfo` | `DatabaseProviders/ProviderInfo.cs` | Per-dialect descriptor |
| `Platform` | `Platform.cs` | Host OS checks (`IsWindows`, `IsMacOS`) |
| `NuGetPackageVersions` | generated `NuGetPackageVersions.g.cs` | Client package versions from central package management |
| `Notification` | `UI/Notification.cs` | Logging + guarded message boxes |
| `ConnectionSettings` | `Configuration/ConnectionSettings.cs` | Root settings DTO |
| `AppConfig` | `Configuration/AppConfig.cs` | `ILinqToDBSettings` for static contexts |
| `DynamicSchemaGenerator` | `Drivers/DynamicSchemaGenerator.cs` | SCAFFOLD bridge |
| `StaticSchemaGenerator` | `Drivers/StaticSchemaGenerator.cs` | Reflection-based schema tree |
| `ModelProviderInterceptor` | `Drivers/Scaffold/ModelProviderInterceptor.cs` | `ScaffoldInterceptors` impl |
| `DataModelAugmentor` | `Drivers/Scaffold/DataModelAugmentor.cs` | `ConvertCodeModelVisitor` |
| `SettingsModel` | `UI/Model/SettingsModel.cs` | Root ViewModel |
| `AboutModel` | `UI/Model/AboutModel.cs` | About-tab ViewModel, runtime version read |
| `ValueFormatter` | `Drivers/ValueFormatter.cs` | Provider-specific type rendering |
| `PasswordManager` | `Drivers/PasswordManager.cs` | Resolves `{pm:...}` tokens |
| `LinqToDBLinqPadException` | `LinqToDBLinqPadException.cs` | Public domain exception |

## Files (Tier 1 / Tier 2)

**Tier 1 (canonical anchors) -- 15 files:** Drivers (Dynamic/Static/DriverHelper), LINQPadDataConnection, IDatabaseProvider, DatabaseProviderBase, DatabaseProviders, ProviderInfo, ConnectionSettings, AppConfig, DynamicSchemaGenerator, StaticSchemaGenerator, Scaffold/ModelProviderInterceptor, Scaffold/DataModelAugmentor, csproj.

**Tier 2 -- visited 48 of 51 files:**
- Concrete providers (15 files, `YdbProvider.cs` added in an earlier delta): all sampled, Access, SqlServer, DuckDB, YDB, PostgreSQL read in full. This delta also read diffs of ClickHouse, DB2, Firebird, Informix, MySql, Oracle, SQLite, SapHana, SqlCe, Sybase.
- UI Models (12 files): sample read in full, pattern confirmed. `DynamicConnectionModel`, `StaticConnectionModel` read this delta.
- UI Settings code-behind (11 files): `SettingsDialog.xaml.cs`, `StaticConnectionTab.xaml(.cs)` read.
- Compat (3 files): `IReadOnlySet.cs` read, others structurally implied.
- Other: `CSharpUtils.cs`, `ValueFormatter.cs`, `PasswordManager.cs`, `Notification.cs`, `LinqToDBLinqPadException.cs`, `GlobalSuppressions.cs`, `Configuration/CustomSerializers/IReadOnlySetConverter.cs`, `Platform.cs` (new), `BannedSymbols.txt` (new), `README.md`, `Nuget/Pack.cmd`.

## Inbound / outbound dependencies

**Outbound:**
- [SCAFFOLD](../SCAFFOLD/INDEX.md) -- `LinqToDB.Scaffold` project reference.
- [CORE](../CORE/INDEX.md) -- `DataConnection`, `DataOptions`, `IDataContext`.
- All [PROV-*](../PROV-SQLSERVER/INDEX.md) -- each `IDatabaseProvider` impl delegates to `DataConnection.GetDataProvider` or `<X>Tools.GetDataProvider`.
- `LINQPad.Reference` NuGet -- `DynamicDataContextDriver`, etc.
- `Microsoft.CodeAnalysis.CSharp` NuGet -- Roslyn compilation.
- Database client NuGets (`DuckDB.NET.Data.Full`, `Ydb.Sdk`, `Npgsql`, `MySqlConnector`, ...) -- on net8.0-windows these are compile-time references of `LinqToDB.LINQPad.csproj` only. They are NOT dependencies of the NuGet package (`LinqToDB.LINQPad.Pack.csproj`) and are declared per connection through `IDatabaseProvider.GetNuGetPackages` / `DataContextDriver.OverrideDriverDependencies`. The net472 `.lpx` still bundles every client.

**Inbound:** standalone driver project, nothing inside `Source/LinqToDB/` depends on this area.

## Known issues / debt

- `DynamicSchemaGenerator.cs:44` -- `// TODO: disabled due to generation bug in current scaffolder` (`options.Schema.EnableSqlServerReturnValue = false` commented).
- `CSharpUtils.cs` -- `// TODO: move to linq2db.Tools`, keyword list duplicates `CSharpCodeGenerator.KeyWords`.
- `SYSLIB1045` suppressed in `PasswordManager.cs` on net472.
- `SYSLIB0044` (`AssemblyName.CodeBase` obsolete) suppressed in `DynamicLinqToDBDriver.cs:175`.
- DB2 and Informix silently excluded on 32-bit net8.0-windows processes.
- `WITH_ISERIES` conditional: iSeries support compiled in by default but the nuspec packaging step is manual.
- IBM DB2 on net472 requires a PostBuild trick.
- `DuckDBProvider.GetLastSchemaUpdate` always returns `null` -- schema change detection not implemented for DuckDB.
- `YdbProvider.GetLastSchemaUpdate` always returns `null` -- same unimplemented schema-change-detection limitation as DuckDB.
- Resolved in this delta: the `LinqToDB.LINQPad.Pack.csproj` Description now lists DuckDB and YDB.
- Fragility: any code referencing a client type from a body reachable without that client being provisioned (shared method bodies, static fields, static ctors) fails at JIT time. The codebase relies on non-inlined method isolation by convention only. `System.Windows.MessageBox` is guarded by `BannedSymbols.txt` for the same reason (macOS XPF).
- A static context without `StaticContextOptions.Database` downloads every client (all platform-supported providers).
- `NuGetPackageVersions` for DB2 resolves to the net8.0 branch of central package versions, so bumping only the net10.0 entry never reaches the driver.
- The LINQPad 5 `.lpx` redistributes all third-party clients, license notices are generated into `THIRD-PARTY-NOTICES.txt`.

## See also

- [SCAFFOLD area](../SCAFFOLD/INDEX.md)
- [PROV-SQLSERVER area](../PROV-SQLSERVER/INDEX.md)
- [architecture/overview.md](../../architecture/overview.md)

<details><summary>Coverage</summary>

- Tier 1: 15/15 done
- Tier 2: 48/51 done (94.1%)
- Tier 3 (skipped, logged): 6

**Delta read (prior run -- PR #5451 DuckDB additions):**
- `DatabaseProviders/DuckDBProvider.cs` -- new file; DuckDB provider impl with `DuckDBClientFactory.Instance` factory.
- `DatabaseProviders/DatabaseProviders.cs` -- `DuckDBProvider` registration added outside 64-bit guard.
- `LinqToDB.LINQPad.csproj` -- `DuckDB.NET.Data.Full` added to net8.0-windows ItemGroup.

**Read (this run -- delta, sha 2e67bafc9):**
- `Source/LinqToDB.LINQPad/UI/Model/AboutModel.cs` -- no behavioral change; reads version at runtime from `Assembly.GetName().Version`; constructs `pack://` logo URI with initialization-order guard; exposes `RepositoryUri` / `ReportsUri`. Surfaced in delta as packaging churn; `AboutModel` entry added to Key types and WPF UI subsection.
- `Source/LinqToDB.LINQPad/UI/Settings/AboutTab.xaml` -- pure XAML layout bound to `AboutModel`; `<Page Update>` entry added to `LinqToDB.LINQPad.Pack.csproj` in this delta. No content change.
- `Source/LinqToDB.LINQPad/LinqToDB.LINQPad.Pack.csproj` -- `DuckDB.NET.Data.Full` confirmed present (line 62); `AboutTab.xaml` added to `<Page Update>` block (lines 94-97); `<Description>` still omits DuckDB (known-issue bullet cites line 20).


**Read (this run -- delta, sha b3340aa9):**
- `Source/LinqToDB.LINQPad/LinqToDB.LINQPad.Pack.csproj` -- now a packaging-only project (`Microsoft.NET.Sdk`, single TFM `net8.0`, `EnableDefaultItems=false`, `IncludeBuildOutput=false`); driver assembly pulled into `lib/net8.0/` via `_AddLinqPadDriverToPackage` MSBuild target; split motivated by macOS/Linux NuGet compatibility issue #5497 (pre-#5279 layout restored). `<Description>` (line 40) still omits DuckDB. `DuckDB.NET.Data.Full` PackageReference present (line 78).
- `Source/LinqToDB.LINQPad/LinqToDB.LINQPad.csproj` -- SDK changed to `Microsoft.NET.Sdk.WindowsDesktop`; `IsPackable=false` added; `GenerateLpxArtifacts` property gate added for PostBuild `.lpx`/`.lpx6` targets; `<Page Update>` block for all nine XAML files (including `AboutTab.xaml`, `DynamicConnectionTab.xaml`) declared here; `DuckDB.NET.Data.Full` in non-net472 `<ItemGroup>` (line 68).
- `Source/LinqToDB.LINQPad/UI/Settings/DynamicConnectionTab.xaml` -- `UserControl`, design-time `DataContext` `DynamicConnectionModel`; renders Database Type / Provider combo boxes, provider path TextBox + Select button, connection string TextBox (multiline, `{pm:name}` tooltip), secondary connection string panel (MS Access, visibility-gated), Encrypt checkBox, command timeout TextBox (`CommandTimeoutConverter`). No structural change; surfaced for first-time explicit coverage.

**Read (this run -- delta, sha 36ee4f82):**
- `Source/LinqToDB.LINQPad/DatabaseProviders/DatabaseProviders.cs` -- registers new `YdbProvider` unconditionally inside `#if !NETFRAMEWORK` (outside the 64-bit guard, line 37), alongside `DuckDBProvider`.
- `Source/LinqToDB.LINQPad/DatabaseProviders/PostgreSQLProvider.cs` -- added `ProviderName.PostgreSQL19` (`"PostgreSQL 19 Dialect"`) to the dialect-detection `ProviderInfo` list (now eight entries, line 20).
- `Source/LinqToDB.LINQPad/DatabaseProviders/YdbProvider.cs` -- new file; `DatabaseProviderBase` subclass for YDB, `#if !NETFRAMEWORK`-gated, mirrors `DuckDBProvider`'s shape (`GetProviderFactory` -> `YdbProviderFactory.Instance`, `GetLastSchemaUpdate` -> `null`, `ClearAllPools` -> `YdbConnection.ClearAllPools().GetAwaiter().GetResult()`).
- `Source/LinqToDB.LINQPad/LinqToDB.LINQPad.Pack.csproj` -- added `PackageReference Include="Ydb.Sdk"` to the net8.0 dependency group (line 79); `<Description>` (line 40) not updated, still omits DuckDB and now also YDB.
- `Source/LinqToDB.LINQPad/LinqToDB.LINQPad.csproj` -- added `PackageReference Include="Ydb.Sdk"` to the non-net472 `<ItemGroup>` (line 69), alongside existing `DuckDB.NET.Data.Full`.

**Read (this run -- delta):**
- `BannedSymbols.txt` (A) -- new, bans `System.Windows.MessageBox` (use `Notification`, macOS XPF constraint).
- `Platform.cs` (A) -- new, `IsWindows` / `IsMacOS`, constants on net472.
- `Configuration/ConnectionSettings.cs` -- `Save` restores plain secondary connection string in `finally` (double-encrypt fix), `StaticContextOptions.Database` added.
- `DatabaseProviders/DatabaseProviderBase.cs`, `IDatabaseProvider.cs`, `DatabaseProviders.cs` -- `IsPlatformSupported`, `GetNuGetPackages`, `GetAllNuGetPackages`.
- `DatabaseProviders/AccessProvider.cs`, `ClickHouseProvider.cs`, `SQLiteProvider.cs`, `SapHanaProvider.cs` -- per-client non-inlined isolation, package lists, Access `IsPlatformSupported` Windows-only, SQLite native base dir changed.
- `DatabaseProviders/DB2Provider.cs`, `InformixProvider.cs` -- OS-specific `ClientPackage`.
- `DatabaseProviders/DuckDBProvider.cs`, `FirebirdProvider.cs`, `MySqlProvider.cs`, `OracleProvider.cs`, `PostgreSQLProvider.cs`, `SybaseAseProvider.cs`, `YdbProvider.cs` -- `GetNuGetPackages` one-liners.
- `DatabaseProviders/SqlCeProvider.cs` -- `IsPlatformSupported => Platform.IsWindows`.
- `DatabaseProviders/SqlServerProvider.cs` -- lazy spatial types assembly load, Windows vs dotMorten package choice.
- `Drivers/DriverHelper.cs` -- `OverrideDriverDependencies`, `TestConnection`, `OpenConnections`, `LogException`, new resolvers (Channels, Reflection.Metadata), dialog scope.
- `Drivers/DynamicLinqToDBDriver.cs`, `Drivers/StaticLinqToDBDriver.cs` -- dependency override hooks, `TestConnectionCore`, separator-agnostic runtime token regex, new Notification overloads.
- `Drivers/ValueFormatter.cs` -- per-provider non-inlined converter registration, name-based spatial types.
- `LinqToDB.LINQPad.csproj`, `LinqToDB.LINQPad.Pack.csproj` -- client refs moved out of the package, `GenerateNuGetPackageVersions`, Roslyn version override, lpx-only packing, description updated, PublicAPI removed.
- `Nuget/Pack.cmd` -- lpx-only (extension argument removed).
- `PublicAPI/**` (D, 6 files) -- baselines deleted, not read.
- `README.md` -- LINQPad 8+/macOS, database client download, licensing, troubleshooting sections.
- `LinqToDBLinqPadException.cs` -- class body simplified to primary-constructor-only form.
- `UI/Model/DynamicConnectionModel.cs`, `UI/Model/StaticConnectionModel.cs`, `UI/Notification.cs`, `UI/Settings/SettingsDialog.xaml.cs`, `UI/Settings/StaticConnectionTab.xaml`, `UI/Settings/StaticConnectionTab.xaml.cs` -- platform-filtered database list, static Database combo, logging-aware Notification, tolerant context type loading.

</details>
