# Gap ledger — issue/cli-impersonation-scope (PR #5995)

## Round 1 — reviewed HEAD 816c3b7a9c67d647449aa6e57187fac63256bb86

## Attribution

No plan on the branch: `.claude/plans/issue-cli-impersonation-scope/plan.md` does not exist (external contributor) and there are no `P9` results. Each row names the block a Tier M plan would have needed to carry that finding.

- **MAJ001** — GAP-02 — needed a `P4` row: "the reference/import closure of the ADO.NET client is the complete set of modules a session loads", resolved by a module-load census probe. The PR body asserts this as the design ("the reference closure of every loaded assembly") without checking it. linq2db itself loads `Microsoft.SqlServer.Types` by name, not through SqlClient's references (`Source/LinqToDB/DataProvider/SqlServer/SqlServerTools.cs:55-65`), so a `P7` sweep of linq2db's by-name loaders would also have listed it. Second class: GAP-05, because no `TO-n` used a reachable server with a typed-value read, which is the precondition for reaching `ImpersonationPreload.cs:94-100`'s gap. — — — preventable: yes
- **MIN001** — GAP-05 — needed a `P8` that expands "nothing loaded while impersonating" into one cold case per bundled client (rule `work-plan.md:136`). An Oracle.Managed unreachable-server case has the same shape as the existing SqlServer/PostgreSQL ones, needs no server, and would have gone red. Second class: GAP-02, the same closure-completeness assumption as MAJ001, since `DiaSymReader` is a dynamic load outside any import table. — — — preventable: yes
- **MIN002** — GAP-01 — needed a `P2`/`P3` line saying what the impersonated account must be able to read when the provider comes from `--provider-location`. The PR states the requirement only for the tool's own folder, and `SKILL.md:70` carries no line for an external provider folder. Discovering that the IBM clidriver loads `IBMOSauthclient64.dll` and reads its cfg/msg files itself at connect needed a `P4` probe with a real DB2 client, so this is not certain without that probe. — — — preventable: partly
- **MIN003** — GAP-05 — needed a `TO-n` for "validation runs as the process account" whose input separates the two arms (rule `work-plan.md:142`). Its control also needed a recorded mutation (rule `:158`). ScriptDom is loaded by the preload either way, so `ImpersonationScopeTests.cs:139-141` cannot go red; the mutation that moved validation into the session stayed green. — — — preventable: yes
- **MIN004** — GAP-05 — needed a recorded mutation for the in-process tool-assembly control (rule `:158`) and a proof that it runs independently of fixture order (rule `:144`). `ImpersonationScopeTests.cs:194` stayed green in fixture order with the preload removed. — — — preventable: yes
- **MIN005** — GAP-05 — needed a `TO-n` for the advertised behaviour change ("logon failure before validation") and for the `OpenAsync` dispose paths, plus a test double that mirrors the production logon's failure axis (rule `:162`). `TestCliEnvironment.cs:117-128` cannot fail a logon, so neither path is reachable. — — — preventable: yes
- **SUG001** — GAP-01 — needed a `P5` `D-n` that orders the three phases (preload → logon → validation), with a rejected alternative and a failure-mode line. The PR names fail-fast on logon relative to validation, but never relative to preload, and never covers disposing the token when the preload throws (`ConnectionExecution.cs:39-45`). — — — preventable: partly
- **SUG002** — GAP-05 — needed a `TO-n` that states what proves the overlap happened (rule `:144`). `ImpersonationScopeTests.cs:482` asserts `Current.ShouldBeNull` on a path where the concurrency is never forced, so the assertion cannot fail. — — — preventable: yes
- **SUG003** — GAP-05 — needed `P8` to expand the set claim into elements (rule `:136`): bundled clients × session phases (detect, connect-fail, connect-ok, typed read) × provider origin (bundled, `--provider-location`). The matrix at `ImpersonationScopeTests.cs:208` covers 3 of 15 clients, all through refused TCP connections. — — — preventable: yes

## Aggregate

