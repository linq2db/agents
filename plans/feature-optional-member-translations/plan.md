# Work plan: feature-optional-member-translations — PreferClientCalculation: declarable optional member translations

**Tier:** L  ·  **Status:** approved (revision 4)  ·  **Approved-at:** 2026-09-14  ·  **Branch:** feature/optional-member-translations
**Schema:** `.claude/docs/work-plan.md`  ·  **Gates:** `.claude/docs/definition-of-done.md`

## P1 Problem

With `LinqOptions.PreferClientCalculation` **enabled**, a projected interpolated string is still translated into
server-side concatenation. Reported by a user against v6: *"Even though I set it to true, linq2db continues to generate
string concatenation inside SELECT. Version before 6 did not do that, it only selected placeholder values. And in my
project it creates regressions."*

**Measured** (probe at `.build/.agents/interp-probe/`, net10.0, `LangVersion preview`, bodies of
`Expression<Func<Row,string>>`) — inside an expression tree Roslyn's `string.Concat` optimisation does **not** apply;
every interpolated form lowers to `string.Format`:

| Source form | Emitted node | Gated today? |
|---|---|---|
| `a + " " + b` | `Binary(Add, Method = String.Concat)` | yes — `VisitBinary:3039` gates on `PreferClientCalculation` |
| `$"{a} {b}"` | `String.Format(String, Object, Object)` | **no** |
| `$"{a}, {b} ({a})"` | `String.Format(String, Object, Object, Object)` | **no** |
| `$"{n}: {b}"` (int hole) | `String.Format(String, Object, Object)`, hole wrapped `Convert : Object` | **no** |
| `$"{a}"`, `$"{n:D4}"`, `$"x{a}y"` | `String.Format(String, Object)` | **no** |
| 4+ holes | `String.Format(String, Object[])` with `NewArrayInit` | **no** |
| `string.Concat(a, " ", b)` written explicitly | `String.Concat(String, String, String)` | **no** |
| `string.Concat(new[]{…})` written explicitly | `String.Concat(String[])` | **no** |

So the reported defect has a single cause: `HandleStringFormat` (`ExpressionBuildVisitor.cs:2647`, call site `:901`)
consults the option nowhere. It already handles both emitted shapes — `[_, NewArrayExpression arrayExpr]` for 4+ holes,
fixed-arity otherwise (`:2659-2663`) — and `string.Format` is registered in no translator, so `:901` is its only path.

