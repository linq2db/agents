---
area: INFRA
kind: issues
sources: [gh-issues, gh-prs, gh-discussions]
confidence: medium
last_verified: 2026-11-11
last_verified_sha: f90c5bcfb86d88db436a6494f0640c4c43dd691f
---

# INFRA -- GitHub themes

## Open themes

- **netstandard2.0 build on modern runtimes** -- the netstandard2.0 asset of linq2db behaves differently from the net8+ build when a modern runtime loads it. `string.TrimStart()` / `TrimEnd()` without arguments, or with char overloads, do not translate (#6075 issue, draft PR #6082). The netstandard2.0 build probes only the Sap.Data.Hana.Core.v2.1 client, so the .NET 8 SAP HANA client is not found (#6076 issue, draft PR #6083). C# 14 `span.Contains` inside an expression tree is not recognised (draft PR #6074). Five open items, three with draft fixes in flight.

- **Unclustered open items** -- no other open cluster reaches the 3-item threshold. Open issues: #5812 (declare `IInfrastructure<IServiceProvider>` on `IDataContext`; labelled infrastructure but reads as compatibility work), #3266 (CompiledQuery with async update; area classification looks off). Open issue #6267 (documentation site is published by pushing built output to linq2db/linq2db.github.io with an SSH deploy key; evaluating GitHub Pages Actions publishing; tagged DOCS, kept here as CI/publishing infrastructure). Open discussion: #5891 (see Active discussions).

## Resolved themes

- **nuget packaging** -- 12 closed issues share this keyword: #1156, #1175, #1183, #1251, #1254, #1297, #1342, #1401, #1414, #3335, #3575, #2001. Resolved patterns: package publishing workflow (#1248, #1251, #1297), multi-target package support (#1156), package metadata and readme updates (#1414, #3335), dependency version bumps (#1342), symbol packages (#599), AspNet package on .NET 5 (#3575). Recent: #5731 added third-party license notices to the linq2db.cli tool package (closed 2026-09-03); #4155 rename of the linq2db.AspNet package (closed 2024-05-11). 2026 sourcing changes: #5861 (SQL Server Compact taken from its NuGet package, Redist/SqlCe retired; closed 2026-10-27 via PR #6163, merged 2026-10-27); #5862 (SAP HANA provider taken from SAP's NuGet packages, Redist/SapHana shrunk; closed 2026-10-28 via PR #6162, merged 2026-10-28). NuGet audit: PR #6043 fixed advisory failures on restore (merged 2026-10-14); PR #6295 pinned legacy SignalR transitives that audit flagged (merged 2026-11-11).

- **ci infrastructure** -- 8 closed issues cluster around CI/testing automation: #1104, #1121, #1246, #1260, #1359, #1488, #2858, #3020. Patterns: image deprecation / OS migration (#3020; PR #3456 removed the win2016 image ahead of its 2022-03-15 retirement), database provider coverage expansion (#1121, #1488, #2858; PR #1872 for Azure DevOps DB2/Informix/SAP HANA), test result tracking (#1104, #1246), dependency upgrades affecting CI-facing packages (#1260; PR #2193 bumped dependencies). Recent (Sep-Nov 2026): analyzers re-enabled once their blocker merged (#5883 and #6118 closed 2026-10-24; PR #6130 re-enables Roslyn analyzers on PR and master CI, merged 2026-10-24); #5903 (adopt MA0217 static lambdas across Source/) closed 2026-10-24 with no linked PR in the index; Examples solution Release build fixed (#5945 closed 2026-10-24; PR #6127 merged 2026-10-24); Oracle legs moved to GitHub Actions (PR #5950 merged 2026-09-21; #5888 pinned NUnit parallelism, closed 2026-10-24); test jobs skip unguarded setup steps when their matrix selects no leg (#5890 closed 2026-10-25 via PR #6132, merged 2026-10-25); release-PR provider matrix moved to GitHub Actions (PR #6128 merged 2026-10-26); Azure Pipelines stops auto-cancelling in-flight PR runs when a draft is marked ready (PR #6288 merged 2026-11-09).

- **target framework / runtime support** -- 5 closed issues: #1533, #3935, #3936, #3937, #3358. Patterns: legacy TFM deprecation (#1533 netstandard 1.6; #3935 .NET Core 3.1; #3936 .NET 5.0; #3937 .NET Framework 4.5/4.6.1 in favour of 4.6.2), modern target addition (#3358, net6 / C# 10). Netstandard2.0 build issues opened in 2026 are tracked under the open theme above.

- **netstandard2.0 build, Npgsql 10 date types** -- #6077 (closed 2026-11-10) and PR #6092 (merged 2026-11-10): Npgsql 10 returns DateOnly for date, TimeOnly for time and NpgsqlRange<DateOnly> for daterange, and the netstandard2.0 build could not read them into DateTime / TimeSpan / NpgsqlRange<DateTime>. The net8+ build was already correct.

- **build infrastructure** -- 3 closed issues and 1 PR: #1595, #2001, #2002, PR #4116 (update local build and test, merged 2023-06-08). Patterns: T4 template discovery / generation (#2002), build script maintenance (#1595), T4 package version alignment (#2001).

- **test harness and baselines** -- 6 items share test-harness keywords (tests, baselines, ActiveIssue): #1378 and PR #1411 (ActiveIssue filtering not applied to DataSources-injected tests, fixed 2018-12-19), PR #1552 (test fixes, 2019-01-23), #5513 (remote-mode SQL trace dropped scalar IQueryable aggregate SQL, causing spurious .sql.other mismatches on Oracle; closed 2026-06-01, no linked PR in index), PR #5653 (per-invocation identity merge fixtures instead of shared static, merged 2026-06-25), PR #5662 (self-heal of the baselines branch so test-job restarts work, merged 2026-06-27). Recent baselines-pipeline fixes: PR #6222 leases the baselines-branch rebase push so it cannot delete concurrent leg commits (merged 2026-10-31); PR #6290 keeps a failed baselines-PR retarget non-fatal (merged 2026-11-10); PR #6291 resolves baselines rebase conflicts to the base branch's side (merged 2026-11-10).

- **Unclustered closed items** -- single items with no recurring keyword: PR #5670 (unify agent instructions under .agents/, merged 2026-07-06), PR #5672 (drop unenforced .editorconfig charset rule, merged 2026-07-03), PR #5676 (remove dead Sql.Extension window-function templates; area looks off), PR #5667 (enum-vs-null comparison fix; area looks off), PR #5489 (PublishSingleFile deployment support, merged 2026-06-11), #4141 (bug, wrong docs link on GitHub, closed 2025-12-15), PR #4005 (metrics, merged 2024-01-23). Reflection lookups: #4314 (review reflection code for BindingFlags.ExactBinding; closed 2026-11-04 via PR #6155, merged 2026-11-04, which binds Type[] lookups only to Expression-compatible overloads).

## Active discussions

- [NullReferenceException in AsyncEnumeratorAsyncWrapper.DisposeAsync() when MoveNextAsync() is not called](https://github.com/linq2db/linq2db/discussions/5891) -- [Q&A] Reports NullReferenceException in DisposeAsync when MoveNextAsync() is never called; asks whether this is a bug or an expected consumer-side workaround. Open, last updated 2026-09-15.

## Stats

- Open issues: 2
- Closed issues: 35
- Open PRs: 0
- Total PRs: 14
- Discussions: 1
- Last fetched: 2026-11-11

<details><summary>Coverage</summary>

- Index entries scanned: 52 tagged INFRA (37 issues + 14 PRs + 1 discussion); keyword and path scan over 6240 entries (3245 issues + 2699 PRs + 296 discussions) for untagged items whose content belongs here
- Themes extracted: 7 (1 open, 6 resolved), plus unclustered open and closed items
</details>
