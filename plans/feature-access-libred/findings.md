# LibRed — measured capability report

All facts below were **measured** with `.build/.agents/libred-probe` (net11.0, SDK
11.0.100-rc.1.26425.128) against real Access files, never inferred from release notes. A probe always
operates on a **copy** of the database.

- **alpha.2**, 2026-09-19, against `.accdb` files LibRed created itself. Raw logs: `smoke-accdb.txt`,
  `battery-accdb.txt`, `schema-accdb.txt`, `access-sql-accdb.txt`, `sig.txt`.
- **alpha.2, second round**, 2026-09-22 — the sections dated *(2026-09-22)* below, measured after the first
  full test-suite run against the suite's own populated `TestData.LibRed.mdb`. These are the ones five
  rounds of raw-ADO probing could not have found, because they are not capability questions: the construct
  parses, executes, and returns the wrong answer.
- **alpha.3**, 2026-09-22, the section immediately below. Where a behaviour changed, the *same* battery was
  run against both package versions rather than compared against notes, so every "regressed" verdict is a
  diff of two measurements.

Packages: `LibRed.Ado` → `LibRed.Engine` → `LibRed.Core`, `LibRed.Sql`, `Antlr4.Runtime.Standard`.
`net11.0` only.

---

# alpha.3 (2026-09-22)

## Regressions against alpha.2

### 1. The reader contradicts itself on a computed column

The most consequential of the three, because nothing in the SQL is unusual and there is no error until
materialization. For a projection over a `CURRENCY` aggregate:

```sql
SELECT IIF([t3].[x] < 0, 9, [t3].[x] + 8), [t3].[x] + [t3].[x]
FROM (SELECT IIF([t2].[x] IS NULL, 0, [t2].[x]) AS [x]
      FROM (SELECT (SELECT SUM([MoneyValue]) FROM [LinqDataTypes]) AS [x]
            FROM [LinqDataTypes] [q]) [t2]) [t3]
```

```
alpha.2   reader: Expr1 GetFieldType=Decimal   value: Expr1 [13] (Decimal)     <- consistent
          reader: Expr2 GetFieldType=Decimal   value: Expr2 [10] (Decimal)
alpha.3   reader: Expr1 GetFieldType=Int32     value: Expr1 [13] (Int32)
          reader: Expr2 GetFieldType=Int32     value: Expr2 [10] (Decimal)     <- declared Int32, returns Decimal
```

`GetSchemaTable` agrees with `GetFieldType` (`DataType = Int32`, `DataTypeName = Long`), so **every**
description of `Expr2` says `Int32` while the value handed back is a `Decimal`. A consumer that compiles a
materializer from the declared type — which is what every ORM does — emits an `Int32` read and fails with
`Unable to cast object of type 'System.Decimal' to type 'System.Int32'`. Note `Expr1` *does* honour the
declared type in the same row set, so the "every value is returned in its column's declared type" change
appears to have landed only partway.

Nullability is **not** involved: `AllowDBNull` is reported correctly for every expression column (`True`
for aggregates, arithmetic and `IIF`; `False` only for a stored `NOT NULL` column). That was the first
hypothesis and the probe refuted it.

Cost in the linq2db suite: 6 failures. A fourth cluster of 4 (`Byte array for Guid must be exactly 16 bytes
long`, on a set operation carrying null literals) is plausibly the same family but is not proven here.

### 2. A text column compared against a numeric literal now throws

Measured on a `VARCHAR` column holding `''`, `'abc'`, `'11'`:

| Query | alpha.2 | alpha.3 |
|---|---|---|
| `SELECT COUNT(*) FROM t WHERE [S] = 11` | `1` | `InvalidCastException: Type mismatch: '' cannot be read as a number` |
| `… WHERE [S] IN (11, 18, 19)` | `1` | throws, same message |
| `… WHERE [S] NOT IN (11, 18, 19)` | `2` | throws — and on a row holding `'abc'` too, so it is not only the empty string |
| control: `… WHERE [S] NOT IN ('11', '18')` | `2` | `2` |

ACE evaluates all three. A `NOT IN` list of numbers against a string column is ordinary generated SQL, so
no caller can route around it. Cost in the linq2db suite: 4 failures.

### 3. Breaking, but in the corrective direction

