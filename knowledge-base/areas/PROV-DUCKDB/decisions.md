---
area: PROV-DUCKDB
kind: decisions
sources: [gh-prs, gh-issues, history-decisions]
confidence: medium
last_verified: 2026-10-21
last_verified_sha: 89b5ce16278728b9936ba374827fea002c76e962
---

# PROV-DUCKDB -- Decisions

## Recorded decisions

- [DuckDB data provider added (PR #5451)](../../history/decisions/2026-duckdb-provider.md) -- sequence-based identity instead of GENERATED AS IDENTITY, Appender-based ProviderSpecific bulk copy with MultipleRows fallback, `_reset` sequence for truncate-with-identity-reset, `DuckDBOptions.BulkCopyType` defaults to ProviderSpecific.
- ["Now" translation split into four virtuals (PR #5467)](../../history/decisions/2026-now-translation-split.md) -- shared `DateFunctionsTranslatorBase` change that the DuckDB Now-translation fix in #5518 depends on.

## Decision-flavored PRs

- None met the decision-flavored test. The DuckDB PRs carry no `breaking` label, the indexed bodies show no `## Decision` section, and files-changed counts are not in the index, so the more-than-30-files test could not be applied. Listed for reference:
  - [#5451](https://github.com/linq2db/linq2db/pull/5451) Add DuckDB data provider (merged 2026-05-10). Covered by the recorded decision above.
  - [#5518](https://github.com/linq2db/linq2db/pull/5518) Fix DuckDB date translation after the #5467 / #5451 merge race (merged 2026-05-10).
  - [#5744](https://github.com/linq2db/linq2db/pull/5744) Fix the DuckDB x86 native guard catching the wrong exception type (merged 2026-08-05). Release blocker for 6.4.0.

## Open items without a recorded decision

- [#5977](https://github.com/linq2db/linq2db/issues/5977) -- DuckDB `Sql.CurrentTimestamp` in a conditional shifts a `DateTime` parameter by the session UTC offset. Open, no decision recorded yet.
- [#6084](https://github.com/linq2db/linq2db/issues/6084) -- DuckDB `TIMETZ` to `TimeSpan` reader is missing on the netstandard2.0 asset (registered only under `SUPPORTS_DATEONLY`). Open, no decision recorded yet.

## Cross-area DuckDB items (not counted in this area)

- [#5698](https://github.com/linq2db/linq2db/pull/5698) -- in-memory DuckDB and SQLite test databases (PROV-SQLITE).
- [#5710](https://github.com/linq2db/linq2db/pull/5710) -- DuckDB in-memory preload for local / filtered runs (PROV-SQLSERVER tag; merged 2026-07-13).
- [#5630](https://github.com/linq2db/linq2db/pull/5630) -- PostgreSQL / DuckDB DISTINCT ON via DistinctBy.
- [#5965](https://github.com/linq2db/linq2db/issues/5965) -- sub-day date functions on the DuckDB server clock (SQL-AST).
- [#6072](https://github.com/linq2db/linq2db/issues/6072) -- integer `Sql.Degrees` overloads keep the fraction on DuckDB and SQLite (PROV-SQLITE tag).

## See also (GLOBAL decisions)

- [Interval translation](../../history/decisions/2026-timespan-interval-translation.md) -- the decision text mentions DuckDB INTERVAL as one of the native interval types.
- [Now translation split](../../history/decisions/2026-now-translation-split.md) -- see recorded decisions above.
