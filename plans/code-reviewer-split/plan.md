# Work plan: code-reviewer-split — Move path-triggered rubric rules out of code-reviewer.md

**Tier:** M  ·  **Status:** approved  ·  **Approved-at:** 2026-10-13 (user, after round-2 `weak` with objections folded in)  ·  **Branch:** n/a (corpus-only, linq2db/agents master)
**Schema:** `.claude/docs/work-plan.md`  ·  **Gates:** `.claude/docs/definition-of-done.md`

## P1 Problem

`agents/code-reviewer.md` is the `code-reviewer` subagent's whole system prompt: 211,803 B at `92624c8` (≈80 k tokens), loaded in full on every reviewer pass — one or three per `/review-pr` (`skills/review-pr/SKILL.md:290-298`), one per `/verify-review` (`:104`), one per pre-push self-review (`docs/definition-of-done.md:20`). It has grown 14.6 KB → 211.8 KB since 2026-04-20, never split. Some rubric rules fire only on a narrow, path-identifiable change kind — tests, CI / build infrastructure, packaging, code generators — yet every pass pays for them.

This is the **narrow** variant chosen by the user (2026-10-13) after a broader split was refuted twice: only rules whose trigger is an unambiguous path family move; SQL / provider rules (4, 13, 19, 24), public-API rules (5, 12) and content- or claim-triggered rules (18, 21, 25) stay in core. Expected (scout per-rule chars): ≈30 k chars move → core ≈ 183 KB (≈ −13 %). An ordinary `Source/**` PR still loads the tests module (rule 6 fires on any code change) → ≈ −4 % single-pass; a PR touching no tests / CI / packaging / generator paths saves up to ≈ −14 %.

## P2 Success criteria

- SC-1 `agents/code-reviewer.md` ≤ 186,000 B (LF blob, `git cat-file -s`). Budget (critic round 3, measured at HEAD blob `ca265de`, 212,478 B): moved blocks 30,236 B → 182,242 B; E-1's additions (index ≤ 2,700 B, `rubricModules` instruction ≤ 600 B, `:144` clause ≤ 200 B) ≤ 3,500 B. → TO-1
- SC-2 Rules 6, 10, 14, 15, 16, 17, 20, 22, 23 each live in exactly one module, keep their number, and their text is byte-identical to `2998d44` except that every file-relative link is re-rooted from `docs/review-rubric/` (`../docs/<x>.md` → `../<x>.md`, `../AGENTS.md` → `../../AGENTS.md`; hrefs only). No in-rule cross-reference is rewritten. → TO-2
- SC-3 `scripts/review-rubric-modules.ps1` implements the D-2 table, and every moved rule's trigger as written in its own text selects its module. → TO-3
- SC-4 Briefing field `rubricModules`: a list → read exactly those (explicit `[]` = core only); absent → read every module. `/review-pr` (per pass), `/verify-review` and the pre-push self-review set it; the core states both meanings. → TO-4
- SC-5 For every moved rule r with focus f, pass f's set contains module(r) whenever it is selected (sets derived from the core's rule index); every rule 1-25 is in exactly one focus and one index row whose file holds it. → TO-5
- SC-6 On the staged tree: anchors 0 broken, commands 0 broken, links `broken[]` set-equal (`{file,target}`) to the 142 broken at plan time. → TO-6
- SC-7 A moved rule fires through the module path on a replayed diff, citing a phrase found only in that rule's text, and not with the module withheld. → TO-7

## P3 Constraints & anti-goals (M/L)

- Relocation only; incident notes stay with their rules; rule numbers and section names stay; output schema unchanged; rules move whole.
- Not moved: 1-5, 7-9, 11-13, 18, 19, 21, 24, 25.
- Not in scope: routing *new* rules to modules in `/session-reflect` / `review-gap-attributor` / `/work-plan` (a new rule lands in core).

## P4 Unknowns (M/L)

