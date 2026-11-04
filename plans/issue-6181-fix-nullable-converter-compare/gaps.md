# Gap ledger — issue-6181-fix-nullable-converter-compare (PR #6189)

## Round 1 — reviewed HEAD 0b843abf0

## Attribution

- **MIN001** — GAP-02 — P5 D-1 as widened by P11 A-2 item 6 (reference-type guards admitted via IsNullableOrReferenceType) assumed `HasValue` can only be `Nullable<T>.HasValue`; the P5 failure-mode text names only a non-null null arm and reversed arms, and the P8 list for A-2 (TO-11..TO-18) has no reference-type-with-own-HasValue cell; the A-2 delta was re-critiqued as `weak` without this probe (SequenceHelper.cs:186-187 vs gate at :161) — — preventable: yes
  - Not GAP-08: no gate was skipped. The defect came in through the amendment, so the amendment's re-critique missed it, not the original P5.
  - Not determinable: whether the A-2 re-critique considered a user-defined `HasValue` at all; the plan records only "objections answered".
- **NIT001** — GAP-10 — prose/formatting nit (stray blank line after the class brace, SequenceHelper.cs:21-23); no plan block carries whitespace, and the G-05 builds do not flag it — — preventable: no
- **NIT002** — GAP-10 — a comment re-wrap left a short line mid-paragraph (SequenceHelper.cs:57-60); no design artifact prevents this — — preventable: no
- **NIT003** — GAP-05 — P8 TO-6b ("the values must already hold", plan P8) and the new mutation-guard test `Issue6181_DelegatingThroughAnUnsetHolderMaps` cannot go red on master. The plan labelled both correctly as characterization/guard, but the PR body claimed "red before the fix, plus a mutation control for each mechanism". The body claim was not reconciled against the P8 proof labels. — — preventable: yes
  - Secondary: the PR-body step has no cross-check of P8 `proof:` values against the Tests section.

## Aggregate

The ledger is flat: 1 GAP-02, 1 GAP-05, 2 GAP-10. There is no systemic fix, only individual misses. The one substantive finding (MIN001) came from the A-2 amendment, not the original design. A-2 widened D-1's parameter kinds, and the delta was re-critiqued `weak` without a probe for a same-named member on a different type. The nits are prose and process; the two formatting nits cannot be prevented by any design artifact. The out-of-scope GetLambdaID observation is a variant of the P10 "ToString not value-bearing" residual, now named in P10 (A-3). It has no gap row because it is not a finding.

P9 bookkeeping at review time: G-01 had no per-TO rows (TO-1b..TO-18) and no test-diff-sweep counts. This was a recording lapse, not tied to any finding. G-02 was discharged by the review (all 69 modified baselines are SetOperationOverNullableAndPlainConversions).

## Recommended durable fixes

- GAP-02 × 1 → `plan-critic.md` attack vector: when an amendment widens a recogniser's input kinds (value type to reference type, etc.), require a probe cell for each name-matched member check (`HasValue`, `Value`, `Length`) against a user-defined type with a same-named member, and require the amendment's P8 to list it.
- GAP-05 × 1 → `work-plan.md` P8 `proof:` → PR-body claim: when writing the PR Tests section, claim red→green only for TOs whose P8 proof is `red→green`, and label characterization / guard TOs as such.
