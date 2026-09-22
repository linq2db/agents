# LibRed.Ado 11.0.0-alpha.3 — measured capability delta

Companion to `findings.md` (which measures alpha.2) and to **A-17** / **A-18** in `plan.md`, which record
what the branch did about it. Every line here is a probe result against `LibRed.Ado` 11.0.0-alpha.3,
published 2026-09-22. The probe ran against the branch's committed containers
(`Data/TestData.LibRed.mdb`) for the dialect half and against the suite's own populated database
(`.build/bin/Tests/Debug/net11.0/Database/TestData.LibRed.mdb`) for the metadata half; it always operates
on a copy. The release notes were the hypothesis, never the evidence — two of the rows below contradict
the reading a note alone would have produced.

## 1. The P13 register, re-measured

| # | alpha.2 | alpha.3 | Verdict |
|---|---|---|---|
| 1 | `GetSchemaTable` / `IDbColumnSchemaGenerator` throw | both implemented; `AllowDBNull` correct per column | fixed |
| 2 | braced GUID literal matches 0 rows, unbraced matches | **braced matches, unbraced matches 0** | **inverted** |
| 3 | `GetDataTypeName` → CLR names (`String` for char/varchar/memo alike) | → store types (`Char`, `VarChar`, `LongText`, `Long`, `DateTime`) | fixed |
| 4 | `REFERENCES <table>` without a column list rejected | accepted, resolves to the parent's primary key | fixed |
| 5 | action-query params, `UPDATE`/`DELETE` bodies, `Scalar_DataReader` rejected | all five shapes create; `CommandType.StoredProcedure` executes | fixed |
| 6 | `SqlBindException` for `SELECT`, bare `InvalidOperationException` for `DROP`, no `Number` | unchanged | open |
| 7 | `WITH OWNERACCESS OPTION`, `CAST`, `LIKE … ESCAPE`, `TOP … WITH TIES`, `VALUES` source, `{ts}`/`{guid}`, `NZ()` rejected | unchanged | open |
| 10 | `CommandBehavior.SchemaOnly` ignored — the query runs | honoured: 0 rows, 6 fields | fixed |
| 11 | parameterised stored SELECT as a table source → `SqlParseException` | still refused, now as `InvalidOperationException: No value was supplied for parameter '@id'` | open (shape changed) |
| 12 | `PRIMARY KEY CLUSTERED` → parse error | accepted | fixed |
| 13/17 | no database-qualified name in any form | unchanged — `[file].[T]`, `[noext].[T]`, `[file]..[T]`, `FROM [T] IN 'file'` all fail | open |
| 14 | trailing `IDENTITY` → parse error | accepted, and the column is a real identity (`Id = 1` after insert) | fixed |
| 15 | `UPDATE a, b SET …` → parse error | accepted | fixed |
| 16 | `IS TRUE` / `IS FALSE` / `IS [NOT] DISTINCT FROM` → parse error | unchanged | open |
| 18 | `DATEADD` returns the OLE Automation serial as `Double` | returns `DateTime` | fixed |
| 19 | derived table as an `UPDATE` target → `NotSupportedException` | accepted | fixed |
| 20 | indexed `GUID` column vs a string → `Cannot encode GUID index key from String` | unchanged — and the A/B control in §5 shows alpha.2 refused the braced form and the literal `INSERT` identically, so the scope did not widen | open |
| 21 | date part returns `Int16` | returns `Int32` | fixed |
| 22 | Access zero date reads back as `DateTime.MinValue` | **mis-recorded**: see §2 | open, re-scoped |
| 23 | `DATETIME` keeps sub-second precision | unchanged (`09:44:34.6530000`) | open |
| 24 | multi-column `SET` evaluated sequentially | evaluated against the pre-update row: `(A=100,B=200)` → `(200,100)` | fixed |
| 25 | bare integer in `ORDER BY` is inert | names the nth output column: `ORDER BY 2` orders by `[N]` | fixed |
| 26 | `CVar(1)` returns a typed `Int32` | unchanged | open |
| 27 | `cdbl(-9223372036854775808)` → `OverflowException` | evaluates to `-9.223372036854776E+18` | fixed |

