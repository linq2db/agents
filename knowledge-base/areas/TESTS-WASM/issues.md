---
area: TESTS-WASM
kind: issues
sources: [gh-issues, gh-prs, gh-discussions]
confidence: medium
last_verified: 2026-11-11
last_verified_sha: f90c5bcfb86d88db436a6494f0640c4c43dd691f
---

# TESTS-WASM -- GitHub themes

## Open themes
- **Client-side provider loading breaks under WASM** -- the remote client builds a client-side mapping schema, and for PostgreSQL, MySqlConnector, ClickHouse.Driver and DuckDB that creates a provider adapter which loads an ADO.NET assembly the browser bundle does not ship. Gated by `ClientLoadsProviderAssembly` (`[ActiveIssue(6167)]`). Open: #6167. Predecessor, resolved: #5158.
- **Reflection-based JSON and trimming** -- the HttpClient client serializes with reflection-based System.Text.Json while suppressing trim and AOT warnings, so the TrimFull and NoReflectionJson bundles fail (`ClientFailsUnderFullTrimming`, `ClientFailsWithoutReflectionJson`, both `[ActiveIssue(6168)]`). Fixing #6168 exposes #6167 on the LoadsProviderAssembly rows, so the cases must be split then. General AOT stripping context: #4018.
- **Provider matrix keys and provider selection** -- two open defects in the matrix the WASM run depends on. A configuration name containing a slash never reaches the server route: `DB2.z/OS` gets HTTP 404 (#6176), and the matrix uses `DB2.zOS` as a workaround. `SybaseTools.GetDataProvider` ignores the requested `SybaseProvider` and returns the managed provider (#6177, regression from #5228).
- **Test gates in the WASM fixture** -- `[ActiveIssue]` rewrites a result only when the fixture has a `[SetUp]` or `[TearDown]` (#6174). `WasmRuntimeTests` carries an empty `[SetUp]` (`WasmRuntimeTests.cs:78`) so its gates take effect; that workaround depends on this issue.

## Resolved themes
- **Remote client loading data providers in the browser** -- moving provider-specific code into ProviderAdapters made the Remote component load ADO.NET providers on the client. Fixed by #5158 (merged 2025-11-28, commit 316d415).
- **Sync APIs blocking the single-threaded runtime** -- the remote context sync APIs block or throw under WASM (`PlatformNotSupportedException`, "Cannot wait on monitors"). Tracked by #4618 (closed 2025-09-09; the index records no closing commit). `Program.cs` works around it by calling `InitHttpClientAsync` first.
- **WASM runtime test coverage** -- #5159 asked for WASM runtime tests to catch #5158-style regressions. Closed 2026-10-27 by #6178 (merged the same day, "Fixes #5159"), which added the `Tests.Wasm` harness and the `wasm-tests` CI job.

## Active discussions
- [Problem Running LinqToDb.Remote.Grpc query in blazor wasm hosted](https://github.com/linq2db/linq2db/discussions/4617) -- [Q&A] Blazor WASM hosted client using the gRPC remote transport fails with `PlatformNotSupportedException` ("Cannot wait on monitors"); the thread that led to #4618. Index area tag is REMOTE-CLIENT; classified here by content.

## Stats
- Open issues: 5 (#6167, #6168, #6174, #6176, #6177)
- Closed issues: 2 (#4618, #5159)
- Open PRs: 0
- Total PRs: 2 (#5158, #6178)
- Discussions: 1 (#4617)
- Last fetched: 2026-11-11

<details><summary>Coverage</summary>

- Index entries scanned: 6240 (3245 issues + 2699 PRs + 296 discussions), keyword and item-number screen
- Themes extracted: 7 (4 open, 3 resolved)
- New citations: 11 (#4018, #4617, #4618, #5158, #5159, #6167, #6168, #6174, #6176, #6177, #6178)
</details>
