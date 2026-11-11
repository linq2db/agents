---
area: EXAMPLES
kind: decisions
sources: [gh-prs, gh-issues, history-decisions]
confidence: medium
last_verified: 2026-11-11
last_verified_sha: f90c5bcfb86d88db436a6494f0640c4c43dd691f
---

# EXAMPLES -- Decisions

## Recorded decisions
- [HTTP remote transport (LinqToDB.Remote.Http.Client/Server)](../../history/decisions/2025-http-remote-transport.md) -- the transport the HttpClient sample is built on (#4775). Recorded as a GLOBAL decision.

## Decision-flavored PRs
- [#4775](https://github.com/linq2db/linq2db/pull/4775) (merged 2025-05-12) -- adds the HttpClient and SignalR remote transports with Blazor support. Both Blazor samples depend on it.
- [#4821](https://github.com/linq2db/linq2db/pull/4821) (merged 2025-02-21) -- new `linq2db.Compat` package for `System.Configuration.ConfigurationManager` users. The Compat sample depends on it.
- [#4005](https://github.com/linq2db/linq2db/pull/4005) (merged 2024-01-23) -- adds the `ActivityService` API that the OpenTelemetry sample bridges. Closes #3405.
- [#6043](https://github.com/linq2db/linq2db/pull/6043) (merged 2026-10-14) -- suppresses GHSA-334f-vvp4-7g6p globally to unblock NuGet audit. Superseded by #6095.
- [#6095](https://github.com/linq2db/linq2db/pull/6095) (merged 2026-10-20) -- drops that suppression and raises the SignalR.Client floors to patched versions. The SignalR samples consume these packages.
- [#6127](https://github.com/linq2db/linq2db/pull/6127) (merged 2026-10-24) -- CI builds Examples in Release, not only Debug, so analyzer findings in sample code fail the build.

## Issue-recorded decisions without a linked PR
- [#4618](https://github.com/linq2db/linq2db/issues/4618) (closed 2025-09-09) -- remote context sync APIs are removed or obsoleted for WASM. The index does not record which, and links no closing PR.

## See also
- [EXAMPLES themes](issues.md)
