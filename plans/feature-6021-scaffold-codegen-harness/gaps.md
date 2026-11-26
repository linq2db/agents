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
