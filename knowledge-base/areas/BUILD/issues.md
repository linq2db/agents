---
area: BUILD
kind: issues
sources: [gh-issues, gh-prs, gh-discussions]
confidence: high
last_verified: 2026-11-11
last_verified_sha: f90c5bcfb86d88db436a6494f0640c4c43dd691f
---

# BUILD -- GitHub themes

## Open themes

- **CI migration to GitHub Actions (ongoing)** -- the test matrix is moving from Azure Pipelines to GitHub Actions in increments: the database-free build and checks (#5836), matrix selection as data (#5848), the Linux provider legs and their parity with Azure (#5866, #5880), the docker-free Windows legs (#5898, #5899), and the PR-comment trigger that replaced the Azure dispatch job (#5869, #5871, #5872). Run status is reported on the PR as a commit status (#5875). Later follow-ups: the release-PR provider matrix moved to GitHub Actions (#6128), the Oracle legs moved with NUnit parallelism pinned for parity with Azure (#5888, #5950), setup steps skipped in a job whose matrix selects no leg (#6132), and Azure no longer auto-cancels in-flight PR runs (#6288). Azure-leg follow-ups: Docker Hub login restored (#6011), the x86 Access MDB leg split per provider (#6005), a macOS leg in the CLI tests job (#6017), and the ClickHouse leg moved to ClickHouse 26.9 (#5962). Sample: #5866, #5871, #5898, #6128.
- **Baselines capture and push races (ongoing)** -- SQL baselines are captured on every leg and pushed to linq2db.baselines, and the capture and push paths still race. Open: the schema-filter list is unsorted and two baseline-capture races remain (#5918). Recent fixes: the rebase push is leased so it cannot delete concurrent leg commits (#6222), a failed baselines-PR retarget is non-fatal (#6290), and rebase conflicts resolve to the base branch's side (#6291). Sample: #5918, #6222, #6291.
- **Parallel test execution and test-infra splits** -- the parallel test-execution work (#5614) was split into separate PRs covering shared test data, CI log trimming, Linux disk cleanup and per-leg overhead. Sample: #5622, #5795, #5819.
- **.NET 11 track (open drafts)** -- two open drafts carry the .NET 11 work: the umbrella PR adds .NET 11 support and drops .NET 8 and 9 (supported set net462, netstandard2.0, net10.0, net11.0), and a stage-1 draft raises C# to 15 and enables runtime async on net11.0 (base feature/net11-support). Neither is for merge before .NET 11 RTM. Both are now tagged GLOBAL in the index and remain open. Sample: #5942, #5944.
- **netstandard2.0 build parity with net10.0 (ongoing)** -- the netstandard2.0 asset lags the modern TFMs. TrimStart/TrimEnd with no argument or a char are not translated there (#6075, fix #6082), the SAP HANA build does not find the .NET 8 client (#6076, fix #6083), C# 14 span Contains is not recognised (#6074), and Npgsql 10 date/time types needed classic-type reads (#6077, fixed by #6092). Sample: #6075, #6076, #6074.
- **Documentation site build and deployment (open evaluation)** -- the docfx site moved into the repository (#6265) and its Source-side build warnings were cleared (#6264). Whether to move deployment to GitHub Pages' Actions publishing is still open (#6267). Sample: #6267.

## Resolved themes

- **Release preparation and versioning** -- coordinated dependency updates, PublicAPI baselines, analyzer-rule enforcement and version bumps for 6.3.0, 6.4.0, 6.5.1 and 6.6.0. Sample: #5533, #5536, #6114, #6125.
- **Build failure quick-fix cycles** -- transient master breakage fixed quickly (build errors, unbreak-build PRs, baselines reset before retried attempts, Release-mode analyzer errors in test projects, the Examples solution failing in Release, and a banned overload that broke the master Release build). Sample: #5491, #5537, #5637, #5615, #5572, #6127, #6251.
- **Analyzer gating to Release builds** -- IDE analyzers, ReportAnalyzer and xml-doc generation gated to Release for faster Debug/Testing builds; deferred Meziantou rules resolved. A stale `with_analyzers: false` in CI outlived its blocker and Roslyn analyzers were re-enabled (#5883, #6118, #6130), and MA0217 was adopted across Source/ (#5903). Sample: #5516, #5573, #6130.
- **CS2012 double-build race** -- generator and LinqToDB pre-built before the solution to avoid the CS2012 race during build and pack. Sample: #5858, #5876.
- **Packaging and NuGet source hygiene** -- LINQPad driver packed under net8.0 for macOS/Linux, scaffold package Redist references, tolerance for an over-quota Azure Artifacts feed, and removal of an unusable NuGet source. NuGet audit restore failures were fixed by suppressing GHSA-334f-vvp4-7g6p and pinning System.Security.Cryptography.Pkcs (#6043); the global suppression was dropped by raising the SignalR.Client floor (#6095), the legacy SignalR transitives that audit still flagged were pinned (#6295), and an Examples WebAssembly server package was moved to a patched version (#6248). The LINQPad Pack project no longer builds the driver chain twice (#6030). The MCP Registry prerelease publish workflow (#6278) and the OSS Scanner build image and threat model (#6287) were added. Sample: #5565, #5571, #5807, #5835, #6043, #6030, #6295.
- **Test projects on Microsoft.Testing.Platform** -- NUnit test projects migrated from VSTest to MTP, with a live test-progress heartbeat and a PublishSingleFile smoke test scoped to build/default. The heartbeat reports the filtered test count as total (#6098, issue #5964) and records the launching session (#6149). Sample: #5612, #5610, #5607.
- **Baselines push and stacked-PR baselines** -- CI pushes regenerated SQL baselines to linq2db.baselines and must cope with concurrent pushes. Push retries back off on server-side HTTP 5xx and transport failures (#6004), and a stacked PR bases its baselines branch on the nearest open ancestor's baselines branch, so a child no longer repeats its parent's baseline changes (#6006). Earlier fixes: #5715, #5859, #5878, #5917. Sample: #6004, #6006.

## Active discussions
None currently open.

## Stats
- Open issues: 4 (#5918, #6075, #6076, #6267; themed items only, no BUILD-tagged open issue)
- Closed issues: 8 (#5883, #5888, #5890, #5903, #5945, #5964, #6077, #6118; themed items only)
- Open PRs: 2 (#5942, #5944)
- Total PRs: 61 (all PRs tagged BUILD in the index)
- Discussions: 0
- Last fetched: 2026-11-11

<details><summary>Coverage</summary>

- Index entries scanned: 6,240 (3,245 issues + 2,699 PRs + 296 discussions); BUILD-tagged: 4 issues + 61 PRs; content-matched and themed: 37 items not tagged BUILD
- Themes extracted: 6 open, 7 resolved
- Not themed: #5673 (now closed and merged 2026-11-06; query-engine PR carrying area BUILD in the index, a reclassification question for the index rather than a theme), #5688 (closed), #5633, #2631, #2693 (closed drafts); #6124, #6129 (DO NOT MERGE verification PRs, dropped); #6145, #6151, #5922, #5951 (ANALYZERS area, analyzer work)
- Updated this run but tagged to other areas and not themed here: #6054 (PROV-MYSQL), #6061, #6010 (REMOTE), #6016 (AGENTS-INFRA), #6259, #5908, #5912 (TESTS-INFRA / TESTS-LINQ), #5763 (PROV-YDB, provider SDK bump)
</details>
