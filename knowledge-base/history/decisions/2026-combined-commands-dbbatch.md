---
area: GLOBAL
kind: decision
sources: [git]
confidence: high
last_verified: 2026-11-11
last_verified_sha: f90c5bcfb86d88db436a6494f0640c4c43dd691f
---

# Opt-in combined commands and DbBatch execution

## Context
With the scenario model in place (see `2026-sql-command-scenarios`), eager loading and multi-step DML could run several statements in one round-trip. PostgreSQL, SQL Server and MySQL drivers return result sets of a ';'-separated command in order.

## Decision
Added a combined multi-result-set engine, enabled per provider through `IsMultiStatementBatchSupported` and `IsMultipleResultSetsSupported` (SQL Server, MySQL, PostgreSQL). Groups execute either as one concatenated command or, when the driver supports it, as an ADO.NET `DbBatch` (`LinqOptions.UseDbBatch`, default enabled, `SUPPORTS_DBBATCH` on net8+). The whole feature is gated behind `LinqOptions.UseCombinedCommands`, off by default in 6.x and planned to default to true in 7. It can be set on the `LinqOptions` record, `Configuration.UseCombinedCommands` (process default) and `DataOptionsExtensions.UseCombinedCommands` (per context). Combined commands split at a provider parameter limit and a soft `MaxCombinedCommandLength`.

## Why
Per the gating commit body: combining is observable, not merely faster. A combined eager load runs inside an implicit read-consistency transaction where sequential loading used none, the SQL shape changes (statements joined by ';', one shared parameter scope with deduplicated names), and `DbBatch` changes traced output. The body says a minor release should not turn that on for everyone, since the engine's defects surface as silent wrong results.

## Consequences
- Registering an `ICommandInterceptor` disables DbBatch use (falls back to the concatenated command so the interceptor still observes execution).
- Eager loading of N children can run as one round-trip (N+1 to 1) when the option is on.
- SQL Server limit is 2098 parameters (sp_executesql consumes two of 2100).
- Command-count expectations in tests depend on the option.

## Sources
- Commit `26034ea` -- Optimize the render pipeline; add opt-in combined-command execution and eager loading (#5673) (Svyatoslav Danyliv, 2026-11-06)
- File anchors: `Source/LinqToDB/Common/Configuration.cs`, `Source/LinqToDB/LinqOptions.cs`
