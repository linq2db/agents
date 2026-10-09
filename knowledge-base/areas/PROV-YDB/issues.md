---
area: PROV-YDB
kind: issues
sources: [gh-issues, gh-prs, gh-discussions]
confidence: high
last_verified: 2026-10-10
last_verified_sha: 05150894edc2511f0dd0bc7829b2a309cec36ec9
---

# PROV-YDB -- GitHub themes

## Open themes
- **YDB type system strictness** -- YDB's strict type semantics surface gaps in linq2db's type inference and code generation. Decimal facet mismatches in COALESCE/CAST/arithmetic (#5591), SDK decimal unpacking overflow (#5592, upstream Ydb.Sdk), null parameters lacking a concrete type (#5594), and non-nullable string expressions inferred nullable on output (#5595). Open PR #5943 widens the scaled intermediate in the ROUND emulation, which fails at runtime when the scaled decimal does not fit the column's declared precision -- the same facet class as #5591.

- **Date, time and interval conversions** -- Timestamp--Date and Interval--Int64 conversions are missing on YDB and surface in merge-types round-trips (#5593). Native interval columns need TimeSpan members and comparisons (#5759, cross-area SQL-AST). Date-shift translation for YDB landed in #5987 (see resolved).

- **SQL ordering and optimizer scope** -- Two separate issues affect query shape. A CTE's inner ORDER BY is not preserved in the outer SELECT (#5596), which breaks result ordering. A DDL-only [PrimaryKey], added only to satisfy YDB's mandatory-PK DDL requirement, is treated as a unique key by the optimizer (#5597), which silently drops projected columns on GROUP BY.

- **Unsupported correlated subqueries** -- For providers that cannot run correlated subqueries (YDB and ClickHouse), linq2db does not reliably detect and reject them, which surfaces as a generic "could not be converted to SQL" error or as wrong SQL (#5590, cross-area PROV-CLICKHOUSE). Merged #5574 covers the expression-position case. #5590 stays open for the general detection gap.

- **Schema reads and DDL generation** -- One undescribable object fails the entire YDB schema read (flaky SchemeError) (#5745). Open PR #5763 (cross-area GLOBAL) retries schema reads that race a just-committed DDL. Identifiers that match YQL type keywords are not quoted, which produces invalid DDL (#5749).

## Resolved themes
- **F# record-copy update behavior** -- F# { record with ... } emitted every column including the PK, which YDB rejects. Resolved: #5598 (closed 2026-06-27) via PR #5627 sets only the changed columns.
- **Provider bring-up and test enablement** -- The experimental YDB provider landed in stages: preview (#5218, from the #4954 split, with #5129, #5136, #5137, #5138, #5139, #5140, #5141), then the schema API, NuGet bump and test enablement in #5564 (merged 2026-06-15).
- **Test-suite stability on YDB** -- Keyless local test tables fixed by #5583 and #5589 (PKs added, deterministic Issue5549 baseline). TakeSkipJoin gated for the YDB 26.1.1.20 optimizer regression (#5705). In-memory PDisks cut YDB test time by about 42% (#5756). Merged UpdateOptimisticWithRefresh (#5643, fixes #4194) is tagged to this area.
- **Dateparts and date-shift translation** -- Unsupported dateparts return null instead of throwing NotImplementedException (#5335, closed). Date differences regressed in 6.5.0 were fixed and date shifts translated on SQLite, Firebird, Oracle and YDB (#5987, merged 2026-10-09, cross-area PROV-ORACLE).

## Active discussions
- No active discussions.

## Stats
- Open issues: 9
- Closed issues: 1
- Open PRs: 1
- Total PRs: 17
- Discussions: 0
- Last fetched: 2026-10-10 (index data through 2026-10-09)

Cross-area YDB items cited above but not counted in Stats: #5590 (open, PROV-CLICKHOUSE), #5759 (open, SQL-AST), #5763 (open PR, GLOBAL), #5574 and #5582 (merged, SQL-AST), #5599 (closed, PROV-SQLCE), #5987 (merged, PROV-ORACLE).

<details><summary>Coverage</summary>

- Index entries scanned: 27 (10 issues + 17 PRs + 0 discussions) area-tagged, plus 7 cross-area YDB items
- Themes extracted: 5 open, 4 resolved
</details>
