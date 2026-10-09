---
area: ANALYZERS
kind: patterns
sources: [code]
confidence: low
last_verified: 2026-10-10
last_verified_sha: 05150894edc2511f0dd0bc7829b2a309cec36ec9
---

# ANALYZERS -- Patterns

## Applicable conventions

- No conventions cite files in this area. See [conventions/](../../conventions/) for the full catalog.

## Recurring code patterns (from INDEX.md)

- **Name-only coupling to linq2db.** The package has no linq2db dependency. Each rule resolves types via `GetTypeByMetadataName` and stays silent when absent. Tests prove this with `VerifyWithoutLinqToDBAsync`.
- **Analyzer/code-fix project split** (RS1038): analyzers without Workspaces, fixes in the packable `linq2db.Analyzers` project with the analyzer project as `PrivateAssets=all`. Shared settings in `Source/Analyzers.Common.props`.
- **Diagnostic carries the remedy.** L2DB1003/1004 put `Properties["remedy"]` and `AdditionalLocations` on the diagnostic, and the code fix reads them instead of re-deriving.
- **Custom FixAllProvider** instead of `BatchFixer` (`WindowChainFixAllProvider`, `ContractFixAllProvider`), because batch fixing drops edits for adjacent diagnostics.
- **Degrade to silence** on unrecognised shapes (L2DB1002 folding, L2DB1001 rewrite bails).
- **`.editorconfig` options** under `linq2db.l2dbNNNN.*` for tuning rules.
- **Shared detection core** linked by `Compile Include` into CODEGEN so shipped and internal rules decide identically.
- **Opt-out** via MSBuild `EnableLinqToDBAnalyzers=false` and target `LinqToDBRemoveAnalyzers`.

## Recorded decisions affecting this area

- No area-scoped recorded decisions. See [decisions.md](decisions.md) if present.

## See also

- [INDEX.md](INDEX.md) -- area architecture
- [tech-debt.md](tech-debt.md) -- debt
- [CODEGEN](../CODEGEN/INDEX.md)

<details><summary>Coverage</summary>

- Aggregated from areas/ANALYZERS/INDEX.md, no source files read in this run.
</details>
