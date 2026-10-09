---
area: PROV-DUCKDB
kind: tech-debt
sources: [code, gh-issues]
confidence: low
last_verified: 2026-10-10
last_verified_sha: 05150894edc2511f0dd0bc7829b2a309cec36ec9
---

# PROV-DUCKDB -- Tech debt

## Severity distribution

| Severity | Count |
|---|---|
| (none detected) | 0 |

## By category

No detected-issues entries (`detected-issues/index.json`) reference this area. Debt below is taken from the area's INDEX.md "Known issues / debt" section and is not scored.

## Top issues (up to 20)

No `DI-*` entries for PROV-DUCKDB.

## Known design debt (from INDEX.md)

- **TRUNCATE does not reset sequences** (`DuckDBSqlBuilder.cs:345-388`): workaround creates a replacement sequence and re-points the column DEFAULT, orphaning the old sequence. Needs DuckDB ALTER SEQUENCE RESTART.
- **Untyped parameters need per-site casts**: `TuneParameters` operand casts, `GetParameterCastType`, `TypeParameter`, DateTime2 cast in `LowerTemporalArithmetic`. No central parameter typing, so new functions/operators taking parameter operands may need the same treatment.
- **No version-dialect split**: `TranslateNewGuid7Method` emits `uuidv7()` unconditionally (needs DuckDB 1.3.0+).
- **`ParseBitString`** (`DuckDBDataProvider.cs`) is coupled to the DuckDB.NET bitstring wire format.
- **No stored procedure support**: `GetProcedures` returns empty.
- **No net462 TFM in DuckDB.NET**: T4 NuGet package and LINQPad NuGet driver unsupported.

## See also

- [INDEX.md](INDEX.md) -- area overview
- [issues.md](issues.md) -- GitHub themes
- [patterns.md](patterns.md) -- area patterns

## Open GH bugs in this area: 1

- [#5977 DateTime parameter mixed with Sql.CurrentTimestamp shifts stored value by session UTC offset](https://github.com/linq2db/linq2db/issues/5977)

<details><summary>Coverage</summary>

- Aggregated from `detected-issues/index.json` (0 entries for PROV-DUCKDB), areas/PROV-DUCKDB/INDEX.md and issues.md.
- No source files re-read in this run.

</details>
