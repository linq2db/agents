# Review gap ledger — issue-5814-projectflags-condition-analyzer

## Round 1 — reviewed HEAD c9a9e1ed

| # | Finding | Gap | Gate | Preventable |
|---|---|---|---|---|
| 1 | MAJ — CFG seeded only the graph entry block | GAP-05 | G-01 (12/12 pass; no fixture contains a `try`/`catch`) | partly |
| 2 | MIN — `Directory.Packages.props` comment points "below" at a pin above | GAP-10 | — | no |
| 3 | MIN — TO-5's `HasFlag` arm could not fail | GAP-05 | G-01 (pass recorded without the discrimination check) | partly |
| 4 | SUG — `ProjectFlags.cs` doc understates analyzer reach | GAP-01 | — | yes |
| 5 | SUG — only branch conditions analyzed | GAP-01 | — | partly |
| 6 | SUG — issue-scope narrowing undisclosed | GAP-01 | — | yes |
| 7 | SUG — fixture predicates all expression-bodied | GAP-05 | G-01 (pass; statement-bodied path unexercised) | yes |
| 8 | SUG — `Explain`'s first branch unasserted / unreached | GAP-05 | G-01 (pass; no test inspects message content) | partly |
| 9 | NIT — `ClimbNegations` does not cross `&&`/`||` | GAP-05 | G-01 (P12 nominated TO-3 + census; neither can see message wording) | partly |
| 10 | OOS→fix — `LINQ2DB0006` cross-file reporting | GAP-05 | G-01 (fixture is single-document; structurally cannot discriminate) | yes |

### Detail

- **1 — GAP-05.** D-3 states the algorithm as "entry block all-possible, every other block empty" with no mention of exception-handler regions, and no `TO-n` exercises a `try`/`catch`. `U-4`/`U-5` scouted atom forms and nesting (local functions, lambdas) but never asked whether a CFG region with no ordinary predecessor edge needs its own seed. Unreachable in the current tree, so `TO-6`'s census could not have found it either — a fixture was the only thing that could.
- **2 — GAP-10.** E-9 requires only "extend the comment … Comment only". Copy-editing granularity beneath any `P`-block; a misplaced spatial reference is the prose-defect shape no design document prevents.
- **3 — GAP-05.** TO-5 was rewritten in response to critic objection #4 to defeat two non-discriminating controls, but the *third* arm added at the same time was never itself checked for discrimination the way arms 1–2 were. `P9` records "pass" without the per-arm check `work-plan.md`'s own G-01 rule demands.
- **4 — GAP-01.** E-13 requires only the purpose/modifier split and the `Keys` restriction. D-4's failure-mode requires the two out-of-domain literals and the pragma to be named "or the error is unactionable" — but that was written against the analyzer's own `<remarks>` (satisfied) and never extended to E-13's target file.
- **5 — GAP-01.** Every `SC-n` is phrased around `if`-conditional shapes and D-3 is scoped to blocks with a `ConditionKind`; nothing states that narrowing as deliberate, yet D-6's descriptor wording promises broader coverage than the design delivered.
- **6 — GAP-01.** `U-4` correctly and measurably decides not to implement bitmask recognition, but neither `P2` nor `P3` obligates disclosing the narrowing when the PR carries `Fixes #5814`. The measurement existed at plan time; only the disclosure requirement was never written.
- **7 — GAP-05.** D-5's `Model` stub writes all predicates expression-bodied, while `U-4`'s own scout output shows every real predicate is statement-bodied. No `TO-n` obligates the stub to mirror production's body shape.
- **8 — GAP-05.** The two-reason `Explain()` split is an implementation elaboration of E-1 with no corresponding `P8` obligation; no `TO-n` asserts the `{1}` argument at all.
- **9 — GAP-05.** `P12`'s residual-risk note names exactly this class and nominates TO-3 and the census as the safety net — but TO-3 tests an unrelated shape and the census only diffs ids and counts, never message wording. Both nominated obligations were incapable of catching it.
- **10 — GAP-05.** TO-4c is the only obligation exercising predicate drift, but its stub puts both types in one synthetic source string compiled as a single document, unlike the real two-file split established by `P7`'s own producer sweep.

### Aggregate

Six of ten trace to **GAP-05** — and not in the blunt "no test existed" sense. The tests that *did* exist could not have gone red for the defect they nominally covered: a fixture's synthetic model diverged from production's real shape (expression- vs statement-bodied predicates; single- vs two-file layout), or a control arm added late was not re-subjected to the discipline the plan applied everywhere else, or the obligation nominated as the safety net tested a different shape entirely.

That is the more damning result given how carefully `P8` reasoned about non-discriminating controls elsewhere (TO-3's control, TO-5's two *rejected* controls). The discipline existed and was applied unevenly — missing exactly the places it was not re-run after a late addition, or was never extended to.

Three more (4, 5, 6) are **GAP-01**: requirements the design's own artifacts implied — a diagnostic's message text, an issue's expected-behaviour list, a `<remarks>` disclosure pattern already used once — that `P2`/`P3` never turned into a stated obligation. One (2) is a genuine **GAP-10**.

The highest-yield fix is not "write more tests" but **make every fixture prove it can fail**: mutate the guard it is meant to catch and confirm red, and check that a stub mirrors production's actual syntactic and file shape, before recording the obligation as satisfied. That one habit would have caught 1, 3, 7, 9 and 10.

### Recommended durable fixes

- **GAP-05 ×6 → `work-plan.md` → `P8`.** A fixture or stub standing in for a real production artifact must either mirror its actual syntactic shape (statement- vs expression-bodied, file boundaries) or state why the difference does not matter; and every control obligation must record the mutation applied to confirm it can go red, not merely that it currently passes. Extends the existing TO-3 / TO-5 discriminating-control discipline into a standing check applied to *every* control, including ones added late in response to a critic objection.
- **GAP-01 ×3 → `work-plan.md` → `P2`/`P3` derivation.** When a plan implements an issue, require `P2` to reconcile against the issue's full stated scope line by line and record any narrowing as a `P3` anti-goal carrying a disclosure obligation wherever the PR claims to close that issue; and require a diagnostic's own message text to be checked against the `SC-n` set it is meant to satisfy, so the message cannot promise more than the design delivers.
- **GAP-10 ×1 → no durable fix.** Comment-placement prose is correctly below planning granularity.

### Dispositions

All ten adjudicated in an interactive walk. Nine fixed on the branch across eight commits (`b93ec5e94`…`f3d919d5e`); finding 6 recorded in the PR body. Fixtures 12 → 17, all green; `Source/LinqToDB` Release census 0 warnings / 0 errors. No review posted — nothing was accepted for posting.
