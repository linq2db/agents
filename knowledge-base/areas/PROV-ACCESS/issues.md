---
area: PROV-ACCESS
kind: issues
sources: [gh-issues, gh-prs, gh-discussions]
confidence: high
last_verified: 2026-10-21
last_verified_sha: 89b5ce16278728b9936ba374827fea002c76e962
---

# PROV-ACCESS -- GitHub themes

## Open themes

- **Schema generation and model quality** -- T4 scaffold and schema-read issues affecting MS Access models. Context class names embed full file paths instead of derived names (#3191); association names default to random GUIDs instead of derived back-reference names (#2331); schema build error on Refresh in LINQPad with the ACE provider (#5235).
- **Driver fidelity: ODBC and Jet OLE DB value handling** -- Access drivers handle some values differently from the core path. ODBC throws OverflowException for long parameters above int.MaxValue (#5748); ODBC drops the sub-second part of DateTime values in both directions while OLE DB keeps it (#5998); a projected difference of two local DateTime values is read back as TIME, which Access over ODBC fails on (#5989); Jet OLE DB returns an undecodable NUMERIC buffer for AVG over a DECIMAL column (#5954).
- **ACE SQL shape limits: aggregates and correlated subqueries** -- ACE either rejects or silently mis-evaluates query shapes the core path generates. An uncorrelated `TOP 1 ... ORDER BY` column subquery whose select list is a correlated scalar subquery returns different values per outer row with no error, on both OLE DB and ODBC (#6032). A grouped aggregate compared with `Contains` is rendered in WHERE, which the server rejects with "Cannot have aggregate function in WHERE clause"; the aggregate belongs in HAVING or a wrapped subquery (#6047). Related resolved shape: Single() rendered as TOP 2 (#2557).
- **Managed Access transport via LibRed (in flight)** -- LibRed, a managed cross-platform Jet/ACE engine and ADO.NET provider, as a third Access transport that needs no Microsoft driver install. #5956 adds the LibRed provider on top of #5942 (.NET 11 support) and #5944 (C# 15 and runtime async); it is not for merge before .NET 11 RTM. #5969 (child of #5956) lifts the Access dialect for LibRed: every dialect exclusion named TestProvName.AllAccess, which includes LibRed, so none of the tests exercising its extended SQL ran on it. Both are drafts.

## Resolved themes

- **VS2022 64-bit incompatibility** -- OLE DB / ODBC drivers in 64-bit environment. Access requires 32-bit drivers on VS2022 (64-bit IDE) (#3344, #5311).
- **Boolean / string type mapping** -- Access CHAR/STRING columns mapped to C# bool via ValueConverter; parameter wrapping losses on UPDATE SET (#5519, #5520). Read-side string parsers moved to FromDatabase (#5520). Schema read ACE database fixes (#1119).
- **Schema discovery and FK relationships** -- AccessSchemaProvider issues with foreign keys, multiple association names without user-defined names (#593, #2331). Fixed via schema option DisableForeignKeySchemaLoad (#1907).
- **Query translation specifics** -- LIKE wildcard escaping differences, Single() producing TOP 2, association-alias resolution (#1925, #2022, #2557), contains failing with OleDb (#742), parameter limits (64KB SQL, 767 max params).
- **ODBC vs OLE DB driver support** -- Feature request #333, netcore provider path additions (#1917, #1920).
- **Data access and connection lifecycle** -- Connection pool exhaustion after repeated access (#3608), INSERT statement missing PK inclusion (#3299), foreign key constraint on INSERT (#1909).
- **T4 template and scaffolding** -- Model generation failures (#1164), VS2022 64-bit T4 support, exclude-schemas option regression (#3709), context and scaffold questions (#3626).
- **Type mapping** -- Long Integer field mapping (should be long, not int #289), boolean type mapping (#409), long text column type (#4003), custom type conversions.
- **Date-difference translation on Access** -- A member of a nullable date difference read through Nullable of TimeSpan .Value was not translated (#5988, closed 2026-10-09; no closing PR is linked in the index).
- **Test-suite Access ODBC connection handling** -- Access ODBC test connection strings tuned for Threads and MaxBufferSize (#5700), and one ODBC connection held open for the whole test run (#5747). Both closed. The x86 Access MDB test leg was split per provider (#6005, merged 2026-10-10) after OutOfMemoryException in one 32-bit process.
- **Cross-area changes tagged PROV-ACCESS** -- Engine-level PRs the index tags PROV-ACCESS but that are not Access-specific: #5468, #5482, #5501, #5619, #5639, #5645 (all closed). #5493 (Duplicate parameter optimization) closed unmerged 2026-10-17; the index now tags it CORE.

## Active discussions

- No active discussions.

## Stats

- Open issues: 9 (#2331, #3191, #5235, #5748, #5954, #5989, #5998, #6032, #6047)
- Closed issues: 23
- Open PRs: 2 (#5956, #5969; both draft, LibRed track)
- Total PRs: 15
- Discussions: 4 (all closed)
- Last fetched: 2026-10-21 (issues cursor 2026-10-21T19:48:04Z, PRs cursor 2026-10-21T20:10:53Z)

<details><summary>Coverage</summary>

- Index entries scanned: 51 (32 issues + 15 PRs + 4 discussions)
- Themes extracted: 4 (open) + 11 (resolved)
</details>
