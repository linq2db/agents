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

## Round 2 — reviewed HEAD 2f77524bd

- **SUG001** (E-2's widened arm, `ParametersContext.cs:290`, fires for any two different enums; unpinned for the unregistered case) — GAP-05 — D-2's failure mode named the case, but P8 never turned it into a TO; TO-24's `DtoGender` has the same MapValues as `Gender` and covers a constant only, so it cannot go red. Second class GAP-02: the consequence was recorded in prose and never measured; `DirectCastToEnumWithOtherMapValuesEqualParameter` shows master returning 0 rows instead of 1 (`CAST([p].[Gender] AS NVarChar(255)) = 'Female'`), so E-2 also fixes a bug outside the feature — — — preventable: yes

### Aggregate

1 finding: GAP-05, second class GAP-02. A D-block failure mode stated in prose with no discriminating TO, next to a sibling TO whose fixture coincides with the intended case.

### Recommended durable fix

- GAP-05 → `docs/work-plan.md` P8 semantics and an `agents/plan-critic.md` attack vector: every "failure mode of the choice" line maps to a TO whose fixture discriminates the failing input from the intended one (measured red/green), or says why none is needed; the critic checks that a sibling TO's fixture does not coincide with the intended case.

### Continuity with round 1

- GAP-05 recurs: round 1's MAJ001 also lacked an obligation next to a TO that existed but did not discriminate (closed by TO-19/TO-20).
- GAP-03, GAP-07 and GAP-10 do not recur.

## Round 3 — reviewed HEAD 6d69aeb09

- **MAJ003** (TO-37 #6298 gate red on strict providers, `EnumMappingTests.cs:2918`) — GAP-02 — A-4 pinned TO-35..TO-38 on bare `[DataSources]` with one declared failure from a SQLite.MS-only measurement, while G-01 already recorded the head SQL as `CAST([Gender] AS INTEGER) = @gender` with `'F'`, an int-vs-string compare a strict server rejects; second class GAP-08: G-01 recorded `pass` with "left to `test-all`" in its sub-bullets, which `work-plan.ps1` validates only on the head line and one spelling; no CI ran TO-37 (6d69aeb09 never built: Linux legs ran 89c474425, Windows restore failed without #6295) — G-01 — preventable: yes

### Aggregate

1 finding, GAP-02 (second class GAP-08): a known-issue gate claimed for every provider from one provider's measurement, against the plan's own recorded SQL and with a strict-provider container already in use.

### Recommended durable fix

- GAP-02 → `docs/testing.md` *Gating an assertion failure* (embedded by `skills/work-plan/SKILL.md:73`): an unscoped `[ActiveIssue]` on bare `[DataSources]` is measured on one strictly typed provider and one file DB before pinning; a recorded mismatched-type compare (`CAST(col AS Int) = 'F'`) predicts a server error, so scope the gate or use `no-declaration:`.
- GAP-08 → `scripts/work-plan.ps1` -Validate: fold G-01 sub-bullets into the "left to CI" check and match "left to `test-all`" / "pending"; warn on a bare-`[DataSources]` P8 row measured on SQLite only with no reason.

### Continuity with rounds 1-2

- GAP-02 recurs from round 2's second class (SUG001), in the same #6298 area: a cross-provider claim stated from one provider.
- Round 1's GAP-07 fix (sibling gate inheritance) landed but does not cover a new gate's reach.
- Round 2's recommended P8/critic rule ("sibling fixture does not coincide") was not found in `docs/work-plan.md` or `agents/plan-critic.md`; unverified whether it landed under other wording.