| Behaviour | alpha.2 | alpha.3 |
|---|---|---|
| GUID literal vs a `GUID` column | unbraced `'xxxxxxxx-…'` matches; braced matches **0 rows** | braced `'{xxxxxxxx-…}'` matches; unbraced matches **0 rows** |
| `CStr(<guid>)` | unbraced, `Len` 36 | braced, `Len` 38 |

Both now agree with ACE, which is the right end state — but they silently invert results for code written
against alpha.2, with no error. Two workarounds in the linq2db provider had to be **deleted** rather than
merely retired, because on alpha.3 they produced wrong answers.

## Fixed in alpha.3 (re-measured, not taken from the notes)

`GetSchemaTable` / `IDbColumnSchemaGenerator` implemented, with correct `AllowDBNull` · `GetDataTypeName`
returns the store type (`Char`, `VarChar`, `LongText`, `Long`) instead of CLR names · `PRIMARY KEY
CLUSTERED` accepted · trailing `IDENTITY` accepted, and the column really is an identity · bare
`REFERENCES <table>` resolves to the parent's primary key · all five previously-rejected `CREATE Procedure`
shapes create, and `CommandType.StoredProcedure` executes them · `CommandBehavior.SchemaOnly` honoured —
describing `Person_Insert` / `Person_Update` / `Person_Delete` / `AddIssue792Record` leaves the row counts
untouched · `ORDER BY n` is an ordinal · comma-joined and derived-table `UPDATE`/`DELETE` parse · `DATEADD`
returns a `DateTime` · date parts return `Int32` · a multi-column `SET` is evaluated against the pre-update
row · `cdbl(-9223372036854775808)` evaluates. The full ADO metadata surface (20 collections) is present and
is a superset of `[INFORMATION_SCHEMA.*]` on every fact a schema reader needs except `CreateFormat`.

## Still open on alpha.3 — the consolidated list

Everything below reproduces on 11.0.0-alpha.3 and is ordered by how much it costs a consumer, not by when
it was found. The three at the top are the ones a caller cannot route around; the rest are dialect gaps
where an ORM can at least tell what happened. Where a row also existed on alpha.2 it is unchanged unless
the "changed" column says otherwise.

