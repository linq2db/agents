---
area: TESTS-LINQ
kind: issues
sources: [gh-issues, gh-prs, gh-discussions]
confidence: high
last_verified: 2026-10-21
last_verified_sha: 89b5ce16278728b9936ba374827fea002c76e962
---

# TESTS-LINQ -- GitHub themes

## Open themes

- **Regression tests for expression-translation bugs** -- targeted test coverage for reported translation issues: nullable-type handling (#5125), type mappings (#5390, #5340), string concatenation (#5441), and a Union over converter-typed columns (#6052, covered by the merged test in #6060). Tests often remain in draft pending the related code fix. Sample: #5524, #5508, #5391, #5345, #5308, #5293, #6060. Still open as drafts: #5308, #5293. Closed without merge: #5508, #5524, #5391, #5345. Merged regression test: #6060 (2026-10-16).

## Resolved themes
- **Test-suite stability (4 items)** -- gate and flake hygiene in the LINQ test suite. #5641 removed the [NonParallelizable] markers and their justifying comments across the test suite (merged 2026-06-21). #5912 fixed a flaky test, ParameterReuse_ImpureExpression_CostDoesNotGrowPerBuild, in Tests/Linq/Linq/JoinTests.cs (merged 2026-09-12). #6015 removed [ActiveIssue] gates that the test-all run reported as gate-too-wide, because the gated tests now pass (merged 2026-10-10). #6097 rewrote Issue4199Test1/2 to the issue's repro and dropped the gate; the old tests queried a table that does not exist and never reproduced #4199. Closes #4199 (merged 2026-10-21).

## Active discussions
None.

## Stats
- Open issues: 0
- Closed issues: 0
- Open PRs: 2
- Total PRs: 11
- Discussions: 0
- Last fetched: 2026-10-21

<details><summary>Coverage</summary>

- Index entries scanned: 11 (0 issues + 11 PRs + 0 discussions)
- Themes extracted: 2 (1 open, 1 resolved)
</details>
