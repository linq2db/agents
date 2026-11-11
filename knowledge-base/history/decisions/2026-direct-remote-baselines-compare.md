---
area: GLOBAL
kind: decision
sources: [git]
confidence: medium
last_verified: 2026-11-11
last_verified_sha: f90c5bcfb86d88db436a6494f0640c4c43dd691f
---

# Compare direct and remote baselines on every run

## Context
Direct and remote (LinqService) SQL were only compared when a `BaselinesPath` was set, gated by `RequiresBaselines`, and whole tests opted out through `DisableBaseline` scopes.

## Decision
`BaselineComparer` pairs direct and remote SQL by hash on every run, with or without `BaselinesPath` (`BaselinesWriter` writes files only when a path is set). `ActiveIssue(BaselinesMismatch = true)` replaces `RequiresBaselines`: the verdict comes from the recorded comparison (mismatch gives Inconclusive, match gives Failure, other side not run is left alone), and a gated mismatch writes no `.sql.other`. `[NoBaselines(reason, Configuration)]` opts a whole test out of capture, and whole-test `DisableBaseline` scopes were migrated to it. `DisableBaseline(disable: false)` does not re-enable capture inside a `[NoBaselines]` test.

## Why
The commit body gives no motivation beyond the mechanics. Confidence is medium because the rationale is inferred from the change itself.

## Consequences
- Ungated direct/remote mismatch makes `BaselinesWriter.Write` throw (covered by a test).
- Bug-flavoured gates were measured: `ComplexTests2` table names fixed, #5169 merge mismatch gated, stale scopes dropped.
- A gated mismatch writes the `.sql` from the direct side whichever side runs first.

## Sources
- Commit `89830fa` -- Compare direct and remote baselines on every run, [NoBaselines] and ActiveIssue(BaselinesMismatch) (#6061) (MaceWindu, 2026-10-28), 50 files
- File anchors: `Tests/Base/Attributes/ActiveIssueAttribute.cs`
