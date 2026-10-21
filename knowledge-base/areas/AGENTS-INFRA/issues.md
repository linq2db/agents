---
area: AGENTS-INFRA
kind: issues
sources: [gh-issues, gh-prs, gh-discussions]
confidence: medium
last_verified: 2026-10-21
last_verified_sha: 89b5ce16278728b9936ba374827fea002c76e962
---

# AGENTS-INFRA -- GitHub themes

## Open themes
- **None** -- no open AGENTS-INFRA issues or PRs in the index as of 2026-10-21.

## Resolved themes
- **Claude Code initial setup and configuration** -- the first .claude/ infrastructure and CLAUDE.md agent rules landed in April 2026: [#5452](https://github.com/linq2db/linq2db/pull/5452) (initial setup, merged 2026-04-08), [#5473](https://github.com/linq2db/linq2db/pull/5473) (CLAUDE.md expansion and .claude/ tuning, merged 2026-04-20), [#5479](https://github.com/linq2db/linq2db/pull/5479) (/test, /create-issue and /release-verify skills plus review tooling, merged 2026-04-22).
- **Skill split and KB/azp tooling** -- [#5487](https://github.com/linq2db/linq2db/pull/5487) (KB build infrastructure and azp-run helper, merged 2026-05-11), [#5499](https://github.com/linq2db/linq2db/pull/5499) (/test split, /test-providers extracted for env management, merged 2026-05-01), [#5609](https://github.com/linq2db/linq2db/pull/5609) (review tooling: worktree cache paths, line-verification fallback, prep-manifest coverage, merged 2026-06-15).
- **Test-server port allocation (single item)** -- [#5603](https://github.com/linq2db/linq2db/pull/5603) switched remote test servers to dynamic per-process ports (merged 2026-06-10).
- **Copilot review rules and PublicAPI drift** -- [#6016](https://github.com/linq2db/linq2db/pull/6016) (merged 2026-10-10) removed the instruction that made Copilot flag a missing `PublicAPI.Unshipped.txt` entry in `.github/copilot-instructions.md`. Baseline drift is reconciled at release time (`/release-publicapi`), so a missing entry is not a review finding.

## Active discussions
- None. No discussions are tagged AGENTS-INFRA in the index.

## Stats
- Open issues: 0
- Closed issues: 0
- Open PRs: 0
- Total PRs: 8
- Discussions: 0
- Last fetched: 2026-10-21

<details><summary>Coverage</summary>

- Index entries scanned: 8 (0 issues + 8 PRs + 0 discussions)
- Themes extracted: 4
</details>
