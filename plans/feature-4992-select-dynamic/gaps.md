# Gap ledger — feature/4992-select-dynamic (#6110)

No work plan on this branch: the feature was split out of #5708 (`feature-1475-pivot-unpivot/plan.md`, D-8), which does
not carry this feature's design. Attributions are against the blocks a Tier M plan would have required.

## Round 1 — reviewed HEAD 50cffe64d5a32999db145a30793038cf76bf3b66

Findings were fixed on the branch: dddd35518 (layout), f5695cb84 (MIN004), 746b76f5b (observation). Nothing posted.

- **MIN004** (compiled-query closure retains the first call's arguments and `IDataContext`) — GAP-01 — commit 3b532bf49 made delegate-typed `[SqlQueryDependent]` arguments that read compiled-query parameters materialise at build time; no success criterion named what the substituted constant captures inside the cached compiled query, and no P7 row listed the `ResolveCompiledQueryArguments` consumers (`nameSelector`, the ten `SqlFn` `data_type` overloads) — — — preventable: partly
- **NIT003** (one-line `ShouldThrow().Message.ShouldContain` chains in `SelectDynamicTests.cs`) — GAP-07 — testing.md → Test layout rule 1 was applied in 9140c2ca2 only partially; no test obligation cited the rule or re-swept the file before push — — — preventable: yes
- **NIT004** (`SqlServerFunctionsTests.cs:187-192` chains, new test from 38e51b07a) — GAP-07 — same rule; a fix to one test file did not reach a test added later in another file, with no "every test file added on the branch" sweep — — — preventable: yes
- **OOS-promoted** (inline `IEnumerable<T>`-typed query as `keys` run during the build and cached by instance) — GAP-02 — the assumption that the argument's static type discriminates a query was never probed against a runtime value — — — preventable: partly

### Aggregate

Two groups. The nits (GAP-07 ×2) are the cheapest to prevent: the rule exists and did not reach the author at the moment
the tests were written. MIN004 and the promoted observation share one root: nothing asked what a value materialised at
build time captures once it is cached (GAP-01 once, GAP-02 once).

### Recommended durable fixes (route to `/session-reflect` → plan-rule)

- For any change that evaluates or captures values at build time (expression-visitor constant substitution,
  `[SqlQueryDependent]`), a success criterion on what the cached artifact retains (contexts, argument arrays, query
  instances), paired with a probe of runtime value against static type.
- Each new-test TO-n cites testing.md → Test layout, and the final step re-sweeps every test file added on the branch
  (`test-diff-sweep.ps1`), not only the last one touched.
