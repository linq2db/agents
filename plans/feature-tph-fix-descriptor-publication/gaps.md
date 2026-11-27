# Gap ledger — PR #6454 (feature/tph-fix-descriptor-publication)

No plan on branch (external-author PR). Each row names the block that would have carried the finding.

## Round 1 — reviewed HEAD e34f564bd870111a9ae030cb97d59f87a53535fc

- **SUG001** (exception-path test cannot detect a missing stack restore) — GAP-05 — needed a P8 TO-n for the root-build stack's failure path at TphInheritanceTests.cs:1886-1912 with a recorded delete-the-`finally` mutation shown red, plus a TO-n for the untested RootBuildScope in InitInheritanceMapping — G-01 — preventable: yes
- **SUG002** (AsyncLocal + ThreadId + IsEnded emulate banned [ThreadStatic], EntityDescriptor.cs:240-251) — GAP-04 — needed a P5 weighing how the in-progress root reaches a re-entrant call (explicit context per #6487; thread-local under a scoped RS0030 pragma; flow-local) against the ThreadStaticAttribute ban; arrived in MIN001 fix e5b77aba3, so on a planned branch the P11 amendment that should have re-run P5; second class GAP-01 (ban has no sanctioned exception path) — — — preventable: partly
- **SUG003** (root rebuild re-invokes descriptor-created callback N+1 vs master 1, EntityDescriptor.cs:345) — GAP-01 — needed a P2 criterion naming the callback-invocation contract as observable behaviour; second class GAP-03 (P7 rows for EntityDescriptorCreatedCallback, ConnectionOptions.OnEntityDescriptorCreated, DataOptions.UseOnEntityDescriptorCreated); introduced by e5b77aba3 — — — preventable: partly
- **NIT001** (nine one-line assertion chains + one misalignment, TphInheritanceTests.cs) — GAP-07 — rule exists (testing.md:659, CONTRIBUTING.md:346, copilot-instructions.md:41); no conventions baseline in front of the author and no G-01 test-diff-sweep run — G-01 — preventable: partly
- **NIT002** (first Debug.Assert in Source/, compiled out of Release, ColumnDescriptor.cs:872) — GAP-01 — no corpus rule or ban on Debug.Assert in Source/; rule that should exist: an invariant check in Source/ throws InvalidOperationException or is removed — — — preventable: partly

### Aggregate

4 of 5 trace to blocks a Tier M plan would have required (P8, P5/P11, P2/P7, conventions baseline); NIT002 needs a rule that does not exist. None GAP-10. SUG002 and SUG003 share one cause: the plan never stated, as a P2 requirement, that a descriptor-created callback can re-enter GetEntityDescriptor (igor-tkachev's MIN001); fix e5b77aba3 then chose its re-entrancy mechanism and rebuild behaviour with no design pass.

### Recommended durable fixes

- GAP-01/GAP-04 x2 (SUG002, SUG003; upstream MIN001) → plan-critic.md attack vector: a change to when/how a public user callback is invoked must state re-entrancy, thread/flow, and invocation count per cache entry vs master, each a P2 criterion or a documented behaviour change in the callback's XML docs.
- GAP-05 x1 (SUG001; recurrence of #6258) → agents/test-writer.md: a new or moved `finally` restore of a stack/scope/pool in Source/ gets a test whose follow-up input the leaked state answers differently; record the delete-the-restore mutation and its red result.
- GAP-07 x1 (NIT001; sixth recurrence) → .github/workflows (linq2db commit): run test-diff-sweep.ps1 on PR diffs as a non-blocking annotation.

### Corpus trace

- SUG001 · rule: testing.md:807 (cleanup check that re-asks a question the leaked state answers the same way), predates the PR · did not fire: lives only in the testing.md catalogue, no agent brief or DoD gate triggers it · correction: test-writer.md trigger above · recurs: fix-lambda-parameter-binding-cache gaps round-1 MIN002/SUG002.
- SUG002 · rule: Source/BannedSymbols.txt:14 ("don't do it") · did not fire: no rationale, no sanctioned exception; the only written alternative is testing.md:1169 (AsyncLocal, scoped to Tests/) which reads as a general substitute · correction: BannedSymbols.txt:14 message names the exception path (synchronous re-entrancy guard: scoped RS0030 pragma with justification; AsyncLocal flows into tasks); testing.md:1169 states AsyncLocal is not a Source/ substitute for thread-local state.
- SUG003 · rule: none on the callback invocation contract · correction: plan-critic vector above; optional KB decisions entry "callback runs once per type per cached descriptor".
- NIT001 · rule: testing.md:659, CONTRIBUTING.md:346, copilot-instructions.md:41, detector test-diff-sweep.ps1 · did not fire: external author gets no plan gate; Copilot did not review the PR · correction: run the detector in CI · recurs: grpc-shared-channel, issue-6000, fix-ydb-round-decimal-precision, issue-5951, issue-6192 ledgers.
- NIT002 · rule: none · correction: code-design.md "invariant checks in Source/ throw in every build; no Debug.Assert"; optionally ban M:System.Diagnostics.Debug.Assert* in Source/BannedSymbols.txt.
