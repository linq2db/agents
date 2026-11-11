---
area: EXAMPLES
kind: tech-debt
sources: [code]
confidence: medium
last_verified: 2026-11-11
last_verified_sha: f90c5bcfb86d88db436a6494f0640c4c43dd691f
---

# EXAMPLES -- Tech debt

## No detected issues

This area has no entries in [detected-issues/index.json](../../detected-issues/index.json) as of 2026-11-11. The debt below is taken from [INDEX.md](INDEX.md) and the sources under `Examples/`. It is not detector output. `issues.md` and `decisions.md` do not exist for this area yet.

## Debt observed in source

- **Duplicated demo model.** `IDemoDataModel`, `DemoDataModel`, `WeatherForecast`, `DemoClientData` and `DemoDB` are near-identical copies in `Examples/Remote/HttpClient/*` and `Examples/Remote/SignalR/*`. A fix in one sample has to be repeated in the other.
- **Driver package sprawl.** `SignalRServer` and `SignalRClient` reference about 10 ADO.NET driver packages (Npgsql, MySqlConnector, Oracle, Db2, Firebird, ASE, ClickHouse x2). Only `UseAse` is enabled in `SignalRServer/Program.cs`. The other providers exist as commented-out `Use*` lines.
- **Hard-coded connection string.** `GrpcServer` embeds a SQL Server `Northwind` connection string via `DataConnection.DefaultSettings`.
- **Certificate validation disabled.** `GrpcClient` `ExampleDataContext` builds an `HttpClient` that accepts any dev certificate (`#pragma warning disable MA0039`). This is a copy-paste hazard for consumers.
- **Build-only CI.** The `examples` job in `.github/workflows/build.yml` and the "Build Examples (verify)" step in `Build/Azure/pipelines/templates/build-job.yml` only compile the samples. Runtime breakage is not detected. `with_examples` is `false` in `testing.yml`.
- **Public API coupling.** Samples use project references into `Source/`, so any public API change fails the samples build. There is no inbound ownership signal in `Source/`.
- **Windows-only legs.** `WcfHost` and `WcfClient` target `net462`, which forces the `examples` job onto windows-2025.

## See also

- [INDEX.md](INDEX.md) -- area overview
- [patterns.md](patterns.md) -- area patterns

<details><summary>Coverage</summary>

Derived from `areas/EXAMPLES/INDEX.md` (Known issues / debt) and the `Examples/` source it indexes. `detected-issues/index.json`: 0 entries for EXAMPLES. `issues.md` / `decisions.md`: absent.

</details>
