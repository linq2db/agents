---
area: PROV-DUCKDB
kind: patterns
sources: [conventions, decisions, gh-themes]
confidence: low
last_verified: 2026-10-10
last_verified_sha: 05150894edc2511f0dd0bc7829b2a309cec36ec9
---

# PROV-DUCKDB -- Patterns

## Applicable conventions

- No conventions cite files in this area. See [conventions/](../../conventions/) for the full catalog.

## Recurring patterns in this area

- **Untyped-parameter casting**: DuckDB.NET parameters arrive untyped, so overload resolution needs explicit CASTs. Pattern: `DuckDBSqlBuilder.GetParameterCastType` supplies the type, `DuckDBSqlOptimizer.TuneParameters` applies `QueryHelper.EnsureParameterCast` on the binary-expression operand (not the shared parameter), and the convert visitor's `TypeParameter` handles `date_diff`. Open symptom: [#5977](https://github.com/linq2db/linq2db/issues/5977).
- **Function-call forms over bare keywords** for Now translation (`now()`, `current_localtimestamp()`), because ON CONFLICT DO UPDATE SET parses bare keywords as columns ([#5518](https://github.com/linq2db/linq2db/pull/5518)).
- **Capability hooks over visitor rewrites**: `ConcatStyle = Pipes` (#5504), `CanLowerIntervalDifference` / `CanLowerIntervalShift` / `TruncateDivide` (#5987), `CanWrapWindowOrderByConstant = false`.
- **Flag-driven translation**: nulls ordering follows `ProviderFlags.DefaultNullsOrdering`, window capabilities via `DuckDBWindowFunctionsMemberTranslator`.

## Recorded decisions affecting this area

- No area-scoped recorded decisions.

## See also

- [INDEX.md](INDEX.md) -- area architecture
- [issues.md](issues.md) -- GitHub themes
- [tech-debt.md](tech-debt.md) -- debt

<details><summary>Coverage</summary>

- Aggregated from areas/PROV-DUCKDB/INDEX.md and issues.md. No source files re-read.

</details>
