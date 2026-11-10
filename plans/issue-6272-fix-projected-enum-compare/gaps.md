# Gap ledger: issue-6272-fix-projected-enum-compare

## Round 1 — reviewed HEAD 466207b6a

- **MAJ001** (direct cast with constant returned wrong rows, `ExpressionBuildVisitor.cs:2861`) — GAP-03 — U-4 and P7 mapped E-1's consumers by searching the flag, so `ConvertEnumConversion` got no row: it never reads the flag, keys on the raw `left.NodeType is Convert`, and for this cast runs only once E-1 lets the operand build; second class GAP-05, since no TO put the cast and the constant in one predicate until TO-19 and TO-20 — — — preventable: yes
- **MAJ002** (`DistinctBy` test without its sibling's gate, `EnumMappingTests.cs:2602`) — GAP-07 — TO-16 had no sibling comparison; `testing.md:540` requires a new test to inherit a same-mechanism sibling's measured gate or run the provider, but the step-4 embed reduces that to gates a TO adds, and the critic vector compares only siblings in the same fixture — — — preventable: yes
- **MIN002** (union tests on bare `[DataSources]`, `EnumMappingTests.cs:2513`) — GAP-07 — same rule on TO-13 and TO-14; the code was correct, and the only gap was the measurement A-1 later made on Access.Ace.OleDb and Firebird.2.5 — — — preventable: yes
- **NIT001** (field alignment, `ParametersContext.cs:402`) — GAP-10 — the alignment column exists only once both field declarations are typed — — — preventable: no

## Aggregate

GAP-07 is the most frequent class (2 of 4). GAP-03 (1 of 4) matters most, because it is the only wrong-results finding: the map was keyed on the flag name, and the critic searched by the same key.

Unestablished: whether step 4 embedded *A narrowed provider set is a claim* (if it was, the two GAP-07 rows become GAP-06), and whether the scouts had the rule at `work-plan/SKILL.md:107`, which landed about three hours before the plan commit.

## Recommended durable fixes

- GAP-07 × 2 → `skills/work-plan/SKILL.md:71` (step 4 embed): add that a new bare `[DataSources]` test inherits a same-mechanism sibling's measured gates or runs those providers.
- GAP-07 × 2 → `agents/plan-critic.md:55`: widen "same-shape tests in that fixture" to the home fixture of each operator or load strategy the test exercises, and state that a bare `[DataSources]` is in scope.
- GAP-03 × 1 → `skills/work-plan/SKILL.md:107` (reword): extend the trigger to branches that key on the raw input expression and run once the operand builds, and require a flag-gated change to sweep the consuming methods as well as the flag's setters and readers.
