---
area: ANALYZERS
kind: tech-debt
sources: [code]
confidence: low
last_verified: 2026-10-10
last_verified_sha: 05150894edc2511f0dd0bc7829b2a309cec36ec9
---

# ANALYZERS -- Tech debt

## No detected issues

This area has no entries in [detected-issues/index.json](../../detected-issues/index.json) as of 2026-10-10 (new area, the issue detector has not yet run over it). The items below come from [INDEX.md](INDEX.md) "Known issues / debt", not from the detector.

## Debt carried from INDEX.md

- L2DB1002 (`Source/LinqToDB.Analyzers/DurationComparisonAnalyzer.cs`) sees only attribute-declared units. Units set via `HasDuration` or a mapping schema are invisible, and a derived attribute assigning `Configuration` in its constructor body is undetectable (documented in source).
- L2DB1001 code fix (`LegacyWindowChainRewriter`) declines many shapes (`Filter`, `ListAgg`, unknown functions, bare `Ext` root), so the diagnostic stays without a fix.
- `ServerSideOnlyContract.cs` is pinned to Roslyn 4.8 (no collection expressions, no nested helper types) because it is linked into `Source/CodeGenerators`, which uses 5.6.0.
- `LegacyWindowChainRewriter` mirrors the internal `LegacyMemberConverterBase.TryConvertAnalyticFunction`, and the duration unit table mirrors `SqlIntervalUnits.TryGetTicksRatio`: duplicated logic that can drift.
- Test fixtures in `Tests/Tests.Analyzers` were not read during the index build (Tier-2 coverage 6/11), so test-obligation claims are inferred.

## See also

- [INDEX.md](INDEX.md) -- area overview
- [patterns.md](patterns.md) -- area patterns
- [CODEGEN](../CODEGEN/INDEX.md) -- internal LINQ2DB0xxx twins

<details><summary>Coverage</summary>

- Aggregated from areas/ANALYZERS/INDEX.md, no source files read in this run.
- detected-issues: 0 entries for ANALYZERS.
</details>
