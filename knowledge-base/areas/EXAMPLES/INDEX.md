---
area: EXAMPLES
kind: area-index
sources: [code]
confidence: high
last_verified: 2026-11-11
last_verified_sha: f90c5bcfb86d88db436a6494f0640c4c43dd691f
coverage_tier_1: 6/6
coverage_tier_2: 20/20
---

# EXAMPLES

Standalone sample applications under `Examples/`, each demonstrating one linq2db integration: remote data contexts (gRPC, HTTP, SignalR, WCF), activity metrics (OpenTelemetry, `LinqToDB.Tools`), UTC DateTime mapping, and `System.Configuration` compatibility. They are consumer-facing documentation-by-code, not tests. CI only verifies that they compile.

## Subsystems

### Build wiring

- `Examples/Examples.slnx` lists the 13 sample projects plus the `Source/` projects they reference (`LinqToDB`, `LinqToDB.Compat`, `LinqToDB.Extensions`, `LinqToDB.Tools`, `LinqToDB.Remote.*`, `CodeGenerators`). Build types: `Azure`, `Debug`, `Release`.
- `Examples/Directory.Build.props` imports the root `Directory.Build.props`, sets `SignAssembly=False`, `IsPackable=false`, `EnablePackageValidation=false`, and `ArtifactsProjectName=Examples_$(MSBuildProjectName)` (avoids output clashes with the main solution). It adds a `ProjectReference` to `Source/LinqToDB/LinqToDB.csproj` to every sample and removes `Source/Shared/*.cs` from compilation.
- `Examples/Compile.cmd` builds `Examples.slnx` in Release then Debug with `--no-incremental`.
- Package versions come from the central `Directory.Packages.props` (listed in the slnx), so sample `PackageReference` items carry no versions.

### How samples reference linq2db

All samples use **project references**, never the `linq2db` NuGet package. The base reference is `Source/LinqToDB` (from `Directory.Build.props`), plus the specific extension project per sample (table below). The only linq2db-related `PackageReference` is `linq2db.t4models` in `GrpcClient` and `WcfClient`, which supplies the T4 include files for `Northwind.tt` (not the runtime library).

### CI coverage

- GitHub Actions: job `examples` in `.github/workflows/build.yml` (windows-2025, 30 min) runs `dotnet build Examples/Examples.slnx --configuration $RELEASE_CONFIGURATION`. Windows is needed because `WcfHost`/`WcfClient` target `net462`. Setup installs SDKs 9.x and 10.x.
- Azure: `Build/Azure/pipelines/templates/build-job.yml` has a "Build Examples (verify)" step gated by `with_examples`. The flag is `true` in `default.yml` and `build.yml`, `false` in `testing.yml` and as the template default.
- Nothing runs the samples. No tests, no DB provisioning. Build-only.

### Remote samples (`Examples/Remote/`)

| Sample | Projects (TFM) | linq2db reference | Shows |
|---|---|---|---|
| gRPC | `GrpcServer` (net8.0), `GrpcClient` (net8.0, Exe) | `LinqToDB.Remote.Grpc` | `Startup.ConfigureServices` registers `GrpcLinqService(new LinqService { AllowUpdates = true }, true)` via `AddCodeFirstGrpc`, maps it with `MapGrpcService<GrpcLinqService>`, listens on `https://localhost:15001` (`Program.cs`). Server uses SQL Server `Northwind` via `DataConnection.DefaultSettings`. Client `ExampleDataContext` ctor passes a `GrpcChannelOptions` with a hand-built `HttpClient` accepting any dev certificate. |
| WCF | `WcfHost`, `WcfClient` (both net462, Exe) | `LinqToDB.Remote.Wcf` | Host: `ServiceHost` over `WcfLinqService` at `net.tcp://localhost:30304`, endpoint `LinqOverWcf` plus MEX. Client: `ExampleDataContext` ctor builds the matching `NetTcpBinding` and `EndpointAddress`. |
| HttpClient | `HttpClientServer`, `HttpClientClient` (net10.0, Blazor) | `LinqToDB.Remote.HttpClient.Server` / `.Client`, `LinqToDB.Extensions` (server) | Server: `AddLinqToDBContext<IDemoDataModel>` + `AddControllers().AddLinqToDBController<IDemoDataModel>()` + `MapControllers`, SQLite in-memory shared cache. Client (WASM): `AddLinqToDBHttpClientDataContext<IDemoDataModel>` then `InitHttpClientAsync()`. |
| SignalR | `SignalRServer`, `SignalRClient` (net10.0, Blazor) | `LinqToDB.Remote.SignalR.Server` / `.Client`, `LinqToDB.Extensions` (server) | Server: `AddLinqToDBService<IDemoDataModel>().AddSignalR(...)`, `MapHub<LinqToDBHub<IDemoDataModel>>("/hub/linq2db")`. Client: `AddLinqToDBSignalRDataContext` then `InitSignalRAsync`. Server `Program.cs` carries commented-out `Use*` lines for ~10 providers (ClickHouse x3, DB2, Firebird, Informix, Oracle, PostgreSQL, SQL Server, SQLite) and actually enables `UseAse`. |

