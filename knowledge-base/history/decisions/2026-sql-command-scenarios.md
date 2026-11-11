---
area: GLOBAL
kind: decision
sources: [git]
confidence: high
last_verified: 2026-11-11
last_verified_sha: f90c5bcfb86d88db436a6494f0640c4c43dd691f
---

# Scenario-based command rendering with per-provider DML services

## Context
Identity retrieval, truncate-with-reset and InsertOrUpdate emulation were produced by splitting one statement into several commands through `CommandCount` and `BuildCommand` on `ISqlBuilder`/`BasicSqlBuilder`, with per-provider flags such as `IsIdentityParameterRequired`. The #5673 series (Svyatoslav Danyliv) migrated providers one by one off this mechanism.

## Decision
Each DML shape is described as a `SqlCommandScenario` made of steps, built by a `DmlServiceBase` subclass per provider (for example `SybaseDmlService`, `SapHanaDmlService`, and a DB2 LUW/zOS split). `DmlServiceBase` always builds a scenario, a default single-step one for plain statements, so `GetCommand` is fully scenario-driven. `PreparedQuery` carries the logical scenario. A shared `ScenarioCommandRenderer` renders groups so the direct runner and remote `GetSqlText` emit identical commands. The legacy `CommandCount`/`BuildCommand` path, the `SqlCommandFragment` enum (replaced by `SqlFragmentStatement` and `SqlObjectNameExpression` AST nodes), `GetIdentityParameter`, `IsIdentityParameterRequired` and the `commandNumber` parameter of `ISqlBuilder.BuildSql` were deleted.

## Why
The commit bodies state the goal as a single scenario model through which grouping, parameter forwarding and combined execution flow. OUT-parameter identity (Oracle, Firebird) moved into the scenario interpreter instead of provider flags. No wider rationale is given in the bodies.

## Consequences
- Providers migrated: Sybase, SapHana, Access, SqlCe, DB2, Firebird, Oracle, Informix. API baselines were regenerated for the removed members.
- Remote `GetSqlText` now reflects the real scenario (identity SELECT, truncate reset, upsert steps) instead of only the base statement.
- The render pipeline was reworked in the same PR: the optimizer and convert visitors merged into one pass (`SqlExpressionConvertVisitor` derives from `SqlExpressionOptimizerVisitor`), the SQL builder was decoupled from `OptimizationContext` via `ISqlBuilderRenderContext`, and render results are cached in `PreparedScenario`.
- A per-provider combined-statement cap became a provider flag (`MaxStatementsPerCombinedGroup`).

## Sources
- Commit `26034ea` -- Optimize the render pipeline; add opt-in combined-command execution and eager loading (#5673) (Svyatoslav Danyliv, 2026-11-06), 153 files, +13079/-2788
- File anchors: `Source/LinqToDB/` DataProvider DML services and `ScenarioCommandRenderer`
