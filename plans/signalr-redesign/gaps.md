# Gap ledger — signalr-redesign (PR #6014)

## Round 1 — reviewed HEAD c78e635dc19a0eee6ca026bd88721324bf8cc6db

No plan on this branch (external contribution). Attribution is made against the absent artifact: each finding names the block a Tier M plan would have carried.

### Attribution

- **BLK001** — GAP-01 — P1/P2 never named "public surface of LinqToDBHub is frozen in a non-major milestone"; P7 would also have needed a row for the five removed public methods and their PublicAPI/compat consequence. — preventable: yes
- **MAJ001** — GAP-02 — P5/P7 would have assumed passing the caller's token to `StreamAsChannelAsync` is equivalent to master's `InvokeAsync`; checkable against the Signal/R client source (it discards the CancellationTokenRegistration). SignalRLinqServiceClient.cs:55, :102. — preventable: partly
- **MAJ002** — GAP-05 — TO-n for "cancellation stops row reads" needed a red→green proof; CancellationStopsReadingRows (SignalRTransportTests.cs:210-214) cannot go red. — preventable: yes
- **MAJ003** — GAP-06 — baseline-producing test issuing timing-dependent SQL without DisableBaseline (SignalRTransportTests.cs:752). GAP-07 if the rule is not written anywhere. — preventable: yes
- **MAJ004** — GAP-05 — no test obligations for new public options (`ConfigureConnection`, `ConnectTimeout`→`TimeoutException`, sync `Dispose()`). — preventable: yes
- **MIN001** — GAP-02 — assumed default `JsonHubProtocol` measures the client's actual protocol (RequestSize.cs:36-40). — preventable: partly
- **MIN002** — GAP-01 — late joiner on a shared start: documented `TimeoutException` vs observed OCE never named (LinqToDBSignalRConnection.cs:176-178). — preventable: partly
- **MIN003** — GAP-10 — depends on Signal/R never reading `Completion` (OperationChannelReader.cs:143-146). — preventable: no
- **MIN004** — GAP-10 — .NET 9+ trace headers not counted by the pre-flight (RequestSize.cs:40). — preventable: no
- **MIN005** — GAP-10 — legacy client teardown ordering leaves `_connected` true (LinqToDBSignalRConnection.cs:102). — preventable: no
- **MIN006** — GAP-01 — lifetime of the `MaxConcurrentCalls` limiter never stated (LinqToDBHubOptions.cs:40-44). — preventable: partly
- **MIN007** — GAP-05 — QueuedCallCanBeCancelled asserts "never runs" while the slot is held (SignalRTransportTests.cs:334-337). — preventable: yes
- **MIN008** — GAP-05 — CallFinishingAfterDisconnectReleasesItsSlot cannot observe a failed late release (SignalRTransportTests.cs:368). — preventable: yes
- **MIN009** — GAP-07 — no test-hygiene rule (bounded awaits, per-purpose timeouts, port allocation) in front of the author (SignalRTransportTests.cs:56). — preventable: partly
- **MIN010** — GAP-02 — TFM matrix not checked for how `Configure<T>` options reach derived hubs via the parameterless ctor (LinqToDBHub.cs:43-49). — preventable: yes
- **SUG001** — GAP-01 — validation contract for `ConnectTimeout` never named (LinqToDBSignalRClientOptions.cs:30). — preventable: yes
- **NIT001** — GAP-05 — error-hiding test passes even if the operation never ran (SignalRTransportTests.cs:535). — preventable: yes
- **NIT002** — GAP-10 — readme `await using` on legacy `HubConnection` (readme.md:29). — preventable: no
- **NIT003** — GAP-10 — example README diverges from Program.cs. — preventable: no
- **NIT004** — GAP-06 — NUnit Assert instead of Shouldly (RemoteContextTests.cs). — preventable: yes

### Aggregate

