# Gap ledger — remote-client-leaks (PR #6010)

## Round 1 — reviewed HEAD 47a68e5fb

No plan on this branch (external-style PR, no P9 results, no CI run). Attributed against the absent artifact.

## Attribution

- **MIN001** — GAP-05 — a plan P8 test obligation (TO-n) for "context client stops at dispose / pooling still happens" with a red-for-the-right-reason proof; a bare ObjectDisposedException type check cannot go red when pooling silently stops, because a disposed HubConnection throws the same type. RemoteContextTests.cs:349 — preventable: yes
- **MIN002** — GAP-10 — prose-only: comment length at TestSignalRDataContext.cs:118-124. The 1-3 line rule exists in agent-rules.md but is not part of any plan baseline. — preventable: no
- **SUG001** — GAP-02 — a P5/P7 assumption that the `_lease ?? base.GetClient()` fallback is reachable; checkable by reading what base.GetClient() returns during the base constructor (TestSignalRDataContext.cs:47-48). — preventable: yes
- **SUG002** — GAP-05 — missing TO-n rows for pooled reuse, discard on an interrupted lease (the 3852→18 ms claim), and the DisposeAsync path; all stated in the PR body. TestSignalRDataContext.cs (file-level) — preventable: yes
- **NIT001** — GAP-10 — prose-only: field comment restating the PR body (TestSignalRDataContext.cs:16-20). — preventable: no
- **NIT002** — GAP-10 — prose-only: comment with incident history (TestGrpcDataContext.cs:19-23). — preventable: no

## Aggregate

6 findings: 2 GAP-05 (MIN001, SUG002), 1 GAP-02 (SUG001), 3 GAP-10 (comment style). The highest-leverage fix is a P8 test-obligation row per behaviour claimed in the PR body (pooling, discard-on-interrupt, dispose), each with a stated red condition.

## Recommended durable fixes

- GAP-05 ×2 → work-plan.md P8 + plan-critic.md attack vector: every behaviour claim in the PR body/issue needs a TO-n whose assertion fails if the mechanism silently degrades; a type-only exception assertion fails this when the type is shared with another failure path.
- GAP-02 ×1 → code-reviewer.md rubric: a fallback/defensive branch must name the state in which it fires; one returning the same null as the primary path is dead code with a misleading comment.
- GAP-10 ×3 → none; rule already in agent-rules.md.
