---
area: FSHARP
kind: issues
sources: [gh-issues, gh-prs, gh-discussions]
confidence: medium
last_verified: 2026-11-11
last_verified_sha: f90c5bcfb86d88db436a6494f0640c4c43dd691f
---

# FSHARP -- GitHub themes

## Open themes
- **F# data-model code generation for the CLI scaffolder** -- Generating F# records, a data context and a test harness for them from `dotnet linq2db scaffold`. Open items: #1553 (original request for F# record generation, still open; the scaffolder work tracks it), #5707 (draft PR `scaffold --target-language f#`, AST and code-generation path only; T4 stays C#-only), #6021 (code-generation test harness: predefined schema, generate, compile, execute, for C# and F#), #6037 (draft PR implementing that harness, based on #5707's branch). Related merged fix: #6026 (SQL Server procedure return value mapped as ReturnValue, not Output; #5707 notes the same fix covers the F# generator).
- **F# option values with value converters** -- An F# `option` column whose element type carries a value converter (a single-case union such as `UserId option`) breaks on the provider path. Open: #5886 (`.Value` comparison against an element literal passes the raw union instance to the provider; updated 2026-11-10). The storage-side sibling of the same converter path was closed on 2026-10-22 (#6106, fixed by #6107; see Resolved).
- **F# query-syntax joins (chained groupJoin)** -- `query { }` blocks that chain `groupJoin ... into g` blocks followed by `for x in g.DefaultIfEmpty()`. Open: #5790 (a correlated inner sequence in the second groupJoin fails to translate on every provider), #5794 (a trailing plain `join` after chained groupJoins turns the second DefaultIfEmpty into INNER JOIN, so unmatched rows vanish without an error). Both were filed 2026-08. The single-join fix that started this path is #1813 / #5701 (see Resolved).

## Resolved themes
- **F# option types (Some / option / voption)** -- Recurring failures and support for F# option wrapping. Cited: #3670 (Some in Where/Join throws, closed 2022), #194 (option type tests, closed 2016), #195 (original request for F# option column types, closed 2026-06-26), #4646 (F# int option with None stored as 0, closed 2026-07-04), #5624 (automatic F# 'T option type mapping, merged 2026-07-04; fixes #195 and #4646), #5704 (option/voption members translated in query predicates, merged 2026-09-08), #6106 (option and single-case union columns refused as divergent storage next to plain columns, closed 2026-10-22), #6107 (fix for #6106, merged 2026-10-22).
- **F# record types and record update semantics** -- Record types were not queryable early on and updates over records needed work. Cited: #178 (record types cannot be queried, closed 2015), #4132 (insert/update API with lambdas, closed 2025-12-01), #5598 (`{ record with ... }` update emitted every column including the PK, closed 2026-06-27), #5627 (record `with` update sets only changed columns, merged 2026-06-27), #6025 (records that declare a `static let` had their columns passed to the wrong constructor parameters; fixed, merged 2026-10-12).
- **F# predicate and join translation** -- Lambda and predicate shapes in F# queries fail in the expression parser or join translation. Cited: #2678 (select behaviour in F#, closed 2021), #3743 (InvalidOperationException from predicate parser, closed 2022), #1813 (LEFT JOIN in F#, closed 2026-08-29 by #5701), #5701 (captured-lambda join predicates, merged 2026-08-29).
- **F# packaging and FSharp.Core compatibility** -- Extension wiring and FSharp.Core version drift. Cited: #4851 (UseFSharp() not usable as an extension method, closed 2025-03-01), #5430 (FSharp.Core 10.1.x compatibility, merged 2026-03-20), #5743 (analyzer delivery via linq2db.FSharp package, merged 2026-08-05), #6191 (F# EF Core tests moved to EF10 with EntityFrameworkCore.FSharp 10.0.0, merged 2026-10-28).

## Active discussions
- No active discussions.

## Stats
- Open issues: 5
- Closed issues: 11
- Open PRs: 2
- Total PRs: 13
- Discussions: 0
- Last fetched: 2026-11-11

<details><summary>Coverage</summary>

- Index entries scanned: 19 prior and current FSHARP-tagged entries (issues and PRs), plus F#-titled or `area: fsharp`-labelled issues and PRs updated since 2026-10-21, checked by content
- Themes extracted: 7 (3 open, 4 resolved)
- Carry-over: all prior citations kept. The four prior open citations (#1553, #5707, #6021, #6037) are still open, so none moved to resolved. The prior resolved citations are unchanged.
- New citations: 10 (#5886, #5790, #5794, #195, #4646, #6106, #6107, #1813, #5598, #6191)
- Not cited: #2487 (test framework bump, FSHARP-tagged but no F# theme). #5675 (metadata reader schema awareness, carries `area: fsharp` label but no F# content in title). #1953 and #5428 (F#-titled but closed before the window and outside any theme). Pre-window F# issues and PRs without a theme are not added.
- Not cited: FSHARP-tagged index entries outside F# themes (the per-item area tag is lossy). Examples: #5680, #5667, #5727, #6095, #6109, #5426, #5485, #3754.
</details>
