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
