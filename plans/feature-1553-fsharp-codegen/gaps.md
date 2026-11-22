# Gap ledger — feature/1553-fsharp-codegen (PR #5707)

## Round 1 — reviewed HEAD 36caa4908

No work plan exists for this branch; findings are attributed to the block that would have carried them.

| Finding | Class | Would-be block | Gate | Preventable |
|---|---|---|---|---|
| MAJ001 type initializer dropped | GAP-03 | P7 parity row per C# `CodeClass` member visited | — | yes |
| MAJ002 7 options silently overridden | GAP-03 (+GAP-01) | P7 row per `ScaffoldOptions` member with F# disposition | — | yes |
| MAJ003 option values at `DataParameter` | GAP-02 (+GAP-03) | P4 probe of option handling at value boundaries | — | partly |
| MAJ004 CI never runs generator | GAP-05 | TO-n regenerate + diff goldens in CI | G-01 | yes |
| MAJ005 missing XML doc | GAP-08 | G-03 new public surface | G-03 | yes |
| MIN001 OCaml-reserved keywords | GAP-02 | P4 check keyword list vs spec | — | yes |
| MIN002 bare `#nowarn` | GAP-05 | TO-n for `--no-xmldoc-warn` | — | partly |
| MIN003 `--base-entity` dropped | GAP-03 | P7 per-option row | — | yes |
| MIN004 stale CLI in generate.ps1 | GAP-05 | regenerate-and-diff TO-n | G-01 | partly |
| MIN005 runtime tests on hand mirror | GAP-05 | TO-n consuming generator output | G-01 | yes |
| MIN006 no CLI fail-fast tests | GAP-05 | negative TO-n per rejected option | G-01 | yes |
| SUG001 CT defaults / outref | GAP-03 | P7 method-signature parity rows | — | partly |
| NIT001/NIT002 `module rec` doc drift | GAP-10 | — | — | no |
| NIT003 stale PR body (`--nrt`) | GAP-10 | — | — | no |

### Aggregate

12 of 15 trace to blocks a Tier M plan would have required. Dominant: GAP-05 (×5) and GAP-03 (×4), with one root cause: an alternative back-end built against an existing reference implementation without enumerating its surface, and verified against artifacts not produced by the generator (committed goldens, hand mirror). Largest single prevention: a P8 obligation that tests consume generator output produced in the same CI run.

### Recommended durable fixes (route to /session-reflect plan-rule bucket)

- GAP-05 → `work-plan.md` P8 semantics: for a code generator, a TO-n must exercise output of the current generator in the same run; every rejected option gets a negative TO-n.
- GAP-03 → `work-plan` SKILL scout brief: an alternative implementation of an existing abstraction enumerates the reference's full surface in P7, each row implemented / fail-fast / deferred-with-reason.
- GAP-02 → `plan-critic.md` attack vector: target-language wrapper types crossing runtime value boundaries; keyword lists sourced from the language spec.

## Round 2 — reviewed HEAD 11426fe3c + local master merge 26614576e

The plan (Tier L, approved 2026-10-11) covers only the capability-flag change and amendments A-1..A-8. Its scope note excludes the earlier branch: the July F# scaffolder and the round-1 fix commits `bc0330712`..`938737d41`, which were written without a plan on 2026-10-11 before `cffdd7126`. 8 of the 17 findings sit in that excluded code. Those are attributed to the block that would have carried them, as in round 1.

### Attribution

