---
area: GLOBAL
kind: decision
sources: [git]
confidence: medium
last_verified: 2026-10-09
last_verified_sha: 05150894edc2511f0dd0bc7829b2a309cec36ec9
---

# Translate TimeSpan members and date differences as elapsed time via interval AST nodes

## Context
A duration column unit cannot be inferred from its SQL type (a bigint may hold ticks or seconds), guessing wrong is a silent factor-of-10000000 error. TimeSpan members and date differences also had provider-inconsistent translations.

## Decision
Declarative per-column unit via `[Duration(DurationUnit.Second)]` / `.HasDuration(...)`, undeclared columns keep current TIME / time-of-day meaning. Four new AST nodes keep interval intent through optimization: `SqlIntervalExpression`, `SqlIntervalDifferenceExpression` (elapsed End - Start, never a boundary count), `SqlIntervalPartExpression`, `SqlTemporalArithmeticExpression`. They are lowered in each provider `SqlExpressionConvertVisitor`, reaching the SQL builder throws. `SqlIntervalUnits` converts exactly via rational ratios, calendar units and overflow return false rather than approximate.

## Why
Per commit body: not `SqlBinaryExpression`, because it carries operation as a string and type as `DbDataType`, with no room for interval semantics. Exact integer arithmetic avoids a plausible-wrong duration.

## Consequences
- New AST node types with remote serialization (field-order mirrored).
- Per-provider convert-visitor changes (Access, ClickHouse, DB2, DuckDB, Firebird, MySQL, ...).
- Date-difference regressions from this work were later fixed in #5987.

## Sources
- Commit `3a2960a` -- Add declarative TimeSpan duration mapping (first commit of PR, squash `Translate TimeSpan members and date differences as elapsed time (#5750)`, Svyatoslav Danyliv, 2026-08-21)
- PR #5750, follow-up #5987
- File anchors: `Source/LinqToDB/Internal/DataProvider/*/*SqlExpressionConvertVisitor.cs`
