---
area: GLOBAL
kind: decision
sources: [git]
confidence: medium
last_verified: 2026-10-09
last_verified_sha: 05150894edc2511f0dd0bc7829b2a309cec36ec9
---

# Replace [ActiveIssue] gating with a run-and-verify attribute

## Context
`[ActiveIssue]` sets `RunState.Explicit`, so a gated test never runs: it cannot signal when its issue is fixed, and `AllowMultiple=false` means one test cannot record two issues for two providers.

## Decision
Introduced `ActiveIssueNew` (modelled on `ThrowsWhenAttribute`), which runs the test and asserts the declared failure: passed -> Failure ("appears fixed"), failed as declared -> Inconclusive, failed otherwise -> Failure, skipped/ignored passes through. Targeting is decided at execution time via `NUnitUtils.GetContext`. The 24 live EF Core gates were migrated first, then the rest (the squash touches `Tests/Base/Attributes/ActiveIssueAttribute.cs`).

## Why
Per the commit body: gates must be triaged from observed outcomes, and fixed issues must surface automatically. Execution-time targeting makes `AllowMultiple` workable (two `ITestBuilder`s on one method build the case list twice).

## Consequences
- `TestProgressState` gains an inconclusive bucket (Book and Unbook kept symmetric), known-issue cases are countable in local sweeps.
- `ActiveIssueSentinel` carries a parsable single-line triage record.
- A gated test that unexpectedly passes now fails the run.

## Sources
- Commit `76ae833` -- Tests: add ActiveIssueNew... (first commit of PR, squash `Tests: replace [ActiveIssue] with a run-and-verify attribute (#5882)`, MaceWindu, 2026-09-18)
- PR #5882
- File anchors: `Tests/Base/Attributes/ActiveIssueAttribute.cs`, `Tests/Base/Attributes/ThrowsWhenAttribute.cs`
