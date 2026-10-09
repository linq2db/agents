---
area: GLOBAL
kind: decision
sources: [git]
confidence: high
last_verified: 2026-10-09
last_verified_sha: 05150894edc2511f0dd0bc7829b2a309cec36ec9
---

# Ship user-facing analyzers as linq2db.Analyzers, delivered via a linq2db dependency

## Context
linq2db had only internal build-tooling analyzers. #5703 added the first user-facing Roslyn analyzer package (rule L2DB1001, legacy `Sql.Ext` window API to `Sql.Window`, with a code fix). #5720 then reworked how the rules reach consumers.

## Decision
#5703 created `Source/LinqToDB.Analyzers` (analyzer only, no Workspaces reference) and `Source/LinqToDB.Analyzers.CodeFixes` (packable), pinned to Roslyn 4.8.0. During #5720 the analyzers were first bundled into the `linq2db` package, then that was reverted: a packable `linq2db.Analyzers` project was restored and `linq2db` takes a plain package dependency on it (same shape as EFCore -> EFCore.Analyzers). Satellite packages leave `analyzers` out of PrivateAssets so the subtree keeps flowing. The diagnostic id was renamed LINQ2DB1001 -> L2DB1001, given its own `LinqToDB` category, and an MSBuild opt-out `EnableLinqToDBAnalyzers=false` was added.

## Why
The bundling was justified by "NuGet does not flow analyzers transitively"; the commit body records that this did not reproduce (measured on SDK 10.0.302: analyzers reach a consumer whose only reference is linq2db.Tools). The separate package keeps the migration rule installable against 6.1-6.3 and lets the code fix ship without a runtime release. Roslyn 4.8 is the Roslyn bundled with the lowest supported SDK (.NET 8). Category rename was free because the package had not shipped (pre-6.4.0).

## Consequences
- Rules are on by default for every linq2db consumer, opt-out via `EnableLinqToDBAnalyzers` or per-rule `.editorconfig` severity.
- `Build/Azure/scripts/verify-analyzer-delivery.ps1` asserts the delivery invariant on packed nuspecs in the nugets job.
- Code fix uses a custom `DocumentBasedFixAllProvider` instead of `BatchFixer` (Fix-All dropped clustered edits).
- `Tests/Tests.Analyzers` (net8.0) runs in CI via `with_analyzer_tests`.

## Sources
- Commit `d47896f` -- linq2db.Analyzers: new analyzer package + LINQ2DB1001 (MaceWindu, 2026-07-12)
- Commit `d5a9897` -- Ship the analyzers with linq2db via the linq2db.Analyzers package (MaceWindu, 2026-08-03)
- PR #5703, PR #5720
- File anchors: `Source/LinqToDB.Analyzers/`, `Source/LinqToDB.Analyzers.CodeFixes/`, `Source/Analyzers.Common.props`