| # | Behaviour | Minimal repro | Why it costs | Changed on alpha.3 |
|---|---|---|---|---|
| R1 | A computed column is **declared one type and returned as another**: `GetFieldType` and `GetSchemaTable` say `Int32`/`Long`, `GetValue` hands back a `Decimal` | `SELECT [t].[x] + [t].[x] FROM (SELECT IIF(… IS NULL, 0, …) AS [x] FROM (SELECT (SELECT SUM([MoneyValue]) FROM [LinqDataTypes]) AS [x] FROM [LinqDataTypes]) [t2]) [t]` | every ORM compiles its materializer from the declared type; the read then throws `Unable to cast object of type 'System.Decimal' to type 'System.Int32'`. Silent until materialization | **regression** — alpha.2 said `Decimal` and was consistent |
| R2 | A **text column compared to a numeric literal** throws instead of evaluating | `SELECT COUNT(*) FROM t WHERE [S] NOT IN (11, 18)` where `S` is `VARCHAR` holding `''` or `'abc'` → `InvalidCastException: Type mismatch: '' cannot be read as a number` | ACE evaluates it; a `NOT IN` list of numbers against a string column is ordinary generated SQL | **regression** — alpha.2 returned rows |
| R3 | A `PARAMETERS` clause **Access wrote** comes back quoted and is then re-emitted double-quoted, after which it no longer parses | see the dedicated section above — `PARAMETER_NAME` = `[@firstName]`, `PROCEDURE_DEFINITION` = `PARAMETERS [[@firstName]] TEXT(50); …` | a parameterised stored query in an ACE-written file can be neither described nor executed; scaffolding degrades it to a non-query | new — procedures could not be created at all on alpha.2 |
| R4 | An **indexed `GUID` column** cannot be compared to a string literal, nor have one inserted | `CREATE INDEX … ON t([G]); SELECT … WHERE [G] = '{…}'` → `NotSupportedException: Cannot encode GUID index key from String` | an internal encoder failure rather than a dialect refusal; both brace forms and `INSERT` are affected | no — alpha.2 refused these identically |
| R5 | `DATETIME` keeps **sub-second precision** Access truncates | parameter round-trip of `09:44:34.653` reads back with the milliseconds | round-trips through LibRed disagree with round-trips through the Microsoft drivers on the same file | no |
| R6 | `GetDateTime` returns `DateTime.MinValue` for the **Jet zero date** while `GetValue` returns it correctly | the `DateSerial(1899, 12, 30)` row; `IsDBNull` is `False` and `AllowDBNull` is `False`, so nothing else flags it | the two accessors disagree on the same cell | **re-scoped** — the recorded "reads back as MinValue" was measured at the wrong layer |
| R7 | `CVar` is a **no-op** | `SELECT CVar(1)` → typed `Int32` `1`, not a Variant reading back as `"1"` | the function exists to produce a Variant | no |
| R8 | Missing-object errors are **untyped and inconsistent** | `SELECT` → `SqlBindException "… does not exist."`; `DROP TABLE`/`DROP PROCEDURE` → bare `InvalidOperationException "… no such table."`; no `Number` on either | every caller must match on message text, and a bare `InvalidOperationException` is indistinguishable from a client-side bug | no |
| R9 | No **database-qualified table name** in any form | `[<file>].[T]`, `[<file-no-ext>].[T]`, `[<file>]..[T]`, `FROM [T] IN '<file>'` all fail | cross-database queries are unreachable | no |
| R10 | A **parameterised stored SELECT** cannot be a table source | `SELECT * FROM [Person_SelectByKey]` | Access permits it | error moved from `SqlParseException` to `InvalidOperationException: No value was supplied for parameter '@id'` |
| R11 | `IS TRUE` / `IS FALSE` / `IS [NOT] DISTINCT FROM` do not parse | `WHERE ([Id] = 1) IS TRUE` → `mismatched input 'TRUE' expecting {NOT, NULL}` | ordinary dialect gap | no |
| R12 | `WITH OWNERACCESS OPTION`, `CAST(x AS t)`, `LIKE … ESCAPE`, `TOP n WITH TIES`, `VALUES` as a table source, `{ts …}` / `{guid …}` escapes, `NZ()` do not parse | each is a one-line `SELECT` | lowest priority — linq2db emits none of them for Access except the hint | no |
| R13 | `IIF` / `CASE` is **typed by the branch it takes** | `1000 - IIF([t1].[Sum_1] IS NULL, 0, [t1].[Sum_1])` (and, since the dialect branch emits CASE, `1000 - CASE WHEN [t1].[Sum_1] IS NULL THEN 0 ELSE [t1].[Sum_1] END` — re-measured 2026-09-24) over an `OUTER APPLY` whose `SUM` covers no rows returns the `0` literal's `Int32` where the column is the aggregate's `Decimal`/`Double`/`Single` → `InvalidCastException` in the materializer | ACE unifies the branches; linq2db emits exactly this shape for a coalesced empty aggregate (`AggregationNullabilityTests.Sum*SubqueryEmpty`, gated) | found on `feature/access-libred-dialect` |
| R14 | `NTH_VALUE` **ignores the default frame** | `NTH_VALUE([p].[Id], 2) OVER (ORDER BY [p].[Order] DESC)` gives the first row the partition's second value instead of NULL (default frame is `RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW`) | silent wrong result (`AnalyticTests.Issue1732NthValue`, gated) | found on `feature/access-libred-dialect` |

**Not defects, recorded so they are not re-reported:** an unterminated `LIKE` bracket (`LIKE '[0'`) raises
`ArgumentException: Invalid pattern string` — Access rejects it too, through its own drivers, so LibRed
agrees; and `CLng` being 32-bit is VBA's `Long`, not a narrowing bug.

## Two corrections to the alpha.2 report below

- **The Access zero date.** Recorded as "reads back as `DateTime.MinValue`". Measured on alpha.3 — and the
  layer matters — 1899-12-30 round-trips correctly through a parameter, through a `#1899-12-30#` literal
  *and* through `DateSerial(1899, 12, 30)`, which is what linq2db emits. The loss is in the typed read
  alone: on the row whose serial is `0.0`, `GetValue` returns `12/30/1899` and **`GetDateTime` returns
  `01/01/0001`**. `IsDBNull` is `False` and `AllowDBNull` is `False`, so nothing else flags it.
- **`NZ()`** was reported as working in one alpha.3 round. It is not, on either version — that probe ran the
  statement with `ExecuteNonQuery`, which never evaluates the projection. A false positive of the probe,
  not a capability.

