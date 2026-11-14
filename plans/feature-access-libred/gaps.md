# Gap ledger — PR #5956 (feature-access-libred)

## Round 1 — reviewed HEAD f4956a907 (2026-11-12/13)

Judged against the plan through A-22 (2026-11-10). DROPPED items omitted (SUG003, NIT002, MIN012).

- **MAJ001** (REPLY+RESOLVE: database component dropped) — GAP-01 — the drop was a 4th LibRed SQL divergence beyond SC-2's three (A-13 run 4 BuildObjectName override); G-02 measured it (16 baselines, "Expected") but it never reached SC-2 or a P10 line, so the drop-not-refuse contract (Issue681Tests / NO_DATABASE_NAME) was first cited in A-24 — G-02 — preventable: partly
- **MIN001** (REPLY+resolve: LibRedConnection not detected) — not-a-gap: reviewer-disagrees-with-P10 — P10 adjudicated connection-string auto-detection; the connection-object case was added by A-24
- **MIN002** (FIX: wire DatabaseExists/DropDatabase/ClearPool) — GAP-01 — P2 had no SC for LibRed's product-side database lifecycle, so E-3 bound helpers no requirement asked for; A-2 dropped CreateDatabase as "no consumer" but kept three equally consumer-less helpers — — — preventable: partly
- **MIN003** (FIX: README "net11.0 only", template `\\`) — GAP-03 — README rows went stale at A-20 (net10 enablement), which updated template/CI/CLI/LINQPad but not E-25's rows; E-16 copied the Windows separator form into a Linux-first provider with no P7 row on path form — — — preventable: yes
- **SUG001** (FIX: remarks prerelease / no lock file) — GAP-02 — D-9's failure mode names file locking as a risk, but no U-n probed LibRed's locking; G-03's content half never asked for the doc — G-03 — preventable: partly
- **MIN004** (FIX: PublicAPI duplicates + ConvertType namespace) — GAP-08 — G-03 recorded pass with no head/date and no failable instrument, not re-run after the 2026-11-09/10 master merges that re-added 12 Shipped lines; the LinqToDB.SqlQuery.ConvertType spelling dates from authoring — G-03 — preventable: yes
- **MIN005** (FIX: length 0 → VarChar(0)) — GAP-02 — A-18 asserted "a length of 0 is reported for the unbounded types" without checking a bounded VarChar from a stored-query expression; also GAP-05: TO-6 checks idempotence only and committed VarChar(0) as baseline — — — preventable: partly
- **MIN006** (FIX: Bit reported bool?) — GAP-08 — TO-3 required per-column SystemType or a whole-DatabaseSchema diff vs Access.Ace.OleDb; neither arm was built, yet G-01 recorded TO-3 pass from 14/14 and 44/44; also GAP-05: the SystemType arm alone cannot see nullability — G-01 (TO-3) — preventable: yes
- **NIT001** (FIX COMMENT: CreateFormat casing) — GAP-10 — the comment was written while implementing A-18; no plan block carries comment wording; the counter-evidence lived only in generated scaffold output — — — preventable: no
- **OOS-ACCDB** (PROMOTED MIN: BIGINT/DATETIME2 typed object) — GAP-02 — A-18's "all 17 names the engine returns were covered" was measured on the suite's MDB-typed database only; the engine's type set was never listed; also GAP-05: TO-3 targets AllTypes, which has no such column — G-01 (TO-3) — preventable: partly
- **MIN007** (FIX: Issue3360 gate is linq2db's GUID literal) — GAP-02 — A-20 re-stamped Issue3360 as LibRed's without re-probing the {guid {…}} form D-6/U-9 had rejected; the gate's own Details pointed at linq2db SQL; ChrisJollyAU's 2026-10-16 measurement was not recorded in A-21/A-22; G-02's alpha.3 cross-compare was never re-captured — G-02 — preventable: yes
- **MIN008** (FIX: FromSqlTests trio narrowed without reason) — GAP-09 — FromSqlTests.cs had no E-n through A-22; fbf408b3d (2026-11-09) landed after the reconcile-before-push rule without a reconcile; A-21/A-22 sweeps were scoped (-Path Tests/Tests.Wasm/, -Base HEAD) and could not see it; also GAP-07: the narrowed-set rule reached no conventions: line until A-23 — G-01 — preventable: yes
- **MIN009** (FIX: TestConvertToDate_WithNull narrowed) — GAP-09 — 5926952da (2026-09-22) narrowed it during A-16 triage, named by neither A-16 nor A-17; AccessTests.cs then got an E-n for a different test (E-36), so a per-file reconcile passes it; also GAP-07 — G-01 — preventable: yes
- **MIN010** (FIX: McpInfoTool note vs Bundled:true; CLI SKILL.md) — GAP-03 — P7 lists McpInfoTool and ProviderDialectCatalog but not Source/LinqToDB.CLI/SKILL.md; the note went stale at A-20; A-21's sweep checked presence, not content — — — preventable: yes
- **OOS-BETA1** (FIX: bump to beta.1 + AccessDmlService arm) — GAP-10 — alpha.5/beta.1 and beta.1's new missing-table text post-date A-22; the master retarget (first recorded A-23) retired P3's "unmergeable before .NET 11 RTM" premise that made a prerelease dependency tolerable — — — preventable: no
- **MIN011** (ACCEPT+P10: LINQPad paired-entry behaviours) — GAP-09 — DriverHelper/DynamicConnectionModel/xaml had no E-n through A-22; A-19's "stored settings are unchanged" contradicts f05176b05; -Reconcile was never run between f05176b05 and A-23, and when it ran the brace-list false positives buried these files — — — preventable: yes
- **OOS-LINQPAD-AUTOASSIGN** (GUARD: Providers.Count == 1 rewrites a stored connection off Windows) — GAP-03 — A-19 hid OLE DB/ODBC off Windows with no P7 row on consumers of Database.Providers cardinality; also GAP-02: "existing connections still load" claimed without the check — — — preventable: yes
- **SUG002** (FIX: Contains("LibRed") before the Microsoft markers) — GAP-06 — P3 allows only arms added beside existing ones; E-10 did not place the marker in the first-match chain; also GAP-05: TO-5 had no Microsoft configuration name containing "LibRed" and its red arm was never run — G-01 (TO-5) — preventable: yes
- **OOS-ACCESSFACTORY** (FIX: assembly-name dispatch untested) — GAP-05 — P7's AccessFactory row was "covered by E-12" but no TO-n names AccessFactory; TO-1/TO-5 run through configuration names only — G-01 — preventable: yes

### Aggregate

18 attributed + 1 not-a-gap. GAP-02 ×4, GAP-03 ×3, GAP-09 ×3, GAP-01 ×2, GAP-08 ×2, GAP-10 ×2, GAP-05 ×1, GAP-06 ×1. Unpreventable 2/18 (11%).

Clusters: (1) A-18's schema-provider rewrite validated only on the suite's MDB-typed database, TO-3's whole-schema diff vs OLE DB never built — MIN005, MIN006, OOS-ACCDB, NIT001; (2) post-approval edits no sweep could see — MIN008, MIN009, MIN011. Single highest-yield prevention: TO-3's whole-DatabaseSchema diff vs OLE DB, re-run after A-18, procedures and parameters included. A-23's pre-review reconcile named MIN007/MIN008/MIN009/MIN011/SUG002 — the mechanism works; it ran seven weeks late.

### Recommended durable fixes

- GAP-09 ×3 → work-plan/SKILL.md *Mode: amend* step 4 + a work-plan.ps1 validate check: the sweep cited on a conventions:/G-01 line must cover `<PR base>...` over all of `Tests/` (reject `-Base HEAD` and a narrower `-Path`); fail on `narrowedWithoutReason` hits in a file whose E-n rows do not name that test.
- GAP-02 ×4 → plan-critic.md attack vector: when a dependency bump re-measures behaviour and a gate or list is kept, require (a) every D-n-rejected alternative re-probed, (b) a hand-written type list diffed against the engine's catalog, not the suite database, (c) every D-n failure-mode risk to have a U-n probe.
- GAP-03 ×3 → work-plan/SKILL.md *Mode: amend* step 3: when an amendment flips a premise or changes a list's cardinality, grep the branch diff and consumer-facing docs (README.md, Source/*/SKILL.md, MCP notes) for the retired premise's wording, and add a P7 row per consumer of the changed collection.

## Round 2 — reviewed HEAD c2888aded (2026-11-13/14)

Judged against the plan through A-25. Dropped or no-gap items omitted: ACCDB complex types, inline DateTime sub-ms, NULL-vs-False.

- **SUG005** (FIX: four LibRed [ActiveIssue] gates with no tracking issue) — GAP-07 — the plan's conventions: lines (A-21..A-24) cite testing.md "Gating an assertion failure" but carry no rule that a gate's "re-check when a newer LibRed ships" must name an issue; the rule was never put in front of the author — G-01 — preventable: yes
- **SUG004** (FIX: AccessProvider.LibRed remarks omit tested LibRed.Ado version) — GAP-02 — A-24 re-measured GUID behaviour across prereleases yet E-1's XML doc was never listed as a place that must carry the reflection-loaded version; round 1 SUG001 added only "prerelease" — G-03 (content half) — preventable: yes
- **MIN014** (FIX: AccessTools.CreateDatabase version doc LibRed-only, AutoDetect .accdb vs .mdb) — GAP-01 — E-46 named no required behaviour for `version` on the non-LibRed arms nor the AutoDetect outcome per provider, and no TO covered it — G-03 — preventable: yes
- **NIT003** (FIX: one-line chain AccessTests.cs:456) — GAP-08 — A-24's G-01 records test-diff-sweep "0 one-line chains in new code", yet one remained in E-58's CreateDatabaseLibRed; sweep ran before the last test edit or missed it — G-01 (test-diff-sweep) — preventable: yes
- **MIN013** (PROVE+FIX: CreateDatabaseLibRed never reaches deleteIfExists on an existing file) — GAP-05 — no obligation required the deleteIfExists arm on a pre-existing file; the test stayed green with AccessTools.cs:163 removed (walk red arm: 4 IOException cases) — G-01 — preventable: yes
- **NIT004** (FIX: nested one-line chains Issue1925Tests.cs:74-75) — GAP-08 — A-24 claims "0 nested chains", yet two added nested chains inside Assert.Throws lambdas survived; secondary: sibling arms use the same shape — G-01 (test-diff-sweep) — preventable: partly
- **MIN015** (PROVE+FIX: UseAccess(cs, LibRed) untested, extra version-probe connection) — GAP-05 — no TO names UseAccess(cs, LibRed); TO-1/TO-5 go through configuration names; the extra open (2 vs 1) is a behaviour no SC named (GAP-01 secondary) — G-01 — preventable: yes
- **MIN016** (from SUG006, FIX: dead view exception for Bit nullability) — GAP-02 — the view exception rested on an unmeasured premise; same class as round-1 MIN006 (TO-3's whole-schema diff vs OLE DB never built; no view column in AccessLibRedColumnTypes) — G-01 (TO-3) — preventable: yes
- **SUG007** (promoted OOS, REWRITE: hand-built reflection binding of CreateDatabase) — GAP-02 — E-45 (A-24) prescribed the hand-built expression on A-2's unchecked "TypeMapper cannot wrap" (TypeMapper maps Nullable<T> generically); code-design.md's "Provider adapters read driver members through TypeMapper wrappers" appears in no conventions: line, P-block or E-n (GAP-07 secondary); the round-1 fix introduced it — G-01 — preventable: yes
- **SUG008** (promoted OOS, FIX: stable CLI/LINQPad docs omit prerelease LibRed) — GAP-03 — round 1 MIN010 / OOS-BETA1 flagged the same consumer docs; P7 still had no row for the prerelease statement in CLI SKILL.md, McpInfoTool, LINQPad README — G-03 — preventable: yes
- **OOS-E47** (MEASURE → FIX: LINQPad ClearAllPools arm and 17-file signature change reverted; ClearPool is a no-op) — GAP-02 — A-24's stop rule (drop the arm if ClearPool is a no-op) was never run and no test covered the arm; the decompile was available at plan time; also GAP-08 (G-01 recorded pass without it) — G-01 — preventable: yes
- **IGOR-DBNAME-DOC** (FIX: DatabaseName "Supported by: Access" unqualified) — GAP-03 — MAJ001's P10 line never swept per-provider "Supported by" doc lists (LinqExtensions.TableHelpers.cs:54, outside the diff); P7 had no row for them — — — preventable: yes

### Aggregate

11 attributed, 0 not-a-gap. GAP-02 ×4, GAP-05 ×2, GAP-08 ×2, GAP-03 ×2, GAP-01 ×1, GAP-07 ×1. Preventable yes 9, partly 1, no 0.

GAP-02 dominates again, as in round 1: a plan sentence asserted a capability or premise ("TypeMapper cannot wrap", "view exception", "ClearPool measured by the test") that a one-line check or decompile would have refuted. A-24 (the round-1 fix amendment) produced 6 of the 11 (SUG007, OOS-E47, MIN013, MIN015, NIT003, NIT004).

### Continuity

- MIN002's round-1 fix (E-45) introduced SUG007; A-2's TypeMapper premise was retired, not re-derived.
- A-24's own stop rule was never run; OOS-E47 is the direct result (17-file revert).
- MIN016 repeats MIN006 (Bit nullability without a whole-schema diff vs OLE DB); SUG008 / IGOR-DBNAME-DOC repeat round 1's GAP-03 (MIN010); SUG004 repeats SUG001.
- Landing status of round 1's recommended corpus fixes not verified.

### Recommended durable fixes

- GAP-02 (+GAP-08) → plan-critic.md attack vector and work-plan/SKILL.md *Mode: amend*: no E-n marked implemented, and no earlier premise ("not expressible", "no consumer", "measured by test X") retired, without a recorded probe or decompile; every amendment stop rule gets a G-01 line.
- GAP-07 + GAP-01 → work-plan.md *conventions:*: an amendment touching `*ProviderAdapter.cs` cites code-design.md's TypeMapper rule; one adding `[ActiveIssue]` cites the tracking-issue requirement.
- GAP-05/GAP-08 → test-diff-sweep.ps1 usage: re-run after the last test edit and record the head it covered; extend the nested-chain detector to lambdas inside Assert.Throws; every new public overload / UseXxx entry point gets a TO whose red arm is the removed line.

## Round 3 — reviewed HEAD a6027efcb (2026-11-14)

Judged against the plan through A-26 (P6 E-59/E-60 rows at plan.md:654-664, A-26 at plan.md:1847-1884, P10 A-26 lines at plan.md:1001-1008). G-09's A-26 condition is met: Azure test-all 25672 green at a6027efcb. All three findings come from A-26, the round-2 fix amendment.

- **MIN017** (PROVE+FIX: UseAccess still runs the version probe when LibRed is named by ProviderName / configuration string) — GAP-03 — E-59 (plan.md:660-661) and A-26 (plan.md:1854) keyed the skip on the `provider` argument alone; no P7 row listed the other routes by which `UseAccess` reaches LibRed, though the plan names all three (P10 plan.md:934; P7 plan.md:675-676 shows the flavour is resolved inside the detector, after the argument). Secondary GAP-05: `UseAccessLibRed`'s red arm (plan.md:1874) covered only the argument route. Secondary GAP-06: acting-on-findings.md:49 "attack a fix's own new condition" not applied to `provider == AccessProvider.LibRed` — G-01 — preventable: yes
- **MIN018** (FIX: AccessProvider.LibRed remarks hard-code 11.0.0-beta.1 with no updater; over-general parenthetical) — GAP-03 — A-26 (plan.md:1856) and its P10 line (plan.md:1001-1003) told the remarks to name the tested version; no P7 row recorded its single source (`Directory.Packages.props:167`) or that nothing updates the copy (`release-deps` has no LibRed step), though the same A-26 bullet chose "no version copy" for the CLI SKILL.md, MCP note and LINQPad README. The over-general claim and early wrap are prose (GAP-10 floor); the work-plan.md:300 prose-claim vector was never run on A-26 (no P12 round after round 8) — — — preventable: partly
- **SUG009** (PROVE+FIX: AutoDetect → .mdb on the LibRed arm untested) — GAP-05 — A-26's E-46 bullet (plan.md:1853) names the AutoDetect outcome change, but its test bullet (plan.md:1857) extended `CreateDatabaseLibRed` only for `deleteIfExists`; `[Values] bool accdb` maps to Ace/Jet only, so reverting `AccessTools.cs:150` stays green; work-plan.md:181 (an enumerated set is an obligation checklist) applied: AccessVersion has three members, the fixture covered two — G-01 — preventable: yes

### Aggregate

3 attributed, 0 not-a-gap: GAP-03 ×2, GAP-05 ×1. Preventable: yes 2, partly 1, no 0.

All three come from A-26, as A-24 produced 6 of round 2's 11. Shared shape: A-26 named a set (LibRed's three naming routes in P10, the AccessVersion members in E-46), then wrote its condition or fixture against a subset. One change would have prevented MIN017 and SUG009: a G-01 line per new or changed condition in a review-fix amendment, listing every input the plan already enumerates that reaches it, with one red-arm case per input.

Fixes (2026-11-14, worktree, not yet committed): MIN017 — `AccessProviderDetector.IsLibRed` picks the dialect from the resolved provider; `UseAccessLibRed` gains `[Values] bool byProviderName` (red 4/4 at a6027efcb, opens 2). SUG009 — `CreateDatabaseLibRed` takes `[Values(Ace, Jet, AutoDetect)] AccessVersion` (AutoDetect red 2/2 with line 150 reverted). MIN018 — remarks name the version by reference (user's choice: no number, no release-deps step). Green: 17/17 on both LibRed configs.

### Continuity

- Round 2's "every new public overload / UseXxx entry point gets a TO whose red arm is the removed line" was never written into the corpus (only gaps.md:73). A-26 applied it anyway (`UseAccessLibRed` red at 2 opens); it still could not catch MIN017, since a red arm on the removed line proves only the fixture's route. Read as "a red arm for every behaviour-changing line", it would have caught SUG009.
- Round 2's "every amendment stop rule gets a G-01 line" landed at work-plan.md:304; A-26 declared no stop rule, so no bearing.
- MIN017 repeats round 2's MIN015 (same `UseAccess` probe): the fix closed one of three naming routes.
- SUG009 repeats round 2's MIN014 ("no TO covered" AutoDetect): the fix amendment named the AutoDetect outcome and again wrote no case.
- MIN018 is the third finding on the same remarks (SUG001 → SUG004 → MIN018), directly from round 2's SUG004 fix; round 2's SUG004 row (gaps.md:44) framed the remedy as a copy.
- A-26 had no P12 critic round although it changed XML docs and READMEs (work-plan.md:300); A-24 had two (rounds 7 and 8).

### Recommended durable fixes

- GAP-03 + GAP-05 (MIN017, SUG009) → `work-plan/SKILL.md` *Mode: amend*: each new or changed condition in an amendment's E-n gets a G-01 line listing every input the plan enumerates that reaches it (P10 routes, enum members, P7 resolution order), with a red-arm case per input; the condition tests the resolved value, not the caller's argument.
- GAP-03 (MIN018) → `code-reviewer.md` rubric rule plus the amend-step P7 scout: prose that restates a single-source value (a package version, a count) cites the source by reference unless the owning update skill gains a step that rewrites the copy; gap-ledger remedies must not prescribe such copies.
- GAP-08 secondary (MIN018, no critic round on A-26) → `work-plan.ps1 -Action validate`: error when an A-n touching XML docs or READMEs has no later P12 round (enforces work-plan.md:300).
