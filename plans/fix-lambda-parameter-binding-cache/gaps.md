# Gap ledger — fix/lambda-parameter-binding-cache (#6258)

No work plan on this branch (external contributor). Each row names the block that would have carried the finding.

## Round 1 — reviewed HEAD 72bc50dc0cd7717337b3b6437441e985346936a5

- **MAJ001** (major) — GAP-02 — `EqualsToVisitor.cs:127-129` rests on the unprobed premise "a shared node cannot be accepted under different bindings"; a `P4` probe instrumenting the reference-shared reject branches over the `TestQueryCache` corpus would have enumerated `SqlQueryRootExpression` (captured `ITable` inlined as one instance) and `ConstantPlaceholderExpression`, both parameter-free leaves; secondary GAP-05 (no `TO-n` asserting flat `GetCacheMissCount` across runs reusing one queryable) — — — preventable: yes
- **MIN002** (minor) — GAP-05 — `FailedComparisonDoesNotRetainBindings` (`ExpressionComparisonTests.cs:276-282`) needed a `P8` `TO-n` with a recorded mutation (drop pool `Clear` + lambda-arm `Pop`) and a discriminating input (fresh same-named parameter); the NUnit `Assert.Throws` half is GAP-07 — — — preventable: yes
- **NIT001** (nit) — GAP-07 — one-call-per-line assertion-chain rule (`testing.md` Test layout rule 1) is on-demand and absent from `.github/copilot-instructions.md`, the surface an external contributor's tooling reads (`TestQueryCache.cs:415-416`) — — — preventable: partly

### Aggregate

All 3 findings trace to blocks a Tier M plan would require (one `P4` probe, one `P8` obligation with a recorded mutation, one embedded convention). Classes spread evenly (GAP-02, GAP-05, GAP-07); no single systemic fix. Highest-value change: a critic question for changes that make the cache key *stricter* — "which legitimately equal trees does the new reject branch fire on?". The cache-key vectors in `plan-critic.md` attack only the lenient direction (stale hits).

### Recommended durable fixes (route to `/session-reflect` plan-rule bucket)

- GAP-02 → `plan-critic.md` attack vector beside the cache-key vectors: for an accept→reject change in `EqualsToVisitor` / `ExpressionEqualityComparer`, enumerate the node types reaching the new reject branch by instrumenting it over the cache suite; shared instances inlined from a captured `ITable`/`IQueryable` and placeholder leaves must stay hits; require a flat-`GetCacheMissCount` characterization `TO-n` over a reused queryable.
- GAP-05 → `testing.md`: a cleanup test for pooled/reset state must probe with an input the leaked state answers differently, and name the mutation that turns it red.
- GAP-07 → `.github/copilot-instructions.md` (linq2db repo, not the corpus): inline Test layout rule 1 next to the Shouldly line.

## Round 3 — reviewed HEAD f371bb8cf7f6185a9e7879f676d1fe464ff55d24

Post-merge review (merged 2026-11-13 as 9b92c1734). No work plan (external contributor); each row names the block that would have carried the finding. All five findings were accepted for a follow-up PR (`issue/6258-cover-comparer-scope-ends`, [#6320](https://github.com/linq2db/linq2db/pull/6320)); a perf observation (shared-subtree walk per lookup, estimated linear) was dropped.

- **SUG001** (suggestion) — GAP-05 — the three `_declared.RemoveRange` scope exits (`EqualsToVisitor.cs:606/616/627`) arrived in `e3dee59cd`, the post-round-1 MAJ001 redesign; on a planned branch that is a `P11` amendment needing one `P8` `TO-n` per scope kind (lambda/block/catch: a reference after the scope inside a shared subtree) with the reddening mutation; measured 28/28 existing tests green under the mutation — — — preventable: yes
- **SUG002** (suggestion) — GAP-05 — the block-arm `bindings.Pop(count)` (`EqualsToVisitor.cs:148`) dates from `2d3c71ed9`; round-1 MIN002 added mutation coverage for the lambda arm only (catch already covered); a `P8` `TO-n` per arm of the scope restore was needed — same class as round-1 MIN002, on the success path — — — preventable: yes
- **SUG003** (suggestion) — GAP-05 — `IsVisitedKind` (added `1897d0611`, the last code commit) needed a `P8` `TO-n` per branch; kind `1000` (`ChangeTypeType`, the exact-type special case) is the one branch `SharedNodesOfUnknownKindAreRejected` (`ExpressionComparisonTests.cs:189`) never selects; the test exists, so a cheaper plan might still have picked the same three kinds — — — preventable: partly
- **NIT002** (nit) — GAP-06 — the narrowed-provider-set reason rule was on the contributor surface (`.github/copilot-instructions.md:40`, an ancestor of the PR's first commit) and in `testing.md:545`, yet four `[IncludeDataSources(TestProvName.AllSQLite)]` tests (`TestQueryCache.cs:223,288,375,421`) lack it; a plan would carry it in its embedded step-4 baseline; secondary: no Copilot review ran on #6258, and round 1 did not flag the three tests already present — — — preventable: partly
- **DOC** (documentation) — GAP-03 — `P7` had no row for the public virtual `SqlQueryDependentAttribute.ExpressionsEqual` (its overriders and its `context` doc at `SqlQueryDependentAttribute.cs:70`), whose argument the PR changed from `null` to `bindings`, now dereferenced by the comparer; the scout triggers at `work-plan/SKILL.md:131/133` cover readers and declarers but not a change to what a reader passes into an attribute's public virtual — — — preventable: yes

### Aggregate

3 of 5 findings (SUG001–SUG003) are GAP-05: a multi-arm mechanism (scope-exit restores across lambda/block/catch; the branches of a kind filter) where only some arms have a test that can go red. All 5 trace to blocks a Tier M plan would require (three `P8` obligations, two on post-round-1 amendments; one embedded convention; one `P7` row). Highest-leverage fix: one `testing.md` rule requiring each arm of a scope-restore or kind-dispatch mechanism to have its own case with a recorded mutation, on the success path as well as the failure path.

### Recommended durable fixes (route to `/session-reflect` plan-rule bucket)

- GAP-05 × 3 → `testing.md`, beside the round-1 rule at `:734` (which covers cleanup "after a failure" only): in a visitor that pushes and pops scope state, each scope kind gets a success-path case referencing the scope's variable after it closes, plus a recorded mutation; a kind filter with a special case gets a case for that exact special case.
- GAP-03 × 1 → `work-plan/SKILL.md:133`: when a reader changes what it passes into a public attribute's virtual (a `context` that was `null` and is now dereferenced, a new delegate shape), the overriders and that member's `<param>` docs each get a `P7` row.
- GAP-06 × 1 → `.github/copilot-instructions.md:40` (linq2db repo): add a do/don't example of the required reason line, e.g. `// Query-cache test: provider-independent.` above an `[IncludeDataSources(...)]` test.

### Continuity

- **Round-1 MIN002 recurs as SUG002.** Its fix covered the lambda-arm `Pop` only, and the rule it produced (`testing.md:734`) is scoped to failure-path cleanup, so it would not catch the block arm's success-path restore. The first durable fix above widens it.
- **Round-1 NIT001's attribution premise was wrong.** It said the one-call-per-line rule was absent from `.github/copilot-instructions.md`; it was at `:39` in the PR's own base. NIT001 and NIT002 share one mechanism: the rule was on the contributor surface, but Copilot review never ran on #6258.
- All three round-1 recommendations are now in place (`plan-critic.md:120`, `testing.md:734`, `copilot-instructions.md:39`).
- Round-2 MIN003 (stale PR body) does not recur.
