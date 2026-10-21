---
area: FSHARP
kind: issues
sources: [gh-issues, gh-prs, gh-discussions]
confidence: medium
last_verified: 2026-10-21
last_verified_sha: 89b5ce16278728b9936ba374827fea002c76e962
---

# FSHARP -- GitHub themes

## Open themes
- **F# data-model code generation for the CLI scaffolder** -- Generating F# records, a data context and a test harness for them from `dotnet linq2db scaffold`. Open items: #1553 (original request for F# record generation, still open; the scaffolder work tracks it), #5707 (draft PR `scaffold --target-language f#`, AST and code-generation path only; T4 stays C#-only), #6021 (code-generation test harness: predefined schema, generate, compile, execute, for C# and F#), #6037 (draft PR implementing that harness, based on #5707's branch). Related merged fix: #6026 (SQL Server procedure return value mapped as ReturnValue, not Output; #5707 notes the same fix covers the F# generator).

## Resolved themes
- **F# option types (Some / option / voption)** -- Recurring failures and support for F# option wrapping. Cited: #3670 (Some in Where/Join throws, closed 2022), #194 (option type tests, closed 2016), #5624 (automatic F# 'T option type mapping, merged 2026-07-04), #5704 (option/voption members translated in query predicates, merged 2026-09-08).
- **F# record types and record update semantics** -- Record types were not queryable early on and updates over records needed work. Cited: #178 (record types cannot be queried, closed 2015), #4132 (insert/update API with lambdas, closed 2025-12-01), #5627 (record `with` update sets only changed columns, merged 2026-06-27), #6025 (records that declare a `static let` had their columns passed to the wrong constructor parameters; fixed, merged 2026-10-12).
- **F# predicate and join translation** -- Lambda and predicate shapes in F# queries fail in the expression parser or join translation. Cited: #2678 (select behaviour in F#, closed 2021), #3743 (InvalidOperationException from predicate parser, closed 2022), #5701 (captured-lambda join predicates, merged 2026-08-29).
- **F# packaging and FSharp.Core compatibility** -- Extension wiring and FSharp.Core version drift. Cited: #4851 (UseFSharp() not usable as an extension method, closed 2025-03-01), #5430 (FSharp.Core 10.1.x compatibility, merged 2026-03-20), #5743 (analyzer delivery via linq2db.FSharp package, merged 2026-08-05).

## Active discussions
- No active discussions.

## Stats
- Open issues: 2
- Closed issues: 6
- Open PRs: 2
- Total PRs: 12
- Discussions: 0
- Last fetched: 2026-10-21 (issues cursor 2026-10-21T20:10:53Z)

<details><summary>Coverage</summary>

- Index entries scanned: 15 prior FSHARP-area entries carried over, plus 6 F#-relevant fetched items merged in this run (#1553, #6021 issues; #5707, #6025, #6026, #6037 PRs)
- Themes extracted: 5 (1 open, 4 resolved)
- Not clustered: PR #2487 (test framework bump, FSHARP-tagged but no F# theme)
- Carry-over: all 15 prior citations kept; none closed-and-dropped. The prior "no clustered open themes" line is replaced by the code-generation theme, which keeps #5707
- Not cited: FSHARP-tagged index entries outside F# themes (the per-item area tag is lossy)
</details>
