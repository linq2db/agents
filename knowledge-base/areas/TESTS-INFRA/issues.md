---
area: TESTS-INFRA
kind: issues
sources: [gh-issues, gh-prs, gh-discussions]
confidence: medium
last_verified: 2026-10-21
last_verified_sha: 89b5ce16278728b9936ba374827fea002c76e962
---

# TESTS-INFRA -- GitHub themes

## Open themes
- **Scaffold code-generation test harness** -- The scaffolder's generated code has only been checked against committed golden files that CI never regenerates. #6021 asks for a harness that feeds a predefined schema to the generator, compiles the output (C# and F#) and executes it. Draft #6037 implements it in `Tests/Tests.Scaffold.Harness`, stacked on the F# codegen PR #5707.
- **Baseline comparison and capture** -- Direct-vs-remote SQL baseline gating is moving from environment-dependent to every run. Draft #6061 compares both baselines on every run and makes the suppressions declarative (`[NoBaselines]`, `ActiveIssue(BaselinesMismatch)`). Open #5918 covers two remaining baseline-capture races.
- **Flaky tests from shared state and pooled connections** -- Intermittent failures trace to state shared across tests or runs. #5887: the ParameterReuse cost test is flaky on netfx legs and lacks `[QueryCacheTest]`. #5745 and draft #5763: a YDB schema read fails when a table is dropped between listing and describing it. #6012: a cancelled Firebird async call can poison a pooled connection; the test-side workaround #6013 is merged.
- **Provider test dependencies and CI parallelism** -- #5888 pins NUnit parallelism on the Oracle GitHub Actions legs to match Azure. #5730 replaces the legacy dotMorten SQL Server types test dependency. Both open.

## Resolved themes
- **Test progress heartbeat under --filter** -- The heartbeat reported the pre-filter test count as total, so the percentage and ETA were wrong on filtered runs. Fixed by #6098 (merged 2026-10-21, new `Tests/Base/TestRunCounter.cs`), closing #5964.
- **Test-host stability (pooled connections, exit crashes, FPU traps)** -- #6010 stopped remote test clients leaking connections to in-process hosts. #6073 purges the IBM DB2 connection pool at assembly teardown (SIGSEGV at process exit after a passing run). #6013 works around #6012 in the suite. #6058 adds the x86 FPU-unmasked JIT sweep gate (`Tests/Tests.FpuJit`) and fixes ten provider methods; the reporting issue #6051 closed with it.
- **Gate hygiene** -- #6097 rewrote Issue4199 to the issue's repro and removed the gate, closing #4199. #6029 excluded Sybase from `UnusedSource_Query` instead of gating it, because the test's MERGE segfaults the ASE session. #6048 gates the PostgreSQL remote case of Issue5972 only when baselines are written. #6015 (remove gates that now pass) was closed without merge.
- **Test database lifecycle** -- #6054 makes MySQL `CreateDatabase` recreate a missing database after an interrupted run. #5765 (DB2 AllTypes junk rows accumulate across runs) is closed; the closing change is not identified in the index excerpt.
- **CI test-leg plumbing** -- #5322 (closed) fixed the Testing configuration and filtered solutions. #6005 split the x86 Access MDB leg per provider after OutOfMemory in NUnit result aggregation. #6011 restored Docker Hub login on Azure test legs. #6017 added a macOS leg to the CLI tests job. #6004 retries baselines pushes that fail with HTTP 5xx. #6006 bases stacked PRs' baselines on the parent's baselines branch.

## Active discussions
- None in this area as of 2026-10-21.

## Stats
- Open issues: 7
- Closed issues: 4
- Open PRs: 4
- Total PRs: 20
- Discussions: 0
- Last fetched: 2026-10-21

<details><summary>Coverage</summary>

- Index entries scanned: 128 (63 issues + 65 PRs + 0 discussions), plus index area-tag lookups (TESTS-INFRA, area: tests)
- Themes extracted: 9 (4 open, 5 resolved)
- Stats count only items cited in this artifact
</details>
