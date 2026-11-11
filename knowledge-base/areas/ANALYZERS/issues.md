---
area: ANALYZERS
kind: issues
sources: [gh-issues, gh-prs, gh-discussions]
confidence: medium
last_verified: 2026-11-11
last_verified_sha: f90c5bcfb86d88db436a6494f0640c4c43dd691f
---

# ANALYZERS -- GitHub themes

## Open themes
- **No open user-facing analyzer work** -- As of the index snapshot (latest indexed item 2026-11-10) no open issue is classified to ANALYZERS, and no open PR is user-facing analyzer work. Known follow-ups are wiki-level limits, not tracked issues: L2DB1002 reads the unit only from the member attribute (no mapping-schema or IMetadataReader routes), and L2DB1001 withholds its code fix on return-type mismatch unless `apply_fix_on_return_type_mismatch` is set.
- **Boundary: repo-internal analyzer rules (not user-facing)** -- The internal rule host (`Source/CodeGenerators`, LINQ2DB0001 onward) carries the repo-only rules. The index tags two open draft PRs as ANALYZERS: #6145 (adds LINQ2DB0010: build steps must read the source sequence's MappingSchema; fixes #5951) and #6151 (adds LINQ2DB0007-0009: a MapMember entry shadowing a member translator or attribute; fixes #5922). Issues #5922 and #5951 remain open (tagged EXPR-TRANS). #5814 (internal analyzer for unsatisfiable ProjectFlags) is closed and implemented by #5877. Listed for awareness; not counted in Stats.
- **Boundary: agent-skill documentation naming an analyzer code** -- PR #5376 (open, AGENTS-INFRA, updated 2026-11-10) ships an Agent Skill and names analyzer code L2DB2001 as a link target. Its subject is the skill, not analyzer behaviour; not counted here.

## Resolved themes
- **Shipping the rules to consumers** -- PR #5703 created `Source/LinqToDB.Analyzers` and `Source/LinqToDB.Analyzers.CodeFixes` with the first rule (first named LINQ2DB1001). PR #5720 moved delivery to a separate `linq2db.Analyzers` package that linq2db depends on (EFCore / EFCore.Analyzers shape). PR #5770 added the `LinqToDB.csproj` ProjectReference to CodeFixes. PR #5743 (6.4.0 release blocker, "Restore analyzer delivery through the linq2db.FSharp package") restored delivery for the F# package. All merged; the delivery invariant is asserted by `Build/Azure/scripts/verify-analyzer-delivery.ps1` on packed nuspecs.
- **Legacy window API migration (L2DB1001)** -- Introduced by #5703. Flags `Sql.Ext` analytic chains containing `.Over()` and offers a code fix rewriting them to `Sql.Window` while preserving comments and formatting. Fix covers ranking, aggregates, Lead/Lag, value functions, Oracle KEEP and more; shapes with no `Sql.Window` equivalent are reported without a fix. Reference: wiki L2DB1001. No separate GH issue beyond #5703.
- **Server-side-only contract (L2DB1003 / L2DB1004)** -- Issue #5788 (closed) noted that nothing checked a server-side-only stub's marker, so a missed marker surfaced as a runtime `ServerSideOnlyException` in user code. PR #5870 (merged 2026-09-08) added the rules: L2DB1003 (declare a server-side-only stub, or implement it; option `unmarked_stub_exception_types`) and L2DB1004 (a server-side-only stub should throw `ServerSideOnlyException`; option `allowed_exception_types`). Auto-memory records a dead-end titled "#5870 ServerSideOnly markers inert"; not re-verified here.
- **Duration unit mismatch (L2DB1002)** -- Issue #5779 (closed) reported that `==` between a `[Duration(DurationUnit.Second)]` member and a constant such as `TimeSpan.FromSeconds(1.5)` silently returns no rows. PR #5873 (merged 2026-09-08) added L2DB1002. No code fix by design, since the intended value cannot be inferred. Known limits: member-attribute-only unit read; fires inside any expression tree, so it is wrong for other LINQ providers or in-memory `Compile()`.
- **CI analyzer re-enable** -- Issue #5883 (closed, BUILD) reported that CI ran with `with_analyzers: false` after its stated blocker had cleared. PR #6130 (merged 2026-10-24) re-enabled Roslyn analyzers on PR and master CI. Before it, analyzer violations merged green and surfaced only at release prep (#6114: MA0008, NUnit4001). The blocker, dotnet/roslyn#80621, is in Visual Studio 2026 18.3 (Roslyn 5.3).

## Active discussions
- None. No entry in discussions-index.json matched analyzer keywords.

## Stats
- Open issues: 0 (user-facing; #5922 and #5951 are boundary, see above)
- Closed issues: 2 (#5779, #5788)
- Open PRs: 2 (#6145, #6151; both draft, internal-host rules, boundary)
- Total PRs: 7 (#5703, #5720, #5743, #5770, #5870, #5873, #6130)
- Discussions: 0
- Last fetched: not recorded in the indexes (latest indexed item 2026-11-10)

<details><summary>Coverage</summary>

- Index entries scanned: 6240 (3245 issues + 2699 PRs + 296 discussions)
- Keyword matches reviewed: title and body-keyword matches across the three indexes, every ANALYZERS-tagged entry (#6130, #6145, #6151, #5883, #5922, #5951 and others), and L2DB / LINQ2DB rule-code matches
- Themes extracted: 5 resolved, 0 open user-facing, 2 boundary notes
</details>
