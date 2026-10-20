# Provider decimal limits

Measured facts about how each provider types, renders and compares a decimal literal. They decide what a literal beside a computed decimal may be typed as (`QueryHelper.GetDecimalTypeForValue`), and they are the cells to re-measure before changing that rule. All measured on the local containers on 2026-10-20 for [#5959](https://github.com/linq2db/linq2db/pull/5959) unless noted; YDB detail is in [`ydb-yql-notes.md`](ydb-yql-notes.md).

## Who renders a literal's precision

A literal's `DbDataType` facets reach SQL only through some providers, so a widened type is SQL-neutral elsewhere.

| Provider | Comparison literal | Set-operation literal | Note |
|---|---|---|---|
| ClickHouse | `toDecimal<family>('v', scale)` — family and scale, precision unused (`ClickHouseMappingSchema.ConvertDecimal`) | same | `DataType.Decimal` has no arm and throws; fixtures declare `Decimal32/64/128/256` |
| YDB | `Decimal('v', p, s)` — both facets; `(22, 9)` when absent (`YdbMappingSchema.BuildDecimalLiteral`) | same | IN items are parameters typed from the same `DbDataType` |
| DB2, Informix, SqlCe, DuckDB, MySQL, PostgreSQL, Oracle, SAP HANA | bare | `CAST(v AS DECIMAL(p, s))` from `BasicSqlOptimizer.CorrelateValueTypes`, or a mandatory `WrapColumnExpression` cast (MySQL, PostgreSQL, SAP HANA) | DuckDB renders a facet-less `CAST(… AS DECIMAL)`, i.e. DuckDB's `(18, 3)` |
| SQL Server, Sybase, Firebird | bare | cast, but `CorrectDecimalFacets` re-derives the facets from the value | widening is text-neutral; Firebird then rewrites precision > 18 to 10 (`FirebirdSqlBuilder.cs:145`) |
| Access | bare | none — `AccessSqlExpressionConvertVisitor.ConvertConversion` drops decimal casts | |

## Maximum precision

| Provider | Max | Measured |
|---|---|---|
| DB2 LUW | 31 | `CAST(1.004 AS DECIMAL(32,3))` → SQL0604N class (`42611`), and a `UNION ALL` with it refused; `DECIMAL(4,3)` accepted |
| Informix | 32 | `DECIMAL(33,3)` refused |
| YDB | 35 | `Decimal('1.004', 36, 3)` refused at type annotation |
| ClickHouse | 9 / 18 / 38 / 76 by family | — |
| Others | 38+ | — |

`SqlDataType.GetMaxPrecision(DataType.Decimal)` is 29 — the CLR decimal's width (`SqlDataType.cs:157`), not any provider's limit. A CLR `decimal` value itself never needs more than 29 digits.

## Comparison and set-operation behaviour

- **ClickHouse compares two decimals in the wider operand's family, and overflows it.** `toDecimal64('12345678901234.50', 2) = toDecimal64('1.000001', 6)` → *"Can't compare decimal number due to overflow"*; `= toDecimal128('1.000001', 6)` → 0. A literal whose scale is raised beside a near-full `Decimal64` must move to `Decimal128`.
- **Firebird overflows aligning a near-full `DECIMAL(18,2)` to a finer scale** — `MAX(col) = 1.000001` with a 16-integer-digit value → *"arithmetic exception, numeric overflow … numeric value is out of range"*, on master too; Firebird 3 and 5 measured. Not fixable by typing the literal: it is written bare.
- **SqlCe compares a decimal literal at the other side's scale** (#6062): `[Value] = 1.004` matches a stored `1.00` even on a plain column; only `CAST(MAX([Value]) AS NUMERIC(19,3)) = 1.004` answers 0.
- **SqlCe types a `UNION ALL` column by its first branch alone**: `Abs((18,2) col) UNION ALL CAST(1.0000000000005 AS Decimal(29, 13))` returns `1.00` for the literal branch, whatever the literal is cast to. Put the finer branch first, or exclude SqlCe from such a test.
- **YDB** accepts mixed decimal types in a comparison and an `IN` list, and refuses them in a `UNION ALL`, an `IF` / `CASE` and arithmetic ([`ydb-yql-notes.md`](ydb-yql-notes.md)).
