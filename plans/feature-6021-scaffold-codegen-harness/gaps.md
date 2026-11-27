# Gap ledger — feature-6021-scaffold-codegen-harness

## Round 1 — reviewed HEAD 6c14afb9c

Plan: Tier L, approved 2026-10-12, amendments A-1..A-7. Commit `6ae24c49c` (2026-10-22, #5707 pin removal) has no amendment. No finding is GAP-09: every file is inside an `E-n`, and `-Reconcile` is per file. `work-plan.ps1 -Action validate -Summary` on the plan as it stood returned 3 errors (G-01 has no sweep counts on the implemented tree; A-7 has no P12 round; A-7 adds test edit-points without a `conventions:` line). The checks existed and fired; they were not run or not acted on before `ce0c76311` was pushed. G-09 was `(pending)`.

- **MIN001** (ModelSmoke Find checked against row 0) — GAP-05 — TO-8a..l say only "invoked, returns the inserted row"; D-6 names no input separating a key lookup from an unfiltered `FirstOrDefault`; TO-8 labelled `characterization` and G-01 waives it ("Not mutation-proven individually: TO-4/5/6/7/8/9/10/11") — G-01 — preventable: yes
- **MIN002** (ProcedureSchemaErrorGenerated F# arm asserts no generated method) — GAP-05 — `6ae24c49c` removed the A-2 pin and wrote a new F# assertion with no `A-n`, so the P11 re-derive corollary never ran; A-2/G-01/TO-10c still described the pinned state — G-01 — preventable: yes
- **MIN003** (PostgreSqlTupleFunction passes the same column twice) — GAP-05 — TO-13g borrowed its expectation from `PostgreSQLTests`; `SqlShape.SelectCall` accepted only column names; work-plan.md's distinct-value-vector rule landed 2026-11-26, after the plan — G-01 — preventable: partly
- **MIN004** (CrossSchemaForeignKey lacks the `s2` SQL assertion) — GAP-08 — TO-7f required the `[s2].` SQL and named the `IncludeDatabaseName = false` mutation; the implementation dropped the clause and G-01 never ran the mutation — G-01 — preventable: yes
- **MIN005** (C# compiled at Roslyn default warningLevel 4) — GAP-02 — D-7 assumed parity with consumer warnings-as-errors builds; P4 probed only FCS flags, never `CSharpCompilationOptions` defaults vs SDK `AnalysisLevel` — — — preventable: partly
- **MIN006** (`[ActiveIssue]` pins match uncontrolled text) — GAP-07 — A-1/A-2 recorded pins with no discriminating fragment; testing.md *Gating an assertion failure* predated A-1 but step 4 embeds only *Test layout*, and A-1's own attribute made the Tests.Base text read as not applying; `f9c02c271` swapped in another fragment both assertions match — G-01 — preventable: partly
- **MIN007** (PreprocessAssociation lacks TO-12n's cardinality half) — GAP-08 — TO-12n named both halves under `proof: control`; G-01 has no TO-12n row; `validate -Done` belongs to G-09, still pending — G-01 — preventable: yes
- **MIN008** (10 narrowed `IncludeDataSources` without reasons; 2016Plus floor) — GAP-02 — U-13 wrote `AllSqlServer2016Plus` as scouted capability with no reason, never checking that pre-2016 legs run .NET Core on the one SqlServer.sql; testing.md *A narrowed provider set is a claim* never reached a `conventions:` line — G-01 — preventable: yes
- **MIN009** (ViewNamedTable_Issue4831) — GAP-07 — TO-17 dictated the name four days before the naming rule (522a396); A-7 owed the amend-mode embed; the rule says "prefixed" and sweep check 11 matches only `^Issue\d+`, so the `_Issue4831` suffix escapes both — G-01 — preventable: partly
- **MIN010** (scaffold-harness/<guid> never deleted) — GAP-01 — no plan block names the lifecycle of per-compile output; no corpus rule covers test-helper temp directories — — — preventable: partly
- **SUG001** (harness ActiveIssue Passed/other-failure arms untested) — GAP-05 — A-1 states a three-outcome policy; its `re-derives:` TO-1e covers one outcome plus scoping; A-1 got no P12 round — G-01 — preventable: yes
- **SUG002** (AfterSourceCodeGenerated reads live models, conflict-free schema) — GAP-05 — TO-12o's discriminating input targets loader-time normalization; the hook's distinguishing point is codegen-time conflict resolution — G-01 — preventable: partly
- **SUG003** (outputPath dead on the F# path) — GAP-05 — added by symmetry with D-9's C# `.dll` case; A-7 wrote a contract for it with no TO-n covering "loaded" or "written"; G-09 for A-7 never ran — G-09 — preventable: partly
- **SUG004** (Tests.LinqToDB.CLI.csproj lacks SatelliteResourceLanguages=en) — GAP-03 — D-4 lists three harness consumers; E-2/E-4/E-9 carry the property, E-11 does not; no P7 row for every project receiving FCS through the harness — — — preventable: yes
- **NIT001** (148 one-line + 11 nested chains) — GAP-07 — no `conventions:` line in the plan; the *Test layout* embed landed the day of approval; A-7 had no amend-mode embed or sweep; G-01 records no sweep counts — G-01 — preventable: yes
- **OOS1** (C# compiled only at LanguageVersion.Latest) — GAP-01 — SC-1/D-7 never name the C# language version generated code must compile under; A-7 added the F# floor/latest axis without a P7 row for `CSharpCompiler` — — — preventable: partly
- **OOS2** (`[ActiveIssue(6036)]` reddens when #6036 flows in) — GAP-03 — A-1 (pass → Failure) and A-2 (#6036 on its own branch) each hold half the fact; no P7 row names the merge-forward that reddens the pin — — — preventable: yes

### Aggregate

GAP-05 ×6, GAP-07 ×3, GAP-08 ×2, GAP-02 ×2, GAP-01 ×2, GAP-03 ×2. No GAP-10.

Dominant cluster GAP-05 + GAP-08, 8 of 17: tests that cannot go red for their stated purpose (MIN001–MIN004, MIN007, SUG001–SUG003). P3's "no product-code change" led to nearly every TO-n being labelled `characterization`; G-01 then waived mutation proof for TO-4..TO-11 in one line, and the validator never checks a characterization row. On a coverage-harness plan the label exempted the property the plan exists for.

Second cluster (MIN006, MIN009, NIT001, part of MIN008): the amend-mode embed and sweep. Validate reported the errors; nothing ran validate at push time.

### Recommended durable fixes (proposed, not applied)

1. `docs/work-plan.md` P8: on a plan whose product is test coverage, `characterization` does not exempt a TO-n from a recorded mutation; a blanket "not mutation-proven" G-01 line is `fail`. `work-plan.ps1` `$mutationRx` to accept the `mutation: \`…\`` colon form.
2. `docs/definition-of-done.md` + `work-plan.ps1 -Action reconcile`: emit validate's P11/P9 errors (missing `conventions:` line, missing P12 round, no sweep counts) before push. Widen sweep check 11 and testing.md's "prefixed" rule to an `_Issue\d+` suffix.
3. `agents/plan-critic.md`: an in-process compiler standing in for a consumer toolchain lists every default it replicates (warning level/AnalysisLevel waves, LangVersion floor per consumer TFM, nullable context), each with a parity probe and floor/latest arm per language.

## Round 2 — reviewed HEAD 8ccce36d3

Plan: Tier L. This round's fixes were recorded as A-11 (`319cbb324..d65c4c9c0`); G-01 round 3 and G-09 round 2 were recorded 2026-11-27. No finding is GAP-09: every touched file is inside E-3/E-4. No finding contests a P10 entry, and no deferral was a P10 row; the harness exclusion lived only in A-10's prose. Round-1 durable fixes 1–3 landed in corpus `e40f898` (2026-11-26 23:28), after A-10 and G-01 round 2 were committed (`713cdc3`, 19:41), so the new rules did not exist when A-10 was written and nothing re-applied them to this plan until the review.

### Attribution

- **SUG001** (TO-9d asserted only that an `S2*` type exists) — GAP-05 — P8 TO-9d named no discriminating input or mutation, so a module without the entity satisfied it; G-01 round 1's blanket "Not mutation-proven individually: TO-4/5/6/7/8/9/10/11" waived it; A-10 re-derived only the rows round 1 named. Second class: the row's "executes" half was never implemented (GAP-08) — G-01 — preventable: yes
- **NIT001** (22 trailing-whitespace lines from A-10's chain split) — GAP-07 — A-10 rewrote 149 sites with `tools/chain-split`, which keeps the receiver's alignment padding before the split dot; no formatting gate was re-derived (G-06 last recorded 2026-10-13); the trailing-whitespace rule exists only reviewer-side (`review-conventions.md:131`) — G-06 — preventable: yes
- **OOS1** (24 one-line + 10 nested chains left in `Tests/Tests.Scaffold.Harness/*`) — GAP-06 — A-10 excluded the harness "as test infrastructure" in prose, against `definition-of-done.md:11`, with no P10 entry or user sign-off; second class: G-01 round 2 recorded `pass` while naming the remaining hits (GAP-08) — G-01 — preventable: yes
- **OOS2** (#4831 / #6486 pins matched a bare id inside the full compile report) — GAP-06 — A-10 fixed MIN006 only for #6036 / #3749 and wrote the #6486 pins as `"CS8981"` in the same amendment; testing.md:109 states the aggregated-message trap only for NUnit's `EnterMultipleScope` — G-01 — preventable: yes
- **BK1** (G-01 round 1 recorded "38 cases" for TO-15; true count 37) — GAP-08 — TO-15 asked for an executed-count equality against a filtered pre-move run; G-01 round 1 recorded rename similarity and a listed count with no run behind it — G-01 — preventable: yes
- **BK2** (TO-7f / TO-9a mutations named in P8 unrecorded until 2026-11-27) — GAP-08 — both rows name `IncludeDatabaseName = false`; G-01 round 1 waived them; A-10 claimed TO-7f's red with no date or head; the validator check is a warning without `-Done` and reconcile forwards only errors; recurs from round-1 MIN004 — G-01 — preventable: yes

### Continuity

- Round-1 MIN006 → round-2 OOS2: A-10 fixed the two named pins and wrote two new bare-id pins in the same bullet; round 1 proposed no durable fix for MIN006.
- Round-1 NIT001 → round-2 OOS1, plus NIT001 introduced by the fix itself; round-1 fix 2 (reconcile carries validate's P9/P11 errors) could not catch OOS1 because the sweep counts were recorded with a waiver attached.
- Round-1 MIN001/MIN004 (GAP-05/GAP-08) → round-2 SUG001 and BK2: round-1 fix 1 landed (`work-plan.md:164`, colon-form `$mutationRx` at `work-plan.ps1:503`), but the blanket-waiver-is-`fail` rule has no validator check and the unrecorded-mutation check stays a warning at reconcile.
- Round-1 fix 3 (compiler-parity vector) is in `plan-critic.md` and did not recur.

### Aggregate

GAP-08 ×2, GAP-06 ×2, GAP-05 ×1, GAP-07 ×1; no GAP-09 / GAP-10. Five of six (SUG001, OOS1, OOS2, BK2, NIT001's introduction) trace to A-10 fixing round 1's named instances rather than each finding's class across the branch — the two named pins, not every `ErrorMessage =`; the named TO-n rows, not the whole waived TO-4…TO-11 range; the 14 fixture files, not every file the sweep scans — and producing new instances while doing it. The single change that would have prevented the most: an amendment that fixes a review finding records the search that enumerates the finding's class across the branch, with its hit count, and fixes or P10-adjudicates every hit.

### Recommended durable fixes

1. GAP-05/06/08 ×4 (SUG001, OOS1, OOS2, BK2) → `skills/work-plan/SKILL.md` *Mode: amend* and P11 semantics in `docs/work-plan.md`: a review-fix `A-n` carries a `class:` line per finding with the class search and its count; a scope exclusion ("infrastructure, not tests") is valid only as a P10 entry, never as amendment prose.
2. GAP-08 ×2 (BK2, SUG001) → `scripts/work-plan.ps1` validate, on a plan whose P3 has no product-code change: "G-01 records no run of TO-n's mutation" becomes an error; a G-01 line matching `not mutation-proven` is an error; a `characterization` P8 row naming no mutation is an error.
3. GAP-07 ×1 (NIT001; recurs from issue-5951 NIT005) → `tools/chain-split/Program.cs:76-77`: consume the whitespace run before each dot; plus an author-side `docs/definition-of-done.md` item: no trailing whitespace on added lines (`git diff --check <base>`) after any mechanical rewrite.

### Corpus trace

- SUG001 · rule: `docs/work-plan.md:164` · why it did not fire: landed in `e40f898` four hours after A-10; no validator check, so the open plan was never re-tested against it · correction: *Mode: amend* — when a corpus rule lands from a plan's own ledger, re-validate that plan and re-derive every row in a waived range; plus fix 2 · recurs: round-1 MIN001, MIN004
- NIT001 · rule: `docs/review-conventions.md:131`, reviewer-side only · why it did not fire: no author-side DoD item; `chain-split` keeps alignment spaces before the dot · correction: `tools/chain-split/Program.cs`, `docs/definition-of-done.md` `git diff --check` item · recurs: `plans/issue-5951-enforce-source-mapping-schema/gaps.md` NIT005
- OOS1 · rule: `docs/testing.md:657` (*Test layout* rule 1), `docs/definition-of-done.md:11` · why it did not fire: testing.md:655 scopes the rules to "new test code" with fixture examples, so a helper library under `Tests/` read as not test code; DoD:11 names plan-scope waivers, not category waivers · correction: testing.md:655 — every file the sweep scans under `Tests/` is test code, harness libraries included; DoD:11 — a category exclusion is a P10 entry with user sign-off · recurs: round-1 NIT001; #5673
- OOS2 · rule: `docs/testing.md:109` (aggregated-message `ErrorMessage` trap) · why it did not fire: worded for NUnit's "Multiple failures" text only; the harness `ActiveIssueAttribute` doc comment endorses fragment matching · correction: generalise testing.md *Gating an assertion failure* to any aggregated failure message (compiler diagnostics, validation lists): pin the whole failure set or a header that encodes it · recurs: round-1 MIN006
- BK1 · rule: `docs/testing.md:129` and the TO-15 row · why it did not fire: G-01 substituted a reading for the specified run; nothing checks that a count-equality TO-n cites two artifacts · correction: `docs/work-plan.md` P9 — a count-equality G-01 row cites both runs by artifact path · recurs: —
- BK2 · rule: `scripts/work-plan.ps1:500-521` · why it did not fire: matched TO-7f/TO-9a only after `e40f898`'s colon-form regex; a warning without `-Done`; reconcile forwards only `^P(9|11) :` errors · correction: make it an error on coverage plans (fix 2) · recurs: round-1 MIN004
