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
