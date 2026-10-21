---
area: REMOTE
kind: issues
sources: [gh-issues, gh-prs, gh-discussions]
confidence: medium
last_verified: 2026-10-21
last_verified_sha: 89b5ce16278728b9936ba374827fea002c76e962
---

# REMOTE -- GitHub themes

## Open themes
- **Remote path builds different SQL than the direct path** -- The LinqService wire format sends some typed nodes without their type, so the server optimizes a different tree than the direct path does. `SqlBinaryExpression` and `SqlUnaryExpression` cross the wire with their CLR type only (#6055), losing `DbDataType`. The server then folds a non-mandatory narrowing cast that the client kept, giving different and sometimes invalid SQL (YDB reports "Implicit decimal cast would narrow the range"). The same type loss happens on the direct path when a Transform-mode visitor rebuilds a typed node (#6056). Fix is in draft PR [#6057](https://github.com/linq2db/linq2db/pull/6057). #6088 and #6089 were measured on both the direct and the LinqService arm, so they are provider defects rather than remote-only ones; they are cited for arm coverage.
- **gRPC client opens a connection per remote call** -- `GrpcDataContext(address)` creates a new channel (TCP, TLS handshake, HTTP/2 preface) for every remote call and closes it afterwards, so a busy client accumulates `TIME_WAIT` sockets at its query rate. Open PR [#6020](https://github.com/linq2db/linq2db/pull/6020) proposes one channel per context, a caller-owned channel option, and reporting cancellation as `OperationCanceledException`.
- **SignalR streaming cancellation and reconnection** -- On 6.5.0 a client-side cancel of a 5 s query over `LinqToDBHub` throws after 300 ms, but the database keeps running the query. The next quick query on the same connection then waits about 4.4 s behind it, and a client dispose mid-query lets the server query run to completion. Open PR [#6014](https://github.com/linq2db/linq2db/pull/6014) adds cancellable streaming calls, concurrency limits, a size pre-flight and a restartable DI connection.
- **Direct and remote baselines compared only when a path is written** -- The direct-vs-remote SQL comparison ran only when `BaselinesPath` was set, so a remote gate passed or failed depending on the environment. Open draft PR [#6061](https://github.com/linq2db/linq2db/pull/6061) compares both on every run and makes the suppressing gates declarative (`[NoBaselines]`, `ActiveIssue(BaselinesMismatch)`). Earlier steps: [#6048](https://github.com/linq2db/linq2db/pull/6048) (merged 2026-10-15) gated the PostgreSQL remote case of `Issue5972_UInt64` on baselines being written, and [#6015](https://github.com/linq2db/linq2db/pull/6015) (closed, not merged) proposed removing gates that now pass.

## Resolved themes
- **Remote test clients leaking connections to test hosts** -- Each remote test opened its own client and, for gRPC and most transports, never released it. With providers running in parallel inside one test process, the hosts were flooded with leaked connections. Fixed by [#6010](https://github.com/linq2db/linq2db/pull/6010) (merged 2026-10-10).
- **SignalR.Client audit advisories** -- GHSA-334f-vvp4-7g6p was suppressed globally in [#6043](https://github.com/linq2db/linq2db/pull/6043) (merged 2026-10-14) while the patched SignalR packages were not yet on nuget.org. After the advisory was revised on 2026-10-19, [#6095](https://github.com/linq2db/linq2db/pull/6095) (merged 2026-10-20) raised the `SignalR.Client` floors to patched versions and removed the suppression.

## Active discussions
- No REMOTE-tagged discussions in this delta. Discussion #4617 carries the tag REMOTE-CLIENT and is not cited here.

## Stats
- Open issues: 4
- Closed issues: 0
- Open PRs: 4
- Total PRs: 9
- Discussions: 0
- Last fetched: 2026-10-21

<details><summary>Coverage</summary>

- Index entries scanned: 128 (63 issues + 65 PRs + 0 discussions), delta run for issues and PRs.
- REMOTE-tagged index entries: 6 (#6055 issue; #6010, #6014, #6020, #6057, #6095 PRs). All 6 are cited above.
- Other entries cited: #6015, #6043, #6048, #6056, #6061, #6088, #6089 (see themes).
- Remote-titled entries in the index under other area tags were not re-scanned in this delta run.
- Themes extracted: 6 (4 open, 2 resolved)
</details>
