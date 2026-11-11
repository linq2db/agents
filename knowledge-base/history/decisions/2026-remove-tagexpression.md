---
area: GLOBAL
kind: decision
sources: [git]
confidence: high
last_verified: 2026-11-11
last_verified_sha: f90c5bcfb86d88db436a6494f0640c4c43dd691f
---

# Remove the never-constructed TagExpression

## Context
`TagExpression` and `ExpressionVisitorBase.VisitTagExpression` were added on the refactor/parsing branch (`e43c8b5b2`, 2024-02-10) and landed on master with #3401 (`7ec71d530`). The body states neither branch nor master ever had a producer: the only `new TagExpression(` was inside its own `Update`, nothing read `Tag` outside the base visitor, and there was no reflection or string reference.

## Decision
Removed the type, `ExpressionVisitorBase.VisitTagExpression` and the two pass-through overrides (`TransformVisitorsBase` from #5273, the eager-load keyed-query visitor from #5450).

## Why
Dead code with no producer. It sat under `LinqToDB.Internal.*`, so the API baselines were updated rather than treated as a public break.

## Consequences
- `PublicAPI.Unshipped.txt` got 11 `*REMOVED*` lines. `CompatibilitySuppressions.xml` was regenerated (CP0001 for the type, CP0002 for `VisitTagExpression`, per TFM) under SDK 10 to keep its BOM.
- Verified by Release builds (net10.0, netstandard2.0) and the SQLite.MS suite.

## Sources
- Commit `907a4b5` -- Remove the never-constructed TagExpression (#6134) (Ivan Demchuk, 2026-11-04)
- File anchors: `Source/LinqToDB/Internal/Expressions/ExpressionVisitorBase.cs`
