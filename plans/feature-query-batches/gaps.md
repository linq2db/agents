## Round 1 — reviewed HEAD e40c90018

No plan covers any of these findings: `plan.md` line 6 scopes the plan to the #6201 reduce-ordering fix, and all six findings sit in the combined-command engine, the DML scenario, the eager-load tests or the PR body. The planned reduce-ordering code drew no findings this round. Attribution names the block that *would* have carried each one.

## Attribution

- **MAJ012** — GAP-03 — a `P7` row listing every re-derivation of the DbBatch gate (`DataConnection.CanRunDbBatch` = no `ICommandInterceptor` && `CanCreateBatch`), tests included, with the test-harness inputs that change it: `TestBase.Context.cs:82/131/173/190/224` register `SequentialAccessCommandInterceptor` on SqlServer.CS(.MS), and `EagerLoadingTests.cs:4170` copies only the `CanCreateBatch` half. Knowable on this branch: 706a455be fixed the same mechanism in `DbBatchTraceTruncatesLongParameters`, and e40c90018's message itself says "a command interceptor would force the concatenated backend". The lesson was never codified (no `SequentialAccess` rule in `testing.md`). Secondary GAP-08: e40c90018 was not run on SqlServer.CS.MS before push; no plan, so no `P9` demanded it. — G-01 — preventable: yes
- **MIN018** — GAP-03 — a `P7` row per reader of the DbBatch decision and which options object it reads: `DataConnection.QueryRunner.cs:342/:776` render the batch form under the query's options + `CanRunDbBatch`; `:547/:594` re-gate on `CanUseDbBatch` (connection's options). Plus the remote wire shape where they diverge (LinqService server `UseDbBatch=false`, client `UseCombinedCommands(true)`). `plan-critic.md:76` ("a capability flag read by two consumers needs a probe through each") would have caught it. `RemoteContextTests.cs:326` proves the options reach the server, never with server/client disagreeing. — — — preventable: partly
- **MIN019** — GAP-08 — `definition-of-done.md:26` (*The PR body matches the code after every push*) applied and was not run; "No public (non-Internal) API added" is mechanically checkable against the branch's `PublicAPI.Unshipped.txt` diff; the "Opting in" transaction claim contradicts the PR's own XML doc and master's `Query.cs`. Secondary GAP-01: that item names only *Behaviour change* / *Tests*, not API-surface claims. — — — preventable: partly
- **MIN020** — GAP-05 — a `P8` `TO-n` with a control proving the combined path engaged (`work-plan.md:161`, opt-in fast path). `InterceptorsTests.cs:1582` and `CompileTests.CompiledQueryWithEagerLoad(Async)` (`:274/:293`) never call `UseCombinedCommands`. 65c6dce79 fixed this exact class in `EagerRenderCacheTests` without sweeping siblings (`work-plan/SKILL.md:131`). — — — preventable: yes
- **NIT005** — GAP-07 — rule exists (`code-design.md` → *Column-aligned formatting is intentional*; `review-conventions.md` → *Formatting on PR-touched lines*); no plan, no conventions embed. ~35 retyped sites under `Internal/Linq/*` = one bulk retype with no re-pad step. — G-06 — preventable: partly
- **NIT006** — GAP-08 — `test-diff-sweep.ps1` (definition-of-done item 1) flags them; the plan's `G-01` record (`plan.md:131`) shows the sweep ran and its hits on branch test code were waived as "pre-existing branch test code outside this plan". The `EagerLoadingTests.cs:4170/4175` hits arrived with e40c90018, so the sweep was not re-run before that push either. — G-01 — preventable: yes

## Aggregate

6/6 outside the plan's scope. 4/6 (MAJ012, MIN018, MIN020, NIT005) trace to blocks a Tier M/L plan would have required (`P7` ×2, `P8` ×1, conventions embed ×1); 2/6 (MIN019, NIT006) are plan-independent definition-of-done gates. Dominant class GAP-03 ×2, one root: the "may this run as a DbBatch" decision is evaluated at several sites from different inputs (query vs connection options vs harness interceptors) and was never inventoried. MAJ012 and MIN020 share a second root: a test's model of which execution path ran is wrong, and the branch met each shape once before (706a455be, 65c6dce79) without codifying it. Single most-preventive change: an inventory of the DbBatch/combine eligibility predicate — i.e. the combined-command engine needs its own plan.

## Recommended durable fixes

