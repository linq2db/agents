# Gap ledger: feature/5717-dml-output-as-source

No work plan on this branch; each row names the absent block that would have carried the finding.

## Round 1 — reviewed HEAD 6f9f0473b4d73c0d66881b7be6dd9a9928a8dab8

- **MIN005** (dynamic column throws at render) — GAP-03 — needed a P7 mirrored-site row for InsertWithOutput, whose Sql.Property output works while the name-keyed lookup in BuildDataModificationCteBody only searches target.Fields; second class GAP-05, no TO-n read a column outside the mapped entity — — — preventable: partly
- **MIN006** (remark false under eager loading) — GAP-02 — needed a P11 amendment for the earlier SUG001, backed by a P4 row on transaction × eager load × direct/remote; the remark arrived in 545a7d49f when EagerLoadOverOutputRollsBackOnFailure already existed — — — preventable: partly
- **MIN007** (two unnecessary DisableBaseline waivers) — GAP-10 — waivers came in 4fa6e5da4; CommitTransaction stripping arrived on the parallel stack line in ec94a2892, a dependency that moved mid-branch — — — preventable: no
- **MIN008** (Concat source renders UNION ALL after RETURNING) — GAP-03 — needed a P7 row for the insert-from-source render path the new overload inherits; the shape was refused on the CTE body only — — — preventable: partly
- **SUG002** (EagerLoad message does not fit QueryBatch) — GAP-10 — message wording; no plan block carries it — — — preventable: no
- **SUG003** (Correlated message, untested arm) — GAP-05 — needed a P8 TO-n per overload; CorrelatedCallThrows covers only the setter overload — — — preventable: yes
- **SUG004** (repeated AllPostgreSQL attributes) — GAP-01 — no written rule exists, only sibling practice — — — preventable: partly
- **NIT001** (missing space) — GAP-10 — typo; no plan block carries it — — — preventable: no
- **NIT002** (`=` misaligned) — GAP-07 — no plan-step embed of the alignment rule; the catch is the diff read — G-06 — preventable: partly
- **NIT003** (`=>` misaligned) — GAP-07 — same embed; the touched-lines rule pulls the other way — G-06 — preventable: partly
- **NIT004** (missing LinqTunnel) — GAP-07 — no plan-step embed of the JetBrains-contracts rule — — — preventable: partly

### Aggregate

4 of 11 findings trace to blocks a Tier L plan would have required: P7 (MIN005, MIN008), P4/P11 (MIN006), P8 (SUG003). Three (NIT002-004) trace to the convention embed at low marginal value. Four map to no existing block. The substantive cluster is GAP-03: what the new API inherits from the existing insert pipeline was never enumerated.

### Recommended durable fixes (unverified, for session-reflect)

- work-plan SKILL step 5 scout brief: for a new public API over an existing pipeline, list the input shapes that pipeline accepts (dynamic columns, set-operator sources, each overload), one P7 verdict each.
- acting-on-findings.md: a behavioural sentence added to answer a finding is checked against the branch's own tests on that subject before it lands.
- testing.md: reports that BaselinesWriter.Normalize does not strip the commit, while origin/master strips CommitTransaction.
