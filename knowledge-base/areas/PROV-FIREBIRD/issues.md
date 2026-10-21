---
area: PROV-FIREBIRD
kind: issues
sources: [gh-issues, gh-prs, gh-discussions]
confidence: high
last_verified: 2026-10-21
last_verified_sha: 89b5ce16278728b9936ba374827fea002c76e962
---

# PROV-FIREBIRD -- GitHub themes

## Open themes

- **Type mapping edge cases** -- Firebird's type system diverges from standard SQL in subtle ways: UInt32 constants incorrectly cast to BigInt unsupported in SQL Dialect 1 (#1318); CHAR(x) CHARACTER SET OCTETS not recognized for binary data (#755); numeric constants vs variables producing different SQL and result types (#4469); a DateTimeOffset value round-trips to a different instant or throws in the client (#5915, opened 2026-09-12, area types).

- **Stored procedure scaffolding coverage** -- CLI scaffold skips stored procedures with output parameters (#4447) and generates incorrect signatures with redundant output parameters in the method signature (#4718). Related closed history: procedure without parameters (#4065), QueryProc with optional input parameters (#1812), stored procedure follow-up (#1043).

- **Firebird 6 DDL syntax modernization** -- Firebird 6 introduces native `IF [NOT] EXISTS` clauses for CREATE/DROP TABLE, but linq2db continues using legacy `EXECUTE BLOCK` + metadata-lookup workaround. Tracked in #5483; Firebird 6 support work is in open PR #5485.

- **Cancelled async operations and pooled connection health** -- A cancelled async operation (token already cancelled, or cancelled between steps such as inside `CreateTempTableAsync`) can leave a pooled FirebirdClient connection with a half-written request, so a later unrelated `DataConnection` hangs forever in `NetworkStream.Read` and the original one throws a `NullReferenceException` from `FbCommand` (#6012, open, opened 2026-10-09). Product-level fix still open; upstream tracked in FirebirdSQL/NETProvider#1281 per the PR body. The test suite was worked around by test-only PR #6013 (merged 2026-10-11) so intermittent `tests [all]` hangs in `CreateTableAsyncCanceled*` stop. The workaround does not resolve #6012. Related pool history: scoped `FirebirdTools.ClearPool(connection)` (#5689) and the connection-lost pool error (#1035).

## Resolved themes

- **Firebird provider foundation** -- 45 closed issues covering the full history of Firebird provider support. Sample: #92, #682, #806, #868, #966, #967, #1043, #1035.

- **Boolean mapping** -- Boolean support added via PR #1646. Later pattern: Firebird 2.5 emitting an unnecessary '1' constant column (#4559), string "1" conversion error on boolean insert (#4619), and a Firebird 6 RC3 boolean comparison failure (#5214, closed as resolution external).

- **Guid support** -- Guid data type not handled by FirebirdSqlBuilder (#2823, fixed by PR #2826), and Guid literal generation (#2833).

- **Identifier quoting and reserved words** -- Qualified table name generation (#682), reserved-word list updates (#1741 with PR #1747; PR #1109), and table alias escaping (PR #2446).

- **Merge and bulk-copy paths** -- Multiple update/insert (#806), Merge performance (#868), max records for Merge API (#2027), BulkCopyType.MultipleRows corrupting varchar data (#2839), and InsertOrReplace scale/precision error in the merge statement (#5272).

- **Decimal type calculation** -- Corrected decimal type calculation for Firebird and DB2 (PR #5276, closed 2025-12-28).

- **Connection pool handling** -- Connection pool error on connection lost (#1035) closed in 2018; scoped `FirebirdTools.ClearPool(connection)` added via PR #5689 (closed 2026-07-09).


## Active discussions

- [Create POCO with only some fields](https://github.com/linq2db/linq2db/discussions/3229) -- [Q&A] Template-based POCO generation filtering: how to exclude unwanted table columns from the `.tt` T4 output.
- [Select a substring of a memo field without having the base field on the entity](https://github.com/linq2db/linq2db/discussions/3465) -- [Q&A] Field property mapping to a SQL substring without requiring the full base memo field.
- [How is the query that Linq2Db generates for Firebird supposed to be executed?](https://github.com/linq2db/linq2db/discussions/4418) -- [Q&A] Parametrized SELECT query execution and dialect-specific SQL generation verification.
- [Linq2Db not all stored procedures scaffolding](https://github.com/linq2db/linq2db/discussions/4442) -- [Q&A] CLI-based database scaffolding coverage for Firebird stored procedures.

## Stats

- Open issues: 8
- Closed issues: 45
- Open PRs: 2
- Total PRs: 25
- Discussions: 4
- Last fetched: 2026-10-21

<details><summary>Coverage</summary>

- Index entries scanned: 82 (53 issues + 25 PRs + 4 discussions)
- Themes extracted: 11 (4 open, 7 resolved)
- Note: open PR #5542 (AsQueryable UseTempTable threshold) is index-tagged PROV-FIREBIRD but is not Firebird-specific; counted in Open PRs, not cited as a theme.
- Note: merged PR #6013 is a test-only workaround for open issue #6012; cited under the open theme, not as a resolution.
- Note: all four discussions are marked closed in discussions-index.json; retained under Active discussions as in the previous revision.
</details>
