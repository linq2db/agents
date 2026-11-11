---
area: IDENTITY
kind: issues
sources: [gh-issues, gh-prs]
confidence: low
last_verified: 2026-11-11
last_verified_sha: f90c5bcfb86d88db436a6494f0640c4c43dd691f
---

# IDENTITY -- GitHub themes

## Open themes

- **No open themes** -- The indexes hold no open issue, PR or discussion about the Identity stores (`UserOnlyStore`, `UserStore`, `RoleStore`, `AddLinqToDBStores`). The area's recent work is the monorepo migration, merged 2026-11-04 (#5640, #6251), so its themes are resolved ones until new reports arrive. Known debt (ClickHouse update concurrency, SQL Server `UPDATE` triggers breaking the `OUTPUT` stamp refresh, no FKs from `CreateTable`) comes from the area index, not from GitHub, and is not repeated here.

## Resolved themes

- **Lockout DateTimeOffset on MySQL** -- The lockout store writes a `DateTimeOffset` that MySQL cannot hold in the mapped type. #1206 (2020, MySQL and DateTimeOffset in the lockout store, closed) and #3469 (2022, `AccessFailedAsync` throws because DateTimeOffset is treated as Blob, closed with resolution `mysql.data`) describe the same symptom against the standalone package. The current `LockoutEnd` mapping pins a per-provider datetime type with a UTC whole-seconds converter, MySQL included, and the monorepo migration records it as a fix (#5640, merged 2026-11-04).

- **Consumer wiring questions** -- #2400 (2020, closed as a question) reports `UserManager.CreateAsync` failing after `AddLinqToDBStores` and a hand-built connection factory were wired in. The index records no fix PR. The current DI path is `AddLinqToDBStores<TContext>`, with its resolution matrix pinned by the `DependencyInjection_*` tests in `IdentityStoreVariantTests`.

- **Standalone package to monorepo** -- The Identity stores lived in a separate repository as `linq2db.Identity` 6.0.0. #2533 (PR "added Linq2db.identity", 2022-12-24) tracked the port and closed unmerged. #3886 (LinqToDB.Identity migration, closed unmerged 2026-06-20) was superseded by #5640 (merged 2026-11-04), which added `Source/LinqToDB.Identity` on the `Microsoft.Extensions.Identity.Stores` base types. #6251 (merged 2026-11-04) replaced a banned `Type.GetMethod` overload in `RemoveClaimsAsync` that broke the master Release build. Decision record: [2026-linq2db-identity-monorepo](../../history/decisions/2026-linq2db-identity-monorepo.md).

## Active discussions

- None. No discussion in the index concerns the Identity stores.

## Stats

- Open issues: 0
- Closed issues: 3
- Open PRs: 0
- Total PRs: 4 (2 merged, 2 closed unmerged)
- Discussions: 0
- Last fetched: 2026-11-11 (index horizon)

<details><summary>Coverage</summary>

- Index entries scanned: 6240 (3245 issues + 2699 PRs + 296 discussions)
- Themes extracted: 3 (0 open + 3 resolved)
</details>
