---
area: SQL-AST
kind: issues
sources: [gh-issues, gh-prs, gh-discussions]
confidence: medium
last_verified: 2026-10-21
last_verified_sha: 89b5ce16278728b9936ba374827fea002c76e962
---

# SQL-AST -- GitHub themes

## Open themes
- **Type information lost between translation and SQL emission** -- Expression type metadata is not carried on SQL nodes, so emission recovers it from column descriptors, schema defaults or a provider default, and can get it wrong. Open: #5758 (carry type mapping on SQL expressions instead of recovering it from ColumnDescriptor), #5960 (GetDbDataType discards a SqlExtendedFunction's declared type for the schema default), #5759 (TimeSpan members and comparisons on native interval columns), #6044 (attribute-built SQL reports the mapping schema's default type, not the value's), #6056 (a typed SqlBinaryExpression loses its DbDataType when a visitor rebuilds it), #6055 (remote context drops the DbDataType of binary and unary nodes; fix in draft PR #6057), #6064 (IN list beside an aggregate over a decimal column is written at the schema's default scale), #6079 (inline IN list values are typed through SUM and type-changing casts).
- **Literals and casts rendered at the wrong type** -- Date/time, decimal and cast text is written at a type or precision that differs from the operand, so comparisons and reads change without an error. Open: #5997 (date/time literal compared with a coarser column loses its sub-second part), #6078 (SQL Server datetime literal beside MAX or COALESCE of a datetime column is written as datetime2 and misses a read-back value), #6081 (SQLite and ClickHouse: a date column IN a list of datetime columns misses a match that == finds), #6049 (MySQL CAST to a date/time type drops fractional seconds), #6071 (text to date/time casts wrong on SQLite and Informix, no rows on YDB), #6062 (SqlCe compares a decimal literal at the other operand's scale), #6019 (DB2 recursive CTE anchor double-casts a DateTime literal; result unaffected, SQL longer than needed).
- **Null semantics of emitted predicates and casts** -- A predicate or cast that is UNKNOWN or folded away in SQL evaluates differently from the C# expression over NULL. Open: #6065 (DB2: a nullable equality ORed with another condition evaluates to UNKNOWN when compared as a value), #6066 (nullable inline-array Contains converted to a string returns NULL where C# returns "False"), #6070 (a narrowing numeric conversion followed by a widening back is dropped before SQL is built).
- **Calculations over missed LEFT JOIN rows** -- A calculation over a non-matching LEFT JOIN row is evaluated over SQL NULL, and the server rejects it or answers differently from C#. Open: #6046 (eager-load and CTE projections still calculate over NULL with PreferClientCalculation off), #6087 (math functions over a missed row throw "Nullable object must have a value" with the option on), #6088 (Sybase: DateTime and Sql.MakeDateTime over NULL parts raise a conversion error), #6089 (ClickHouse: decimal division by a missed row raises "Decimal convert overflow"). Projection calculations are fixed by #5983 (see resolved).
- **Set operations and CTE column projection** -- Projection over set-operation members and CTE columns produces invalid or bloated SQL. Open: #5822 (recursive CTE with a UNION body emits invalid SQL when the projection computes over CTE columns), #5881 (chain of 3+ set operations pads members apart when a branch projects a derived type), #6094 (Union or Concat of a lifted struct with a (T?)null branch builds no marker column for the null branch, and reading throws NullReferenceException), #6050 (Sybase: UNION of a date column with a datetime value truncates the datetime branch to a date). Resolved siblings: #5617 (ordering of columns inside UnionAll), #5457 (6.x removes CTE columns).
- **Subquery shape: apply joins, TOP and aggregate placement** -- Correlated subqueries, derived tables and aggregates are emitted in a shape the server rejects or evaluates differently. Open: #6032 (Access: uncorrelated TOP 1 ORDER BY column subquery with a nested correlated subquery returns per-row wrong values), #6034 (apply joins over set operations are never decorrelated, so they always need LATERAL / APPLY), #6047 (Access: GroupBy(...).Select(aggregate).Contains puts the aggregate in WHERE). Open draft PR #5900 (Sybase: TOP of a First() applied to the whole eager-load join) covers a related derived-table TOP case.
- **Identifier quoting and parameter naming** -- Names that reach generated SQL text, identifiers and parameters are not reliably quoted, escaped or kept unique. Open: #6022 (identifier passthroughs on seven providers and unescaped embedded quotes on nine; an injection vector when names come from runtime strings), #6023 (Sybase: empty field name throws IndexOutOfRangeException in SqlBuilder.Convert; open fix PR #6039), #6040 (an explicitly named DataParameter is renamed when a generated parameter claims its name first).
- **Constant and redundant nodes reach the server** -- Expressions that should fold or reduce before emission are emitted as written, and the optimizer pass meant to catch them is costly. Open: #5851 (constant WITHIN GROUP / KEEP sort key reaches the server verbatim), #5963 (redundant non-mandatory SqlCastExpression built by a provider is not reduced), #5911 (whole-tree expression optimizer runs five times per build). Resolved sibling: #5806 (constant window ORDER BY emits a bare integer index).
- **Unclustered open items** -- Below the theme threshold, listed for coverage: #5853 (Output clause emits duplicate columns on providers without DELETED/INSERTED tables), #5965 (sub-day date functions over date-only / DATE / low-precision operands fail on SQL Server, Firebird, Oracle, DuckDB), #6041 (YDB Math.Floor / Ceiling / Truncate over a decimal are computed through Double), #6063 (YDB decimal with Precision but no Scale is written through a Decimal(P, 0) parameter), #6072 (integer Sql.Degrees overloads keep the fraction where the engine's DEGREES returns a float), #6080 (a provider's refusal inside a projection filtered through AsSubQuery loses its reason), #6035 (ArgumentException "must be reducible node" for a correlated Select(anonymous).Distinct().Count(predicate) in a projection), #5787 (untranslatable aggregate selector inside a projection fails with "There is no method 'AggregateExecute'"; draft PR #5901 fixes it).
- **PR-only coverage (open, index-tagged to other areas)** -- #5949 (PostgreSQL FILTER gated on the 9.5 dialect tier), #5943 (YDB ROUND widens the scaled intermediate), #5982 (INSERT ... RETURNING as a composable query source, part of #5717), #5892 and #5913 (DateTimeOffset differences and time-zone handling, both drafts).

