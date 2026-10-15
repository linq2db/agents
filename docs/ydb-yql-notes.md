# YDB / YQL behaviour notes

Measured facts about YQL that a YDB translator or optimizer change depends on. Each entry names how it was measured, so a later YDB version can be re-checked rather than trusted. Read this before designing a cast, a type pin or a branch in `Source/LinqToDB/Internal/DataProvider/Ydb/`.

## Decimal types

All measured on the local `ydb` container (2026-10-15, PR [#5943](https://github.com/linq2db/linq2db/pull/5943)) with raw YQL or through `Tests/Linq` on `YDB` and `YDB.LinqService`.

| Operation | Mixed Decimal types? | Evidence |
|---|---|---|
| Comparison (`>`, `<`, `=`) | **accepted** — `Decimal(10,2) > Decimal(35,9)` answers correctly | `r.E * r.E > Decimal('0', 35, 9)` executed, values correct |
| Arithmetic (`+`, `-`, `*`, `/`) | **rejected** — `Cannot add/substract different decimals`, `DecimalMul … Cannot calculate with different decimals` | `Round(D*D, -14) + D22s9`; `H * E` over `Decimal(20,12)` × `Decimal(10,2)` |
| `IF` / `CASE` branches | **rejected** — type annotation error, or `Failed to convert type: Decimal(31,9) to Decimal(22,9) … Implicit decimal cast would narrow the range` | `SELECT IF(true, Decimal('1',35,2), Decimal('1',22,9))` |

So a cast that exists only to make a *comparison* type-match buys nothing, while every branch of a conditional and every operand of arithmetic must carry one identical Decimal type.

- **`IF` / `CASE` evaluate only the taken branch, per row.** An `Ensure(...)` in an untaken branch does not fire: `MathFunctionTests.Round23` row 8 (precision −14) stays green with the negative branch's `Ensure` accepting only `p ≥ −13`. (A constant `IF(true, 1, Ensure(1, false, 'x'))` = 1 agrees but could be constant-folded, so it is not evidence on its own.) Type annotation still checks every branch: a branch that is never taken still fails the query if its type is wrong.
- **`CAST(Decimal(P,P) AS Decimal(x,0))` is refused at type annotation** (`Cannot cast type Decimal(4,4) into Decimal(35,0)`), in both directions; `Decimal(P,P) → Decimal(35,S)` is accepted for `S ≥ 1` (`(4,4) → (35,9)` = `0.123400000`, `(35,35) → (35,1)`). Route a value whose type may have no integer digits through `Decimal(35,1)` before dropping the scale.
- **A scale-narrowing `CAST` rounds half-to-even**, both signs, exactly at full width (`1.25 → 1.2`, `1.35 → 1.4`, `-1.25 → -1.2`).
- **An out-of-range Decimal `CAST` does not raise a cast error.** It yields an empty optional (the surrounding `Unwrap` then fails the query with `PreconditionFailed … Failed to unwrap empty optional`) or a value the client cannot read (`OverflowException: Value does not fit into decimal` from `Ydb.Sdk`).
- **A computed Decimal's YQL type is not the type linq2db infers.** linq2db types most computed Decimals (`SUM`, `AVG`, a product) with the default `Decimal(22,9)`, while YQL keeps the operand type (`Decimal(10,2) * Decimal(10,2)` → `Decimal(10,2)`; `SUM` of `Decimal(10,2)` → `Decimal(35,2)`). Any expression built around a computed Decimal must cast it — mandatory — to the type the rest of the expression assumes.
- `YdbMappingSchema` registers no default precision/scale for `decimal`, so a binary expression's `DbDataType` carries none unless the translator sets it.

## Remote (`YDB.LinqService`) divergence

`LinqServiceSerializer` round-trips a `SqlBinaryExpression` by `SystemType` only, so its precision/scale are lost on the server; `SqlExpressionOptimizerVisitor` then folds a **non-mandatory** cast whose re-inferred source type equals its target. A narrowing cast that YDB direct renders can therefore vanish over LinqService. Mandatory casts (`isMandatory: true`) survive: `SqlCastExpression.IsMandatory` is serialized. Tracked as [#6055](https://github.com/linq2db/linq2db/issues/6055); until it lands, prefer mandatory casts where the type must reach the SQL.

## Local container

The local `ydb` container tends to degrade 20–30 minutes into heavy test load (`Schemeshard not available`, `ClientTransportTimeout`, `CreateDatabase` leaving tables missing). Keep YDB runs targeted, and read a mass `SchemeError … does not exist` failure as an environment fault, not a code verdict.
