# LibRed 11.0.0-alpha.2 — measured capability report

All facts below were **measured** on 2026-09-19 with `.build/.agents/libred-probe` (net11.0, SDK
11.0.100-rc.1.26425.128) against real `.accdb` files created by LibRed itself. Raw logs:
`smoke-accdb.txt`, `battery-accdb.txt`, `schema-accdb.txt`, `access-sql-accdb.txt`, `sig.txt`.

Packages: `LibRed.Ado` 11.0.0-alpha.2 → `LibRed.Engine` → `LibRed.Core`, `LibRed.Sql`,
`Antlr4.Runtime.Standard`. `net11.0` only. alpha.3 exists **only** in the open PR
CirrusRedOrg/EntityFrameworkCore.Jet#301; nuget.org has alpha.1 and alpha.2.

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
