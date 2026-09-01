# Work plan: issue-5729-fix-inheritance-derived-insert — setter-lambda writes with a derived-type initializer through a base-mapped table

**Tier:** M  ·  **Status:** reviewed  ·  **Approved-at:** — (implemented on user instruction; PR [#5840](https://github.com/linq2db/linq2db/pull/5840))  ·  **Branch:** issue/5729-fix-inheritance-derived-insert
**Schema:** `.claude/docs/work-plan.md`  ·  **Gates:** `.claude/docs/definition-of-done.md`

**Tier rationale.** **M.** One area (`EXPR-TRANS`, `Internal/Linq/Builder`), no `cross-cutting-core.md` path, no `IDataProvider` or SQL-builder base, no public API. It was briefly escalated to **L** while a second mechanism in `Internal/Mapping` was in scope; that half has been **split out to its own issue** (see `P1`), so the change is back inside one area. The critic runs anyway — advisory at M — because the blast radius within the area is wide (21 `ParseSetter` call sites).

## P1 Problem

[#5729](https://github.com/linq2db/linq2db/issues/5729). Inserting a derived type through a base-mapped table throws:

```
System.ArgumentException: Property 'System.String Name' is not defined for type 'ConsoleApp2.Test2+Base' (Parameter 'property')
```

for

```csharp
db.GetTable<Base>().Insert(() => new Chil1 { Code = Code.Child1, Name = "Jack" });
```

where `Base` carries `[InheritanceMapping(Code = Code.Child1, Type = typeof(Chil1))]` and `Name` is declared only on `Chil1`.

Mechanism, verified in the tree at `639d6aaf8` and reproduced by execution (`P7` Search 7):

- `UpdateBuilder.ParseSetter` builds the field side with `Expression.MakeMemberAccess(targetRef, assignment.MemberInfo)` at `Source/LinqToDB/Internal/Linq/Builder/UpdateBuilder.cs:649` (assignments) and `:658` (parameters).
- `targetRef` is typed from the **table's** element type: `InsertBuilder.cs:150` takes `targetType = genericArguments[0]` and `:158` builds `intoContextRef` from it — i.e. `Base`.
- `assignment.MemberInfo` is `Chil1.Name`. The BCL factory rejects that pairing, which is the exact reported exception.

The message is **not ours** — `Grep "is not defined for type"` over `Source` returns nothing; it is `System.Linq.Expressions`.

**Roslyn emits no `Convert` wrapper at all** — measured, see `U-1`. `Body.NodeType` is `MemberInit` (or `New` for a positional record) and `Body.Type` is the **derived** type for every setter-lambda shape in the API surface, so `correctedSetter` reaches line 645 as a `SqlGenericConstructorExpression` and the `default: throw new NotSupportedException()` at `:672` is never involved.

### Scope boundary — a second mechanism exists and is NOT fixed here

The same user-visible situation fails a **different** way through the entity-builder spec API, the `Upsert` API, and Merge's parameterless clauses:

```
System.InvalidOperationException: Member 'System.String Name' not found in type 'Base'.
```

Measured on five shapes (`P7` Search 7). It never reaches `ParseSetter`: `EntitySetterBuilder` / `UpsertBuilder` iterate the **base** descriptor's merged `Columns` against a base-typed instance, and `ColumnDescriptorExtensions.GetMemberAccessExpression` (`Internal/Mapping/ColumnDescriptorExtensions.cs:67-72`) resolves each column by a **by-name lookup on `instance.Type`** (`ReflectionExtensions.cs:102-127`), which misses and throws by design.

**This was folded in, then split back out after the critic refuted the proposed fix for it — it is now [#5837](https://github.com/linq2db/linq2db/issues/5837)** (Bug, milestone 6.6.0). The refutation is recorded in `P12` and was carried into that issue's Notes: correcting the helper alone would make the *value* getters emit `((Child2)itemConstant).Child2Field` for a `Child1` item — a cross-branch downcast that throws `InvalidCastException` at runtime, replacing today's clean build-time error with a worse one. The helper is the wrong altitude for the value side because it is the one place the item's **runtime** type is invisible; the correct fix selects columns by runtime type at the caller. That is a different and larger design.

## P2 Success criteria

- SC-1 `GetTable<Base>().Insert(() => new Derived { baseCol = …, derivedCol = … })` executes, and the emitted `INSERT` carries the derived column. *Unmet if:* it still throws, or the derived column is absent from the generated SQL. → TO-1
- SC-2 The same initializer shape works for `Update` — both `q.Update(t => new Derived { … })` and the explicit-target overload. *Unmet if:* either throws. → TO-2
- SC-3 The same works for `InsertOrUpdate`, in all three of its lambdas (insert setter, update setter, key selector — they share one context ref). *Unmet if:* any throws. → TO-3
- SC-4 The same works for an **`OUTPUT … INTO`** clause whose output table is base-mapped and whose lambda constructs a derived type. *Unmet if:* it throws. → TO-4
- SC-5 An initializer whose members are **all** base-declared emits byte-identical SQL to today. *Unmet if:* any existing baseline moves. → TO-5
- SC-6 A member that genuinely belongs to no mapped type in the hierarchy still fails loudly. *Unmet if:* it is silently dropped from the `INSERT` instead of erroring. → TO-6
- SC-7 A derived type whose members are set through **constructor parameters** (a positional/record subtype) inserts through the base table. *Unmet if:* it throws where the member-initializer form succeeds. → TO-7
- SC-8 A **row-returning output clause** over an inheritance-mapped table gets past expression building, even when the setter mentions only base members — the projection carries the subtypes' merged columns regardless. *Unmet if:* it throws `ArgumentException` from `Expression.MakeMemberAccess`. Materializing the returned row is **out of scope** and tracked as [#5838](https://github.com/linq2db/linq2db/issues/5838). → TO-8

## P3 Constraints & anti-goals (M/L)

- **No generated-SQL change for non-inheritance entities**, and none for base-only initializers on inheritance entities (SC-5 pins this).
- **No public API change.** The fix is entirely under `Internal/`. `ExpressionExtensions.GetMemberGetter` is public (`PublicAPI.Shipped.txt:14010`) and is **not** to be re-signatured.
- **`ColumnDescriptorExtensions.GetMemberAccessExpression` is out of scope** (`Internal/Mapping/ColumnDescriptorExtensions.cs:37`) — it belongs to the split-out mechanism. Its XML remarks and `<exception>` contract (`:25-27`, `:34-36`) describe today's by-name lookup and must stay true, which they do as long as this change does not touch it.
- **Do not silently drop an unresolvable member.** Turning a hard error into a missing column is a worse failure than the current exception.
- **Do not retrofit the other three guard idioms** in this change (see D-3).

## P4 Unknowns (M/L)

- U-1 Whether Roslyn emits `Expression.Convert(memberInit, TBase)` for the setter lambda shapes. — **resolved-by probe: it does not, in any shape.** A standalone BCL program (`.build/.agents/u1probe`) reported `NodeType=MemberInit`, `Type=Derived`, `wrapped=no` for `Func<Base>`, `Func<Base,Base>` and `Func<Base,Base,Base>`, and `NodeType=New`, `Type=RecDerived` for a positional record. **Consequence, now confirmed by execution:** the five sites that pre-retype from `setterExpression.Type` receive the *derived* type and are immune — `Merge().InsertWhenNotMatched(s => new Child1{…})` and `Merge().UpdateWhenMatched((t,s) => new Child1{…})` both build successfully and fail only at execution with `LinqToDBException: SQLite provider doesn't support SQL MERGE statement`.
- U-2 Whether the **row-returning** output site (`InsertBuilder.cs:319`) can receive a user `MemberInit`. — **resolved-by adjudication (P10 entry 3): shipping unanswered, deliberately.** The question is narrower than previously claimed: the `InsertWithOutput(() => new Child1{…})` probe cell throws `ArgumentException`, but at the *insert-setter* `ParseSetter` site during `BuildMethodCall`, before the output expression is built — so it does **not** establish that `:319` is reachable, and the earlier "resolved: yes, in scope" was an over-attribution. SC-4 is therefore anchored on the `OUTPUT … INTO` sites (row 7), which are measured-reachable. `:319` is neither proven reachable nor proven immune. The probe that would settle it: an `InsertWithOutput` whose *insert* setter is base-only and whose *output* lambda constructs a derived type. Not run, because it is not load-bearing for the reported defect and E-1 covers `:319` anyway if it does turn out reachable.
- U-3 Whether `UpsertBuilder` is affected. — **resolved-by probe: yes, and my first answer was wrong.** The earlier cell probed `db.InsertOrReplace<Base>(…)`, which is the object/QueryRunner API and does **not** route through `UpsertBuilder`. `UpsertBuilder` handles `Upsert`/`UpsertAsync` (`UpsertBuilder.cs:31`), and `GetTable<Base>().Upsert(child1)` and `.Upsert(child1, spec => spec)` both throw the mechanism-2 `InvalidOperationException` while `GetTable<Child1>().Upsert(child1)` succeeds. **It belongs to the split-out issue, not here.**
- U-4 Whether `ContextRefExpression.WithType` dropping `Alias` matters. — **resolved-by search, independently confirmed by the critic.** `WithType` forwards only `(type, BuildContext)` (`ContextRefExpression.cs:30-36`). The property has exactly **two** readers in `Source/LinqToDB` and neither affects generated SQL: `SqlErrorExpression.cs:138` names a parameter when rendering an **error message**, with a `?? "x"` fallback, and `SequenceHelper.cs:894` merely forwards it. The loss is cosmetic and confined to an already-failing path.
- U-5 `SequenceHelper.RemapToNewPath` / `RemapToNewPathSimple` appear to be **dead code** — the only external hits are a different same-named method on `ExpressionBuilder.Generation.cs:108/:121`, itself uncalled. — resolved-by scout: treat them as *precedent for the idiom*, not evidence it is exercised.

## P5 Decisions (M/L)

### D-1 — Fix inside `ParseSetter`, not at the call sites

- **chosen:** apply the declaring-type guard at `UpdateBuilder.cs:649` / `:658`, i.e. inside the single helper.
- **rejected:** retype `targetRef` at each call site — there are **21** across 11 files, and the Merge group already does this inconsistently (`MergeBuilder.InsertWhenNotMatched.cs:50-51` and three siblings retype; `MergeBuilder.cs:102` does not). Fixing at the call sites means getting 21 judgement calls right and leaves the next new caller unguarded.
- **why this:** `ParseSetter` is the one point where "the setter named this member" becomes "build an access against the target", and every one of the 21 callers funnels through it.
- **failure mode of the choice:** `ParseSetter` is not the only door into the user-visible defect. The `Insert(item, spec)` / `Upsert` / Merge-null-setter family fails earlier and elsewhere (`P1` scope boundary), so a fix here will read as "inheritance setters are fixed" while those stay broken until the split-out issue lands.

### D-2 — One file-private helper over `SequenceHelper.EnsureType`, used at all three sites

- **chosen:** a `static Expression EnsureDeclaringType(Expression target, MemberInfo memberInfo)` on `UpdateBuilder` that retypes through `SequenceHelper.EnsureType` (`:258-274`) when `memberInfo.DeclaringType` is not assignable from `target.Type`, and is called at E-1, E-2 and E-3.
- **rejected:** raw `targetRef.WithType(...)` as at `SequenceHelper.cs:492-499`. **This was the choice for one revision and it was wrong — measurement, not argument, settled it.** It generalises only while `ParseSetter` is the sole edit-point: its `targetRef` parameter is declared `ContextRefExpression` (`UpdateBuilder.cs:631`), but E-3's target is whatever `ParseSet` recursed with, which is a `MemberExpression`. `EnsureType` covers both — `WithType` for a context ref, `Expression.Convert` otherwise — so one helper serves all three sites and neither shape gets a wrapper it doesn't need.
- **rejected:** raw `Expression.Convert` everywhere. `TableBuilder.TableContext.cs:480` calls `UnwrapConvert` before `SequenceHelper.IsSameContext`, so a `Convert`-wrapped ref does resolve at the column-lookup site — not a correctness objection. It is rejected because it would wrap the context-ref sites too, where the in-repo idiom retypes, leaving a node shape every other setter-path consumer must unwrap.
- **rejected:** three inlined copies of the guard. The tree already carries four incompatible inline idioms (D-3); adding three more of a fifth is what D-3 exists to avoid. One file-private helper is the smallest thing that doesn't grow the divergence.
- **rejected:** raw `Expression.Convert`, on a weaker basis, and the plan says so rather than overstating it. `TableBuilder.TableContext.cs:480` calls `UnwrapConvert` before `SequenceHelper.IsSameContext`, so a `Convert`-wrapped ref **does** resolve at the column-lookup site; that is not a correctness objection. It is rejected because it wraps where the in-repo idiom retypes, leaving a node shape every *other* setter-path consumer must also unwrap, and those were not audited.
- **why this:** it is the exact idiom at the four `SequenceHelper` sites, and the critic supplied a live precedent the plan had missed — `ExpressionBuildVisitor.cs:1682` already builds `MakeMemberAccess(contextRef.WithType(tableContext.ObjectType), newMember)`, so retyping a **table** ref before a member access is established visitor practice.
- **failure mode of the choice:** `WithType` drops `Alias`. U-4 shows that is cosmetic here — but it is a property the type carries and a future consumer could start reading.

### D-3 — Do not retrofit the other three guard idioms

- **chosen:** add the guard at the two `ParseSetter` edit-points only.
- **rejected:** extract one shared helper and apply it to all ~20 unguarded sites. The tree has **four mutually incompatible** idioms — (A) retype the context ref, (B) `Convert`/`EnsureType`, (C) re-resolve via `GetMemberEx` and skip on null, (D) applicability test then drop the member — and no shared helper exists (`MakeMemberAccessSafe|SafeMemberAccess|CorrectDeclaring|EnsureDeclaring|AdjustForDeclaring` over `Source/` → 0 hits).
- **why this:** the four idioms differ in *behaviour*, not spelling — (C) and (D) deliberately drop or error where (A)/(B) retype. Unifying them is a semantic change to ~20 sites with no failing test to anchor it.
- **failure mode of the choice:** this adds a fifth instance of idiom (A) and leaves the divergence in place. Recorded in `P10`.

## P6 Edit-points (M/L)

- E-1 `Source/LinqToDB/Internal/Linq/Builder/UpdateBuilder.cs:649` — `ParseSetter`, assignments loop: retype the target to `assignment.MemberInfo.DeclaringType` before `MakeMemberAccess` when it is not assignable from the target's type.
- E-2 `Source/LinqToDB/Internal/Linq/Builder/UpdateBuilder.cs:658` — `ParseSetter`, parameters loop: same for `parameter.MemberInfo`.
- E-3 `Source/LinqToDB/Internal/Linq/Builder/UpdateBuilder.cs:609` — `ParseSet`'s nested-generic recursion: same helper. **Dropped for one revision and restored after measurement** — see the note below.
- E-4 `Tests/Linq/Linq/InheritanceTests.cs` — regression tests for SC-1…SC-8, in the `#region Discriminator Filtering` neighbourhood at `:1180`, reusing the existing `BaseClass`/`Child1` model at `:1188-1238` for the member-initializer cases, plus a constructor-parameter (positional/record) derived model for TO-7.

**E-3 was dropped on a correct-but-narrow objection, and restoring it is the plan's sharpest lesson.** Critic pass 1 observed that `:609` runs only for a nested `SqlGenericConstructorExpression` and that a flat `.Set(x => x.Name, v)` takes the `:613` else-branch — true, and it correctly killed the *symmetry guard* that claimed to cover it. Dropping the edit-point on that basis was an over-application: `:609` is reachable, just not from `.Set(…)`. It is reached from `ParseSetter`'s own recursion, which is what an **output projection over an inheritance root** produces, because the projection carries the subtypes' merged columns. Measured: with E-1/E-2 alone, `UpdateWithOutput` still threw `ArgumentException` from `Expression.Property` via `ParseSet:609` ← `ParseSetter:662`. A correct objection to a *test* is not automatically an objection to the *edit-point*.

**Still dropped:** `ColumnDescriptorExtensions.cs:67-72` — mechanism 2, split to [#5837](https://github.com/linq2db/linq2db/issues/5837) after its proposed fix was refuted (`P1`, `P12`).

## P7 Impact map (M/L)

**Search 1** — `Grep "ParseSetter"` across the worktree, covering *call sites*, not just the declaration. **21 call sites in 11 files**, not the 4 in `UpdateBuilder.cs` a same-file read suggests.

| # | Site | Target-ref type source | Reachable with a derived initializer? | Verdict |
|---|---|---|---|---|
| 1 | `InsertBuilder.cs:189` | `genericArguments[0]` (`:150`,`:158`) | **yes — the reported shape**, measured | covered by E-1 |
| 2 | `InsertBuilder.cs:139` | `genericArguments[1]` | yes | covered by E-1 |
| 3 | `UpdateBuilder.cs:145` | `genericArguments[0]` | yes, measured | covered by E-1 |
| 4 | `UpdateBuilder.cs:238` | `genericArguments[1]` | yes | covered by E-1 |
| 5 | `InsertOrUpdateBuilder.cs:38`,`:46`,`:97` | one shared `contextRef` (`:23`,`:35`) | yes, measured; all three lambdas incl. the key selector | covered by E-1 |
| 6 | `MergeBuilder.cs:102` | `GetGenericArguments()[2]` (`:99`) | yes — the only OUTPUT-INTO site with **no** adaptation | covered by E-1 |
| 7 | `UpdateBuilder.cs:295`, `InsertBuilder.cs:236`, `DeleteBuilder.cs:95` | output-table object type | yes, derived relative to the **output** table | covered by E-1 |
| 8 | `MergeBuilder.{InsertWhenNotMatched:52, UpdateWhenMatched:42, UpdateWhenMatchedThenDelete:45, UpdateWhenNotMatchedBySource:35}` | `…ContextRef.WithType(setterExpression.Type)` | **no — immune, measured.** U-1 shows `setterExpression.Type` is the derived type, and both explicit-setter Merge cells build successfully | out-of-scope — nothing to fix |
| 9 | `MultiInsertBuilder.cs:112` | `new ContextRefExpression(setterExpression.Type, into)` (`:108`) | no — immune by the same mechanism as row 8 | out-of-scope — nothing to fix |
| 10 | `UpdateBuilder.cs:856`, `InsertBuilder.cs:319` | synthetic `SelectContext` over an already-built projection | **yes — measured.** The projection over an inheritance root carries the subtypes' merged columns, so it reaches `ParseSet:609` even for a base-only setter | covered by E-3 |
| 10b | `DeleteBuilder.cs:194`, `MergeBuilder.MergeContext.cs:86` | same shape | not exercised — `DeleteWithOutput` matched no rows in the probe | deferred: untested, same shape as row 10 so presumed covered by E-3 |
| 11 | `InsertBuilder.cs:108` | `genericArguments[1] ?? sourceRef.Type`; setter is machine-built (`:106`) | no user `MemberInit` handed in | deferred: no user-expressible shape found |

**Search 2** — `Grep "Expression\.MakeMemberAccess\("` + `Expression\.(Property|Field|PropertyOrField)\(` + the wrapper helpers (`GetMemberGetter|GetMemberAccessExpression|GetGetterExpression`) + `MemberExpression.Update(` + `Expression.Bind(` over `Source/LinqToDB`. Covers the BCL factories, the wrapper helpers, and the `Update`/`Bind` routes. ~20 unguarded sites beyond E-1/E-2, all deferred under D-3:

- `UpdateBuilder.cs:795` (`FindForRightProjectionPath`) — same recursion shape, no declaring-type test — deferred: D-3, no reported shape reaches it.
- `SequenceHelper.cs:347`, `ProjectionPathHelper.cs:97`, `BuildProxyBase{TOwner}.cs:131`,`:161` — assignments loop guarded, **parameters loop not** (the same asymmetry in each file) — deferred: D-3.
- `ExpressionBuildVisitor.cs:4003`,`:4004`,`:4033`,`:4073` — comparison-operand rebuild; `:4033`/`:4073` are the *member-absent-on-this-side* diagnostic branch, where a throw would replace a good error message with `ArgumentException` — deferred: D-3, but the highest-value follow-up.
- `Concurrency/ConcurrencyExtensions.cs:32`,`:85`,`:326` — iterate a TPH root's merged `Columns` against a base-typed parameter; `:85` covers *all* updatable columns — deferred: D-3, and outside the builder entirely, so it wants its own issue.
- The wrapper-helper family the first census silently dropped, all reaching `GetMemberAccessExpression`: `EntitySetterBuilder.cs:56`,`:68`,`:106`,`:122`,`:158`; `UpsertBuilder.cs:126`,`:134`,`:139`,`:159`,`:165`; `MergeBuilder.On.cs:77-78`; `MergeBuilder.UpdateWhenMatched.cs:59-60`; `MergeBuilder.UpdateWhenMatchedThenDelete.cs:61-62`; `ExpressionBuildVisitor.cs:5159`; `ExpressionBuilder.SqlBuilder.cs:796` — out-of-scope: this is the split-out issue's surface, not D-3's.

**Search 3** — `Grep "MakeMemberAccessSafe|SafeMemberAccess|MakeMemberAccessFor|CorrectDeclaring|EnsureDeclaring|AdjustForDeclaring"` over `Source/` → **0 hits**. No shared helper exists; the guard is duplicated inline in four incompatible shapes. Evidence for D-3.

**Search 4** — `Read EntityDescriptor.cs:510-547` (`InitInheritanceMapping`) — the load-bearing one. Derived-only columns **are** merged into the base descriptor: `:518-524` adds each subtype `ColumnDescriptor` verbatim to `Columns`, so `baseDescriptor.Columns[i].MemberInfo.DeclaringType` can be a derived type, and `SqlTable.cs:66-70` turns each into a real `SqlField`. `TableBuilder.TableContext.cs:456` then matches by `ColumnDescriptor.MemberInfo.EqualsTo(member, …)` — **member identity, not ref type** — and the ref is gated only by `SequenceHelper.IsSameContext` (`:480`), which compares `BuildContext` and ignores type. **Retyping the ref is sufficient for the member to resolve to a real column.** — covered by E-1

**Search 5** — `Grep "Chil1"` / `Grep "5729"` over `Tests` → 0 hits. Type-set extraction over every `Insert*(() => new X` in `Tests` → 89 distinct types, of which the only inheritance-derived ones are `CreateTable1`/`CreateTable2` at `TphInheritanceTests.cs:1679-1680` — `[ActiveIssue]`-disabled, SQLite-only, asserting only on `ColumnDescriptor.CanBeNull`. **No live asserting test covers this shape anywhere.** — covered by E-3

**Search 6** — the name-collision caveat. `EntityDescriptor.cs:526-545`: a derived member whose *name* collides with an already-merged member goes to `_inheritanceSiblingColumns` rather than `Columns`, and gets a `SqlField` only if its physical column name is new (`SqlTable.cs:86-98`); otherwise it resolves through the inheritance fallback at `TableBuilder.TableContext.cs:485-496`. — deferred: outside the reported shape; TO-6 pins that it still errors rather than silently dropping.

**Search 7** — the executable probe (`.build/.agents/repro5729`: a console app referencing the branch's `LinqToDB.csproj`, SQLite in-memory, the issue's own model). The only row set here that is **run** rather than read. 17 cells:

| Shape | Result | Bearing |
|---|---|---|
| `GetTable<Base>().Insert(() => new Child1{})` | `ArgumentException` | the reported defect — TO-1 red anchor |
| `GetTable<Base>().Update(t => new Child1{})` | `ArgumentException` | TO-2 red anchor |
| `GetTable<Base>().InsertOrUpdate(…)` | `ArgumentException` | TO-3 red anchor |
| `GetTable<Base>().InsertWithOutput(() => new Child1{})` | `ArgumentException` | throws at the *insert-setter* site — see U-2 |
| `GetTable<Base>().Insert(() => new Base{})` | OK | control |
| `GetTable<Child1>().Insert(() => new Child1{})` | OK | control |
| `Merge().InsertWhenNotMatched(s => new Child1{})` | `LinqToDBException: SQLite … doesn't support SQL MERGE` | **built successfully** — row 8 immune |
| `Merge().UpdateWhenMatched((t,s) => new Child1{})` | `LinqToDBException: SQLite … doesn't support SQL MERGE` | **built successfully** — row 8 immune |
| `GetTable<Base>().Insert(child1, spec => spec)` | `InvalidOperationException` | mechanism 2 — split out |
| `Merge().OnTargetKey().UpdateWhenMatched()` (no setter) | `InvalidOperationException` | mechanism 2 — split out |
| `GetTable<Base>().Upsert(child1)` / `.Upsert(child1, spec)` | `InvalidOperationException` | mechanism 2 — split out (corrects U-3) |
| `GetTable<Child1>().Insert(child1, spec)` / `.Upsert(child1)` | OK | controls for mechanism 2 |
| `db.Insert<Base>` / `db.Update<Base>` / `db.InsertOrReplace<Base>` | OK | object API unaffected |

**The controls are what make this diagnostic.** Every derived-table cell passes, for both mechanisms — so neither failure is about inheritance mapping as such; both are specifically a *base-typed target* meeting a *derived-declared member*. — covered by E-1, E-2

## P8 Test obligations (M/L)

- TO-1 (SC-1) `InheritanceTests`: `GetTable<BaseClass>().Insert(() => new Child1 { … })` inserts, and the emitted SQL contains the derived column. — proof: **red→green** (must throw `ArgumentException` on unfixed code, for that reason — not a compile or fixture error; the probe confirms it does).
- TO-2 (SC-2) same for both `Update` overloads. — proof: **red→green**
- TO-3 (SC-3) same for `InsertOrUpdate`, with a derived initializer in each of its three lambdas in turn — they share one context ref, so one test per position. — proof: **red→green**
- TO-4 (SC-4) same for an **`OUTPUT … INTO`** clause (row 7's sites — the measured-reachable anchor, not the row-returning `:319` which U-2 leaves open). Follow the per-file `Feature*` provider-constant pattern at `InsertWithOutputTests.cs:20-25`, not a new attribute. — proof: **red→green**
- TO-5 (SC-5, SC-6) a base-only initializer on the same hierarchy emits unchanged SQL, and the existing suite's baselines do not move. — proof: **characterization** — proves no new behaviour.
- TO-6 (SC-6) a member belonging to no mapped type still errors rather than being dropped. — proof: **control** — accepted under the current lenient path, rejected under the guard.
- TO-7 (SC-7) a **constructor-parameter** derived entity — a positional/record TPH subtype — inserted through the base table. This is the obligation that makes **E-2 failable**: `ParseSetter`'s parameters loop (`UpdateBuilder.cs:658`) fires only for `SqlGenericConstructorExpression.Parameters`, and every other obligation uses the member-initializer shape from `InheritanceTests.cs:1188-1238`, whose model is property-based — so without TO-7 the whole suite stays green if E-2 is wrong or omitted. Needs a new constructor-based model. — proof: **red→green**

- TO-8 (SC-8) `GetTable<Base>().Where(…).UpdateWithOutput(t => new Base { … })` — a **base-only** setter on an inheritance-mapped table — gets past expression building. This is the obligation that makes **E-3 failable**, and the one whose absence let E-3 be dropped: with E-1/E-2 alone it throws `ArgumentException` at `ParseSet:609`. Assert on the exception *not* being `ArgumentException`; the call still fails downstream on [#5838](https://github.com/linq2db/linq2db/issues/5838), so this cannot be a plain "it works" assertion until that lands. — proof: **red→green**

**Symmetry note (E-1 vs E-2 vs E-3).** E-1/E-2 are the assignments and parameters arms of `ParseSetter`'s switch; E-3 is `ParseSet`'s recursion beneath them. TO-1…TO-6 exercise only E-1; TO-7 guards E-2; TO-8 guards E-3. Each edit-point now has exactly one obligation that fails without it.

**No Merge obligation.** Earlier revisions carried one. Measurement removed it: the explicit-setter clauses are immune (they build), and the parameterless clause belongs to the split-out mechanism. Writing a Merge test here would have been a characterization test mislabeled as red→green.

## P9 Verification gates

- G-01: **pass, partially** — `dotnet test Tests/Linq/Tests.csproj -f net10.0 -c Testing --filter "…CreateDatabase|…Issue5729_" --provider SQLite.MS` returned `total: 13  succeeded: 13  skipped: 0`, `Test run summary: Passed!`. Each obligation's red state was observed on unfixed code earlier in the session via the `.build/.agents/repro5729` grid. **Unverified on SQL Server**: `sql2016` is a named instance rather than a container, and the worktree sits outside the primary clone so it cannot resolve `UserDataProviders.json` by walk-up. That leg rests on CI (`/azp run test-all` on [#5840](https://github.com/linq2db/linq2db/pull/5840)) — so SQL-Server-specific behaviour is **unverified locally**, not verified-and-clean.
- G-02: **n/a** — `BaselinesPath` is unset in this environment, so no baselines were written to diff. The change alters expression building, not SQL emission, and the local run moved no baselines because none were captured. CI is the check.
- G-03: n/a — no new public surface (`P3` forbids it)
- G-04: n/a — no public API change, so no `CompatibilitySuppressions` refresh
- G-05: **skipped** — no portable-TFM build was run, so `net462` / `netstandard2.0` are **unverified**. The edit uses only `MemberInfo.DeclaringType`, `Type.IsAssignableFrom` and an existing internal helper, none newer than netstandard2.0, so the risk is low — but low is not verified, and CI's build leg is what will actually confirm it.
- G-06: **pass** — `-Action reconcile` against the worktree: 1 file considered, covered by an `E-n`, 0 unplanned. The diff touches only `UpdateBuilder.cs` and `InheritanceTests.cs`.
- G-07: **pass** — no `Tests.Playground` changes; `playgroundLink` was deliberately not set, so no `<Compile Include>` scratch exists to stage. `git status` on the worktree showed exactly the two intended files.
- G-08: n/a — not cross-cutting core; `P6` touches no `SqlQuery/**` or `Translation/**` path

## P10 Adjudicated (M/L)

- **Four incompatible declaring-type guard idioms remain in the tree, and this change adds a fifth instance of one of them.** Reason: unifying them is a semantic change to ~20 sites with no failing test to anchor it (D-3). A reviewer who disagrees should raise it against this entry.
- **Mechanism 2 is split to [#5837](https://github.com/linq2db/linq2db/issues/5837) rather than fixed here**, with five measured failing shapes (`Insert(item, spec)`, `Update(item, spec)`, `Upsert(item)`, `Upsert(item, spec)`, Merge's parameterless clauses). Reason: the fix requires caller-side column selection by the item's **runtime** type, which is a different design from this one — and the helper-side fix that looked equivalent was refuted for producing runtime `InvalidCastException`s on multi-branch hierarchies (`P12` objection 1). Bundling them would put an unreviewable second design inside a regression fix.
- **`U-2` ships open.** The row-returning output site `InsertBuilder.cs:319` is neither proven reachable nor proven immune, and SC-4 is anchored on the `OUTPUT … INTO` sites instead. Reason: the probe that appeared to settle it actually threw at a different site. Cheap to close later; not load-bearing for the reported defect.

## P11 Amendments (M/L)

_None._ (Approval has not been granted, so revisions to date are re-authoring, not amendments.)

## P12 Critic verdict (M/L)

**Verdict: `refuted`** — `plan-critic` on `fable` (per `.claude/plans/config.json`), second pass, delta-scoped, against the worktree at `639d6aaf8`. The first pass returned `weak`; its six objections were all conceded or accepted and are summarised at the end.

The refutation targeted the folded-in mechanism-2 half, and **it was upheld** — that half is now split out rather than revised. Seven objections:

1. **REFUTED — the mechanism-2 fix would ship a worse bug than it fixed.** `EntitySetterBuilder.BuildInsertSetter` iterates *every* merged column of *every* branch (`:47`) and builds each value as `GetMemberAccessExpression(itemConstant)` (`:68`). With the proposed helper fix, a `Child1` item would still hit `Child2Field` and the four grandchild columns, producing `((Child2)const).Child2Field` — a client-evaluated downcast throwing `InvalidCastException` at runtime, replacing today's clean build-time error. The helper is the wrong altitude for the *value* side because it is the one place the item's runtime type is invisible. **Upheld → mechanism 2 split out; the correct design (caller-side selection by runtime type) goes to the new issue.**
2. **REFUTED — internal contradiction between resolved U-1 and TO-3.** U-1 declared the explicit-setter Merge sites immune; TO-3 required them to go red. Both could not stand. **Probed and upheld:** both Merge cells build successfully and fail only at execution with `SQLite … doesn't support SQL MERGE`. **The Merge obligation was removed**, not relabelled.
3. **U-3's resolution probed the wrong door.** `InsertOrReplace` is the object API; `UpsertBuilder` handles `Upsert`/`UpsertAsync`. **Probed and upheld:** `GetTable<Base>().Upsert(child1)` throws the mechanism-2 exception. U-3 is corrected and moved to the split-out issue.
4. **D-4's stated failure mode was vacuous.** `GetMemberEx` returns `foundByName` on `Base` even when member types mismatch, so the miss branch never fires for a name-collision. **Conceded** — moot now that D-4 is gone, but carried to the new issue so it is not re-derived.
5. **E-3 was unimplementable as specified** — the instances at the throwing sites are `ParameterExpression` / `ConstantExpression` / `MemberExpression`, and `WithType` exists only on `ContextRefExpression`. **Conceded** — carried to the new issue.
6. **U-2 over-attributed.** The `InsertWithOutput` cell threw at the insert-setter site, not the output site. **Conceded** → U-2 reopened and narrowed; SC-4 re-anchored on the `OUTPUT … INTO` sites.
7. **Doc contract.** `GetMemberAccessExpression`'s XML remarks and `<exception>` would have been falsified. **Moot** — the method is no longer touched; noted for the new issue.

**What it verified rather than attacked:** `ParseSetter`'s `targetRef` is declared `ContextRefExpression` (D-2's premise), `SequenceHelper.cs:492-497` is verbatim precedent, and U-4's two-reader `Alias` claim survived an independent sweep exactly as written. It called the 12-cell probe grid "real diagnostic work" that "correctly killed the old E-3".

### Correction to this plan's handling of pass 1, objection 2

Recorded here because a reader will otherwise see a conceded objection and assume it was applied correctly.

Pass 1 objected that E-3's *symmetry guard* could not reach `UpdateBuilder.cs:609` — a flat `.Set(…)` takes the `:613` else-branch. **That was correct, and the guard deserved to die.** The plan then dropped the **edit-point** as well, which did not follow: `:609` is reachable, just not from `.Set(…)`. It is reached from `ParseSetter`'s own recursion whenever the setter contains a nested generic constructor, which is exactly what a row-returning output projection over an inheritance root produces.

Caught by execution, not by review: with E-1/E-2 alone, `UpdateWithOutput` still threw `ArgumentException` from `Expression.Property` at `ParseSet:609` ← `ParseSetter:662`. E-3 is restored, `D-2` re-decided to the shared `EnsureType` helper the restored site needs, and `TO-8` added so the edit-point now has an obligation that actually fails without it.

**The transferable lesson: an objection to a test is not an objection to the edit-point it was attached to.** Both critic passes were right about the tests they attacked; this plan twice drew a wider conclusion than the objection supported, and only a run distinguished the two.

**First pass (`weak`), for the record:** E-2 had no failable obligation → TO-7 added; the `ParseSet` edit-point's symmetry guard could not reach its own line → dropped, which cascaded into re-deciding D-2 from `EnsureType` to `WithType`; U-4's probe was vacuous → redesigned, then resolved by search; `P10` under-stated the deferred surface → rewritten; Search 2's census dropped its own wrapper-helper hits → restored; "9 files" was 11.