All 9 of 9 findings trace to blocks a Tier M plan would have required; 7 are fully preventable, MIN002 and SUG001 only partly. GAP-05 is the largest class (6: MIN001, MIN003, MIN004, MIN005, SUG002, SUG003), then GAP-01 (2) and GAP-02 (1). Two groups:

- MIN001 and SUG003 come from a negative invariant ("nothing loaded while impersonating") tested on a hand-picked subset.
- MIN003, MIN004, MIN005 and SUG002 come from tests whose controls were never mutation-proven to go red.

The single change that would have prevented the most is a `P8` matrix over clients × phases × provider origin, with a recorded mutation per control: 6 of 9 caught directly, and MAJ001's typed-read gap exposed as a second class.

## Recommended durable fixes

- GAP-05 × 6 → `testing.md` (new section: testing a scope invariant, "nothing X happens while Y") — each element of the set the invariant ranges over gets its own cold-process case, including phases that need a reachable server (typed-value reads); beside each control, record the mutation that reddens it (delete the preload, move the work inside the scope, run in reverse fixture order). The `work-plan.md` P8 rules (`:136`, `:158`) only bind planned branches, so this has to live where a no-plan contributor's reviewer will apply it.
- GAP-02 × 1 (plus the second class on MIN001) → the scout brief in `work-plan/SKILL.md` step 5 — when the design is "load everything ahead of a boundary", probe completeness with a load census (`AppDomain.AssemblyLoad` plus a native-module hook) across success, failure and typed-read paths, and sweep linq2db's by-name loaders (`SqlServerTools` spatial types, `*ProviderAdapter`), which never appear in a reference closure.
- GAP-01 × 2 → an attack vector in `plan-critic.md` — for any privilege or identity boundary, list every operation and every externally supplied artifact (`--provider-location` folders, third-party native clients) on each side of it, then ask what the reduced identity must be able to read and in what order the boundary is entered relative to preload and validation.

## Round 2 — reviewed HEAD 0f75222b2c006690874b3b9cc5e67c4665c0519a

## Attribution

Still no plan on the branch (`plan.md` absent) and no `P9` results. Each row names the block a Tier M plan would have needed. MIN006, MIN007, NIT001 and NIT002 come from the verification pass; the rest come from the fresh pass at the same HEAD.

- **MIN006** — GAP-02 — needed a `P4` row "which clients the warm-up covers and what it does per client". `SKILL.md:70` says the warm-up creates DuckDB files, but `ImpersonationPreload.cs:111-117` never warms DuckDB up. Second class: GAP-01, because no `P3` line named "DB credentials log in twice per command". — — — preventable: partly
- **MIN007** — GAP-10 — the mid-branch redesign (from a connection that is created but not opened to an opened warm-up connection) did not exist at plan time, and the PR body was never reconciled with it. — — — preventable: no
- **NIT001** — GAP-10 — the doc comment at `ImpersonationPreload.cs:183` went stale against the DuckDB skip. Prose staleness. — — — preventable: no
- **NIT002** — GAP-05 — needed a `TO-n` with a recorded mutation (rule `work-plan.md:158`). `ImpersonationScopeTests.cs:551` cannot fail. It originated in round 1's MIN005 suggestion, which was not mutation-proven either. — — — preventable: yes
- **MIN008** — GAP-02 — needed a `P5` `D-n` for the warm-up's side effects, with a rejected alternative (read-only mode). `GetUnpooledConnectionString` changes only `Pooling`, so SQLite's default ReadWriteCreate creates the file as the process account (`ImpersonationPreload.cs:205-207`). `SKILL.md:70` documents this as intended. — — — preventable: partly
- **SUG004** — GAP-01 — needed a `P3` line for the long-lived MCP host covering the warm-up's per-call cost and audit footprint. Every other preload step is memoized and `ImpersonationPreload.cs:118-128` is not. — — — preventable: partly
- **SUG005** — GAP-05 — needed a `TO-n` for the production logon failure axis (`WindowsImpersonation.cs:28-34`) and a test double that fails the way production fails (rule `:162`). The failed-logon CLI test asserts text that its own double injects. — — — preventable: yes
- **NIT003** — GAP-10 — the doc at `ConnectionScope.cs:18-22` drifted from what its caller actually runs. Prose. — — — preventable: no
- **NIT004** — GAP-10 — the `--impersonate` help (`QueryExecutionCliOptions.cs:36`) says a warm-up always runs, but the code skips DuckDB, ODBC, OLE DB and YDB. Prose. — — — preventable: no
- **NIT005** — GAP-10 — the class summary at `WindowsImpersonation.cs:14` went stale when `RunAsync` moved to `WindowsImpersonationSession`. Prose. — — — preventable: no

