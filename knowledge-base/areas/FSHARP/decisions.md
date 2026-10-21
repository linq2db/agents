---
area: FSHARP
kind: decisions
sources: [gh-prs, history-decisions]
confidence: medium
last_verified: 2026-10-21
last_verified_sha: 89b5ce16278728b9936ba374827fea002c76e962
---

# FSHARP -- Decisions

## Recorded decisions

- No area-scoped recorded decisions. See [GLOBAL decisions](../GLOBAL/decisions.md) for cross-cutting choices.

## Decision-flavored PRs

- [#2487 update tests from net46 to net472](https://github.com/linq2db/linq2db/pull/2487) -- [merged] Migrate test target from .net framework 4.6 to 4.7.2 to woraround breaking change in net core 5 sdk https://github.com/dotnet/fsharp/issues/10009, which breaks tests build with VS 2019 16.8

## See also (GLOBAL decisions)

- [Remove Nemerle support](../../history/decisions/2012-remove-nemerle.md)
- [Remove DbManager](../../history/decisions/2013-remove-dbmanager.md)
- [Add SAP HANA provider](../../history/decisions/2014-saphana-provider.md)
- [New Merge API (PR #686)](../../history/decisions/2017-new-merge-api.md)
- [Project reorganization](../../history/decisions/2017-project-reorganization.md)