- U-1 Subagent reads named files — resolved-by scout: precedent `code-reviewer.md:12`, rule 6's conditional checklist (L242), `baselines-reviewer.md:12`, `test-writer.md:12`, `kb-research.md:12-16`; compliance unmeasured → TO-7 with a withheld-module control.
- U-2 References severed by moving these rules — resolved-by scout + critic (`\brule \d+\b`): `:179` (rule 1 → 6) and `:315` (rule 23 → 19) cross the boundary; both resolve through the index (D-4). Rule 6's `test-review-checklist.md` link moves with it.
- U-3 Module-name collisions — resolved-by critic Glob: `knowledge-base/architecture/{sql-provider,public-api}.md` exist; modules are named `rubric-<x>.md` and referenced path-qualified.
- U-4 Checkers see new files only once staged — resolved-by critic (`git ls-files` in all three); TO-6 runs after `git add`.
- U-5 Moved rules' links — resolved-by critic Grep `\]\(\.\./[^)]*\)`: all `../docs/<x>.md` except rule 14's `[AGENTS.md](../AGENTS.md)` (`:293`); SC-2 re-roots both shapes.

## P5 Decisions (M/L; rejected alternatives mandatory at L)

### D-1 — Move only path-triggered rules, whole

- **chosen:** rules 6, 10, 22 (tests), 14, 16, 20 (CI / build infra), 15, 17 (packaging), 23 (tooling).
- **rejected:** the broad split (also 4, 5, 12, 13, 19, 24, 18, 21, 25) — refuted twice; its SQL / public-API rows fire on nearly every Source PR (≈ −2 % saving there) and claim-triggered rules (18, 21, 25) cannot be selected by path.
- **why this:** each moved rule's trigger is a path family the script can test.
- **failure mode of the choice:** ≈ −4 % on an ordinary Source PR; the bulk (rule 1, 51 k) stays.

### D-2 — Path → module table

- **chosen:** per changed path, union of matching rows:

  | Path shape | Module | Rules |
  |---|---|---|
  | `Source/**` code (`*.cs`, `*.fs`, `*.vb`, `*.tt`, `*.ttinclude`), `Tests/**`, `DataProviders.json`, `UserDataProviders.json*` (rule 6 `:259`) | rubric-tests | 6, 10, 22 |
  | `.github/**`, `Build/**`, `.githooks/**`, `.vscode/**`, `.cursor/**`, `.gemini/**`, `.claude/**` and the `.claude` gitlink (rule 14 `:293`), `*.csproj`, `*.fsproj`, `*.vbproj`, `*.props`, `*.targets`, `*.yml`, `*.yaml`, `global.json`, `*.sln*`, `.editorconfig`, `nuget.config`, `*.cmd`, `*.ps1`, `*.sh` outside `Source/`/`Tests/`, and binary extensions (`dll exe pdb so dylib zip nupkg snupkg 7z png jpg jpeg gif webp ico bmp svg pdf sqlite mdb accdb sdf db bin`) | rubric-ci-infra | 14, 16, 20 |
  | `Source/**/*.csproj`, `Source/**/*.fsproj`, `Directory.*.props`, `NuGet/**`, `Build/licenses/**`, `Redist/**` (rule 15 `:296`), `Source/**` non-code files except `PublicAPI*.txt`, `CompatibilitySuppressions.xml`, `BannedSymbols.txt`, `CodeMetricsConfig.txt`, `*.DotSettings` | rubric-packaging | 15, 17 |
  | `Source/LinqToDB.CLI/**`, `Source/LinqToDB.Scaffold/**`, `Source/LinqToDB.Templates/**`, `Source/LinqToDB.LINQPad/**`, `NuGet/**/*.tt*` (shipped generators — rule 23) | rubric-tooling | 23 |
  | `*.md` / `*.txt` outside `Source/`, `Tests/`; `**/PublicAPI*.txt`; `**/CompatibilitySuppressions.xml`; `Source/BannedSymbols.txt`, `Source/CodeMetricsConfig.txt`, `*.DotSettings` | none | — |
  | anything else (e.g. `Examples/**` code, `Data/**` scripts, `*.sql`, `*.xaml`, `*.razor`) | **all** | fallback |

  Output `{ modules, byFocus, unmatched }`, `byFocus` from the core's index.
