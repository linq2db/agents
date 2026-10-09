---
area: FSHARP
kind: issues
sources: [gh-issues, gh-prs, gh-discussions]
confidence: medium
last_verified: 2026-10-10
last_verified_sha: 05150894edc2511f0dd0bc7829b2a309cec36ec9
---

# FSHARP -- GitHub themes

## Open themes
- No clustered open themes. One open FSHARP-area item: draft PR #5707 (F# data-model code generation for the CLI scaffolder, tracking #1553).

## Resolved themes
- **F# option types (Some / option / voption)** -- Recurring failures and support for F# option wrapping. Cited: #3670 (Some in Where/Join throws, closed 2022), #194 (option type tests, closed 2016), #5624 (automatic F# 'T option type mapping, merged 2026-07-04), #5704 (option/voption members translated in query predicates, merged 2026-09-08).
- **F# record types and record update semantics** -- Record types were not queryable early on and updates over records needed work. Cited: #178 (record types cannot be queried, closed 2015), #4132 (insert/update API with lambdas, closed 2025-12-01), #5627 (record `with` update sets only changed columns, merged 2026-06-27).
- **F# predicate and join translation** -- Lambda and predicate shapes in F# queries fail in the expression parser or join translation. Cited: #2678 (select behaviour in F#, closed 2021), #3743 (InvalidOperationException from predicate parser, closed 2022), #5701 (captured-lambda join predicates, merged 2026-08-29).
- **F# packaging and FSharp.Core compatibility** -- Extension wiring and FSharp.Core version drift. Cited: #4851 (UseFSharp() not usable as an extension method, closed 2025-03-01), #5430 (FSharp.Core 10.1.x compatibility, merged 2026-03-20), #5743 (analyzer delivery via linq2db.FSharp package, merged 2026-08-05).

## Active discussions
- No active discussions.

## Stats
- Open issues: 0
- Closed issues: 6
- Open PRs: 1
- Total PRs: 9
- Discussions: 0
- Last fetched: 2026-10-09 (index cutoff)

<details><summary>Coverage</summary>

- Index entries scanned: 15 FSHARP-area entries (6 issues + 9 PRs + 0 discussions)
- Themes extracted: 5 (1 open, 4 resolved)
- Not clustered: PR #2487 (test framework bump, FSHARP-tagged but no F# theme)
- Carry-over: prior file had no open-theme citations, so none were dropped
</details>