Separately, the registry-translated methods (`string.Concat` written explicitly, `Math.*`, `Convert.*`, BCL `DateTime.*`,
`Guid.ToString()`) are excluded from the option by a second, broader cause: the gate at `:882` is
`if (!PreferClientCalculation(node) || !MappedFunctionAllowsClientCalculation(node.Method))`, and
`MappedFunctionAllowsClientCalculation` (`:2299`) is `method.GetExpressionAttribute(MappingSchema) != null`. Registry
entries carry no attribute, so the gate fails open for all 576 of them. That test was added by
[#5604](https://github.com/linq2db/linq2db/pull/5604)'s follow-up solely to keep `Sql.ToNullable` / `Sql.AsNullable`
server-side; it is the wrong question, and the user's ask is for a **declarative** way to say a translation is optional.

## P2 Success criteria

- SC-1 → TO-1: with the option on, every interpolated form in the P1 table projects raw columns and emits no `SqlConcatExpression`; with it off, each still emits one.
- SC-2 → TO-2: a **method registration** can be declared optional at its registration site, and that declaration alone decides — nothing infers optionality from an attribute, a namespace or a type name. Scope-limited by construction: translations reached via `TranslateOverrideHandler` have no registration site and are therefore never optional (P3).
- SC-3 → TO-3: `Sql.ToNullable` / `Sql.AsNullable` yield SQL `NULL` (not `default(T)`) through a missed `LEFT JOIN` with the option on, **including when their argument is itself an opted-in method or a binary expression**.
- SC-4 → TO-4: aggregate-over-grouping concat, window functions, `Sql.Concat` / `Sql.ConcatStrings` / `Sql.Expr`, GUID generation and `Sql.GetDate()` stay server-side with the option on.
- SC-5 → TO-5: with the option **off** (the default), no generated SQL changes anywhere — the baselines diff is empty.
- SC-6 → TO-7: no registration is opted in whose client-side evaluation **has no client body, or throws unconditionally for every input that binds the overload**. Deliberately *not* "or changes value" (formatting/rounding is accepted in P10 #2) and *not* data-dependent throws (`"".Replace("", …)`, `Convert.ToInt32(badString)`, `PadLeft(negative)`), which are accepted in P10 as ordinary .NET semantics.

## P3 Constraints & anti-goals (M/L)

- **No removals from `PublicAPI.Shipped.txt`.** `TranslationRegistration.RegisterMethodInternal` (`:3919`), `RegisterMemberInternal` (`:3917`) and `GetTranslation` (`:3903`) are shipped, as are the `TranslationRegistrationExtensions.Register*` overloads (`:14517`+). Every addition is a new overload or new member, never a changed signature.
- **`IMemberTranslator` is not changed.** It is public and user-implemented (#5347), and the repo targets `net462` / `netstandard2.0`, so there is no default-interface-method escape.
- **Option off ⇒ byte-identical SQL.** `PreferClientCalculation` defaults to `false`; no baselined query may move.
- **Only `RegisterMethod` registrations may be optional.** Per D-2 the scope marks method registrations and nothing else, so `VisitNew:948` and `HandleMember:1658` — which call `TranslateMember` with no `PreferClientCalculation` gate — are unaffected by construction.
- **A third translation route is out of reach by construction.** `TranslateOverrideHandler` bodies have no registration site and so cannot be declared optional: `ConvertMemberTranslatorDefault.cs:419` `ProcessToString`, `ProviderMemberTranslatorDefault.cs:108,166` `ProcessGetValueOrDefault`/`ProcessHasFlag`, `AggregateFunctionsMemberTranslatorBase.cs:42` `TranslateMinMaxSumAverage`, `StringMemberTranslatorBase.cs:107` `TranslateBinaryStringConcat`, `DateFunctionsTranslatorBase.cs:922` `TranslateTotalComparison`. Consequence: `e.Value1.GetValueOrDefault()` and `Enum.HasFlag` stay server-side under the option. (Revision 3 illustrated this with `e.Value1.ToString()`, which is wrong — `ProcessToString:450` → `ConvertToString:348` returns `null` whenever `TranslationFlags.Expression` is set, so `int.ToString()` in a projection is client-side today with the option on *or* off; critic W-2.) Named here so review reads it as scope, not as a P7 miss.
- **Anti-goal: `VisitMember`.** Members always translate to SQL; #5604 reverted that guard deliberately and plain column access flows through the same visitor.
- **Anti-goal: which SQL a provider emits for concat.** Only *where* the computation happens changes.

## P4 Unknowns (M/L)

- U-1 Does adding a member to the public `[Flags] TranslationFlags` break a consumer testing it by equality, `switch`, or an enum-keyed table? — resolved-by scout: searched `translationFlags ==`, `translationFlags !=`, `flags == TranslationFlags`, `switch (translationFlags`, `Dictionary<TranslationFlags`, `HashSet<TranslationFlags`, `(int)translationFlags` across the worktree → zero matches; all 1096 occurrences in 66 files are `HasFlag`/construction, so the addition is additive.
- U-2 Is the absent `[Expression]` attribute on `Sql.ToNullable` / `Sql.AsNullable` still load-bearing under the new mechanism? — resolved-by probe: `HandleExtension` returns false unless `attribute != null` (`ExpressionBuildVisitor.cs:1179`) and runs after `TranslateMember` (`:884` before `:890`), so a mandatory registration pins the function regardless of the attribute; the hack is no longer load-bearing and `MappedFunctionAllowsClientCalculation` can be deleted (D-4).
- U-3 Does the remote / `LinqService` path forward the new flag? — resolved-by scout: `RemoteDataContextBase.cs:173-174`, `RemoteMemberTranslator.Translate` forwards `translationFlags` verbatim; no edit needed.
- U-4 Which `IMemberTranslator` implementations bypass `MemberTranslatorBase` and so never decline? — resolved-by scout (corrected after critic round 1): **two** direct implementors, not one — `RemoteDataContextBase.cs:151` (the pass-through of U-3) and `SqlTypesTranslationDefault.cs:11`, which holds its own `readonly TranslationRegistration _registration` (`:13`) and is wired in at `ProviderMemberTranslatorDefault.cs:92`. My first census missed the second because the grep keyed on the field name `Registration.`; its registrations are all `Sql.Types.*` and stay mandatory, so the consequence is benign but the inventory row was false.
- U-5 Is `Arguments[0] is NewArrayExpression` a sound discriminator between scalar `string.Concat(string[])` and aggregate-over-grouping concat? — resolved-by decision: the question is dropped. Revision 2 asked a registration to be optional *and* its delegate to discriminate internally, which cannot both hold because the decline happens at lookup (`MemberTranslatorBase.cs:55-57`) before the delegate runs (critic O-2). Every sequence-taking overload is now excluded from the scopes outright (E-4), so no discriminator is written and no explicitly-written `string.Concat(array)` moves client-side — which costs nothing on the reported defect, since U-8 measured that interpolation never emits `string.Concat`.
- U-5b Which other registrations share the aggregate-over-grouping routing that made U-5 necessary? — resolved-by scout (critic O-1, verified): the `string.Join` overloads at `StringMemberTranslatorBase.cs:59-70` route through `TranslateStringJoin:549-553` into the same `AggregateFunctionBuilder` path as `TranslateConcatWithoutNullList:194`, so `string.Join(", ", g.Select(...))` is a GROUP_CONCAT shape — 13 such shapes in `Tests/Linq/Linq/StringJoinTests.cs:72-181` — and declining it would trip the `GroupByBuilder.cs:160` guard. Excluded by name in E-4 and pinned by TO-4.
- U-6 Are there BCL registrations that are non-deterministic or ambient and wrong to pull client-side? — resolved-by scout: searched `Registration\.Register.*(NewGuid|CreateVersion7|\.Now|UtcNow|Today|CurrentTimestamp|GetDate|Random)` across `Source/LinqToDB` → 12 hits, ten of them `Sql.*` or `RegisterMember` (out of scope per P3) but two BCL methods — `ProviderMemberTranslatorDefault.cs:64` `Guid.NewGuid()` and `:68` `Guid.CreateVersion7()` — which a "BCL ⇒ optional" rule would have moved client-side, collapsing per-row server GUIDs to one client value.
- U-7 Are registrations grouped contiguously by category, so one scope can cover a range without reordering code? — resolved-by scout: no; `StringMemberTranslatorBase.cs` interleaves (`Sql.Like`/`Sql.Replace` `:25-32`, BCL `:33-71`, `Sql.ConcatStrings` `:73-76`, BCL `string.Concat` `:79-88`, `Sql.Concat` `:89-90`), so the design uses several short scopes per file and reorders nothing.
- U-8 What does C# actually emit for each string-composition form inside an expression tree? — resolved-by probe: `.build/.agents/interp-probe/`, results in the P1 table; every interpolated form lowers to `string.Format`, refuting revision 1's assumption that `$"{a} {b}"` emits `string.Concat`.
- U-9 Does a mandatory translator's *nested* argument translation inherit `SkipOptional`, so an optional method beneath a mandatory one makes the mandatory one decline? — resolved-by probe (critic round 1 objection, verified): yes under revision 1. `TranslateToNullableMethod` forwards its flags into the argument translation (`SqlFunctionsMemberTranslatorBase.cs:26`, `:38`) and returns `null` when the result is not a placeholder; `TranslationContext.Translate` re-enters the builder (`ExpressionBuildVisitor.cs:5477-5484`) where `GetTranslationFlags` would re-derive `SkipOptional` from the node. Fixed by D-5.
- U-10 Does `Sql.Convert<string,Guid>` stay server-side under the option? — resolved-by scout (critic O-3, mechanism corrected): **no, and that is accepted.** Revision 2 named the wrong path: the live route is `Sql.cs:328 [ExpressionMethod]` → `Sql.ConvertTo<string>.From(x)` (`:334-337`) → `Linq/Expressions.cs:568` MapMember → `x.ToString()`, both expansions running at `ConvertSingleExpression:868` (`ExposeExpressionVisitor.cs:107,323`) with `:872 Visit(exposed)` returning *before* the gate at `:882`, so the un-expanded call never reaches `TranslateMember`; `ProvideReplacement`'s only caller is `MemberTranslatorBase.cs:85`, off the builder path. The terminal node is therefore the `Guid.ToString()` registration E-8 makes optional. E-8 is kept and revision 2's TO-4 pin is dropped — it was a control that could not pass — with the acceptance recorded in P10.
- U-11 Can an opted-in BCL registration throw or have no client body when evaluated client-side? — resolved-by scout (critic O-5, extended): two cases, both excluded from E-4's scopes by name. `System.Data.Linq.SqlClient.SqlMethods.Like` (`StringMemberTranslatorBase.cs:28-29`, `#if NETFRAMEWORK`) has no client body, no linq2db attribute and no built-in predicate path. `"".CompareTo(1)` (`:36`) binds `string.CompareTo(object)`, which throws `ArgumentException` client-side whenever the runtime argument is not a string — i.e. exactly when the compiler picked that overload. TO-7 covers both and must run on `net462`, because TO-6's net10 run cannot observe the first.
- U-12b Is `ResetPrevious` the only flag-clearing shape that can drop `InsideTranslation`? — resolved-by scout (critic W-8): no — `ExpressionBuildVisitor.cs:5326 UsingBuildFlags(BuildFlags.None)` *replaces* rather than unions, dropping the bit for the whole of `TryBuildSequence`; traced benign because the only `BuildPurpose.Expression` builds reachable inside a sequence build are `ForSetProjection` (`MergeProjectionHelper.cs:48`, `EagerLoadUnion.cs:203,313,471,904`) where `PreferClientCalculation` is already false, `IsSupportedSubquery:186` builds under `Sql`, and projections are built via `MakeExpression` after the `using` is disposed. Recorded because revision 3's census searched `ResetPrevious` only and structurally could not see it.
- U-12 Can `BuildFlags.InsideTranslation` be dropped between `:5483` and the `PreferClientCalculation` check? — resolved-by scout (critic O-4, unprobed by the critic): yes at one site — `BuildProxyBase{TOwner}.cs:69-74` rebuilds under `ResetPrevious` and `CombineFlags:252-253` drops every flag; reachable via `CteContext.cs:379` and `CteTableContext.cs:131`, so `Sql.ToNullable(cte.Col)` over a CTE whose projection contains an opted-in method would re-derive the collapse. Fixed in E-10 by preserving the bit across `ResetPrevious`, and pinned by the CTE case added to TO-3. The critic verified the other two `ResetPrevious` sites are safe (`MergeProjectionHelper.cs:49` is `ForSetProjection`, where `PreferClientCalculation` is already false).
- U-14 Does `string.Format` with a format specifier survive translation to SQL? — resolved-by scout (critic W-4, verified against my own earlier read): no. `QueryHelper.cs:1413` `ParamsRegex` captures a `(?<format>:[^}]+)?` group but `ConvertFormatToConcatenation:1466-1489` consumes only `key`, and `HandleStringFormat:2684-2688` casts each hole to string with no formatting, so `$"{n:D4}"` silently loses the `D4` server-side. **Pre-existing, independent of this change, and separable** — it gets its own issue rather than being bundled here (agent-rules → a distinct shared-engine fix gets its own branch/PR). Its only effect on this plan is that TO-1's option-off arm cannot assert the value for that one form.
- U-13 Is `TranslationContext.Translate:5483` the only re-entry a translator can use, so D-5's guard is sufficient? — resolved-by scout (critic round 2): almost — the critic confirmed `:5483` is the only member that re-enters the builder with the *caller's* purpose (`ConvertToSql:283`, `BuildAggregationFunction:534,733` and `GetAggregationContext:5527` all force `Sql`/`Traverse`, where `PreferClientCalculation` is false by construction), and that `CombineBuildFlags:222/264` unions while `StateHolder.Dispose:206` restores, so the flag cannot leak to sibling nodes. The one exception is `MemberTranslatorBase.cs:88`, where `ProvideReplacement` recurses same-object with `translationFlags` rather than through `:5483`; E-3 strips `SkipOptional` there.

## P5 Decisions (M/L; rejected alternatives mandatory at L)

### D-1 — Declare optionality at the registration, carried to the translator by a `TranslationFlags` member

- **chosen:** new `TranslationFlags.SkipOptional`; `TranslationRegistration` records which *method* registrations are optional; `MemberTranslatorBase.Translate` returns `null` when the flag is set and the registration opted in.
- **rejected:** a heuristic in the visitor's gate (declaring type is BCL / no sequence parameter) — the user asked for a declarative mechanism, and U-6 and U-11 show the heuristic is wrong for `Guid.NewGuid()` and `SqlMethods.Like`.
- **rejected:** a new member on `IMemberTranslator` so the visitor can ask before calling — breaks a public, user-implemented interface with no DIM escape on `net462`/`netstandard2.0` (P3).
- **why this:** `CombinedMemberTranslator.Translate:27` forwards flags unchanged and no provider translator registers anything of its own (P7), so one edit in the base reaches all 15 providers and the remote path at once.
- **failure mode of the choice:** a user-written `IMemberTranslator` not deriving from `MemberTranslatorBase` ignores the flag and keeps translating — the safe direction (today's behaviour); U-4 shows both in-tree cases are safe.

### D-2 — Opt in with a scope that marks method registrations only

- **chosen:** `TranslationRegistration.OptionalScope()` returning `IDisposable`; **only `RegisterMethodInternal` consults it**. `RegisterMemberInternal`, `RegisterConstructorInternal`, `RegisterBinaryInternal`, `RegisterUnaryInternal` and `RegisterMemberReplacement` ignore the scope entirely and are never optional. Plus one additive `GetTranslation(MemberInfoWithType, out bool isOptional)` overload.
- **rejected:** `bool isOptional = false` on `RegisterMethodInternal` and the 7 `RegisterMethod` extension overloads — every one of those signatures is in `PublicAPI.Shipped.txt`, making it a shipped-API removal plus ApiCompat suppressions for a purely internal need (P3).
- **rejected:** a scope that marks every registration kind — that is what revision 1 left open, and it contradicted P3 while silently capturing `"".Length` (`StringMemberTranslatorBase.cs:33`) and the Date file's 49 `RegisterMember` / 13 binary-unary registrations.
- **why this:** it closes the accepted set, keeps `VisitNew:948` and `HandleMember:1658` (which call `TranslateMember` ungated) unreachable by the mechanism, and keeps the diff as category blocks rather than hundreds of near-identical line edits.
- **implementation note (critic O-8):** `RegisterMethodInternal:50` overwrites `_translations[key]`, so the optional mark must be written *after* the overwrite and **cleared** when a re-registration of the same key happens outside a scope. Every `*TranslatorBase` is `public`, so a provider subclass re-registering a key is a supported move; without the clear the last registration wins for the delegate but not for optionality.
- **failure mode of the choice:** a scope is positional, so a method registration later inserted inside a block silently inherits optional — mitigated by TO-4 asserting the pins and by recording each scope's exact line range in E-4…E-8 so G-06 is checkable.

### D-3 — `string.Format` is gated at its call site, and that is the fix for the reported bug

- **chosen:** `if (!PreferClientCalculation(node) && HandleStringFormat(node, out …))` at `:901`.
- **rejected:** registering the `string.Format` overloads in `StringMemberTranslatorBase` so they can be declared optional like everything else — a larger refactor of a path that also serves `FormatAsExpression`.
- **why this:** U-8 measured that every interpolated form lowers to `string.Format`, and `HandleStringFormat` is not a registry entry, so there is nothing to declare and this one gate closes SC-1 on its own.
- **failure mode of the choice:** the mechanism has two shapes, and a reader grepping for `OptionalScope` will not find this gate — mitigated by a comment at the call site naming the asymmetry.

### D-4 — Delete `MappedFunctionAllowsClientCalculation` and split the two translation routes

- **chosen:** always call `TranslateMember` (it self-declines per D-1); gate only `HandleExtension` on `!PreferClientCalculation(node)`.
- **rejected:** keeping the attribute test alongside the new flag — two competing admission rules, and the attribute one asks the wrong question (it admits `Sql.Lower` because it has an attribute and refuses `string.Concat` because it has none).
- **rejected:** restoring `[Expression]` on `Sql.ToNullable` / `Sql.AsNullable` now that U-2 shows it is safe — it buys nothing and adds a `ConvertExtension` fallback reachable only in the case that must stay client-side.
- **why this:** the pin becomes explicit (a mandatory registration) instead of implicit (an absent attribute).
- **failure mode of the choice:** a member that is **both** attributed and registered flips from the attribute route to the registry route when the option is on. Searched: registered `Sql.*` functions carry no `[Expression]` (`Sql.cs:712,840,874,1008-1165`) and `Sql.Expr` is `ServerSideOnly` (`Sql.Expressions.cs:561`), so no in-tree member is both. It can only bite user code carrying a `[Sql.Function]` *and* a #5347 registration — recorded in P10.

### D-5 — `SkipOptional` does not survive into a nested translation

- **chosen:** three parts. (a) `TranslationContext.Translate` (`ExpressionBuildVisitor.cs:5483`) passes a new internal `BuildFlags.InsideTranslation` instead of `BuildFlags.None`, and `PreferClientCalculation` returns false when that flag is set. (b) `CombineFlags:252-253` preserves `InsideTranslation` across `ResetPrevious`, closing the CTE-proxy hole of U-12. (c) `MemberTranslatorBase.cs:88` strips `SkipOptional` before recursing on a replacement, the one re-entry that bypasses `:5483` (U-13).
- **rejected:** clearing `SkipOptional` in `MemberTranslatorBase` before invoking a mandatory translate func — insufficient, because `:5483` hardcodes `BuildFlags.None` and `GetTranslationFlags` re-derives the flag from the node on re-entry, so it would come straight back.
- **rejected:** leaving it, and telling users not to nest — U-9 shows `Sql.ToNullable(Math.Abs(j.Value1))` over a missed `LEFT JOIN` would then read `0` instead of `null`, which is precisely the #5604 regression SC-3 forbids.
- **why this:** any translate func that is *running* has already been admitted (mandatory, or optional and not skipped), so its arguments must be translatable — the rule is uniform and needs no per-translator knowledge. `BuildFlags` is an internal enum (`BuildFlags.cs:6`), so the new bit costs no public surface.
- **failure mode of the choice:** it also suppresses the gate for binary arguments inside a translation, e.g. `Sql.ToNullable(j.Value1 + 1)` — today an unguarded hole at `VisitBinary:3039`. That is **intended**: the same rule fixes a pre-existing defect, and TO-3 asserts it rather than leaving it undeclared.

## P6 Edit-points

- E-1 `Source/LinqToDB/Linq/Translation/TranslationFlags.cs:TranslationFlags` — add `SkipOptional = 1 << 4` with an XML doc.
- E-2 `Source/LinqToDB/Internal/DataProvider/Translation/TranslationRegistration.cs:TranslationRegistration` — record optional method registrations; add `OptionalScope()` (consulted by `RegisterMethodInternal` only, per D-2) and an additive `GetTranslation(..., out bool isOptional)` overload.
- E-3 `Source/LinqToDB/Internal/DataProvider/Translation/MemberTranslatorBase.cs:Translate` — decline an optional registration when `SkipOptional` is set.
- E-4 `Source/LinqToDB/Internal/DataProvider/Translation/StringMemberTranslatorBase.cs` — optional scopes over exactly the BCL `string.*` **scalar method** registrations at `:35` (`CompareTo(string)`), `:42-55`, `:57`, `:79-84` (the six fixed-arity `string.Concat` overloads). Explicitly **outside** every scope, by name: `Sql.Like` `:25-26`; `SqlMethods.Like` `:28-29` (U-11, no client body on netfx); `Sql.Replace` `:31-32`; `"".Length` `:33` (a member); `"".CompareTo(1)` `:36` (U-11, `string.CompareTo(object)` throws client-side); `string.Join` `:59-70` (U-5b, aggregate routing); `Sql.ConcatStrings` `:73-76`; `string.Concat` sequence overloads `:85-88` (U-5, aggregate routing); `Sql.Concat` `:89-90`. No translator delegate gains an internal `SkipOptional` discriminator — revision 2's attempt to have both was incoherent (U-5).
- E-5 `Source/LinqToDB/Internal/DataProvider/Translation/ConvertMemberTranslatorDefault.cs` — optional scope over `:41-337` (every registration body there is `System.Convert`); `RegisterMemberReplacement` at `:343` stays outside (D-2, U-10).
- E-6 `Source/LinqToDB/Internal/DataProvider/Translation/MathMemberTranslatorBase.cs` — optional scopes over the BCL `Math.*` ranges `:24-34`, `:39-49`, `:54-60`, `:73-76`, `:82-85`, `:91-94`; the `Sql.*` ranges `:62-68`, `:77-80`, `:86-89`, `:95-98`, `:104-105` stay outside. `:103` (`Math.Pow`) is inside a BCL range but **inert** — `Linq/Expressions.cs:626` rewrites `Math.Pow` before the gate, so the registration is dead; kept in the scope for range contiguity and recorded in P10 rather than claimed as coverage.
- E-7 `Source/LinqToDB/Internal/DataProvider/Translation/DateFunctionsTranslatorBase.cs` — optional scopes over exactly the 17 BCL method registrations at `:57-63`, `:95-101`, `:120-122`; the 11 `Sql.*` method registrations (`:26,27,39,55,65,67,93,103,109,118,124`), all 49 `RegisterMember`, the 4 `RegisterConstructor` and the 13 binary/unary registrations (`:269-310`) stay outside.
- E-8 `Source/LinqToDB/Internal/DataProvider/Translation/GuidMemberTranslatorBase.cs:15-16` — both `Guid.ToString()` registrations optional.
- E-9 `Source/LinqToDB/Internal/Linq/Builder/ExpressionBuildVisitor.cs` — `GetTranslationFlags(Expression node)` ORs in `SkipOptional`; delete `MappedFunctionAllowsClientCalculation` and split the gate at `:882-894` per D-4; gate `HandleStringFormat` at `:901` per D-3; refresh the comment at `:877-881` and the XML doc at `:2284`.
- E-10 `Source/LinqToDB/Internal/Linq/Builder/BuildFlags.cs` + `ExpressionBuildVisitor.cs:5483,2284,252-253` + `MemberTranslatorBase.cs:88` — add `InsideTranslation = 1 << 9`; pass it from `TranslationContext.Translate`; make `PreferClientCalculation` return false under it; preserve it across `ResetPrevious` in `CombineFlags` (U-12); strip `SkipOptional` before the `ProvideReplacement` recursion (U-13). All three parts of D-5.
- E-11 `Source/LinqToDB/Sql/Sql.cs:71-73,94-96` — rewrite the two comments justifying the absent `[Expression]` attribute by `PreferClientCalculation`; that justification is false after E-9 (U-2).
- E-12 `Source/LinqToDB/LinqOptions.cs:156-164` and `Source/LinqToDB/DataOptionsExtensions.cs:326-333,651-658` — restate the option's XML docs in terms of the new rule and name string interpolation explicitly.
- E-13 `Source/LinqToDB/PublicAPI/PublicAPI.Unshipped.txt` — entries for `TranslationFlags.SkipOptional`, `TranslationRegistration.OptionalScope()` and the `GetTranslation` overload.
- E-14 `Tests/Linq/Linq/PreferClientCalculationTests.cs` — the tests in P8.
- E-15 Deliberately NOT edited, mandatory registrations: `AggregateFunctionsMemberTranslatorBase.cs` (8), `SqlFunctionsMemberTranslatorBase.cs` (5), `ProviderMemberTranslatorDefault.cs` (4, incl. `Guid.NewGuid` `:64` / `Guid.CreateVersion7` `:68` per U-6), `Linq/Translation/WindowFunctionsMemberTranslator.cs` (117), `SqlTypesTranslationDefault.cs` (its own `_registration`, per U-4).

## P7 Impact map (M/L)

- `Source/LinqToDB/**` `TranslationFlags` consumers — searched `translationFlags ==|!=`, `flags == TranslationFlags`, `switch (translationFlags`, `Dictionary<TranslationFlags`, `HashSet<TranslationFlags`, `(int)translationFlags`: zero matches, all 1096 occurrences across 66 files are `HasFlag`/construction — covered by E-1
- `ExpressionBuildVisitor.cs:5483` — `TranslationContext.Translate` re-enters `BuildSqlExpression` with a hardcoded `BuildFlags.None`, so no visitor-instance state crosses the nesting boundary; searched `public Expression Translate(Expression expression, TranslationFlags` — covered by E-10
- `SqlFunctionsMemberTranslatorBase.cs:26,38` — `ToNullable`/`AsNullable` forward `translationFlags` into argument translation and decline on a non-placeholder; searched `translationContext\.Translate\([^,)]+,\s*translationFlags\)` across `Source/LinqToDB` (34 forwarding sites: Date 28, SqlFunctions 2, MemberTranslatorBase 2, String 1) — covered by E-10
- `Source/LinqToDB/Remote/RemoteDataContextBase.cs:151,173` — direct `IMemberTranslator` implementor, forwards flags verbatim; searched `: IMemberTranslator` and `IMemberTranslator` across the worktree — covered by E-3
- `Source/LinqToDB/Internal/DataProvider/Translation/SqlTypesTranslationDefault.cs:11,13` — second direct implementor with its own `_registration`, wired at `ProviderMemberTranslatorDefault.cs:92`; all registrations are `Sql.Types.*` members and stay mandatory — covered by E-15
- `Source/LinqToDB.FSharp/FSharpMemberTranslator.fs:19` — derives `MemberTranslatorBase`, registers nothing, overrides `TranslateOverrideHandler` only, so it ignores the flag and keeps option/`IsSome` translation server-side — out-of-scope
- `Source/LinqToDB/Internal/DataProvider/<Provider>/Translation/*.cs` — searched `Registration.Register` across `Source/LinqToDB/Internal/DataProvider/**`: zero provider-specific translators register anything; all 15 customize via `Translate*` virtuals, so one base edit covers every provider — covered by E-4
- `Sql.cs:328` → `Sql.ConvertTo<string>.From` `:334-337` → `Linq/Expressions.cs:568` → `Guid.ToString()` — the live `Sql.Convert<string,Guid>` route, both expansions running at `ConvertSingleExpression:868` (`ExposeExpressionVisitor.cs:107,323`) with `:872` returning before the gate at `:882`, so the terminal node is the registration E-8 opts in and the call follows it client-side; searched `ExpressionMethod|ConvertMember\(|isSingleConvert` — deferred: accepted in P10, its `ExpressionMethod` says it *is* `ToString()`
- `MemberTranslatorBase.cs:85-88` — `ProvideReplacement` recurses same-object carrying `translationFlags`, bypassing `TranslationContext.Translate:5483`, so a mandatory replacement whose target is optional would decline; searched `ProvideReplacement\(|GetMemberReplacementInfo\(` (single caller) — covered by E-10
- `StringMemberTranslatorBase.cs:59-70` — the `string.Join` overloads route via `TranslateStringJoin:549-553` to `AggregateFunctionBuilder`, the same aggregate path as `TranslateConcatWithoutNullList:194`; searched `string\.Join\(…g\.Select` across `Tests/` (13 shapes, `StringJoinTests.cs:72-181`) — covered by E-4 exclusion, pinned by TO-4
- `BuildProxyBase{TOwner}.cs:69-74` + `CombineFlags:252-253` — `ResetPrevious` drops every flag including `InsideTranslation`, reachable via `CteContext.cs:379` / `CteTableContext.cs:131`; searched `ResetPrevious` across `Source/LinqToDB` (3 sites; `MergeProjectionHelper.cs:49` is `ForSetProjection` and already safe) — covered by E-10
- `ExpressionBuildVisitor.cs:393` — `HasTranslation` also calls `TranslateMember` but has no callers; searched `HasTranslation` (definition and self-recursion only) — out-of-scope
- `ConvertMemberTranslatorDefault.cs:261-276` — the `Convert.ToString(...)` **registrations** route to `TranslateConvertToString:700` → `TranslateConvertDefault:587`, which has no `TranslationFlags.Expression` check and emits `CAST` (`:597`), so opting them in **is** a server→client change and needs test coverage; revision 3 wrongly cited `:346-349`, which is `ConvertToString`, the separate override-handler path (critic W-1) — covered by E-5
- `Linq/Expressions.cs:626` — the legacy MapMember rewrites `Math.Pow` → `Sql.Power(x,y)!.Value` and `ExposeExpressionVisitor.cs:154 ConvertMethod(node)` applies it unconditionally before `:882`, so `MathMemberTranslatorBase.cs:103` is dead and an E-6 scope over it is inert: `Math.Pow` stays server-side via the mandatory `Sql.Power` registration `:104` while `Math.Abs` moves client-side; TO-6 cannot observe the asymmetry (critic W-3) — deferred: recorded in P10, the scope is harmless but must not be read as coverage
- `StringMemberTranslatorBase.cs:28-29` — `SqlMethods.Like` is netfx-only with no client body; searched `SqlMethods` across `Source/LinqToDB` and `Like` across `ExpressionBuildVisitor.cs` (only `CompareNulls.LikeClr`) — covered by E-4 exclusion, pinned by TO-7
- `Linq/Expressions.cs:611-643` — the legacy `MapMember` table rewrites 19 `Math.*` methods to attributed `Sql.*` via `ConvertSingleExpression:868` *before* the gate, disjoint from `MathMemberTranslatorBase`'s registrations, so E-6's scopes are not dead — covered by E-6
- `ExpressionBuildVisitor.cs:884,948,1658,2351,2374,3045,3674` — the seven `TranslateMember` call sites; `VisitUnary:2346` and `VisitBinary:3039` gate before it, while `VisitNew:948`, `HandleMember:1658` and `TryConvertPredicate` do not — out-of-scope: P3 restricts optionality to method registrations, so no member or constructor registration is ever optional and these two ungated sites cannot decline
- `ExpressionBuildVisitor.cs:5688` — `GetAlreadyTranslated` returns a cached translation before the translator can decline, so a method already translated for a `WHERE` stays server-side in the projection; searched `GetAlreadyTranslated|RegisterTranslatedSql` — deferred: an inconsistency, not a wrong value; recorded in P10
- `ExpressionBuildVisitor.cs:3034` — a second `Builder._memberTranslator.Translate(...)` passing a hardcoded `TranslationFlags.Expression` has-translation probe that must keep seeing the un-declined registry — deferred: intentional, probe semantics
- Registration inventory, `git grep -c "Registration.Register"` — Convert 241, Window 117, Date 94, Math 63, String 42, Aggregate 8, SqlFunctions 5, Provider 4, Guid 2 = 576, **counted by line not by registered member**; the per-file BCL/`Sql.*` split must be re-derived by declaring type during implementation — covered by E-5
- `Tests/Linq/Linq/{StringConcatTests,OperatorsTests,MemberTranslatorTests}.cs`, `Tests/Linq/UserTests/Issue5347Tests.cs`, `Tests/Base/TestProviders/TestNoopProvider.cs` — user-translator fixtures deriving from `MemberTranslatorBase` that register nothing optional — covered by E-14

## P8 Test obligations (M/L)

- TO-1 each interpolated form from the P1 table, one test with `[Values] bool preferClient`, asserting `(sq.Find(e => e is SqlConcatExpression) != null).ShouldBe(!preferClient)` and `sq.Select.Columns.All(c => c.Expression is SqlField).ShouldBe(preferClient)`, with a seeded `null` row so C# `null → ""` is compared against the server-side `COALESCE`; `AssertQuery` runs in both modes **except** for the format-specifier hole `$"{n:D4}"`, where the option-off arm asserts only the AST because a pre-existing defect (U-14) makes the server-side value wrong — proof: red-green
- TO-1c the `$"{n:D4}"` option-**on** arm asserts the materialized value is correct (client-side formatting honours `D4`), which is the half U-14 does not block — proof: control
- TO-1b the registry path tested independently of Roslyn's lowering, as **explicitly written** `string.Concat(a, " ", b)` and `string.Concat(new[]{…})` plus `a + " " + b`, same assertions — proof: red-green
- TO-2 a test-local `MemberTranslatorBase` registering one method inside an `OptionalScope()` and one outside, asserting the first moves client-side under the option and the second does not; plus a `RegisterMember` inside a scope asserted to stay server-side (D-2's closed set) — proof: control
- TO-3 SC-3's nesting guard: `Sql.ToNullable(Math.Abs(j.Value1))`, `(int?)Sql.AsNullable(Math.Abs(j.Value1))`, `Sql.ToNullable(j.Value1 + 1)` and a CTE case `Sql.ToNullable(cte.Col)` whose CTE projection contains an opted-in method (U-12's `ResetPrevious` path), each over a missed `LEFT JOIN` with the option on and each required to read `null`, alongside the existing `ToNullableOverMissingLeftJoinReturnsNull`, `AsNullableOverMissingLeftJoinReturnsNull` and `ToNullableOverNonSqlArgumentEvaluatesClientSide` — proof: red-green
- TO-4 pins asserting each construct stays in SQL with the option on — **both** aggregate-over-grouping shapes, `string.Concat(g.Select(x => x.Name))` and `string.Join(", ", g.Select(x => x.Name))` (U-5/U-5b: one pin per aggregate-routing delegate, so re-introducing the class is caught by a test), plus a window function, `Sql.Concat`, `Sql.ConcatStrings`, `Sql.Expr<string>($"…")`, `Guid.NewGuid()`, `Sql.GetDate()` and a set projection containing an interpolated string. Revision 2's `Sql.Convert<string,Guid>` pin is **dropped** — U-10 shows it cannot pass — proof: control
- TO-5 symmetry guard on the unchanged path — a full `Tests.Linq` run with the option off, existing `StringConcatTests` / Math / Convert / Date / Window suites unmoved and an empty baselines diff — proof: characterization
- TO-6 bulk gate for the opted-in registrations TO-1…TO-4 do not name individually — one `Tests.Linq` run with `Configuration.Linq.PreferClientCalculation = true` forced on, read as correctness-only (`AssertQuery` failures and exceptions are findings; baseline diffs are expected noise and the baselines clone is restored afterwards, never staged) — proof: control
- TO-7 SC-6's no-client-body set: `SqlMethods.Like(e.Name, "A%")` on `net462` and `e.Name.CompareTo((object)1)` on every TFM, each in a projection with the option on, must still translate — catching either registration wrongly captured by an E-4 scope — proof: control

## P9 Verification gates

Derived by `work-plan.ps1 -Action gates`: all nine apply. Nothing has run yet — this plan precedes the first source edit.

- G-01: (pending) — `/test run PreferClientCalculationTests` on SQLite then `[DataSources]`; TO-1 and TO-3's reds must be observed before E-1…E-10 land, never inferred
- G-02: (pending) — baselines diff with the option off must be empty (TO-5); a non-empty diff means the mechanism leaked into the default path
- G-03: (pending) — `PublicAPI.Unshipped.txt` entries per E-13
- G-04: (pending) — `/api-baselines`; expect no `CompatibilitySuppressions.xml` change, since P3 forbids shipped-signature edits, so a suppression appearing is evidence D-2 was violated
- G-05: (pending) — `dotnet build Source/LinqToDB/LinqToDB.csproj -c Release -f netstandard2.0`, `-f net10.0`, and `-f net462` for TO-7
- G-06: (pending) — no reordering of existing registrations (U-7); each scope's line range matches the range recorded in E-4…E-8
- G-07: (pending) — nothing under `Tests/Tests.Playground/` staged; the `.build/.agents/interp-probe/` probe is scratch and is never committed
- G-08: (pending) — cross-cutting core proven by TO-2, TO-3, TO-4, TO-6, TO-7
- G-09: (pending) — `/review-pr` before the PR leaves draft

## P10 Adjudicated (M/L)

- Opting a registration in **widens what the option does**, by design: a projection that produced one computed SQL column may now select N raw columns, so more data crosses the wire. That is the v5 behaviour the option exists to restore and it only happens when the user enables it. Not a finding.
- Client-side evaluation of a BCL function can differ from the provider's SQL function in formatting or rounding (`double.ToString()` vs `CAST`, `Math.Round` midpoint rules). Client-side matches LINQ-to-Objects, which is what `AssertQuery` compares against and what v5 did. Not a finding.
- `string.Format` is gated at its call site rather than declared optional (D-3). The asymmetry is deliberate; flagging it needs an argument against D-3's rejected alternative, not a restatement of the asymmetry.
- `GetAlreadyTranslated` (`ExpressionBuildVisitor.cs:5688`) short-circuits before the decline, so the same method translated earlier for a `WHERE` stays server-side in the projection. The cache key is `(path, selectQuery)` and carries no flags (`:635-656`), so the result **may differ** per the rounding/formatting entry above: `Where(e => Math.Round(e.D) > 1).Select(e => Math.Round(e.D))` returns server rounding while the same `Select` without the `Where` returns client rounding. Accepted because the cache is load-bearing for query-build cost and making it flag-aware widens the change into the translation cache. (Revision 2 claimed "the value is correct either way", which contradicted the entry above — critic O-6.)
- `Sql.Convert<string,Guid>` moves client-side under the option, because it expands to `Guid.ToString()` before reaching the gate (U-10) and E-8 opts that registration in. Accepted: its `[ExpressionMethod]` declares that it *is* `ToString()`, so following `ToString()` is the consistent outcome rather than an exception to be carved out.
- **Classification is by registered-member declaring type, not by translator routing** — the user's explicit call after both critic rounds surfaced aggregate-routing registrations (`string.Concat(IEnumerable)`, `string.Join`) that share a declaring type with safe scalar overloads. The accepted consequence is that a *future* registration whose delegate reaches `AggregateFunctionBuilder` can be opted in by mistake, since nothing mechanical prevents it. The mitigation is the **by-name exclusion list in E-4 plus G-06's range check** — not TO-4, whose pins bind one overload's shape each (`string.Join(", ", g.Select(...))` binds `:59`/`:60`) and would not catch a future registration with a different signature routing to the same `TranslateStringJoin:830` (critic W-6). Not a finding; re-proposing routing-based classification needs an argument against that trade, not a restatement of it.
- Data-dependent client-side exceptions are accepted as ordinary .NET semantics: an opted-in method evaluated on the client throws where SQL would have returned a value — `"".Replace("", …)` (`StringMemberTranslatorBase.cs:42`, in scope), `Convert.ToInt32(badString)` (E-5), `PadLeft(negative)`. SC-6 excludes only *unconditional* throws and no-client-body cases. The option is opt-in and client evaluation is what v5 did, so matching LINQ-to-Objects — exceptions included — is the intended semantic.
- `Math.Pow` is inert under the option: `Linq/Expressions.cs:626` rewrites it to `Sql.Power` before the gate, so `MathMemberTranslatorBase.cs:103` is dead code and `Math.Pow` stays server-side while `Math.Abs` moves. Accepted as pre-existing legacy-MapMember precedence, not introduced here; the E-6 scope over `:103` is harmless but is not coverage.
- A member carrying **both** a `[Sql.Function]` attribute and a #5347 user registration flips from the attribute route to the registry route under D-4. No in-tree member is both; user code could be. Accepted.

## P11 Amendments (M/L)

_None._

## P12 Critic verdict (M/L)

Round 1 — **refuted** (`fable`). Objections accepted and the plan revised: (1) nested translation re-derived `SkipOptional`,
re-opening the #5604 NULL collapse for `Sql.ToNullable(Math.Abs(col))` — fixed by the new D-5 and TO-3, with the
pre-existing binary-argument hole explicitly folded into the same rule; (2) E-4's opt-in set included
`SqlMethods.Like`, which has no client body on `net462` — excluded by name, TO-7 added; (3) E-7's "41 BCL / 53 `Sql.*`"
split was an artifact of a line grep matching `Sql.DateParts.*` inside *translator* lambdas — recounted by registered
member to 17 BCL / 11 `Sql.*`, and the same error flagged for E-5/E-6; (4) P3 and E-2 contradicted each other on the
scope's accepted set — closed in D-2 to method registrations only; (5) U-4's "exactly one direct implementor" was false —
`SqlTypesTranslationDefault` added; (6) the `Sql.Convert<string,Guid>` → `Guid.ToString()` replacement row was missing —
added to P7 and TO-4; (7) TO-1 rested on an unprobed compiler claim — since probed (U-8), which refuted revision 1's P1
table and split TO-1b out so the registry path is tested independently of Roslyn's lowering. Two minor objections were
adjudicated rather than fixed (translation cache, D-4's failure-mode wording) and are recorded in P10.
Round 2 — **refuted** (`fable`). The architecture survived: the critic verified D-5's placement independently
(`TranslationContext.Translate:5483` is the only translator→builder re-entry carrying the caller's purpose; every other
re-entry is already `Sql`/`Traverse` where `PreferClientCalculation` is false by construction) and confirmed D-2, D-3,
D-4 and the option-off byte-identity claim. What failed is the **edit surface**, in the same class of error as round 1 —
registrations enumerated by grep rather than by registered member *and by translator routing*:

- **O-1** E-4's scope `:59-71` captures the `string.Join(sep, IEnumerable<T>)` overloads, which route through
  `TranslateStringJoin:549-553` to the same `AggregateFunctionBuilder` path as `string.Concat(IEnumerable)`. Declining
  them breaks `string.Join(", ", g.Select(...))` — 13 such shapes in `Tests/Linq/Linq/StringJoinTests.cs:72-181` — via
  the `GroupByBuilder.cs:160` guard. The plan carved this out for Concat (U-5) and missed the mirror.
- **O-2** E-4 is self-contradictory: it puts `:79-88` in an optional scope *and* asks
  `TranslateConcatWithoutNullList` to discriminate internally. E-3 declines before the func runs
  (`MemberTranslatorBase.cs:55-57`), so the discriminator is unreachable and the aggregate Concat form declines too.
  Only one of the two sentences can ship.
- **O-3** P7's `Sql.Convert<string,Guid>` row names the wrong mechanism. The live path is
  `Sql.cs:328 [ExpressionMethod]` → `Expressions.cs:568` → `Guid.ToString()`, expanded at `ConvertSingleExpression:868`
  and returned at `:872` *before* `:882`; `ProvideReplacement`'s only caller is `MemberTranslatorBase.cs:85`, off the
  builder path. So E-8 makes the terminal node optional and TO-4's pin is a control that cannot pass.
- **O-4** D-5 has a named hole: `BuildProxyBase{TOwner}.cs:69-74` rebuilds with `ResetPrevious`, and
  `CombineFlags:252-253` drops every flag including `InsideTranslation`; reachable via `CteContext.cs:379` /
  `CteTableContext.cs:131`. Critic marks it unprobed.
- **O-5** SC-6 ("throw **or change value**") contradicts P10 #2 (rounding differences accepted); and
  `StringMemberTranslatorBase.cs:36` `"".CompareTo(1)` binds `string.CompareTo(object)`, which throws client-side.
- **O-6** P10's `GetAlreadyTranslated` wording ("value is correct either way") is false given P10 #2 — the cache key
  (`:635-656`) carries no flags, so a `Where` upstream changes the projection's result.
- **O-7** SC-2 overclaims: `TranslateOverrideHandler` is a third translation route with no registration site
  (`ConvertMemberTranslatorDefault.cs:419`, `ProviderMemberTranslatorDefault.cs:108,166`, and four more), so
  `e.Value1.ToString()` cannot be declared optional at all.
- **O-8** `RegisterMethodInternal:50` overwrites `_translations[key]`; the optional mark must follow the overwrite or a
  subclass re-registering outside a scope keeps the stale mark.

Revision 3 — authored after the user explicitly authorised a third round past `/work-plan` step 7's one-round cap, and
chose to **keep declaring-type classification** over routing-based classification. All eight objections addressed:
O-1 `string.Join` `:59-70` excluded by name (U-5b) and pinned in TO-4; O-2 resolved by excluding the sequence overloads
`:85-88` outright and writing no internal discriminator (U-5); O-3 P7 row rewritten to the real
`[ExpressionMethod]` → `Expressions.cs:568` → `Guid.ToString()` chain, TO-4's unpassable pin dropped and the outcome
accepted in P10 (U-10); O-4 `CombineFlags` preserves `InsideTranslation` across `ResetPrevious`, with a CTE case added
to TO-3 (U-12); O-5 SC-6 restated to "no client body / throws by BCL contract" and `"".CompareTo(1)` `:36` excluded
(U-11); O-6 P10's cache wording corrected to "may differ"; O-7 the `TranslateOverrideHandler` route named in P3 and
SC-2 narrowed; O-8 the registration-overwrite ordering recorded in D-2. The routing-vs-declaring-type trade is recorded
in P10 as adjudicated, so review does not re-raise it.
Round 3 — **weak** (`fable`). No objection reached the design. The critic ran an independent census and confirmed:
E-4's exclusion list is **complete for the aggregate class** (every in-scope String delegate is aggregate-free; routing
is only `:194,553,560,567,206`, all excluded); D-5's three parts close **every** translator→builder re-entry it could
find; the five `TranslateOverrideHandler` bodies are the only override route and no provider overrides
`TranslateMethodCall`/`TranslateMemberExpression`, confirming P10 #5; D-4's "no in-tree member is both attributed and
registered" survived a full attribute sweep of the registered `Sql.*` surface; U-1 was re-confirmed (one internal
`== TranslationFlags.None`); `Math.Abs` is registry-only, so TO-3 genuinely exercises the registry-decline path.

Eight residual objections, all evidence hygiene rather than design, and all folded in: W-1 P7's `Convert.ToString` row
cited the override-handler path instead of the registrations' real route (`:700` → `:587`, emits `CAST`) so opting them
in *is* a behaviour change; W-2 P3's `e.Value1.ToString()` example described behaviour that does not exist (it is
client-side today either way) and was replaced with `GetValueOrDefault` / `HasFlag`; W-3 `Math.Pow` is inert via the
legacy MapMember, now recorded rather than claimed as disjointness; W-4 `$"{n:D4}"` loses its format specifier
server-side — a **pre-existing, separable defect** now tracked as U-14 and due its own issue, which also means TO-1's
option-off arm cannot assert that form's value; W-5 SC-6 restated to *unconditional* throws with data-dependent ones
adjudicated in P10; W-6 P10 #6's mitigation corrected from "TO-4 pins" to "by-name exclusion list + G-06"; W-7 E-5/E-6
ranges written out instead of deferred; W-8 U-12b records `:5326 UsingBuildFlags(BuildFlags.None)` as a second
flag-clearing shape the `ResetPrevious`-only census could not see, traced benign by purpose.

Carried forward as the strongest case against the design: the exclusion lists for E-5 (Convert), E-6 (Math), E-7 (Date)
and E-8 (Guid) have **not** had the delegate-level census that E-4 received — completeness there is reasoned, not
measured, and TO-6 is the only thing standing behind it.
