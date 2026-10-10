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
