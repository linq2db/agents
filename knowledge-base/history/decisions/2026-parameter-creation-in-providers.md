---
area: GLOBAL
kind: decision
sources: [git]
confidence: medium
last_verified: 2026-10-09
last_verified_sha: 05150894edc2511f0dd0bc7829b2a309cec36ec9
---

# Move DbParameter creation into the data provider

## Context
Command parameters were created at LINQ and raw-SQL call sites, leaving providers no hook to infer or customize parameter types (e.g. Oracle long strings).

## Decision
Added a provider-level `CreateParameter` API with a shared `DataProviderParameterContext`. Both LINQ query execution (`DataConnection.QueryRunner`) and raw SQL `DataParameter` binding use it. The default implementation keeps the common inference logic, providers may override. Oracle uses it to infer `NText` for long string parameters when no type is specified, threshold `OracleOptions.MaxStringParameterLength` (default 4000, `null` disables).

## Why
Provider-specific parameter behavior needed a seam. The commit body records that LINQ string parameters are typed from their column/CLR type and never arrive as `DataType.Undefined`, so the Oracle NCLOB inference does not fire for LINQ parameters (placeholder test removed).

## Consequences
- New public surface in `IDataProvider` and `DataProviderParameterContext` (see `CompatibilitySuppressions.xml` change).
- Dead hardcoded >=4000 NText block removed from `OracleDataProvider.SetParameter`.
- `SqlParameterValue` / `SqlParameterValues` touched.

## Sources
- Commit `233037a` -- Move parameter creation into providers (Igor Tkachev, 2026-07-11)
- PR #5600
- File anchors: `Source/LinqToDB/DataProvider/DataProviderParameterContext.cs`, `Source/LinqToDB/DataProvider/IDataProvider.cs`, `Source/LinqToDB/Internal/DataProvider/Oracle/OracleDataProvider.cs`
