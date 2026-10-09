---
area: INFRA
kind: issues
sources: [gh-issues, gh-prs, gh-discussions]
confidence: medium
last_verified: 2026-10-10
last_verified_sha: 05150894e
---

# INFRA -- GitHub themes

## Open themes

- **Unclustered open items** -- no open cluster reaches the 3-item threshold. Open issues: #5883 (CI: Roslyn analyzers disabled with `with_analyzers: false` after its stated blocker merged), #5903 (adopt MA0217 static lambdas across Source/, 2918 sites), #5890 (CI: unguarded setup steps run in test jobs whose matrix selects no leg), #5812 (declare `IInfrastructure<IServiceProvider>` on `IDataContext`; labelled infrastructure but reads as compatibility work), #3266 (CompiledQuery with async update; area classification looks off, labels are async and compiled-query). Open discussion: #5891 (see Active discussions).

## Resolved themes

- **nuget packaging** -- 12 closed issues share this keyword: #1156, #1175, #1183, #1251, #1254, #1297, #1342, #1401, #1414, #3335, #3575, #2001. Resolved patterns: package publishing workflow (#1248, #1251, #1297), multi-target package support (#1156), package metadata and readme updates (#1414, #3335), dependency version bumps (#1342), symbol packages (#599), AspNet package on .NET 5 (#3575). Recent: #5731 added third-party license notices to the linq2db.cli tool package (closed 2026-09-03); #4155 rename of the linq2db.AspNet package (closed 2024-05-11).

- **ci infrastructure** -- 8 closed issues cluster around CI/testing automation: #1104, #1121, #1246, #1260, #1359, #1488, #2858, #3020. Patterns: image deprecation / OS migration (#3020; PR #3456 removed the win2016 image ahead of its 2022-03-15 retirement), database provider coverage expansion (#1121, #1488, #2858; PR #1872 for Azure DevOps DB2/Informix/SAP HANA), test result tracking (#1104, #1246), dependency upgrades affecting CI-facing packages (#1260; PR #2193 bumped dependencies).

- **target framework / runtime support** -- 5 closed issues: #1533, #3935, #3936, #3937, #3358. Patterns: legacy TFM deprecation (#1533 netstandard 1.6; #3935 .NET Core 3.1; #3936 .NET 5.0; #3937 .NET Framework 4.5/4.6.1 in favour of 4.6.2), modern target addition (#3358, net6 / C# 10).

- **build infrastructure** -- 3 closed issues and 1 PR: #1595, #2001, #2002, PR #4116 (update local build and test, merged 2023-06-08). Patterns: T4 template discovery / generation (#2002), build script maintenance (#1595), T4 package version alignment (#2001).

- **test harness and baselines** -- 6 items share test-harness keywords (tests, baselines, ActiveIssue): #1378 and PR #1411 (ActiveIssue filtering not applied to DataSources-injected tests, fixed 2018-12-19), PR #1552 (test fixes, 2019-01-23), #5513 (remote-mode SQL trace dropped scalar IQueryable aggregate SQL, causing spurious .sql.other mismatches on Oracle; closed 2026-06-01, no linked PR in index), PR #5653 (per-invocation identity merge fixtures instead of shared static, merged 2026-06-25), PR #5662 (self-heal of the baselines branch so test-job restarts work, merged 2026-06-27).

- **Unclustered closed items** -- single items with no recurring keyword: PR #5670 (unify agent instructions under .agents/, merged 2026-07-06), PR #5672 (drop unenforced .editorconfig charset rule, merged 2026-07-03), PR #5676 (remove dead Sql.Extension window-function templates; area looks off), PR #5667 (enum-vs-null comparison fix; area looks off), PR #5489 (PublishSingleFile deployment support, merged 2026-06-11), #4141 (bug, wrong docs link on GitHub, closed 2025-12-15), PR #4005 (metrics, merged 2024-01-23).

## Active discussions

- [NullReferenceException in AsyncEnumeratorAsyncWrapper.DisposeAsync() when MoveNextAsync() is not called](https://github.com/linq2db/linq2db/discussions/5891) -- [Q&A] Reports NullReferenceException in DisposeAsync when MoveNextAsync() is never called; asks whether this is a bug or an expected consumer-side workaround. Open, last updated 2026-09-15.

## Stats

- Open issues: 5
- Closed issues: 34
- Open PRs: 0
- Total PRs: 14
- Discussions: 1
- Last fetched: 2026-10-09

<details><summary>Coverage</summary>

- Index entries scanned: 54 (39 issues + 14 PRs + 1 discussion)
- Themes extracted: 5 (plus unclustered open and closed items)
</details>
