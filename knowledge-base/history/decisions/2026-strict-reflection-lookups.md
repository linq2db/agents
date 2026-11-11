---
area: GLOBAL
kind: decision
sources: [git]
confidence: high
last_verified: 2026-11-11
last_verified_sha: f90c5bcfb86d88db436a6494f0640c4c43dd691f
---

# Strict versus coercing reflection lookups

## Context
`Type.GetConstructor`/`GetMethod`/`GetProperty` with a `Type[]` use the default binder, which also matches parameters needing a value conversion (byte to int, T to T?, boxing). Every Expression-fed caller then failed late with `ArgumentException` from `Expression.New`/`Expression.Call` (#4313, #4314).

## Decision
Ban the 18 `Type[]` overloads in `Source/BannedSymbols.txt` (plus `GetRuntimeMethod`). `ReflectionExtensions` gets strict helpers, `GetConstructorEx` and `GetMethodEx(BindingFlags)`, that accept only identical or reference-assignable parameter types. A generic-arity `GetMethodEx` enumerates on every TFM (identical wins, ties throw), removing the net8+/net462 polyfill split in `TypeMapper`. Coercing variants, `GetConstructorCoercing` and `GetMethodCoercing`, keep default-binder matching for `ConvertBuilder`, which converts arguments itself. All 58 core sites plus CLI and EF.Core lookups moved to the helpers.

## Why
Failing at lookup with "Method/Constructor not found" is preferred over a late `ArgumentException`. During review, base-type walk-ups (`GetMemberEx`, mapping attributes, `Linq.Expressions.MapMember`) were found to need coercing matches, so `GetMemberEx` was kept on `GetMethodCoercing` ("as on master"). Red tests: `MapMemberOnBaseOverloadWithWiderParameter`, `SqlExpressionOnBaseOverloadWithWiderParameter`.

## Consequences
- `TypeMapper` reports not-found instead of throwing `ArgumentException`. A derived wrapper argument still binds to a base-typed parameter.
- The arity `GetMethodEx` treats a hiding generic method as hidden and picks the most specific compatible overload, throwing only if more than one survives.
- Direct `Type.GetMethod(Type[])` use is a banned-API build error in Release.

## Sources
- Commit `facbcd3` -- Bind reflection lookups only to Expression-compatible overloads (#4314) (#6155) (MaceWindu, 2026-11-04)
- File anchors: `Source/BannedSymbols.txt`, `Source/LinqToDB/Extensions/ReflectionExtensions.cs`
