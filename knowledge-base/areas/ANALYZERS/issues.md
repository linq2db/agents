---
area: ANALYZERS
kind: issues
sources: [gh-issues, gh-prs, gh-discussions]
confidence: medium
last_verified: 2026-10-10
last_verified_sha: 05150894edc2511f0dd0bc7829b2a309cec36ec9
---

# ANALYZERS -- GitHub themes

## Open themes
- **No open user-facing analyzer work** -- As of the index snapshot (latest indexed item 2026-09-21) no open issue or PR is classified to ANALYZERS. Known follow-ups are wiki-level limits, not tracked issues: L2DB1002 reads the unit only from the member attribute (no mapping-schema or IMetadataReader routes), and L2DB1001 withholds its code fix on return-type mismatch unless `apply_fix_on_return_type_mismatch` is set.
- **Boundary: repo-internal analyzer rules (not ANALYZERS)** -- #5883 (CI runs with `with_analyzers: false`), #5945 (Examples solution fails in Release), #5903 (adopt MA0217 across Source), #5922 (MapMember shadows member-translator registration, internal analyzer proposed), #5951 (internal analyzer: build steps must use the source MappingSchema), #5814 (internal analyzer for unsatisfiable ProjectFlags, closed; implemented by #5877). These target the internal rule host (Source/CodeGenerators, LINQ2DB0001) or build config and belong to INFRA or LINQ. Listed for awareness; not counted in Stats.

## Resolved themes
- **Shipping the rules to consumers** -- PR #5703 created `Source/LinqToDB.Analyzers` and `Source/LinqToDB.Analyzers.CodeFixes` with the first rule (first named LINQ2DB1001). PR #5720 moved delivery to a separate `linq2db.Analyzers` package that linq2db depends on (EFCore / EFCore.Analyzers shape). PR #5770 added the `LinqToDB.csproj` ProjectReference to CodeFixes. PR #5743 (6.4.0 release blocker, "Restore analyzer delivery through the linq2db.FSharp package") restored delivery for the F# package. All merged; the delivery invariant is asserted by `Build/Azure/scripts/verify-analyzer-delivery.ps1` on packed nuspecs.
- **Legacy window API migration (L2DB1001)** -- Introduced by #5703. Flags `Sql.Ext` analytic chains containing `.Over()` and offers a code fix rewriting them to `Sql.Window` while preserving comments and formatting. Fix covers ranking, aggregates, Lead/Lag, value functions, Oracle KEEP and more; shapes with no `Sql.Window` equivalent are reported without a fix. Reference: wiki L2DB1001. No separate GH issue beyond #5703.
- **Server-side-only contract (L2DB1003 / L2DB1004)** -- Issue #5788 (closed) noted that nothing checked a server-side-only stub's marker, so a missed marker surfaced as a runtime `ServerSideOnlyException` in user code. PR #5870 (merged 2026-09-08) added the rules: L2DB1003 (declare a server-side-only stub, or implement it; option `unmarked_stub_exception_types`) and L2DB1004 (a server-side-only stub should throw `ServerSideOnlyException`; option `allowed_exception_types`). Auto-memory records a dead-end titled "#5870 ServerSideOnly markers inert"; not re-verified here.
- **Duration unit mismatch (L2DB1002)** -- Issue #5779 (closed) reported that `==` between a `[Duration(DurationUnit.Second)]` member and a constant such as `TimeSpan.FromSeconds(1.5)` silently returns no rows. PR #5873 (merged 2026-09-08) added L2DB1002. No code fix by design, since the intended value cannot be inferred. Known limits: member-attribute-only unit read; fires inside any expression tree, so it is wrong for other LINQ providers or in-memory `Compile()`.

## Active discussions
- None. No entry in discussions-index.json matched analyzer keywords.

## Stats
- Open issues: 0
- Closed issues: 2 (#5779, #5788)
- Open PRs: 0
- Total PRs: 6 (#5703, #5720, #5743, #5770, #5870, #5873)
- Discussions: 0
- Last fetched: not recorded in the indexes (latest indexed item 2026-09-21)

<details><summary>Coverage</summary>

- Index entries scanned: 5957 (3079 issues + 2582 PRs + 296 discussions)
- Keyword matches reviewed: 43 lines (8 user-facing items; boundary and unrelated matches not enumerated individually)
- Themes extracted: 4 resolved, 0 open user-facing, 1 boundary note
</details>