- **rejected:** reviewer-chosen modules (user decision 2026-10-13).
- **why this:** each row cites the rule text it serves (`:293` names MSBuild `Exec` / `<Target>`, `.claude/` hooks / settings and binaries; `:233` "Is there a test?"; `:259` `DataProviders.json` / `.template`; `:296` `Redist/`). Binaries are an explicit extension list (not "anything outside an allowlist", which round 3 showed sends ~240 tracked text files to ci-infra and makes the fallback unreachable); the binary row is applied in addition to the `Source/**` / `Tests/**` rows, so they cannot shadow rule 14. `*.csproj → packaging` is limited to `Source/**` (test projects are not packed) and tooling to shipped generators.
- **failure mode of the choice:** a CI / packaging concern expressed only in a `.cs` file (e.g. an env-var knob read in code) loads tests but not ci-infra; rule 3's L199 config-knob clause stays in core for that reason.

### D-3 — Files, index, per-pass sets

- **chosen:** `.claude/docs/review-rubric/rubric-{tests,ci-infra,packaging,tooling}.md`; the core's `### Focus scoping` lists (`:140-142`) become the rule index — each moved rule's entry gains its module path, so number, title, focus and file live in one place used for "rule N" resolution and for `byFocus` (pass f gets every selected module holding a rule of focus f). The index **replaces** the lists rather than adding a second table (SC-1 headroom is 258 B after the 3,500 B allowance; critic round 2). Each module opens with a header listing its `(rule, focus)` pairs, outside the byte-conserved rule text, so a pass skips the rules of other foci without a round-trip to the core.
- **rejected:** hand-written module↔focus list (round 1 showed it drops rules); `agents/` subfolder (agent discovery); bare basenames (U-3).
- **why this:** one table drives resolution, selection and TO-5.
- **failure mode of the choice:** a malformed index row breaks selection; TO-5 parses the same table.

### D-4 — `rubricModules` semantics and reference resolution

- **chosen:** list → those modules (`[]` = none); absent → all. A listed module that cannot be read is not fatal: the agent reviews with the rest and emits one `out_of_scope_observations[]` entry naming the unreadable module (schema unchanged). In-rule cross-references stay verbatim and resolve via the index; the main-agent "Grep it, never Read it" pointers (`agent-rules.md:171`, `review-orchestration.md:10`) name `docs/review-rubric/` as a second Grep target.
- **rejected:** "empty list means all" (loads everything for docs-only PRs); rewriting references (breaks SC-2).
- **why this:** separates "nothing applies" from "nobody computed it"; keeps the move byte-checkable.
- **failure mode of the choice:** a dispatcher setting `[]` wrongly drops modules — TO-3's committed-branch fixture and TO-4 guard it.

## P6 Edit-points