## A `PARAMETERS` clause Access wrote comes back double-quoted, and then will not parse

Found by diffing the CLI-scaffolded model against the one the OLE DB flavour produces from the *same*
database, which is the case this provider exists for: a file Microsoft's engine wrote.

`Data/TestData.mdb` (ACE-written) against `TestData.LibRed.mdb` (same queries, written through LibRed):

```
ACE-written     PARAMETER_NAME = [@firstName]      <- the [ ] quoting is part of the reported name
                PROCEDURE_DEFINITION = PARAMETERS [[@firstName]] TEXT(50), [[@lastName]] TEXT(50); SELECT ...
                describe with '@firstName'   -> SqlParseException: token recognition error at: ']'
                describe with '[@firstName]' -> SqlParseException: token recognition error at: '@['
LibRed-written  PARAMETER_NAME = @firstName
                PROCEDURE_DEFINITION = PARAMETERS [@firstName] TEXT(50), [@lastName] TEXT(50); SELECT ...
                describe with '@firstName'   -> 6 columns
```

Two consequences, one of which has no client-side remedy:

- the reported parameter name cannot be used to bind — it names a parameter no query declares. A consumer
  can strip the quoting, and this branch does.
- the re-emitted definition is **double-quoted and unparseable**, so a parameterised stored SELECT in an
  ACE-written file cannot be described or executed by any spelling of the name. Scaffolding therefore
  degrades it from a result-returning query to a non-query: `ExecuteProc` returning `int` where the OLE DB
  flavour produces `QueryProc<…Result>` with a generated result class.

The declared name really is `@id`, with `[ ]` as Access's identifier quoting — `CREATE Procedure
Person_SelectByKey([@id] Long)` is what this repo's own create script writes. So the read path appears to
take the quoted token as the name rather than unquoting it, and the write path then quotes it again.

## Stored-procedure parameters bind **by name**

New on alpha.3, since procedures could not be created before. `CommandType.StoredProcedure` resolves
arguments by parameter name and raises `InvalidOperationException: No value was supplied for parameter
'@MiddleName'` when the caller's names differ from the declaration. Microsoft's OLE DB and ODBC providers
bind Access stored-query parameters **positionally** and ignore the names entirely, so callers written
against them commonly pass arbitrary names — the linq2db suite had three such helpers, one with a
misspelling (`midleName` against a declared `[@MiddleName]`) that had never mattered. Not wrong of LibRed,
but it is a portability trap worth documenting: the by-name contract is invisible until it fails.

Also worth noting for consumers: a parameter declared **bracketed** (`[@id]`) keeps the `@` in
`GetSchema("ProcedureParameters")`, while one declared bare (`@id`) comes back as `id`.

---

# alpha.2

## ADO.NET surface (`LibRed.Data`)

Standard shapes: `LibRedConnection/Command/DataReader/Parameter/ParameterCollection/Transaction/Factory/ConnectionStringBuilder/Exception`.

- `LibRedFactory.Instance` exists (DbProviderFactory).
- Connection string: **`Data Source=<file>` only**. No other keywords; no SQL-mode keyword.
- `static void LibRedConnection.CreateDatabase(string connectionString, Collation? collation = null, JetVersion version = Version12_2007)`
- `static bool DatabaseExists(string)`, `static void DropDatabase(string)`, `static string GetConnectionString(string fileNameOrConnectionString)`, `static void ClearPool(LibRedConnection)`, `bool HasUserTables()`
- `JetVersion = Version3, Version4, Version12_2007, Version14_2010, Version15_2013, Version16_2016, Version17_2019`.
  `Version4` → `.mdb`; `Version12_2007`+ → `.accdb`. **`Version3` (Access 97) throws** on create.
- `LibRedException.Number`, with `DuplicateKey = 2627`, `ObjectAlreadyExists = 2714` (SQL-Server-style codes).
- `LibRedTransaction` supports savepoints (`Save`/`Rollback(name)`/`Release`).
- `ServerVersion` returns the `JetVersion` name, e.g. `Version12_2007`.

**No `LibRedSqlMode`.** The `Compatible` vs extended mode described in EFCore.Jet#292 does not exist in
alpha.2 — the parser always accepts the extended dialect.

## Parameters

- **Named only.** `?` → `NotSupportedException: Positional ('?') parameters are not supported yet; use named (@name) parameters.`
- `@name` works; the same parameter may be referenced twice in one statement; a parameter name given
  **without** the `@` prefix still binds.
- `SELECT TOP @n ...` accepted (parameterised TOP).
- 5 000 parameters in one `IN (...)` list executed fine (38 934-char command text).

## SQL — accepted

DDL: `CREATE TABLE` with `COUNTER`, inline `CONSTRAINT … PRIMARY KEY`, `ALTER TABLE … ADD CONSTRAINT …
PRIMARY KEY/FOREIGN KEY`, `CREATE [UNIQUE] INDEX`, `DROP INDEX … ON …`, `CREATE VIEW`,
`ALTER TABLE … ALTER COLUMN [Id] COUNTER(1, 1)` (linq2db's identity reset after TRUNCATE).

DML/queries: `INSERT … VALUES` (incl. multi-row), `INSERT … SELECT`, `SELECT … INTO`, `UPDATE`,
`UPDATE t1 INNER JOIN t2 ON (…) SET …` (Access-style update-with-join), `DELETE [p].* FROM …`,
`SELECT 1` with no `FROM`, `TOP n`, `TOP n PERCENT`, parenthesized nested joins with parenthesized `ON`,
comma joins + `WHERE`, `UNION`/`UNION ALL`, `INTERSECT`, `EXCEPT`, `FULL JOIN`, `CROSS APPLY`,
derived tables, correlated `COUNT(*)` subqueries, set operations inside `EXISTS`, `ROW_NUMBER() OVER`,
`OFFSET … FETCH`, `GROUP BY … HAVING`, `DISTINCT`.

Literals/operators: `#yyyy-MM-dd HH:mm:ss#`, `0x0102` hex, `'…'` strings, `&` and `+` concat,
`MOD`, `BAND`, `BOR`, `^`.

