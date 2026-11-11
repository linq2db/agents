---
area: TESTS-INFRA
kind: issues
sources: [gh-issues, gh-prs, gh-discussions]
confidence: medium
last_verified: 2026-11-11
last_verified_sha: f90c5bcfb86d88db436a6494f0640c4c43dd691f
---

# TESTS-INFRA -- GitHub themes

## Open themes
- **Scaffold code-generation test harness** -- The scaffolder's generated code has only been checked against committed golden files that CI never regenerates. #6021 asks for a harness that feeds a predefined schema to the generator, compiles the output (C# and F#) and executes it. Draft #6037 implements it in `Tests/Tests.Scaffold.Harness` on branch `feature/6021-scaffold-codegen-harness`, stacked on the F# codegen draft #5707. Both drafts are still open.
- **Baseline comparison and capture** -- Direct-vs-remote SQL baseline gating now runs on every run, with declarative suppressions (`[NoBaselines]`, `ActiveIssue(BaselinesMismatch)`). #6061 merged 2026-10-28 (see Resolved). Open #5918 covers two remaining baseline-capture races and the unsorted schema-filter list.
- **Flaky tests from pooled connections and shared state** -- Intermittent failures trace to state shared across tests or runs. #5745: a YDB schema read fails when one undescribable path breaks the whole listing (SchemeError). #6012: a cancelled Firebird async call can poison a pooled connection; the test-side workaround #6013 is merged.
- **Test lane routing for context-less tests** -- #6232 (open) proposes running tests that carry no provider context in the default provider's lane.
- **Gate mechanics and host-dependent gates** -- Gates fail in two ways. An attribute does not rewrite the outcome in a fixture without `[SetUp]` / `[TearDown]` (#6174). A gate keyed to host settings fails on other hosts (#6164: SQLite #2107 `DateTimeRoundtrip_*Utc` gates fail on non-UTC hosts). #6296 (open PR) removes two stale Access #6203 gates.
- **Result comparison without a comparer** -- Without a comparer, AssertQuery checked only the row count for a scalar element type (#6099). #6131 switched to value comparison. #6179 (open) finds the test comparer still ignores the key of an `IGrouping`.

## Resolved themes
- **Test progress heartbeat under --filter** -- The heartbeat reported the pre-filter test count as total, so the percentage and ETA were wrong on filtered runs. Fixed by #6098 (merged 2026-10-21, new `Tests/Base/TestRunCounter.cs`), closing #5964. #6149 (closed) records the launching session in the heartbeat.
- **Test-host stability (pooled connections, exit crashes, FPU traps)** -- #6010 stopped remote test clients leaking connections to in-process hosts. #5992 fixed remote test hosts serving the wrong LinqService under parallel lanes. #6073 purges the IBM DB2 connection pool at assembly teardown (SIGSEGV at process exit after a passing run). #6013 works around #6012 in the suite. #6058 adds the x86 FPU-unmasked JIT sweep gate (`Tests/Tests.FpuJit`) and fixes ten provider methods; the reporting issue #6051 closed with it. #6233 snapshots TestBase reference data once per run.
- **Gate hygiene** -- #6097 rewrote Issue4199 to the issue's repro and removed the gate, closing #4199. #6029 excluded Sybase from `UnusedSource_Query` instead of gating it, because the test's MERGE segfaults the ASE session. #6048 gates the PostgreSQL remote case of Issue5972 only when baselines are written. #6015 (remove gates that now pass) was closed without merge. #5882 replaced `[ActiveIssue]` with a run-and-verify attribute. #6135 gates TestNullConfiguration on SQLite.Classic. #6171 states why MDS UDT reads are gated on net8+. #5908 stopped executing the 101-join StackOverflow test.
- **Flaky tests resolved** -- #5887 (ParameterReuse cost test flaky on netfx legs, missing `[QueryCacheTest]`) closed after its fix #5912 landed. #5763 (merged 2026-11-06) bumps Ydb.Sdk to 0.38.0 and skips tables dropped during the primary-key read; #5745 stays open. #6104 locks client-side evaluation of a captured collection's Count.
- **Test database lifecycle** -- #6054 makes MySQL `CreateDatabase` recreate a missing database after an interrupted run. #5765 (DB2 AllTypes junk rows accumulate across runs) is closed; the closing change is not identified in the index excerpt. #5920 truncates the Sybase test databases' log on checkpoint. #5986 fixes the local Oracle 12 setup script. #6161 tests the SQL Server case-sensitive catalog and merges the custom SQL Server test modes onto 2025.
- **CI test-leg plumbing** -- #5322 (closed) fixed the Testing configuration and filtered solutions. #6005 split the x86 Access MDB leg per provider after OutOfMemory in NUnit result aggregation. #6011 restored Docker Hub login on Azure test legs. #6017 added a macOS leg to the CLI tests job. #6004 retries baselines pushes that fail with HTTP 5xx. #6006 bases stacked PRs' baselines on the parent's baselines branch. #5990 and #5996 renamed sqlserver2016.cmd to sqlserver2016-win.cmd (it starts a Windows container). #5950 disabled the ODP.NET statement cache and moved the Oracle legs to GitHub Actions. #5962 fixed the ClickHouse CI leg on ClickHouse 26.9. #6128 runs the release-PR provider matrix on GitHub Actions. #6126 fixed release-run failures from build 24621. #6132 skips the setup steps in a test job whose matrix selected no leg. #6288 stops Azure Pipelines auto-cancelling in-flight PR runs.
- **Provider test dependencies** -- #5888 pins NUnit parallelism on the Oracle GitHub Actions legs to match Azure (closed; moved from Open). #5730 replaced the legacy dotMorten SQL Server types test dependency (closed; moved from Open).
- **Baseline pipeline fixes** -- #6061 compares direct and remote baselines on every run and adds `[NoBaselines]` and `ActiveIssue(BaselinesMismatch)` (merged 2026-10-28; moved from Open). #6222 leases the baselines-branch rebase push so it cannot delete concurrent leg commits. #6290 keeps a failed baselines-PR retarget non-fatal. #6291 resolves baselines rebase conflicts to the base branch's side. #5917 makes SQL baselines agree between the release and PR pipelines. #6259 excludes SchemaProvider_TableDroppedConcurrently from baselines.
- **Scalar and collection comparison** -- #6099 (closed) fixed AssertQuery over a scalar element type without a comparer, which checked only the row count. #6131 compares scalar and collection results by value when no comparer is passed.

## Active discussions
- None in this area as of 2026-11-11.

## Stats
- Open issues: 8
- Closed issues: 9
- Open PRs: 3
- Total PRs: 46
- Discussions: 0
- Last fetched: 2026-11-11

<details><summary>Coverage</summary>

- Index entries scanned: 371 updated in the 2026-10-21..2026-11-11 window (201 issues + 170 PRs + 0 discussions), plus area-tag lookups (TESTS-INFRA: 6 issues tagged)
- Themes extracted: 15 (6 open, 9 resolved)
- Stats count only items cited in this artifact
</details>
