# Work plan: issue-6055-remote-binary-dbdatatype — Remote context keeps DbDataType of binary/unary expressions

**Tier:** M  ·  **Status:** approved  ·  **Approved-at:** 2026-10-15 (after critic round 2, verdict weak)  ·  **Branch:** issue/6055-remote-binary-dbdatatype
**Schema:** `.claude/docs/work-plan.md`  ·  **Gates:** `.claude/docs/definition-of-done.md`

## P1 Problem

[#6055](https://github.com/linq2db/linq2db/issues/6055): `LinqServiceSerializer` writes `SqlBinaryExpression` / `SqlUnaryExpression` with their CLR `SystemType` only (`Source/LinqToDB/Internal/Remote/LinqServiceSerializer.cs:1038`, `:1051`) and reads them back through the `Type` constructors (`:2239-2245`, `:2252-2257`), so `DataType` / `DbType` / `Length` / `Precision` / `Scale` are lost on the LinqService path. On the server, `QueryHelper.GetDbDataType` (`Internal/SqlQuery/QueryHelper.cs:708`, schema fill-in at `:668-684`) then answers the mapping-schema default for the CLR type, and `SqlExpressionOptimizerVisitor.VisitSqlCastExpression` (`Internal/SqlProvider/SqlExpressionOptimizerVisitor.cs:1354-1357`) drops a non-mandatory cast the client kept.

Measured on unfixed `origin/master` 0d4aa1f1e (log `.build/.agents/probe-unfixed.log`): a `Decimal(10,2)`-typed `a + b` wrapped in a non-mandatory cast to the schema-default decimal renders `CAST([r].[A] + [r].[B] AS Decimal(18, 10))` on SqlServer.2022 direct but `[r].[A] + [r].[B]` on SqlServer.2022.LinqService; same split on SQLite.Classic, SQLite.MS, DuckDB, PostgreSQL.16 (`::decimal` direct, nothing remote) and YDB (`Unwrap(CAST(r.A + r.B AS Decimal(22,9)))` direct, no cast remote). On YDB the dropped narrowing cast makes YQL reject the query (#5943 `Round28`: "Implicit decimal cast would narrow the range").

## P2 Success criteria

- SC-1 A typed binary under a non-mandatory narrowing cast keeps the cast on every `.LinqService` context, as it does on the direct context → TO-1
- SC-3 A redundant cast over a typed binary is still folded on both paths (no new casts introduced remotely) → TO-3
- SC-4 No existing test regresses on the direct or remote path, and remote SQL does not newly diverge from direct SQL (baselines comparison) → TO-4
- SC-5 The #5169 YDB baseline gates are removed where this fix makes remote SQL equal to direct SQL, and kept otherwise → TO-5

## P3 Constraints & anti-goals

- No public API change: `LinqServiceSerializer` is `internal`; `SqlBinaryExpression` / `SqlUnaryExpression` constructors are unchanged.
- No direct-path SQL change: the edit is confined to the remote wire format, which the direct path never touches.
- Wire compatibility with older clients/servers is NOT a constraint (user decision 2026-10-15: client and server always run the same linq2db version; prior wire changes such as the `NeedsCast` removal shipped the same way).
- Not in scope: `QueryElementVisitor` Transform-mode rebuilds that use `element.SystemType` (`Internal/SqlQuery/Visitors/QueryElementVisitor.cs:3060-3065`, `:3099-3103`), the optimizer folds that rebuild with `element.SystemType` (`SqlExpressionOptimizerVisitor.cs:1122,1139,1185,1202,1234`), and the missing `SqlUnaryExpression` arm in `QueryHelper.GetDbDataTypeImpl` — see D-2, D-3.

## P4 Unknowns

- U-1 Does `Append(DbDataType)` need the node's `SystemType` pre-registered by the type pre-pass (`LinqServiceSerializer.cs:884-885`)? — resolved-by scout: `Append(DbDataType)` (`:164-172`) writes `SystemType` via `Append(Type)` → `GetType` (`:144-149`), the same path `SqlFunction` / `SqlField` / `SqlValue` already use; `ReadType` (`:461-488`) also accepts inline type definitions. The pre-registration lines stay unchanged.
- U-2 Is the client-side `PrepareStatementForRemoting` Transform-mode rebuild (`SqlOptimizerExtensions.cs:20-21` → `QueryElementVisitor.cs:3060`) a second remote-only loss point that the serializer fix alone does not cover? — resolved-by probe (round 2, after the critic showed the first probe's `B + 0` is reduced at build time in Modify mode, `SelectQueryOptimizerVisitor.cs:43,223`, and never reaches `:3060`): a `Decimal(10,2)` sum `A + COALESCE(C, 0)` under the narrowing cast — a child the convert visitor replaces with a function (`SqlExpressionConvertVisitor.cs:1747-1750`) — renders WITHOUT the cast on the direct path too (`[r].[A] + Coalesce([r].[C], 0)` on SqlServer.2022 direct and remote; same on SQLite.Classic, SQLite.MS, PostgreSQL.16, DuckDB; `.build/.agents/probe-coalesce-serializer-only.log`). The rebuild loses the type on both paths, so it is an engine-wide defect, not a remote/direct divergence — out of #6055 (D-2), proposed as its own issue.
- U-3 Can a test reach the serializer directly? — resolved-by scout: no; `LinqServiceSerializer` is `internal` and the repo bans `InternalsVisibleTo` (`.claude/docs/code-design.md:96-98`). Tests go through a `.LinqService` context with a public `Sql.Extension` builder emitting the AST (precedent `Tests/Linq/UserTests/Issue5769Tests.cs:86`).
- U-4 Does `GetCurrentBaselines()` capture the server-side SQL of a `.LinqService` case without `BaselinesPath`? — resolved-by probe: yes; the unfixed run's remote failure messages quote the server SQL (`probe-unfixed.log`), and `BaselinesManager.LogQuery` (`Tests/Base/BaselinesManager.cs:15-33`) does not consult `BaselinesPath`.
- U-5 Is the `SqlUnaryExpression` half observable through SQL? — resolved-by scout: not through cast folding — `GetDbDataTypeImpl` has no unary arm (`QueryHelper.cs:735` falls to `{ SystemType: var t }`), so only copy-through sites read `.Type` (`SqlExpressionConvertVisitor.cs:2283-2306`, `YdbSqlExpressionConvertVisitor.cs:186`, `ClickHouseSqlExpressionConvertVisitor.cs:176-177`), and those normally run on the client before serialization. Kept in the edit for symmetry; no discriminating test (see P8).
- U-6 Are the #5169 YDB baseline gates (`Tests/Linq/Linq/StringJoinTests.cs:451`, `Tests/Linq/Linq/StringFunctionTests.cs:928`) caused by this bug? — resolved-by scout: unlikely for `StringJoinTests` (its `CAST(Unicode::GetLength AS Int32)` is mandatory, `YdbMemberTranslator.cs:62`); plausible for `StringFunctionTests.LastIndexOf2` (index arithmetic). Decided by TO-5 measurement; un-gate only on a measured match (E-4/E-5 conditional).

## P5 Decisions

### D-1 — Serialize the full `DbDataType` in place of `SystemType`

- **chosen:** write `Append(elem.Type)` (the existing `Append(DbDataType)` helper) where `Append(elem.SystemType)` stood, and read with `ReadDbDataType()` into the `DbDataType` constructors, for both nodes.
- **rejected:** append the `DbDataType` after the existing `SystemType` field — redundant (the `DbDataType` carries `SystemType`), and wire compatibility is not a constraint (P3).
- **rejected:** re-infer the type on the server from the operands — the client's type is authoritative (it was set by the translator that built the node); re-inference is what produces the wrong answer today.
- **why this:** mirrors how `SqlFunction`, `SqlExpression`, `SqlValue`, `SqlCastExpression` already serialize their type (`LinqServiceSerializer.cs:958`, `:1001`, `:1059`, `:1775`).
- **failure mode of the choice:** the type now comes from the client's mapping schema rather than being filled in from the server's; a client and server configured with different mapping schemas for the same CLR type now get the client's choice. On the direct path client and server are one schema, so this only moves remote toward direct.

### D-2 — Leave the `QueryElementVisitor` Transform rebuild alone

- **chosen:** no change to `QueryElementVisitor.cs:3060-3065` / `:3099-3103` on this branch; the measured both-paths loss (U-2: narrowing cast dropped on direct AND remote when a child of the typed binary is converted) goes to its own issue, branch and PR.
- **rejected:** rebuild with `element.Type` in the same PR — it is a separable shared-engine fix with a standalone observable effect on the direct path (AGENTS.md → *Creating a new branch*), in `SqlQuery/` (Tier L surface), and #6055's remote divergence is fully closed without it (TO-1 green on all 6 remote contexts with E-1/E-2 only).
- **why this:** keeps #6055 to the remote contract; the engine fix gets its own red test (the `COALESCE` shape) and its own baselines review.
- **failure mode of the choice:** until the engine fix lands, a typed binary whose child is converted loses its type on both paths — unchanged behaviour, now tracked.

### D-3 — Leave the missing unary arm in `GetDbDataTypeImpl` alone

- **chosen:** no change to `QueryHelper.cs:699-736`.
- **rejected:** add `SqlUnaryExpression { Type: var t } => t` — changes type inference on both paths, a behaviour change unrelated to the remote defect.
- **why this:** out of #6055's scope; the serializer edit already makes the unary node round-trip faithfully.
- **failure mode of the choice:** unary typing stays CLR-only in inference on both paths (unchanged behaviour).

## P6 Edit-points

- E-1 `Source/LinqToDB/Internal/Remote/LinqServiceSerializer.cs:QuerySerializer (SqlBinaryExpression / SqlUnaryExpression write)` — `Append(elem.SystemType)` → `Append(elem.Type)`
- E-2 `Source/LinqToDB/Internal/Remote/LinqServiceSerializer.cs:QueryDeserializer (SqlBinaryExpression / SqlUnaryExpression read)` — `ReadType()` → `ReadDbDataType()`, `DbDataType` constructors
- E-3 `Tests/Linq/UserTests/Issue6055Tests.cs` — new regression fixture (TO-1, TO-3)
- E-4 `Tests/Linq/Linq/StringFunctionTests.cs:LastIndexOf2` — remove the #5169 YDB `DisableBaseline` scope ONLY if TO-5 measures direct == remote with the fix
- E-5 `Tests/Linq/Linq/StringJoinTests.cs:JoinAggregateArrayNotNullAndFilter` — same condition as E-4

## P7 Impact map

- `Source/LinqToDB/Internal/Remote/LinqServiceSerializer.cs:1034-1057` (writer) and `:2237-2260` (reader) — the only place either node is serialized; searched `SqlBinaryExpression|SqlUnaryExpression` in `Internal/Remote` — covered by E-1, E-2
- `LinqServiceSerializer.cs:884-885` type pre-registration — still registers `SystemType`, which `Append(DbDataType)` writes first (U-1) — out-of-scope
- Server-side readers of the node type (scout: `QueryHelper.GetDbDataType` arms `QueryHelper.cs:708,762,770,780`; `SqlExpressionOptimizerVisitor.cs:180,1070,1086-1089,1122-1256,1354-1363`; `SqlExpressionConvertVisitor.cs:2253-2306,2490-2506` and provider `ConvertConversion` sites; `BasicSqlBuilder.cs:3087`, `YdbSqlBuilder.cs:458`, `DB2SqlBuilderBase.cs:46`) — each now receives the client's type instead of the schema default, i.e. what the direct path already receives — covered by E-1
- Client-only readers (`DuckDBSqlOptimizer.cs:120` in `FinalizeStatement`, `Finalize`/`SelectQueryOptimizerVisitor`, `WrapParametersVisitor`) — run before serialization, unaffected — out-of-scope
- Producers of richer-than-CLR binary/unary types (scout: `SqlExpressionFactoryExtensions.cs:134-292` used by member translators; `ExpressionBuildVisitor.cs:2430,2434` unary `MappingSchema.GetDbDataType`; `SelectBuilder.cs:104`; `Sql.DateTime.cs:536,541`; provider ConvertVisitors) — their remote SQL may now change toward direct; plain LINQ arithmetic (`ExpressionBuildVisitor.cs:3470-3491`, CLR-only) is unaffected — covered by E-1, verified by TO-4
- Transform-mode rebuilds dropping the type (`QueryElementVisitor.cs:3060-3065,3099-3103`; `SqlExpressionOptimizerVisitor.cs:1122,1139,1185,1202,1234`; `YdbSqlExpressionConvertVisitor.cs:212,223,247,250`) — deferred: D-2, measured to lose the type on direct and remote alike (U-2), separate issue
- Tests gated for direct/remote SQL divergence: `git grep -n "5169\|Baselines for remote" -- Tests` → `StringJoinTests.cs:451`, `StringFunctionTests.cs:928` (YDB, possibly this bug), `MergeTests.Types.cs:654` and `QueryGenerationTests.cs:140` (parameter naming/dedup, not this bug), `IssueTests.cs:1216` (#5973, literal typing, not this bug) — covered by E-4, E-5 (conditional); the other three out-of-scope
- `git grep -n "ActiveIssue(6055" -- Tests` — no hits — Localized — searched ActiveIssue(6055 across Tests/, no gates to remove
- YDB translator comments claiming "IsMandatory is lost across the remote LinqService" (`YdbMemberTranslator.cs:555-557`, `:642-643`) — `IsMandatory` is serialized (`LinqServiceSerializer.cs:1781`), so these workarounds may have been compensating for this bug — deferred: removing them changes YDB SQL and needs its own measurement; noted for the #5943 session

## P8 Test obligations

- TO-1 `Issue6055Tests.NarrowingCastIsKept([DataSources(TestProvName.AllAccess)])`: typed `Decimal(10,2)` sum under a non-mandatory cast to the schema-default decimal; asserts the SQL matches `CAST|::|Decimal(|toDecimalNN(` (DB2 renders a precision-bearing decimal cast as `Decimal(x, 18, 10)`, `DB2SqlExpressionConvertVisitor.cs:174-175`; ClickHouse as `toDecimal128(x, 10)`, `ClickHouseSqlBuilder.cs:567-589` — both reasoned from code, not run locally). Access excluded: `AccessSqlExpressionConvertVisitor.ConvertConversion:491-508` removes a decimal cast on both paths, so there is no cast to lose (reasoned from code; CI's Access legs would fail the assertion without the exclusion). Discriminating input: the binary's `Decimal(10,2)` differs from the cast target only when the type survives; measured red on all 6 `.LinqService` contexts and green on all 6 direct contexts before the fix (`probe-unfixed.log`), all green after (`probe-serializer-only.log`); providers: all `[DataSources]` except Access, measured locally on SQLite.Classic, SQLite.MS, PostgreSQL.16, SqlServer.2022, YDB, DuckDB (direct + LinqService), the rest via CI — proof: red→green
- TO-3 `Issue6055Tests.RedundantCastIsFolded([DataSources])`: typed sum cast to its own `Decimal(10,2)`; asserts the captured SQL contains the `+` of the sum (anchor: an empty capture fails) and does not match the cast pattern. Green before and after (the client folds it before serialization) — symmetry guard that the fix does not introduce casts remotely; providers: all `[DataSources]` — proof: characterization
- TO-4 CI `/azp run test-all` with baselines: no new direct-vs-remote mismatch ("Baselines for remote context doesn't match direct access baselines") and no failures attributable to this change; providers: every CI test-all leg — proof: characterization
- TO-5 `StringFunctionTests.LastIndexOf2` and `StringJoinTests.JoinAggregateArrayNotNullAndFilter` on `YDB` + `YDB.LinqService` with the `DisableBaseline` scope removed and a scratch `BaselinesPath`: green (no mismatch) → apply E-4/E-5; red → leave the gate, record the remaining divergence under #5169. A measurement deciding E-4/E-5, not a proof of new behaviour; providers: YDB — proof: characterization
- Unexercised: the `SqlUnaryExpression` half of E-1/E-2 has no discriminating SQL-level test (U-5: no server-side reader decides on a unary's type for the cast path); covered only by TO-4's full remote suite running unary nodes through the new wire format.

## P9 Verification gates

- G-01: pass — TO-1 red→green observed: red on the 6 `.LinqService` contexts unfixed (`probe-unfixed.log`); with the fix and the final assertions green direct + remote on SQLite.Classic, SQLite.MS, DuckDB, PostgreSQL.16 (`probe-final-fixed.log`, `probe-final-fixed-2.log`), YDB (`probe-ydb-baselines.log`, 10/10, scratch baselines written, no `.sql.other`) and SqlServer.2022 (`probe-sqlserver-baselines.log`, 6/6, scratch baselines written, no `.sql.other`). TO-3 green on the same contexts. TO-5 measured: see P11 A-1.
- G-02: — (pending) CI baselines diff after `/azp run test-all`
- G-05: pass — `dotnet build Source/LinqToDB/LinqToDB.csproj -c Release -f netstandard2.0` and `-f net10.0`, `dotnet build Tests/Linq/Tests.csproj -c Release -f net10.0`: all three "Build succeeded" (`.build/.agents/release-*.log`)
- G-06: pass — `git diff --stat`: `LinqServiceSerializer.cs` (4 changed lines in the two node cases) + new `Issue6055Tests.cs`; nothing else touched
- G-07: pass — no `Tests/Tests.Playground/` changes
- G-09: pass — the critic (fable) read the applied serializer diff in both rounds (`git diff` of `LinqServiceSerializer.cs`, every `**/Remote/**` reference to the two nodes, `Tests/` for wire fixtures); no objection against the code

## P10 Adjudicated

- `StringJoinTests.JoinAggregateArrayNotNullAndFilter` (#5169 YDB gate) is expected to stay gated: its comment (`StringJoinTests.cs:446-448`) describes a *mandatory* cast dropped remote-only, and `VisitSqlCastExpression` never folds a mandatory cast (`SqlExpressionOptimizerVisitor.cs:1352`), so that divergence is not #6055's mechanism. TO-5 measures it anyway; a red there is not a finding against this branch.
- Access is excluded from `NarrowingCastIsKept`: `AccessSqlExpressionConvertVisitor.ConvertConversion:491-508` removes a decimal cast on both paths, so the test has nothing to discriminate there (reasoned from code; no local Access provider).
- The `COALESCE`-child type loss (U-2) is out of scope: measured on direct and remote alike, filed as [#6056](https://github.com/linq2db/linq2db/issues/6056).

## P11 Amendments

- A-1 (2026-10-16) — E-4 / E-5 not applied. TO-5 with both #5169 YDB scopes removed and scratch baselines: no direct/remote mismatch with the fix (`probe-ydb-baselines.log`) **and** none on the unfixed serializer either (control, `probe-ydb-baselines-unfixed.log`). The divergence those gates describe is already gone on `origin/master` for an unrelated reason, so removing them is not evidence for #6055 and does not belong on this branch; both scopes were restored. They go to the baseline-gating refactor, which re-measures every gated test. The P10 prediction that `StringJoinTests` would stay red was wrong (it matched on both arms). No approval change: the authorized surface shrank.

## P12 Critic verdict

**Round 1 (fable): refuted.** Objections: (1) TO-2's `B + 0` is reduced at build time in Modify mode (`SelectQueryOptimizerVisitor.cs:43,223`), so it never reached the Transform rebuild — TO-2 duplicated TO-1 and U-2 was closed on a non-discriminating probe; (2) lead: a convert-visitor-replaced child (`COALESCE`) does reach `QueryElementVisitor.cs:3060` on the client — D-2's "no measured divergence" premise was unsupported; (3) TO-1's `CAST|::` pattern cannot match Access (cast removed), DB2 (`Decimal(x,p,s)`), ClickHouse (`toDecimalNN`); (4) TO-3's negative assertion passes on an empty capture. Critic searched: the serializer diff, all `LinqServiceSerializer.Serialize/Deserialize` callers (remote-only, P3 holds by construction), `Tests/` for wire fixtures (none), build-time optimizer runs, `new Sql(Binary|Unary)Expression(\w+.SystemType` sites, provider `BuildTypedExpression`/`ConvertConversion`, `GetCurrentBaselines` capture, `5169` gates. Strongest point per critic: D-1 at the right altitude, mirroring `SqlField`/`SqlFunction`/`SqlCastExpression`.
Response: (1) TO-2 dropped, U-2 reopened with the mechanism named; (2) probed — the `COALESCE` shape drops the cast on the direct path as well (`probe-coalesce-serializer-only.log`), so it is an engine-wide defect, moved to its own issue (D-2 re-decided on that measurement); (3) pattern widened for DB2/ClickHouse, Access excluded with reason; (4) TO-3 anchored on the `+`.

**Round 2 (fable): weak.** Objections: (1) G-05 did not build the `Tests/Linq` project whose doc comments E-3 adds; (2) TO-1's evidence cited the narrower-pattern logs — the critic inspected the unfixed captures (SELECT only, `\bDecimal\(` cannot match `[DecimalTable]`) and confirmed the widened pattern stays red, but asked for the widened re-run to be cited; (3) TO-5 labelled red→green while it is a measurement, and the `StringJoinTests` gate describes a mandatory cast (not this mechanism). Critic searched: serializer diff and helpers, every `**/Remote/**` reference to the two nodes (only the pre-pass and E-1/E-2), every provider's `ConvertConversion` / `BuildTypedExpression` / decimal default (the cast pattern holds on all CI-only providers by code reading, Access excluded correctly), `PrepareStatementForRemoting` vs `PrepareStatementForSql` (both run one client-side `OptimizeAndConvertAll`, so the serializer is the only remote-only loss point), U-5's missing unary arm. Strongest point: D-2 now rests on a discriminating measurement.
Response: (1) Tests Release build added to G-05; (2) TO-1 cites `probe-final-fixed.log` once it lands (widened pattern, fixed code) plus the critic's inspection of the unfixed captures; (3) TO-5 relabelled characterization, `StringJoinTests` outcome pre-recorded in P10.
