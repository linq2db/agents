---
area: IDENTITY
kind: decisions
sources: [gh-prs, history-decisions]
confidence: medium
last_verified: 2026-11-11
last_verified_sha: f90c5bcfb86d88db436a6494f0640c4c43dd691f
---

# IDENTITY -- Decisions

## Recorded decisions

- [Migrate LinqToDB.Identity into the monorepo](../../history/decisions/2026-linq2db-identity-monorepo.md) -- `Source/LinqToDB.Identity` replaces the standalone package (#5640, merged 2026-11-04). Layered `UserOnlyStore`, `UserStore` and `RoleStore` sit on `Microsoft.Extensions.Identity.Stores`, with `IdentityDataConnection` and `IdentityDataContext` contexts, `AddLinqToDBStores<TContext>` DI, default `AspNet*` mappings kept schema-compatible with EF Core, and passkeys on .NET 10+. `IProtectedUserStore` is not declared, and `DeleteAsync` removes dependent rows.
- Same record: Identity.Stores is pinned to one runtime floor (8.0, 9.0, 10.0) instead of a four-way split, because Identity.Stores 8, 9 and 10 still ship net462 and netstandard2.0 assets.

## Decision-flavored PRs

- [#5640](https://github.com/linq2db/linq2db/pull/5640) -- Migrate LinqToDB.Identity into the monorepo. Merged 2026-11-04. Flagged by the merged-with-large-diff rule (33 files, +6686, per the history record). Covered by the recorded decision above.
- [#3886](https://github.com/linq2db/linq2db/pull/3886) -- LinqToDB.Identity migration. Closed unmerged 2026-06-20 and superseded by #5640. Its body set the first-cut decisions: move to the monorepo, rename the assembly to `linq2db.Identity`, and drop the legacy `Microsoft.AspNetCore.Identity` membership model for `Microsoft.Extensions.Identity.Stores`. Not in force.

## See also

- [EFCORE decisions](../EFCORE/decisions.md) -- the other EF-interop package, with the same `AspNet*` schema compatibility goal.
- Follow-up fix [#6251](https://github.com/linq2db/linq2db/pull/6251) (merged 2026-11-04) is a fix, not a decision, so it is not listed above.
