---
area: PROV-ACCESS
kind: issues
sources: [gh-issues, gh-prs, gh-discussions]
confidence: high
last_verified: 2026-11-11
last_verified_sha: f90c5bcfb86d88db436a6494f0640c4c43dd691f
---

# PROV-ACCESS -- GitHub themes

## Open themes

- **Schema generation and model quality** -- T4 scaffold and schema-read issues affecting MS Access models. Context class names embed full file paths instead of derived names (#3191); association names default to random GUIDs instead of derived back-reference names (#2331); schema build error on Refresh in LINQPad with the ACE provider (#5235).
- **Driver fidelity: ODBC and Jet OLE DB value handling** -- Access drivers handle some values differently from the core path. ODBC throws OverflowException for long parameters above int.MaxValue (#5748); ODBC drops the sub-second part of DateTime values in both directions while OLE DB keeps it (#5998); a projected difference of two local DateTime values is read back as TIME, which Access over ODBC fails on (#5989); Jet OLE DB returns an undecodable NUMERIC buffer for AVG over a DECIMAL column (#5954).
- **ACE SQL shape limits: aggregates and correlated subqueries** -- ACE either rejects or silently mis-evaluates query shapes the core path generates. An uncorrelated `TOP 1 ... ORDER BY` column subquery whose select list is a correlated scalar subquery returns different values per outer row with no error, on both OLE DB and ODBC (#6032). A grouped aggregate compared with `Contains` is rendered in WHERE, which the server rejects with "Cannot have aggregate function in WHERE clause"; the aggregate belongs in HAVING or a wrapped subquery (#6047). ACE also rejects with "Query is too complex" when several members of one date difference each expand into their own DateDiff/DateAdd decomposition (#5993). Related resolved shape: Single() rendered as TOP 2 (#2557).
- **Outer joins and UPDATE shape on Jet/ACE** -- Jet/ACE mishandles join shapes the core path emits. Jet treats an ON conjunct of a LEFT JOIN that reads only the preserved outer side as a filter, dropping outer rows that must be null-extended (#6215); linq2db wraps joined-side ON predicates that Jet accepts when IsComplexJoinConditionSupported is false (#6216); an UPDATE whose target sits on the preserved side of a RIGHT JOIN nested in a LEFT JOIN throws InvalidOperationException in the UPDATE correction step before any SQL is sent (#6240).
- **Access SQL text generation** -- Two open defects in the SQL text linq2db writes for Access. A SQL-side concatenation of a column with a non-null string parameter re-enters SqlExpressionConvertVisitor until StackGuard throws (#6193). Identifier quotation is still to be improved (#3893, found by tests from #3892; indexed under SQL-PROVIDER).
- **Managed Access transport via LibRed (in flight)** -- LibRed, a managed cross-platform Jet/ACE engine and ADO.NET provider, as a third Access transport that needs no Microsoft driver install. #5956 adds the LibRed provider on top of #5942 (.NET 11 support) and #5944 (C# 15 and runtime async); it is not for merge before .NET 11 RTM. #5969 (child of #5956) lifts the Access dialect for LibRed: every dialect exclusion named TestProvName.AllAccess, which includes LibRed, so none of the tests exercising its extended SQL ran on it. Both are drafts.

## Resolved themes

- **VS2022 64-bit incompatibility** -- OLE DB / ODBC drivers in 64-bit environment. Access requires 32-bit drivers on VS2022 (64-bit IDE) (#3344, #5311).
- **Boolean / string type mapping** -- Access CHAR/STRING columns mapped to C# bool via ValueConverter; parameter wrapping losses on UPDATE SET (#5519, #5520). Read-side string parsers moved to FromDatabase (#5520). Schema read ACE database fixes (#1119).
- **Boolean ORDER BY keys** -- Jet/ACE evaluate True as -1, so an ascending ORDER BY on a Yes/No column or predicate returned the true rows first; the keys now sort in .NET order (#6203, merged 2026-11-10). Follow-up #6296 (open) removes the stale #6203 gates from two ORDER BY predicate tests.
- **Schema discovery and FK relationships** -- AccessSchemaProvider issues with foreign keys, multiple association names without user-defined names (#593, #2331). Fixed via schema option DisableForeignKeySchemaLoad (#1907).
- **Query translation specifics** -- LIKE wildcard escaping differences, Single() producing TOP 2, association-alias resolution (#1925, #2022, #2557), contains failing with OleDb (#742), parameter limits (64KB SQL, 767 max params).
- **ODBC vs OLE DB driver support** -- Feature request #333, netcore provider path additions (#1917, #1920).
- **Data access and connection lifecycle** -- Connection pool exhaustion after repeated access (#3608), INSERT statement missing PK inclusion (#3299), foreign key constraint on INSERT (#1909).
- **T4 template and scaffolding** -- Model generation failures (#1164), VS2022 64-bit T4 support, exclude-schemas option regression (#3709), context and scaffold questions (#3626).
- **Type mapping** -- Long Integer field mapping (should be long, not int #289), boolean type mapping (#409), long text column type (#4003), custom type conversions.
- **Date-difference translation on Access** -- A member of a nullable date difference read through Nullable of TimeSpan .Value was not translated (#5988, closed 2026-10-09; no closing PR is linked in the index).
- **Test-suite Access ODBC connection handling** -- Access ODBC test connection strings tuned for Threads and MaxBufferSize (#5700), and one ODBC connection held open for the whole test run (#5747). Both closed. The x86 Access MDB test leg was split per provider (#6005, merged 2026-10-10) after OutOfMemoryException in one 32-bit process. The x86 Access ACE leg was split per provider with its OLE DB connection held open (#5753, merged 2026-08-10), and the 32-bit Access legs were stabilised with a 4 GB address space and a System.Data.OleDb pin (#5761, merged 2026-08-17).
- **Cross-area changes tagged PROV-ACCESS** -- Engine-level PRs the index tags PROV-ACCESS but that are not Access-specific: #5468, #5482, #5501, #5619, #5639, #5645 (all closed). #5493 (Duplicate parameter optimization) closed unmerged 2026-10-17; the index now tags it CORE.

## Active discussions
- No active discussions.

## Stats
- Open issues: 15 (#2331, #3191, #3893, #5235, #5748, #5954, #5989, #5993, #5998, #6032, #6047, #6193, #6215, #6216, #6240)
- Closed issues: 23
- Open PRs: 3 (#5956, #5969, #6296; #5956 and #5969 are drafts on the LibRed track)
- Total PRs: 20
- Discussions: 4 (all closed)
- Last fetched: 2026-11-11 (indexes refreshed with items updated 2026-10-21 to 2026-11-11)

<details><summary>Coverage</summary>

- Index entries scanned: 62 (38 issues + 20 PRs + 4 discussions)
- Themes extracted: 6 (open) + 12 (resolved)
</details>
