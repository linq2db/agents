# Gap ledger — fix/object-to-string-invariant (PR #6442)

## Round 1 — reviewed HEAD 1186cb7cfff29c3d532132b7055b1f291d95b95c

No work plan (external contributor). Attribution is to the block a Tier S/M plan would have needed. Posted as review 6042103263 (COMMENT).

- **MIN001** (Issue<N> names in shared fixture) — GAP-07 — P8 TO-n + step-4 conventions embed (testing.md:746, test-review-checklist.md:93); rule absent from .github/copilot-instructions.md; test-diff-sweep.ps1 had no Issue<N> detector; inserted mid Issue4371* legacy cluster — — — preventable: partly
- **MIN002** (AllSQLite gate on shared-conversion defect, no reason) — GAP-07 — P8 TO-n provider scope; secondary GAP-08: test-diff-sweep.ps1 narrowedWithoutReason flags it; checklist "compare against neighbours" endorsed it because all neighbours are narrowed — G-01 — preventable: yes
- **SUG001** (ConvertToStringObjectMethod belongs in Methods.System) — GAP-01 — no rule; code-design.md example showed a private static field for a BCL method, and the Methods.* paragraph scoped the registry to matching only — — — preventable: no
- **NIT001** (four one-line chains) — GAP-07 — step-4 conventions embed (testing.md:655); secondary GAP-08: sweep chains output detects all four; copilot-instructions.md:41 carries the rule but Claude Code does not load it — G-01 — preventable: yes

### Aggregate

GAP-07 3/4, GAP-01 1/4. The test rules exist but did not reach the contributor's AI session; the adjacent Issue4371* cluster shows both violations nine times.

### Durable fixes (all applied 2026-11-24)

1. `.github/copilot-instructions.md` (linq2db commit): the Issue<N> naming rule and a pointer to `test-diff-sweep.ps1`.
2. `scripts/test-diff-sweep.ps1`: check 11, `issueNamedMembers`.
3. `docs/code-design.md` → *Use `MemberHelper.MethodOf`*: reflected BCL methods go in `Methods.System`; the `TrimEnd` example marked legacy.
4. `docs/test-review-checklist.md` → *Compare against the neighbours*: narrowed neighbours with no reason line are legacy, not a floor.

### Continuity

No prior round on this branch. MIN002's class recurs across branches: fix-lambda-parameter-binding-cache gaps.md:28, feature-baseline-gating-attributes gaps.md:27, #5840.
