---
area: PROV-DUCKDB
kind: issues
sources: [gh-issues, gh-prs, gh-discussions]
confidence: low
last_verified: 2026-11-11
last_verified_sha: f90c5bcfb86d88db436a6494f0640c4c43dd691f
---

# PROV-DUCKDB -- GitHub themes

## Open themes
- **Date/time parameter typing and Now translation** -- DuckDB binds untyped parameters, and `now()` returns `TIMESTAMP WITH TIME ZONE`, so mixing a `DateTime` parameter with `Sql.CurrentTimestamp` in one conditional can shift the stored value by the session's UTC offset. Open: [#5977](https://github.com/linq2db/linq2db/issues/5977). Same family as the Now-translation work in [#5518](https://github.com/linq2db/linq2db/pull/5518) (resolved below). Sub-day date functions also fail on the DuckDB server clock and on DATE / low-precision operands, the same bug class as ClickHouse, found on several providers: [#5965](https://github.com/linq2db/linq2db/issues/5965) (cross-provider, tagged SQL-AST).
- **Native reader gaps on the netstandard2.0 asset** -- the ns2.0 build registers DuckDB's date/time readers only under `SUPPORTS_DATEONLY`, so a modern runtime that loads the ns2.0 asset cannot read `TIMETZ` into `TimeSpan`. Open: [#6084](https://github.com/linq2db/linq2db/issues/6084). Single item; the same TFM-gate pattern shows up in other providers' compatibility issues, which are not counted here.
- **Integer function overloads keep the fraction in SQL** -- the integer `Sql.Degrees` overloads translate to the engine's `DEGREES`, which returns a float on DuckDB and SQLite, so the fraction survives into a SQL comparison. Open: [#6072](https://github.com/linq2db/linq2db/issues/6072). Indexed under PROV-SQLITE and labelled `provider: duckdb`; cited here, not counted in Stats.
- **Decimal rounding with a precision on DuckDB** -- `Math.Round` and `Sql.RoundToEven` with a decimal precision fail on DuckDB in two shapes: a precision computed per row ([#6100](https://github.com/linq2db/linq2db/issues/6100)), and a constant precision on a large decimal that overflows or loses digits ([#6275](https://github.com/linq2db/linq2db/issues/6275)). Both are open; the fix will likely share one rounding translation path.
- **DistinctBy on DISTINCT ON providers (DuckDB and PostgreSQL)** -- DuckDB and PostgreSQL lower `DistinctBy` to `DISTINCT ON`, which makes row choice depend on the ordering that reaches it. Open: [#6192](https://github.com/linq2db/linq2db/issues/6192) (ordered and limited sequence returns wrong rows), [#6223](https://github.com/linq2db/linq2db/issues/6223) (ordering lost across a LEFT JOIN grouped by the inner key). The fix in progress is [#6197](https://github.com/linq2db/linq2db/pull/6197) (open PR, DistinctBy row choice after Take/Skip, joins and GroupBy). Earlier lowering work is in [#5630](https://github.com/linq2db/linq2db/pull/5630) (resolved below).
- **Invalid ORDER BY after GroupBy with a string aggregate** -- an ordering on a non-grouped column before `GroupBy`, with a string aggregate in the projection, stays on the grouped query, and DuckDB rejects the SQL. Open: [#6283](https://github.com/linq2db/linq2db/issues/6283). Single item.
- **Remote client on WASM loads provider assemblies** -- the client-side mapping schema for DuckDB (among PostgreSQL, MySqlConnector and ClickHouse) creates the provider adapter, which loads an ADO.NET assembly a WASM client cannot load. Open: [#6167](https://github.com/linq2db/linq2db/issues/6167) (REMOTE-CLIENT, cross-provider).

## Resolved themes
- **Now and date translation regressions** -- the Now translation refactor (bare keywords replaced by function-call forms such as `now()` and `current_localtimestamp()`) broke the master build during the #5451 / #5467 merge race; fixed by [#5518](https://github.com/linq2db/linq2db/pull/5518) (merged 2026-05-10).
- **Provider bring-up and native loading** -- DuckDB provider added in [#5451](https://github.com/linq2db/linq2db/pull/5451) (merged 2026-05-10). The x86 native-load guard caught the wrong exception type, which failed both x86 Access jobs on the 6.4.0 release PR; fixed by [#5744](https://github.com/linq2db/linq2db/pull/5744) (merged 2026-08-05).
- **DISTINCT ON lowering for DistinctBy** -- PostgreSQL and DuckDB `DistinctBy` support via `DISTINCT ON` was added in [#5630](https://github.com/linq2db/linq2db/pull/5630) (merged 2026-06-24, closes #2075). The open row-choice follow-ups are under the DistinctBy theme above.
- **In-memory test databases for SQLite and DuckDB** -- the CI and test work that runs the DuckDB suite against an in-memory database and preloads it was split out in [#5698](https://github.com/linq2db/linq2db/pull/5698) (merged 2026-07-10) and [#5710](https://github.com/linq2db/linq2db/pull/5710) (merged 2026-07-13). Test infrastructure only, no provider behaviour change.
- **DECLARE type names in trace and baselines** -- DuckDB parameters printed an empty type in the trace `DECLARE` block (`DECLARE @p -- Int32`) because its builder had no type-name override; fixed with the SQLite and ClickHouse builders in [#6198](https://github.com/linq2db/linq2db/pull/6198) (merged 2026-11-10).

## Active discussions
- None in the PROV-DUCKDB area.

## Stats
- Open issues: 5
- Closed issues: 0
- Open PRs: 0
- Total PRs: 3
- Discussions: 0
- Last fetched: 2026-11-11

<details><summary>Coverage</summary>

- Index entries scanned: 3245 issues + 2699 PRs + 296 discussions. Filter: DuckDB keyword in title, summary, body excerpt, labels, linked files or area tag. Matches: 14 issues + 14 PRs + 1 discussion (the discussion is EXPR-TRANS, not counted).
- Themes extracted: 7 open, 5 resolved.
- Notes: refresh on 2026-11-11 over the 2026-10-21 to 2026-11-11 window. Kept all three prior open citations (#5977, #6084, #6072), all still open. Added open citations #6100, #6275, #6283, #6192, #6223, #6197, #6167 and #5965. Added resolved citations #5630, #5698, #5710 and #6198. Nothing moved from open to resolved. Not cited: #6200 (PROV-POSTGRES, labelled `provider: duckdb`, CONCAT_WS typing is a general PostgreSQL and DuckDB issue, not DuckDB-specific), #6218 (EXPR-TRANS, DistinctBy in Contains, no DuckDB reference), #5759 (interval members, DuckDB named only as one of four interval types), #5806 (closed, DuckDB only as an accepting provider). Stats count only items tagged PROV-DUCKDB.
</details>