- GAP-03 ×2 → `work-plan/SKILL.md` step 5 scout brief: when a change introduces/consumes a multi-input eligibility predicate (options, connection capability, registered interceptors), `P7` lists every evaluation site, product and test, with the exact inputs each reads (query vs connection options; remote server vs client).
- GAP-03 + GAP-05 (MAJ012, MIN020) → `testing.md`: a test of an opt-in execution path opts in explicitly and asserts the path engaged; a test predicting the DbBatch backend accounts for interceptors (SqlServer.CS(.MS) carry `SequentialAccessCommandInterceptor`): build the connection from explicit `DataOptions` (706a455be) or derive the expectation from the product gate.
- GAP-08 ×2 → `definition-of-done.md` items 1 and 26: sweep hits in branch test code a plan doesn't cover are not waivable as "outside this plan"; re-run the sweep before every push touching `Tests/`; widen the PR-body item to every factual claim, with "no public API added" checked against the `PublicAPI.Unshipped.txt` diff.

## Round 3 — reviewed HEAD 9818a4f1a

Round 2 (review 5758576142 at `f12cf5b9e`: MAJ012, MIN021, MIN022, SUG013–015, NIT010, all fixed by the author) was not attributed here. All four round-3 findings are in test code the PR author committed outside `/work-plan` (the A-8 commits); the plan recorded those commits afterwards (A-8), and its `conventions:` sweep and critic round 13 named every finding's `file:line` before the review ran.

## Attribution

- **MIN024** (MIN023 regression tests narrowed to AllSQLite, direct only) — GAP-07 — `testing.md` *A narrowed provider set is a claim* / *State the reason at the attribute* existed, but no plan step reached the author before `b2b8be100`; the reviewer-proposed `[DataSources]` and its nine-family red were known at commit time; TO-21 adopted the narrowed set and G-01 counted it satisfied by CI green — G-01 — preventable: no
- **MIN025** (SUG016 test omits SQL Server / Firebird 2.5) — GAP-07 — same chain for `16b35167f`; possible second class GAP-05 if the chosen legs never showed the direct-vs-remote divergence, not settleable from the artifacts — G-01 — preventable: no
- **MIN026** (`67d0d1c0f` test SQLite-only) — GAP-07 — same chain; second class GAP-05: TO-23 is characterization and its red side is recorded as never shown — G-01 — preventable: no
- **NIT011** (one-line call chains, `ParameterTests.cs:565-573`, `PredicateTests.cs:1026`) — GAP-07 — *Test layout* existed and never reached the author of `b2b8be100` / `67d0d1c0f`; round 1's NIT006 fix (re-run the sweep before every push) was honoured and detected them — G-01 — preventable: no

Not rows: the unregistered optimizer exits `:314` / `:492` are out-of-plan-scope with a reason (P7, pre-existing on master); the LikeSql comment wording would be GAP-10 if ever posted as a finding.

## Aggregate

4/4 GAP-07, one root: a co-author's push outside the plan process, with the rules and the measured failure set already in existence; the after-the-fact amendment could only detect, not prevent. As a detector the mechanism worked: A-8's sweep and critic round 13 predicted every finding at its exact `file:line`. Across plans the narrowed-set rule was also broken on #6194 (`feature-fix-string-args-varchar-type/gaps.md`, MIN004), so the failure is delivery to the committing author, not the rule's wording.

## Continuity

- NIT006 → NIT011: recurs in class (sweep-detectable one-line chains); round 1's fix landed and fired; the recurrence comes from a co-author's push, not a skipped gate.
- MIN020 → MIN024–026: related (test coverage narrower than the mechanism), different rule; MIN020's fix landed (`testing.md`).
- MAJ012, MIN018, MIN019, NIT005: no recurrence.

## Recommended durable fixes

- GAP-07 ×4 → `.github/copilot-instructions.md` (linq2db repo, needs a linq2db commit): inline *A narrowed provider set is a claim* / *State the reason at the attribute* ("a reviewer-proposed `[DataSources]` is narrowed only by a measured failure, stated at the attribute") and *Test layout*'s one call per line; its `## Testing` section holds only "Use Shouldly". Value depends on Copilot review running on co-author pushes.
- GAP-07 ×4 → `work-plan/SKILL.md` amend step 4: an amendment adopting another author's commits after the fact gives each sweep hit a disposition (fix here with the author's OK, or a named review item), and an adopted `TO-n` whose provider set the plan records as below the measured failure set stays open in G-01 instead of being counted satisfied by CI green.
