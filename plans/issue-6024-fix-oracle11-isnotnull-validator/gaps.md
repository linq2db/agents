# Gap ledger: issue-6024-fix-oracle11-isnotnull-validator

## Round 1 — reviewed HEAD e70651bb0b1faf6d445b2e896ccce01ac948aeba (PR #6027)

### Attribution

- **BLK001** — GAP-02 — P8 TO-3/TO-9 and E-2. The plan never checked what `[ThrowsRequiresCorrelatedSubquery]` (simple:false) asserts on non-Oracle providers. TO-9 names only SQLite.MS and Oracle 12, and P9 delegates the breadth to CI. The plan assumed the attribute was right for a correlated Any. One grep of the sibling Any tests in `AllAnyTests.cs`, all `simple: true`, would have shown it was wrong. If you count the sibling-file convention as a rule, this is GAP-06/07 instead, but the plan embeds no such rule, so GAP-02 is the earliest. The failing leg was the ClickHouse set. — G-01 / G-08 ran only Oracle 11 + SQLite.MS, so the gate was scoped narrowly, not skipped; not GAP-08. — preventable: yes
- **SUG001** — GAP-05 — P8 TO-5 against P5 D-1 rejected alternative (c). D-1 rejects (c) on the claim that the pre-#5500 visitor flagged nested references. TO-5 is single-level, and its mutation (check forced to false) cannot tell per-boundary reset from outermost-only reset. The plan's claim that (c) is wrong had no obligation behind it. The post-hoc probe found the distinction is not observable end-to-end, so this is partly irreducible. — — — preventable: partly
- **OOS-1** — GAP-03 — P4 U-3 (census) and the P7 impact map. The census logged only tests where the validator fired, so tests excluded from Oracle 11 via `[DataSources(...)]` could never appear. P7 has no row for a sweep of `AllOracle11` exclusions. A-2 found one such exclusion (Issue5256) and handled that single case, with no sweep for siblings. A-2 is the last point where this was catchable. A grep of `Tests/` for `AllOracle11` in `DataSources` exclusions would have listed all seven tests. — G-?? none applicable; no gate drives off excluded tests. — preventable: yes
- **OOS-2** — dropped by user, not attributed.
- **Side finding (Access ACE wrong rows)** — not-a-gap: out-of-plan-scope — P9 G-01 TO-5 "Side finding" and P3 ("Not re-deciding which IS NOT NULL shapes genuinely break Oracle 11…"). The Access ACE issue is unrelated to this code path and is tracked separately.

### Aggregate

The findings are spread thinly: GAP-02, GAP-05 and GAP-03 once each, plus one side finding that is not a gap. The dominant pattern is a verification scope that was too narrow. TO-9 named only SQLite.MS, and U-3 covered only tests that reach the validator. Both BLK001 and OOS-1 were cheap to find (a sibling grep, an exclusion grep) and were not searched. The single change with the most effect is a test-obligation rule: any new test with a provider-exclusion or throws attribute must be checked against the siblings in its file and against all providers' behaviour. Together with a sweep of exclusions in the plan's impact map, that would have prevented 2 of the 3 findings. SUG001 is mostly unobservable and not worth a systemic fix.

### Recommended durable fixes

- GAP-03 × 1 → the scout brief in `work-plan/SKILL.md` step 5 — when a fix narrows a rejection or validator rule, add a P7 row for tests that opt out of the affected providers (`[DataSources(... exclusions)]`, `ActiveIssue`). Excluded tests are invisible to any firing census.
- GAP-02 × 1 → an attack vector in `plan-critic.md` — "For each new test, name every provider-conditional attribute and the sibling tests that already use it; if P8 proof runs on fewer providers than the attribute asserts about, flag it." This would also have caught TO-9's SQLite-only scope.
- GAP-05 × 1 → the P8 semantics in `work-plan.md` — when a rejected alternative in P5 is justified by an observable difference, require a TO that distinguishes the two. If none is possible, require D-1 to record that the rejection is untestable.