Of 20 findings, 12 trace to blocks a Tier M plan would have required (P2, P5, P7, P8); 8 rated preventable: yes, 4 partly. Dominant class: **GAP-05** (MAJ002, MAJ004, MIN007, MIN008, NIT001) — tests that cannot go red, or new public behaviour with no obligation. 5 GAP-10 rows (runtime-internal behaviour, doc prose) are a legitimate floor.

### Post-probe update (posted review #5479748941, HEAD 61ce7a5)

Probing changed the set before posting: MIN001 (JSON yardstick) refuted and dropped; MAJ002/MIN007/MIN008/NIT001 fixed by the review's own test commit; two new findings surfaced only by running tests — BLK002 (net462: the PR's own cancellation tests fail) and MAJ002 (a cancelled queued call can still run, exposed by the rewritten test). Both are GAP-05 in shape: the author's test obligations named net462 but the leg was never run, and the queued-call test could not go red. IDs above are the pre-probe ones.

### Recommended durable fixes (route to `/session-reflect` plan-rule bucket; not applied)

- GAP-05 → `work-plan.md` P8: each TO-n names the defect (mutation/revert) that turns it red; one TO-n per new public option/behaviour; plan-critic vector "can this test pass with the feature removed?".
- GAP-01/GAP-02 → `work-plan` scout brief + `plan-critic.md`: list a public type's surface against the milestone and its option validation; check third-party-library assumptions (cancellation registrations, TFM-specific option wiring) against that library's source.
- GAP-06/GAP-07 → `code-reviewer.md` rubric + `testing.md` do/don't: DisableBaseline for timing-dependent SQL.

## Round 2 — reviewed HEAD 2c4b21379e7149cf12853c18c560567c685997f0

No plan on this branch (external contribution): each finding is attributed to the block a Tier M plan would have carried. Gate evidence: CI green on 2c4b213, no baselines, so no row is GAP-08.

### Attribution

