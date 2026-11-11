---
area: PROV-YDB
kind: issues
sources: [gh-issues, gh-prs, gh-discussions]
confidence: high
last_verified: 2026-11-11
last_verified_sha: f90c5bcfb86d88db436a6494f0640c4c43dd691f
---

# PROV-YDB -- GitHub themes

## Open themes
- **YDB type system strictness** -- YDB's strict type semantics surface gaps in linq2db's type inference and code generation. Decimal facet mismatches in COALESCE/CAST/arithmetic (#5591), SDK decimal unpacking overflow (#5592, upstream Ydb.Sdk), null parameters lacking a concrete type (#5594), and non-nullable string expressions inferred nullable on output (#5595). The same decimal-facet class recurs in newer shapes: Math.Floor/Ceiling/Truncate computed through Double lose digits (#6041), and a decimal mapped with Precision but no Scale is bound as Decimal(P, 0) and rejects fractional values (#6063). The captured IN list beside an aggregate written at the schema's default scale (#6064, cross-area PROV-CLICKHOUSE) and the ROUND emulation overflow (#5943) are both closed or merged and sit under resolved.

- **Date, time and interval conversions** -- Timestamp--Date and Interval--Int64 conversions are missing on YDB and surface in merge-types round-trips (#5593). Native interval columns need TimeSpan members and comparisons (#5759, cross-area SQL-AST). Date-shift translation for YDB landed in #5987 (see resolved). A text-to-date/time cast returns no rows on YDB and is wrong on SQLite and Informix (#6071, cross-area labels; index area PROV-SQLITE).

- **SQL ordering and optimizer scope** -- Two separate issues affect query shape. A CTE's inner ORDER BY is not preserved in the outer SELECT (#5596), which breaks result ordering. A DDL-only [PrimaryKey], added only to satisfy YDB's mandatory-PK DDL requirement, is treated as a unique key by the optimizer (#5597), which silently drops projected columns on GROUP BY.

- **Unsupported correlated subqueries** -- For providers that cannot run correlated subqueries (YDB and ClickHouse), linq2db does not reliably detect and reject them, which surfaces as a generic "could not be converted to SQL" error or as wrong SQL (#5590, cross-area PROV-CLICKHOUSE). Merged #5574 covers the expression-position case. #5590 stays open for the general detection gap. The same generic refusal hides the provider's reason when the refused construct sits in a projection filtered through AsSubQuery(): on YDB, a LAG with a default argument reports only the comparison as unconvertible (#6080, cross-area LINQ).

- **Schema reads and DDL generation** -- One undescribable object fails the entire YDB schema read (flaky SchemeError) (#5745, still open). Identifiers that match YQL type keywords are not quoted, which produces invalid DDL (#5749).

- **LEFT JOIN predicate placement** -- With SqlProviderFlags.IsComplexJoinConditionSupported = false (YDB), SelectQueryOptimizerVisitor.MoveJoinConditionsToWhere moves a LEFT JOIN ON predicate that reads only the outer side into WHERE, which drops outer rows. A discriminator that an association declared on a derived TPH type adds to the ON clause triggers it (#6148). Fix attempt #6157 was closed unmerged on 2026-11-05. Open PR #6257 (cross-area GLOBAL) keeps outer-dependent predicates in ON when complex join conditions are unsupported.

- **NULL semantics** -- NULL is mishandled on YDB in three shapes. An untyped null parameter is rejected (#5594). Sql.Substring and Sql.Left with a NULL length probably return the rest of the string instead of NULL, and Sql.Stuff may share it (#6262, not yet verified). A cached direct query keeps the NULL check on a System.Data.Linq.Binary comparison that the remote (.LinqService) context drops (#6202).

- **Reader and transaction lifecycle** -- On YDB, an exception thrown while rows are materialized inside a transaction does not reach the caller. Closing the reader then throws YdbDataReader was closed during transaction, which hides the original error (#6289). Single item so far.

## Resolved themes
- **F# record-copy update behavior** -- F# { record with ... } emitted every column including the PK, which YDB rejects. Resolved: #5598 (closed 2026-06-27) via PR #5627 sets only the changed columns.
- **Provider bring-up and test enablement** -- The experimental YDB provider landed in stages: preview (#5218, from the #4954 split, with #5129, #5136, #5137, #5138, #5139, #5140, #5141), then the schema API, NuGet bump and test enablement in #5564 (merged 2026-06-15).
- **Test-suite stability on YDB** -- Keyless local test tables fixed by #5583 and #5589 (PKs added, deterministic Issue5549 baseline). TakeSkipJoin gated for the YDB 26.1.1.20 optimizer regression (#5705). In-memory PDisks cut YDB test time by about 42% (#5756). Merged UpdateOptimisticWithRefresh (#5643, fixes #4194) is tagged to this area. The table-dropped schema test is excluded from baselines because its statement order varies per run (#6259, cross-area TESTS-INFRA, merged 2026-11-06).
- **Dateparts and date-shift translation** -- Unsupported dateparts return null instead of throwing NotImplementedException (#5335, closed). Date differences regressed in 6.5.0 were fixed and date shifts translated on SQLite, Firebird, Oracle and YDB (#5987, merged 2026-10-09, cross-area PROV-ORACLE).
- **Schema read race** -- Reading the YDB schema while another connection drops tables could fail with SchemeError. #5763 bumps Ydb.Sdk to 0.38.0 and skips tables dropped between the table listing and the per-table describe (merged 2026-11-06). The undescribable-object failure stays open in #5745.
- **Decimal facet fixes** -- #5943 widens the scaled intermediate in the YDB ROUND emulation, so Math.Round(x, p) over a decimal column no longer fails when the scaled value exceeds the declared precision (merged 2026-10-22). #6064 writes captured IN-list values beside an aggregate at the column's scale instead of the schema default (closed 2026-10-22, cross-area PROV-CLICKHOUSE).
- **Transport retry on YDB** -- #6199 retries ClientTransportCancelled only for idempotent operations when enableRetryIdempotence is set, with equal-jitter backoff (merged 2026-11-04).

## Active discussions
- No active discussions.

## Stats
- Open issues: 15
- Closed issues: 1
- Open PRs: 0
- Total PRs: 20
- Discussions: 0
- Last fetched: 2026-11-11 (index data through 2026-11-11)

Cross-area YDB items cited above but not counted in Stats: #5590 (open, PROV-CLICKHOUSE), #5759 (open, SQL-AST), #5574 and #5582 (merged, SQL-AST), #5599 (closed, PROV-SQLCE), #5987 (merged, PROV-ORACLE), #6064 (closed, PROV-CLICKHOUSE), #6071 (open, PROV-SQLITE), #6080 (open, LINQ), #6257 (open, GLOBAL), #6259 (merged, TESTS-INFRA).

<details><summary>Coverage</summary>

- Index entries scanned: 36 (16 issues + 20 PRs + 0 discussions) area-tagged, plus 10 cross-area YDB items
- Delta 2026-11-11: new open PROV-YDB issues #6148, #6202, #6262, #6289; new PROV-YDB PRs #6157 (closed unmerged) and #6199 (merged); #5943 merged and #6064 closed, moved to resolved; #5763 merged, moved to resolved
- Themes extracted: 8 open, 7 resolved
</details>