Functions: `IIF`, `SWITCH`, `ISNULL`, `COALESCE`, `NULLIF`, `LCASE`, `UCASE`, `LEN`, `MID`, `INSTR`
(4-arg, both compare modes), `STRING`, `LTRIM`, `TRIM`, `CHR`, `CSTR`, `CINT`, `CDBL`, `CBOOL`,
`CDATE`, `CSNG`, `CVAR`, `ROUND`, `INT`, `FIX`, `ABS`, `SGN`, `SQR`, `EXP`, `LOG`, `NOW`, `DATE`,
`DATESERIAL`, `TIMEVALUE`, `DATEVALUE`, `DATEPART`, `DATEADD`, `DATEDIFF`, `@@IDENTITY`.

LIKE: **both** `%`/`_` and `*`/`?` wildcards are accepted, and `[…]` bracket escaping works — which is
exactly the escaping strategy `AccessSqlExpressionConvertVisitor` already uses.

GUID: a `Guid` parameter round-trips (read back as `Guid`), and an **unbraced** `'xxxxxxxx-…'` string
literal compares equal to a GUID column. The **braced** form `'{xxxxxxxx-…}'` — which is what the base
`AccessMappingSchema.cs:30` emits, and therefore what the ODBC leaves inherit — parses without error
and matches **zero rows**: `braced=0 unbraced=1` against the same row. A silent wrong-results shape,
not an exception.

## Reader type names, and CHAR padding

`GetDataTypeName` reports **CLR** names, not Access store types, so the fixed-width type cannot be
identified at read time:

```
C=String, VC=String, M=String, I=Int32, D=Double, CU=Decimal, DEC=Decimal, B=Boolean,
G=Guid, BIN=Byte[], DT=DateTime, BY=Byte, S=Int16, SI=Single
```

for columns declared `CHAR(1)`, `VARCHAR(50)`, `MEMO`, `INT`, `DOUBLE`, `CURRENCY`, `DECIMAL(18,4)`,
`BIT`, `GUID`, `LONGBINARY`, `DATETIME`, `BYTE`, `SMALLINT`, `SINGLE`. `[INFORMATION_SCHEMA.COLUMNS]`
*does* carry the store type for the same table (`char`, `varchar`, `longchar`, `integer`, …), but that
is schema-time information.

