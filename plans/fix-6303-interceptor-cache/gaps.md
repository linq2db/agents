# Gap ledger — fix/6303-interceptor-cache (PR #6314)

## Round 1 — reviewed HEAD 611577f333822ef7a803057bebc2356b5e570cba

No work plan on this branch (no-plan); no P9 record. Attribution names the block a Tier M plan would have needed.

- **SUG001** (reset fires for every interceptor kind) — GAP-03 — P7 row for callers of the new `_configurationID = null` reset in `DataContext.Interceptors.cs:91-93`/`:141-142` by interceptor kind (`OnNextCommandInitialized` → `OneTimeCommandInterceptor`; `DataContextOptions.ConfigurationID` hashes every type); second class GAP-05, no TO-n counting `CacheMissCount` across `OnNextCommandInitialized` — — — preventable: yes
- **SUG002** (`IEntityBindingInterceptor` contract only on an internal helper) — GAP-03 — P7 row for the extension-point interface doc outside the diff (`Internal/Interceptors/IEntityBindingInterceptor.cs`); DoD:14 depends on a D-n naming it — G-03 — preventable: yes
- **SUG003** (per-execution contract missing on `IQueryExpressionInterceptor`) — GAP-03 — the PR body's P3 behaviour delta never became an edit-point on `Interceptors/IQueryExpressionInterceptor.cs` — G-03 — preventable: yes
- **SUG004** (self-join second reference shares accessor key, not instance constants) — GAP-02 — unprobed assumption at `TableBuilder.cs:216`; a P4 probe of two references with per-instance interceptors shows 5 misses and a retained instance; second class GAP-05, `SeveralReferencesToOneTable` asserts rows only — — — preventable: partly
- **MIN001** (remote-context changes have no test that can fail) — GAP-05 — P8 needed a TO-n arm per context type edited in parallel (DataConnection, DataContext, RemoteDataContextBase) for reset-after-compute, RemoveInterceptor and scope restore — G-09 — preventable: yes
- **NIT001** (`oldSchema` not re-padded at three sites) — GAP-07 — rule exists (`code-design.md:442`, `:444`), not embedded — G-06 — preventable: partly
- **NIT002** (`bool` padding short of the `List<…>` property) — GAP-07 — rule exists (`code-design.md:440`); `:442` subgroup wording ambiguous — G-06 — preventable: partly
- **NIT003** (`<summary>` attached to the helper, not the test) — GAP-10 — edit-time placement slip; no design block carries it and CS1587 cannot fire — — — preventable: no
- **NIT004** (~55 one-line chains; query-syntax `from` on the ternary line) — GAP-08 — `definition-of-done.md:11` sweep before push; unknown whether it ran — G-01 — preventable: partly
- **NIT005** (no blank line after six member closing braces) — GAP-01 — no corpus rule requires a blank line between members — — — preventable: partly

### Aggregate

No dominant class. 7 of 10 trace to blocks a Tier M plan would have required (P7 ×3, P4 ×1, P8 ×1, conventions embed ×2); NIT004 is a plan-independent DoD gate, NIT005 has no rule, NIT003 is the prose floor.

### Recommended durable fixes

- GAP-03 ×3 → `skills/work-plan/SKILL.md` step 5 (generalise `:133` beyond attributes): a change to an existing extension point's invocation frequency or cache keying lists the interface's declaration doc and every caller of a new configuration-id reset, by argument kind, as P7 rows; mirror in `code-design.md:105`/`:111`.
- GAP-05 + GAP-02 → `agents/plan-critic.md` near `:52`/`:35`: one TO-n per sibling type a parallel E-n set edits; a probe per query shape that registers an accessor more than once (two references to one table) behind any cache-sharing claim.
- GAP-07 ×2 + GAP-01 → `scripts/test-diff-sweep.ps1`: categories for `=`/name-column drift in an aligned block an added line joins, and for a missing blank line after a member's closing brace.
