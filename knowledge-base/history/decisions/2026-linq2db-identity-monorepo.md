---
area: GLOBAL
kind: decision
sources: [git]
confidence: high
last_verified: 2026-11-11
last_verified_sha: f90c5bcfb86d88db436a6494f0640c4c43dd691f
---

# Migrate LinqToDB.Identity into the monorepo

## Context
ASP.NET Core Identity stores for linq2db existed outside this repository. The commit says it supersedes #3886.

## Decision
`LinqToDB.Identity` was added to the monorepo, modernized onto `Microsoft.Extensions.Identity.Stores` base types: layered `UserStore`/`UserOnlyStore`/`RoleStore`, `IdentityDataConnection`/`IdentityDataContext`, `AddLinqToDBStores<TContext>` DI registration, default `AspNet*` fluent mappings (DB-schema compatible with EF Core), `IUserPasskeyStore` on .NET 10+ (passkey data stored as JSON), and a `TUserPasskey` type parameter on .NET 10 matching EF Core's shape. Identity.Stores is pinned to the lowest runtime floor (8.0, 9.0, 10.0) like the DependencyInjection block, which removed a 6.0.36 legacy pin and a CS8609/CS8613 suppression.

## Why
The body states the single-pin simplification: Identity.Stores 8/9/10 still ship net462/netstandard2.0 assets, so a 4-way split was unnecessary.

## Consequences
- Tests under `Tests/Linq/Identity` run on all providers and over LinqService (direct and remote), with SQL baseline capture opted out.
- Per-provider mapping fixes: `LockoutEnd` (no DateTimeOffset DDL type, MySQL TIMESTAMP ends in 2038, Firebird dialects), widened `ClaimValue`/token `Value`, passkey data as text/CLOB where unbounded NVarChar is 255 or 2000 wide.
- `DeleteAsync` removes a user's or role's dependent rows. `IProtectedUserStore` is not declared.
- Shadow navigation types were replaced with association extension methods.
- Follow-up `b6fb447` replaced a banned `Type.GetMethod` overload in `RemoveClaimsAsync`.

## Sources
- Commit `4ffc6b2` -- Migrate LinqToDB.Identity into the monorepo (#5640) (MaceWindu, 2026-11-04), 33 files, +6686
- Commit `b6fb447` -- Identity: replace the banned Type.GetMethod overload in RemoveClaimsAsync (#6251)
