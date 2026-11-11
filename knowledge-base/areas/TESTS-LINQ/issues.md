---
area: TESTS-LINQ
kind: issues
sources: [gh-issues, gh-prs, gh-discussions]
confidence: high
last_verified: 2026-11-11
last_verified_sha: f90c5bcfb86d88db436a6494f0640c4c43dd691f
---

# TESTS-LINQ -- GitHub themes

## Open themes

- **Regression tests for expression-translation bugs** -- targeted regression tests for reported translation issues. Tests often stay in draft until the related code fix lands. Still open as drafts: #5308 (regression tests for several issues, among them #5303 and #5296) and #5293 (tests for #5267). Drafts closed without merge and merged tests are listed under Resolved themes.
- **Set operations over a (T?)null branch (open part)** -- Union, Intersect and Except where one branch is a null (T?)null projection and the other an optional object. Still open: #6183 (Union, Intersect and Except return wrong rows for a query-written null test against a (T?)null branch) and #6187 (reading a member of the optional object after Union or Intersect with a null branch throws; follow-up to #6156 and #6159).
- **Gate hygiene in Tests/Linq** -- [ActiveIssue] gates that outlive their fix or fail on some hosts. Still open: #6296 (PR removing the stale Access #6203 gates from two ORDER BY predicate tests, updated 2026-11-11) and #6164 (SQLite #2107 DateTimeRoundtrip_*Utc gates fail on non-UTC hosts). Only two open items; kept as a theme because the gate-removal pattern recurs (see Resolved themes).

## Resolved themes
- **Test-suite stability (8 items)** -- gate and flake hygiene in the LINQ test suite. #5641 removed the [NonParallelizable] markers and their justifying comments across the test suite (merged 2026-06-21). #5912 fixed a flaky test, ParameterReuse_ImpureExpression_CostDoesNotGrowPerBuild, in Tests/Linq/Linq/JoinTests.cs (merged 2026-09-12). #5908 stopped executing the 101-join JoinTests.StackOverflow test (merged 2026-09-12). #6015 removed [ActiveIssue] gates that the test-all run reported as gate-too-wide, because the gated tests now pass (merged 2026-10-10). #6097 rewrote Issue4199Test1/2 to the issue's repro and dropped the gate; the old tests queried a table that does not exist and never reproduced #4199. Closes #4199 (merged 2026-10-21). #6135 gated the four DataContextTests.TestNullConfiguration_* tests on SQLite.Classic (merged 2026-10-29). #6048 gated the PostgreSQL remote Issue5972_UInt64 case to runs that write baselines (merged 2026-10-15). #6160 removed redundant PreLoadSQLite_BaseDirectory assignments (merged 2026-10-28; issue #5906 closed).
- **Regression tests for translation bugs (resolved part)** -- #6060 added the Union regression test over columns that share a value converter class (merged 2026-10-16) for #6052; the defect itself was fixed by #5978 (6.5.1). #6104 locked client-side evaluation of a captured collection's Count (merged 2026-10-22; regression tests for #5557). Closed without merge: #5508 (for #5125), #5524 (for #5441), #5391 (for #5390) and #5345 (for #5340).
- **Set operations over a (T?)null branch (fixed part)** -- #6156 (closed 2026-11-10) reported Union and Intersect of an optional object against a (T?)null branch throwing "Could not decide which ..."; the null-branch fix is #6159 (merged 2026-11-10).

## Active discussions
None.

## Stats
- Open issues: 0 (by area tag TESTS-LINQ)
- Closed issues: 0 (by area tag TESTS-LINQ)
- Open PRs: 2
- Total PRs: 9
- Discussions: 0
- Last fetched: 2026-11-11

<details><summary>Coverage</summary>

- Index entries scanned: 6240 (3245 issues + 2699 PRs + 296 discussions), filtered by area tag, Tests/Linq linked_files and title or summary keywords
- Themes extracted: 6 (3 open, 3 resolved)
</details>
