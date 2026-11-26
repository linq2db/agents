# Gap ledger: issue-4053-eager-load-transaction-option

## Round 1 — reviewed HEAD e0dd537aa

- **SUG001** (Suggestion) — GAP-05 — `P8` TO-17 fixed the shim's discriminating input as one row ending `true, false, true` and called it "a positional pattern a reordering changes"; D-4's failure mode covers every reordering of the same-typed bools, and one row of two-valued bools over three positions must repeat a value, so swapping `optimizeForSequentialAccess` / `useCombinedCommands` stayed green. `G-01` recorded only M-d, a swap the row happens to separate. Fixed in `399df2315` (`[Values] bool useCombinedCommands`; the swap mutation reddens only the `False` case). — G-01 — preventable: yes

## Aggregate

One finding, GAP-05: the obligation existed, but its own literal input could not deliver the property its wording claimed. TO-17's pattern was written in the revision answering critic round-1 objection 1, and a `weak` verdict's revision is not sent back to the critic, so no critic round read it.

## Recommended durable fixes

- `skills/work-plan/SKILL.md` step 7, *Reconcile by verdict*, `weak` bullet — a revision that rewrites a `TO-n`'s input, assertion or recorded mutation to answer a `weak` objection goes back to the critic as a delta round scoped to those rows; otherwise `P12` lists them as `not re-attacked`.
- `docs/work-plan.md` *P8 Test obligations*, beside the discriminating-input rule — an obligation over forwarding across k same-typed positions (compat shim, `Deconstruct`, copy constructor, positional mapper) owes rows giving each position a distinct value vector (for `bool`, at least ⌈log₂ k⌉ rows; `[Values]` on one position is the cheap form), and `G-01` records a transposition mutation for each pair any single row maps to equal values. Example: three bools in one row cannot differ pairwise (#6456 SUG001).

## Corpus trace

- SUG001 — rules: `docs/work-plan.md` (record the discriminating input; a mutation confirms it), `agents/plan-critic.md` (`separates:` rows are computed, fold-ins scrutinised hardest), `docs/review-rubric/rubric-tests.md` (an input that cannot separate the arms). Why none fired: the row entered in a `weak`-verdict revision no critic saw; the P8 rule asks for the input to be named, not checked against every member of the `D-n` failure mode; one mutation satisfies "break the product, confirm the fixture reddens", and nothing asks the mutation set to span the failure mode; the implementing agent copied the plan's claim into the test comment ("differ pairwise") beside a row that contradicts it. Recurs: `plans/feature-1475-pivot-unpivot/gaps.md` (MIN203, GAP-05, same pairing class); `plans/feature-6021-scaffold-codegen-harness/plan.md` (A-3, a key whose two orders coincided). Neither produced a rule about inputs separating same-typed positions.
