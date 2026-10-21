---
area: GLOBAL
kind: decision
sources: [git]
confidence: high
last_verified: 2026-10-21
last_verified_sha: 89b5ce16278728b9936ba374827fea002c76e962
---

# Read a missed LEFT JOIN row as the reader does in projection calculations

## Context
Over a missed LEFT JOIN row, a calculation translated to SQL kept SQL's NULL for a non-nullable column, while the reader (and C#) reads default(T). With `PreferClientCalculation` off the results diverged from the option-on arm and from C# (for example `(j.Value1 + 1) * 10` read 0 instead of 10). A widening nullable cast such as `(long?)j.Value1` also returned default(T) instead of null.

## Decision
PR #5983 (`d27ab54`) makes projection calculations read a missed-row column as the reader does, by wrapping it in a COALESCE to the type's default (`SqlDefaultValueExpression`, lowered per provider). The contract is documented once on `LinqOptions.PreferClientCalculation`: string interpolation moves to the client, members with a built-in translation and their arguments stay in SQL, and over a missed row a calculation reads a non-nullable column as default(T) in both modes. The change touches `NullabilityContext`, `QueryHelper`, `ExpressionBuildVisitor`, `ContainsBuilder`, `SqlExpressionConvertVisitor` and the provider convert visitors.

## Why
The commit bodies state the aim as consistency with the reader and with C#. Exceptions are kept where the default is outside the operator's domain (a divisor, a shifted date, date-from-parts) to avoid new server errors such as "Divide by zero" or datetime2 overflow. Server-side-only `[Sql.Function]` / `[Sql.Expression]` arguments keep SQL NULL so the function's own NULL handling is preserved.

## Consequences
- Inline arrays (IN lists, `Contains`, `string.Join`) and their `AsEnumerable` / `AsQueryable` / cast wrappers are recognised via a shared `UnwrapInlineArray`. Only the BCL wrappers are unwrapped, not `LinqExtensions.AsQueryable(db)`.
- `CompareNulls.LikeClr` IN lists with nullable non-constant items are rewritten to OR-ed null-safe equalities.
- Provider-specific default lowering: DateTimeOffset defaults are written as DateTime on SQL Server, YDB and MySQL. Oracle writes a DateTime mapped as DateTimeOffset with an explicit +00:00 offset. The YDB DateOnly default is clamped.
- `SqlDefaultValueExpression` is serialized for remote use (`LinqServiceSerializer`).
- Two known gaps are gated with `[ActiveIssue]` on #6046: the eager-load detail query and a COALESCE over a CTE field. DB2 is gated on #6065.
- Baselines of existing tests (Issue3001, Issue4336, Issue3043, Issue2478) moved with the rule and were pinned with missed-row seeds.

## Sources
- Commit `d27ab54` -- Read a missed LEFT JOIN row as the reader does in projection calculations (#5983) (Svyatoslav Danyliv, 2026-10-21)
- File anchors: `Source/LinqToDB/Common/Configuration.cs`, `Source/LinqToDB/Internal/SqlQuery/NullabilityContext.cs`, `Source/LinqToDB/Internal/SqlQuery/SqlDefaultValueExpression.cs`, `Source/LinqToDB/Internal/Linq/Builder/ContainsBuilder.cs`, `Tests/Linq/Linq/PreferClientCalculationTests.cs`
