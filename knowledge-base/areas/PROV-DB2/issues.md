---
area: PROV-DB2
kind: issues
sources: [gh-issues, gh-prs, gh-discussions]
confidence: medium
last_verified: 2026-10-10
last_verified_sha: 05150894edc2511f0dd0bc7829b2a309cec36ec9
---

# PROV-DB2 -- GitHub themes

## Open themes

- **DB2 string type handling edge cases** -- #2362 describes rows being skipped when a VARCHAR column contains an empty string (mapped via value converter). The issue affects querying with value converters where empty strings need to be distinguished from NULL.

- **DB2 numeric and floating-point semantics** -- Floating-point results on DB2 diverge from other providers. #5897 reports `RATIO_TO_REPORT` returning `Infinity` on a zero partition sum where other providers return NULL. #5994 reports a `double` parameter added to an integer column losing its fraction because the C# cast is dropped and DB2 types the parameter from the column; the same expression with the column on the left keeps `CAST(... AS Float)`. The special-value mapping work in #5663 (resolved below) is the adjacent fix.

- **DB2 DateTime difference read back as TIME** -- #5989 (tagged PROV-ACCESS, but the same defect affects DB2 and Firebird) reports that a projected difference of two local `DateTime` values is returned as TIME: Access fails and DB2 truncates the value. Area ownership is still with PROV-ACCESS; the DB2 symptom is cross-referenced here until reclassified.

## Resolved themes

- **DB2/Informix native client loading on Linux/macOS** -- #5538 tracked transient failures where the native `libdb2.so` shared library failed to load because `LD_LIBRARY_PATH` did not reliably propagate to the testhost subprocess. Fixed by PR #5563 (merged 2026-06-02), which added an explicit native-library resolver in `Tests/Linq/TestsInitialization.cs`.

- **DB2 DECFLOAT type mapping for special values** -- #5663 fixed mapping of DB2 `DECFLOAT` columns that hold IEEE 754 special values (`Infinity`, `-Infinity`, `NaN`). These values arise naturally from expressions like `RATIO_TO_REPORT()` and require double/float mapping instead of decimal. Fixed by PR #5669 (merged 2026-07-02).

- **DB2 test-suite data hygiene (AllTypes accumulation)** -- #5765 reported that the DB2 `AllTypes` table accumulated junk rows across test runs because `ResetAllTypesIdentity` never deleted on DB2. Addressed by PR #5784 (fixed tests leaving ~90k rows and reverted the ORDER BY workaround) and by #5754 (disabled AUTO_STMT_STATS in DB2 setup, roughly 3.7x faster tests).

- **DB2 identity column support with OVERRIDING SYSTEM VALUE** -- #4601 implemented support for SELECT INTO/INSERT operations with identity columns using DB2's `OVERRIDING SYSTEM VALUE` clause.

- **DB2 UPDATE with tuple assignment (SET clause)** -- #4696 documented the syntax for DB2's tuple assignment in UPDATE statements (`SET (col1, col2) = (val1, val2)`).

- **IBM DB2 provider packaging and versions** -- Provider-assembly and package work over time: #3470 (IBM.Data.DB2 assembly load in the model generator, resolved external), #3478 and #3481 (support for the copy-paste IBM DB2 provider builds and updated dependencies), #5247 (LINQPad: enable DB2 iSeries).

## Active discussions

- [DB2 testing and licensing](https://github.com/linq2db/linq2db/discussions/5127) -- [Q&A] Asks how the maintainers obtained IBM support for DB2 regression testing; open since 2025-09.

## Stats
- Open issues: 3
- Closed issues: 25
- Open PRs: 0
- Total PRs: 26
- Discussions: 2
- Last fetched: 2026-10-10

<details><summary>Coverage</summary>

- Index entries scanned: 56 (28 issues + 26 PRs + 2 discussions)
- Themes extracted: 9 (3 open, 6 resolved)
</details>
