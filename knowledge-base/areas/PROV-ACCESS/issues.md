---
area: PROV-ACCESS
kind: issues
sources: [gh-issues, gh-prs, gh-discussions]
confidence: high
last_verified: 2026-10-10
last_verified_sha: 05150894edc2511f0dd0bc7829b2a309cec36ec9
---

# PROV-ACCESS -- GitHub themes

## Open themes

- **Schema generation and model quality** -- T4 scaffold and schema-read issues affecting MS Access models. Context class names embed full file paths instead of derived names (#3191); association names default to random GUIDs instead of derived back-reference names (#2331); schema build error on Refresh in LINQPad with the ACE provider (#5235).
- **Driver fidelity: ODBC and Jet OLE DB value handling** -- Access drivers handle some values differently from the core path. ODBC throws OverflowException for long parameters above int.MaxValue (#5748); ODBC drops the sub-second part of DateTime values in both directions while OLE DB keeps it (#5998); a projected difference of two local DateTime values is read back as TIME, which Access over ODBC fails on (#5989); Jet OLE DB returns an undecodable NUMERIC buffer for AVG over a DECIMAL column (#5954).

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
- **Test-suite Access ODBC connection handling** -- Access ODBC test connection strings tuned for Threads and MaxBufferSize (#5700), and one ODBC connection held open for the whole test run (#5747). Both closed.
- **Cross-area changes tagged PROV-ACCESS** -- Engine-level PRs the index tags PROV-ACCESS but that are not Access-specific: #5468, #5482, #5501, #5619, #5639, #5645 (all closed).

## Active discussions

- No active discussions.

## Stats

- Open issues: 7 (#2331, #3191, #5235, #5748, #5954, #5989, #5998)
- Closed issues: 23
- Open PRs: 1 (#5493, tagged PROV-ACCESS by the index; labelled area: sql)
- Total PRs: 14
- Discussions: 4 (all closed)
- Last fetched: 2026-10-10 (index items through 2026-10-09)

<details><summary>Coverage</summary>

- Index entries scanned: 48 (30 issues + 14 PRs + 4 discussions)
- Themes extracted: 2 (open) + 11 (resolved)
</details>
