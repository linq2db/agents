---
area: SQL-PROVIDER
kind: issues
sources: [gh-issues, gh-prs, gh-discussions]
confidence: high
last_verified: 2026-10-21
last_verified_sha: 89b5ce16278728b9936ba374827fea002c76e962
---

# SQL-PROVIDER -- GitHub themes

## Open themes

- **Identifier quotation and escaping edge cases** -- Multiple providers lack proper identifier quotation logic, causing SQL errors when identifiers contain special characters. General issue (#1510) tracks cross-provider gaps; Access-specific issue (#3893) addresses backtick and reserved-character escaping per SQL/OLE DB standard. #6022 (open) extends the class: seven providers pass a name through verbatim when it already starts with their opening quote, and nine wrap a name without escaping an embedded closing quote. With identifier names taken as runtime strings this is an injection vector. #6023 (open) is the Sybase builder variant: `SybaseSqlBuilder.Convert` checks the builder's own `Name` before reading `value[0]`, so an empty field name throws. PR #6039 (open, external) fixes the empty-name case with a regression test. Issues: #1510, #3893, #6022, #6023. PRs: #6039.

- **Operator precedence and SQL generation** -- SQL expression precedence table at `Source/LinqToDB/SqlQuery/Precedence.cs` is hardcoded and applied uniformly across all providers, but each SQL dialect defines its own operator precedence. Mismatch causes unnecessary brackets in generated SQL. TODO comment acknowledged but no prior tracking. Issues: #5527.

- **Complete INSERT and UPSERT operations coverage** -- Epic issue (#2558) tracking design and incremental implementation of various INSERT forms including UPSERT, excluding bulk operations. Aims to translate merge API calls to provider-specific UPSERT variants (e.g., `INSERT ... ON DUPLICATE KEY UPDATE` for MySQL, `INSERT ... ON CONFLICT` for PostgreSQL, native MERGE for SQL Server). Phase 1 of #5717 (draft PR #5982) exposes `INSERT ... RETURNING` rows as a composable PostgreSQL source. Issues: #2558. PRs: #5982.

- **DDL and schema management helper extensions** -- Three related requests: table-existence detection (#506) seeks efficient check without full schema enumeration; comprehensive CreateTable type coverage (#749) needs test suite covering all supported column types per provider; convenience helpers (#1201) request ColumnExists/AddColumn fluent extensions replacing try-catch patterns. Issues: #506, #749, #1201.

- **Advanced SQL features (PIVOT/UNPIVOT, Regex)** -- Two unrelated advanced features: PIVOT/UNPIVOT support (#1475) requires per-provider implementation (SQL Server PIVOT, Oracle UNPIVOT, PostgreSQL tablefunc extension, MariaDB CONNECT, etc.). Draft PR #5708 adds `SelectDynamic`, `Pivot` and `Unpivot` lowered to portable SQL on every provider; native PIVOT/UNPIVOT emission was measured on DuckDB, SQL Server 2017 and Oracle 23 and is not implemented in that PR. Regex support (#698) needs translation of LINQ Regex.IsMatch to provider-specific regex operators (LIKE for SQLite, REGEXP for MySQL/PostgreSQL, REGEXP_LIKE for Oracle, etc.). Issues: #1475, #698. PRs: #5708.

- **Sql.Function attribute generics support** -- Feature request (#326) to allow provider-specific function overloads based on generic type parameters. Currently Sql.Function supports per-provider and per-TFM selection but not per-generic-instantiation, requiring users to create multiple concrete wrapper methods instead of one generic template. Related: #5953 (open) -- a `Sql.Property` name computed from a lambda parameter fails with an undiagnosed exception, which blocks the natural spelling for per-entry predicates. Issues: #326, #5953.

- **Date/time literal, cast and comparison typing** -- Date/time values reach SQL with the wrong type or precision on several providers. A literal compared with a coarser column loses its sub-second part (#5997). MySQL `CAST(x AS DATETIME)` ignores precision (#6049). A Sybase UNION of a `date` column with a `datetime` value truncates the datetime to midnight (#6050). SQL Server writes a literal beside a computed datetime as `DATETIME2FROMPARTS`, and a stored value read back then fails to match (#6078). SQLite and ClickHouse miss a match when a date column is compared IN a list of datetime columns (#6081). Text-to-date/time casts are wrong on SQLite and Informix and return no rows on YDB (#6071). Sybase raises on a DateTime built from NULL parts (#6088). ClickHouse epoch functions need DateTime64 operands; PR #5959 (open) coerces them. SQLite DateTimeOffset arithmetic that keeps offsets is PR #5931 (open). Issues: #5997, #6049, #6050, #6071, #6078, #6081, #6088. PRs: #5931, #5959.

- **Decimal scale in literals and parameters** -- Decimal literals and parameters take the wrong scale. SqlCe compares a decimal literal at the other operand's scale, so 1.004 matches a decimal(18,2) value of 1.00 where a parameter does not (#6062). YDB writes a decimal mapped with Precision but no Scale through a Decimal(P, 0) parameter, so fractional values fail on a parameterized write (#6063). A captured IN list beside an aggregate over a finer decimal column is written at the mapping schema's default scale (#6064). The cause is the same in each: the scale comes from the schema default rather than the operand or the column.

- **DbDataType lost when expressions are rebuilt, serialized or typed by a default** -- The node's DbDataType (DataType, length, precision, scale) is dropped in four places. A Transform-mode visitor that rebuilds a SqlBinaryExpression keeps only the CLR type, so a non-mandatory narrowing cast is folded away (#6056). LinqServiceSerializer sends binary and unary nodes with the CLR type only, so remote SQL differs from direct SQL and YDB can produce invalid SQL; fix in draft PR #6057 (#6055). Attribute-built SQL takes the mapping schema default for the member's CLR type (#6044). IN values are typed through SUM and type-changing casts (#6079). Issues: #6044, #6055, #6056, #6079. PRs: #6057.

- **Query-cache SQL reuse with captured values** -- Cached SQL is replayed when a value that changes the text is not part of the cache key. A compiled query reuses its first build when a raw SQL format or closure argument changes (#6045). `[SqlQueryDependent]` values that are Equals-equal but render differently share one entry (#6059). A cached second execution of a grouped `MAX(CASE ... THEN string ...)` maps the column as byte[] (#6028). Queries with a constant TAKE/SKIP are rebuilt on every execution; PR #6033 (open) caches their command text. The nested FromSql/Sql.Expr case is resolved (see Resolved themes). Issues: #6028, #6045, #6059. PRs: #6033.

- **Numeric function and conversion precision** -- Numeric values lose precision or are truncated during translation. YDB Math.Floor, Math.Ceiling and Math.Truncate over decimal go through Double and return the wrong integer for values with more than 15 to 17 significant digits (#6041). The integer Sql.Degrees overloads keep the fraction in SQL where the engine's DEGREES returns a float (#6072). A narrowing `(int)x` over a double, followed by a widening back, is dropped before SQL is built (#6070). YDB ROUND emulation that overflows the declared precision is fixed in PR #5943 (open). Issues: #6041, #6070, #6072. PRs: #5943.

## Resolved themes

- **Provider customization barriers (mostly addressed)** -- Long-standing issue: ISqlBuilder and related builder classes were internal, blocking custom provider extensions. Fixed by making classes public (#347, #144, #156, #182, #58). Later refactoring (#4948) removed ISqlBuilder interface entirely to simplify maintainability. Fixed via #4948.

- **Type mapping and conversion edge cases** -- Historical issues with TimeSpan/DateTimeOffset literal generation (#149), anonymous type filtering (#2769), string/nullable coercion (#2746), custom type mappings (#3821). Most resolved case-by-case via converter overrides or type-specific builder fixes. Issues: #149, #2769, #2746, #3821.

- **ASP.NET Core DI registration problems** -- Multiple context registration (#3527, #4077, #4326), scoped lifetime issues (#2507, #3623), and DataOptions type selection bugs (#4326, #5024, #5041). Fixed incrementally through RC cycles and preview versions, now stabilized. Fixed via #4406.

- **Nested raw SQL in the query cache (stale SQL)** -- A FromSql, FromSqlScalar or Sql.Expr call nested in a query reused the first execution's SQL, because the cache compared its raw-SQL argument structurally while the builder evaluated the format at build time. Fixed by PR #6003 (merged 2026-10-16), closing #6000 and #5857. Follow-ups merged the same week: PR #6007 stops IN-to-EXISTS conversion from mutating the cached query, and PR #6008 drops raw SQL arguments the format never references (Sybase rejected them). Issues: #5857, #6000. PRs: #6003, #6007, #6008.

- **Oracle 11 column-subquery validator false positive** -- The validator rejected `IS NOT NULL` on a column subquery's own table as a parent reference, before any SQL was sent. Closed by #6024 (2026-10-12) and fixed by PR #6027 (merged). Issues: #6024. PRs: #6027.

## Active discussions
No active discussions in this area.

## Unclustered recent items
Not themed: below the three-item threshold or outside the recurring topics above. Listed so they stay visible.
- #6019 -- DB2 recursive CTE anchor double-casts a DateTime literal.
- #6031 -- SQLite DateTimeOffset columns read through GetDateTime; offset lost, MaxValue throws.
- #6032 -- Access: uncorrelated TOP 1 ORDER BY column subquery with nested correlated subquery returns per-row wrong values.
- #6034 -- Decorrelate apply joins over set operations.
- #6040 -- Explicitly named DataParameter is renamed when a generated parameter claims its name first.
- #6047 -- Access: GroupBy(...).Select(aggregate).Contains(value) puts the aggregate in WHERE.
- #6065 -- DB2: nullable equality ORed with another condition evaluates to UNKNOWN when compared as a value.
- #6066 -- Nullable inline-array Contains converted to a string returns NULL where C# returns "False".
- PR #5949 -- Gate PostgreSQL FILTER on the 9.5 dialect tier (open).


## Stats
- Open issues: 13 (index area tag SQL-PROVIDER; the tag is lossy, so treat as a floor)
- Closed issues: 37 (same basis)
- Open PRs: 8 cited in themes above (#5708, #5931, #5943, #5959, #5982, #6033, #6039, #6057; drafts: #5708, #5982, #6057); index area tag yields 0
- Total PRs: 18 (index area tag SQL-PROVIDER)
- Discussions: 0
- Last fetched: 2026-10-21

<details><summary>Coverage</summary>

- Index entries scanned: 68 (50 issues + 18 PRs + 0 discussions, by area tag)
- Fetched items screened by content: 128 (63 issues + 65 PRs) from kb-refresh-fetch-issues.json and kb-refresh-fetch-prs.json
- Themes extracted: 16 (11 open + 5 resolved)
- Unclustered recent items: 9
</details>
