---
area: REMOTE
kind: issues
sources: [gh-issues, gh-prs, gh-discussions]
confidence: medium
last_verified: 2026-11-11
last_verified_sha: f90c5bcfb86d88db436a6494f0640c4c43dd691f
---

# REMOTE -- GitHub themes

## Open themes
- **Remote path builds different SQL than the direct path** -- The LinqService wire format sends some typed nodes without their type, so the server optimizes a different tree than the direct path does. `SqlBinaryExpression` and `SqlUnaryExpression` cross the wire with their CLR type only (#6055), losing `DbDataType`. The server then folds a non-mandatory narrowing cast that the client kept, giving different and sometimes invalid SQL (YDB reports "Implicit decimal cast would narrow the range"). The same type loss happens on the direct path when a Transform-mode visitor rebuilds a typed node (#6056). Fix is in draft PR [#6057](https://github.com/linq2db/linq2db/pull/6057). #6088 and #6089 were measured on both the direct and the LinqService arm, so they are provider defects rather than remote-only ones; they are cited for arm coverage. The 2026-10-21 to 2026-11-11 delta adds more instances of the same family: a YDB cached query keeps a NULL check that the remote context drops (#6202), a `ulong.MaxValue` literal fails on several providers and its inlined value differs between direct and remote PostgreSQL (#5973), and the umbrella issue for direct-vs-remote SQL divergence is still open (#5169). Type and configuration information also goes missing in transit: a custom scalar type with a string converter round-trips through `ToString()` (#6153), and a `UseMappingSchema` scope does not restore its schema or `ConfigurationID` (#6270).
- **gRPC client opens a connection per remote call** -- `GrpcDataContext(address)` creates a new channel (TCP, TLS handshake, HTTP/2 preface) for every remote call and closes it afterwards, so a busy client accumulates `TIME_WAIT` sockets at its query rate. Open PR [#6020](https://github.com/linq2db/linq2db/pull/6020) proposes one channel per context, a caller-owned channel option, and reporting cancellation as `OperationCanceledException`.
- **SignalR streaming cancellation and reconnection** -- On 6.5.0 a client-side cancel of a 5 s query over `LinqToDBHub` throws after 300 ms, but the database keeps running the query. The next quick query on the same connection then waits about 4.4 s behind it, and a client dispose mid-query lets the server query run to completion. Open PR [#6014](https://github.com/linq2db/linq2db/pull/6014) (updated 2026-11-10) adds cancellable streaming calls, concurrency limits, a size pre-flight and a restartable DI connection.
- **Remote HttpClient and WASM clients fail outside a full .NET host** -- The remote client breaks in hosts where reflection-based JSON or client-side ADO.NET loading is unavailable. On browser-wasm, building the client-side mapping schema loads ADO.NET provider assemblies that the client cannot load, so initialization fails for PostgreSQL, MySqlConnector, ClickHouse and DuckDB configurations (#6167). A client that suppresses the trim and AOT warnings still serializes with reflection-based System.Text.Json, so it fails wherever that is disabled (WASM, trimmed, NativeAOT) (#6168). The HttpClient transport puts the configuration name into the request path unescaped, so a name containing `/` (`DB2.z/OS`) never reaches the controller and every call answers HTTP 404 (#6176). Blazor WASM hosted gRPC queries have been reported since 2025 (discussion #4617). Merged PR [#6178](https://github.com/linq2db/linq2db/pull/6178) (2026-10-27) added the browser-wasm test lane that surfaced these.

## Resolved themes
- **Remote test clients leaking connections to test hosts** -- Each remote test opened its own client and, for gRPC and most transports, never released it. With providers running in parallel inside one test process, the hosts were flooded with leaked connections. Fixed by [#6010](https://github.com/linq2db/linq2db/pull/6010) (merged 2026-10-10). Related fixes: [#5762](https://github.com/linq2db/linq2db/pull/5762) (merged 2026-08-29) stopped leaking a client per two-query plan in the client itself, and [#5992](https://github.com/linq2db/linq2db/pull/5992) (merged 2026-10-02) made parallel lanes reach the correct LinqService on each test host.
- **Direct and remote baselines compared only when a path is written** -- The direct-vs-remote SQL comparison ran only when `BaselinesPath` was set, so a remote gate passed or failed depending on the environment. [#6048](https://github.com/linq2db/linq2db/pull/6048) (merged 2026-10-15) gated the PostgreSQL remote case of `Issue5972_UInt64` on baselines being written, and [#6015](https://github.com/linq2db/linq2db/pull/6015) (closed, not merged) proposed removing gates that now pass. [#6061](https://github.com/linq2db/linq2db/pull/6061) (merged 2026-10-28) compares both on every run and makes the suppressing gates declarative (`[NoBaselines]`, `ActiveIssue(BaselinesMismatch)`). Tracked by issue [#5157](https://github.com/linq2db/linq2db/issues/5157) (closed 2025-11-02). Moved here from the open themes in this refresh.
- **SignalR.Client audit advisories** -- GHSA-334f-vvp4-7g6p was suppressed globally in [#6043](https://github.com/linq2db/linq2db/pull/6043) (merged 2026-10-14) while the patched SignalR packages were not yet on nuget.org. After the advisory was revised on 2026-10-19, [#6095](https://github.com/linq2db/linq2db/pull/6095) (merged 2026-10-20) raised the `SignalR.Client` floors to patched versions and removed the suppression. [#6295](https://github.com/linq2db/linq2db/pull/6295) (merged 2026-11-11) pinned the legacy SignalR transitives that NuGet audit still flagged.
- **Remote SQL divergence fixed in Transform-mode and keyed eager-load** -- Two fixes closed concrete instances of the open SQL-divergence theme. [#5971](https://github.com/linq2db/linq2db/pull/5971) (merged 2026-10-07) keeps IS NULL on a rebuilt LEFT JOIN source, closing [#5970](https://github.com/linq2db/linq2db/issues/5970), where Transform-mode folded the check so that remote and parameter-dependent queries dropped the default. [#5665](https://github.com/linq2db/linq2db/pull/5665) (closed 2026-07-02) makes the VALUES key order deterministic in keyed eager-load, closing [#5664](https://github.com/linq2db/linq2db/issues/5664).
- **Remote columns resolved against the wrong mapping schema** -- [#5966](https://github.com/linq2db/linq2db/issues/5966) (closed 2026-10-09) reported that the server ignored configuration-scoped column attributes. [#5967](https://github.com/linq2db/linq2db/pull/5967) (merged 2026-10-09) resolves remote columns against the request context's mapping schema.

## Active discussions
- [Problem Running LinqToDb.Remote.Grpc query in blazor wasm hosted](https://github.com/linq2db/linq2db/discussions/4617) -- [Q&A] Blazor WASM hosted client fails with PlatformNotSupportedException (Monitor wait) when querying through LinqToDB.Remote.Grpc. Last updated 2025-09-09.

## Stats
- Open issues: 12
- Closed issues: 4
- Open PRs: 3
- Total PRs: 16
- Discussions: 1
- Last fetched: 2026-11-11

<details><summary>Coverage</summary>

- Index entries cited: 33 (16 issues + 16 PRs + 1 discussion). Open-issue count covers every open issue cited here, not only remote-labelled ones (#6056, #6088, #6089 and #5169 are cited on their SQL or provider content).
- Remote-keyword sweep (title, area, labels, summary) across the issues, PRs and discussions indexes, for the 2026-10-21 to 2026-11-11 delta, plus older REMOTE-tagged entries needed for resolved themes.
- New citations this refresh: 20 (12 issues, 7 PRs, 1 discussion).
- Moved to resolved this refresh: 1 theme (direct vs remote baselines, #6061).
- Dropped citations: none.
- Themes extracted: 9 (4 open, 5 resolved)
</details>