`clng(9223372036854775807)` still overflows `Int32` — correctly: VBA's `Long` **is** 32-bit, so that arm of
row 27 was never a defect.

Also re-measured, from A-16 rather than P13: **`CStr` over a GUID now renders braced** (`Len` 38), so the
base `GuidMemberTranslator`'s `LCase(Mid(CStr(g), 2, 36))` produces the right answer again. The control
that separated the two competing explanations on alpha.2 — `Mid('ABCDEF', 2, 3) = BCD`, i.e. `Mid` is
1-based — still holds; it was the brace that moved, not the index base.

## 2. Row 22 was recorded from the wrong layer

`TestZeroDate` still fails, and the recorded mechanism ("LibRed reads the Access zero date as
`DateTime.MinValue`") does not reproduce at the ADO layer. Measured on a `DATETIME` column:

- write by parameter → reads back `12/30/1899`
- write as `#1899-12-30#` → reads back `12/30/1899`
- write as `DateSerial(1899, 12, 30)` — **what linq2db actually emits** → reads back `12/30/1899`
- `SELECT DateSerial(1899, 12, 30)` → `12/30/1899`; `SELECT CDbl(DateSerial(1899, 12, 30))` → `0`

The loss is in the typed read, on the row whose serial is `0.0`:

```
GetSchemaTable AllowDBNull: ID=False, Date=False
  ID=1  IsDBNull=False GetValue=[12/29/1899] GetDateTime=[12/29/1899]
  ID=2  IsDBNull=False GetValue=[12/30/1899] GetDateTime=[01/01/0001]   <-- the zero serial
  ID=3  IsDBNull=False GetValue=[12/31/1899] GetDateTime=[12/31/1899]
```

`GetValue` and `GetDateTime` disagree on the same column of the same row. That is the upstream report.

## 3. `GetSchema` vs `[INFORMATION_SCHEMA.*]`

Measured side by side on the populated suite database (15 tables, 12 stored queries, 6 FK column pairs).

| Fact | `[INFORMATION_SCHEMA.*]` | `GetSchema` |
|---|---|---|
| Tables | 15 `BASE TABLE`; no views, no `MSys*` | 15 `TABLE` + 4 `SYSTEM TABLE` + 3 `VIEW` |
| Views | absent; recoverable only via `MSysObjects Type = 5` (12 candidates), a DAO `Flags` low-byte gate and one bind probe each | 3 rows with `VIEW_DEFINITION` and `IS_UPDATABLE`; the 6 parameterised selects and 3 action queries are classified as procedures instead |
| View columns | name + CLR type; nullability forced `true`; store type reverse-mapped from the CLR type | full rows in `Columns`: `TYPE_NAME`, `IS_NULLABLE`, length (`Diagnosis` → `VarChar(255)`) |
| Column store type | `counter`, `varchar`, `longchar`, `char` | `Long`, `VarChar`, `LongText`, `Char` — all 17 already covered by `AccessSchemaProviderBase.GetDataType` (`OrdinalIgnoreCase`) |
| Identity | inferred from `DATA_TYPE = 'counter'` | `IS_AUTOINCREMENT` + `SEED`/`INCREMENT` |
| Nullability | `IS_NULLABLE` | `IS_NULLABLE`, agrees row for row |
| Length | `null` for memo/binary | `0` for `LongText`/`LongBinary`, `2` for `Bit` — normalise via `CreateParameters` |
| Precision / scale | only for `decimal` | for every numeric (`Long` 10, `Short` 5, `Byte` 3, `Double` 15, `Single` 7, `Currency` 19) |
| Ordinal | 0-based | 1-based |
| Primary keys | `INDEXES(INDEX_TYPE='PRIMARY')` ⋈ `INDEX_COLUMNS` | `PrimaryKeys` (10 columns, same set) + `PK_NAME` |
| Foreign keys | `MSysRelationships` (6 rows, no rules) | `ForeignKeys` (same 6) + `UPDATE_RULE`/`DELETE_RULE`, `CASCADE` reported for `PersonDoctor`/`PersonPatient` |
| Procedures | no source at all | 9 procedures with definitions, 18 parameters with type/length/direction (unordered — sort by `ORDINAL_POSITION`) |
| Data types | hand-written list | 17 rows with CLR type and `CreateParameters`, **no `CreateFormat`** |
| Restrictions | `WHERE` clause | supported: `GetSchema("Columns", [,,Person,])` → 5 rows |
| Cost (warm) | 1 ms for 5 queries, plus one query per view candidate | 3 ms for 8 collections |

## 4. Regressions: alpha.2 and alpha.3 run side by side

**The full write-up lives in `findings.md` → *alpha.3 → Regressions against alpha.2*** — that is the file
the upstream author monitors, so the report goes there and is not duplicated here. In summary: the reader
declares `Int32` for a computed column whose value is a `Decimal` (6 suite failures, possibly 10); a text
column compared against a numeric literal now throws where alpha.2 evaluated it (4 failures); and the GUID
literal brace form plus `CStr(<guid>)` flipped — corrective, but breaking, and the reason two of this
branch's workarounds had to be deleted rather than retired.

What matters for *this branch* is the method, because it is what the verdict rests on: the question "did
alpha.3 break anything" cannot be answered from the new failure list alone — a test that fails now may have
been gated then. The same battery was run against **both** package versions on a copy of the same database,
and it overturned three claims made from the failure list alone:

- **"The GUID index-key fault widened to the braced form and to `INSERT`."** It did not: alpha.2 refuses
  both identically. Written from the alpha.3 measurement alone, with no alpha.2 arm.
- **"`NZ()` now works."** It does not, on either version. That probe ran the statement with
  `ExecuteNonQuery`, which never evaluates the projection — a false positive of the probe, not a capability.
- **"Removing the `IsDBNullAllowed` override exposed the `Decimal`→`Int32` failures."** The obvious
  hypothesis, and wrong: `AllowDBNull` is reported correctly for every expression column. The declared
  *type* is the fault, which only the two-version reader dump showed.

Everything else held: `REPLACE`, the `IIF`/`DateValue` guard, `TOP n`, a repeated named parameter, 100
open/close cycles and reading a `GUID` through a set operation behave identically on both versions, and the
two improvements the control confirms are `GetSchemaTable()` (throws on alpha.2, works on alpha.3) and
`GetDataTypeName` (`String`/`Int32` on alpha.2 against `VarChar`/`Char`/`Long` on alpha.3).

## 5. Describing a procedure does not execute it

The property A-3 protected by hand. Measured with `CommandType.StoredProcedure` and
`CommandBehavior.SchemaOnly`, no parameter values supplied:

```
before: Person=4 AllTypes=2
  Person_SelectByKey    SchemaOnly  rows=0 cols=[PersonID:Long, FirstName:VarChar, LastName:VarChar, MiddleName:VarChar, Gender:VarChar]
  Person_SelectAll      SchemaOnly  rows=0 cols=[...]
  Person_Insert         SchemaOnly  rows=0 cols=[]
  Person_Update         SchemaOnly  rows=0 cols=[]
  Person_Delete         SchemaOnly  rows=0 cols=[]
  AddIssue792Record     SchemaOnly  rows=0 cols=[]
after SchemaOnly: Person=4 AllTypes=2
```

The OLE DB flavour's route is not available here and does not need to be: `CommandBehavior.KeyInfo` on a
parameterised query fails with `Procedure 'Person_SelectByKey' declares 1 parameter(s) but was executed
with 0 argument(s)`. Hence `GetProcedureSchemaExecutesProcedure` stays `false`. Transactions roll back
normally (insert inside a transaction → `Person=5`; after `Rollback()` → `Person=4`), so the base class's
safety net is intact either way.
