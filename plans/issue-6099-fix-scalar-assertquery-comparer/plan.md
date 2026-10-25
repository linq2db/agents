# Work plan: issue-6099-fix-scalar-assertquery-comparer — AssertQuery default comparer for scalar and collection element types

**Tier:** M  ·  **Status:** approved  ·  **Approved-at:** 2026-10-24  ·  **Branch:** issue/6099-fix-scalar-assertquery-comparer
**Schema:** `.claude/docs/work-plan.md`  ·  **Gates:** `.claude/docs/definition-of-done.md`

## P1 Problem

[#6099](https://github.com/linq2db/linq2db/issues/6099). When no comparer is passed, test infrastructure falls back to `ComparerBuilder.GetEqualityComparer<T>()` (`Tests/Base/TestBase.AssertQuery.cs:521`, `:295`; `Tests/Base/TestBase.Asserts.cs:55`; `Tests/EntityFrameworkCore/TestBase.cs:109`), which compares `T`'s public instance members (`TypeAccessor<T>`, `Source/LinqToDB/Reflection/TypeAccessor{T}.cs:17-24`). Falsifiable symptoms:

- `T` with zero members (`int`, `long`, `double`, `bool`, `object`; `Guid` too before .NET 9, which added `Version`/`Variant` — see A-1): `CreateEqualsFunc` reduces to `DefaultIfEmpty(True)` (`Source/LinqToDB.Tools/Comparers/ComparerBuilder.cs:201-202`), so every pair is equal. `AreEqualWithComparer(new[] { 1 }, new[] { 2 })` passes today. `AreEqual` (`TestBase.Asserts.cs:112`) then checks only the count.
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

- **chosen:** after unwrapping `Nullable<U>`: `U` is `string`, `decimal` or `Guid` (A-1), or `TypeAccessor.GetAccessor(U).Members.Count == 0`. Then use `EqualityComparer<U>.Default`, except `decimal` → `TestBase.DecimalComparerInstance`, and `Nullable<U>` → a null-aware wrapper over `U`'s comparer, applied **only when `U` itself satisfies this predicate**. A member-bearing `U` (`DateTime?`, `DateTimeOffset?`) falls through to `ComparerBuilder.GetEqualityComparer<T>()` unchanged: today that is `HasValue`/`Value`, compared Kind-/Offset-insensitively, and TO-10 pins it.
- **rejected:** `MappingSchema.IsScalarType` — it admits `byte[]` and date types and depends on schema state. A hard-coded primitive list — misses `Guid`, enums and `object`, and drifts.
- **why this:** the predicate is "zero members, plus a named allowlist (`string`, `decimal`, `Guid`)", open by design. It covers every zero-member type by construction, plus the allowlisted member-bearing types whose members are known not to express the value and which reach the fallback sites. Other types of that shape are a P10 known limit (A-1 `class:`).
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
- E-7 `Source/LinqToDB.Tools/EnumerableExtensions.cs:ToDiagnosticString` — a member-less non-scalar `T` uses the type name for the header column and `ta.Type` for the row alignment, instead of indexing the empty `ta.Members` (`:100`, `:115`). A-2.
- E-8 `Tests/Linq/Tools/ToDiagnosticStringTests.cs:TestDiagnosticStringNoMembers` (new test) — red→green for E-7. A-2.
- E-9 `Source/LinqToDB.Tools/EnumerableExtensions.cs:ToDiagnosticString` — honour `addTableHeader: false`: pass it through the scalar re-entry and size columns from values regardless of the flag (`:42`, `:85`). A-4.
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
- `Source/LinqToDB.Tools/EnumerableExtensions.cs:100,115` — `ToDiagnosticString<T>` callers (Grep `ToDiagnosticString\(` over `*.cs,*.fs,*.vb`): its own scalar re-entry `:42` and string overload `:176`; `Activity/ActivityStatistics.cs:405` (member-bearing record); `Tests/Base/TestBase.Asserts.cs:90-91,108-109`; `Tests/EntityFrameworkCore/TestBase.cs:146-147`; `Tests/Linq/Tools/ToDiagnosticStringTests.cs`. Only the zero-member, non-`IsScalarType` branch changes, and it threw before, so no previously working output changes — covered by E-7
- `TestBase.DecimalComparerInstance` readers (Grep): `Tests/Linq/Linq/MathFunctionTests.cs` (1) and `TestBase.Asserts.cs` itself; the field keeps its type and its value on both TFM branches — covered by E-4 (A-2)
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
- TO-11 `AreEqualWithComparer` on `IEnumerable<int>`: `[1,2]` (array) vs `[1,2]` (list) passes, `[1,2]` vs `[1,3]` throws — providers: none — proof: red→green (A-2 F1)
- TO-12 `AreEqualWithComparer` on a self-referential `Node : IEnumerable<Node>`: equal trees pass, a different child count throws — providers: none — proof: red→green (A-2 F2)
- TO-13 `ToDiagnosticString` over a member-less class prints a one-column table headed by the type name — providers: none — proof: red→green (A-2, E-7)
- TO-14 `ToDiagnosticString(addTableHeader: false)`: a member value wider than its name renders, and a scalar sequence prints no header — providers: none — proof: red→green (A-4, E-9)
- TO-10 `AreEqualWithComparer` on `DateTime` with the same ticks but different `Kind` throws, and the same pair as `DateTime?` passes — providers: none — proof: characterization (D-1 keeps both today's member comparer and today's `Nullable` path for date types)

## P9 Verification gates

- G-01: pass — `worktree-test.ps1` on SQLite.MS + SQLite.MS.LinqService, net10.0, filter `CreateDatabase|Tests.Infrastructure.AssertQueryTests`, all 10 methods present. Pre-fix (unchanged fallback sites): 8/13 failed, namely TO-1 (no throw, both contexts), TO-2 (expected count 1 vs 8, both contexts), TO-3 (`int` arm, first), TO-4, TO-7 (`2.5 <> 2.50`) and TO-8 (`List<int>` arm, first); TO-5, TO-6, TO-9 and TO-10 were green, as labelled. TO-3's `Guid`/`bool`/enum arms and TO-8's later arms are unmeasured pre-fix, because the first arm fails the test. Post-fix: 12/13, with TO-3's `Guid` arm still green (A-1). After A-1: 13/13 pass. A-2: red-first, TO-11 (equal case judged unequal, then the E-7 crash), TO-12 (`NullReferenceException`) and TO-13 (`ArgumentOutOfRangeException`) failed and the two existing `ToDiagnosticString` tests stayed green. After A-2: 18/18 pass (CreateDatabase + `AssertQueryTests` on SQLite.MS/.LinqService + `ToDiagnosticStringTests`).
- G-02: n/a — comparison-only change; no SQL is emitted from the edited code. Confirm on the CI baselines PR.
- G-05: pass — `dotnet build Tests/Base/Tests.Base.csproj -c Release -f net462`: first run failed with IDE0340 (`nameof(EqualityComparer<int>.Default)`), fixed to the unbound form, then 0 warnings / 0 errors. `Tests/EntityFrameworkCore/Tests.EntityFrameworkCore.EF10.csproj -c Debug -f net10.0`: succeeded. `Tests/Linq/Tests.csproj -c Release -f net10.0` (analyzers + XML docs): 0 warnings / 0 errors. After A-2: `Source/LinqToDB.Tools` Release (all TFMs), `Tests.Base` Release net462 and `Tests/Linq` Release net10.0 each built with 0 warnings / 0 errors.
- G-06: pass — `git diff --stat`: 3 tracked files, +4/−6, all of it fallback-site swaps plus two now-unused `using LinqToDB.Tools.Comparers;` lines; 2 new files.
- G-07: pass — nothing under `Tests/Tests.Playground/` is touched.
- G-09: pass — fresh general-purpose reviewer on the uncommitted diff, 9 findings, walked one at a time with the user (A-2): 4 fixed, 4 dropped as already adjudicated, 1 sent to the CI sweep.

## P10 Adjudicated (M/L)

- Redundant explicit scalar comparers (`MathFunctionTests.ByValue`/`ByNullableValue`, `PreferClientCalculationTests.AssertScalarQuery`, `Issue5916Tests.Structural`) are left in place — out of scope per P3, harmless with an explicit comparer winning.
- Plain `Intersect` is not remapped in `AssertQuery` (`TestBase.AssertQuery.cs:212`, :336-365). This predates the branch and is not touched.
- Date types and other member-bearing structs keep the member comparer (D-1 failure mode). Making them looser is not a goal of #6099.
- Known limit (A-1 `class:`): `BigInteger`, `SqlHierarchyId`, `System.Data.Linq.Binary`, `JsonElement` and similar member-bearing types whose members do not determine the value stay on the member comparer. None reaches a fallback site today (critic round 3 search). If one surfaces in CI it is handled per D-4(b): an explicit comparer in that test, or an allowlist entry in an amendment.
- E-5 (EF `AreEqualWithComparer`) has no dedicated test. It is the same one-line call as E-4, which TO-3…TO-10 exercise, and it is verified by the EF test project building.

## P11 Amendments (M/L)

- A-1 (2026-10-24, post-fix run) — TO-3's `Guid` arm stayed green after the fix. On .NET 9+ `Guid` has the public properties `Version` and `Variant`, so it is not zero-member, and two random v4 Guids compared equal under the member comparer: the #6099 bug class on net9+/net10. D-1's predicate gains an explicit `Guid`, beside `string`/`decimal`. No new edit-point (E-1 only).
  class: types whose public instance members do not determine the value. Guid (`Version`/`Variant`, net9+; measured by the critic in the `System.Runtime.xml` reference docs: present in 9.0, absent in 8.0), and by the same shape `BigInteger` (`IsZero`/`IsOne`/`IsEven`/`IsPowerOfTwo`/`Sign`), `SqlHierarchyId` (`IsNull`), `System.Data.Linq.Binary` (`Length`) and `JsonElement` (`ValueKind`). None of the others reaches a fallback site today (critic round 3: they occur only in files with zero `AssertQuery(`/`AreEqualWithComparer(` calls), so they are recorded as a P10 known limit and not added to the allowlist.
  re-derives: P1 (zero-member list), P5 (D-1 chosen), P8 (TO-3 Guid arm: measured green post-fix with the original predicate, red→green expected for net9+)
- A-2 (2026-10-24, G-09 adversarial read, walked one by one with the user) — fixes for findings 1, 2, 5 and 6, plus a pre-existing defect the new tests reached; findings 3, 4, 7 and 9 dropped (already adjudicated in D-1/D-2/P8), finding 8 goes to the CI sweep (D-4). User chose "fix here" for the defect, which relaxes P3's "no change under `Source/`" for E-7 only; it is a behaviour fix, with no API surface change.
  - F1: an `IEnumerable<X>` interface `T` has zero `TypeAccessor` members, so D-1 routed it as a scalar (reference equality), contradicting D-2. `Create` now checks for an element type before `IsScalar`, with `string` excluded first. TO-11: `IEnumerable<int>`, an equal pair across array/list and an unequal pair.
  - F2: a self-referential `IEnumerable<Self>` read `Cache<Self>.Instance` re-entrantly during its own type initialiser, which gives `null`. `SequenceComparer` now resolves its element comparer lazily through `GetDefault<TElement>()`. TO-12: `Node : IEnumerable<Node>` with a public `Size`, so the pre-fix run reaches the recursion.
  - F5: the decimal branch read `TestBase.DecimalComparerInstance`, which runs `Tests.TestBase`'s static constructor (trace hook, `CurrentDirectory`, `CopyDatabases`) even inside the EF test assembly. The netfx decimal comparer moves into `TestComparers`, and `TestBase.DecimalComparerInstance` now returns it. E-4 widens to the `DecimalComparerInstance` field and the nested `DecimalComparer` in `TestBase.Asserts.cs`. No red test: proving it means observing static-constructor side effects inside the EF process; TO-7 covers the behaviour.
  - F6: `ZeroMemberScalars_DifferentValues_Fail` renamed `Scalars_DifferentValues_Fail`, since enums are not zero-member.
  - E-7: `ToDiagnosticString<T>` threw `ArgumentOutOfRangeException` for a member-less non-scalar `T` (header loop `:100`, row loop `:115`). `AreEqual`'s mismatch branch (`TestBase.Asserts.cs:123`) reaches it as soon as such a `T` is compared unequal, which this branch now makes possible. TO-13: `TestDiagnosticStringNoMembers`.
  - Dropped or deferred: F3 (a bare `IGrouping`/`IDictionary`/`ILookup` `T` compares only its elements, in order) — D-2 failure mode, unreachable today. F4 (`DateTime?` ignores `Kind` while `DateTime` does not) — D-1, pinned by TO-10. F7 (several checks already pass on the old code) — P8 characterization labels, confirmed by G-01; the reviewer's claim that the `List<int>` line passes on the old code is refuted by the pre-fix run. F8 (now-strict `string`/`double`/`object` comparisons may turn tests red) — CI `test-all` sweep, triaged per D-4. F9 (`SequenceComparer` duplicates the internal `EnumerableEqualityComparer<T>`) — D-2, which rejects that type as internal and unusable for struct sequences.
  - Tier stays M (the `LinqToDB.Tools` fix is a two-line local repair). The critic is re-dispatched on the delta (P12 round 3).
  re-derives: P3 (Source exception for E-7), P5 (D-1 order of checks, D-3 cache recursion), P6 (E-4 widened, E-7, E-8), P7 (ToDiagnosticString callers, DecimalComparerInstance readers), P8 (TO-11, TO-12, TO-13)
  conventions: `testing.md` → *Test layout* (one call per line, Shouldly in E-8), checked by hand against the new tests
- A-3 (2026-10-25, CI on `1faaee0a1`) — U-5 resolved: Azure `test-all` 24655 and GitHub `tests [all]` 40119233045 were fully green, including the unfiltered net462 main suite on the GitHub Win legs (SqlCE leg: 9005 tests). So the D-4 fallout set is empty, and the TO-7 net462 labels are confirmed. The baselines branch is 136 added / 0 modified / 0 deleted (TO-1 + TO-2 × 68 providers), so G-02 is confirmed.
  re-derives: P4 (U-5), P7 (the deferred "currently-green tests that go red" row: empty), P9 (G-02)
- A-4 (2026-10-25, `/review-pr` round 1, walked with the user) — MIN001: the PR body is corrected (zero fallout; characterization tests named as such). NIT001: the `GetDefault<T>` XML doc names `EqualityComparer{T}.Default` instead of "value equality", because a member-less class compares by reference. An out-of-scope observation became a fix on the branch: `ToDiagnosticString(addTableHeader: false)` threw `ArgumentOutOfRangeException` once a value was wider than its column name (the width ignored values when the header was off), and the scalar branch dropped the flag on re-entry. This relaxes P3 for E-9 the same way A-2 did for E-7: a behaviour fix with no API surface change.
  - E-9 `Source/LinqToDB.Tools/EnumerableExtensions.cs:ToDiagnosticString` — pass `addTableHeader` through the scalar re-entry (`:42`); size columns from values regardless of the flag (`:85`).
  - TO-14 `ToDiagnosticStringTests.TestDiagnosticStringWithoutHeader` (member value wider than its name) and `TestDiagnosticStringScalarWithoutHeader` (no header for a scalar) — proof: red→green, measured (pre-fix: `ArgumentOutOfRangeException` `repeatCount -3`; unexpected `| Value |` header).
  re-derives: P3 (Source exception for E-9), P6 (E-9), P8 (TO-14)

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

**Round 3 (fable, delta A-1 + A-2 against the uncommitted code): weak.** The critic:
- read the diff and both new files in full;
- confirmed `Guid.Version`/`Variant` from the .NET 9 reference XML, absent in 8.0;
- walked `Create`'s order for `string`, `Nullable<U>`, `IEnumerable<int>`, `IList<int>`;
- showed mutual recursion is safe by construction (the only eager cache read is the scalar `NullableComparer` arm);
- mapped each A-2 clause to the obligation that reddens when it alone is reverted (order → TO-11, lazy resolution → TO-12, E-7 → TO-13);
- confirmed E-7 completes a half-built zero-member branch in `ToDiagnosticString` (`:49-81`) and changes no previously working output (`object` takes the `IsScalarType` path);
- confirmed the `DecimalComparerInstance` readers and the removed `TestBase` dependency.

Objections, all folded in as plan text:
- A-1 recorded the instance rather than the class: `class:` line plus P10 known limit; D-1 `why this` reworded.
- The dropped G-09 findings were listed by number only: one line each in A-2.

The string-exclusion clause in `Create` is non-load-bearing (`SequenceComparer<string,char>` would also be correct); this is noted, not a defect.
