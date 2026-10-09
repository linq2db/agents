---
area: SQL-AST
kind: issues
sources: [gh-issues, gh-prs, gh-discussions]
confidence: medium
last_verified: 2026-10-10
last_verified_sha: 05150894edc2511f0dd0bc7829b2a309cec36ec9
---

# SQL-AST -- GitHub themes

## Open themes

- **Type information lost between translation and SQL emission** -- Expression type metadata is not carried on SQL nodes, so emission recovers it from column descriptors or schema defaults and can get it wrong. Open: #5758 (carry type mapping on SQL expressions instead of recovering it from ColumnDescriptor), #5960 (GetDbDataType discards a SqlExtendedFunction's declared type for the schema default), #5759 (TimeSpan members and comparisons on native interval columns).
- **Set operations and CTE column projection** -- Projection over set-operation members and CTE columns produces invalid or bloated SQL. Open: #5822 (recursive CTE with a UNION body emits invalid SQL when the projection computes over CTE columns), #5881 (chain of 3+ set operations pads members apart when a branch projects a derived type). Resolved siblings: #5617 (ordering of columns inside UnionAll), #5457 (6.x removes CTE columns).
- **Constant and redundant nodes reach the server** -- Expressions that should fold or reduce before emission are emitted as written, and the optimizer pass meant to catch them is costly. Open: #5851 (constant WITHIN GROUP / KEEP sort key reaches the server verbatim), #5963 (redundant non-mandatory SqlCastExpression built by a provider is not reduced), #5911 (whole-tree expression optimizer runs five times per build). Resolved sibling: #5806 (constant window ORDER BY emits a bare integer index).
- **Unclustered open items** -- Below the theme threshold, listed for coverage: #5853 (Output clause emits duplicate columns on providers without DELETED/INSERTED tables), #5965 (sub-day date functions over date-only / DATE / low-precision operands fail on SQL Server, Firebird, Oracle, DuckDB).

## Resolved themes

- **generated** -- 11 closed issues share this keyword. Sample: #395, #271, #100, #732, #437, #1721, #1709, #1777.
- **query** -- 8 closed issues share this keyword. Sample: #539, #271, #1338, #1799, #1946, #2288, #2405, #4349.
- **wrong** -- 7 closed issues share this keyword. Sample: #424, #539, #100, #982, #437, #1655, #1946.
- **join** -- 6 closed issues share this keyword. Sample: #175, #982, #1655, #1906, #2448, #2421.
- **oracle** -- 6 closed issues share this keyword. Sample: #539, #228, #732, #1939, #2526, #2204.
- **IN / EXISTS subquery conversion** -- Resolved by PRs #4196 (IN/EXISTS conversion), #5268 (IN subquery with DISTINCT optimization), #5522 (IN-to-EXISTS fix for set-based subqueries), #5582 (null-safe non-correlated NOT IN / IN emulation). Correlated Contains fixed in #5558.

## Active discussions

- No active discussions.

## Stats

- Open issues: 10
- Closed issues: 65
- Open PRs: 0
- Total PRs: 22
- Discussions: 0
- Last fetched: 2026-10-09

<details><summary>Coverage</summary>

- Index entries scanned: 97 (75 issues + 22 PRs + 0 discussions)
- Themes extracted: 9
</details>
