---
area: TESTS-LINQ
kind: issues
sources: [gh-issues, gh-prs, gh-discussions]
confidence: high
last_verified: 2026-10-10
last_verified_sha: 05150894edc2511f0dd0bc7829b2a309cec36ec9
---

# TESTS-LINQ -- GitHub themes

## Open themes

- **Regression tests for expression-translation bugs** -- targeted test coverage for reported translation issues: nullable-type handling (#5125), type mappings (#5390, #5340), and string concatenation (#5441). Tests often remain in draft pending the related code fix. Sample: #5524, #5508, #5391, #5345, #5308, #5293. Still open as drafts: #5308, #5293. Closed without merge: #5508, #5524, #5391, #5345.

## Resolved themes
- **Test-suite stability (2 items, below the 3-item theme threshold)** -- #5641 removed the [NonParallelizable] markers and their justifying comments across the test suite (merged 2026-06-21). #5912 fixed a flaky test, ParameterReuse_ImpureExpression_CostDoesNotGrowPerBuild, in Tests/Linq/Linq/JoinTests.cs (merged 2026-09-12).

## Active discussions
None.

## Stats
- Open issues: 0
- Closed issues: 0
- Open PRs: 2
- Total PRs: 8
- Discussions: 0
- Last fetched: 2026-10-09

<details><summary>Coverage</summary>

- Index entries scanned: 8 (0 issues + 8 PRs + 0 discussions)
- Themes extracted: 1
</details>