- **MAJ005** — GAP-01 — no P1/P2 requirement said "a 6.5-shipped `public virtual` hub method is an extension point: either every call it governed still goes through it, or it is removed and the build breaks". The BLK001 fix (af17cbd72) restored the signatures (LinqToDBHub.cs:142-182); the 6.6 `*Stream` path (:81-136) never calls them. Round 1's attribution stated the requirement at signature level (gaps.md Round 1, BLK001) and the fix inherited it. code-design.md:27 ("`[Obsolete]` does not unfreeze behavior") covers an obsolete body, not dispatch. A P8 obligation ("an override of `ExecuteReaderAsync` observes a 6.6 client's query") would have gone red. — G-03 — preventable: yes
- **MIN008** — GAP-02 — unchecked P4 assumption that any positive `TimeSpan` is a usable deadline for `CancellationTokenSource` / `Task.WaitAsync`; both document an upper limit (LinqToDBSignalRClientOptions.cs:38, 34bdd472b, SUG001 fix). Also GAP-05: no test for the validation or the `MaxConcurrent*` setters (work-plan.md:152 would have required one). — G-03 — preventable: yes
- **MIN009** — GAP-02 — unchecked P4 assumption that trace-header injection follows linq2db's TFM (`NET9_0_OR_GREATER`, RequestSize.cs:3/51/66); it follows the SignalR.Client asset — the 9.x netstandard2.1 asset injects (package DLLs checked). The repo pins net8.0 → SignalR.Client 8.x, so no local or CI leg builds that combination. — preventable: partly
- **MIN010** — GAP-03 — no impact-map row for sync `Dispose()` (LinqToDBSignalRConnection.cs:358) as the sibling of this round's legacy-only `DisposeAsync` change; plan-critic.md:127 (TFM-gated text carries the gate; sibling strings agree) covers it, never run. — preventable: yes
- **MIN011** — GAP-05 — no P8 obligation for the legacy restart path added by e04950f70 (MIN004 fix): `IsNotActive` → `OnNotActive`. Reaching it needs a seam into the legacy client's receive-loop window, and only net462 reaches it; that leg was never run locally (round 1 post-probe). — G-01 — preventable: partly
- **MIN012** — GAP-05 — the obligation for 9147017f1 (MAJ002 fix) recorded no mutation; under work-plan.md:182 deleting LinqToDBHub.cs:251/258 leaves QueuedCallCanBeCancelled green. Third round in which this test is the finding. Measured this round: with both checks removed the old test stays green and the new 50-round test fails 3/3 (61–72 calls for 50). — G-01 — preventable: yes
- **MIN013** — GAP-10 — the decision to restore the hub methods (af17cbd72) postdates the PR body; no plan block owns external PR-body prose. — preventable: no
- **SUG002** — GAP-03 — the port-0 change (c0a583641) needed a sibling sweep (a P11 `class:` line) over every site building or dialing a hub URL; the host switched to `127.0.0.1` (SignalRTransportTests.cs:1850), the DI client kept `localhost`. — preventable: yes
- **SUG003** — GAP-01 — P2/P5 never stated how many connections N `AddLinqToDBSignalRDataContext` registrations get once the public `LinqToDBSignalRConnection` replaced `Container<HubConnection>`; a `deferred:` row would have made it not-a-gap. — preventable: partly
- **NIT004** — GAP-07 — column alignment (OperationChannelReader.cs:25); the rule never reached an external author (round 1's NIT004 is the same class). — preventable: partly
- **NIT005** — GAP-07 — one-line chains in new test code (testing.md Test layout rule 1); `test-diff-sweep.ps1` catches it only at review time. — preventable: partly

### Aggregate

10 of 11 trace to blocks a Tier M plan would have required (P1/P2, P4, P7, P8, P11); 5 preventable: yes, 5 partly, 1 no. Classes are flat (GAP-01/02/03/05/07 ×2, GAP-10 ×1). The pattern is provenance: 7 of 11 (MAJ005, MIN008, MIN009, MIN011, MIN012, MIN013, SUG002) are gaps in commits written to fix round-1 findings — each fix answered the instance, not its class (signatures not dispatch, lower bound not upper, own TFM not the dependency's asset, a test with no recorded mutation, one URL site not its sibling).

### Continuity

Posted round-1 IDs from MIN001 on are one lower than the Round 1 table's pre-probe IDs (MIN001 was dropped).

- **BLK001 → MAJ005, MIN013.** The fix restored the surface and removed the compile-error migration; the ledger's signature-level wording did not prevent it.
- **SUG001 → MIN008.** The fix named half the validation contract.
- **Posted MIN003 / ledger MIN004 (trace headers, ledgered GAP-10) → MIN009.** The behaviour was readable from the package DLLs, so round 1's GAP-10 reads better as GAP-02.
- **Posted MIN004 / ledger MIN005 (legacy teardown) → MIN011.** Its fix added a path no test reached.
- **Post-probe MAJ002 / ledger MIN007 (QueuedCallCanBeCancelled) → MIN012.** Third round on the same test.
- **Ledger MIN009 (test hygiene) → SUG002, NIT005; ledger NIT004 (convention) → NIT004, NIT005.**
- **Round-1 recommendation 1 (P8 mutation) landed** (work-plan.md:152, :182, e41396a) but cannot bind a plan-less branch; MIN011/MIN012 are that class again.
- **Round-1 recommendation 2 (public surface vs milestone; third-party assumptions checked against the library) did not land**; MAJ005, MIN008, MIN009 are that class.

### Recommended durable fixes (route to `/session-reflect` plan-rule bucket; not applied)

- Fix commits ×6 → review-pr posting step / code-reviewer finding schema: on a plan-less branch each posted finding's Fix names the class the fix must cover (other bound, dependency per-asset behaviour, sync sibling, every same-URL site, every dispatch path to an overridable member) and the mutation its regression test must go red under.
- GAP-02 ×2 (+ round-1 MAJ001/MIN010) → re-propose round-1 recommendation 2 in the work-plan scout brief and plan-critic.md: record each value/behaviour handed to a dependency with its accepted range and per-asset behaviour, keyed by the dependency's asset/version, never linq2db's TFM macro.
- GAP-01 (MAJ005) → code-design.md:27: extend "`[Obsolete]` does not unfreeze behavior" to virtual dispatch — an obsolete `public virtual` kept for compatibility must still be called on every path it governed in the shipped version, or be removed; add a matching plan-critic vector.

## Round 3 — reviewed HEAD 5208d734db6962cfb970ebb123bf1286210cddb7

No plan on the branch; each row names the block a Tier M plan would have carried. 16 findings, all posted (review 6058482678, COMMENT).

### Attribution

- **MAJ006** (obsolete hub methods + refusal machinery) — GAP-07 — P3 constraint citing code-design.md:430/:533 and a P7 row classifying the five hub `*Async` methods as wire shape, not stability contract; the author's first design removed them, round-1 BLK001 (api-surface-classification.md step 3, no remote-transport carve-out) reinstated them and round-2 MAJ005 built the refusal machinery (4f1e15f26) on that premise — — — preventable: yes
- **MIN014** (client readme cross-version) — GAP-07 — same missing P3 constraint; paragraph from af17cbd72 (the answer to BLK001), re-stamped in e355a1425 — — — preventable: yes
- **MIN015** (server readme cross-version + protocol internals) — GAP-07 — same P3 constraint; :57-62 near-verbatim round-2 MAJ005 suggestion text, :63-66 from 4f1e15f26; the "readmes stay user-level" half had no rule anywhere (GAP-01) — — — preventable: partly
- **MIN016** (DB-side cancellation overstated) — GAP-02 — P4 probe behind the readme E-n: "cancels it in the database" assumes every ADO.NET provider implements Cancel() (Microsoft.Data.Sqlite: "Does nothing"); from 347cd66b0 — — — preventable: partly
- **MIN017** (stale "shared by all contexts" class doc) — GAP-03 — P11 sweep row for b98bff7b6 listing every text describing connection sharing; the class summary at LinqToDBSignalRConnection.cs:17 was missed — — — preventable: yes
- **MIN018** (200 ms timer race) — GAP-05 — TO-n for client cancellation triggered on the server's "started" signal; the timer can fire inside the first-call GetMaximumReceiveMessageSize round trip the PR's pre-flight added (8ba1194eb) — — — preventable: partly
- **MIN019** (untraced arm vacuous) — GAP-05 — TO-n with a control that can disagree; test written by the reviewer in round 1 (61ce7a555), :738 accepts both outcomes, and the reviewer's round-2 fix 0b800970f made the reserve unconditional on net8+, falsifying the comment — — — preventable: yes
- **MIN020** (shared ConfigurationString cache key) — GAP-02 — P4 row "a remote test context's configuration string is only a label", contradicted by KB areas/REMOTE-CLIENT/INDEX.md:61; :1552 from the reviewer's 61ce7a555 — — — preventable: partly
- **MIN021** (legacy wrapper assumes 1.x client) — GAP-02 — P4 row keyed by the SignalR.Client version, not the TFM, for StartAsync refusal handling (LinqToDBSignalRConnection.cs:197-203, c2c499e1c); same class as round-2 MIN009 — — — preventable: partly
- **MIN022** (no trace-header reserve on legacy) — GAP-02 — same P4 row; RequestSize.cs:67/:80-82 from the reviewer's round-2 fix 0b800970f, which moved the gate NET9→NET8 instead of off TFMs, the day plan-critic.md:118 was written from it — — — preventable: yes
- **MIN023** (PR body: WCF, 2 s bounds, cross-version) — GAP-03 — P7 row per remote transport behind LinqService (WCF passes no token, already noted in round 1's out-of-scope list); part 2 is prose (GAP-10), part 3 is the MAJ006 chain (GAP-07) — — — preventable: partly
- **SUG004** (factory path untested) — GAP-05 — TO-n per registration path for b98bff7b6 (context and IDataContextFactory<TContext>); SUG003's Fix named neither path nor a mutation — — — preventable: yes
- **SUG005** (cancel callbacks inside Signal/R's Cancel) — GAP-01 — P2 never named the failure contract for provider cancel callbacks run inside a foreign CancellationTokenSource.Cancel(); round 1 kept the mechanism out of scope — — — preventable: partly
- **SUG006** (cancel-before-dispose only on SQLite) — GAP-03 — P7 rows per provider for the shared-engine LinqService cancel-before-dispose (LinqService.cs:232-238) with a TO-n beyond SQLite; round 1's out-of-scope note named the reach — — — preventable: yes
- **NIT006** (one-line chains) — GAP-07 — testing.md:657 rule 1 never reached the author; the reviewer's NIT005 fix (3437ec765) ran test-diff-sweep.ps1 before 0ddad0d taught it the `(await x).ShouldBe(` shape, and the reviewer's 61ce7a555 added :1544 — — — preventable: yes
- **NIT007** (exception-assertion form) — GAP-10 — the constraint-form rule (testing.md:5-12, 62b6f2a, 2026-11-15) postdates the code (3f1b9ad20, 2026-10-09), which met the then-current Shouldly rule — — — preventable: no

### Aggregate

15 of 16 trace to blocks a Tier M plan would have required; NIT007 is the floor. 8 preventable yes, 7 partly, 1 no. Classes are flat (GAP-02 ×4, GAP-07 ×4, GAP-03 ×3, GAP-05 ×3, GAP-01 ×1, GAP-10 ×1); provenance is not: 7 findings sit wholly (MAJ006, MIN014, MIN015, MIN019, MIN020, MIN022, SUG004) and 3 partly (NIT006, NIT007, MIN023) in code or text that earlier review rounds wrote or asked for.

### Recommended durable fixes

1. api-surface-classification.md step 3: a member whose only consumer is the same-version remote peer (Signal/R hub methods, ILinqService / gRPC / WCF service contracts) is not a stability-contract BLK; cite code-design.md:533; CompatibilitySuppressions regeneration happens at release. Same commit: rescope code-design.md:29 to non-transport public virtuals and replace its #6014 example, which now contradicts :533.
2. code-reviewer rubric: flag `[Obsolete]` transport members kept "for older clients", and readme / PR-body text promising cross-version operation or describing the hub/wire protocol; package readmes state usage, guarantees, limits and options only.
3. review-orchestration.md closing sequence: a fix or test commit the reviewer pushes to the branch gets test-diff-sweep.ps1, a control proven able to disagree, and (for a dependency-keyed gate) the plan-critic.md:118 question, before the push.
4. testing.md remote-test section: cancel on a server-side "started" signal, never on a timer; a test remote context's configuration string is unique per server target (RemoteDataContextBase caches LinqServiceInfo by ConfigurationString).
5. code-reviewer rubric: mirror plan-critic.md:118 (dependency behaviour keyed by the dependency's version, not linq2db's TFM macro).

### Continuity

- Round 1 BLK001 ("public surface frozen", GAP-01, gaps.md:9) and round 2's MAJ005 ledger + durable fix (code-design.md:29) entrenched the premise MAJ006 now reverses: the recommendation was aimed at the wrong thing.
- Round 1 MIN009 recommended a test-hygiene rule (gaps.md:22) that never landed in testing.md; MIN018 is that class again.
- Round 2 MIN009 → MIN021/MIN022: the TFM-for-dependency-version class recurs, the second time inside the reviewer's own fix.
- Round 2 NIT005 → NIT006: the fix left hits a later detector version catches.
- Round 2 MIN013 (PR-body drift) → MIN023.
