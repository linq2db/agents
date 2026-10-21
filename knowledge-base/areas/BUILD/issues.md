---
area: BUILD
kind: issues
sources: [gh-issues, gh-prs, gh-discussions]
confidence: high
last_verified: 2026-10-21
last_verified_sha: 89b5ce16278728b9936ba374827fea002c76e962
---

# BUILD -- GitHub themes

## Open themes

- **CI migration to GitHub Actions (ongoing)** -- the test matrix is moving from Azure Pipelines to GitHub Actions in increments: the database-free build and checks (#5836), matrix selection as data (#5848), the Linux provider legs and their parity with Azure (#5866, #5880), the docker-free Windows legs (#5898, #5899), and the PR-comment trigger that replaced the Azure dispatch job (#5869, #5871, #5872). Run status is reported on the PR as a commit status (#5875). Recent follow-ups on the Azure legs: Docker Hub login restored (#6011), the x86 Access MDB leg split per provider (#6005), and a macOS leg added to the CLI tests job (#6017). Sample: #5866, #5871, #5898, #6011.
- **Parallel test execution and test-infra splits** -- the parallel test-execution work (#5614) was split into separate PRs covering shared test data, CI log trimming, Linux disk cleanup and per-leg overhead. Sample: #5622, #5795, #5819.
- **.NET 11 track (open drafts)** -- two open drafts carry the .NET 11 work: the umbrella PR adds .NET 11 support and drops .NET 8 and 9 (supported set net462, netstandard2.0, net10.0, net11.0), and a stage-1 draft raises C# to 15 and enables runtime async on net11.0 (base feature/net11-support). Neither is for merge before .NET 11 RTM. Listed as a track rather than a recurring cluster, since only two items exist. Sample: #5942, #5944.

## Resolved themes

- **Release preparation and versioning** -- coordinated dependency updates, PublicAPI baselines, analyzer-rule enforcement and version bumps for 6.3.0 and the 6.4.0 bump. Sample: #5533, #5534, #5536.
- **Build failure quick-fix cycles** -- transient master breakage fixed quickly (build errors, unbreak-build PRs, baselines reset before retried attempts, Release-mode analyzer errors in test projects). Sample: #5491, #5537, #5637, #5615, #5572.
- **Analyzer gating to Release builds** -- IDE analyzers, ReportAnalyzer and xml-doc generation gated to Release for faster Debug/Testing builds; deferred Meziantou rules resolved. Sample: #5516, #5573.
- **CS2012 double-build race** -- generator and LinqToDB pre-built before the solution to avoid the CS2012 race during build and pack. Sample: #5858, #5876.
- **Packaging and NuGet source hygiene** -- LINQPad driver packed under net8.0 for macOS/Linux, scaffold package Redist references, tolerance for an over-quota Azure Artifacts feed, and removal of an unusable NuGet source. NuGet audit restore failures fixed by suppressing GHSA-334f-vvp4-7g6p and pinning System.Security.Cryptography.Pkcs in test projects and linq2db.cli (#6043); the global suppression was later dropped by raising the SignalR.Client floor (#6095). The LINQPad Pack project no longer builds the driver chain twice (#6030). Sample: #5565, #5571, #5807, #5835, #6043, #6030.
- **Test projects on Microsoft.Testing.Platform** -- NUnit test projects migrated from VSTest to MTP, with a live test-progress heartbeat and a PublishSingleFile smoke test scoped to build/default. The heartbeat reports the filtered test count as total (#6098). Sample: #5612, #5610, #5607.
- **Baselines push and stacked-PR baselines** -- CI pushes regenerated SQL baselines to linq2db.baselines and must cope with concurrent pushes. Push retries back off on server-side HTTP 5xx and transport failures (#6004), and a stacked PR now bases its baselines branch on the nearest open ancestor's baselines branch, so a child no longer repeats its parent's baseline changes (#6006). Earlier fixes: #5715, #5859, #5878, #5917. Sample: #6004, #6006.

## Active discussions

None currently open.

## Stats

- Open issues: 0
- Closed issues: 0
- Open PRs: 3
- Total PRs: 56
- Discussions: 0
- Last fetched: 2026-10-21

<details><summary>Coverage</summary>

- Index entries scanned: 56 (0 issues + 56 PRs + 0 discussions)
- Themes extracted: 3 open, 7 resolved
- Not themed: #5633, #2631, #2693 (closed drafts); #5673 (open) and #5688 (closed), query-engine PRs carrying area BUILD in the index, a reclassification question for the index rather than a theme
- Updated this run but tagged to other areas and not themed here: #6054, #6061 (TESTS-INFRA), #6016 (AGENTS-INFRA), #6010 (REMOTE)
</details>
