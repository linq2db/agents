---
area: TESTS-WASM
kind: patterns
sources: [code, conventions]
confidence: medium
last_verified: 2026-11-11
last_verified_sha: f90c5bcfb86d88db436a6494f0640c4c43dd691f
---

# TESTS-WASM -- Patterns

## Recurring patterns in the area

- **Publish out of band, run by launching node.** The NUnit host (`Tests/Tests.Wasm`) never references the app project. `publish-wasm-bundles.ps1` writes `.build/wasm/<mode>/` and `WasmBundleRunner` spawns `node main.mjs` on it. Every mode gets its own `ArtifactsProjectName` (`Directory.Build.props`) so trimmed output is never reused across modes.
- **Four-mode bundle matrix.** Debug, TrimPartial, TrimFull and NoReflectionJson. The explicit `PublishTrimmed=false` in non-trimmed modes is needed because the WebAssembly SDK trims by default.
- **Shared contract by linked source.** `WasmReport.cs` and `WasmPerson.cs` are compiled into both app and host with `<Compile Include ... Link>`. The report is one `L2DB-WASM-REPORT ` JSON line per configuration, written with `Utf8JsonWriter` because reflection JSON is disabled or trimmed in some modes.
- **Cache one node run per mode.** `WasmRuntimeTests.GetRunAsync` covers all available, preflight-clean configurations in a single process, and tests assert per row on the parsed report.
- **Server-side preflight blames the right side.** Each row builds its provider in-process and calls `GetInfoAsync` first. A provider that cannot load on the runner is reported as unavailable, never as a client failure. Preflight and missing-report errors are thrown as `ShouldAssertException` so they cannot accidentally match an `[ActiveIssue]` gate.
- **Gate known failures with `[ActiveIssue(<n>)]`, and assert exclusions.** `UnavailableOnRunner` asserts the expected "Cannot load assembly" text, so a stale exclusion turns red.
- **Table-driven coverage with a completeness check.** `ProviderMatrix.Rows` plus `ProviderNamesAreCovered` (every public `ProviderName` constant needs a row or an `Aliases` entry).
- **Exit 0 from the app, verdict in the host.** `Program.Main` records per-operation errors and an `Unexpected` operation, and the host decides what is red. `AssemblyResolve` failures are recorded, not failed, since optional assemblies are probed on purpose.

## Applicable conventions

- Tests use Shouldly (`ShouldAssertException`), not NUnit `Assert`. See [conventions/](../../conventions/) for the catalog.
- The app removes the Tests-wide `BannedSymbols.txt` because it writes to `System.Console`.

## Recorded decisions affecting this area

- No area-scoped recorded decisions existed when this rollup was produced (`decisions.md` absent). See [INDEX.md](INDEX.md) for the design rationale (regression guard for #5158 / #5159, no database involved).

## See also

- [INDEX.md](INDEX.md) -- area architecture
- [tech-debt.md](tech-debt.md) -- gated issues and structural debt
- [../TESTS-BENCHMARKS/patterns.md](../TESTS-BENCHMARKS/patterns.md) -- sibling test-side area