Shared demo pattern (HttpClient and SignalR, near-identical copies): `IDemoDataModel : IDataContext` exposes `DemoDataModel Model` (primary-ctor class returning `ITable<WeatherForecast>`). `DemoClientData` derives `HttpClientDataContext` / `SignalRDataContext`. Server-side `DemoDB : DataConnection, IDemoDataModel` uses SQLite `Mode=Memory;Cache=Shared`. The client project holds the model so the server references it (`ProjectReference` server -> client). Both servers seed five `WeatherForecast` rows with `BulkCopy` in `InitDemoDatabase`. The `.razor` pages (`Interactive*`, `Weather`, layout) are UI-only and were only noted.

gRPC and WCF clients both compile the shared `Examples/Remote/Program.cs` via `<Compile Include="..\..\Program.cs" Link="Program.cs" />`. It is the common client scenario against `ExampleDataContext` (generated from `Northwind.tt`): `InsertWithIdentityAsync`, `Where(...).Set(...).UpdateAsync()`, `FirstAsync` on a projection, and a `DefaultIfEmpty()` left join materialised with `ToListAsync`.

### Metrics (`Examples/Metrics/`)

- `OpenTelemetry/Program.cs`: builds a `TracerProvider` with console exporter, registers an `ActivityListener`, then `ActivityService.AddFactory(LinqToDBActivity.Create)`. `LinqToDBActivity : ActivityBase` bridges linq2db `ActivityID`/`ActivityTagID` to `System.Diagnostics.Activity`. Workload: SQLite (`SQLiteProvider.Microsoft`) `Northwind.MS.sqlite`, `CreateTableAsync<Customer>` + count. No linq2db project reference beyond the base one (core `LinqToDB.Metrics` namespace).
- `Tools/Program.cs`: `LinqToDB.Tools` activity helpers. `ActivityHierarchy` (call tree into a `StringBuilder`) and `ActivityStatistics.Factory` / `GetReport()`, with `Configuration.TraceMaterializationActivity = true`. References `LinqToDB.Tools`.

### Mapping (`Examples/Mapping/UtcDateTime/`)

`Program.cs` builds a named `MappingSchema("UtcConvert")` with two `SetConvertExpression<DateTime,DateTime>` calls: `ToLocalTime` for `ConversionType.FromDatabase`, `ToUniversalTime` for `ConversionType.ToDatabase`. It is attached per connection via `db.AddMappingSchema`. Exercises four write paths (`Insert`, `Value(...).Insert()`, `BulkCopy`, each again with `InlineParameters = true`) and reads back with and without the schema. Uses `UseTracing(TraceLevel.Info, ...)` to print SQL. Has its own `UtcDateTime.slnx` besides the shared one.

### Compat (`Examples/Compat/ConfigurationManager/`)

`Program.cs` sets `DataConnection.DefaultSettings = LinqToDBSection.Instance` (the `app.config` provider from `LinqToDB.Compat`), creates a `Person` table, inserts and lists. Targets `net462` and `net9.0`, references `LinqToDB.Compat` and `System.Data.SQLite`. Prints `Environment.Version` and `RuntimeInformation.FrameworkDescription`.

## Key types

- `GrpcLinqService`, `LinqService` (`AllowUpdates = true`), `WcfLinqService`: server-side remote endpoints, defined in `Source/LinqToDB.Remote.*` and only consumed here.
- `IDemoDataModel` / `DemoDataModel` / `DemoClientData` / `DemoDB`: duplicated demo model in HttpClient and SignalR samples.
- `LinqToDBActivity` (`Examples/Metrics/OpenTelemetry/Program.cs`): the sample OpenTelemetry adapter.
- `ExampleDataContext` (partial): hand-written ctor half in `GrpcClient`/`WcfClient`. The other half is `Northwind.generated.cs`.