## Resolved themes
- **generated** -- 11 closed issues share this keyword. Sample: #395, #271, #100, #732, #437, #1721, #1709, #1777.
- **query** -- 8 closed issues share this keyword. Sample: #539, #271, #1338, #1799, #1946, #2288, #2405, #4349.
- **wrong** -- 7 closed issues share this keyword. Sample: #424, #539, #100, #982, #437, #1655, #1946.
- **join** -- 6 closed issues share this keyword. Sample: #175, #982, #1655, #1906, #2448, #2421.
- **oracle** -- 6 closed issues share this keyword. Sample: #539, #228, #732, #1939, #2526, #2204.
- **IN / EXISTS subquery conversion** -- Resolved by PRs #4196 (IN/EXISTS conversion), #5268 (IN subquery with DISTINCT optimization), #5522 (IN-to-EXISTS fix for set-based subqueries), #5582 (null-safe non-correlated NOT IN / IN emulation). Correlated Contains fixed in #5558. Cached-query mutation in the IN-to-EXISTS conversion fixed by #6007 (merged 2026-10-13). Stale SQL for a FromSqlScalar nested in IN (#6000) closed by #6003 (merged 2026-10-16).
- **Calculations over missed LEFT JOIN rows** -- Projection calculations read a missed NOT NULL column the way the reader does, as COALESCE(col, default(T)), in #5983 (merged 2026-10-21). Closes #5932 (non-nullable member reads as default(T) but NULL inside SQL calculations) and #5923 (Sql.ToNullable over a binary expression returned a value instead of NULL for a missed join).
- **Subquery validation on Oracle 11** -- #6024 (validator rejects IS NOT NULL on a column subquery's own table as a parent reference) fixed by PR #6027 (merged 2026-10-12).
- **Union over shared value converter class** -- #6052 (6.5.0 Union over columns that share a ValueConverter class threw ArgumentException) fixed by #5978 (6.5.1); the shape is covered by the regression test in PR #6060 (merged 2026-10-16).
- **Raw SQL arguments never referenced by the format** -- PR #6008 (merged 2026-10-19): an argument the format never references is replaced with NULL and no longer registers a parameter; Sybase ASE rejected the extra parameter.

## Active discussions
- No active discussions.

## Stats
- Open issues: 12
- Closed issues: 65
- Open PRs: 0
- Total PRs: 22
- Discussions: 0
- Last fetched: 2026-10-21

<details><summary>Coverage</summary>

- Index entries scanned: 99 (77 issues + 22 PRs + 0 discussions); incremental delta reviewed: 63 issues + 65 PRs fetched since 2026-10-09
- Themes extracted: 8 open clusters + 1 unclustered list + 1 PR-only list
- Open PRs of 0 is the index tag count; PR citations above are items the index tags to other areas
</details>
