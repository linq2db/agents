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

## Round 2 — reviewed HEAD 36093411202288f2888ece28ae171edcfaac5edb

MAJ001 was fixed on the branch (`BuildTimeArgumentReader.ReadArgument` refuses a non-materialized `IEnumerable` before enumerating it). Nothing posted.

- **MAJ001** (deferred keys sequence over a query passes the `is IQueryable` check: runs every execution, and the compiled cache keeps the lazy sequence and its disposed context) — GAP-07 — the defect is the type-keyed clause 746b76f5b added to fix round 1's promoted finding; `acting-on-findings.md:45` already required attacking a fix's own new condition ("when the clause keys on a type property, name a user type that has that property but breaks the semantics", d55b348, 2026-11-01) but the overlay's trigger list (`agent-rules.md:145`) omits it; second class GAP-02: no probe of the assumption "a keys value that runs a query is an `IQueryable` at runtime", and no impact row for the second keys holder, `CompiledTable.GetDependentArgumentValues`, where the retention lives — — — preventable: partly (attacking the clause gives the deferred-sequence class; a materializing fix would still have left the by-value re-evaluation and the compiled-cache retention)

### Aggregate

One finding, a fix-of-a-fix: the defect sits in the clause written to close round 1's promoted finding. The rule aimed at
exactly this existed but had no trigger in the always-loaded overlay — a delivery gap, not an analysis gap.

### Recommended durable fixes (route to `/session-reflect` → plan-rule)

- GAP-07 → `docs/agent-rules.md:145`: add the trigger "a fix's own new condition gets attacked before commit; a
  type-keyed guard: name a value that has the type and breaks the semantics", pointing at `acting-on-findings.md` →
  *A fix written during a walk…*; optionally cite #6110 (`is IQueryable` vs a LINQ-to-Objects wrapper) there.
- GAP-02 → `docs/work-plan.md:134` (the build-time-capture `P7` row from round 1): reword "whether a runtime value can
  differ from its static type" to "whether reading or enumerating it can execute work or reach a data context, whatever
  its runtime type", and list every holder of the captured value (closure, by-value comparison, compiled-query cache key).

### Continuity with round 1

- **OOS-promoted (GAP-02) recurs as MAJ001**, one level down: round 1 discriminated by static type, 746b76f5b by runtime
  type; both decide by type what must be decided by behaviour.
- **MIN004 (GAP-01) recurs in consequence**: the cached compiled query again kept the first call's argument and its
  `IDataContext` — round 1 through a `nameSelector` closure, this round through the compiled-query cache key.
- **Round 1's durable fix #1 landed** (`work-plan.md:134`, corpus dff4c85, ten minutes after 746b76f5b), binds only
  plans, and its wording would not have caught MAJ001.
- **NIT003 / NIT004 do not recur.**
