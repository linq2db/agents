# Gap ledger — issue/6303-fix-interceptor-cache-key (PR #6444)

## Round 1 — reviewed HEAD 8cfd32eb8f0e6fe7a3a8a38b97c3a779e919c202

No work plan on this branch (no-plan); no P9 record. Attribution names the block a Tier L plan would have needed (query-cache keying across three context types + remote, new public API).

- **MIN001** (#4266 snapshot only for the exact base `[SqlQueryDependent]`) — GAP-02 — unprobed assumption "a subclass has a custom ObjectsEqual that expects its own collection type", encoded as `attribute.GetType() == typeof(SqlQueryDependentAttribute)` (`ExpressionCacheManager.cs` diff :207-215); a P4 row with a sealed no-override subclass mutated in place returns [1, 2] (pr6444-proofs.md P1); second class GAP-05, no TO-n with a user-defined subclass — — — preventable: partly
- **MIN002** (`IInterceptorCacheKey` doc omits null-key meaning, read time, breach consequence) — GAP-01 — no D-n for the new public contract named what `null` means; the meaning lives only in `HasUntrustedQueryInterceptor`'s `is not IInterceptorCacheKey` (`InterceptorInternalExtensions.cs:134-142`), which EF Core and F# rely on; breach consequence is in the PR body's Cons, not the doc; second class GAP-08, `definition-of-done.md:14` had no D-n to check against — G-03 — preventable: yes
- **MIN003** (remote configuration-ID resets / UseOptions restore have no failing test) — GAP-05 — P8 needed a TO-n per context-type edit (`RemoteDataContextBase` Remove reset, scope restore), each proven by a mutation reverting that edit; the covering tests are `IncludeDataSources(false, …)`; mutation A turns no query-interceptor arm red, mutation B one (proofs P2) — G-01 — preventable: yes
- **SUG001** (per-stage invocation contract missing on `IQueryExpressionInterceptor`; `IEntityBindingInterceptor` contract absent) — GAP-03 — P7 had no row for each extension-point interface whose invocation frequency changes, carrying the per-stage delta; the PR body's "Interceptor without a key" list was that delta, only the keyed remark reached `IQueryExpressionInterceptor.cs:8-11`, `IEntityBindingInterceptor.cs` not in the diff; second class GAP-08 (`definition-of-done.md:14`) — G-03 — preventable: yes
- **SUG002** (no `IEntityBindingInterceptor` add/remove after the ID is computed) — GAP-05 — `IsTranslationInterceptor` admits two entries (`InterceptorInternalExtensions.cs:75`); `work-plan.md:164` gives each admitted entry a TO-n + removal mutation; only `IQueryExpressionInterceptor` is tested after the ID is computed; mutation turns 6/6 ported arms red (proofs P3) — G-01 — preventable: yes
- **SUG003** (`HasPlainValueEquality` guard untested) — GAP-05 — closed type-keyed admission predicate; rejected side (struct whose IEquatable<T>.Equals differs from Equals(object)) needed a TO-n + mutation (`work-plan/SKILL.md:99`, `work-plan.md:164`); code "taken from #6314" without #6314's `BakedStructValueComparedAsBefore`, which goes red under the mutation (proofs P4) — G-01 — preventable: yes
- **SUG004** (nothing pins that default EF Core and F# interceptors stay keyed) — GAP-05 — the body claim "EF Core's default setup is keyed and pays nothing" needed a TO-n per built-in implementer of the opt-out (cache-miss or QueryFilter-stage call count); `CustomImplementationRewritesAreNotShared` covers only the keyless side — G-01 — preventable: yes
- **NIT001** (`InterceptorsTests.cs` one-line/nested chains; new `#region`) — GAP-08 — `test-diff-sweep.ps1` gate at `definition-of-done.md:11` applies plan or not; at head it reports 14 chains + 11 nested in this file (every cited site but 1941), so not run or hits ignored; second class GAP-07, `#region` rule (`testing.md:641`) has no detector — G-01 — preventable: partly
- **NIT002** (`CachingTests.cs` chains, nested DataOptions, one-line query syntax, Description #4266 vs #5810) — GAP-08 — sweep reports all 11 chains + 3 nested; one-line query syntax (`testing.md:703`, rule 2) has no detector; wrong Description number is a prose slip (GAP-10 part) — G-01 — preventable: partly
- **NIT003** (one-line chain `CompileTests.cs:1274`) — GAP-08 — the sweep reports exactly this line (pr6444-testsweep.json) — G-01 — preventable: yes

### Aggregate

10 of 10 trace to blocks a Tier L plan or a plan-independent DoD gate would have required; none GAP-10 (only NIT002's Description slip is prose). Dominant class GAP-05 ×4 (MIN003, SUG002, SUG003, SUG004): a two-sided predicate or per-context edit with a red-capable test on one side or one context only (keyless vs keyed opt-out, IsTranslationInterceptor's two entries, HasPlainValueEquality's rejected side, remote reset/restore).

Highest-yield plan-independent change: when a branch is an alternative to, or ports code from, another open PR, walk that PR's review threads and carry over the tests and out-of-diff docs added in response — would have prevented MIN003, SUG001, SUG002, SUG003; #6314 had all four answers by 2026-11-19 (igor-tkachev replies 4627025625, 4627026260; `BakedStructValueComparedAsBefore`), while 19 of #6444's 22 commits are dated 11-19..11-22.

Goal-level rescope traces to P1 scope: bundling #4266/#5810 breaks `AGENTS.md:72` (separable fix → own PR).

### Continuity with #6314

| #6314 review finding / fix | Recurs on #6444 as |
|---|---|
| MIN001 remote arms; igor's measured reply 4627025625 (remote query-interceptor arms stay green with remote reset reverted → added `AddAndRemoveEntityBindingInterceptor`) | MIN003 + SUG002 |
| SUG002 `IEntityBindingInterceptor` contract; fixed on #6314 by remarks on `ConvertConstructorExpression` (4627026260) | SUG001 (second half) |
| SUG003 per-execution contract on `IQueryExpressionInterceptor` | SUG001 (first half) |
| #6314's own `BakedStructValueComparedAsBefore` | SUG003 |

#6444 took #6314's code answers (translation-only reset, self-join accessor sharing, typed comparison) but not the tests / out-of-diff docs that pinned them; `CommandInterceptorKeepsCachedQuery` not ported either.

None of the three #6314-ledger durable fixes landed (fix 1: no "extension point's / invocation frequency / declaration doc" in `skills/work-plan/SKILL.md`, `code-design.md:105` still facades only; fix 2: no "sibling type / context type / in parallel" in `agents/plan-critic.md`; fix 3: no alignment-drift / blank-line category in `test-diff-sweep.ps1`). Fixes 1–2 are plan-time and could not fire on a plan-less branch; fix 2 is also insufficient as worded — "one TO-n per sibling type" is satisfied by remote arms of query-interceptor tests, which igor's measurement and mutation A show stay green; only an interceptor whose output is not re-checked (entity binding) or a scope-restore test witnesses the key.

### Recommended durable fixes

- GAP-05 ×4 (MIN003, SUG002, SUG003, SUG004) → `docs/work-plan.md` P8 next to `:164`, mirrored as a `plan-critic.md` vector: every entry of a trust / opt-out / admission predicate gets a TO-n on both sides, built-in implementers included; every per-context-type edit of a cache key / reset / restore gets a TO-n proven by a mutation reverting that context's edit; a test whose rewrite is re-validated on a cache hit does not witness the key.
- Continuity ×4 (MIN003, SUG001, SUG002, SUG003) → `skills/work-plan/SKILL.md:93`, mirrored in `definition-of-done.md` so it binds a plan-less branch: when a branch is an alternative to, or ports code from, another open PR, list that PR's review findings with resolutions and the tests/docs added in response, each a row `applies` / `n/a: <reason>`; ported code brings its tests.
- GAP-03/GAP-01 ×2 (SUG001, MIN002) → `docs/code-design.md:105`/`:111` (re-proposes #6314 fix 1): the written semantic contract (invocation points, frequency) also applies when a change alters an existing static interception point's invocation frequency, per stage on the interface doc; a trust / opt-out interface's doc states what its default / null value means, when it is read, and what a broken contract does; `definition-of-done.md:14` checks the doc against that.

## Corpus trace

- MIN001 · rule: `skills/work-plan/SKILL.md:137` (sweep a public attribute's declarers; user-defined declarer gets a TO-n) · why not: no plan; rule covers declarers, not subclasses; author's comment shows the override case was considered but implemented as a type-identity check that also catches no-override subclasses · correction: `SKILL.md:137` — when code branches on a public non-sealed type's runtime type to detect an override, key on the overridden member, and give a no-override user subclass a TO-n · recurs: #6003 round 2
- MIN002 · rule: `docs/code-design.md:111` (extension point states its query-cache behaviour; scoped to proposed points); `definition-of-done.md:14` · why not: no D-n; downside reached PR body Cons, not doc; null meaning never written · correction: durable fix 3 · recurs: issue-v6-regression-long-alias/gaps.md:11; #6008 SUG002/SUG003
- MIN003 · rule: `docs/work-plan.md:164` (recognisers); `agents/plan-critic.md:62` (`IncludeDataSources(false, …)` runs no .LinqService case) · why not: no plan; no rule ties a per-context-type edit to a mutation-proven arm · correction: durable fix 1 · recurs: fix-6303-interceptor-cache/gaps.md:11 (MIN001); its fix at `:25` did not land and is insufficient as worded
- SUG001 · rule: `docs/code-design.md:105` (facades only) · why not: static interception point out of scope; author wrote only the keyed case; #6314 remarks not carried over · correction: durable fix 3 · recurs: fix-6303-interceptor-cache/gaps.md:8-9; fix 1 at `:24` did not land
- SUG002 · rule: `docs/work-plan.md:164` · why not: no plan; only entity-binding test registers before first query; #6314's test not ported · correction: durable fixes 1, 2 · recurs: #6316 SUG001; #6314 MIN001 follow-up
- SUG003 · rule: `skills/work-plan/SKILL.md:99`; `docs/work-plan.md:164` · why not: no plan; ported from #6314 without its pinning test · correction: durable fix 2 · recurs: #6197
- SUG004 · rule: `docs/work-plan.md:164`; `definition-of-done.md:28` (body claims checked against code — wording, not test coverage) · why not: no plan; no rule asks for a test of a cost claim on a built-in implementer · correction: durable fix 1 · recurs: —
- NIT001/NIT002/NIT003 · rule: `docs/testing.md:655`, `:703`, `:641`; `definition-of-done.md:11` · why not: sweep reports 26 chains + 14 nested at head, so not run or not acted on; unknown whether the author's session loaded this corpus; `#region`, one-line query syntax and nested site 1941 have no detector · correction (optional): `test-diff-sweep.ps1` category for an added `#region` under `Tests/` · recurs: fix-6303-interceptor-cache/gaps.md:15; issue-v6-regression-long-alias/gaps.md:52
- goal-level rescope · rule: `AGENTS.md:72`; `skills/work-plan/SKILL.md:93` · why not: no plan · correction: none new · recurs: —
