# Work plan: issue-6099-fix-scalar-assertquery-comparer — AssertQuery default comparer for scalar and collection element types

**Tier:** M  ·  **Status:** approved  ·  **Approved-at:** 2026-10-24  ·  **Branch:** issue/6099-fix-scalar-assertquery-comparer
**Schema:** `.claude/docs/work-plan.md`  ·  **Gates:** `.claude/docs/definition-of-done.md`

## P1 Problem

[#6099](https://github.com/linq2db/linq2db/issues/6099). When no comparer is passed, test infrastructure falls back to `ComparerBuilder.GetEqualityComparer<T>()` (`Tests/Base/TestBase.AssertQuery.cs:521`, `:295`; `Tests/Base/TestBase.Asserts.cs:55`; `Tests/EntityFrameworkCore/TestBase.cs:109`), which compares `T`'s public instance members (`TypeAccessor<T>`, `Source/LinqToDB/Reflection/TypeAccessor{T}.cs:17-24`). Falsifiable symptoms:

- `T` with zero members (`int`, `long`, `double`, `bool`, `Guid`, `object`; reasoned, measured by TO-3's pre-fix run): `CreateEqualsFunc` reduces to `DefaultIfEmpty(True)` (`Source/LinqToDB.Tools/Comparers/ComparerBuilder.cs:201-202`), so every pair is equal. `AreEqualWithComparer(new[] { 1 }, new[] { 2 })` passes today. `AreEqual` (`TestBase.Asserts.cs:112`) then checks only the count.
- `string`: compared by `Length` only. `AreEqualWithComparer(new[] { "ab" }, new[] { "cd" })` passes today.
- `decimal` (net7+): `Scale` is a member, so `2.5m` vs `2.50m` is unequal. `MathFunctionTests.ByValue` (`Tests/Linq/Linq/MathFunctionTests.cs:401`) is a workaround for this. On net462 `decimal` has no `Scale` and is a zero-member type, so every pair is equal there.
- A collection `T` (`byte[]`, `List<E>`, `E[]`) gives a false *red* (critic round 2): its members include `SyncRoot` (`Array.SyncRoot` returns `this`; `List<T>` via explicit `ICollection.SyncRoot`, `TypeAccessor{T}.cs:71-79`), which is compared with `EqualityComparer<object>.Default`. So distinct instances never compare equal, and no default-comparer collection-`T` assertion can pass today.
- Not broken (critic, read from `Source/LinqToDB/Internal/Extensions/ReflectionExtensions.cs:27-28`): `Nullable<U>` is compared via `HasValue`/`Value`, and an enum via its public instance field `value__`. Both already compare by value on net8+. On netfx, `decimal?` still hits the `decimal.GetHashCode` scale bug inside `Except`.
- Set-op remap (`TestBase.AssertQuery.cs:295`): the expected side of a scalar `Union`/`Except`/`ExceptAll`/`IntersectAll` runs in memory with the all-equal comparer and hash. A scalar `Union` collapses the expected rows to one.

## P2 Success criteria

- SC-1 A scalar `AssertQuery` whose DB values differ from the in-memory values (same row count) fails.  → TO-1
- SC-2 A scalar `Union` under `AssertQuery` keeps distinct expected rows (no collapse to one).  → TO-2
- SC-3 The default comparer for zero-member scalars and `string` distinguishes unequal values; enums and `Nullable<scalar>` keep distinguishing them; equal values stay equal.  → TO-3, TO-4, TO-5, TO-6
- SC-4 `decimal` / `decimal?` compare by value: `2.5m` equals `2.50m`, and the hashes agree (netfx included).  → TO-7
- SC-5 A collection `T` (`byte[]`, `int[]`, `List<int>`) compares element-wise and order-sensitively.  → TO-8
- SC-6 A `T` with members (entities, anonymous types, `DateTime`) keeps the `ComparerBuilder` member comparison.  → TO-9, TO-10

## P3 Constraints & anti-goals (M/L)

- No change under `Source/` and no public `LinqToDB.Tools` API change. `ComparerBuilderTests.NoMemberTest` (`Tests/Linq/Tools/ComparerBuilderTests.cs:183`) pins "no members → equal" as the `ComparerBuilder` contract.
- An explicitly passed comparer always wins. Only the null-comparer fallback changes.
- Existing workarounds stay untouched (`MathFunctionTests.ByValue`/`ByNullableValue`, `PreferClientCalculationTests.AssertScalarQuery`, `Issue5916Tests.Structural`). They become redundant but not wrong, and removing them is unrelated cleanup.
- No SQL or baseline change. This affects comparison only.

## P4 Unknowns (M/L)

- U-1 Which scalars have zero `TypeAccessor` members — resolved-by design + probe: the predicate *is* "zero members" (plus explicit `string`/`decimal`), so the routing is by construction. Enums have one member (`value__`, critic) and stay on the member path, which already compares by value. The pre-fix run of TO-3…TO-8 is the measurement: each arm's actual pre-fix result gets recorded in G-01, and any arm labelled `red→green` that is green pre-fix is relabelled `characterization` before commit.
- U-8 Can a test assert that an NUnit assertion failed? — resolved-by probe (ilspycmd on NUnit 4.6.1 `NUnit.Framework.Assert` / `TestExecutionContext`): `Assert.Throws(…, Action)` runs `code()` inside `new TestExecutionContext.IsolatedContext()`, whose `CreateIsolatedContext` gives the delegate a fresh `CurrentResult = CurrentTest.MakeTestResult()`, so the failure recorded by `Assert.ReportFailure` is discarded on dispose. Shouldly's `Should.Throw` has no such isolation, so the recorded failure would persist (critic objection 1, correct for that API). The negative obligations therefore use NUnit `Assert.Throws<AssertionException>`. This is a deliberate exception to "Shouldly over Assert", and the only API that works here.
- U-2 Does the in-memory side of `AssertQuery` run a `[Sql.Expression]` method's CLR body while the DB runs its SQL? — resolved-by probe at TO-1. Reasoned, unprobed: `RemapMethod` (`TestBase.AssertQuery.cs:284`) handles only set ops and joins, so a user static method stays a call. If TO-1's two arms agree, TO-1 cannot fail, and the plan is amended to another divergence source before implementation proceeds.
- U-3 Does any current call site rely on the default comparer with a collection `T`? — resolved-by scout + U-5: a text sweep found one explicit collection-`T` site, `SetOperatorComplexTests.cs:473` (`Dictionary<string,string>`, with an explicit `DictionaryEqualityComparer`). A grep cannot see an inferred collection `T`, so "none found" means the corpus visibly doesn't exercise it, not that there is no site. CI (U-5) is the real resolution. There are 973 `AssertQuery(` calls in 64 files, all under `Tests/Linq`.
- U-4 Ordered or unordered element comparison for a collection `T` — resolved-by decision D-2.
- U-5 Which currently-green tests turn red — resolved-by user answer: CI `test-all` after push, since a full local run exceeds the 1000-test local cap. Each red is triaged per D-4 and recorded as an `A-n`.
- U-6 netfx `decimal.GetHashCode` gives `2.5m`/`2.50m` different hashes — resolved-by code: `TestBase.DecimalComparerInstance` (`TestBase.Asserts.cs:26-41`) already handles it. `decimal?` needs a nullable wrapper around it.
- U-7 `object` `T` (zero members) moves from all-equal to `object.Equals` — resolved-by scout: `Issue5916Tests.Structural` (`Tests/Linq/UserTests/Issue5916Tests.cs:18`) already makes exactly this choice explicitly. Any other `object`-`T` call site without a comparer is fallout per U-5.

## P5 Decisions (M/L)

### D-1 — Scalar predicate

- **chosen:** after unwrapping `Nullable<U>`: `U` is `string` or `decimal`, or `TypeAccessor.GetAccessor(U).Members.Count == 0`. Then use `EqualityComparer<U>.Default`, except `decimal` → `TestBase.DecimalComparerInstance`, and `Nullable<U>` → a null-aware wrapper over `U`'s comparer, applied **only when `U` itself satisfies this predicate**. A member-bearing `U` (`DateTime?`, `DateTimeOffset?`) falls through to `ComparerBuilder.GetEqualityComparer<T>()` unchanged: today that is `HasValue`/`Value`, compared Kind-/Offset-insensitively, and TO-10 pins it.
- **rejected:** `MappingSchema.IsScalarType` — it admits `byte[]` and date types and depends on schema state. A hard-coded primitive list — misses `Guid`, enums and `object`, and drifts.
- **why this:** it fixes exactly the types where member comparison is wrong (vacuous, or `Length`/`Scale` instead of value) and leaves every type whose members do express the value.
- **failure mode of the choice:** a struct with members that don't express equality is still compared by members. Date types are left on purpose: `DateTime` members include `Kind`, `DateTimeOffset`'s include `Offset`, and `EqualityComparer<T>.Default` would ignore both, so switching would loosen today's comparison.

### D-2 — Collection `T`

- **chosen:** a non-`string` `T` implementing `IEnumerable<E>` → an order-sensitive element-wise comparer whose element comparer is this same helper applied to `E`. It is null-aware, and its hash combines element hashes in order.
- **rejected:** order-insensitive (multiset) — differs from `ComparerBuilder`'s own member-level `EnumerableEqualityComparer` (`SequenceEqual`, `Source/LinqToDB.Tools/Comparers/EnumerableEqualityComparer`1.cs:38`). Reusing that class — it is internal, and `LinqToDB.Tools` has no `InternalsVisibleTo` (scout).
- **why this:** the user asked for it to be included, and it matches the existing member-level semantics.
- **failure mode of the choice:** element order inside a collection `T` (e.g. unordered eager-loaded children) could go red without a real defect. No call site can depend on today's default here, because a default-comparer collection `T` always fails today (P1, `SyncRoot`), which is why the only such site, `SetOperatorComplexTests.cs:473`, passes its own comparer. `IGrouping<K,E>` is an `IEnumerable<E>`, so a bare grouping `T` would drop `Key` and compare an unordered group in order. This is unreachable today: both `AssertQuery(…GroupBy(` hits (`Tests/Linq/Linq/BooleanTests.cs:145,460`) project to anonymous types. A non-generic `IEnumerable` (`BitArray`) keeps the member comparer.

### D-3 — One shared static helper

- **chosen:** a new `Tests/Base/TestComparers.cs`: `public static class TestComparers` with `GetDefault<T>()` and `GetDefault(Type)`. The cache is a static generic holder (`static class Cache<T> { internal static readonly IEqualityComparer<T> Instance = Create<T>(); }`), so the CLR's type initialisation makes it thread-safe across parallel test lanes. `GetDefault(Type)` reflects into `GetDefault<T>()`. Called from all four fallback sites.
- **rejected:** a `TestBase` instance method — `LinqToDB.EntityFrameworkCore.Tests.TestBase` (`Tests/EntityFrameworkCore/TestBase.cs:32`) does not derive from `Tests.TestBase`.
- **why this:** one definition for four sites. The non-generic overload serves `SetOperationRemap`, which only has a `Type`.
- **failure mode of the choice:** none beyond D-1/D-2.

### D-4 — Fallout triage rule

- **chosen:** each CI red caused by this change is one of three kinds. (a) A wrong value is a product defect: file an issue and gate the test with `[ActiveIssue]` on that issue, keeping the fix on its own branch per AGENTS.md. (b) A DB-vs-memory representation difference (precision, padding, scale) gets an explicit comparer or a normalising projection in that test. (c) A zero-member reference `T` (`object` holding entity instances, a member-less class) that moved from vacuous equality to reference equality gets an explicit structural comparer (`ComparerBuilder.GetEqualityComparer` on the runtime type) or a projection to a value-typed shape. Each one is recorded as an `A-n` with its `E-n`.
- **rejected:** loosening the helper to make reds disappear — that re-hides the defect class this issue is about.
- **why this:** the issue expects reds, and each one is either a hidden bug or a test that never checked values.
- **failure mode of the choice:** a large fallout set makes the PR wide. If it exceeds about 15 tests, stop and ask about splitting.

## P6 Edit-points

- E-1 `Tests/Base/TestComparers.cs` (new) — `TestComparers.GetDefault<T>()` / `GetDefault(Type)` per D-1/D-2/D-3, plus private nullable and sequence comparers.
- E-2 `Tests/Base/TestBase.AssertQuery.cs:AssertQuery` — `comparer ??= TestComparers.GetDefault<T>();` (line 521).
- E-3 `Tests/Base/TestBase.AssertQuery.cs:RemapMethod.SetOperationRemap` — `ComparerBuilder.GetEqualityComparer(elementType)` → `TestComparers.GetDefault(elementType)` (line 295).
- E-4 `Tests/Base/TestBase.Asserts.cs:AreEqualWithComparer<T>(expected, result)` — default comparer via `TestComparers.GetDefault<T>()` (line 55).
- E-5 `Tests/EntityFrameworkCore/TestBase.cs:AreEqualWithComparer<T>` — same as E-4 (line 109).
- E-6 `Tests/Linq/Infrastructure/AssertQueryTests.cs` (new) — the TO-1…TO-10 tests, beside the existing infrastructure fixtures (ActiveIssueTests, TestProgressStateTests).

## P7 Impact map (M/L)

- `Tests/Base/TestBase.AssertQuery.cs:521` — `AssertQuery` null-comparer fallback, reached by 973 `AssertQuery(` calls in 64 `Tests/Linq` files (scout, Grep `AssertQuery\(`) — covered by E-2
- `Tests/Base/TestBase.AssertQuery.cs:295` — `SetOperationRemap` builds the comparer for `UnionImpl` :179, `ExceptImpl` :189, `ExceptAllImpl` :194, `IntersectAllImpl` :217; the `null!` stubs at :343-363 (scout, Grep `comparer|Comparer`) — covered by E-3
- `Tests/Base/TestBase.AssertQuery.cs:212` — `IntersectImpl` is never remapped (no `Queryable.Intersect` branch at :336-365), so plain `Intersect` runs with default equality — out-of-scope
- `Tests/Base/TestBase.Asserts.cs:55` — `AreEqualWithComparer<T>(expected, result)`, 58 calls in 23 files (Grep `AreEqualWithComparer\(` count) — covered by E-4
- `Tests/Base/TestBase.Asserts.cs:60` — `AreEqualWithComparer<T>(…, memberPredicate)`: a caller asking for member filtering wants member comparison — out-of-scope
- `Tests/Base/TestBase.Asserts.cs:237-248` — `ComparerBuilder` over fixed entity types only (scout) — out-of-scope
- `Tests/EntityFrameworkCore/TestBase.cs:109` — separate copy of `AreEqualWithComparer<T>` (scout, Grep `ComparerBuilder` over `Tests/EntityFrameworkCore`); Tests.Base is referenced via `Tests/EntityFrameworkCore/Tests.EntityFrameworkCore.props:14` — covered by E-5
- `Tests/Linq/Update/UpdateWithOutputTests.cs:28` — `UpdateOutputComparer<T>`; all 20 `new UpdateOutputComparer<` sites use `DestinationTable` / `TableWithData` (Grep) — out-of-scope
- `Tests/FSharp`, `Tests/VisualBasic`, EF tests — no `AssertQuery(` and no `ComparerBuilder` hits (scout) — out-of-scope
- Explicit scalar comparers already passed: 26 `AssertQuery` calls + 12 `AssertScalarQuery` (`PreferClientCalculationTests.cs:63`) + `Issue5916Tests` 10 sites (scout) — out-of-scope (an explicit comparer wins; P3)
- `Tests/Linq/Linq/SetOperatorComplexTests.cs:473` — the only collection-`T` `AssertQuery`, with an explicit `DictionaryEqualityComparer` — out-of-scope
- `.claude/docs/testing.md:586` — the *Scalar element types* rule tells authors to pass `EqualityComparer<T>.Default`, and says `DateTime` has no members, which is wrong — deferred: corpus edit after this PR merges (the rule stays correct-but-redundant until then)
- Currently-green tests that go red once values are actually compared — unknown set, not statically enumerable — deferred: CI `test-all` after push, triaged per D-4 into `A-n` amendments

## P8 Test obligations (M/L)

House rules embedded: `testing.md` → *Test layout* (one call per line; `AssertQuery` over hand-duplicated `AreEqual`; no `Issue<N>` names in a shared fixture). TO-3…TO-10 are DB-free and use `[Test]` without data sources. Every "throws" below is `Assert.Throws<AssertionException>(() => …)` (U-8), never `Should.Throw`. Each `red→green` label is a prediction until the pre-fix run (U-1): implementation runs TO-1…TO-10 against the unchanged fallback sites first, records each arm's result in G-01, and relabels any arm that is green pre-fix.

- TO-1 `AssertQuery(db.Person.Select(p => Shifted(p.ID)))`, where `[Sql.Expression("{0} + 1")] static int Shifted(int v) => v;`, throws; discriminating input: DB `ID+1` vs memory `ID`, same count — providers: SQLite.MS (local), all via CI — proof: red→green (pre-fix: no throw)
- TO-2 `AssertQuery(db.Person.Select(p => p.ID).Union(db.Person.Select(p => p.ID + 100)))` passes; discriminating input: distinct ints that the all-equal hash collapses into one expected row — providers: SQLite.MS — proof: red→green (pre-fix: count mismatch)
- TO-3 `AreEqualWithComparer`: `int` `[1]` vs `[2]`, two different `Guid`s, `bool` `[true]` vs `[false]` each throw — providers: none (DB-free) — proof: red→green; enum `[Gender.Male]` vs `[Gender.Female]` throws — proof: characterization (`value__` member)
- TO-4 `AreEqualWithComparer` on `["ab"]` vs `["cd"]` (equal length) throws — providers: none — proof: red→green
- TO-5 `AreEqualWithComparer` on `int?` `[1, null]` vs `[2, null]` throws, and `[1, null]` vs `[null, 1]` passes — providers: none — proof: characterization (`HasValue`/`Value` already compare by value; guards the new nullable wrapper)
- TO-6 `AreEqualWithComparer` on equal scalars (`[1, 2]` vs `[2, 1]`, `["a"]` vs `["a"]`) passes — providers: none — proof: characterization (guards against an over-strict helper)
- TO-7 `AreEqualWithComparer` on `decimal` `[2.5m]` vs `[2.50m]` passes, and `[2.5m]` vs `[2.6m]` throws — providers: none — proof: on net10, red→green for the first arm (`Scale`) and characterization for the second; on net462 via CI, the reverse (zero members → all equal). `decimal?` `[2.5m, null]` vs `[2.50m, null]` passes — proof: characterization on net10, red→green on net462 via CI (hash bug)
- TO-8 `AreEqualWithComparer` on `List<int>` `[[1,2]]` vs `[[1,2]]` and `byte[]` `[{1,2}]` vs `[{1,2}]` (distinct instances) pass — providers: none — proof: red→green (pre-fix `SyncRoot` reference compare); `byte[]` `[{1,2}]` vs `[{1,3}]` throws and `int[]` `[{1,2}]` vs `[{2,1}]` throws (order) — proof: characterization (already red pre-fix; guards element-wise and ordered semantics)
- TO-9 `AreEqualWithComparer` on an entity class (two `Person`s differing only in `FirstName`) throws, and equal-valued distinct instances pass — providers: none — proof: characterization (symmetry guard on the unchanged member path)
- TO-10 `AreEqualWithComparer` on `DateTime` with the same ticks but different `Kind` throws, and the same pair as `DateTime?` passes — providers: none — proof: characterization (D-1 keeps both today's member comparer and today's `Nullable` path for date types)

## P9 Verification gates

- G-01: — (pending) — TO-1…TO-10 via `/test` on SQLite.MS net10.0
- G-02: — (pending) — expected n/a: comparison-only change, no emitted SQL moves; confirm on the CI baselines PR
- G-05: — (pending) — added by hand: Tests.Base builds for net462 and E-1 has a `NETFRAMEWORK` decimal path; `dotnet build Tests/Base/Tests.Base.csproj -f net462`
- G-06: — (pending)
- G-07: — (pending)
- G-09: — (pending)

## P10 Adjudicated (M/L)

- Redundant explicit scalar comparers (`MathFunctionTests.ByValue`/`ByNullableValue`, `PreferClientCalculationTests.AssertScalarQuery`, `Issue5916Tests.Structural`) are left in place — out of scope per P3, harmless with an explicit comparer winning.
- Plain `Intersect` is not remapped in `AssertQuery` (`TestBase.AssertQuery.cs:212`, :336-365). This predates the branch and is not touched.
- Date types and other member-bearing structs keep the member comparer (D-1 failure mode). Making them looser is not a goal of #6099.
- E-5 (EF `AreEqualWithComparer`) has no dedicated test. It is the same one-line call as E-4, which TO-3…TO-10 exercise, and it is verified by the EF test project building.

## P11 Amendments (M/L)

_None._

## P12 Critic verdict (M/L)

**Round 1 (fable): refuted.** The critic searched every `ComparerBuilder` call under `Tests/` (120 hits; no missed fallback site), decompiled NUnit 4.6.1 `Assert.ReportFailure` / `TestMethodCommand.Execute`, read `TypeAccessor{T}.cs` and `ReflectionExtensions.cs`, and grepped `value__`, `AssertionException`, `ExpectedException` and the `ExposeExpressionVisitor` attribute expansion.
- Obj 1, "a caught `AssertionException` still fails the test": probed, partly rejected. It is correct for `Should.Throw`, but NUnit `Assert.Throws` isolates the result (U-8, measured by decompiling). P8 now pins `Assert.Throws<AssertionException>`.
- Obj 2, "`Nullable<U>` is not broken on net8+": accepted. TO-5 and the TO-7 `decimal?` arm were relabelled characterization (net462 red via CI); P1 and SC-3 corrected.
- Obj 3, "enums have `value__`": accepted. P1 and U-1 corrected, and the TO-3 enum arm relabelled. A pre-fix run now measures every label (U-1).
- Obj 4, "third fallout kind": accepted, D-4 (c).
- Obj 5, "U-3 overstated; `IGrouping`": accepted, U-3 reworded and the `IGrouping` case added to D-2's failure mode.
- Obj 6, "cache mechanism": accepted, D-3 names the static generic holder.

**Round 2 (fable): weak.** U-8 was independently re-verified by decompiling, and holds. The P7 census, D-3 and D-4 survived. The critic also found 113 existing `Assert.Throws`/`Catch` uses under `Tests/`, and that `CustomTestContext` keys by test id, which the isolated context preserves. All three objections were folded in:
- Collections are a false *red* today (`SyncRoot` reference compare): P1, D-2 and the TO-8 labels inverted.
- D-1's `Nullable` wrapper is limited to a scalar `U`, so `DateTime?` keeps today's Kind-insensitive path; TO-10 gains a `DateTime?` arm.
- net462 `decimal` has no `Scale`: P1 and the TO-7 net462 expectations recorded.

Residual, carried visibly: the labels are predictions, and the pre-fix run measures net10 only. The net462 labels (TO-7) are confirmed only by CI.
