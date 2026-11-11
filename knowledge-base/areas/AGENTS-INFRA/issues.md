---
area: AGENTS-INFRA
kind: issues
sources: [gh-issues, gh-prs, gh-discussions]
confidence: medium
last_verified: 2026-11-11
last_verified_sha: f90c5bcfb86d88db436a6494f0640c4c43dd691f
---

# AGENTS-INFRA -- GitHub themes

## Open themes
- **None** -- no open AGENTS-INFRA items as of 2026-11-11. [#5376](https://github.com/linq2db/linq2db/pull/5376) (Agent Skill) is tagged AGENTS-INFRA in the index but is a shipped product feature (skill content in the linq2db NuGet package, installed with linq2db-cli, consumed by library users), so it is excluded from this theme file.

## Resolved themes
- **Claude Code initial setup and configuration** -- the first .claude/ infrastructure and CLAUDE.md agent rules landed in April 2026: [#5452](https://github.com/linq2db/linq2db/pull/5452) (initial setup, merged 2026-04-08), [#5473](https://github.com/linq2db/linq2db/pull/5473) (CLAUDE.md expansion and .claude/ tuning, merged 2026-04-20), [#5479](https://github.com/linq2db/linq2db/pull/5479) (/test, /create-issue and /release-verify skills plus review tooling, merged 2026-04-22).
- **Skill split and KB/azp tooling** -- [#5487](https://github.com/linq2db/linq2db/pull/5487) (KB build infrastructure and azp-run helper, merged 2026-05-11), [#5499](https://github.com/linq2db/linq2db/pull/5499) (/test split, /test-providers extracted for env management, merged 2026-05-01), [#5609](https://github.com/linq2db/linq2db/pull/5609) (review tooling: worktree cache paths, line-verification fallback, prep-manifest coverage, merged 2026-06-15).
- **Test-server port allocation (single item)** -- [#5603](https://github.com/linq2db/linq2db/pull/5603) switched remote test servers to dynamic per-process ports (merged 2026-06-10).
- **Copilot review rules and PublicAPI drift** -- [#6016](https://github.com/linq2db/linq2db/pull/6016) (merged 2026-10-10) removed the instruction that made Copilot flag a missing `PublicAPI.Unshipped.txt` entry in `.github/copilot-instructions.md`. Baseline drift is reconciled at release time (`/release-publicapi`), so a missing entry is not a review finding. [#6254](https://github.com/linq2db/linq2db/pull/6254) (merged 2026-11-05) added two test rules to the same file: narrowed provider sets and one call per line in tests.
- **Agent-instruction corpus consolidation and submodule move** -- [#5670](https://github.com/linq2db/linq2db/pull/5670) unified the agent instructions under `.agents/` with the curation tooling (merged 2026-07-06; the earlier attempt [#5521](https://github.com/linq2db/linq2db/pull/5521) was closed unmerged), [#5721](https://github.com/linq2db/linq2db/pull/5721) correctness pass over the corpus (merged 2026-07-20), [#5735](https://github.com/linq2db/linq2db/pull/5735) moved the corpus into the linq2db/agents submodule at `.claude/` (merged 2026-07-31), [#5736](https://github.com/linq2db/linq2db/pull/5736) corrected the submodule reload semantics in the setup docs (merged 2026-07-31).
- **Corpus bootstrap at checkout and worktree creation** -- [#5820](https://github.com/linq2db/linq2db/pull/5820) bootstrapped the `.claude` corpus submodule at checkout time (merged 2026-08-26); [#5821](https://github.com/linq2db/linq2db/pull/5821) fixed the detached-HEAD, swallowed-error and fresh-clone gaps in that bootstrap (merged 2026-08-26).
- **Agent solution glue projects** -- [#5752](https://github.com/linq2db/linq2db/pull/5752) replaced the per-file `.github` / `.claude` solution listing with NoTargets glue projects (merged 2026-08-10).

## Active discussions
- None. No discussions are tagged AGENTS-INFRA in the index.

## Stats
- Open issues: 0
- Closed issues: 0
- Open PRs: 0
- Total PRs: 16
- Discussions: 0
- Last fetched: 2026-11-11

<details><summary>Coverage</summary>

- Index entries scanned: 19 (0 issues + 19 PRs + 0 discussions)
- Themes extracted: 7
</details>
