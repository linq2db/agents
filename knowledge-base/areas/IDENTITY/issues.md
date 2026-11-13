---
area: IDENTITY
kind: issues
sources: [gh-issues, gh-prs]
confidence: low
last_verified: 2026-11-11
last_verified_sha: 1732302e2365c87b9465ab754b768a149308a537
---

# IDENTITY -- GitHub themes

## Open themes

- **External-login matching depends on database collation** -- `linq2db.Identity` resolves (`FindByLoginAsync`) and removes (`RemoveLoginAsync`) external logins by comparing `LoginProvider` and `ProviderKey` in SQL only, so the database collation decides what matches. Under a case-insensitive or trailing-space-insensitive collation, a login whose provider key differs only by case or padding is found and deleted. ASP.NET Core is moving its EF Core Identity stores to exact ordinal matching, which makes the gap visible. Open: #6301 (opened 2026-11-11, no fix PR in the index). It is the only open Identity-store report so far, so the theme is a singleton and may grow.

## Resolved themes

- **Lockout DateTimeOffset on MySQL** -- The lockout store writes a `DateTimeOffset` that MySQL cannot hold in the mapped type. #1206 (2020, MySQL and DateTimeOffset in the lockout store, closed) and #3469 (2022, `AccessFailedAsync` throws because DateTimeOffset is treated as Blob, closed with resolution `mysql.data`) describe the same symptom against the standalone package. The current `LockoutEnd` mapping pins a per-provider datetime type with a UTC whole-seconds converter, MySQL included, and the monorepo migration records it as a fix (#5640, merged 2026-11-04).

- **Consumer wiring questions** -- #2400 (2020, closed as a question) reports `UserManager.CreateAsync` failing after `AddLinqToDBStores` and a hand-built connection factory were wired in. The index records no fix PR. The current DI path is `AddLinqToDBStores<TContext>`, with its resolution matrix pinned by the `DependencyInjection_*` tests in `IdentityStoreVariantTests`.

- **Standalone package to monorepo** -- The Identity stores lived in a separate repository as `linq2db.Identity` 6.0.0. #2533 (PR "added Linq2db.identity", 2022-12-24) tracked the port and closed unmerged. #3886 (LinqToDB.Identity migration, closed unmerged 2026-06-20) was superseded by #5640 (merged 2026-11-04), which added `Source/LinqToDB.Identity` on the `Microsoft.Extensions.Identity.Stores` base types. #6251 (merged 2026-11-04) replaced a banned `Type.GetMethod` overload in `RemoveClaimsAsync` that broke the master Release build. Decision record: [2026-linq2db-identity-monorepo](../../history/decisions/2026-linq2db-identity-monorepo.md).

## Active discussions

- None. No discussion in the index concerns the Identity stores.

## Stats

- Open issues: 1
- Closed issues: 3
- Open PRs: 0
- Total PRs: 4 (2 merged, 2 closed unmerged)
- Discussions: 0
- Last fetched: 2026-11-11 (index horizon)

<details><summary>Coverage</summary>

- Index entries scanned: 6243 (3247 issues + 2700 PRs + 296 discussions)
- Themes extracted: 4 (1 open + 3 resolved)
</details>