- E-1 `agents/code-reviewer.md` — remove rules 6, 10, 14, 15, 16, 17, 20, 22, 23; add the D-3 index and the D-4 instruction under `### Focus scoping`; extend `:144`'s add-a-rule clause to the index and modules.
- E-2 `docs/review-rubric/rubric-tests.md` — new: rules 6, 10, 22.
- E-3 `docs/review-rubric/rubric-ci-infra.md` — new: rules 14, 16, 20.
- E-4 `docs/review-rubric/rubric-packaging.md` — new: rules 15, 17.
- E-5 `docs/review-rubric/rubric-tooling.md` — new: rule 23.
- E-6 `scripts/review-rubric-modules.ps1` — new: D-2 table, `byFocus` from the index.
- E-7 `skills/review-pr/SKILL.md` — step 6: run E-6 on the confirmed file list; single pass `modules`, multi-pass `byFocus[focus]`.
- E-8 `skills/verify-review/SKILL.md` — run E-6 on the PR file list; brief `rubricModules`; `:60`'s rule 6 pointer gains the module path.
- E-9 `docs/review-orchestration.md` — briefing contract gains `rubricModules`; `:10` names `docs/review-rubric/` as a second Grep target.
- E-10 `docs/definition-of-done.md` — self-review: E-6 over `git diff --name-only <base>...HEAD` ∪ `git status --porcelain` (committed, uncommitted and untracked).
- E-11 `docs/test-review-checklist.md` — `:3`, `:131` point at rule 6 in `review-rubric/rubric-tests.md`.
- E-12 `docs/agent-rules.md` — `:171` size claim and second Grep target.
- E-13 `plans/code-reviewer-split/ledger.md` — new: rule → file → bytes before / after.
- E-14 `skills/session-reflect/SKILL.md` — `:168`'s overlap check for the `review-rule` bucket (`:51`) Greps `docs/review-rubric/` as well as `code-reviewer.md`.
- E-15 `docs/review-bot-claim-audit.md` — `:29` "`code-reviewer.md` rule 6" pointer gains the module path (`verify-review/SKILL.md:60`'s twin is part of E-8).
- E-16 `docs/ci-tests.md` — `:48` rule 16 pointer gains the module path.

## P7 Impact map (M/L)

- Dispatchers `skills/review-pr/SKILL.md:286-320`, `skills/verify-review/SKILL.md:104`, `docs/definition-of-done.md:20` (scout + critic dispatch search) — covered by E-7, E-8, E-10
- Briefing contract `docs/review-orchestration.md:55-83` — covered by E-9
- References naming `code-reviewer.md` + a moved rule (`docs/test-review-checklist.md:3,131`, `skills/verify-review/SKILL.md:60` and `docs/review-bot-claim-audit.md:29-34` (rule 6), `docs/ci-tests.md:48` (rule 16); critic pattern `rules? \d+ … code-reviewer`; round-2 critic re-swept `\b[Rr]ules? (6|10|14|15|16|17|20|22|23)\b` — same set) — covered by E-8, E-11, E-15, E-16
- Main-agent Grep pointers into the rubric (`agent-rules.md:171`, `review-orchestration.md:10`, `review-bot-claim-audit.md:32`, `verify-review/SKILL.md:60`) — covered by E-12, E-9 (second Grep target)
- In-file cross-references crossing the boundary `:179` (→6), `:315` (23→19) — covered by E-1 (index)
- Links inside moved rules (U-5) — covered by E-2…E-5 (re-rooted)
- Output-schema consumers — Localized — searched the field names; schema unchanged
- Rule-authoring destinations (`session-reflect/SKILL.md:51,138`, `review-gap-attributor.md:66`, `work-plan/SKILL.md:249`) — deferred: new rules land in core (P3)
- Readers that dedupe against the rubric (`session-reflect/SKILL.md:168`; critic round 2 — `audit-agents` and `review-gap-attributor` do not read the rubric) — covered by E-14

## P8 Test obligations (M/L)

- TO-1 Size ≤ 186,000 B (red at `2998d44`, ≈212 k). — proof: red→green
- TO-2 Conservation script: rules 1-25 at `2998d44` vs HEAD, each exactly once, text equal after SC-2's href re-rooting only. Mutation: drop a sentence from a moved rule in a scratch copy → fails. Its per-rule byte output is E-13's ledger. — proof: control
- TO-3 Selection fixtures: one per D-2 **glob**, generated from the table (so a typo in any glob fails), plus the bare `.claude` gitlink path, `Build/Azure/pipelines/templates/build-job.yml` (rules 16 / 20), `Build/licenses/components.json` (15), `Directory.Packages.props` (17), `DataProviders.json` (6) and a `Source/LinqToDB.Scaffold/**` file (23); and these named cases: `Source/LinqToDB/Internal/Linq/Builder/ExpressionBuildVisitor.cs` → {tests}; `Source/LinqToDB/LinqToDB.csproj` → {ci-infra, packaging}; `Tests/Linq/Tests.csproj` → {tests, ci-infra} (not packaging); `Tests/Linq/x.webp` → {tests, ci-infra}; `Data/odd.bin` → {ci-infra}; `Source/LinqToDB/PublicAPI/net10.0/PublicAPI.Unshipped.txt` → {}; `Source/LinqToDB.CLI/server.json` → {packaging, tooling}; `UserDataProviders.json.template` → {tests}; `Redist/SapHana/x.dll` → {packaging, ci-infra}; `.claude/settings.json` → {ci-infra}; `README.md` → {}; genuine fallbacks `Examples/Remote/Foo.cs` and `Data/Setup Scripts/x.sql` → all; and a committed-only branch fixture for E-10's file list (non-empty). Mutation: remove `*.csproj` from the ci-infra row → the csproj fixtures fail. — proof: control
- TO-4 Dispatch wording in E-7, E-8, E-10 and the core's `rubricModules` instruction, read against SC-4 by a different model than the author. — proof: characterization
- TO-5 Index / focus script: every rule in one focus and one index row whose file holds it; for every TO-3 fixture and every moved rule r of focus f, `byFocus[f]` ∋ module(r) when selected. Mutation: drop rubric-tests from `byFocus["code-correctness"]` → rule 10 fails. — proof: control
- TO-6 Checkers on the staged tree: anchors 0, commands 0, links `broken[]` set-equal to the plan-time 142 (snapshot taken before the first edit); plus a Grep that each pointer edited by E-9, E-11, E-12, E-14, E-15, E-16 names `review-rubric/`. — proof: control
- TO-7 **Measures file-read compliance through the module path (U-1), not rule quality** — rule 22's text is unchanged by the move; what is new is that it reaches the agent only via a `Read`. Replay PR [#5882](https://github.com/linq2db/linq2db/pull/5882)'s diff (the incident in rule 22's own text: four methods carved out of gated tests on stated premises; rule 22's mechanism has no corpus twin — grep `narrowed gate|asserted provider behaviour|hypothesis in a comment`: only `:142` and `:311`), briefed **without** its review threads, plan or DoD, twice: with `rubricModules` from E-6, and in a scratch checkout with `docs/review-rubric/` **physically removed** (a `[]` control cannot withhold a file the index names and the agent may `Read`). Pre-registered predicate: run 1 passes when some finding's `why` contains the literal `rule 22` or `hypothesis in a comment`; the control passes when no finding contains either literal **and** `out_of_scope_observations[]` names `rubric-tests.md` as unreadable (D-4). Any other control output (a `blocked`-style abort, a silent review) fails it. — proof: control

## P9 Verification gates

- G-01: — (pending) — TO-1…TO-7
- G-06: — (pending) — diff limited to E-1…E-16
- G-09: — (pending) — critic; user diff review; TO-4's independent read

## P10 Adjudicated (M/L)

- Saving ≈ −13 % on the file, ≈ −4 % on an ordinary Source PR (rule 6 loads); accepted as the narrow variant's honest return (user choice, 2026-10-13).
- A CI / packaging concern written only in code is caught by core rules (rule 3's config-knob clause) rather than the ci-infra module (D-2 failure mode).
- One replayed PR is the only behavioural evidence; no eval harness exists.
- `/verify-review` computes modules from the current file list; a prior finding whose trigger file left the diff loses its moved rule's text. Accepted: a `fixed` / `still_actual` verdict needs the finding and the code, not the rule body.
- In multi-pass, Pass A loads `rubric-tests` for rule 10 on any Source PR (rule 10 fires only on `Tests/Tests.Playground/**`): Pass A / C save ≈ 3.6 %, Pass B ≈ 12.7 % (critic round 3). Accepted; splitting rule 10 into its own module is a later option.

## P11 Amendments (M/L)

_None._

## P12 Critic verdict (M/L)

Prior history (broad variant, same key, not committed): round 1 refuted (hand-listed per-pass sets, empty-list semantics, SC-2 vs retargeting, KB name collisions, missing path table, TO-7 discrimination, reference undercount); round 2 refuted (`*.csproj` missing from ci-infra, committed-branch `[]`, rule 14's `../AGENTS.md` link, rule 21 content-triggered, TO-7 leakage via briefing, PublicAPI files in packaging, Grep pointers, `.tt` for rule 6, growth claim). This plan narrows the scope and folds those fixes in.

**Narrow variant, round 1 — refuted** (plan-critic on `fable`, 2026-10-13). Confirmed sound: D-1, D-3, D-4, the reference map. Objections and responses:
1. TO-3 fixtures inconsistent (`Data/odd.bin` both ci-infra and `all`) → binaries are now an explicit extension list; `odd.bin` → ci-infra; genuine fallback fixtures added (`Examples/Remote/Foo.cs`, `*.sql`).
2. SC-3 unmet for rule 6 (`DataProviders.json` / `.template`), rule 15 (`Redist/`), rule 14 (`.claude/` hooks / settings) → rows and fixtures added.
3. "Not in allowlist = binary" sent ~240 text files (`.cmd`, `.sql`, `.razor`, `.xaml`, …) to ci-infra; `*.csproj → packaging` and `**/*.tt → tooling` over-matched → explicit binary list, `Source/**`-only csproj, shipped-generator tooling, script / solution / config files routed explicitly.
4. SC-1 margin unbudgeted (HEAD is 212,478 B; moved blocks 30,236 B) → budget stated in SC-1.
5. TO-7 could not discriminate (`[]` withholds nothing the agent can `Read`; phrase chosen post hoc; rules 14 / 16 / 20 have corpus twins) → rule 22, module directory physically removed for the control, phrase pre-registered.
6. Verify-mode prior findings and rule 10's Pass-A cost → recorded in P10.

**Narrow variant, round 2 — weak** (plan-critic on `fable`, 2026-10-13). Reproduced: SC-1 arithmetic (moved blocks 30,236 B: r6 14,664 · r10 1,093 · r14 2,588 · r15 2,481 · r16 1,461 · r17 1,546 · r20 1,481 · r22 3,532 · r23 1,390; headroom 258 B), SC-6 baselines (links 142, anchors 0, commands 0), U-2's two boundary crossings, the focus lists partitioning 1-25, and every D-2 trigger path existing in the tree. Searched: dispatchers, numeric and by-title references to moved rules, `audit-agents` / `review-gap-attributor` (neither reads the rubric), corpus hooks / CI (none gate the file). Objections, folded in:
1. `session-reflect` dedupes `review-rule` proposals by Grepping `code-reviewer.md` (`:168`) → would miss moved rules → E-14; the four "`code-reviewer.md` rule N" pointers get the module path → E-8, E-11, E-15, E-16.
2. TO-3 fixtured rows, not globs → one fixture per glob, plus the bare `.claude` gitlink and the named trigger files.
3. TO-7: PR unnamed, "quote or paraphrase" a judgement, control's expected output unspecified → #5882 named, literal predicate, D-4 defines the unreadable-module behaviour the control asserts; TO-7 stated as measuring file-read compliance.
4. SC-6 a count, not a set → set equality against the plan-time snapshot.
5. Focus labels absent from modules → module header lists `(rule, focus)`; index replaces `:140-142` rather than adding (D-3).

Not re-critiqued after folding; the changes add edit-points and tighten obligations without moving D-1…D-4's choices.
