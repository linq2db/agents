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