Padding is real: a `CHAR(10)` holding `'ab'` reads back as `'ab        '` (length 10), a `CHAR(1)`
holding `'x'` as `'x'`. `DataProviderBase.SetCharField` / `SetCharFieldToType<T>`
(`DataProviderBase.cs:186-194`) are both keyed on `DataTypeName`, so the OLE DB/ODBC registrations
(`DBTYPE_WCHAR` / `CHAR`) cannot be mirrored.

## Replaying `Data/Create Scripts/Access.sql`

70 statements split on the `GO` divider, as `CreateData.RunScript` does: **all 15 tables created**,
27 expected `DROP` failures on a fresh file, 7 real failures — the 2 foreign keys (bare `REFERENCES`,
above) and 5 `CREATE Procedure` statements (`Person_Insert`, `Person_Update`, `Person_Delete`,
`Scalar_DataReader`, `AddIssue792Record`). `Person_SelectByKey`, `Person_SelectAll`,
`Person_SelectByName` and `Person_SelectListByName` — all parameterised SELECT procedures — succeeded.

## SQL — rejected (alpha.2)

| Construct | Result | linq2db impact |
|---|---|---|
| `?` positional parameters | `NotSupportedException` | must use the base `@name` builder path, not the ODBC `?` one |
| `CAST(expr AS Date)` | `SqlParseException: mismatched input 'AS'` | **none — linq2db never emits it.** `AccessSqlExpressionConvertVisitor.ConvertConversion:411-444` rewrites every DateTime→`Date` cast into `IIF(x IS NOT NULL, DateValue(x), NULL)` before the builder runs (`AccessSqlBuilderBase.cs:272`: Access has no `CAST`). Measured: that guarded shape **executes fine** on LibRed, as do the `TimeValue`/`CDate`/`CStr`/`CBool` forms from the same method. Replaying the `CAST` string was a probe of a shape the pipeline does not produce. |
| `WITH OWNERACCESS OPTION` | `SqlParseException` | `AccessHints.WithOwnerAccessOption` is unusable |
| bare `REFERENCES <table>` (no column list) | `InvalidOperationException: Foreign key on '<t>' has 1 columns but references 0` | hit by `Data/Create Scripts/Access.sql:88-93` **and** `Tests/Base/TestBase.Identity.cs:36-37`; `REFERENCES <table> (<col>)` is measured to work |
| `CREATE Procedure` with parameters on an action query / `UPDATE`/`DELETE` bodies | `NotSupportedException` / `SqlParseException` | 5 of the create script's procedures; parameterised `SELECT` procedures do create |
| `LIKE … ESCAPE '~'` | `SqlParseException` | none — Access path already uses bracket escaping |
| `{ts '…'}` / `{guid {…}}` ODBC escapes | token recognition error | GUID literal must be a plain string (works) or a parameter |
| `TOP n WITH TIES` | `SqlParseException` | not emitted by linq2db |
| `VALUES (…)` as a table source | `SqlParseException` | `IsValuesSyntaxSupported` is already `false` for Access |
| `NZ()` | `NotSupportedException: Function NZ is not supported` | not emitted by linq2db |
| Jet 3 (Access 97) file creation | throws | documented upstream limitation |
| `-9223372036854775808` as a **literal** (2026-09-22) | `OverflowException: Value was either too large or too small for an Int64.` — raised before evaluation, for `cdbl`/`csng`/`clng` alike | 2 failures in `AccessTests.TestNumerics`. **The control is the same value as a parameter**, which round-trips exactly (`cdbl(@p)` → `-9.223372036854776E+18` → `Int64 -9223372036854775808`), so the value is representable and only the literal path is not: the digits are consumed as a positive `Int64` before the unary minus is applied. Also measured: `clng(9223372036854775807)` overflows **Int32**, i.e. `CLng` is 32-bit here. |

## SQL — accepted, but semantically divergent (2026-09-22)

The dangerous class, and the one five rounds of raw-ADO probing missed: these constructs **parse and
execute** and return the wrong answer. Nothing in the emitted SQL is non-standard, so no caller can route
around them, and there is no exception to notice. Each row carries the control that could have disagreed.

