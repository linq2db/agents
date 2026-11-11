---
area: TESTS-WASM
kind: decisions
sources: [gh-issues, gh-prs, history-decisions]
confidence: medium
last_verified: 2026-11-11
last_verified_sha: f90c5bcfb86d88db436a6494f0640c4c43dd691f
---

# TESTS-WASM -- Decisions

## Recorded decisions
- [HTTP remote transport (LinqToDB.Remote.Http.Client and Server)](../../history/decisions/2025-http-remote-transport.md) -- HTTP is available on WASM, so the remote client's transport runs in the browser. This is the transport the WASM tests exercise.

## Decision-flavored PRs
- [#6178](https://github.com/linq2db/linq2db/pull/6178) (merged 2026-10-27, "Test the remote client in the browser-wasm runtime", fixes #5159) -- decision to run the remote client inside browser-wasm against every shipped provider configuration on every PR. The index summary shows no breaking label and no `## Decision` heading; included because it sets the test-scope policy for this area.
- [#5158](https://github.com/linq2db/linq2db/pull/5158) (merged 2025-11-28, "Fixed in browser remote") -- decision that the remote client must not load data-provider assemblies client-side. The index shows no breaking label and no file count; included as the boundary the WASM matrix now enforces.

## Related proposals
- [#4618](https://github.com/linq2db/linq2db/issues/4618) (closed 2025-09-09, "[Refactoring] Remove or obsolete sync APIs from remote context") -- proposed removing or disabling the sync remote APIs, which block the WASM runtime. The index records no outcome beyond the closed state.

## See also
- [GLOBAL decisions](../GLOBAL/decisions.md)
- [TESTS-BENCHMARKS decisions](../TESTS-BENCHMARKS/decisions.md)
