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
