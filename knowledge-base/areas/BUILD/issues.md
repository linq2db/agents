---
area: BUILD
kind: issues
sources: [gh-issues, gh-prs, gh-discussions]
confidence: high
last_verified: 2026-10-10
last_verified_sha: 05150894edc2511f0dd0bc7829b2a309cec36ec9
---

# BUILD -- GitHub themes

## Open themes

- **CI migration to GitHub Actions (ongoing)** -- the test matrix is moving from Azure Pipelines to GitHub Actions in increments: the database-free build and checks (#5836), matrix selection as data (#5848), the Linux provider legs and their parity with Azure (#5866, #5880), the docker-free Windows legs (#5898, #5899), and the PR-comment trigger that replaced the Azure dispatch job (#5869, #5871, #5872). Run status is reported on the PR as a commit status (#5875). Sample: #5866, #5871, #5898.
- **Baselines push and stacked-PR baselines (open)** -- CI pushes regenerated SQL baselines to linq2db.baselines and must cope with concurrent pushes. Open: #6004 replaces the fixed fetch/rebase/push retry loop with back-off on server-side push failures, and #6006 (draft) bases a stacked PR's baselines branch on its parent's baselines branch so the child does not repeat parent changes. Earlier fixes: #5715, #5859, #5878, #5917. Sample: #6004, #6006.
- **Parallel test execution and test-infra splits** -- the parallel test-execution work (#5614) was split into separate PRs covering shared test data, CI log trimming, Linux disk cleanup and per-leg overhead. Sample: #5622, #5795, #5819.

## Resolved themes

- **Release preparation and versioning** -- coordinated dependency updates, PublicAPI baselines, analyzer-rule enforcement and version bumps for 6.3.0 and the 6.4.0 bump. Sample: #5533, #5534, #5536.
- **Build failure quick-fix cycles** -- transient master breakage fixed quickly (build errors, unbreak-build PRs, baselines reset before retried attempts, Release-mode analyzer errors in test projects). Sample: #5491, #5537, #5637, #5615, #5572.
- **Analyzer gating to Release builds** -- IDE analyzers, ReportAnalyzer and xml-doc generation gated to Release for faster Debug/Testing builds; deferred Meziantou rules resolved. Sample: #5516, #5573.
- **CS2012 double-build race** -- generator and LinqToDB pre-built before the solution to avoid the CS2012 race during build and pack. Sample: #5858, #5876.
- **Packaging and NuGet source hygiene** -- LINQPad driver packed under net8.0 for macOS/Linux, scaffold package Redist references, tolerance for an over-quota Azure Artifacts feed, and removal of an unusable NuGet source. Sample: #5565, #5571, #5807, #5835.
- **Test projects on Microsoft.Testing.Platform** -- NUnit test projects migrated from VSTest to MTP, with a live test-progress heartbeat and a PublishSingleFile smoke test scoped to build/default. Sample: #5612, #5610, #5607.

## Active discussions

None currently open.

## Stats

- Open issues: 0
- Closed issues: 0
- Open PRs: 3
- Total PRs: 50
- Discussions: 0
- Last fetched: 2026-10-09

<details><summary>Coverage</summary>

- Index entries scanned: 50 (0 issues + 50 PRs + 0 discussions)
- Themes extracted: 3 open, 6 resolved
- Not themed: #5633, #2631, #2693 (closed drafts); #5673 and #5688 (query-engine PRs carrying area BUILD in the index, a reclassification question for the index rather than a theme)
</details>
