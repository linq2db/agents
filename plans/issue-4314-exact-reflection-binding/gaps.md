# Gap ledger: issue-4314-exact-reflection-binding

## Round 1 — reviewed HEAD c483aefaf

### Attribution

- **MIN001** — GAP-02 — P7 row 1's verdict on the `ReflectionExtensions.cs:136` `GetMemberEx` callers ("26 callers passing a real `MemberInfo`'s parameter types… only ConvertBuilder:82-83 diverged") and P7's contract-change row ("null can only replace today's `ArgumentException`, never a working binding") rest on U-1's divergence probe. That probe instrumented the lookup and let the existing test corpus supply the inputs. No fixture has a base-type overload with wider parameters than the derived member (`Base.Calc(long)` / `Derived.Calc(int)`), so the probe could not diverge at `Linq/Expressions.cs:365`, and its "nothing else" was a verdict built on an absence. The plan could have checked this: P1 defines the consumer contract ("feeds `Expression.New`/`Call`"), and critic round 1 already made P1 list its exceptions, but only the CLI `Invoke` sites were added. `GetMemberEx`'s callers were never read one by one to see what they do with the result, because U-10's per-site read was limited to uninstrumented sites and `GetMemberEx` counted as instrumented. A walk-up that reads `MapMember` registrations is not an `Expression.Call` target. Secondary class GAP-03: the 26 callers were counted but never classified by consumer, which A-1's critic round 3 had to finish (24 sites, 8 previously unlisted). — preventable: yes
  - The G-09 `code-reviewer` pass (2026-10-26) and critic rounds 1–2 inherited the same premise. P12 named it the plan's strongest point.
  - The existing vector at `plan-critic.md:53` ("name the input that must make it say *no*", dated 2026-09-06) predates the plan, but its wording scopes it to "every gate, harvester, sweep or search in `P8`/`P9`". It did not reach a P4 `resolved-by probe`.

Items in commit `80a2fcbb3` with no finding id. The round's list was not persisted, so it is unknown whether these were findings. If they were:
- The `GetRuntimeMethod(Type,string,Type[])` ban: GAP-03. U-5 / D-2 / G-05 scoped the ban to "the 18 `Type[]` overloads of `Type.GetConstructor/GetMethod/GetProperty`", and `banned-api-overloads.ps1` enumerated `Type`'s own members. No search covered BCL extension methods that bind through `DefaultBinder`. Preventable: yes.
- The two `ReflectionExtensions` XML-doc corrections: GAP-10 (prose). Preventable: no.
- Missing for a proper attribution: the round-1 finding ids and texts.

## Round 2 — reviewed HEAD 80a2fcbb3

### Attribution

- **MIN001** — GAP-02 — Same premise as round 1: the P7 row 1 / U-1 verdict on `GetMemberEx`'s callers, here the `MappingAttributesCache.cs:75,85,103-105` attribute walk-up. The plan was never revised after round 1. Secondary class GAP-09, which is why it recurred: the round-1 fix (`80a2fcbb3`, 2026-10-31 21:30) touched `Source/LinqToDB/Linq/Expressions.cs` and `Tests/Linq/Linq/ExpressionsTests.cs`. Neither had an `E-n`, and P11 was still "_None._" (the last plan commit was `57f4d6e` at 19:43; the next was `d36cd4a`, A-1, on 2026-11-01 after round 2). A logged A-n would have owed a `re-derives:` line (`work-plan.md:272`) and a `class:` sibling search (`plan-critic.md:137`) over `GetMemberEx`'s other callers, which is what A-1 eventually did. Instead the fix was a site-local `GetBaseTypeMethod` that left the shared helper strict. — preventable: yes
  - Whether `-Reconcile` ran before round 2 (orchestrator note): it did not. The round-2 review noticed the stale plan by hand at the step-4 scope gate (P6 had no edit-point for `Linq/Expressions.cs` / `ExpressionsTests.cs`, P11 "None") and the user chose to amend after the review. Nobody ran the `review-pr/SKILL.md:176` `work-plan.ps1 -Action reconcile -Head origin/pr/<n>` step, and the round-1 fix commit had no amendment.
- **NIT001** — GAP-10 — A trailing space at `RemoteDataContextBase.cs:537`, carried over from master onto a line the scripted rename rewrote (E-10). No design block would have carried it. The rule that applies (formatting on PR-touched lines) already exists, and the G-09 reviewer pass looked at this line and missed it. That is reviewer recall, not a missing plan entry. — preventable: no

## Aggregate

Two of the three findings are one GAP-02. The plan relaxed a shared helper's matching on the strength of a dynamic probe whose input corpus could not produce the shape that breaks it. It then extended "every consumer feeds `Expression.Call`" to `GetMemberEx`'s 26 callers without reading them. The change that would have prevented both: before approval, list each caller of a tightened helper by what it does with the result, and do not accept a probe over existing tests as a census for an input shape that no fixture contains. Round 2's recurrence also shows a separate process miss: a review fix outside P6 went in without a P11 entry, so the existing sibling-search rules never fired. The remaining finding is a GAP-10 whitespace nit.

## Recommended durable fixes

- GAP-02 × 2 → the scout brief in `work-plan/SKILL.md` step 5, beside the decline-census rule. When an edit-point makes a shared helper match *less* (it returns null for, or rejects, inputs it used to accept), list every caller with what it does with the result: `Expression.Call`/`New` target, reflection `Invoke`, metadata or attribute read, base/interface walk-up. A helper that has been probed still needs this per-site read whenever the probe's corpus lacks the input the tightening rejects.
- GAP-02 × 2 → widen `plan-critic.md:53` from "`P8`/`P9`" to also cover P4 `resolved-by probe` rows. When a probe resolves an unknown by instrumenting code and running the existing test corpus, demand the input that would make it diverge and evidence that the corpus contains that input. If it doesn't, the unknown is unresolved for that shape.
- GAP-03 × 1, conditional on the round-1 ban item having been a finding → `plan-critic.md`, an attack vector for "ban the API family" decisions: the ban's census enumerates every BCL entry point that reaches the same binder (extension methods such as `RuntimeReflectionExtensions.GetRuntimeMethod`), not only the named type's own overloads.

## Continuity

- Round 1 → round 2: the round-1 fix addressed one instance (`Linq/Expressions.cs:365`) with a local helper. The shared helper and the P7 premise stayed unchanged, and no A-n was written. Round 2 found the same mechanism at the next caller of the same helper. The existing rules (`work-plan.md:113,272`, `plan-critic.md:137`, `review-pr/SKILL.md:176`) cover this, and none of them was applied.
- After round 2: A-1 (`d36cd4a`) adds D-6 (master's coercing lookup inside `GetMemberEx`), E-26/E-27, TO-9/TO-10, and a 24-site `GetMemberEx` census in P7 after critic round 3. That closes the GAP-02 premise for this branch. The durable fixes above are for the next plan with the same shape.
