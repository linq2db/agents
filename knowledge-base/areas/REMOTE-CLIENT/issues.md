---
area: REMOTE-CLIENT
kind: issues
sources: [gh-issues, gh-prs, gh-discussions]
confidence: medium
last_verified: 2026-10-10
last_verified_sha: 05150894edc2511f0dd0bc7829b2a309cec36ec9
---

# REMOTE-CLIENT -- GitHub themes

## Open themes
- **Remote test-host and client lifetime** -- Remote test clients leak connections to the test hosts, and test-host wiring picked the wrong LinqService under parallel lanes. Open: #6010 (PR, stop remote test clients leaking connections to the test hosts). Recent fixes: #5762 (stop leaking a client per two-query plan, guard double dispose, merged 2026-08-29), #5992 (test hosts serving the wrong LinqService under parallel lanes, merged 2026-10-02). Harness precursor: #5157 (baselines comparison for direct and remote context testruns).

## Resolved themes
- **WCF / LinqService transport (legacy)** -- Recurring WCF-era reports on the WCF-based remote context: #16, #659, #730, #1041, #1187, #1678, #1915, #2993, #3409. Resolved by the move to HTTP transport in #4775 (LinqToDB.Remote.Http.Client / Server, merged 2025-05-12).
- **Remote MappingSchema and column resolution** -- Remote host did not apply the caller's mapping (#1726 additional MappingSchema on host; #1629 DateTime with Kind=Utc sent incorrectly over remote context). Resolved by #5967 (resolve remote columns against the request context's mapping schema, merged 2026-10-09). Related SQL-side remote-context fix: #5971 (keep IS NULL on a rebuilt LEFT JOIN source in Transform-mode convert, merged 2026-10-07).
- **WebApi / OData entity serialization** -- #1046 (OData cast to derived type with expand), #2442 (LoadWith exception in WebApi Core 3.1), #4197 (navigation properties break ModelState validation). All closed, no linked fix in the index.
- **Sync API surface on remote context** -- #4618 (remove or obsolete sync APIs) and #5106 (remove sync APIs from transport interface, merged 2025-09-09). Two items only, below cluster threshold; listed for context.

## Active discussions
- [Documentation for creating new data provider or extending existing](https://github.com/linq2db/linq2db/discussions/4555) -- [Q&A] Hello, asks how to build a custom remote transport; no maintainer answer in index.
- [Problem Running LinqToDb.Remote.Grpc query in blazor wasm hosted](https://github.com/linq2db/linq2db/discussions/4617) -- [Q&A] Blazor WASM hosted client using LinqToDB.Remote.Grpc. In-browser remote fix landed in #5158 (merged 2025-11-28).

## Stats
- Open issues: 0
- Closed issues: 16
- Open PRs: 1
- Total PRs: 14
- Discussions: 2
- Last fetched: 2026-10-09

<details><summary>Coverage</summary>

- Index entries scanned: 32 (16 issues + 14 PRs + 2 discussions)
- Themes extracted: 5
</details>