## Aggregate

10 findings: 5 trace to plan blocks (GAP-05 ×2, GAP-02 ×2, GAP-01 ×1) and 5 are GAP-10 prose staleness. The prose findings all trail the two mid-branch redesigns (the opened warm-up connection, and the move of `RunAsync`). The design-gap findings all concern the warm-up added in response to round 1: its per-client coverage, its side effects and its lifecycle were never enumerated.

## Recommended durable fixes

- GAP-05 × 2 → `testing.md` (round 1's scope-invariant section), plus: a reviewer-suggested assertion is a claim too. It needs a recorded mutation that reddens it, and a test double must fail on the production failure axis rather than inject the text it asserts.
- GAP-02 × 2 + GAP-01 × 1 → `plan-critic.md` attack vector: a pre-flight or warm-up action at a privilege boundary needs a per-client table with four columns: covered?, what it creates or mutates, credential uses, and frequency in a long-lived host.
- GAP-10 × 5 → optional `code-reviewer.md` rubric line: after a mid-branch redesign, sweep the PR body, SKILL.md, help text and doc comments for the superseded design.

## Continuity

- Round-1 GAP-05 recurs (NIT002, SUG005). The round-1 `testing.md` recommendation was applied (`testing.md` → *A scope invariant tested on a hand-picked subset*, citing #5995), but it binds the author's controls, not a reviewer's suggested test: NIT002 came from the reviewer's own MIN005 suggestion, copied verbatim. Routed to `acting-on-findings.md`.
- Round-1 GAP-01 (`plan-critic.md` identity-boundary vector) recurs through SUG004 and MIN006.
- Round-1 GAP-02 (load census in the scout brief) did not recur; the warm-up redesign replaced the scan it targeted.

## Round 4 — reviewed HEAD ba165b9c2d63122880eeb2d56209ed86f85edf99

## Attribution

There is still no plan on the branch: `plan.md` is absent and no `P9` results exist. Each row names the block a Tier M plan would have needed to carry that finding. The round delta is a single test-line edit (`4b75d810c`). Every finding below sits in code that was already there at round 2's HEAD `0f75222b2`: the IVT and `_poolMethods` arrived in `6331e7719`, the OLE DB claim was already at `SKILL.md:69`, and the chains were on the same lines. So round 4 mostly surfaces what the earlier passes missed, not new code.

- **BLK001** (preload is a second, unobserved goal) — GAP-02 — needed a `P1` that cites an observed run of the fault, plus a `P4` row "a tool-folder load fails under a token that cannot read it, in install layout X", resolved by a live probe (second local account, global tool under user A's profile, `query --impersonate` against SQL Server with integrated security). Every test runs through `RecordingImpersonationSession` or a duplicated current-user token, so `NothingIsLoadedWhileImpersonating` proves the invariant, not the fault. Second class: GAP-01. No `P3`/`P5` line names behaviour per `ImpersonateMode`, and `ConnectionExecution.cs:43-47` runs the preload and warm-up in new-credentials mode too. — — — preventable: yes
- **MIN010** (`InternalsVisibleTo` for tests) — GAP-07 — needed a `P3` constraint embedding `code-design.md:132-136` (*Never `InternalsVisibleTo`*) for the edit to `LinqToDB.CLI.csproj:97-99`. The rule has existed since 2026-08-26 (`7d45628`) but was never put in front of the author. — — — preventable: yes
- **MIN011** (body names net8/9/10) — GAP-10 — the information did not exist at plan time. The `#5942` merge (`c41d1aae1`) changed `ToolTargetFrameworks` to `net10.0;net11.0` after the body's test summary was written. On a planned branch, the post-push body re-check (`work-plan.md:74`) is the control that would have caught it. — — — preventable: no
- **MIN012** (pool-method no-warm-up branch untested) — GAP-05 — needed a `P8` `TO-n` for each route on which the warm-up declines to act (`_poolMethods` at `ImpersonationPreload.cs:95` / `:324-325`, and the `_sharedStateClients` skip), with a provider that is not in `_poolingKeywords` and the recorded mutation "return the unpooled string instead of `null`". All four warm-up test providers derive from `SQLiteDataProvider`, so they take the keyword path. — — — preventable: yes
- **MIN013** (OLE DB pooling claim) — GAP-02 — needed a `P4` row per client: "can pooling be switched off from the connection string?", resolved against vendor docs or a probe. The claim decides which clients are warmed up, so it is a design assumption and not only prose. It sits at `SKILL.md:69`, `QueryExecutionCliOptions.cs:36` and the `_poolMethods` summary (`ImpersonationPreload.cs:91-94`), and one learn.microsoft.com page refutes it for OLE DB (`OLE DB Services=-4`). — — — preventable: yes
- **SUG006** (real session's token release untested) — GAP-05 — needed a `P8` characterization `TO-n` for the moved ownership. Token release moved from `using (token)` in `WindowsImpersonation.RunWindowsAsync` to `WindowsImpersonationSession.Dispose`. The obligation had to run against the real type, with the mutation "empty `Dispose`". Callers' disposal is tested only through the `RecordingImpersonationSession` double. — — — preventable: yes
- **SUG007** (Unix native probing unreachable) — GAP-01 — needed a `P3`/`P5` line naming the preload's platform scope. It is reached only after `StartImpersonation`, and `WindowsImpersonation.Logon` throws `PlatformNotSupportedException` off Windows (`WindowsImpersonation.cs:31-32`). The line also needed the decision "keep the non-Windows paths so the preload is tested on Linux/macOS legs" with its failure mode. Second class: GAP-03, because a `P7` caller row for `ImpersonationPreload.RunAsync` would have shown the Windows-only reach. — — — preventable: partly
- **NIT006** (`ImpersonationScopeTests.cs:175` chain) — GAP-07 — needed the `P8` conventions line embedding `testing.md:634` (*Test layout* rule 1) and a `test-diff-sweep.ps1` run recorded in `G-01`. The sweep's default `-Path Tests/` covers `Tests/LinqToDB.CLI`. — G-01 — preventable: yes
- **NIT007** (`ImpersonationScopeTests.cs:389` chain) — GAP-07 — same embed and sweep as NIT006 (`testing.md:634`). — G-01 — preventable: yes
- **NIT008** (`ImpersonationScopeTests.cs:399` chain) — GAP-07 — same embed and sweep as NIT006 (`testing.md:634`). — G-01 — preventable: yes
- **NIT009** (`WindowsImpersonationSessionTests.cs:56/77/93/140` single-call chains) — GAP-07 — same embed as NIT006, specifically the single-call-plus-assertion example at `testing.md:652-661`, plus a `G-01` sweep. — G-01 — preventable: yes

## Aggregate

10 of 11 findings trace to blocks a Tier M plan would have required. Only MIN011 is GAP-10.

- **By count, GAP-07 leads (5).** Four of those are the NIT chains, and that rule plus its detector were already briefed to review passes from 2026-10-28 onward, which is why round 4 caught them.
- **By weight, GAP-02 leads (BLK001, MIN013).** The single change that would have prevented the most is a `P1` that cites an observed run of the fault, i.e. a live logon as a second account. Without that run, the enumerative preload/warm-up would not exist in this shape. That removes BLK001 directly. MIN012, MIN013 and SUG007 all live inside that mechanism, so it also removes most of them: 4 of 11, plus most of rounds 1–2's preload findings.

## Recommended durable fixes

- GAP-02 × 2 (BLK001 directly; MIN012, MIN013 and SUG007 sit in the mechanism it would have rescoped) → `skills/review-pr/SKILL.md` step 3a (`:192` suppression) — re-offer goal-check when, since the last check, the diff has grown a mechanism the title does not name, or when the prior round's findings asked to extend a list-based mechanism. State in `work-plan.md` *P1* (`:62`) that a red→green run against a recording double proves a proxy invariant, not the fault.
- GAP-05 × 2 → `docs/testing.md:764` (*A scope invariant tested on a hand-picked subset*) — add two elements to the set:
  - every route on which the mechanism declines to act (skip lists, pool-method checks), each with its mutation;
  - any responsibility moved into a type that every test replaces with a double. It gets one test on the real type.
- GAP-07 × 1 (MIN010) → `docs/review-rubric/rubric-packaging.md` — flag any added `InternalsVisibleTo` in any `.csproj` or `AssemblyInfo`, citing `code-design.md:132`. Also widen `code-design.md:134` to tool projects (CLI), with the remedy "make it public" for projects that have no `Internal.*` namespace or PublicAPI analyzer. NIT006–NIT009 need no new rule: `review-pr/SKILL.md:550` (`b8676a3`, 2026-10-28) already briefs the sweep.

## Continuity

- **GAP-05 recurs:** round 1 ×6, round 2 ×2, round 4 ×2 (MIN012, SUG006).
  - Round 1's fix landed at `testing.md:764`, but it expands the invariant over clients × phases × origin. It does not name the mechanism's own skip routes, or a real type hidden behind a double.
  - Round 2's fix landed at `acting-on-findings.md:31`, but it binds only reviewer-suggested tests.
  - SUG006 is the same family as round 1's MIN005 and round 2's SUG005: every test goes through `RecordingImpersonationSession`.
- **GAP-02 recurs:** round 1 MAJ001, round 2 MIN006 and MIN008, round 4 BLK001 and MIN013.
  - Round 1's fix landed (load census in the scout brief, `work-plan/SKILL.md:124`). It targets completeness of the preload, so it presupposes the preload's goal. BLK001 is the upstream assumption that every earlier GAP-02 sat downstream of.
  - MIN013 has the same shape as round 2's MIN006: a `SKILL.md:69-70` claim about per-client behaviour that the warm-up branches on.
- **GAP-01 recurs:** round 1 MIN002 and SUG001, round 2 SUG004, round 4 SUG007 plus BLK001's second class. Round 1's vector landed (`plan-critic.md:114`, *For a privilege or identity boundary, list both sides*). It enumerates operations on each side but never asks per impersonation mode, and new-credentials keeps the local identity.
- **Round 2's other two recommendations did not land.** A Grep of `agents/`, `docs/` and `skills/` for `warm-up`, `credential use` and `superseded design` returns 0 hits. These were the per-client warm-up table vector in `plan-critic.md` and the redesign sweep in `code-reviewer.md`. The table's "covered?" column would have listed ODBC, OLE DB, YDB and LibRed with reasons (MIN012, MIN013). It binds only planned branches, though, so it would not have reached this one.
- **GAP-10 fell from 5 of 10 (round 2) to 1 of 11.**

## Corpus trace

- BLK001 · rule: `AGENTS.md` *verify before asserting — reproduced red→green*; `docs/work-plan.md:62` (`P1` falsifiable); `agents/goal-checker.md:39,51` · why it did not fire: the red→green requirement was met against a proxy (`RecordingImpersonationSession`), so the letter of the rule held while the fault was never observed; goal-check is opt-in and suppressed once the user has a submitted review (`skills/review-pr/SKILL.md:192`), and no `pr5995-goal-check.json` existed before 2026-11-19; rounds 1–2's own findings (MAJ001, MIN001, SUG003) and the rules they produced (`testing.md:764`, `work-plan/SKILL.md:124`) all asked for a more complete list, which deepened the mechanism · correction: `skills/review-pr/SKILL.md` step 3a re-offer trigger; `docs/work-plan.md` P1 proxy-invariant sentence · recurs: round 1 MAJ001 (GAP-02)
- MIN010 · rule: `docs/code-design.md:132-136` · why it did not fire: the rule's wording and remedy are core-library shaped (`Internal.*` namespace, `PublicAPI.Unshipped.txt`, `QueryCache`), and the KB echoes it as `Source/LinqToDB`-scoped (`knowledge-base/state/audit-log.md:151`); no reviewer rubric carries it (0 hits for `InternalsVisibleTo` in `agents/code-reviewer.md` and in `docs/review-rubric/`); three review rounds passed the line and the maintainer raised it · correction: `docs/review-rubric/rubric-packaging.md` rule; `docs/code-design.md:134` scope sentence covering tools and test-only grants · recurs: —
- MIN011 · rule: `docs/pr-and-push.md:51,54` (a factual line a follow-up commit makes false, such as a test list, is corrected in place) · why it did not fire: the trigger is "diff the newly pushed commits", and a master merge's TFM change does not read as the branch's own work; the PR author also works outside this corpus's push workflow · correction: `docs/pr-and-push.md:51` — a master merge counts; re-derive the body's TFM and test-count lines from the merged `Build/TargetFrameworks.props` · recurs: round 2 MIN007 (body not reconciled after a redesign)
- MIN012 · rule: `docs/testing.md:764` (scope invariant on a hand-picked subset, written from this PR's round 1) · why it did not fire: the rule ranges over clients × phases × origin for "nothing loads"; it does not cover the second claim, "no pooled process-account connection serves impersonated work", nor that claim's skip routes; the author's test providers are all `SQLiteDataProvider` subclasses · correction: `docs/testing.md:764` — the mechanism's decline routes are elements of the set · recurs: round 1 MIN001 and SUG003
- MIN013 · rule: `agents/code-reviewer.md:273` (third-party claims verified against vendor docs) · why it did not fire: the trigger is "new or changed comment"; two of the three sites are `SKILL.md:69` (markdown) and the `--impersonate` help string (`QueryExecutionCliOptions.cs:36`); round 2's NIT004 quoted the same skip list and checked only its membership, not its stated reason · correction: `agents/code-reviewer.md:273` — extend to markdown docs and CLI help/description strings · recurs: round 2 MIN006 (`SKILL.md:70` per-client warm-up claim)
- SUG006 · rule: `docs/work-plan.md:222` (a stub mirrors the production shape) binds plans only; `docs/acting-on-findings.md:31` binds reviewer suggestions only · why it did not fire: no rule reaches a no-plan author whose every test replaces the type that took over a responsibility · correction: `docs/testing.md:764` (second clause of fix 2) · recurs: round 1 MIN005, round 2 SUG005 (double-only coverage of `IImpersonationSession`)
- SUG007 · rule: none · why it did not fire: no rule covers production-unreachable paths kept for cross-OS testability · correction: none recommended; this is a one-off, and BLK001's rescope removes most of the class · recurs: —
- NIT006 · rule: `docs/testing.md:634` · why it did not fire: the author never ran `scripts/test-diff-sweep.ps1`; review passes were first briefed its hits by `skills/review-pr/SKILL.md:550` (`b8676a3`, 2026-10-28), after round 2 · correction: none, already landed · recurs: —
- NIT007 · rule: `docs/testing.md:634` · why it did not fire: same as NIT006 · correction: none · recurs: —
- NIT008 · rule: `docs/testing.md:634` · why it did not fire: same as NIT006 · correction: none · recurs: —
- NIT009 · rule: `docs/testing.md:652-661` (single call plus assertion is a chain) · why it did not fire: same as NIT006; the example also landed only on 2026-10-17 (`0239405`), the day of round 2 · correction: none · recurs: —
