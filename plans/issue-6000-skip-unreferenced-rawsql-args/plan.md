# Work plan: issue-6000-skip-unreferenced-rawsql-args — FormattableStringHelper + DataParameter-intent filter for unreferenced raw SQL arguments

**Tier:** L  ·  **Status:** approved  ·  **Approved-at:** 2026-10-10 (user, after critic round 1 `weak`, all objections addressed)  ·  **Branch:** issue/6000-skip-unreferenced-rawsql-args
**Schema:** `.claude/docs/work-plan.md`  ·  **Gates:** `.claude/docs/definition-of-done.md`

Stacked on #6003 (`issue/6000-fix-nested-fromsql-cache`, head `4404711ae`). Replaces the previous design of PR #6008 (commit `2bcb6bc29`, name-matching in `BasicSqlBuilder`), which is discarded; its four tests are reused.

## P1 Problem

Since #6003 the interpolated / captured arguments of `FromSql` / `FromSqlScalar` / `Sql.Expr` become query parameters. An argument the format never references by `{n}` still becomes a parameter registered on the command. Sybase ASE rejects a command carrying a parameter its SQL does not use. Repro (old #6008 test `UnreferencedArgumentIsNotSent`): `db.FromSqlScalar<int>(FormattableStringFactory.Create("SELECT … WHERE id = {0}", 1, 99))` nested in `p.ID.In(...)` — on master+#6003 the command carries a parameter with value 99; on Sybase the query fails.

Constraint from the old design's history: a `DataParameter` argument is referenced **by name or position**, not by `{n}` (`FromSql("… = @p", new DataParameter("p", 2))`, Access/HANA `?`). Dropping those breaks working queries (`MiniProfilerTests.TestMySqlData` read a zero date when the old design dropped them).

Second, structural: `FormattableString` handling is spread across 5 files (shape match ×3, construction ×2, equality/hash ×2), and composite-format `{n}` parsing exists twice in `QueryHelper` via a regex that mis-lexes alignment (`{0,5}` is not matched — `QueryHelper.cs:1413` pattern has no `,` branch) plus a third copy the old #6008 added. None of it is unit-testable without a database today.

## P2 Success criteria

- SC-1 An argument not referenced by `{n}` whose type cannot hold a `DataParameter` produces no command parameter (FromSql, FromSqlScalar nested, Sql.Expr) on every provider that is not `IsParameterOrderDependent` (D-3 carve-out: Access, SAP HANA, Informix IFX keep it), incl. Sybase. → TO-1, TO-2
- SC-2 A `DataParameter` argument not referenced by `{n}` is still sent and binds by name (`@p` / `:p`, PostgreSQL `@p`, MySQL `?p`) and by position (Access, SAP HANA `?`). → TO-3, TO-4, TO-5
- SC-3 All `FormattableString` expression/value handling and composite-format lexing lives in one public helper `LinqToDB.Internal.Common.FormattableStringHelper`; no other file pattern-matches `FormattableStringFactory.Create` or lexes `{n}`. → TO-6 (grep), TO-7..TO-10
- SC-4 The helper is covered by DB-free unit tests (lexer, index transform, concatenation split, shape split, equality/hash). → TO-7..TO-10
- SC-5 No existing baseline moves; existing FromSql / SqlExtensions / string.Format / StringJoin suites stay green. → TO-11

## P3 Constraints & anti-goals (M/L)

