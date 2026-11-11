---
area: TESTS-WASM
kind: tech-debt
sources: [code]
confidence: medium
last_verified: 2026-11-11
last_verified_sha: f90c5bcfb86d88db436a6494f0640c4c43dd691f
---

# TESTS-WASM -- Tech debt

## No detected issues

This area has no entries in [detected-issues/index.json](../../detected-issues/index.json) as of 2026-11-11. The debt below is taken from [INDEX.md](INDEX.md) and the source under `Tests/Tests.Wasm*/`, not from the issue detector. `issues.md` and `decisions.md` did not exist for this area when this rollup was produced.

## Debt recorded in source (gated or documented)

- `[ActiveIssue(6167)]` on `ClientLoadsProviderAssembly` (`Tests/Tests.Wasm/WasmRuntimeTests.cs`): client libraries for `LoadsProviderAssembly` rows (DB2, Informix.DB2, MySql family, PostgreSQL, ClickHouse, DuckDB) fail with "Cannot load assembly" in the WASM runtime.
- `[ActiveIssue(6168)]` on `ClientFailsUnderFullTrimming` (TrimFull, `DeserializeNoConstructor`) and `ClientFailsWithoutReflectionJson` (NoReflectionJson, `JsonSerializerIsReflectionDisabled`). Trim cleanliness of linq2db is why `Tests.Wasm.App.csproj` sets `SuppressTrimAnalysisWarnings`.
- Coupling between the two gates: a fix to #6168 will expose #6167 on `LoadsProviderAssembly` rows under TrimFull and NoReflectionJson (comment near `WasmRuntimeTests.cs:105`), so those cases must be split when #6168 lands.
- #6176: the client does not escape the configuration name in the request path, so the matrix keys DB2 z/OS as `DB2.zOS` instead of `DB2.z/OS`.
- #6177: `SybaseTools.GetDataProvider(Unmanaged)` returns the managed provider when the native assembly is absent, so the Sybase native row is built through `DataConnection.GetDataProvider("Sybase.Native", ...)`.
- #6174: `[ActiveIssue]` rewrites a result only when a SetUp command has turned the exception into one, hence the intentionally empty `[SetUp]` in `WasmRuntimeTests`.

## Structural debt (no issue filed)

- Hand-maintained provider matrix: `ProviderMatrix.Rows` has 61 rows. A new provider version needs a manual edit, and `ProviderNamesAreCovered` guards only at `ProviderName` constant level, not version level.
- Six rows are permanently unavailable on every runner OS (Informix, Oracle11Native, OracleNative, SqlCe, Sybase native, SapHanaNative). `UnavailableOnRunner` keeps the exclusions honest but they never exercise the client.
- DB2 rows depend on a CI-only `clidriver` step in `.github/workflows/build.yml` (job `wasm-tests`) that mirrors `Build/Azure/scripts/db2.provider.sh`. The two copies can drift.
- Out-of-band bundle publishing: `Tests.Wasm` never references `Tests.Wasm.App`, and the app is not in `linq2db.slnx`. A stale or missing `.build/wasm/<mode>/` fails only at test time, with an `InvalidOperationException` carrying the publish command. The publish script's stale-output deletion is the only guard.
- GitHub Actions only: no Azure pipeline runs this area.
- Operational limits: a fixed 2 minute node timeout (`WasmBundleRunner.Timeout`) and a 20 minute job timeout. Slow runners could turn a healthy run into a false red.
- Verification gap: the app checks only generated SQL text (`ToSqlQuery().Sql`) plus one SQLite round trip, so runtime failures in query execution paths are out of scope by design.

## See also

- [INDEX.md](INDEX.md) -- area overview
- [patterns.md](patterns.md) -- area patterns
- [../TESTS-BENCHMARKS/tech-debt.md](../TESTS-BENCHMARKS/tech-debt.md) -- sibling test-side area
