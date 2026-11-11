---
area: GLOBAL
kind: decision
sources: [git]
confidence: high
last_verified: 2026-11-11
last_verified_sha: f90c5bcfb86d88db436a6494f0640c4c43dd691f
---

# Move the documentation site into the repository

## Context
The docs site lived in the separate linq2db/docs repository and consumed Source via submodules.

## Decision
`Docs/source` now holds the content of linq2db/docs (source/ at 0543c1145) with API metadata pointed at `Source/`, and the Home and Contributing pages include the root `README.md` and `CONTRIBUTING.md`. `Docs/build.ps1` builds into `.build/docs/_site` using a custom docfx pinned in `Docs/docfx-version.json` (a MaceWindu/docfx release verified by SHA-256), so no docfx binaries are tracked and no Node is needed. `.github/workflows/docs.yml` builds on pull requests touching docs and publishes to linq2db.github.io when a GitHub release is published. API reference now documents net10.0 for every project that targets it (docfx documents one framework per project, previously the first, net462).

## Why
Stated reasons are build mechanics, not motivation for the move itself. The body records: docfx documents one framework per project, and the two netstandard2.0 analyzer projects keep their own framework (dotnet/docfx#10772).

## Consequences
- Folder and article file names lowercased to avoid case-sensitive file system link failures, so old article URLs return 404 after the first deploy.
- Deploy is skipped for suffixed (rc/preview) tags, which are published without the GitHub prerelease flag.
- Change detection fails open, and the docs build is tested on Windows only.
- The follow-up #6264 fixed Source-side warnings of the docs build.

## Sources
- Commit `fdc08bf` -- Move the documentation site into the repository (#6265) (MaceWindu, 2026-11-10)
- Commit `73f5759` -- Fix the Source-side warnings of the docs build (#6264)
- File anchors: `Docs/build.ps1`, `.github/workflows/docs.yml`