## Files (Tier 1 / Tier 2)

Tier 1 (6/6 read in full): `Examples/Examples.slnx`, `Examples/Directory.Build.props`, `Examples/Remote/Program.cs`, `Examples/Metrics/OpenTelemetry/Program.cs`, `Examples/Mapping/UtcDateTime/Program.cs`, `Examples/Compat/ConfigurationManager/Program.cs`.

Tier 2 (`**/*.cs`, 20/20 read): `Metrics/Tools/Program.cs`, `Remote/Grpc/GrpcServer/{Program,Startup}.cs`, `Remote/Grpc/GrpcClient/ExampleDataContext.cs`, `Remote/Wcf/WcfHost/Program.cs`, `Remote/Wcf/WcfClient/ExampleDataContext.cs`, `Remote/HttpClient/HttpClientClient/{Program.cs, DataModel/*.cs (4)}`, `Remote/HttpClient/HttpClientServer/{Program.cs, DataModel/DemoDB.cs}`, `Remote/SignalR/SignalRClient/{Program.cs, DataModel/*.cs (4)}`, `Remote/SignalR/SignalRServer/{Program.cs, DataModel/DemoDB.cs}`.

Tier 3 / not indexed: `GrpcClient/Northwind.generated.cs`, `WcfClient/Northwind.generated.cs` (T4 output from `Northwind.tt`), `.razor` UI files, `wwwroot/lib/bootstrap/**`.

## Inbound / outbound dependencies

- Outbound: project references into `Source/LinqToDB`, `LinqToDB.Compat`, `LinqToDB.Extensions`, `LinqToDB.Tools`, `LinqToDB.Remote.{Grpc,Wcf,HttpClient.*,SignalR.*}`. Third-party: `protobuf-net.Grpc.AspNetCore`, `Grpc.Net.Client`, `OpenTelemetry*`, `Microsoft.Data.Sqlite`, `System.Data.SQLite`, plus many ADO.NET drivers in `SignalRServer`/`SignalRClient` (Npgsql, MySqlConnector, Oracle, Db2, Firebird, ASE, ClickHouse x2).
- Inbound: none from source. `Build/Azure/pipelines/*` and `.github/workflows/build.yml` build the slnx. Public API changes in the referenced `Source/` projects can break these samples at compile time.

## Known issues / debt

- HttpClient and SignalR demo models are copy-pasted (`DemoDataModel`, `WeatherForecast`, `IDemoDataModel`, `DemoDB`).
- `SignalRClient`/`SignalRServer` reference ~10 driver packages although only one provider is enabled in code. The rest are commented-out connection strings.
- `GrpcServer` hard-codes a SQL Server connection string. `GrpcClient` disables certificate validation (annotated with `#pragma warning disable MA0039`).
- Build-only CI: samples can compile yet fail at runtime, since nothing executes them.

## See also

- [TESTS-BENCHMARKS](../TESTS-BENCHMARKS/INDEX.md)
- `Examples/*/README.md` per-sample instructions

## Pointers

- CI: `.github/workflows/build.yml` job `examples`, `Build/Azure/pipelines/templates/build-job.yml` step "Build Examples (verify)".

<details><summary>Coverage</summary>

Tier 1: 6/6 read in full (Examples.slnx, Directory.Build.props, Remote/Program.cs, Metrics/OpenTelemetry/Program.cs, Mapping/UtcDateTime/Program.cs, Compat/ConfigurationManager/Program.cs).

Tier 2: 20/20 `*.cs` read (listed above). No skips.

Tier 3 (counted, not read): 2 `Northwind.generated.cs`, `.razor` UI, `wwwroot/lib/bootstrap/**`.

Also read for the reference graph: all 13 csproj files via grep, `GrpcClient.csproj`, `WcfClient.csproj`, `.github/workflows/build.yml` (examples job), `Build/Azure/pipelines/templates/build-job.yml`, and a `with_examples` grep across `Build/`.

Not read: READMEs, `app.config`/`App.config`, `Northwind.tt`.

</details>
