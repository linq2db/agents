---
area: PROV-DB2
kind: issues
sources: [gh-issues, gh-prs, gh-discussions]
confidence: medium
last_verified: 2026-11-11
last_verified_sha: f90c5bcfb86d88db436a6494f0640c4c43dd691f
---

# PROV-DB2 -- GitHub themes

## Open themes

- **DB2 string type handling edge cases** -- #2362 describes rows being skipped when a VARCHAR column contains an empty string (mapped via value converter). The issue affects querying with value converters where empty strings need to be distinguished from NULL. #6195 (open) reports that concatenating a column with a non-null string parameter fails on DB2 LUW with CLI0109E: the `COALESCE(@p, '')` wrapper types the marker as VARCHAR(0). #6237 (open) reports that `Sql.Convert(Sql.Types.NVarChar(n), column)` over a VARCHAR column renders `Char(column, n)`, a blank-padded value, so `Sql.Like` misses a pattern without a trailing wildcard.

- **DB2 numeric and floating-point semantics** -- Floating-point results on DB2 diverge from other providers. #5897 reports `RATIO_TO_REPORT` returning `Infinity` on a zero partition sum where other providers return NULL. #5994 reports a `double` parameter added to an integer column losing its fraction because the C# cast is dropped; DB2 types the parameter from the column; the same expression with the column on the left keeps `CAST(... AS Float)`. #6263 (open) reports that `Math.Round(double, digits)` rounds an exact double tie to even differently from .NET on DB2: `Math.Round(1.15, 1)` returns 1.1 on DB2, while .NET returns 1.2. The special-value mapping work in #5663 (resolved below) is the adjacent fix.

- **DB2 date/time typing and casts** -- #5989 (tagged PROV-ACCESS, but the same defect affects DB2 and Firebird) reports that a projected difference of two local `DateTime` values is returned as TIME: Access fails and DB2 truncates the value. Area ownership is still with PROV-ACCESS; the DB2 symptom is cross-referenced here until reclassified. #6019 (open, labelled `provider: db2`) reports that a recursive CTE anchor wraps a `DateTime` literal in a second cast to the same type, `CAST(CAST('...' AS TIMESTAMP(6)) AS timestamp)`. The result is unaffected; the SQL is longer than it needs to be.

- **DB2 NULL semantics in value comparisons** -- A nullable equality or IN predicate used as a value, not as a WHERE filter, can evaluate to UNKNOWN where C# evaluates to a bool. #6065 (open, PROV-DB2) reports `e.Flag == (e.Id == e.Item || e.Id == 5)` with `Item` as `int?`: DB2 LUW evaluates the right-hand side as UNKNOWN for a row with `Item` NULL and drops the row that C# keeps. #6066 (area tag sql; DB2 symptom cross-referenced here until reclassified) reports the same class for a nullable inline-array `Contains` converted to a string: on DB2 the membership is UNKNOWN and the concatenated string comes back NULL where C# returns a string ending in `False`. Only two items; kept as one theme because both are one defect class (UNKNOWN propagated into a projected value).

## Resolved themes

- **DB2/Informix native client loading on Linux/macOS** -- #5538 tracked transient failures where the native `libdb2.so` shared library failed to load because `LD_LIBRARY_PATH` did not reliably propagate to the testhost subprocess. Fixed by PR #5563 (merged 2026-06-02), which added an explicit native-library resolver in `Tests/Linq/TestsInitialization.cs`.

- **DB2 DECFLOAT type mapping for special values** -- #5663 fixed mapping of DB2 `DECFLOAT` columns that hold IEEE 754 special values (`Infinity`, `-Infinity`, `NaN`). These values arise naturally from expressions like `RATIO_TO_REPORT()` and require double/float mapping instead of decimal. Fixed by PR #5669 (merged 2026-07-02).

- **DB2 test-suite data hygiene (AllTypes accumulation)** -- #5765 reported that the DB2 `AllTypes` table accumulated junk rows across test runs because `ResetAllTypesIdentity` never deleted on DB2. Addressed by PR #5784 (fixed tests leaving ~90k rows and reverted the ORDER BY workaround) and by #5754 (disabled AUTO_STMT_STATS in DB2 setup, roughly 3.7x faster tests).

- **DB2 identity column support with OVERRIDING SYSTEM VALUE** -- #4601 implemented support for SELECT INTO/INSERT operations with identity columns using DB2's `OVERRIDING SYSTEM VALUE` clause.

- **DB2 UPDATE with tuple assignment (SET clause)** -- #4696 documented the syntax for DB2's tuple assignment in UPDATE statements (`SET (col1, col2) = (val1, val2)`). The same question came in as discussion #4697 (closed).

- **IBM DB2 provider packaging and versions** -- Provider-assembly and package work over time: #3470 (IBM.Data.DB2 assembly load in the model generator, resolved external), #3478 and #3481 (support for the copy-paste IBM DB2 provider builds and updated dependencies), #5247 (LINQPad: enable DB2 iSeries).

- **DB2 iSeries parameter length metadata** -- #5826 (GLOBAL-tagged, closed 2026-08-29 with label `resolution: external`) reported that `UpCastDbDataTypeToFit` in the DB2 for IBM i provider overwrote a configured `[Column(DataType, Length)]` length for string and byte[] parameters, while decimal was respected. No linq2db change is recorded for it.

- **DB2 test-harness namespace decoupling** -- PR #6249 (merged 2026-11-07) removed hard references to the target DB2 namespace from the test code and routed them through the `DB2ProviderAdpater` implementation, so a downstream DB2 for IBM i provider can test against different versions of the DB2 ADO provider.

- **DB2 test-host exit crash at teardown** -- An intermittent DB2 test leg went red after the suite had printed its pass summary: the test host exited with code 139 (SIGSEGV) at process exit, per a core dump of a local reproduction, from the IBM client's exit handler. Test-only fix in PR #6073 (merged 2026-10-21), which purges the IBM DB2 connection pool at assembly teardown. No product change.

## Active discussions

- [DB2 testing and licensing](https://github.com/linq2db/linq2db/discussions/5127) -- [Q&A] Asks how the maintainers obtained IBM support for DB2 regression testing; open since 2025-09.
- [IBM iSeries get next value from sequence](https://github.com/linq2db/linq2db/discussions/5446) -- [Q&A] Asks how to call a sequence's NEXT VALUE FOR from a user-defined SQL-translatable function on DB2 for IBM i; index tags it EXPR-TRANS, content is DB2 iSeries.

## Stats
- Open issues: 8
- Closed issues: 25
- Open PRs: 0
- Total PRs: 28
- Discussions: 2
- Last fetched: 2026-11-11

<details><summary>Coverage</summary>

- Index entries scanned: 65 (34 issues + 28 PRs + 3 discussions)
- Themes extracted: 13 (4 open, 9 resolved)
- Stats count PROV-DB2-tagged items only. Content-matched and added: #5826 (GLOBAL tag), discussion #5446 (EXPR-TRANS tag). Cross-referenced and kept: #5989 (PROV-ACCESS), #6066 (SQL-PROVIDER).
</details>
