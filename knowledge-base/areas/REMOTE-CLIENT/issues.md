---
area: REMOTE-CLIENT
kind: issues
sources: [gh-issues, gh-prs, gh-discussions]
confidence: medium
last_verified: 2026-11-11
last_verified_sha: f90c5bcfb86d88db436a6494f0640c4c43dd691f
---

# REMOTE-CLIENT -- GitHub themes

## Open themes
- **Remote value and type fidelity (direct vs remote)** -- The remote client sends expression values and types over LinqService, and direct and remote runs diverge. Open: #6055 (SqlBinaryExpression / SqlUnaryExpression lose their DbDataType in LinqServiceSerializer), with the fix in draft PR #6057; #6153 (custom scalar type with a string converter round-trips through ToString()); #5973 (ulong.MaxValue literal inlined differently direct vs remote on PostgreSQL, the PostgreSQL remote case gated by #6048 merged 2026-10-15; the literal itself also fails on SQLite, SQL Server, Sybase and Firebird); #6202 (YDB: a cached direct query keeps the NULL check that the remote context drops). Earlier fixes: #3865 (ValueConverter support for RemoteContext, merged 2022-12-07), #1629 (DateTime with Kind=Utc sent incorrectly over remote context, closed), #1445 (LinqService sent the same query AST for providers with different SQL flags, closed), #5970 (Transform-mode IS NULL fold on a LEFT JOIN source, closed 2026-10-07 with the fix in #5971).
- **Remote mapping schema and configuration scope** -- Remote calls must resolve columns and converters against the caller's mapping schema and configuration. Open: #6270 (a UseMappingSchema scope does not restore the schema or ConfigurationID). Earlier: #5967 (resolve remote columns against the request context's mapping schema, merged 2026-10-09), #5966 (server ignores configuration-scoped column attributes, closed 2026-10-09), #1726 (additional MappingSchema on the host with ServiceModelDataContext, closed, WCF era).
- **Remote HttpClient and WASM client** -- The in-tree client on the HTTP transport fails in browser and trimmed or AOT builds. Open: #6167 (WASM: unguarded provider mapping schemas load ADO.NET assemblies client-side); #6168 (client fails when reflection-based System.Text.Json is disabled, WASM / trimmed / NativeAOT); #6176 (a configuration name containing '/' gets HTTP 404). Earlier: #6178 (remote client tested in the browser-wasm runtime, merged 2026-10-27), #5158 (in-browser remote fix, merged 2025-11-28), #4775 (LinqToDB.Remote.Http.Client / Server, merged 2025-05-12).

## Resolved themes
- **WCF / LinqService transport (legacy)** -- Recurring WCF-era reports on the WCF-based remote context: #16, #659, #730, #1041, #1187, #1678, #1915, #2993, #3409. Resolved by the move to HTTP transport in #4775 (LinqToDB.Remote.Http.Client / Server, merged 2025-05-12).
- **Remote test-host and client lifetime** -- Remote test clients leaked connections to the test hosts, and test-host wiring picked the wrong LinqService under parallel lanes. Resolved by #6010 (stop remote test clients leaking connections to the test hosts, merged 2026-10-10) and #5992 (test hosts serving the wrong LinqService under parallel lanes, merged 2026-10-02). Earlier: #5762 (stop leaking a client per two-query plan, guard double dispose, merged 2026-08-29). Harness: #5157 (baselines comparison for direct and remote context testruns), #6061 (compare direct and remote baselines on every run, merged 2026-10-28), #2759 (LinqService Oracle test failures, closed 2021-05-29).
- **WebApi / OData entity serialization** -- #1046 (OData cast to derived type with expand), #2442 (LoadWith exception in WebApi Core 3.1), #4197 (navigation properties break ModelState validation). All closed, no linked fix in the index. OData query translation: #2070 (GroupBy with aggregate fails on .NET Core OData, fixed by #2074, merged 2020-02-07), #2092 (query generation issues with OData, closed 2020-02-29), #2970 (OData contains does not generate the correct SQL, closed 2021-10-02).
- **Sync API surface on remote context** -- #4618 (remove or obsolete sync APIs) and #5106 (remove sync APIs from transport interface, merged 2025-09-09). Two items only, below cluster threshold; listed for context.

## Active discussions
- [Documentation for creating new data provider or extending existing](https://github.com/linq2db/linq2db/discussions/4555) -- [Q&A] Hello, asks how to build a custom remote transport; no maintainer answer in index.
- [Problem Running LinqToDb.Remote.Grpc query in blazor wasm hosted](https://github.com/linq2db/linq2db/discussions/4617) -- [Q&A] Blazor WASM hosted client using LinqToDb.Remote.Grpc. In-browser remote fix landed in #5158 (merged 2025-11-28).

## Stats
- Open issues: 8
- Closed issues: 23
- Open PRs: 1
- Total PRs: 14
- Discussions: 2
- Last fetched: 2026-11-11

<details><summary>Coverage</summary>

- Index entries cited: 47 (31 issues + 14 PRs + 2 discussions)
- Themes extracted: 7
</details>