- No change to public API outside `LinqToDB.Internal.*`. `SqlQueryDependentAttribute.ObjectsEqual`/`ExpressionsEqual` keep signature and semantics (they only delegate).
- `BasicSqlBuilder` is **not** changed (old #6008's `IsParameterReferenced` / `ContainsParameterReference` / PostgreSQL override are not reintroduced) — no new PublicAPI entries on builders.
- Query-cache behaviour of #6003 unchanged: the filter runs at build time on argument expressions, never on the cached expression tree.
- `DependentArgumentValues` keeps its recursive element comparison and `ObjectsEqual` its non-recursive one (documented difference, `DependentArgumentValues.cs:7-14`) — the helper takes the element comparer as a delegate.
- `Sql.ExpressionAttribute.MatchParamRegex` (`{name}` / `{_}` / delimiter grammar) is a different grammar and stays.
- Anti-goal: no change to how `BuildFormatValues` renders (`BasicSqlBuilder.cs:4201`).

## P4 Unknowns (M/L)

- U-1 Does replacing a dropped argument by `Expression.Constant(null, typeof(object))` convert to SQL in both callers? — resolved-by code: `DataExtensions.GenerateArray` already emits `Expression.Constant(null, typeof(object))` for a null argument (`DataExtensions.cs:1451`), and those flow through `PrepareRawSqlArguments` → `TryConvertToSql` / `ConvertExpressionToSql` today. Reasoned, unprobed for `Sql.Expr`; TO-2 exercises it.
- U-2 Which static types can an argument expression have when it carries a `DataParameter`? — resolved-by code reading of the four shapes `PrepareRawSqlArguments` produces (`TableBuilder.RawSqlContext.cs:72-149`): (a) `NewArrayInit` element = `Convert(<expr of type DataParameter>, object)` → unwrap gives `DataParameter`; (b) evaluated `FormattableString` → `Constant(value, runtimeType)`; (c) evaluated `object[]` → `Convert(ArrayIndex, runtimeType)`; (d) a statically `object`-typed element (`new object[] { o }`) → stays `object`. Shapes (b)/(c) carry the **runtime** type, so a `DataParameter` subclass arrives typed as itself (critic, `DataExtensions.cs:1453`, `TableBuilder.RawSqlContext.cs:107`; `DataParameter` is unsealed, `DataParameter.cs:15`). Rule keeps an argument when its unwrapped type `t` satisfies `typeof(DataParameter).IsSameOrParentOf(t) || t.IsSameOrParentOf(typeof(DataParameter))` — subclasses, `DataParameter`, its bases incl. `object`; same direction as `ParametersContext.cs:239,346,358`. Reasoned, unprobed for (d); the subclass case is pinned by TO-10.
- U-3 Positional `?` with a **plain value** (not DataParameter) on an order-dependent provider (`FromSql("… = ?", 2)` on Access) — sent today. — resolved-by decision D-3: keep every argument on `SqlProviderFlags.IsParameterOrderDependent` providers.
- U-4 Does moving `QueryHelper.TransformExpressionIndexes` / `ConvertFormatToConcatenation` onto the lexer change output for formats in the test corpus? — resolved-by scout: `git grep "string.Format(\"{0,"` over `Tests/` → no hits; callers are `BasicSqlOptimizer.cs:793` (SqlExpression formats with parameters), `StringMemberTranslatorBase.cs:977`, `ExpressionBuildVisitor.cs:2695` (user `string.Format`). Behavioural deltas are enumerated in D-4 and pinned by TO-8/TO-9; SC-5 (baselines) is the corpus check.
- U-5 Can Tests reach an `internal` helper? — resolved-by scout: no `InternalsVisibleTo` in `Source/LinqToDB` (Grep `InternalsVisibleTo`, 0 hits); existing DB-free tests target **public** types in `LinqToDB.Internal.Common` (`Tests/Linq/Common/EnumerableHelperTest.cs`). → helper is `public static`, PublicAPI.Unshipped entries required.
- U-7 Do HANA / Informix IFX accept an extra bound parameter (the old TO-1 order-dependent leg)? — resolved-by scout (measured): the old design's CI baselines (`git diff --name-only origin/master...origin/baselines/pr_6008` in `linq2db.baselines`) contain `UnreferencedArgumentIsNotSent` for Informix.DB2 (not order-dependent) and no SapHana / Informix IFX file at all — no CI leg runs them, and Azure build 24000's failure list could not be fetched (transport error, twice). Unmeasurable here → TO-1 excludes order-dependent providers rather than asserting a predicted outcome; Access is measurable locally (TO-5).
- U-6 MySQL `?p` binds a command parameter named `@p`? — reasoned, unprobed (MySqlConnector / MySql.Data normalise a leading `@`/`?`). No local MySQL container; CI is the gate (TO-4). If CI refutes it, TO-4 drops the MySQL case — it is not a precondition of the design. — resolved-by decision: CI measures it (TO-4)

## P5 Decisions (M/L; rejected alternatives mandatory at L)

### D-1 — Where the unreferenced-argument decision is made

- **chosen:** in `PrepareRawSqlArguments` (moved into the helper), the single site both `TableBuilder.BuildRawSqlTable` and `Sql.ExprBuilder` call; it still has argument **expressions**, so intent (`DataParameter` or not) is visible.
- **rejected:** in `BasicSqlBuilder.BuildFormatValues` by searching SQL text for the parameter name (old #6008) — only knows the canonical prefix per provider (needed a PostgreSQL `@` override; misses MySQL `?p`), adds 3 public members to the builder, and applies to every `SqlExpression`/`SqlFragment`, not just raw SQL.
- **rejected:** a "user-supplied" flag on `SqlParameter` — reshapes a SQL AST node for a raw-SQL-local fix (cross-cutting-core rule).
- **why this:** smallest surface that sees intent; no provider knowledge needed except D-3.
- **failure mode of the choice:** an argument whose static type is `object` but holds a plain value is kept (conservative — today's behaviour, P10). A one-direction type test would drop a `DataParameter` subclass (critic round 1) — hence the two-direction rule in U-2. When the lexer rejects the format (`ParseFormatItems` → `null`), **every argument is kept** and `BuildFormatValues`' `AppendFormat` reports the bad format as today.

### D-2 — What a dropped argument becomes

- **chosen:** `Expression.Constant(null, typeof(object))` at the same index, so `{n}` indexes in the format stay valid and the format is not rewritten.
- **rejected:** remove the argument and renumber the format via `TransformExpressionIndexes` — rewrites user SQL text, more moving parts, same observable result.
- **failure mode of the choice:** a provider that parameterises NULL literals would re-introduce a parameter — none does (`SqlValue` null renders `NULL`).

### D-3 — Order-dependent providers keep every argument

- **chosen:** when `SqlProviderFlags.IsParameterOrderDependent` (Access, SAP HANA, Informix IFX), no argument is dropped; raw SQL there may bind any value with `?` (U-3).
- **rejected:** drop there too — regresses `FromSql("… = ?", 2)` on Access.
- **failure mode of the choice:** none for ASE (not order-dependent). Callers pass the flag in: `builder.DataContext.SqlProviderFlags` / the extension builder's data context.

### D-4 — Shared composite-format lexer, and QueryHelper migrated onto it

- **chosen:** `FormattableStringHelper.ParseFormatItems(string format)` returns the format items (`Start`, `Length`, `Index`, `IndexStart`, `IndexLength`) or `null` when the format is not a valid composite format. Grammar: `{{` / `}}` escapes; item = `{` digits [ws] [`,` alignment] [`:` format] `}`. Consumers:
  - `GetReferencedArguments(format, count)` (D-1);
  - `QueryHelper.TransformExpressionIndexes` — rewrites only the index digits, **keeping alignment/format specifier and adjacent escapes** (old regex rebuilt `{newIndex}`, dropping `:fmt`, and on `{{{0}}}` matched the odd 3-brace run and dropped the escaped literal braces; latent — critic found no `SqlExpression` format in `Source/` with an item adjacent to an escape);
  - `QueryHelper.ConvertFormatToConcatenation` — literal segments unescaped, items → `parameters[idx]`; alignment and format specifier ignored (old: `:fmt` already ignored; `{0,5}` was emitted as literal text `{0,5}` — a silent wrong result). A zero-item format is unescaped too (`"a{{b}}"` → `'a{b}'`, as `string.Format` gives; old returned the escapes verbatim, `QueryHelper.cs:1498`).
  - invalid format: `TransformExpressionIndexes` returns the input unchanged; `ConvertFormatToConcatenation` returns `SqlValue(format)` (old: regex partial matches).
- **rejected:** keep the regex in `QueryHelper` and add a third parser (old #6008) — three grammars for one syntax.
- **rejected:** `System.Text.CompositeFormat` — exposes only `MinimumArgumentCount`, not item positions; net8+ only.
- **failure mode of the choice:** the `QueryHelper` behaviour deltas above (`:fmt` kept, `{{{0}}}` escapes kept, `{0,5}` recognised, zero-item unescape); all are toward the .NET grammar `AppendFormat` uses (`BasicSqlBuilder.cs:4216`) and pinned by TO-8/TO-9.

### D-5 — Helper shape and visibility

- **chosen:** `public static class LinqToDB.Internal.Common.FormattableStringHelper` (public so DB-free tests can reach it, U-5), members:
  - lexer: `ParseFormatItems`, `GetReferencedArguments`, `Unescape` (literal segment);
  - expressions: `CreateExpression(string format, Expression arguments)`, `CreateExpression(FormattableString)`, `CreateArgumentsExpression(object?[])` (moved `GenerateArray`), `TrySplit(Expression, out Expression format, out NewArrayExpression arguments)`;
  - values: `Equals(FormattableString, FormattableString, Func<object?, object?, bool> argumentsEqual)`, `GetHashCode(FormattableString, Func<object?, int> argumentsHash)`;
  - raw SQL: `PrepareRawSqlArguments(Expression formatArg, Expression? parametersArg, bool keepUnreferenced, out string format, out IReadOnlyList<Expression> arguments)`.
- **rejected:** `internal` + `InternalsVisibleTo` — no precedent in the repo.
- **failure mode of the choice:** public surface in `Internal.*` (allowed; PublicAPI entries added).

## P6 Edit-points

- E-1 `Source/LinqToDB/Internal/Common/FormattableStringHelper.cs` — new helper (D-4, D-5), incl. the DataParameter filter (D-1..D-3); XML docs on every public member (`1591` is in `NoWarn`, `Directory.Build.props:43`, so no build catches a gap).
- E-2 `Source/LinqToDB/DataExtensions.cs:GenerateArray/GenerateFormattableString/FromSql` — remove the three helpers; `FromSql`/`FromSqlScalar`/`FromSql(RawSqlString)` call the helper.
- E-3 `Source/LinqToDB/Internal/Linq/Builder/Visitors/ExposeExpressionVisitor.cs:ConvertRawSqlString/PrepareFormattableString` — use `CreateExpression` / `TrySplit`.
- E-4 `Source/LinqToDB/Mapping/SqlQueryDependentAttribute.cs:ObjectsEqual/ExpressionsEqual/TrySplitFormattableString` — delegate to helper; remove the private splitter.
- E-5 `Source/LinqToDB/Internal/Linq/DependentArgumentValues.cs:ValuesEqual/ValueHashCode` — delegate the FormattableString branch to helper.
- E-6 `Source/LinqToDB/Internal/Linq/Builder/TableBuilder.RawSqlContext.cs:BuildRawSqlTable/PrepareRawSqlArguments` — remove `PrepareRawSqlArguments`; call helper with the order-dependent flag.
- E-7 `Source/LinqToDB/Sql/Sql.Expressions.cs:ExprBuilder.Build` — call helper with the order-dependent flag.
- E-8 `Source/LinqToDB/Internal/SqlQuery/QueryHelper.cs:TransformExpressionIndexes/ConvertFormatToConcatenation/ParamsRegex` — reimplement on the lexer; remove `ParamsRegex`.
- E-9 `Source/LinqToDB/PublicAPI/PublicAPI.Unshipped.txt` — helper's public members.
- E-10 `Tests/Linq/Linq/FromSqlTests.cs` — the four tests from `2bcb6bc29` (adjusted per P8) + Sql.Expr case.
- E-11 `Tests/Linq/Common/FormattableStringHelperTests.cs` — new DB-free unit tests.
- E-12 `Source/LinqToDB/Internal/Linq/Builder/ExpressionBuildVisitor.cs:HandleStringFormat` — decline `string.Format` translation when a format item has an alignment (A-2).
- E-13 `Tests/Linq/Linq/SelectScalarTests.cs` — `FunctionWithAlignment` (A-2).

## P7 Impact map (M/L)

- `DataExtensions.GenerateFormattableString` callers — searched `GenerateFormattableString|GenerateArray\(|FormattableStringFactory` over `Source/` in the worktree: `DataExtensions.cs:1466,1507,1549,1585`, `ExposeExpressionVisitor.cs:267,300` — covered by E-2, E-3.
- `FormattableStringFactory_Create` shape matches — same search: `SqlQueryDependentAttribute.cs:92`, `ExposeExpressionVisitor.cs:277`, plus the looser `NodeType == Call` branch at `TableBuilder.RawSqlContext.cs:75` — covered by E-4, E-3, E-6. `Methods.cs:43` (the MethodInfo itself) stays.
- `FormattableString` value equality/hash — searched `FormattableString` over `Source/LinqToDB/**/*.cs`: `SqlQueryDependentAttribute.cs:39`, `DependentArgumentValues.cs:58,82` — covered by E-4, E-5.
- `PrepareRawSqlArguments` callers — searched `PrepareRawSqlArguments` over `Source/`: `TableBuilder.RawSqlContext.cs:53`, `Sql.Expressions.cs:537` — covered by E-6, E-7.
- `TransformExpressionIndexes` / `ConvertFormatToConcatenation` callers — searched both names over the worktree `*.cs`: `BasicSqlOptimizer.cs:793`, `StringMemberTranslatorBase.cs:977`, `ExpressionBuildVisitor.cs:2695` — signatures unchanged, callers untouched; behaviour delta D-4 — covered by E-8.
- `FormattableString` type checks that are not handling code — `ExpressionCacheHelpers.cs:14`, `ExpressionBuilder.SqlBuilder.cs:1874` — out-of-scope (type guards, no shape/format logic).
- `RawSqlString` — `RawSqlString.cs`, `ExposeExpressionVisitor.cs:264` evaluates `.Format` — out-of-scope (not FormattableString code).
- Builder-side rendering — `BasicSqlBuilder.BuildFormatValues` (`:4201`) callers `:2064` raw table, `:3464` SqlExpression, `:3476` SqlFragment — untouched by design (P3); the filter is upstream — out-of-scope
- `Sql.ExpressionAttribute.MatchParamRegex` (`Sql.ExpressionAttribute.cs:177`) — out-of-scope, different grammar (P3).
- Remote (LinqService) — Localized - searched `PrepareRawSqlArguments` over `Source/`: 2 build-time callers, none in `Remote/`; the filter runs in expression building, no serialized shape touched.
- Tests referencing moved symbols — Localized - searched `TransformExpressionIndexes|ConvertFormatToConcatenation|FormattableStringHelper|PrepareRawSqlArguments` over `Tests/`: 0 hits.

## P8 Test obligations (M/L)

- TO-1 `UnreferencedArgumentIsNotSent` (all providers except order-dependent ones — Access, SAP HANA, Informix IFX excluded; the old test excluded only Access and asserted `ShouldContain(99)` on the others): nested `FromSqlScalar` with `Create("… {0}", 1, 99)` returns `[1]`; `ToSqlQuery().Parameters` does not contain 99. Discriminating input: the unreferenced `99`. The order-dependent leg is dropped from this test because no CI leg could measure it (U-7); D-3 is pinned by TO-5 and TO-10 instead. — proof: red→green (on the #6003 base 99 is a parameter; run before E-1 lands).
- TO-2 `Sql.Expr` variant: `Sql.Expr<int>($"{x} + 0", y)`-style via `FormattableStringFactory.Create("{0}", 1, 99)` in a projection; no parameter with value 99. — proof: red→green.
- TO-3 `ArgumentReferencedByNameIsSent` (SqlServer, SQLite, MySQL, PostgreSQL, Oracle; + remote): `FromSql("… = @p|:p", new DataParameter("p", 2))` returns `[2]`. — proof: control (red under a mutation that drops DataParameter too — record the mutation when run).
- TO-4 `ArgumentReferencedByAlternateNameIsSent`: PostgreSQL `@p`, MySQL `?p` (U-6, CI-gated). — proof: control (same mutation as TO-3).
- TO-5 `ArgumentReferencedByPositionIsSent` (Access, SAP HANA): `?` + DataParameter returns `[2]`; plus plain-value case `FromSql("… = ?", 2)` on Access (D-3). — proof: control (mutation: ignore the order-dependent flag → plain-value case red).
- TO-6 grep gate: `FormattableStringFactory_Create` referenced only in `Methods.cs` and `FormattableStringHelper.cs`; `ParamsRegex` gone. — proof: characterization (structural).
- TO-7 lexer unit tests (DB-free): `ParseFormatItems` on `"a {0} b"`, `"{{0}}"` (no items), `"{{{0}}}"` (one item, literal braces both sides), `"{0,5}"`, `"{0:N2}"`, `"{0 ,-3:x}"`, `"{1}{0}"`, invalid `"{a}"`, `"{0"`, `"{"` → null; `GetReferencedArguments("{1}", 3)` → `[false,true,false]`, out-of-range index ignored. — proof: characterization (new code).
- TO-8 `TransformExpressionIndexes`: `"{0} x {1:N2} {{2}}"` with `i → i+10` → `"{10} x {11:N2} {{2}}"`; `"{0,5}"` → `"{10,5}"`; `"{{{0}}}"` → `"{{{10}}}"`. Discriminating inputs: `:N2` (old dropped it), `{0,5}` (old did not match), `{{{0}}}` (old dropped the escapes). — proof: red→green against the regex implementation (run the test before E-8).
- TO-9 `ConvertFormatToConcatenation`: `"a{0}b{{c}}"` → concat(`'a'`, p0, `'b{c}'`); `"{0,5}"` → p0 (old: literal `'{0,5}'`); `"a{{b}}"` (no items) → `SqlValue('a{b}')` (old: `'a{{b}}'`). — proof: red→green for `{0,5}` and the zero-item case, characterization for the rest.
- TO-10 helper expression/value unit tests: `TrySplit` accepts `CreateExpression("x", NewArrayInit)` and rejects a non-NewArrayInit second arg / other method; `Equals`/`GetHashCode` equal for same format+args, differ on format or args; `CreateExpression(FormattableString)` round-trips through `Expression.Lambda(...).Compile()` to an equal FormattableString. `PrepareRawSqlArguments` DB-free: `Create("{0}", 1, 99)` → argument 1 is `Constant(null, object)`; same with `99` replaced by a `DataParameter`, a `DataParameter` **subclass** typed as itself, and an `object`-typed element → kept; `keepUnreferenced: true` → kept; invalid format `"{a}"` → all kept. — proof: characterization (new code); the subclass case is red under a one-direction type test (critic round 1 mutation).
- TO-11 regression: existing `FromSqlTests`, `SqlExtensionsTests`, string.Format / `StringConcatTests` on SQLite + SqlServer locally; full matrix + baselines on CI (zero modified baselines). — proof: characterization.
- TO-12 (A-2) `SelectScalarTests.FunctionWithAlignment`: `string.Format("{0,5}|{1}", …)` in a projection returns `"    1|John"` (client-side); in a predicate throws `LinqToDBException`. Discriminating input: the alignment. — proof: red→green.

## P9 Verification gates

- G-01: pass (local; full matrix on CI) — worktree `linq2db.Tests.exe` net10.0 Debug, final run after rebase onto #6003 `44bd08896` and A-2/A-3: SQLite.MS + SQLite.Classic + PostgreSQL.18 + MySql.8.0 + MySqlConnector.8.0 + Access.Ace.OleDb, `FormattableStringHelperTests|FromSqlTests|SqlExtensionsTests|SelectScalarTests`: 800 total, 792 passed, 8 failed — all 8 are #6003's own committed-red tests (`*_Compiled_*_BuildsOnce` ×3 from `c0c3fd295`, `Expr_Captured_AfterRowReference` from `add7163fb`, "Red on this branch") on the two SQLite providers. Sybase, Oracle, DB2, Firebird, ClickHouse, YDB, SQL Server, Informix, SAP HANA unverified locally.
  - TO-1 `UnreferencedArgumentIsNotSent` — red on #6003 base (SQLite.MS direct + remote), green on all 6.
  - TO-2 `UnreferencedExprArgumentIsNotSent` — red under mutation (`Sql.ExprBuilder` forced `keepUnreferenced: true`: 2 failed / 13 passed), green on all 6.
  - TO-3 `ArgumentReferencedByNameIsSent` — red under mutation (filter's DataParameter clauses removed), green on SQLite ×2, PostgreSQL.18, MySQL ×2.
  - TO-4 `ArgumentReferencedByAlternateNameIsSent` — green on PostgreSQL.18 (`@p`), MySql.8.0 / MySqlConnector.8.0 (`?p`); U-6 settled.
  - TO-5 `ArgumentReferencedByPositionIsSent` — red under mutation (order-dependent flag ignored: Access ×4) and with A-3's rule disabled (plain `?` on SQLite.Classic / MySQL ×2, direct + remote); green on Access.Ace.OleDb / Odbc, SQLite.Classic, MySQL ×2.
  - TO-6 grep gate — `FormattableStringFactory_Create` only in `Methods.cs` and `FormattableStringHelper.cs`; `ParamsRegex` gone (code-reviewer pass).
  - TO-7 `FormattableStringHelperTests.ParseFormatItems*`, `GetReferencedArguments` — green.
  - TO-8 `FormattableStringHelperTests.TransformExpressionIndexes` — red ×3 against the regex implementation, green.
  - TO-9 `FormattableStringHelperTests.ConvertFormatToConcatenation_*` — red ×2 (`_Alignment`, `_NoItems`) against the regex implementation, green.
  - TO-10 `FormattableStringHelperTests.TrySplit|CreateExpression_RoundTrip|AreEqual_ComputeHashCode|PrepareRawSqlArguments_*` — green; `_UnreferencedIsKept` red under the DataParameter mutation, `_NoFormatItems` red with A-3's rule disabled.
  - TO-11 regression — SQLite.MS `StringFunctionTests|SelectScalarTests|StringConcatTests|ExpressionTests` 616 passed / 2 skipped (`IndexOf3`, pre-existing) before A-2/A-3; final 6-provider run above.
  - TO-12 `SelectScalarTests.FunctionWithAlignment` — red without the refusal (`"1|John"`), green on SQLite ×2.
- G-02: blocked — baselines come from CI's test-all on the pushed branch; expected delta = new tests only.
- G-03: pass — `PublicAPI.Unshipped.txt` lists the helper's 20 public members; XML docs on all.
- G-04: n/a — no shipped member changed (`TableBuilder` is internal; `DataExtensions` helpers were internal).
- G-05: pass — after A-2/A-3: `dotnet build Source/LinqToDB/LinqToDB.csproj -c Release -f netstandard2.0|net462|net10.0` exit 0 (MA0008 fixed with `[StructLayout(LayoutKind.Auto)]`); `dotnet build Tests/Linq/Tests.csproj -c Release -f net10.0` exit 0.
- G-06: pass — `work-plan.ps1 -Action reconcile -Base origin/issue/6000-fix-nested-fromsql-cache`: no unplanned files.
- G-07: pass — `Tests/Tests.Playground/TestTemplate.cs` probe restored (`git restore`); no Playground changes.
- G-08: pass — cross-cutting `QueryHelper` change surfaced in D-4 and pinned by DB-free TO-8/TO-9.
- G-09: pass — `code-reviewer` single pass over the uncommitted diff: MIN001 (TO-2 `{0}` shortcut) fixed + A-1 corrected; MIN002 (alignment) fixed as A-2; OOS base-moved → rebased; OOS release note → probed, A-3.

## P10 Adjudicated (M/L)

- A plain value referenced only by a provider's positional marker on a **non**-order-dependent provider is dropped **when the format also has `{n}` items** (e.g. `"… {0} … ?"` on MySQL). Reason: indistinguishable from an unreferenced value without parsing provider SQL; a format with no items keeps all arguments (A-3). Workaround `{n}` or `DataParameter`; noted as a behaviour change in the PR body.
- An `object`-typed argument expression is kept even when it holds a plain value (D-1). Reason: it may hold a `DataParameter`; keeping is today's behaviour.
- Order-dependent providers (Access, SAP HANA, Informix IFX) keep unreferenced arguments (D-3, SC-1 carve-out). Reason: raw SQL there may bind any value with `?`; ASE, the provider that rejects extra parameters, is not order-dependent. Same as the old #6008 design.

## P11 Amendments (M/L)

- A-1 (2026-10-10, measured; **corrected** after the G-09 read): TO-2 (`UnreferencedExprArgumentIsNotSent`) passed on the #6003 base because its format was exactly `"{0}"`, which `BasicSqlBuilder.cs:3461` renders as `Parameters[0]` without `BuildFormatValues` — the unreferenced argument is never built. (The first version of this entry blamed `BasicSqlOptimizer.NormalizeExpressions`; wrong — `BasicSqlOptimizer.cs:815-818` keeps the original expression, all parameters included, when indexes do not move.) TO-2's format changed to `"({0})"`; proof stays **red→green**, shown by mutation (`Sql.ExprBuilder` forced `keepUnreferenced: true`): SQLite.MS 2 failed (TO-2 direct + remote) / 13 passed. No `E-n` change. Red run on SQLite.MS: 7 failed / 8 passed, exactly TO-1 (direct + remote), TO-8 ×3, TO-9 ×2.
- A-2 (2026-10-10, G-09 read MIN002, user chose "decline on alignment"): with the lexer, `ConvertFormatToConcatenation` recognises `{0,5}` and would silently drop the padding (old regex emitted literal `{0,5}` text). `FormatItem` gains `HasAlignment`; `ExpressionBuildVisitor.HandleStringFormat` — the only live caller (`StringMemberTranslatorBase.TranslateStringFormat` has no caller: Grep `TranslateStringFormat` over `Source/LinqToDB`) — declines translation when any item has an alignment: a projection evaluates client-side (correct padding), a predicate fails to translate. Format specifiers (`{0:D2}`) stay ignored as before this branch — pre-existing, not widened here. New E-12, E-13; TO-12 `FunctionWithAlignment` (SQLite + remote: projection `"    1|John"`, predicate throws `LinqToDBException`), proof red→green; plus `ParseFormatItems_HasAlignment` unit cases. Voids approval of E-12/E-13 only — approved by the user's "A" on MIN002.
- A-3 (2026-10-10, measured; user chose "keep all when the format has no items"): the first P10 entry's premise ("indistinguishable from an unreferenced value") was probed instead of accepted. Playground probe, `FromSql("… = <marker>", new DataParameter("p", 2))` — the named command parameter a 6.5 plain value became: `?` **binds** on SQLite.Classic (also `?1`), MySql.8.0 and MySqlConnector.8.0; fails on SQLite.MS and PostgreSQL.18 (`$1` fails on all). So `FromSql("… = ?", 2)` worked on 6.5 on MySQL / System.Data.SQLite and the filter as approved broke it. Rule narrowed: `ReplaceUnreferencedArguments` keeps every argument when the format has **no** format items (it binds by name or position); the ASE case (`{0}` plus an extra argument) is still filtered. P10 entry 1 now covers only a format mixing `{n}` with a positional marker for a plain value. TO-5 widened to SQLite.Classic + MySQL (plain value and DataParameter); unit `PrepareRawSqlArguments_NoFormatItems`. Edits stay inside E-1 / E-10 / E-11.

## P12 Critic verdict (M/L)

Round 1 (`plan-critic`, model `fable`): **weak**. Searched: `FormattableString` over `Source/**/*.cs` (incl. EF Core `TransformExpressionVisitor.cs:359-363` → flows into `ConvertRawSqlString`, no new shape), `ParamsRegex|TransformExpressionIndexes|ConvertFormatToConcatenation`, `BuildFormatValues` / `OptimizationContext.AddParameter` (every parameter pre-rendered before `AppendFormat` picks items — the P1 mechanism), null-`SqlValue` handling (`ValueToSqlConverter.cs:174-178` short-circuits null → D-2 holds), `IsParameterOrderDependent` (Access, HANA, Informix IFX only; D-3 plumbing available via `ISqlExtensionBuilder.DataContext` / `ExpressionBuilder.DataContext`), `IsConstant` / `CalcCanBeNull` (no delta from D-2), `InternalsVisibleTo`, alignment in `Tests/Linq` interpolations, positional/named-only raw SQL tests (none rely on the P10 dropped case). Strongest point named: D-1's altitude.

Objections and responses:
1. One-direction `DataParameter` type test drops a subclass; D-1 failure-mode line false → **fixed**: two-direction rule (U-2), D-1 line rewritten, subclass case in TO-10.
2. SC-1 contradicts D-3 → **fixed**: SC-1 carve-out + P10 entry.
3. TO-1 order-dependent leg is an unmeasured prediction → **fixed**: measured that no CI leg runs HANA/IFX (U-7); TO-1 excludes order-dependent providers; D-3 pinned by TO-5/TO-10.
4. `{{{0}}}` delta missing from D-4/TO-8 → **fixed**.
5. Filter behaviour on lexer rejection unspecified → **fixed**: keep all (D-1), TO-10 case.
6. TO-9 pinned a wrong zero-item result → **fixed**: zero-item format is unescaped (D-4, TO-9).
7. XML docs on new public members → **fixed**: noted on E-1.
