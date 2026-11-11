---
area: DOCS
kind: decisions
sources: [gh-prs, history-decisions]
confidence: medium
last_verified: 2026-11-11
last_verified_sha: f90c5bcfb86d88db436a6494f0640c4c43dd691f
---

# DOCS -- Decisions

## Recorded decisions

- **Move the documentation site into the repository (#6265, merged 2026-11-10)** -- the site moved from linq2db/docs into `docs/`. The API reference is generated from `Source/` and documents net10.0 for every project that targets it. `docs/build.ps1` builds it with a pinned, SHA-256-verified docfx fork, and `.github/workflows/docs.yml` publishes it when a non-prerelease GitHub release is published. Known consequences: folder and article names are lowercased, so old article URLs return 404 after the first deploy. Suffixed (rc and preview) tags skip the deploy. The docs build is tested on Windows only. Full record: [2026 docs site into repo](../../history/decisions/2026-docs-site-into-repo.md).

## Decision-flavored PRs

- [#6274](https://github.com/linq2db/linq2db/pull/6274) -- adds two test-layout rules to CONTRIBUTING.md (merged 2026-11-08). It is listed for its policy text, not for a label or file-count test. The Contributing article includes CONTRIBUTING.md, so the rules publish with the site.

## Open decisions

- [#6267](https://github.com/linq2db/linq2db/issues/6267) -- whether to replace the SSH deploy-key push to linq2db/linq2db.github.io with GitHub Pages' Actions publishing. Open, no decision recorded.

## See also

- [BUILD](../BUILD/INDEX.md) -- owns `.github/workflows/docs.yml`, the Roslyn pin in `Directory.Packages.props` and `global.json`.
- [BUILD decisions](../BUILD/decisions.md)
