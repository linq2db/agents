---
area: EXAMPLES
kind: patterns
sources: [code]
confidence: medium
last_verified: 2026-11-11
last_verified_sha: f90c5bcfb86d88db436a6494f0640c4c43dd691f
---

# EXAMPLES -- Patterns

## Applicable conventions

- No conventions cite files in this area. See [conventions/](../../conventions/) for the full catalog.

## Recurring patterns in the samples

- **Project reference, not NuGet.** `Examples/Directory.Build.props` adds a `ProjectReference` to `Source/LinqToDB/LinqToDB.csproj` for every sample. Per-sample extension projects (`LinqToDB.Remote.*`, `LinqToDB.Tools`, `LinqToDB.Compat`, `LinqToDB.Extensions`) are referenced the same way. The only linq2db package is `linq2db.t4models` (T4 includes) in `GrpcClient` and `WcfClient`.
- **Isolated build output.** `ArtifactsProjectName=Examples_$(MSBuildProjectName)`, `IsPackable=false`, `SignAssembly=False`, `EnablePackageValidation=false`.
- **Central package versions.** `PackageReference` items carry no versions. They come from the root `Directory.Packages.props`.
- **Remote client/server pairs.** Each remote sample has a server host that registers the linq2db service and a client with an `ExampleDataContext` or `DemoClientData` that derives from the transport's remote data context. gRPC and WCF clients share `Examples/Remote/Program.cs` through a linked `<Compile Include>`.
- **Self-contained demo databases.** HttpClient and SignalR use SQLite in-memory (`Mode=Memory;Cache=Shared`), seeded with `BulkCopy`. This lets them run without provisioning.
- **Per-connection mapping schema.** `Examples/Mapping/UtcDateTime/Program.cs` attaches a named `MappingSchema` with `db.AddMappingSchema` rather than mutating the global default.

## Recorded decisions affecting this area

- No area-scoped recorded decisions. `decisions.md` does not exist for this area yet.

## See also

- [INDEX.md](INDEX.md) -- area architecture
- [tech-debt.md](tech-debt.md) -- observed debt

<details><summary>Coverage</summary>

Derived from `areas/EXAMPLES/INDEX.md` and `Examples/` source as summarised there. No conventions or decisions were aggregated.

</details>
