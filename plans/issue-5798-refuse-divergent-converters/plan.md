# Refuse combining two columns whose value converters disagree (#5798)

- **Branch:** `issue/5798-refuse-divergent-converters` (authored on the harness's auto-named
  `claude/issue-5798-870e6a`, renamed before the first push; this plan moved with it)
- **Issue:** [#5798](https://github.com/linq2db/linq2db/issues/5798) — milestone 6.6.0
- **PR:** [#5902](https://github.com/linq2db/linq2db/pull/5902)
- **Tier:** M

## P1 Problem

Arithmetic and comparison between two columns that carry hand-written value converters operate on the
stored numbers without asking whether the two converters agree on what those numbers count. Measured on
this branch's base (`cf9fa573c6`), SQLite, with the `DurationRow` model already in
`Tests/Linq/Linq/IntervalTranslationTests.cs` — `Undeclared` stores ticks, `UndeclaredSeconds` stores
seconds, one row holding 90 minutes in both:

```
PROBE5798 mixed=01:30:00.0005400 same=03:00:00 matched=0
```

- `Sql.AsSql(r.Undeclared + r.UndeclaredSeconds)` → `01:30:00.0005400`, where the CLR answers `03:00:00`.
  The SQL is `col_ticks + col_seconds`, and the result is read through whichever descriptor
  `QueryHelper.GetColumnDescriptor` reaches first (`SqlBinaryExpression` → `Expr1` then `Expr2`), so
  `5400` seconds is added as `5400` ticks. Wrong by a factor of ten million, and silent.
- `r.Undeclared + r.Undeclared` → `03:00:00`. Correct, and must stay correct.
- `t.Count(r => r.Undeclared == r.UndeclaredSeconds)` → `0`, where the CLR answers `1`. The same defect,
  and the quieter half: nothing about a comparison reads as arithmetic.

[#5750](https://github.com/linq2db/linq2db/pull/5750) refused the *mixed* pairing — one side declaring
`[Duration(DurationUnit)]`, the other only converted — in both `TranslateIntervalArithmetic` and
`TranslateIntervalComparison` (`Error_Interval_UndeclaredOperand`, commit `bed2222fe0`). It deliberately
left the both-converted pairing alone and named this issue in
`IntervalTranslationTests.Arithmetic.cs:33-37`. This branch is that remaining half, and it is not
TimeSpan-specific: the defect is in the generic binary handling and applies to any two columns of one CLR
type whose converters disagree.

## P2 Success criteria

- **SC-1** Two columns whose converters do not agree are refused, by a message naming both columns, wherever
  the combination must be expressed in SQL — `Sql.AsSql`, `Where`. Applies to every operator
  `HandleBinaryMath` handles and to the six comparison operators. (A set-operation branch was in this list
  and is not — see A-1.) → TO-1, TO-2, TO-6
- **SC-2** The same expression in a plain projection, where SQL is not required, answers what the CLR answers
  (`03:00:00`) instead of the wrong duration, by falling back to .NET. → TO-4
- **SC-3** Two columns that agree — the same converter object, an equivalent converter declared twice, no
  converter at all, the same declared `DurationUnit` — are unaffected: same SQL, same values.
  → TO-5, G-02
- **SC-4** Nothing outside the disagreeing pairing changes: the existing suites stay green on the providers
  run locally. → G-01

## P3 Constraints & anti-goals

- Public API outside `LinqToDB.Internal.*` must not change. The one added member is a `const string` on
  `LinqToDB.Internal.Common.ErrorHelper`, which is `Internal` and takes a `PublicAPI.Unshipped.txt` row.
- No SQL change for any query whose two operands agree — this must not move baselines for ordinary columns.
  A converter-free column pair has to reach `ConvertTheSameWay(null, null)` and be waved through.
- **Anti-goal: reconciling the operands.** The issue offers refusal *or* reconciliation and calls refusal the
  safer; only the converters know what their numbers mean, and nothing in the model states it. No attempt is
  made to bring two hand-written conversions onto common terms.
- **Anti-goal: `Contains` / membership.** `Contains` builds its predicate from two SQL expressions rather
  than through this path; the declared-duration half of that is already tracked as
  [#5776](https://github.com/linq2db/linq2db/issues/5776). Recorded as a narrowing of the issue's
  "any two columns … whose converters disagree" wording — see P10.
- **Anti-goal: `[Duration]`-declared pairs.** Already reconciled or refused by `DateFunctionsTranslatorBase`
  with a better message; this check must sit downstream of it, not in front of it.

## P4 Unknowns

| # | Assumption / unknown | Resolution |
|---|---|---|
| U-1 | The wrong value comes from `GetColumnDescriptor`'s `SqlBinaryExpression` arm picking `Expr1`'s descriptor. | resolved-by probe — `01:30:00.0005400` is exactly `54000000000 + 5400` ticks, which is `Undeclared`'s (Expr1's) conversion applied to the sum. `QueryHelper.cs:345-351`. |
| U-2 | The comparison is broken the same way, not only the arithmetic. | resolved-by probe — `matched=0` above. |
| U-3 | A refusal raised in `HandleBinaryMath` still lets a *plain* projection answer in .NET. | resolved-by probe — measured after implementation, TO-4. `TryConvertToSql` (`ExpressionBuildVisitor.cs:2277-2285`) calls `BuildSqlExpression`, gets a non-placeholder back for an error, returns false, and `VisitBinary` falls to `base.VisitBinary` at `:3054`. |
| U-4 | A set-operation branch projection must **not** get that fallback, or the wrong value returns through a query shape that looks ordinary. | resolved-by probe — measured, and the premise was wrong: `Concat` and `Union` over the divergent sum both answer `03:00:00`, the CLR value. The branch falls back to .NET the way any untranslatable set projection does (`DeclinedForSetProjection`'s own doc describes the pattern), so nothing wrong is returned and there is no refusal to assert. See A-1. |
| U-5 | `ConvertTheSameWay` cannot see through `ValueConverterFunc` (delegate-built), so two behaviourally-identical delegate converters compare unequal and are refused. | resolved-by reading `SequenceHelper.cs:53-58`, which states it; reachable from `PropertyMappingBuilder.HasConversion(Func<>, Func<>)` (`PropertyMappingBuilder.cs:519`). Accepted — see D-3 and P10. |
| U-6 | How many existing tests combine two *differently*-converted columns and would newly refuse. | resolved-by probe — G-01 runs the SQLite suite before/after. |

## P5 Decisions

**D-1 — Refuse rather than reconcile.**
- chosen: raise a named error when the two operands' column descriptors do not read the same way.
- rejected: scale one operand onto the other's terms. The conversions are arbitrary lambdas, not linear
  factors; nothing can invert `ts => ts.Ticks / TimeSpan.TicksPerSecond` on the SQL side in general.
- why this: the issue asks for it by name and calls it the safer of the two options; it also matches what
  #5750 already does for the mixed pairing, so the two halves of the defect answer alike.
- failure mode of the choice: a query that is wrong today starts throwing. That is the intent, but it lands
  on release upgrade rather than on a code change, so it needs a release-notes line.

**D-2 — The check keys on `SequenceHelper.ReadTheSameWay`, the predicate that already answers this
question for set operations and conditionals.**
- chosen: reuse it, unchanged, over two `ColumnDescriptor`s obtained by `QueryHelper.GetColumnDescriptor`.
- rejected: a new comparison written for this site — it would drift from the other two and re-derive the
  duration-unit substitution and the nullable-lambda unwrapping that `ConversionsMatch` already does.
- why this: three call sites now share one definition of "stored on the same terms", so a fix to any of the
  comparison's own blind spots reaches all three.
- failure mode of the choice: `ReadTheSameWay` is deliberately biased to answer *no* when it cannot tell
  (D-3), and this is the first site where "no" costs a refusal rather than an extra column.
- separating input: two columns whose converters are *equivalent but not the same object* — the schema
  declares `Undeclared` once, so TO-5 must build a second entity with a textually identical `HasConversion`
  to exercise `ConversionsMatch` rather than the `ReferenceEquals` fast path.

**D-3 — Only two operands that both resolve to a column descriptor are refused.**
- chosen: `descriptor1 == null || descriptor2 == null` → allow.
- rejected: mirroring `CanShareOneReading`'s third arm, which also refuses a *computed* value beside a
  converted column. That would newly refuse `convertedColumn + <any SQL-computed value>`, which is far wider
  than the issue and has no measured defect behind it.
- why this: a literal or a parameter is written through the descriptor in scope, so it arrives on the
  column's terms by construction — this is why `UndeclaredSeconds + TimeSpan.FromMinutes(5)` is right today
  and must stay so.
- failure mode of the choice: a converted column combined with a genuinely unit-less computed value stays
  silently wrong. Not measured, not reported, and one of the two shapes #5776 already covers.

**D-4 — Two placement sites, both downstream of the member translators.**
- chosen: `HandleBinaryMath`, after both operands resolve to placeholders and before the
  `SqlBinaryExpression` / `SqlCoalesceExpression` is built; and `ConvertCompareExpression`, immediately
  after `leftPlaceholder` / `rightPlaceholder` are read and before the `nodeType` switch — which is *before*
  `ConvertEnumConversion`, so the `(Enum)a == (Enum)b` shape is covered too.
- rejected: `VisitBinary` ahead of the dispatch. The operands are unvisited there, so every binary node in
  every query would pay a speculative visit.
- rejected: `QueryHelper.GetColumnDescriptor`'s `SqlBinaryExpression` arm returning null on disagreement.
  That silently reads the sum raw instead of refusing — a different wrong answer.
- why this: both sites already hold the two resolved `ISqlExpression`s, and both are reached only after
  `TranslateMember` has had its say, so a `[Duration]`-declared pairing keeps `Error_Interval_UndeclaredOperand`.
- failure mode of the choice: any *third* path that combines two placeholders without going through these
  two stays wrong — `Contains` is the known one (P3, #5776).

## P6 Edit-points

| # | Edit | Obligations |
|---|---|---|
| E-1 | `Source/LinqToDB/Internal/Common/ErrorHelper.cs` — add `Error_ValueConverter_DivergentOperands`, a `{0}`/`{1}` message naming both columns and both ways out. | TO-1, TO-2, TO-3, TO-6 |
| E-2 | `Source/LinqToDB/PublicAPI/PublicAPI.Unshipped.txt` — row for E-1. | G-03 |
| E-3 | `Source/LinqToDB/Internal/Linq/Builder/ExpressionBuildVisitor.cs`:`DivergentStorage` — new private static: two descriptors, `SequenceHelper.ReadTheSameWay`, formatted message out. | TO-1, TO-5 |
| E-4 | `…ExpressionBuildVisitor.cs`:`HandleBinaryMath` — call E-3 on the two placeholders, return a `SqlErrorExpression` typed as the node. | TO-1, TO-3, TO-4, TO-5 |
| E-5 | `…ExpressionBuildVisitor.cs`:`ConvertCompareExpression` — call E-3 on the two placeholders, return a `SqlErrorExpression` typed `bool`. | TO-2, TO-3, TO-5, TO-6 |
| E-6 | `Tests/Linq/Linq/IntervalTranslationTests.cs` — a second entity carrying a converter equivalent to `Undeclared`'s but declared separately, for D-2's separating input. | TO-5 |
| E-7 | `Tests/Linq/Linq/IntervalTranslationTests.Arithmetic.cs` — the fixtures for TO-1..TO-6; and the doc comment at `:33-37` which currently states this issue is *not* addressed. | TO-1..TO-6 |

## P7 Impact map

| Site | Verdict |
|---|---|
| `SequenceHelper.ReadTheSameWay` callers — searched `ReadTheSameWay\|ConvertTheSameWay` across `Source/`: `SetOperationBuilder.cs:392-411`, `ExpressionBuildVisitor.cs:2096-2117` (`CanShareOneReading`). Both read-only consumers; the helper is not modified. | covered by E-3 (adds a third caller, changes neither) |
| Other `new SqlBinaryExpression(` sites in `Source/LinqToDB/Internal/Linq/` — searched: `ExpressionBuilder.SqlBuilder.cs:134,141` (Skip/Take arithmetic on `int`), `SelectBuilder.cs:104` (row number − 1), `QueryRunner.cs:447` (Take + Take). None combines two user columns. | out-of-scope |
| Other `new SqlPredicate.ExprExpr(` sites — searched: `ExpressionBuilder.SqlBuilder.cs:118,718`, `ExpressionBuildVisitor.cs:1081`, `:4427` (the site E-5 guards), `:4871`/`:4891` (`ConvertEnumConversion`, reached from `:4293` — E-5 sits ahead of it). | covered by E-5 |
| `Contains` / `IN` membership between two converted columns — builds its predicate from SQL expressions, not through `ConvertCompareExpression`. | deferred: #5776 (P3 anti-goal, P10) |
| Providers where `CanLowerIntervalPart` is false (`SqlExpressionConvertVisitor.cs:1359` → `CanLowerIntervalDifference`; Informix and SQL Server ≤2014 per `UnsupportedDifferenceProviders`): two **declared** duration columns in different units fall through `TranslateIntervalArithmetic` and now meet E-4 instead of adding raw. | covered by E-4 — behaviour improves from a wrong value to a refusal; G-01 confirms no fixture asserted the wrong value |
| Mirrored write path — value converters are also applied on insert/update; nothing there combines two columns with one operator. Searched `Source/LinqToDB/Internal/Linq/Builder/` for binary construction (rows above). | out-of-scope |
| Baselines — E-4/E-5 emit SQL only where they do *not* fire, so no query that keeps working changes shape. | covered by G-02 |
| Surfaces a repo grep cannot reach: the release notes for 6.6.0 (D-1's failure mode) are authored outside this repo's tree. | deferred: release-notes line proposed in the PR body |

## P8 Test obligations

| # | Asserts | Mode |
|---|---|---|
| TO-1 | `Sql.AsSql(r.Undeclared + r.UndeclaredSeconds)` throws `LinqToDBException` naming both columns. | red→green — pre-fix it returns `01:30:00.0005400`; the fixture must assert the *throw*, so its red state is "did not throw", confirmed by the probe value above. |
| TO-2 | `Where(r => r.Undeclared == r.UndeclaredSeconds)` throws the same. Pre-fix it returns zero rows for a row the CLR matches. | red→green |
| TO-3 | ~~Both shapes inside a `Concat` branch projection stay refused.~~ Withdrawn — see A-1: measured, the branch answers the CLR value rather than refusing, so there is nothing to pin. | withdrawn |
| TO-4 | A plain projection `Select(r => r.Undeclared + r.UndeclaredSeconds)` answers `03:00:00`. Distinguishes the .NET fallback from a refusal: the observation is the *value*, which only the client path can produce. | red→green (pre-fix `01:30:00.0005400`) |
| TO-5 | Control, one fixture per agreeing pairing, each asserting the value **and** that nothing throws: (a) same descriptor twice (`Undeclared + Undeclared`); (b) two entities carrying equivalent-but-separately-declared converters, which is D-2's separating input and the only case exercising `ConversionsMatch` rather than `ReferenceEquals`; (c) two converter-free columns; (d) two columns declaring the same `DurationUnit` (`InSeconds + InSeconds`). Mutation to prove the control can go red: drop the `ReadTheSameWay` call from E-3 so every descriptor pair refuses, and confirm (a)–(d) redden. | control |
| TO-6 | The `[Duration]`-declared mixed pairing still reports `Error_Interval_UndeclaredOperand`, not the new message — i.e. E-5 did not get in front of the translator. The existing `ADeclaredDurationRefusesAnUndeclaredOne` / `…RefusesComparisonWithAnUndeclaredOne` fixtures are the assertion; they must stay green unmodified. | characterization |

## P9 Verification gates

Measured 2026-09-09 against `0c0581a13c`, the branch's only commit and the tree these rows describe (base
`cf9fa573c6`). Re-derive after any later commit touching an `E-n`.

| Gate | Result |
|---|---|
| G-01 | `pass` — see the per-`TO-n` table below. Suite runs, all on the reworked tree: full SQLite.MS (direct + LinqService) **11278 total, 0 failed, 289 skipped**, and none of the new tests is in that skip list; `SqlRowTests` + `ValueConversionTests` + `IntervalTranslationTests` on SQLite.MS **256/256**; the new fixtures on `Access.Ace.Odbc`, `Oracle.23.Managed`, `ClickHouse.Octonica`, `DuckDB` (+ LinqService) **47/47**, roster confirmed with `--list-tests` first; EF Core 10 on SQLite.MS **186 total, 0 failed** (17 skipped, all pre-existing gates), run because the EF bridge mints one linq2db converter per property and so is the densest consumer of this comparison. |
| G-02 | `skipped` — `BaselinesPath` in the primary clone's `UserDataProviders.json` points at `c:\GitHub\linq2db.bls`, which is not a git clone, so no local diff is possible. What is therefore unverified: whether any *existing* baselined query changed shape. Indirect evidence only — the check emits no SQL where it does not fire, and where it does fire the test throws rather than re-baselining, so G-01's green sweep bounds it for the providers actually run. The branch's baselines PR is the first real measurement. |
| G-03 | `pass` — `Error_ValueConverter_DivergentOperands` is the only added surface (`LinqToDB.Internal.Common`); row added to `Source/LinqToDB/PublicAPI/PublicAPI.Unshipped.txt`, XML `<summary>` documents the `{0}`/`{1}` arguments, and both fixtures assert the formatted message. |
| G-04 | `n/a` — purely additive `const` on an existing public type; no `CompatibilitySuppressions.xml` movement. |
| G-05 | `pass` — `dotnet build Source/LinqToDB/LinqToDB.csproj -c Release` green on `netstandard2.0`, `net462` and `net10.0` (analyzers on): 0 warnings, 0 errors. `dotnet build Tests/Linq/Tests.csproj -c Debug` (no `-f`, so all four TFMs incl. `net462`) green. XML-doc validation of the edited **test** files needs Release, which master blocks on `Tests/Base` MA0206, so the documented probe was applied and reverted: with it, `Tests/Linq` compiled and emitted per-file diagnostics — no `CS1574` (the new `<see cref="TwoDisagreeingConvertersRefuseToCombine"/>` resolves) and every diagnostic reported sits on a line this branch did not touch (`ValueConversionTests.cs:1670`, `IntervalTranslationTests.Arithmetic.cs:501`/`:515`, plus the `Issue5683` / `Issue5719` / `DataOptionsTests` / `OrmBattleTests` / `ConcurrencyRefreshTests` set auto-memory already records as master-side). |
| G-06 | `pass` — `git diff` touches 5 files; the only lines changed that the task did not add are the doc paragraph in `IntervalTranslationTests.Arithmetic.cs` that named this issue as unaddressed, and the `ErrorHelper` blank line separating the new group. |
| G-07 | `pass` — nothing under `Tests/Tests.Playground/`; `git status --porcelain` lists only the five files. |
| G-08 | `pass` — the change is in shared builder code (`ExpressionBuildVisitor`), and it rests on measurement rather than reasoning: the defect was reproduced first (P1), and both directions were mutation-tested (P8 `TO-5`, results under G-01). |
| G-09 | `skipped` — this session's operating instructions forbid dispatching a reviewer subagent, so the diff got a self-review rather than an independent one. It was not empty: two defects were found and fixed — `CombinesDivergentStorage` had been inserted between `CanShareOneReading`'s doc comment and its declaration, silently reassigning that comment; and the new `const` had landed inside the `Error_Interval_*` group. What is therefore unverified is anything a reader with different priors would have caught, and the branch has had no cross-model read at any point (see P12). |

Per-`TO-n`, with the observation proving each proof mode ran:

| # | Test | Result |
|---|---|---|
| TO-1 | `IntervalTranslationTests.TwoDisagreeingConvertersRefuseToCombine` (`combined` arm), `ValueConversionTests.DivergentConversionsRefuseToCombine` (`combined` + `unconverted` arms) | `pass`. red→green observed by mutation: with `CombinesDivergentStorage` forced to `return false`, both report **should throw**. The message is asserted as the *formatted* string with both member names, so a refusal raised for another reason would not satisfy it. |
| TO-2 | the `compared` arm of both tests above | `pass`. Same mutation, same red. `Where` rather than `Count` deliberately — see A-3. |
| TO-4 | `TwoDisagreeingConvertersStillCombineInDotNet`, and `DivergentConversionsRefuseToCombine`'s `row.Divergent` / `row.Unmapped` | `pass`. red→green: under the same mutation the value arm fails **should be / but was**, i.e. the pre-fix `01:30:00.0005400` and `25`. The observation is the value, which only the client-side path can produce. |
| TO-5 | controls: `row.SameColumn`, `row.SameUnit`, `row.NoConverter`, `row.PlainValue`, `t.Count(r => r.Doubled == 10)`, and `ValueConversionTests.SeparatelyDeclaredConversionsStillCompare` | `pass`. Mutation recorded: dropping the `SequenceHelper.ReadTheSameWay` term so every descriptor pair refuses turns `SeparatelyDeclaredConversionsStillCompare`, `TwoDisagreeingConvertersStillCombineInDotNet` and `DivergentConversionsRefuseToCombine` red, while `TwoDisagreeingConvertersRefuseToCombine` — which asserts only throws — stays green, exactly as it should. `SeparatelyDeclaredConversionsStillCompare` is the arm that reddens for D-2's separating input: two objects, one conversion, so `ConversionsMatch` decides it rather than `ReferenceEquals`. |
| TO-6 | `ADeclaredDurationRefusesAnUndeclaredOne`, `ADeclaredDurationRefusesComparisonWithAnUndeclaredOne`, `ARefusedPairingStaysRefusedInsideASetOperation` — unmodified | `pass`. Characterization: all three still report `Error_Interval_UndeclaredOperand`, so the new check did not get in front of the translator. Probed directly too — `Where(r => r.InSeconds == r.Undeclared)` and `Where(r => r.InTicks + r.UndeclaredSeconds > TimeSpan.Zero)` both carry #5750's message, not this branch's. |
| TO-7 | `SqlRowTests.UpdateRowWithConverters` | `pass` on SQLite.MS and on Oracle.23.Managed (its `[IncludeDataSources]` set excludes the other three providers run locally). All three original assertions intact, and its two `Should.Throw` blocks still discriminate: `src.Ints * 100` is same-domain, so each fails on its own literal / parameter rather than on the new refusal. |

## P10 Adjudicated

- **`Contains` / `IN` between two disagreeing converted columns stays wrong.** The issue's wording covers it
  ("any two columns of one CLR type whose converters disagree"); this branch narrows to the binary operators.
  Reason: `Contains` builds its predicate outside `ConvertCompareExpression`, and its declared-duration half
  is already filed as #5776, so both halves belong on one fix rather than half here. Disclosed in the PR body.
- **Two behaviourally-identical `ValueConverterFunc` (delegate-built) converters are refused.**
  `ConvertTheSameWay` holds delegates as opaque constants and cannot see they match (`SequenceHelper.cs:53-58`).
  Reason: the alternative — treating "cannot tell" as "agree" — keeps the silent wrong answer for exactly the
  converters we cannot inspect, which is the defect. The way out is one line: declare the conversion with
  expressions rather than delegates. Cost is bounded to a refusal, and only for a query combining two such
  columns with one operator.
- **A converted column paired with an unconverted one is refused, which is wider than the issue's literal
  wording.** User-decided after both options were costed (A-4). Measurement behind it: the whole SQLite suite
  is 11 278 cases and the wider line cost exactly one test, whose own comment conceded it was pinning the
  unconverted behaviour. Do not re-raise this as over-reach; do raise a *counter-example* if one is found.
- **A plain projection changes from a wrong value to a client-side computation, not to a refusal.** This
  diverges from the mixed pairing, which refuses in both positions (`ADeclaredDurationRefusesAnUndeclaredOne`).
  Reason: the divergence is mechanical — the mixed pairing's error comes from `TranslateMember`, ahead of
  `TryConvertToSql`'s fallback, while this one is raised below it — and the outcome is strictly better: the
  issue's own expected value for the no-`Sql.AsSql` row is `03:00:00`, which is what the fallback returns.
  Making the two uniform would mean either refusing a projection that can be answered correctly, or moving
  the check ahead of the operand visit (D-4, rejected).

## P11 Amendments

**A-1 — `TO-3` (set-operation branch) is dropped, and `SC-1` no longer claims that position.**
The obligation was written from `ARefusedPairingStaysRefusedInsideASetOperation`, which guards the mixed
pairing against a refusal being swallowed and the wrong value answered instead. Measured on SQLite, the
divergent pairing inside `Concat` and inside `Union` both answer `03:00:00` — the CLR value — because the
branch falls back to .NET exactly as any set projection does whose expression will not translate. There is
therefore no wrong value to guard against and no refusal to assert, and a fixture pinning the *refusal*
would encode a behaviour the design does not have. `SC-1`'s "a set-operation branch projection" clause is
withdrawn with it; what remains is `Sql.AsSql` and `Where`, both fixtured.

**A-2 — `E-6` is satisfied by fixtures already in `ValueConversionTests.cs`, not by a new entity in the
interval fixture.** `SeparatelyDeclaredRowA` / `RowB` already model D-2's separating input — one conversion
declared twice — so `TO-5(b)` reuses them (`SeparatelyDeclaredConversionsStillCompare`) instead of adding a
column to `DurationRow`, which every other fixture in that file would have had to re-baseline.
A second edit-point follows from the same file being the right home for the general rule:

| # | Edit | Obligations |
|---|---|---|
| E-8 | `Tests/Linq/Linq/ValueConversionTests.cs`:`DivergentConversionRow` / `DivergentConversionsRefuseToCombine` / `SeparatelyDeclaredConversionsStillCompare` — the non-duration form of the defect (`int` scaled by two against `int` scaled by three) and D-2's separating input. | TO-1, TO-2, TO-4, TO-5 |

**A-4 — The refusal covers a converted column paired with an *unconverted* one, not only two converted
columns. User-decided; `E-9` and `TO-7` follow.**
`SequenceHelper.ReadTheSameWay` answers `false` for `ConvertTheSameWay(null, conv)`, so the check as written
already refused that pairing — which surfaced as the full SQLite sweep's only failure,
`SqlRowTests.UpdateRowWithConverters` (2 cases of 11 278). The line is principled and is the one
`SetOperationBuilder.ReadsTheSameWay` already draws — *"One side without a conversion of its own is only
safe against another that has none either"* — and the pairing is wrong in exactly the reported way: with
`CentsConverter` at `net => 100 * net`, `src.Ints * src.Cents` is `2 * 100 = 200` in SQL where the CLR says
`2 * 1 = 2`. The narrower alternative (refuse only when *both* carry a converter) matches the issue's literal
wording and keeps that test green, but has no principle behind it and leaves the commoner half of the shape
silently wrong. Put to the user with both costs stated; they chose the wider line.

| # | Edit | Obligations |
|---|---|---|
| E-9 | `Tests/Linq/Linq/SqlRowTests.cs`:`UpdateRowWithConverters` — `src.Ints * src.Cents` → `src.Ints * 100` at its three sites, which keeps every value the test asserts and keeps its two throw-blocks failing for *their* reason (the literal and the parameter in a converted `Row` slot) rather than for the new refusal. | TO-7 |

`TO-7`: `UpdateRowWithConverters` still passes on SQLite and Oracle with all three of its original assertions
intact — `count = 1`, `Cents = 2`, `Ints = 200` — and its two `Should.Throw` blocks still fail on the literal
and the parameter. Mode: `characterization` for the reworked test; the *new* behaviour it made room for is
asserted separately by `TO-1`'s `unconverted` arm in `DivergentConversionsRefuseToCombine` (`Doubled + Plain`
refused, naming both columns), which is `red→green` and mutation-checked with the rest.

**A-3 — Observed, not fixed: `Count(predicate)` drops the `Additional details` half of any refusal.**
`t.Count(r => …)` reports only *the LINQ expression … could not be converted to SQL*, losing the named
reason; `t.Where(r => …)` keeps it. Measured on both refusals — the new one and #5750's
`Error_Interval_UndeclaredOperand`, which this branch does not touch — so it is pre-existing and belongs to
`EnsureError`'s handling in `ExpressionBuilder.SqlBuilder.cs:77`, which replaces a message-carrying error
with a bare one when the error's expression still holds a placeholder. Out of scope here; the fixtures use
`Where` so they assert the message where it survives.

## P12 Critic verdict

`waived-by-user`: this session's operating instructions forbid dispatching subagents unless the user asks,
so `plan-critic` was not run. Recorded rather than substituted — the self-review in D-1..D-4's failure-mode
lines is not a verdict.