| Construct | Access / standard SQL | LibRed | Control |
|---|---|---|---|
| `CStr(<guid>)` | braced `{xxxxxxxx-…}`, length 38 | **unbraced**, length 36 | `Mid('ABCDEF', 2, 3)` = `BCD`, so `Mid` is 1-based as in VBA and the divergence is `CStr`'s. Without this control the symptom is equally explained by a 0-based `Mid`, and the two produce byte-identical output. |
| `UPDATE t SET [A] = [B], [B] = [A]` on `(A=100, B=200)` | `(200, 100)` — every right-hand side is evaluated against the pre-update row | **`(200, 200)`** — assignments apply in order and later ones read what earlier ones wrote | a swap is its own control: the result is asymmetric only under simultaneous evaluation |
| `ORDER BY 1, [LastName]` | ordinal — sorts by the first select column | **inert constant** — identical to `ORDER BY [LastName]` alone | `ORDER BY 2` returns natural order, where the ordinal reading predicts `[LastName]` order. This is the arm that rules out "resolves the ordinal, resolves it wrongly". |
| `CVar(1)` | a Variant, read back as the string `"1"` | typed `Int32` `1` — the function is a no-op | `Execute<int>` returns `1` on both, so only the untyped read distinguishes them |
| `CHAR(n)` read into `string` | trimmed by the driver | padded to `n` | `[INFORMATION_SCHEMA.COLUMNS].DATA_TYPE` knows the store type at schema time; `GetDataTypeName` returns CLR names at read time, so no reader-level key can select the fixed-width column (D-13) |

## Schema discovery

`DbConnection.GetSchema()` (all collections), `DbDataReader.GetSchemaTable()` and
`IDbColumnSchemaGenerator` are **all unsupported** (`NotSupportedException` / `InvalidCastException`).

Metadata is read with SQL instead. The identifier must be **bracket-quoted** — the dotted form
`INFORMATION_SCHEMA.TABLES` fails to parse (`mismatched input '.'`):

| Collection | Columns |
|---|---|
| `[INFORMATION_SCHEMA.TABLES]` | `TABLE_NAME, TABLE_TYPE, VALIDATION_RULE, VALIDATION_TEXT` — `TABLE_TYPE` is `BASE TABLE` / `INTERNAL TABLE`; **views are not listed** |
| `[INFORMATION_SCHEMA.COLUMNS]` | `TABLE_NAME, COLUMN_NAME, ORDINAL_POSITION, DATA_TYPE, IS_NULLABLE, CHARACTER_MAXIMUM_LENGTH, NUMERIC_PRECISION, NUMERIC_SCALE, COLUMN_DEFAULT, VALIDATION_RULE, VALIDATION_TEXT, IDENTITY_SEED, IDENTITY_INCREMENT` — `DATA_TYPE` is the Access store type (`counter`, `varchar`, …) |
| `[INFORMATION_SCHEMA.INDEXES]` | `TABLE_NAME, INDEX_NAME, INDEX_TYPE, IS_NULLABLE, IGNORES_NULLS` — `INDEX_TYPE = PRIMARY` marks the PK |
| `[INFORMATION_SCHEMA.INDEX_COLUMNS]` | `TABLE_NAME, INDEX_NAME, ORDINAL_POSITION, COLUMN_NAME, IS_DESCENDING` |
| `[INFORMATION_SCHEMA.RELATIONS]` | `RELATION_NAME, REFERENCING_TABLE_NAME, PRINCIPAL_TABLE_NAME, RELATION_TYPE, ON_DELETE, ON_UPDATE, IS_ENFORCED, IS_INHERITED` — **no column pairs** |

No `VIEWS`, `TABLE_CONSTRAINTS`, `KEY_COLUMN_USAGE`, `REFERENTIAL_CONSTRAINTS`, `ROUTINES` or
`SCHEMATA` collection (probed via `InformationSchema.IsInformationSchema`, which is the engine's own
allow-list).

System tables that answer the two gaps:
- `MSysObjects` (`Name, Type, ParentId, Flags, …`) — user tables are `Type = 1`, views `Type = 5`.
- `MSysRelationships` (`szRelationship, szObject, szColumn, szReferencedObject, szReferencedColumn, ccolumn, icolumn, grbit`) — the FK **column pairs**.
- `MSysQueries`, `MSysACEs`, `MSysComplexColumns` also readable. `MSysColumns`/`MSysIndexes` do **not** exist.

## Pooling

The "every `Open()` makes a new native connection and the 65th query fails" bug that EFCore.Jet#301
fixes did **not** reproduce: 100 sequential open/close cycles and 200 commands on one open connection
both completed clean.
