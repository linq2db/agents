# Work plan: infra-nunit-5 — one exception-assertion style, enforced by the banned-API analyzer

**Tier:** M  ·  **Status:** approved  ·  **Approved-at:** 2026-11-14 (maintainer, after critic round 2 — weak, objections folded in)  ·  **Branch:** infra/nunit-5
**Schema:** `.claude/docs/work-plan.md`  ·  **Gates:** `.claude/docs/definition-of-done.md`

Scope note: the branch already carries the NUnit 4.6.1 → 5.0.0 bump (PR #6330, commits up to `7a2eefb84`), authored without a plan. This plan covers the delta the maintainer asked for on 2026-11-14, on top of that bump. E-1 lists the bump's files so `-Reconcile` sees them as planned; they get no further change except where E-3..E-16 convert assertions in them.

## P1 Problem

NUnit 5.0.0 made `Assert.ThrowsAsync` / `CatchAsync` / `DoesNotThrowAsync` return a `Task` that asserts only when awaited. On this branch, 12 of 23 such calls compiled un-awaited and asserted nothing; NUnit2059 reports them in Release builds only. NUnit 5.0.0 also made `Assert.Catch(Action, string)` match the exact type, which turned `CommonTests.ReplaceTableTest` red on every SQL Server leg of Azure build 25670. The test tree uses four idioms for one job: about 224 NUnit `Assert.Throws/ThrowsAsync/Catch/CatchAsync/DoesNotThrow*` calls, about 45 `Assert.That(…, Throws…)`, 40 static Shouldly `Should.Throw*` and 98 extension `ShouldThrow*`. `Assert.DoesNotThrow*` and Shouldly's `NotThrow*` assert nothing that a direct call does not already assert. Maintainer decision (2026-11-14): ban the six NUnit exception methods and the Shouldly NotThrow forms. `Assert.That` / `Assert.ThatAsync` with a `Throws` constraint becomes the default, with `Should.Throw[Async]` as the fallback when the test needs the exception object.

## P2 Success criteria

- SC-1 `Tests/BannedSymbols.txt` bans every overload of `Assert.Throws`, `ThrowsAsync`, `Catch`, `CatchAsync`, `DoesNotThrow`, `DoesNotThrowAsync` and Shouldly's `Should.NotThrow`, `Should.NotThrowAsync`, `ShouldThrowExtensions.ShouldNotThrow`, `ShouldThrowTaskExtensions.ShouldNotThrow`, `ShouldNotThrowTaskAsyncExtensions.ShouldNotThrowAsync`, and a Release build of every test project that imports the file reports zero RS0030 → TO-1
- SC-2 a reintroduced banned call fails the Release build with RS0030 naming the replacement → TO-2
- SC-3 each conversion keeps the assertion's strength: exact-type stays exact (`Throws<T>` → `Throws.TypeOf<T>()`), instance-of stays instance-of (`Catch<T>` → `Throws.InstanceOf<T>()`, `Catch` → `Throws.Exception`), message checks stay, and an awaited async assertion stays awaited → TO-3
- SC-4 the `AssertQueryTests` sites that assert a helper's `AssertionException` still pass, and still fail when the helper does not fail → TO-4
- SC-5 the converted fixtures pass where they passed before → TO-5
- SC-6 AGENTS.md, `.github/copilot-instructions.md`, `testing.md`, `rubric-tests.md` and `test-writer.md` teach the new rule, and no current corpus doc recommends a banned form → TO-6

## P3 Constraints & anti-goals (M/L)

- No `Source/` change and no public API change.
- No test changes what it asserts: no exact-type check is loosened to instance-of, no message or property check is dropped, and no test changes its provider set or gating.
- Existing Shouldly `Should.Throw*` / `ShouldThrow*` sites stay as they are; they remain allowed.
- Only the converted call is reformatted; surrounding lines stay untouched.
- Historical plans, gap ledgers and the KB (`.claude/plans/**`, `.claude/knowledge-base/**`) are records and are not rewritten.

## P4 Unknowns (M/L)

- U-1 Does sync `Assert.That(async () => …, Throws…)` assert anything in NUnit 5.0.0, or does it bind to `That<T>(Func<T>)` with `T = Task` and pass vacuously? Measured in `.build/.agents/nunit5-probe2` (NUnit 5.0.0 under the NUnit MTP runner, real test context): sync `Assert.That` over an async lambda, a `() => Task` lambda and a `() => Task<int>` lambda all wait on the task and assert. The throwing cases pass, and `SyncThat_AsyncLambda_Quiet` / `SyncThat_TaskLambda_Quiet` fail with "Expected: <System.InvalidOperationException> But was: no exception thrown". Not vacuous. — resolved-by probe
- U-2 Does `Assert.That(…, Throws.TypeOf<AssertionException>())` / `Assert.ThatAsync` run the delegate in an isolated test context the way `Assert.Throws` does (`testing.md:701`), so that an inner failed `Assert.That` does not fail the outer test? Measured in probe2: `That_ThrowsTypeOf`, `That_ThrowsInstanceOf` and `ThatAsync_ThrowsTypeOf`, each wrapping a failing `Assert.That(1, Is.EqualTo(2))`, pass, as do the `Assert.Throws` / `ThrowsAsync` controls. The constraint path isolates. Round 2 of the probe (`run2.log`, 25 tests, 7 failed, the 7 failures being exactly the `*_MUSTFAIL` cases) adds the value-returning shapes that `AssertQuery<T>` binds (`That<T>(Func<T>)`, `Tests/Base/TestBase.AssertQuery.cs:432`): `That_FuncT_ThrowsTypeOf` and `ThatAsync_FuncTaskT_ThrowsTypeOf` pass, so these isolate too. `That_ShouldlyFailure_ThrowsInstanceOf` passes with a Shouldly `ShouldBe` failure inside the delegate. — resolved-by probe
- U-3 Does a doc ID without a parameter list (`M:NUnit.Framework.Assert.Throws`) make BannedApiAnalyzers ban every overload, generic ones included? Measured in `.build/.agents/nunit5-probe3` (BannedApiAnalyzers 5.6.0, as pinned in `Directory.Packages.props`): no. Eleven parameterless IDs flagged none of 19 banned-form lines; only full-signature IDs fired. `.build/.agents/nunit5-banned-gen.ps1` derives 52 full-signature IDs by reflection over every TFM asset of NUnit 5.0.0 (net462, net8.0, net10.0) and Shouldly 4.3.0 (net8.0, net9.0, netstandard2.0), unioned: 28 NUnit and 24 Shouldly. With that list, all 19 `B<n>` lines in `probe3/Uses.cs` report RS0030 and none of the 7 `OK<n>` lines does (`Assert.That(…, Throws.Nothing)`, `Assert.ThatAsync`, `Should.Throw`, `Should.ThrowAsync`, `ShouldThrow`, `ShouldThrowAsync`, a plain `await`). — resolved-by probe
- U-4 Which projects import `Tests/BannedSymbols.txt`? `Tests/Directory.Build.props:24` adds it to every test project. `Tests.Wasm.App`, `Tests.SingleFile`, `Tests.FpuJit`, `Tests.Analyzers` and `Tests.Analyzers.Internal` remove it (`<AdditionalFiles Remove>` in each csproj). `git grep` finds no banned-form site in those five or outside `Tests/`, and none in F# / VB sources. — resolved-by scout
- U-5 Is RS0030 an error? The analyzers run in Release only, and `TreatWarningsAsErrors=true` turns RS0030 into a build error; CI enforces it in its Release solution build (AGENTS.md → *Build gotchas*). — resolved-by scout
- U-6 Inside `Tests.*`, `Tests/Base/Should.cs` shadows `Shouldly.Should`, so the static fallback must be written `Shouldly.Should.Throw<T>(…)`; the extension `act.ShouldThrow<T>()` resolves as is (`testing.md:1093-1102`). — resolved-by scout
- U-7 NUnit 5.0.0 overloads: `Assert.That(Action, IResolveConstraint, NUnitString | FormattableString | Func<string>, …)` and `Assert.ThatAsync(Func<Task> | Func<Task<T>>, IResolveConstraint, NUnitString | FormattableString, …)`; there is no `TestDelegate` / `AsyncTestDelegate` `That` overload (`nunit.framework.xml` lines 1082-1181, 5.0.0). — resolved-by scout
- U-8 Are the mappings semantically equal: `Throws.TypeOf<T>()` exact, `Throws.InstanceOf<T>()` and `Throws.Exception` instance-of? Measured in probe2: `Throws.TypeOf<ArgumentException>()` against an `ArgumentNullException` fails ("Expected: <System.ArgumentException> But was: <System.ArgumentNullException…>"), while `Throws.InstanceOf<ArgumentException>()` and `Throws.Exception` pass. `ThatAsync(…, Throws.TypeOf<T>().With.Message.EqualTo("nope"))` fails on message "boom"; a quiet delegate fails `ThatAsync`. — resolved-by probe
- U-9 Does `Assert.That(…, Throws…)` inside `Assert.EnterMultipleScope()` accumulate failures like other `Assert.That` calls? Measured in probe2: two failing `Assert.That(() => { }, Throws.Exception)` in one scope report both failures. — resolved-by probe
- U-10 How many sites does the statement-form codemod rewrite? Dry run of `.build/.agents/nunit5-convert-asserts.ps1` over `Tests/`: 172 automatic, 51 manual (44 use the result, 6 block-bodied `DoesNotThrow*` lambdas, 1 non-delegate first argument at `YdbRetryPolicyTests.cs:39`), plus 5 Shouldly `NotThrow*` by hand. — resolved-by probe

## P5 Decisions (M/L; rejected alternatives mandatory at L)

### D-1 — Enforce with BannedApiAnalyzers in `Tests/BannedSymbols.txt`

- **chosen:** the 52 full-signature doc IDs generated in U-3, each with a message naming the replacement, under one comment line saying the IDs are full signatures and must be regenerated when NUnit or Shouldly is bumped.
- **rejected:** parameterless method-group IDs — they ban nothing in BannedApiAnalyzers 5.6.0 (U-3). A custom linq2db analyzer — the existing banned-API wiring does the job with no new code. Documentation only — that was the state that produced four idioms.
- **why this:** the file is already imported by every test project that has sites (U-4), and RS0030 is an error in the CI Release build (U-5).
- **failure mode of the choice:** enforcement is Release-only, so a local Debug or `-c Testing` build accepts a banned call and the PR finds out in CI. An overload added by a future NUnit or Shouldly version is not banned until the list is regenerated.

### D-2 — Constraint mapping

- **chosen:** `Throws<T>` → `Throws.TypeOf<T>()`; `Catch<T>` → `Throws.InstanceOf<T>()`; `Catch` → `Throws.Exception`; the async forms go to `await Assert.ThatAsync(…)` with the same constraint; a message argument stays as the message argument.
- **rejected:** mapping everything to `Throws.InstanceOf` — it silently loosens 100+ exact-type checks.
- **why this:** it keeps each assertion's strength (SC-3); U-8 measured the equivalence.
- **failure mode of the choice:** an author writes sync `Assert.That` over an async lambda. U-1 measured that it still asserts, but it blocks on the task, so the rule text says `Assert.ThatAsync` in async code.

### D-3 — When to fall back to Shouldly

- **chosen:** use the constraint form when the check fits one constraint chain: the type, plus `.With.Message.<op>(…)` (`.IgnoreCase`, `.And.<op>` included), `.With.Property(nameof(…)).<op>(…)` or `.With.InnerException.<constraint>`. Use `Shouldly.Should.Throw<T>(…)` / `await Shouldly.Should.ThrowAsync<T>(…)` only when the test needs the exception object afterwards: checks that do not fit one chain, casts, or passing it on. **Shouldly's `Throw<T>` accepts subclasses** (`testing.md:1104`; critic round 1, decompiled `ThrowInternal`). So a Shouldly fallback replacing an exact-type `Assert.Throws<T>` / `ThrowsAsync<T>` follows the call with `ex.ShouldBeOfType<T>()` on its own line. Replacing an instance-of `Catch<T>` / `Catch` needs nothing extra; untyped `Catch` becomes `Throw<Exception>`.
- **two chain rules, measured in probe2 `ChainTests` (`run3.log`, 6 tests, 3 failed):**
  - A second message check repeats the property: `.With.Message.Contains(a).And.Message.Contains(b)`. `.And.Contains(b)` returns to the exception and throws `ArgumentException: Expected: IEnumerable But was: InvalidOperationException` (`MessageAndContains_BothPresent` fails, `MessageAndMessageContains_BothPresent` passes).
  - Keep the converted assertion's case option. NUnit `Contains` is case-sensitive (`MessageContains_CaseSensitive_MUSTFAIL` fails, `MessageContainsIgnoreCase` passes), while Shouldly's string `ShouldContain` ignores case by default (`ShouldlyShouldContain_WrongCase` passes). A site that checked with `ShouldContain` therefore gets `.IgnoreCase`.
- **disposition of the 14 exact-type result-used sites** (read 2026-11-14), all to the constraint form, none to Shouldly. `MappingTests.cs` here is `Tests/Linq/Linq/MappingTests.cs` throughout:
  - type + message, case-sensitive: `CompileTests.cs:1116`, `MappingTests.cs:2025`, `InsertTests.cs:1945`, `UpdateTests.cs:2167`
  - type + message, Shouldly `ShouldContain` → `.IgnoreCase`: `ImplicitCollectionLoadingTests.cs:40,141`, `WindowFunctionsTests.Frame.cs:300`
  - type + message, `ToLowerInvariant().Contains`: `MappingTests.cs:446,448` → `.With.Message.Contains("firstname").IgnoreCase`
  - two message substrings: `CompileTests.cs:805` → `.With.Message.Contains("ILoadWithQueryable").And.Message.Contains("IQueryable<T>")`, keeping its comment
  - property: `MappingTests.cs:454` → `.With.Property(nameof(LinqToDBConvertException.ColumnName)).EqualTo("firstname").IgnoreCase`; `MappingTests.cs:466` → same with `"lastname"` (`:467`); `RemoteContextTests.cs:508` (`ObjectName`, `Does.Contain`); `ToolsTests.cs:821` (`SqlException.Number`)
- **rejected:** forcing everything into constraint chains — `With.Property` takes a string name and loses compile-time checking for multi-step checks. Keeping `Assert.Catch` behind `#pragma` for result-used sites — that recreates the idiom split the ban exists to end. Plain Shouldly for exact-type sites — it loosens them (critic round 1).
- **why this:** it is a mechanical rule a reviewer and `test-writer` can apply the same way, and it keeps SC-3.
- **failure mode of the choice:** two allowed forms remain, and the exact-type Shouldly arm depends on an author remembering `ShouldBeOfType<T>()`. The E-2 ban message and the doc rule state it.
- **A-2 clause:** never `Shouldly.Should.ThrowAsync` / `ShouldThrowAsync` for a test about a cancelled call. For a `Canceled` task it returns a new `TaskCanceledException`; use the constraint form.

### D-4 — `DoesNotThrow*` / `NotThrow*` become direct calls

- **chosen:** `Assert.DoesNotThrow(() => expr)` → `expr;`; a method group → a call; `DoesNotThrowAsync` → `await expr;`; a block-bodied lambda → its block, kept as a `{ … }` scope so its locals do not collide. A `DoesNotThrow` message is kept as a trailing `//` comment, since it labels what the line checks.
- **rejected:** `Assert.That(() => …, Throws.Nothing)` — it still asserts nothing that a direct call does not, and it hides the stack trace.
- **why this:** a direct call fails the test with the real exception and its full trace.
- **failure mode of the choice:** an expression lambda whose body is not a valid statement expression (a property read) does not compile as `expr;`; the build catches it.

### D-5 — `AssertionException` sites in `AssertQueryTests`

- **chosen:** convert them like any other site, to `Assert.That(() => AssertQuery(…), Throws.TypeOf<AssertionException>())`; U-2 measured that the constraint path isolates the inner failure. `testing.md:701` is reworded to name the constraint form.
- **rejected:** keeping `Assert.Throws` behind `#pragma warning disable RS0030` — unnecessary once U-2 holds, and an escape hatch others would copy. Shouldly — `testing.md:701` records that it has no isolation, so the test would fail.
- **why this:** those tests assert that a test helper fails, which needs NUnit's isolated result, and the constraint form provides it.
- **failure mode of the choice:** U-2 was measured on probe delegates, not on `AssertQuery` itself. If TO-4 shows a converted site failing its outer test, the fallback is `Assert.Throws<AssertionException>` at that site under `#pragma warning disable RS0030`, with a one-line reason citing `testing.md:701` (P10).

### D-6 — Codemod plus hand edits

- **chosen:** `.build/.agents/nunit5-convert-asserts.ps1` rewrites expression-statement uses (172), and the 51 + 5 remaining sites are converted by hand under D-3 / D-4. The Release build (TO-1) is the gate for both.
- **rejected:** hand-editing all 224 — error-prone and unreviewable (AGENTS.md → *fix the loop*). A Roslyn rewriter — more machinery than a mechanical mapping needs.
- **why this:** the script's only judgment is "statement or not"; everything that needs judgment is routed to a human.
- **failure mode of the choice:** a mis-split argument list. Only a message string may follow the delegate (`Test-MessageArg`), anything else goes to manual, and the build catches the rest.

## P6 Edit-points

- E-1 `Directory.Packages.props` `Tests/Base/Parallelization/ResourceLaneDispatcher.cs` `Tests/Linq/Create/CreateData.cs` `Tests/Linq/Update/{BatchTests.cs,CreateTableTests.cs,CreateTempTableTests.cs,DeleteTests.cs,DynamicColumnsTests.cs,MergeTests.cs,OldMergeTests.cs,TruncateTableTests.cs}` — the NUnit 5.0.0 bump already on the branch (`[Order]` removal, `CancelRun()`, awaited async asserts); no further change except assertion conversions under E-3..E-16.
- E-2 `Tests/BannedSymbols.txt` — append the 52 generated full-signature bans (D-1, U-3), each with its replacement message. The `Throws` / `ThrowsAsync` message names the Shouldly fallback as `Shouldly.Should.Throw<T>` followed by `ShouldBeOfType<T>()` (D-3).
- E-3 `Tests/EntityFrameworkCore/Tests/{ManyToManyTests.cs,SqlTransparentExpressionTests.cs,ToolsTests.cs}` — convert banned calls (D-2..D-4).
- E-4 `Tests/Linq/Common/{ConvertTests.cs,EnumerableHelperTest.cs}` — convert banned calls.
- E-5 `Tests/Linq/Data/{InterceptorsTests.cs,RetryPolicyTest.cs}` — convert banned calls.
- E-6 `Tests/Linq/DataProvider/{AccessTests.cs,FirebirdTests.cs,MySqlTests.cs,OracleTests.cs,PostgreSQLTests.cs,SapHanaTests.cs,SqlServerTests.cs,UniqueParametersNormalizerTests.cs,YdbRetryPolicyTests.cs,YdbTests.cs}` — convert banned calls.
- E-7 `Tests/Linq/Exceptions/{AggregationTests.cs,CommonTests.cs,ConvertTests.cs,DmlTests.cs,ElementOperationTests.cs,InheritanceTests.cs,MappingTests.cs}` — convert banned calls.
- E-8 `Tests/Linq/Identity/IdentityStoreNegativeTests.cs` — Shouldly `NotThrowAsync` → `await` (D-4).
- E-9 `Tests/Linq/Infrastructure/{AssertQueryTests.cs,DataOptionsTests.cs}` — convert banned calls; `AssertQueryTests` per D-5, including its XML doc at lines 15-16, which says the failure is "observed through NUnit's `Assert.Throws`".
- E-10 `Tests/Linq/Linq/{AnalyticTests.cs,AssociationTests.cs,AsyncTests.cs,CompileTests.cs,CompileTestsAsync.cs,ConstantTests.cs,DataContextTests.cs,DynamicColumnsTests.cs,EagerLoadingStrategyKeyedQueryTests.cs,EagerLoadingStrategyUnionTests.cs,EnumMappingTests.cs,ExpressionsTests.cs,ExpressionTests.cs,GroupByTests.cs,GrpcDataContextTests.cs,IdlTests.cs,ImplicitCollectionLoadingTests.cs,InheritanceTests.cs,IsNullTests.SqlServer.cs,LoadWithTests.cs,MappingTests.cs,MinByMaxByMethodTests.cs,OrderByTests.cs,ParameterTests.cs,PreferClientCalculationTests.cs,QueryGenerationTests.cs,RemoteContextTests.cs,SelectTests.cs,StringFunctionTests.cs,StringJoinTests.cs,TagTests.cs,TakeSkipTests.cs,ValueConversionTests.cs,WindowFunctionsTests.Frame.cs}` — convert banned calls.
- E-11 `Tests/Linq/Mapping/DynamicStoreTests.cs` `Tests/Linq/Samples/ExceptionInterceptTests.cs` `Tests/Linq/Tools/EntityServices/IdentityMapTests.cs` `Tests/Linq/TypeMapping/MappingTests.cs` — convert banned calls.
- E-12 `Tests/Linq/Update/{BulkCopyTests.cs,DropTableTests.cs,InsertTests.cs,MergeTests.ApiParametersValidation.cs,MergeTests.CommandValidation.cs,MergeTests.Operations.Delete.cs,MergeTests.Operations.Insert.cs,MergeTests.Operations.Update.cs,MergeTests.Operations.UpdateWithDelete.cs,MergeTests.TargetSourceOn.cs,UpdateTests.cs}` — convert banned calls.
- E-13 `Tests/Linq/UserTests/{GenericsFilterTests.cs,Issue1084Tests.cs,Issue1174Tests.cs,Issue1313Tests.cs,Issue1351Tests.cs,Issue1721Tests.cs,Issue1736Tests.cs,Issue1925Tests.cs,Issue1964Tests.cs,Issue2033Tests.cs,Issue2474Tests.cs,Issue2588Tests.cs,Issue2602Tests.cs,Issue2769Tests.cs,Issue2856Tests.cs,Issue445Tests.cs,Issue5052Tests.cs,Issue5100Tests.cs,Issue5154Tests.cs,Issue792Tests.cs}` — convert banned calls.
- E-14 `.github/copilot-instructions.md` — add the exception-assertion rule next to the "Use Shouldly" line (39).
- E-15 corpus `.claude/AGENTS.md` (*Tests*: the Shouldly rule gains the exception-assertion carve-out) and `.claude/agents/test-writer.md` (the assertion rule) — corpus commit, not on this branch.
- E-16 corpus `.claude/docs/testing.md` (lines 5, 120, 701, 748, 1093-1104, 1134-1148, 1158-1165) and `.claude/docs/review-rubric/rubric-tests.md:68` — rewrite the prose that teaches banned forms — corpus commit, not on this branch.

## P7 Impact map (M/L)

- Banned-form call sites — searched `git grep -E 'Assert\.(Throws|ThrowsAsync|Catch|CatchAsync|DoesNotThrow|DoesNotThrowAsync)\b|Should\.NotThrow|ShouldNotThrow' -- '*.cs' '*.fs' '*.vb' '*.tt' '*.ttinclude'` over the worktree: 229 hits in 96 files, all under `Tests/Linq` and `Tests/EntityFrameworkCore` — covered by E-3, E-4, E-5, E-6, E-7, E-8, E-9, E-10, E-11, E-12, E-13
- Test projects that drop `Tests/BannedSymbols.txt` (`Tests.Wasm.App.csproj:65`, `Tests.SingleFile.csproj:33`, `Tests.FpuJit.csproj:37`, `Tests.Analyzers.Internal.csproj:40`, `Tests.Analyzers.csproj:41`) — searched `BannedSymbols` across `*.{props,targets,csproj}`; no banned-form site in any of them, so the ban's hole there covers nothing today — out-of-scope
- `Tests/Base` helpers wrapping a banned call (an infrastructure method every test would inherit) — searched the same pattern over `Tests/Base`: no hits — out-of-scope
- `AssertQueryTests.cs` asserts `AssertionException` from `AssertQuery`, relying on `Assert.Throws` isolation (`testing.md:701`) — covered by E-9
- `Tests.Should` shadowing `Shouldly.Should` (`Tests/Base/Should.cs`) — the D-3 fallback must be fully qualified — covered by E-3, E-10, E-12, E-13
- Corpus prose teaching a banned form — searched the same pattern over `.claude/` (excluding `knowledge-base/`) and every repo `*.md`: `testing.md:5,120,701,748,1104,1134-1148,1160-1165`, `review-rubric/rubric-tests.md:68`; `.github/copilot-instructions.md:39` carries "Use Shouldly … instead of NUnit Assert" — covered by E-14, E-15, E-16
- `testing.md:120` uses `Assert.Throws<T>` only as an example of a passing test whose expected exception fired — covered by E-16 (reworded to the new form)
- Historical plans and gap ledgers naming banned forms (`plans/issue-6181…`, `issue-6099…`, `issue-5879…`, `issue-5788…`, `fix-lambda-parameter-binding-cache/gaps.md`, `feature-access-libred/gaps.md`) and the KB (`areas/TESTS-LINQ/INDEX.md`, `DI-0512`, `DI-0517`) — records, not guidance — out-of-scope
- `test-writer.md` — searched `Throw|Shouldly`: no hits, so it teaches no assertion form today; E-15 adds the rule there — covered by E-15
- `Assert.That(…, Throws…)` sites already in the tree (~45) — they are the target form; no change — out-of-scope
- Existing Shouldly `Should.Throw*` (35) / `ShouldThrow*` (98) sites — allowed by D-3; no change — out-of-scope

## P8 Test obligations (M/L)

- TO-1 Add E-2's bans to the unconverted tree and run Release builds of `Tests/Linq/Tests.csproj` (`-f net10.0`, then `-f net462` for the `#if NETFRAMEWORK` branch at `MappingTests.cs:445-449` and `#if !NETFRAMEWORK` at `StringFunctionTests.cs:64-65`), `Tests/EntityFrameworkCore/Tests.EntityFrameworkCore.EF10.csproj` (net10.0) and `Tests/EntityFrameworkCore/Tests.EntityFrameworkCore.EF3.csproj` (net462): expected RS0030 at every site the census found (red); after conversion, zero RS0030 and a clean build (green). `Tests.EntityFrameworkCore.EF11.csproj` (net11.0) compiles the same three files and is left to CI — providers: none (build) — proof: red→green
- TO-2 Re-insert one `Assert.Throws<InvalidOperationException>(…)` and one `Shouldly.Should.NotThrow(…)` into a converted file, run the Release build: RS0030 with the replacement message; remove them: clean — providers: none (build) — proof: control (mutation: the re-inserted calls)
- TO-3 Probe project `.build/.agents/nunit5-probe2` (NUnit 5.0.0, real test context) measures each mapping: `Throws.TypeOf<ArgumentException>` against `ArgumentNullException` fails, `Throws.InstanceOf` and `Throws.Exception` pass, `Assert.ThatAsync` with a quiet delegate or a wrong message fails, and sync `Assert.That` over an async lambda behaves as U-1 records — providers: none (probe) — proof: control (each MUSTFAIL case is the mutation)
- TO-3b Shouldly arm, same probe project, class `ShouldlyExactness`: `Shouldly.Should.Throw<ArgumentException>` over a thrown `ArgumentNullException` passes on its own (the loosening), and fails once followed by `ShouldBeOfType<ArgumentException>()` (`ShouldThrow_ShouldBeOfType_Subclass_MUSTFAIL`); an exact `ArgumentException` passes both — providers: none (probe) — proof: control (mutation: the subclass thrown)
- TO-3c For each of the 14 exact-type sites in D-3, change the asserted type in the converted constraint to its base type (`Exception`) and confirm the test fails on its provider set; revert. 11 of the 14 sites are reachable locally. The other three are not: `WindowFunctionsTests.Frame.cs:300` (`AllMySql80` only, `:291`), `ToolsTests.cs:821` (EF SQL Server `.MS` only) and `MappingTests.cs:446` (`#if NETFRAMEWORK`, NETFX bucket empty). They get read-only verification instead (P10) — providers: per site (SQLite.MS, SqlServer.2022 locally) — proof: control (mutation: base type asserted)
- TO-4 `AssertQueryTests` after conversion: all pass; then make one asserted helper call pass (swap the deliberately wrong expectation for a correct one) and the test must go red. Do it on both delegate shapes: `:32` (`Func<T[]>`, the one `[DataSources]` test, `:25`) and one provider-less `Action` site — providers: SQLite.MS for `:32`; none for the provider-less tests — proof: control (mutation: the corrected expectation)
- TO-5 Run every E-3..E-13 fixture filtered on net10.0, comparing against the same filter at `7a2eefb84`: no test changes from pass to fail. Both runs pass an explicit `--provider SQLite.MS,SQLite.Classic,DuckDB,SqlServer.2022` list: NET100 also enables PostgreSQL.16, SqlServer.2025 and YDB, which have no running container. Before the baseline run, confirm SqlServer.2022 connects to the `sql2022` container. SqlServer.2022 reaches the `MergeDataContextSource` fixtures, which exclude `AllSQLite` (`MergeDataContextSourceAttribute.cs:12-22`). That covers 11 of the 15 hand-converted `Assert.Catch` sites in `MergeTests.Operations.*` / `MergeTests.TargetSourceOn.cs`; the other four are Oracle-only (`MergeTests.Operations.UpdateWithDelete.cs:661,688,715,736`). NETFX has no provider enabled locally, so net462 is build-only (TO-1). Before the local run, record each hand-converted site's data-source attribute in G-01, and list every site no local provider reaches. CI `/azp run test-all` on the pushed head is the only instrument for them. Known so far: the four Oracle Merge sites, `WindowFunctionsTests.Frame.cs:300` (`AllMySql80`), the provider fixtures in E-6 other than `SqlServerTests`, `ToolsTests.cs:821` (EF runs SQL Server `.MS` variants only, none enabled locally), and every net462 / net11.0 run — providers: SQLite.MS, SQLite.Classic, DuckDB, SqlServer.2022 locally; all on CI — proof: characterization (it proves no behaviour change, not new behaviour)
- TO-6 After E-14..E-16, re-run P7's prose search over `.claude/docs`, `.claude/agents`, `.claude/skills`, `.claude/AGENTS.md` and `.github/copilot-instructions.md`: every remaining hit names a banned form as banned, never as a recommendation — providers: none (grep) — proof: characterization

## P9 Verification gates

- G-01: pass (local), CI pending —
  - TO-1 red: `dotnet build Tests/Linq/Tests.csproj -c Release -f net10.0` with E-2 on the unconverted tree → 221 distinct RS0030 sites, no other error kind. That is the 224-hit census minus the XML doc at `AssertQueryTests.cs:15` and the two `#if NETFRAMEWORK` sites (`MappingTests.cs:446`, `MergeTests.CommandValidation.cs:34`).
  - TO-1 green: after conversion, Release builds are clean (0 warnings, 0 errors) for `Tests/Linq` net10.0 and net462, `Tests.EntityFrameworkCore.EF10` and `EF3`. EF11 is left to CI.
  - TO-2: the TO-1 red run is the re-inserted-call control at scale. All 442 RS0030 lines in `nunit5-to1-red-net10.log` carry the replacement message, e.g. "The symbol 'Assert.Throws<TExpected>(Action)' is banned in this project: Use Assert.That(code, Throws.TypeOf<T>()) …". The green run after conversion is the removal arm.
  - TO-3: red mutants in probe2 `run.log` / `run2.log`: `That_TypeOf_Derived_MUSTFAIL`, `ThatAsync_Quiet_MUSTFAIL`, `ThatAsync_WrongMessage_MUSTFAIL`, `SyncThat_AsyncLambda_Quiet_MUSTFAIL`, `SyncThat_TaskLambda_Quiet_MUSTFAIL` and `MultipleScope_TwoFailures_MUSTFAIL_WITH_2` each failed, and the matching positive cases passed.
  - TO-3b: red mutant in probe2 `run2.log`: `ShouldThrow_ShouldBeOfType_Subclass_MUSTFAIL` failed; `ShouldThrow_AcceptsSubclass` and `ShouldThrow_ShouldBeOfType_Exact` passed.
  - TO-3c + TO-4 + the gRPC inner checks: `.build/.agents/nunit5-mutate.ps1` applied 13 patterns to 15 sites and rebuilt (0 errors). The SQLite.MS run (`nunit5-mutated.json`: 58 total, 20 failed, 28 passed, 10 skipped) failed every mutated test: `CompiledLoadWithInferredResultTest`, `WrapperWithCapturedValueArgumentIsNotSupportedTest`, `Implicit_Select_Collection_Throws`, `GlobalDefaultStrategy_Plus_Option_StillThrows`, `Issue5540Test2`, `ColumnMappingException1`/`2` (direct + LinqService), `AsValueInsertableEmptyTest`, `AsUpdatableEmptyTest` (direct + LinqService), `SignalRTestContextClientStopsAtDispose`, `CancelledQueryThrowsOperationCanceled`, `CancelledTokenThrowsOperationCanceled`, `ScalarQuery_WrongValues_Fails` (direct + LinqService), `String_SameLengthDifferentValue_Fails`. The one unpredicted failure, `TimeoutStaysRpcException`, failed at `released.ShouldBeTrue("the server query was not cancelled")`, not at its exception assertion; it is unmutated and passed in the unmutated run. Files restored; no mutation marker remains in `git diff`.
  - TO-5 (A-1): SQLite.MS (`nunit5-to5-sqlite.json`: 196 total, 183 passed, 10 skipped, 3 failed, the 3 gRPC sites fixed by A-2) → `GrpcDataContextTests` re-run (`nunit5-to5-grpc.json`: 15 total, 8 passed, 7 skipped, 0 failed). SqlServer.2022, Merge + `ReplaceTableTest` (`nunit5-to5-sql2022.json`: 25 total, 25 passed). CI test-all pending.
  - Post-merge and post-restore: Release `Tests/Linq` net10.0 on the merged tree is clean (`nunit5-build-merged.log`, then `nunit5-build-final.log` with the round-3 edits). The gRPC, remote, TO-3c, `AssertQueryTests` and `Issue1925Tests` methods were run three times on SQLite.MS against the restored tree (`nunit5-final-{1,2,3}.json`: 58 total each; failed 1 / 0 / 1). `TimeoutStaysRpcException` passed all three. The only failure was `GrpcDataContextTests.ContextReusesItsChannel` on `SQLite.MS.LinqService`, in runs 1 and 3: "GrpcServerConnections.Accepted - before should be 3 but was 2". That test is untouched by this branch (`git diff 7a2eefb84` hunks are at `:138`, `:178`, `:208`, `:247`, while it sits at `:73`), and it passed in the 196-test run. It is unattributed locally (no base-commit build); CI test-all [25691](https://dev.azure.com/linq2db/linq2db/_build/results?buildId=25691) / GitHub [43661416061](https://github.com/linq2db/linq2db/actions/runs/43661416061) decides.
  - TO-5 reach: hand-converted sites no local run reaches, so CI test-all is their only instrument:
    - `Issue792Tests.cs:143,163` (MySQL)
    - `WindowFunctionsTests.Frame.cs:300` (`AllMySql80`)
    - `MergeTests.Operations.UpdateWithDelete.cs:668,695,722,743` (`AllOracle`)
    - `MappingTests.cs:446` and `MergeTests.CommandValidation.cs:34` (`#if NETFRAMEWORK`)
    - `Issue1925Tests.cs:74,77` (`AllAccessLibRed`, arrived with the master merge)
    - `BulkCopyTests.cs:256` (Firebird branch)
    - `ToolsTests.cs:821` and `ManyToManyTests.cs:236` (EF projects, not in the `Tests/Linq` run)
    - every net462 / net11.0 run
  - Every other hand-converted site ran locally on SQLite.MS or SqlServer.2022.
  - TO-6: the P7 prose search over `.claude/{docs,agents,skills}`, `.claude/AGENTS.md` and `.github/copilot-instructions.md` → every hit names a banned form as banned or historical.
  - `test-diff-sweep.ps1 -IncludeWorkingTree`: 51 one-line chains and 26 nested chains, mostly on converted lines (delegate kept as written, constraint chain on one line, per P3); 4 narrowed sets without a reason, all on pre-existing tests the bump commit's hunks touch, none an assertion converted here.
- G-02: — (pending) assertion rewrites move no SQL; confirm the CI test-all run leaves the baselines PR with no `.sql` change from this delta
- G-06: pass — only converted calls change. Exceptions: the stale comment removed at `CommonTests.cs:89`; the moved comment at `CompileTests.cs:805`; the dropped label at `Issue5052Tests.cs:111` ("Projection should not throw an exception.", which restated the call)
- G-07: pass — no `Tests/Tests.Playground` file in `git status`
- G-09: — (pending) adversarial read of the diff before the PR leaves draft

## P10 Adjudicated (M/L)

- The ban does not reach the five test projects that drop `Tests/BannedSymbols.txt` (P7 row 2). None of them has a site today; extending the ban to them would mean re-adding the file to projects that removed it for their own reasons.
- Existing Shouldly `Should.Throw*` / `ShouldThrow*` sites are not converted to the constraint form (maintainer's call, 2026-11-14: Shouldly stays the fallback).
- The 51 one-line and 26 nested chains `test-diff-sweep.ps1` reports on converted lines stay as written (maintainer's call, 2026-11-15). Each delegate is kept as authored, with the constraint on one line, per P3 "only the converted call is reformatted". This is not a review finding on this PR.
- TO-3c's base-type mutation cannot run locally for `WindowFunctionsTests.Frame.cs:300` (MySQL 8), `ToolsTests.cs:821` (EF SQL Server `.MS`) or `MappingTests.cs:446` (net462). Accepted: their verification is a read of the converted chain against the original assertions plus CI test-all green. Starting a MySQL 8 container or enabling NETFX providers is not worth it for three mechanical rewrites whose chain shapes probe2 has measured.
- U-2 / D-5 isolation was probed on net10.0 only; `AssertQueryTests` also runs on net462 in CI. A divergence there falls under the pragma fallback below.
- A-2's rewritten gRPC chains have 2 of their 5 clauses mutated (the `StatusCode` at `GrpcDataContextTests.cs:146` and the token at `:183`). Accepted: the mutated failure text ("… and property InnerException <Grpc.Core.RpcException> and property InnerException property StatusCode equal to Unknown / But was: Cancelled") shows each `.And` clause applies where intended, and TO-3 measured the `TypeOf` clause generically.
- Shouldly's sync-over-Task overloads (`Should.Throw<T>(Func<Task>)`, `funcTask.ShouldThrow<T>()`) were not probed on a `Canceled` task. No site in the tree uses them near a cancellation exception (`git grep -E 'Should\.Throw|ShouldThrow' -- Tests`, critic round 3), and the A-2 rule names the constraint form for any cancellation test.
- If TO-4 shows the constraint form failing an `AssertQueryTests` outer test despite U-2, that site keeps `Assert.Throws<AssertionException>` under a scoped `#pragma warning disable RS0030` with a reason line citing `testing.md:701`. That is the only sanctioned pragma for this ban.
- The ban lists full signatures (U-3), so an overload added by a later NUnit or Shouldly version escapes it until the list is regenerated. Accepted: a parameterless ID bans nothing, and a custom analyzer is more machinery than the risk warrants.

## P11 Amendments (M/L)

- A-1 (2026-11-14, local test budget) — TO-5's local half is narrowed to the test methods that contain a hand-converted site (D-3 / D-4), on SQLite.MS, with SqlServer.2022 for the 11 `MergeDataContextSource` sites. That fits the standing ≤1000-tests-per-local-run rule. Whole fixtures and the before/after comparison over every converted fixture go to CI test-all. An auto-converted site is a pure mapping whose semantics TO-3 measured, and whose compilation TO-1 proves. A failing local method is compared against the same method at `7a2eefb84` before it is attributed. No E-n changes; approval stands.
  re-derives: P8 (TO-5)
  conventions: `testing.md` → *Test layout* and *A narrowed provider set is a claim* were embedded at authoring (step 4). A-1 adds no test code; the branch's test diff was swept with `test-diff-sweep.ps1 -IncludeWorkingTree`, and the counts are in G-01.
- A-2 (2026-11-14, TO-5 red) — D-3's Shouldly fallback is unsafe for cancellation tests. The first TO-5 run on SQLite.MS (`nunit5-to5-sqlite.json`: 196 total, 183 passed, 10 skipped, 3 failed) failed `GrpcDataContextTests.CancelledBatchIsNotCommitted`, `CancelledQueryThrowsOperationCanceled` and `CancelledTokenThrowsOperationCanceled` on `SQLite.MS.LinqService`, all at `ShouldBeOfType<OperationCanceledException>`: "but was System.Threading.Tasks.TaskCanceledException".
  - Measured in probe2 `CancelledTaskTests` (`run5.log`, 7 tests, 1 failed): for a task in the `Canceled` state, `await` and `Assert.ThatAsync(…, Throws.TypeOf<OperationCanceledException>())` surface the original `OperationCanceledException`, while `Shouldly.Should.ThrowAsync<Exception>` returns a new `TaskCanceledException` (`CanceledState_Shouldly` failed). A Faulted task is unaffected (`ShouldlyThrowAsync_Type` passed).
  - D-3 gains a clause: never `ThrowAsync` for a cancellation test. The three gRPC sites go to the constraint form: `.With.Property(nameof(OperationCanceledException.CancellationToken)).EqualTo(cts.Token)`, plus `.And.InnerException.TypeOf<RpcException>()` / `.And.InnerException.Property(nameof(RpcException.StatusCode)).EqualTo(StatusCode.Cancelled)` where the original checked the inner exception.
  - `testing.md` line 5 and `test-writer.md` state the rule. No E-n changes (same files); the D-3 wording changes, so its approval is re-earned at the user's review of the diff.
  re-derives: P5 (D-3), P8 (TO-3c, TO-5)
  conventions: `testing.md` → *Test layout* (one call per line) applied to the three rewritten gRPC chains, one constraint clause per line. The same `test-diff-sweep.ps1 -IncludeWorkingTree` sweep covered them (counts in G-01).
  class: `Should\.ThrowAsync|ShouldThrowAsync` over `Tests/` (worktree, post-change). Of the two sites this diff adds, both are faulted tasks: `GrpcDataContextTests.cs:209` (`RpcException` on timeout) and `RemoteContextTests.cs:567` (connection refused); both passed in TO-5. The one pre-existing cancellation test, `Tests/LinqToDB.CLI/QueryCommandTests.cs:626`, uses `ThrowAsync<OperationCanceledException>`, which accepts the replacing `TaskCanceledException` subclass. It is not broken and is out of scope. The other pre-existing `ThrowAsync` sites assert non-cancellation exceptions.

## P12 Critic verdict (M/L)

**Current verdict: weak**

**Round 3 (fable, delta on A-1, A-2) — weak.** A-2's root cause (the TO-5 red, the `run5.log` Canceled-vs-Faulted probe, a green re-run, and the mutated failure text) and A-1's narrowing hold. The critic re-read all four TO-5 / mutation JSONs, `run5.log`, `nunit5-mutate.ps1` and the TRX durations, and checked that the auto-converted cancellation sites (`AsyncTests.cs:267-286`, `CompileTestsAsync.cs:875-899`) have the measured-safe `ThatAsync` shape. Objections and responses:
- weak — G-01 was stale against the merged tree (two banned calls arrived from master at `Issue1925Tests.cs:74,77`; no completed post-merge build) → those sites are converted; a post-merge Release build plus a restored-tree re-run of the gRPC / remote / TO-3c methods follow (G-01 updated after they report); the two sites are in the TO-5 reach list.
- weak — no test run after the mutation restore → covered by that re-run.
- weak — the `TimeoutStaysRpcException` attribution was unprobed → the re-run repeats it; the critic's TRX evidence shows the whole remote host 15-60x slower in the mutated run.
- weak — A-2's rule was missing from the `ThrowsAsync` / `CatchAsync` ban messages and from `copilot-instructions.md` → both now carry the cancellation clause.
- weak — `GrpcDataContextTests.cs:209` (`TimeoutStaysRpcException`) stayed on Shouldly `ThrowAsync` in a cancellation-themed test → moved to the constraint form.
- weak — A-2's chains have 2 of 5 clauses mutated → accepted in P10, with the failure-text evidence.
- lead — Shouldly's sync-over-Task overloads were unprobed → P10 line (no such site).
- weak — TO-5's per-site reach record was absent → added to G-01.
- nit — "16 sites" → 15; D-3's P5 block now carries the A-2 clause.

**Round 2 (fable, delta) — weak.** The round-1 refutation is resolved: all 14 exact-type sites go to the constraint form, and U-2 / D-5 hold on the measured probe (the critic read `run2.log`: 25 total, 7 failed, all `*_MUSTFAIL`). The critic re-derived the 44 result-used sites and the 14 exact-type sites one for one, read each with its follow-up assertions and data-source attribute, and checked the 15 Merge `Assert.Catch` sites against `MergeDataContextSourceAttribute.cs`. Objections, all folded in:
- weak — TO-5 claimed SqlServer.2022 covers 15 Merge sites; it covers 11, because 4 are `[IncludeDataSources(true, TestProvName.AllOracle)]` → corrected. The CI-only list is now built per site from data-source attributes, recorded in G-01 before the local run.
- weak — TO-3c's mutation cannot run for 3 sites (MySQL 8, EF SQL Server `.MS`, net462) → named in TO-3c; read-only verification accepted in P10.
- lead → measured: `.And.Contains(b)` returns to the exception (probe2 `ChainTests`) → D-3's chain rule repeats `.Message`, and `CompileTests.cs:805` is corrected.
- lead → measured: Shouldly `ShouldContain` ignores case by default → `.IgnoreCase` at `ImplicitCollectionLoadingTests.cs:40,141` and `WindowFunctionsTests.Frame.cs:300`, and D-3's case-preservation rule.
- minor — `MappingTests.cs:466` asserts `"lastname"` → corrected; `MappingTests.cs` qualified as `Tests/Linq/Linq/`.
- nit — TO-4 provider wording → corrected (`[DataSources]` at `:25`, both delegate shapes).
- unverified — the SqlServer.2022 connection, and PostgreSQL.16 / SqlServer.2025 / YDB having no container → TO-5 now passes an explicit `--provider` list and checks the connection first.
- note — isolation probed on net10.0 only → P10 line.

Not re-sent: the round cap is one revision after `refuted`. The two leads were settled by measurement, and the rest are text corrections the critic itself prescribed.

**Round 1 (fable) — refuted.** Narrow: D-3's Shouldly fallback loosened exact-type checks, against P3 and SC-3. The critic independently re-counted the census (96 files, 172 / 51 / 5), found no `#if`, static-import, `ClassicAssert` or `Throws.Nothing` escape, confirmed the doc census and U-1 / U-4 / U-5 / U-8 / U-9, and read probe2's `run.log` and probe3's `build.log`. Objections and responses:
- refuted — `Shouldly.Should.Throw<T>` accepts subclasses, so 14 exact-type result-used sites would loosen → D-3 now requires `ShouldBeOfType<T>()` after an exact-type Shouldly fallback; all 14 sites were read and dispositioned to the constraint form; TO-3b (probe, measured: `ShouldThrow_AcceptsSubclass` passes, `ShouldThrow_ShouldBeOfType_Subclass_MUSTFAIL` fails) and TO-3c (base-type mutation per site) added; the E-2 message states the rule.
- weak — U-2 never probed the value-returning `Func<T>` shape `AssertQuery<T>` binds → probed (U-2 round 2: isolates); D-5 / P10 now name the pragma fallback if TO-4 disagrees.
- weak — a SQLite-only TO-5 cannot reach the Merge or provider fixtures → TO-5 adds SqlServer.2022 (container up), which reaches `MergeDataContextSource`; it names the sites CI alone covers.
- minor — TO-1 named a directory of three EF projects → it now names EF10 and EF3, and leaves EF11 (net11.0) to CI.
- minor — `AssertQueryTests.cs:15-16` XML doc → added to E-9.
- minor — `testing.md:120` missing from E-16 → added.
- nit — the codemod hard-codes CRLF → the target files are `attr/text eol=crlf` (`git ls-files --eol`), so CRLF matches; no change.