- **MAJ006** (`<c>await</c>` fails MA0154 on merged tree) — GAP-10 — master changed after the last measurement: #6321 (Meziantou 3.0.339, merged 2026-11-13) widened MA0154 to `await`, 22 days after the last G-05 (2026-10-22, exit 0); the line is pre-plan (`dc90b4f07`, 2026-07-11). Partly preventable: G-05 had already hit MA0154 on `<c>this</c>` in `LanguageFeatures.cs` (plan.md:215) and fixed only that instance; a branch-wide sweep for keywords in `<c>` would have removed this one too — G-05 — preventable: partly
- **MIN107** (LINQPad `[NotColumn, NotNull]` phantom column) — GAP-05 — E-27 mirrors E-26 in lockstep but has no `TO-n`; A-6's tests exercise only `EntityDescriptor`, and A-6 stated the rule by analogy ("like `[PrimaryKey]`/`[Identity]`"), so `StaticSchemaGenerator.cs:149` copied the unconditional pk/id shape while `EntityDescriptor.cs:342-368` honours the attribute only without a ColumnAttribute; A-6 also got no P12 delta round — — — preventable: yes
- **MIN109** (Person376 becomes columns, Issue376 baselines move) — GAP-03 — A-6's impact census was one sentence ("all either lack `[Table]` or pair the attribute with `[Column]`") with no pattern or hits, missing `IssueTests.cs:412-420`; the same sentence justified "baselines left to CI", so G-02 was never re-derived for A-6 (P9's G-02 covers TO-4/TO-5 only); no P12 round for A-6 — G-02 — preventable: yes
- **MIN108** (function wrappers pass `'T option` args unconverted) — GAP-03 — pre-plan round-1 fix `f227f3f9a`/`0db32f178` covered procedures only and left the TODO at `DataModelGenerator.Functions.Procedures.cs:633-634`; a P7 row per generated wrapper kind crossing a query/ADO boundary (procedures, table functions, scalar functions) was needed; the later plan read the region (P7 identity-site row cites `:619/:643`) but recorded neither a `deferred:` row nor a P10 line; secondary GAP-05 (no runtime test calls a generated function wrapper); attribution holds whatever the probe shows — — — preventable: yes
- **MIN207** (scaffold gate fsproj restores inherited TFMs) — GAP-01 — pre-plan (`19e7ff1b1`, 2026-07-10); no corpus rule says a `Tests/` project pinning `<TargetFramework>` must clear the plural inherited from `Tests/Directory.Build.props:5-6`; only precedent is code (`Tests.Analyzers.csproj:7-8`) — — — preventable: partly
- **MIN208** (GeneratedShape_* tests run the hand mirror) — GAP-05 — pre-plan tests (`d48489cf7`, `0db32f178`) that cannot go red on a generator defect; round-1 fix `004ea99c4` added `GeneratedCode_*` over real output but nothing retired or re-described the mirror tests; TO-4 names only `FSharpTests.GeneratedCode*`; literal recurrence of round-1 MIN005 — — — preventable: partly
- **MIN209** (resets of flags already false in `Default()` unpinned) — GAP-05 — TO-2's input is `ScaffoldOptions.Default()`, so it cannot go red for `EntityClassIsPartial`, `GenerateStaticInitDataContextMethod`, `HasUntypedOptionsConstructor`, `GenerateAssociationExtensions`, `GenerateProceduresSchemaError`; the P8 residual reason (plan.md:207, "CLI options are rejected for F#") covers CLI callers while SC-3/D-3 exist for library callers; A-7's `ErrorDirective` reset pinned only on #6037 (TO-9) — — — preventable: yes
- **MIN210** (readme C#-only list omits `--emit-schema-errors`) — GAP-03 — A-7's P7 "`PragmaType.Error` producers" row lists the CLI option (`ScaffoldCommand.Options.cs:904` → E-35) but has no row for `readme.md:240-243`, though E-15/E-22 show the plan knew the readme describes F# option handling — — — preventable: yes
- **MIN211** (PR body: "Supported in" wording, CP0006 rationale, 6.6.0 vs 6.7.0) — GAP-02 — earliest source is P10's "no external implementer is possible (U-1)", overstating U-1 ("can only implement it by delegating"), while TO-1a builds such a delegator; the version half is GAP-10 (6.6.0 shipped without #5707, #6344); "Each option shows" is prose drift — — — preventable: partly
- **MIN212** (no CLI test runs `--target-language f#` to success) — GAP-05 — E-12 deleted the CLI forcing block and D-3 relies on the CLI reaching `Scaffolder` (`Execute.cs:168`); TO-6 covers only rejection; P7's "CLI tests … out-of-scope (behaviour unchanged)" contradicts U-4/SC-4; the F# success path runs only in local `generate.ps1` (TO-4) — — — preventable: yes
- **NIT204** (`CliOption.cs:37` example says NRT doesn't apply to F#) — GAP-03 — pre-plan prose (`042fae9dc`, 2026-07-10) falsified next day by `1d99b55db` (F# nullness under `--nrt`), which needed a prose sweep; same falsification was round-1 NIT003 (floored GAP-10 then) — — — preventable: partly
- **NIT205** (`FSharpCodeGenerationTests.cs:116-117` narrowed set without reason) — GAP-07 — written by E-14 (`cffdd7126`); `testing.md` → *A narrowed provider set is a claim* existed since 2026-09-21 but the plan had no `conventions:` line (step 4's Test-layout embed landed 2026-10-12, `406f742`); the reason lived in TO-1a/1b only; secondary GAP-08 (A-7's G-01 sweep set touched-file hits aside) — G-01 — preventable: yes
- **NIT206** (`FSharpTests.cs` narrowed sets without reason) — GAP-07 — same rule never embedded; `:159/:172/:179/:186` round-1 planless, `:202` A-6 (no `conventions:` line), `:152` predates the rule; secondary GAP-08 (A-7's G-01 recorded them as "earlier-round branch code") — G-01 — preventable: yes
- **NIT207** (`FSharpCodeGenerationTests.cs:487/:154/:399` one-line chains) — GAP-08 — `testing.md:634` landed 2026-10-12 after E-14/A-5; first prevention point was A-7, when `work-plan/SKILL.md:320` (2026-10-17) required sweeping the branch's new test code; G-01 (plan.md:211) recorded and dismissed the hits — G-01 — preventable: yes
- **NIT208** (`Tests/FSharp/GeneratedCode.fs:30/:55/:42` chains) — GAP-08 — round-1 planless lines (`004ea99c4`, `84ff1e569`) in a file A-2's E-21 touched; among the hits A-7's G-01 set aside — G-01 — preventable: yes
- **NIT209** (`ScaffoldTargetLanguageTests.cs:79` chain) — GAP-08 — round-1 planless line (`3704419e7`) in a file A-7's own E-35 touched; dismissed the same way — G-01 — preventable: yes
- **OOS-2** (`BaseEntityClass` fails late for library callers) — GAP-03 — D-2 rows and P7's library-caller settings row came from U-4's scout of the CLI forcing block (forced value → option); nobody walked the converse (every `Languages = TargetLanguages.CSharp` option → library disposition); `--base-entity` was CLI-rejected (round-1 `639b69983`), never forced, so `Scaffolder.ApplyLanguageFeatures` never saw it; critic round 7 found the mirror case (`--emit-schema-errors`) — — — preventable: yes

### Aggregate

GAP-03 ×5, GAP-05 ×4, GAP-08 ×3, GAP-07 ×2, GAP-01, GAP-02, GAP-10 ×1 each. Three clusters cover 10:

- **Test-convention sweep (NIT205–NIT209).** A-7's G-01 sweep saw the hits and filed them as "earlier-round branch code". The fix already landed: `definition-of-done.md:11` ("never waived as 'outside this plan'", 2026-11-01, #5673).
- **Restricted option set never enumerated (OOS-2, MIN210, MIN209).** The C#-only option set was never listed as a domain with a per-layer disposition (CLI reject, library reset/fail-fast, readme line, option-on test).
- **A-6 never critiqued (MIN107, MIN109).** A-6 added core-mapping edit-points E-25..E-28 under `Source/LinqToDB` with no `re-derives:` line and no P12 delta round; the validator's date cutoffs (`work-plan.ps1:719`, `:738`) grandfathered it to warnings.

The only true GAP-10 is MAJ006 (#6321).

### Recommended durable fixes

- GAP-03 ×2 + GAP-05 (OOS-2, MIN210, MIN209) → `work-plan/SKILL.md` step 5 scout brief, beside the closed-list rule at :98: when a change moves enforcement of a restricted option set between layers, P7 lists every member with a per-layer disposition and a `TO-n` whose input sets it to the value the layer removes (a `Default()` input cannot go red for fields already at default).
- GAP-05 + GAP-03 (MIN107, MIN109) → `work-plan.ps1 -Action validate -Done`: a missing `re-derives:` line or P12 round is an error regardless of amendment date when the amendment adds edit-points under `Source/LinqToDB/`.
- GAP-05 ×2 (MIN208, MIN212) → `work-plan.md:194` P8 semantics: mirror tests already on the branch are retired or re-described in the same plan; the user entry point (CLI) gets one success `TO-n` per target language.

## Corpus trace

- MAJ006 · rule `agents/code-reviewer.md:261-262` lists only `<c>true/false/null</c>`, narrower than the analyzer; `docs/release/nuget-package-notes.md:328` records #6321's fallout but nothing prompts a Release build of open branches · correction: cover any C# keyword in `<c>` + branch-wide sweep on an MA0154 hit; analyzer bump → merged-tree Release build on open branches · recurs: #5578/#5570/#5602/#5703
- MIN107 · rule `agents/plan-critic.md:33`, `skills/work-plan/SKILL.md:316` · no P12 round for A-6; validator cutoff only warned · correction: the `work-plan.ps1` fix above
- MIN109 · rule `skills/work-plan/SKILL.md:136` landed 19 h after A-6 · correction: a declarer sweep lists each declarer with `file:line` + classification; an "all … either" summary is a labelled hypothesis
- MIN108 · rule `agents/plan-critic.md:117` landed minutes after the planless fix commits · correction: a TODO/known-limitation inside a P7-cited region becomes a `deferred:` row or P10 line · recurs: round 1 MAJ003
- MIN207 · no rule · correction: `docs/testing.md`: a `Tests/` project pinning `<TargetFramework>` also sets `<TargetFrameworks></TargetFrameworks>`
- MIN208 · rule `docs/work-plan.md:194` covers new obligations only · correction: third durable fix · recurs: round 1 MIN005
- MIN209 · no rule checks a P8 residual's reason covers the SC's population · correction: first durable fix
- MIN210 · rule `skills/work-plan/SKILL.md:315` landed after A-7 · correction: none
- MIN211 · rule `docs/definition-of-done.md:27` · correction: a P10 line citing a `U-n` quotes its qualifier
- MIN212 · rule `docs/work-plan.md:194` · correction: third durable fix · recurs: round 1 MAJ004/MIN006
- NIT204 · rule `skills/work-plan/SKILL.md:315` (2026-11-15) · correction: none · recurs: round 1 NIT003
- NIT205/NIT206 · rule `docs/testing.md:547` · correction: covered by `definition-of-done.md:11` · recurs: #5673
- NIT207/NIT208/NIT209 · rules `docs/testing.md:634`, `skills/work-plan/SKILL.md:320` · A-7 read "the branch's new test code" as its own additions · correction: `SKILL.md:320` → "every test line in `git diff <base>...`, whichever round wrote it" · recurs: #5673
- OOS-2 · rules `skills/work-plan/SKILL.md:178`, `:98` · :178 keys on "alternative implementation", not layer moves · correction: first durable fix · recurs: round 1 MIN003

### Continuity

- **GAP-05 recurs (round 1 ×5 → round 2 ×4).** MIN208 repeats MIN005; MIN212 is the MAJ004/MIN006 shape. The round-1 rule landed (`work-plan.md:194`) but never reached the planless round-1 fix commits and has no clause for existing mirror tests.
- **GAP-03 recurs (×4 → ×5).** OOS-2 is MIN003 at the library layer; MIN108 is MAJ003 in function wrappers. Rule `SKILL.md:178` landed but keys on "alternative implementation".
- **GAP-10 calibration.** Round 1 floored NIT003 as GAP-10; NIT204 comes from the same commit (`1d99b55db`), so that class is sweep-catchable.
- **New this round.** GAP-07/GAP-08 (5) and the A-6 critic skip (2).
- **Round-1 durable fixes all present:** `work-plan.md:194`, `work-plan/SKILL.md:178`, `plan-critic.md:117`, `code-reviewer.md:297`.

