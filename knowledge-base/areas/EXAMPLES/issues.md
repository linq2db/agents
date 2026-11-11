---
area: EXAMPLES
kind: issues
sources: [gh-issues, gh-prs, gh-discussions]
confidence: medium
last_verified: 2026-11-11
last_verified_sha: f90c5bcfb86d88db436a6494f0640c4c43dd691f
---

# EXAMPLES -- GitHub themes

## Open themes
- **Blazor WASM clients of the remote samples** -- The HttpClient and SignalR samples ship Blazor WebAssembly clients, and the gRPC sample has a Blazor-hosted variant (discussion #4617). Open reports of client-side failures under WASM: #6168 (the client serializes with reflection-based System.Text.Json while suppressing trim/AOT warnings, so it fails wherever reflection JSON is disabled), #6167 (client-side provider mapping schemas load ADO.NET assemblies that WASM cannot load, for PostgreSQL, MySqlConnector, ClickHouse and DuckDB), and #4617 (gRPC client in a Blazor WASM hosted app throws PlatformNotSupportedException, "Cannot wait on monitors"). The browser-wasm test leg added in #6178 belongs to TESTS-WASM; the index does not link it to #6167 or #6168.
- **Remote transport changes landing under the samples** -- Open remote-library work changes the code the samples are built on. #6020 reuses one gRPC channel per context and accepts a caller-owned channel, which affects how the GrpcClient sample constructs `ExampleDataContext` (it passes `GrpcChannelOptions` with a hand-built HttpClient today). #6014 reworks SignalR transport behaviour (cancellable streaming calls, concurrency limits, restartable DI connection) that the SignalR sample uses. #6176 is open: a configuration name containing `/` (DB2.z/OS) returns HTTP 404 on the HttpClient transport because the route takes it as one path segment.

## Resolved themes
- **Examples Release build and CI verification** -- Examples were built only in Debug on CI, where analyzers do not run, so the Release build broke unnoticed. #5945 reported 60 errors from `dotnet build Examples/Examples.slnx -c Release` (closed 2026-10-24). [#6127](https://github.com/linq2db/linq2db/pull/6127) fixed the sample code (CA1050, [MA0047](https://github.com/meziantou/Meziantou.Analyzer/blob/main/docs/Rules/MA0047.md), [MA0048](https://github.com/meziantou/Meziantou.Analyzer/blob/main/docs/Rules/MA0048.md), culture-invariant formatting) and moved CI to a Release build. [#6248](https://github.com/linq2db/linq2db/pull/6248) (closed 2026-11-04) bumped `Microsoft.AspNetCore.Components.WebAssembly.Server` to 10.0.14 after NU1903 failed the "Build Examples (verify)" step on every PR.
- **NuGet audit gate on the SignalR and WASM sample packages** -- The SignalR samples consume `Microsoft.AspNetCore.SignalR.Client`, pinned in `Directory.Packages.props` at 8.0.32 / 9.0.21 / 10.0.13. Advisory GHSA-334f-vvp4-7g6p failed restore with warnings-as-errors. #6043 (closed 2026-10-14) suppressed it globally. #6095 (closed 2026-10-20) raised the SignalR.Client floors to patched versions and dropped the suppression after the advisory was revised on 2026-10-19. #6295 (closed 2026-11-11) follows the same audit family for the net462 test restore only; it does not touch the samples.
- **Metrics and activity API behind the OpenTelemetry sample** -- The OpenTelemetry sample bridges linq2db `ActivityID` to `System.Diagnostics.Activity`. The request was #3405 (OpenTracing or DiagnosticSource support, closed 2024-01-23 via [#4005](https://github.com/linq2db/linq2db/pull/4005), which added the `ActivityService` API). Follow-ups: [#4400](https://github.com/linq2db/linq2db/pull/4400) (metrics run only on the release or manual pipeline), [#4571](https://github.com/linq2db/linq2db/pull/4571) (NRE in metrics tag logging), [#4573](https://github.com/linq2db/linq2db/pull/4573) (unnecessary connection creation in metrics). #4561 (generated SQL and parameters in activity span tags, closed 2024-07-13) is the matching request; the index links no closing PR.
- **Remote transport history: WCF and gRPC** -- The WCF sample descends from the `LinqOverWCF` example in the standalone linq2db/examples repository. #3409 asked how to replace WCF with gRPC starting from that example (closed 2022-04-16). #1678 asked for LINQ over WCF on .NET Standard 2.0 (closed 2022-04-16); WIP [#1680](https://github.com/linq2db/linq2db/pull/1680) (closed 2021-01-09) removed the ServiceModel LinqService and DataService files as an experiment.
- **HTTP and SignalR transports behind the Blazor samples** -- [#4775](https://github.com/linq2db/linq2db/pull/4775) (merged 2025-05-12) added the HttpClient and SignalR transports with Blazor support; the HttpClient and SignalR samples are built on them. [#5280](https://github.com/linq2db/linq2db/pull/5280) (merged 2025-12-28) fixed a package-name typo in `linq2db.Remote.HttpClient.Server` and bumped dependencies. #4618 (closed 2025-09-09) removes or obsoletes the sync APIs of the remote context because blocking calls break WASM; the index does not record which of the two was done and links no closing PR.
- **Compat and app.config configuration** -- The Compat sample sets `DataConnection.DefaultSettings` to `LinqToDBSection.Instance` from `LinqToDB.Compat`. [#4821](https://github.com/linq2db/linq2db/pull/4821) (merged 2025-02-21) added that package for `System.Configuration.ConfigurationManager` users. Earlier configuration reports: #134 (pass a connection string without App.config, closed 2014), #616 (appsettings.json not picked up on .NET Core, closed 2017), #261 (SQLite configured in App.config under Mono, closed 2017), #906 (NRE in the DataConnection constructor on Mono with App.config, closed 2017), #2806 (the PostgreSQL CopyMe template put `Protocol=3;` in app.config, closed 2021), and discussion #3828 (MAUI has no App.config, closed).
- **UTC DateTime conversion** -- The UtcDateTime sample covers the question raised in discussion #4312 (store UTC, show local time). The index does not record that discussion's resolution. The sample's approach is a named MappingSchema with `SetConvertExpression`, attached per connection.

## Active discussions
- [Problem Running LinqToDb.Remote.Grpc query in blazor wasm hosted](https://github.com/linq2db/linq2db/discussions/4617) -- [Q&A] gRPC remote context in a Blazor WASM hosted client (open)
- [Relation between different types of mapping](https://github.com/linq2db/linq2db/discussions/5554) -- [Q&A] SetConverter versus MappingSchema conversions, adjacent to the UtcDateTime mapping sample (open)

## Stats
- Open issues: 3
- Closed issues: 11
- Open PRs: 2
- Total PRs: 14
- Discussions: 4
- Last fetched: 2026-11-11

<details><summary>Coverage</summary>

- Index entries scanned: 6240 (3245 issues + 2699 PRs + 296 discussions)
- Keyword candidates: 239 (example, sample, demo, Examples/, grpc, signalr, wcf, httpclient, Remote, metrics, OpenTelemetry, Compat, app.config, Blazor, UTC, plus EXAMPLES-tagged items)
- Items cited: 32 (14 issues, 14 PRs, 4 discussions)
- Themes extracted: 9 (2 open, 7 resolved)
- Excluded as other-area: #5966, #6055, #5169 (remote-library defects, REMOTE-CLIENT / PROV-CLICKHOUSE / GLOBAL); #6010, #5603 (remote test infra); #6178 (TESTS-WASM); #6295 kept only as a note above
- Excluded as generic keyword hits: #201 (2015 wiki demo code), #5797 (DateTimeOffset, not the DateTime sample), #6059 (SqlQueryDependent cache), and doc or Q&A items whose only match is "example" or "sample" (e.g. #43, #1836, #2263)
</details>
