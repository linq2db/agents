# Work plan: issue-6272-fix-projected-enum-compare — Projected enum comparisons with SetDefaultFromEnumType

**Tier:** M  ·  **Status:** approved  ·  **Approved-at:** 2026-11-09  ·  **Branch:** issue/6272-fix-projected-enum-compare
**Schema:** `.claude/docs/work-plan.md`  ·  **Gates:** `.claude/docs/definition-of-done.md`

## P1 Problem

[#6272](https://github.com/linq2db/linq2db/issues/6272): with `SetDefaultFromEnumType(typeof(ApiReason), typeof(DbReason))`, a query that projects `(ApiReason)e.Reason` and then filters on it throws `LinqToDBException: The LINQ expression '...' could not be converted to SQL` for `==`, `Equals(object)` and `!Equals(object)`. Translated in 6.1.0, fails since 6.2.0. Measured on origin/master (df3087172): `(int)p.Gender == 1` and `p.Gender.Equals(<closure>)` both throw on SQLite.MS and PostgreSQL.18, direct and remote. Expected SQL is a bare column compare, `WHERE e.reason = :reason`, with no CAST or CASE. The reporter's enums: `public enum ApiReason { Added = 2 }` and `public enum DbReason { [MapValue("added")] Added = 2 }`; the API enum carries no `MapValue`.

Regression source: #5258 added a fallback reusing the column when the cast target has no database type; #5332 removed it (`git show ccbbaeeca -- ExpressionBuildVisitor.cs`). #5399 then added the `GetDefaultMappingFromEnumType` retry, which still finds no database type when the mapped type is itself an enum.

## P2 Success criteria

- SC-1 `==` against a constant over the projected cast translates and returns the right rows → TO-1
- SC-2 `==` against a non-nullable closure value returns the right rows, so the parameter reaches the driver as the column's mapped value (`'F'`), not as the enum → TO-2
- SC-3 `==` against a nullable closure value returns the right rows → TO-3
- SC-4 `Equals(object)` over a boxed API enum returns the right rows → TO-4
- SC-5 `!Equals(object)` returns the right rows → TO-5
- SC-6 The generated SQL has no CAST or CASE around the column → TO-6
- SC-7 `Contains` over a client array of the API enum returns the right rows → TO-7
- SC-8 Projection, sort, group, distinct and set-operation reads of the cast keep working with the same SQL → TO-8, TO-9, TO-10, TO-11, TO-12
- SC-9 The cast inside child collections under `WithUnionLoadStrategy` keeps working, with and without child ordering → TO-13, TO-14

## P3 Constraints & anti-goals

- No change to projection materialisation: `BuildPurpose.Expression` reads still return before the edit (`ExpressionBuildVisitor.cs:2803`).
- No change to the `IsSupportedSubquery` probe outcome for this cast (build flags `None`); changing it crashes `CteContext.RegisterField` (U-3).
- No public API change. No new `BuildFlags` member. No `CteContext` edit.
- A cast whose target has an explicit database type (`SetDataType`) still takes the existing `TryCastTo(node.Type)` path first.
- Enums without a `SetDefaultFromEnumType` registration keep today's behaviour in `VisitUnary` (cast to the underlying type).

## P4 Unknowns

- U-1 Does the failure reproduce on current master — resolved-by probe: 28 of 58 red on master, messages as in P1.
- U-2 Does passing the column through make execution correct, or only SQL generation — resolved-by probe: SQL-only was not enough; a non-nullable parameter reached the driver as `Tests.Model.Gender` (Npgsql: "Writing values of 'Tests.Model.Gender' is not supported for parameters having NpgsqlDbType 'Char'"; SQLite: 0 rows instead of 1) and a boxed `ApiGender` threw `LinqToDBConvertException` from `ConvertBuilder.ConvertDefault`. Both needed E-2 / E-3.
- U-3 Does an unconditional pass-through regress anything — resolved-by probe: yes. With a pass-through gated only on `BuildPurpose.Sql`, `ProjectedEnumCastUnionEagerLoad` and `...Ordered` throw `ArgumentOutOfRangeException` at `CteContext.cs:245` on all four contexts; master passes; a plain column in the same query shape passes. A stack trace from the new branch showed its only caller in that test is `IsSupportedSubquery` at build flags `None`. The exact column/field mismatch was not established; see P10.
- U-4 Which paths set `BuildFlags.ForKeys`, given it now gates the pass-through — resolved-by scout: comparison operands (`ExpressionBuildVisitor.cs:3589`, `:4658`), `Contains` (`:4149`, `ContainsBuilder.cs:169,193,209`), `OrderByBuilder.cs:109,114`, `GroupByBuilder.cs:170,231,395,576`, `JoinBuilder.cs:132,133`, `DistinctByBuilder.cs:127`, `ExpressionBuilder.EagerLoad.cs:47`, `ExpressionBuilder.EagerLoadUnion.cs:1322`, `AggregateExecuteBuilder.cs:57`, `BuildProxyBase{TOwner}.cs:72`, `ExpressionBuildVisitor.cs:1863`, `ConvertInPredicate` (`ExpressionBuildVisitor.cs:5569`). Readers that meet the retyped placeholder: `GetProjectFlags` (`:550-572`), `HandleValue` (`:3116`), `VisitSqlAggregateLifterExpression` (`:3928`).
- U-5 Is the pass-through result isolated in the translation cache — resolved-by scout: `GetProjectFlags` maps `ForKeys` to `ProjectFlags.Keys` (`ExpressionBuildVisitor.cs:550`), which is in `ExprCacheKey` (`:509`), so the `ApiGender`-typed placeholder is not served to a non-keys build.
- U-6 Does the wider `ForKeys` reach change existing SQL — resolved-by probe: `ProjectedEnumCastOrderBy` and `...GroupBy` on SQLite.MS produce identical SQL on master and with the fix (`ORDER BY [p].[Gender], [p].[PersonID]`; `GROUP BY [g_1].[Gender]`). `Join` (all four contexts) and `DistinctBy` (SQLite.MS, direct and remote) over this cast are red on master and green with the fix, so `ForKeys` fixes them too (TO-15, TO-16).
- U-7 Does `Equals(object)` depend on the reporter's `object → DataParameter` converter — resolved-by probe: TO-4 and TO-5 now run on a schema without it and pass; TO-17 keeps the reporter's converter and also passes.
- U-8 Does a boxed value of an unrelated enum still fail loudly — resolved-by probe: TO-18 asserts `LinqToDBConvertException` on master and with the fix.

## P5 Decisions

### D-1 — Where the pass-through applies

- **chosen:** Inside the existing enum branch of `VisitUnary`, when `_buildPurpose is BuildPurpose.Sql`, `BuildFlags.ForKeys` is set, and the target enum's default mapping is the operand's enum type. User chose this over the alternatives below after U-3.
- **rejected:** General pass-through for any SQL build — regresses `WithUnionLoadStrategy` (U-3).
- **rejected:** General pass-through plus a `CteContext.RegisterField` repair — the index bug at `CteContext.cs:243` is real, but the crash needs a select column with no registered field, so repairing only the index risks misaligned columns; `CteContext` serves every CTE query.
- **rejected:** Shipping the general pass-through with a filed issue — knowingly regresses a working query.
- **rejected:** A new `BuildFlags` member for comparisons only — `ForKeys` already marks these builds and is already in the cache key; a new flag would also have to be mapped into `ProjectFlags` to be cache-safe.
- **why this:** `ForKeys` means the value is used as a SQL key, where only the column's identity matters; reader-typed builds never see it.
- **failure mode of the choice:** `ForKeys` is broader than comparisons. A site in U-4 that consumes the placeholder's CLR type rather than its SQL could misbehave for this cast.

### D-2 — Non-nullable parameter conversion

- **chosen:** Extend the existing nullable-only safe-convert branch in `ParametersContext` to a non-nullable enum value whose column member type is a different enum.
- **rejected:** Looping inside `ColumnDescriptor.ApplyConversions` until the value is no longer an enum — that method has six callers including `EnumerableContext` and `ExpressionBuilder.SqlBuilder`, far wider than this path.
- **rejected:** Making `GetDefaultMappingFromEnumType` resolve transitively to `string` — `ApiGender` has no `MapValue`, so a direct conversion to `string` would produce `"Female"`, not `"F"`.
- **why this:** Reuses the path the nullable case already takes and that TO-3 shows correct.
- **failure mode of the choice:** Any non-nullable enum parameter compared against a different enum's column descriptor now converts numerically through the column's enum, whether or not a `SetDefaultFromEnumType` registration exists. The arm requires the two enums to differ after unwrapping, so a value of enum `A` against an `A?` column keeps master's path; the original nullable arm is unchanged.

### D-3 — Boxed enum to column enum

- **chosen:** A branch in `GenerateConvertFromObject` calling `Enum.ToObject`, a numeric reinterpretation matching what the CLR cast does, taken only when the boxed value's enum type has the column's enum as its default mapping (`IsDefaultMappedTo`).
- **rejected:** Changing `ConvertBuilder.ConvertDefault` — a global fallback, far wider.
- **why this:** Only caller is `ParametersContext.cs:268`, reached when a parameter typed `object` meets an enum column descriptor.
- **failure mode of the choice:** The accessor holds a reference to the `MappingSchema`, and evaluates the mapping per execution for a boxed enum parameter. An unrelated enum keeps master's `LinqToDBConvertException` (TO-18).

## P6 Edit-points

- E-1 `Source/LinqToDB/Internal/Linq/Builder/ExpressionBuildVisitor.cs:VisitUnary` — keep the column as-is, retyped, under the D-1 conditions.
- E-2 `Source/LinqToDB/Internal/Linq/Builder/ParametersContext.cs:valueType != MemberType branch` — widen the safe-convert condition per D-2.
- E-3 `Source/LinqToDB/Internal/Linq/Builder/ParametersContext.cs:GenerateConvertFromObject` — boxed-enum branch per D-3, plus the `_enumToObject` field and `System.Reflection` using.
- E-4 `Tests/Linq/Linq/EnumMappingTests.cs:ProjectedEnumCast*` — regression and guard tests on the shared `Person` / `Gender` model.
- E-5 `Source/LinqToDB/Internal/Linq/Builder/ExpressionBuildVisitor.cs:ConvertEnumConversion` — constant arm declines an enum constant of a type other than the operand's.
- E-6 `Tests/Linq/Linq/EnumMappingTests.cs:DirectEnumCast*` — tests for the cast written directly in the predicate.

## P7 Impact map

- `ExpressionBuildVisitor.cs:2803` — `BuildPurpose.Expression` without `ForSetProjection` returns before the edit; searched `_buildPurpose is BuildPurpose.Expression` in `VisitUnary` — out-of-scope
- `BuildFlags.ForSetProjection` callers `ExpressionBuilder.EagerLoadUnion.cs:205,315,473,906` — purpose `Expression`, excluded by the `BuildPurpose.Sql` check; searched `ForSetProjection` under `Internal/Linq/Builder` — covered by E-1
- `ForKeys` setters listed in U-4 — searched `BuildFlags.ForKeys|ForKeys\)` under `Internal/Linq/Builder`; comparison, `Contains`, `OrderBy`, `GroupBy` measured — covered by E-1
- `JoinBuilder.cs:132,133`, `DistinctByBuilder.cs:127` — same search, measured by TO-15 and TO-16 — covered by E-1
- `ExpressionBuildVisitor.cs:3116`, `:3928` — searched `ForKeys` readers; critic could not construct a shape reaching `:3928` with this cast and neither test set exercises it — deferred: no reaching shape found
- `IsSupportedSubquery` callers (`ExpressionBuildVisitor.cs:1900`, `:5827`, `SelectManyBuilder.cs:146`, `DefaultIfEmptyBuilder.cs:124`) — searched the symbol; `:5807` resets to `BuildFlags.None` before the `:5827` probe, and `:1900` probes association targets, which are entity projections — out-of-scope
- `Converter.GetDefaultMappingFromEnumType` callers (`CommandInfo.cs:1725`, `LinqService.cs:349`, `MappingSchema.cs:437`, `ColumnDescriptor.cs:540,824`, `MappingExtensions.cs:48,79`, `OracleMappingSchema.cs:158`, `ConvertFromDataReaderExpression.cs:106`, `ParametersContext.cs:483`) — searched the symbol under `Source/LinqToDB`; the function is unchanged — out-of-scope
- `GenerateConvertFromObject` — searched the symbol under `Source/LinqToDB`, single caller `ParametersContext.cs:268` — covered by E-3
- `ColumnDescriptor.ApplyConversions` callers — searched `\.ApplyConversions\(` under `Source/LinqToDB`; method unchanged, E-2 alters only its input in `ParametersContext` — covered by E-2
- Remote: `.LinqService` contexts run every TO — covered by E-4

## P8 Test obligations

- TO-1 `ProjectedEnumCastEqualConstant`: `== ApiGender.Female` returns the single female row; discriminating input is the mapped `'F'` value — providers: `[DataSources]`, measured SQLite.MS, PostgreSQL.18 — proof: red→green
- TO-2 `ProjectedEnumCastEqualParameter`: `== closure`; discriminating input is a non-nullable parameter that must reach the driver as `'F'` — providers: `[DataSources]`, measured SQLite.MS, PostgreSQL.18 — proof: red→green
- TO-3 `ProjectedEnumCastNullableEqualParameter`: `==` nullable closure — providers: `[DataSources]`, measured SQLite.MS, PostgreSQL.18 — proof: red→green
- TO-4 `ProjectedEnumCastEqualsObject`: boxed `ApiGender` — providers: `[DataSources]`, measured SQLite.MS, PostgreSQL.18 — proof: red→green
- TO-5 `ProjectedEnumCastNotEqualsObject`: negated form — providers: `[DataSources]`, measured SQLite.MS, PostgreSQL.18 — proof: red→green
- TO-6 `ProjectedEnumCastEmitsNoSqlCast`: SQL contains neither `CAST` nor `CASE` — providers: `[DataSources]`, measured SQLite.MS, PostgreSQL.18 — proof: red→green
- TO-7 `ProjectedEnumCastContains`: client array — providers: `[DataSources]`, measured SQLite.MS, PostgreSQL.18 — proof: red→green
- TO-8 `ProjectedEnumCastSelect`: reader still converts `'F'` to `ApiGender` — providers: `[DataSources]`, measured SQLite.MS, PostgreSQL.18 — proof: characterization
- TO-9 `ProjectedEnumCastOrderBy` — providers: `[DataSources]`, measured SQLite.MS, PostgreSQL.18 — proof: characterization
- TO-10 `ProjectedEnumCastGroupBy` — providers: `[DataSources]`, measured SQLite.MS, PostgreSQL.18 — proof: characterization
- TO-11 `ProjectedEnumCastDistinct` — providers: `[DataSources]`, measured SQLite.MS, PostgreSQL.18 — proof: characterization
- TO-12 `ProjectedEnumCastConcat` — providers: `[DataSources]`, measured SQLite.MS, PostgreSQL.18 — proof: characterization
- TO-13 `ProjectedEnumCastUnionEagerLoad`: discriminating input is a general pass-through, which crashes it (U-3) — providers: `[DataSources]`, measured SQLite.MS, PostgreSQL.18 — proof: control
- TO-14 `ProjectedEnumCastUnionEagerLoadOrdered`: same mutation, ordered children — providers: `[DataSources]`, measured SQLite.MS, PostgreSQL.18 — proof: control
- TO-15 `ProjectedEnumCastJoinKey`: join on the cast as a key — providers: `[DataSources]`, measured SQLite.MS, PostgreSQL.18 — proof: red→green
- TO-16 `ProjectedEnumCastDistinctBy`: red on SQLite.MS only, PostgreSQL.18 is green on master — providers: `[DataSources]`, measured SQLite.MS, PostgreSQL.18 — proof: red→green
- TO-17 `ProjectedEnumCastEqualsObjectWithObjectConverter`: the reporter's `object → DataParameter` converter registered — providers: `[DataSources]`, measured SQLite.MS, PostgreSQL.18 — proof: red→green
- TO-18 `EqualsObjectOfUnmappedEnumThrows`: symmetry guard on the unchanged path, a boxed unrelated enum against the plain column still throws — providers: `[DataSources]`, measured SQLite.MS, PostgreSQL.18 — proof: characterization
- TO-19 `DirectEnumCastEqualConstant`: cast and constant in one predicate; discriminating input is the mapped `'F'` against the enum name `'Female'` — providers: `[DataSources]`, measured SQLite.MS, Access.Ace.OleDb, Firebird.2.5 — proof: red→green
- TO-20 `DirectEnumCastNotEqualConstant`: negated form — providers: `[DataSources]`, measured SQLite.MS, Access.Ace.OleDb, Firebird.2.5 — proof: red→green
- TO-21 `DirectEnumCastEqualParameter`: cast and closure value in one predicate — providers: `[DataSources]`, measured SQLite.MS, Access.Ace.OleDb, Firebird.2.5 — proof: red→green
- TO-22 `DirectEnumCastOverConditionalEqualParameter`: operand with no recoverable column descriptor — providers: `[DataSources]`, measured SQLite.MS, Access.Ace.OleDb, Firebird.2.5 — proof: red→green
- TO-23 `ProjectedEnumCastChildReferencesParent`: a child collection comparing against the parent's cast member — providers: `[DataSources]`, measured SQLite.MS, Access.Ace.OleDb, Firebird.2.5 — proof: characterization

## P9 Verification gates

- G-01: pass — `worktree-test.ps1` over `EnumMappingTests`, `ConverterInsertTests`, `Issue5398Tests`, `ComplexTests2`, `ParameterTests`, `EagerLoadingStrategyUnionTests` on SQLite.MS, PostgreSQL.18 and both `.LinqService` contexts, net10.0 Debug: 978 passed, 5 skipped, 0 failed. Unfixed source on the `ProjectedEnumCast*` set plus TO-18: 38 of 74 red, covering TO-1..TO-7, TO-15, TO-16 (SQLite.MS only) and TO-17. TO-8..TO-14 and TO-18 green on master. TO-1..TO-18 on net462 Release: 70 of 70 passed. TO-13/TO-14 control: red under a pass-through without the `ForKeys` condition. `test-diff-sweep.ps1 -IncludeWorkingTree` on the implemented tree: chains 0, nestedChains 0, narrowedSets 0, narrowedWithoutReason 0.
  - TO-1 `ProjectedEnumCastEqualConstant` — red on master, green with fix
  - TO-2 `ProjectedEnumCastEqualParameter` — red on master, green with fix
  - TO-3 `ProjectedEnumCastNullableEqualParameter` — red on master, green with fix
  - TO-4 `ProjectedEnumCastEqualsObject` — red on master, green with fix
  - TO-5 `ProjectedEnumCastNotEqualsObject` — red on master, green with fix
  - TO-6 `ProjectedEnumCastEmitsNoSqlCast` — red on master, green with fix
  - TO-7 `ProjectedEnumCastContains` — red on master, green with fix
  - TO-8 `ProjectedEnumCastSelect` — green on master and with fix
  - TO-9 `ProjectedEnumCastOrderBy` — green on master and with fix
  - TO-10 `ProjectedEnumCastGroupBy` — green on master and with fix
  - TO-11 `ProjectedEnumCastDistinct` — green on master and with fix
  - TO-12 `ProjectedEnumCastConcat` — green on master and with fix
  - TO-13 `ProjectedEnumCastUnionEagerLoad` — green on master and with fix, red under the control mutation
  - TO-14 `ProjectedEnumCastUnionEagerLoadOrdered` — green on master and with fix, red under the control mutation
  - TO-15 `ProjectedEnumCastJoinKey` — red on master, green with fix
  - TO-16 `ProjectedEnumCastDistinctBy` — red on master for SQLite.MS, green with fix
  - TO-17 `ProjectedEnumCastEqualsObjectWithObjectConverter` — red on master, green with fix
  - TO-18 `EqualsObjectOfUnmappedEnumThrows` — green on master and with fix
  - TO-19 `DirectEnumCastEqualConstant` — throws on master, wrong rows without E-5, green with E-5
  - TO-20 `DirectEnumCastNotEqualConstant` — throws on master, wrong rows without E-5, green with E-5
  - TO-21 `DirectEnumCastEqualParameter` — red on master, green with fix
  - TO-22 `DirectEnumCastOverConditionalEqualParameter` — red on master, green with fix
  - TO-23 `ProjectedEnumCastChildReferencesParent` — green on master and with fix
  - After A-1: SQLite.MS over the suites above 557 passed, 5 skipped, 0 failed; new tests on Access.Ace.OleDb 46 of 46 and Firebird.2.5 46 of 46. PostgreSQL.18 and net462 were not rerun after A-1; `test-all` covers them. `test-diff-sweep.ps1 -IncludeWorkingTree` after A-1: chains 0, nestedChains 0, narrowedSets 0, narrowedWithoutReason 0.
- G-02: skipped — no local baselines captured for this worktree, so emitted-SQL drift across providers is unverified locally and left to the CI baselines run; OrderBy and GroupBy SQL compared by hand on SQLite.MS only.
- G-05: pass — `dotnet build` Release of `Source/LinqToDB` for net10.0, netstandard2.0, net462 exit 0; `Tests/Linq` Release net10.0 exit 0 and net462 built by the run above. After A-1: `Source/LinqToDB` and `Tests/Linq` Release net10.0 exit 0.
- G-06: pass — `git diff --stat` touches only the E-n files.
- G-07: pass — no `Tests/Tests.Playground/` changes in `git status`.
- G-09: pass — review round 1 over 466207b6a by the code-reviewer agent: 4 findings, all fixed under A-1, ledger in `gaps.md`.

## P10 Adjudicated

- The exact mechanism of the `CteContext.RegisterField` crash under a general pass-through is not established. D-1 avoids the trigger rather than repairing it. Reason: user decision after two refuted explanations.
- Other SQL uses of the cast keep failing as on master where no `ForKeys` build reaches them. Reason: option chosen by the user.
- The `ForKeys` gate is wider than comparison operands: `Contains`, `Join` and `DistinctBy` over the cast also start working. Each was red on master; `OrderBy` and `GroupBy` SQL is unchanged. Corrected by A-1: this is not automatically error-removal, because an enum constant in the same predicate returned wrong rows until E-5.
- An API enum that carries its own `MapValue`s resolves its default mapping to the value type (`ConvertBuilder.cs:688`), so E-1 does not apply and the error stays as on master. Reason: the reporter's enum has none (P1), and such an enum has its own stored values, so a bare column compare would be wrong.

## P11 Amendments

- A-1 (2026-11-09, review round 1) — E-1 made `(ApiEnum)column == ApiEnum.X` build, and `ConvertEnumConversion` then matched the constant against the column enum's map values, found none and compared against the enum's name: measured on SQLite.MS, 0 rows instead of 1 for `==` and 4 instead of 3 for `!=`, where the base commit throws. E-5 declines such a constant so the regular compare converts it. Also from that review: TO-16 gained the `DistinctBy` provider gate from its sibling, and TO-13/TO-14 were measured on Access.Ace.OleDb and Firebird.2.5 and need no exclusion.
  re-derives: P6 (E-5, E-6), P8 (TO-16, TO-19, TO-20, TO-21, TO-22, TO-23), P10 (ForKeys entry)
  conventions: testing.md Test layout and A narrowed provider set is a claim; swept with test-diff-sweep.ps1 -IncludeWorkingTree over the added tests.

## P12 Critic verdict

**weak** (plan-critic on fable, round 1). The critic searched every `ForKeys` setter and reader, `IsSupportedSubquery` callers, `GetProjectFlags` / `ExprCacheKey`, `GetDefaultMappingFromEnumType`, `GenerateSafeConvert`, `ApplyConversions`, `SuggestColumnDescriptor`, `SqlParameterCastExpression` sites and the ban list, and found the U-3 → D-1 chain sound. Objections and responses:

- TO-4 / TO-5 relied on an unrelated `object → DataParameter` converter — fixed: both run without it, TO-17 keeps the reporter's shape.
- D-3 silently compared unrelated enums numerically — fixed: gated on the default mapping, TO-18 pins the throw.
- E-2 also fired for enum `A` against an `A?` column — fixed: the arm requires different enums.
- U-4 census incomplete — fixed in U-4 and P7; `:3928` remains unexercised, recorded in P7.
- E-1 misses an API enum with its own `MapValue`s — recorded in P1 and P10.
- TO-6 asserted no `CAST` on the whole statement, which providers that cast parameters could trip — fixed: the assertion targets a cast around the column.
- TO-15 / TO-16 pending — done.

Open from the critic: `Enum.ToObject` on a boxed enum on net462 / netstandard2.0 is reasoned, not run; the Release builds compile it but only CI executes it there.
