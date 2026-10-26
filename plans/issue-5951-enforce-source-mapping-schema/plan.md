# Work plan: issue-5951-enforce-source-mapping-schema — Build steps read the source sequence's MappingSchema (LINQ2DB0007)

**Tier:** L  ·  **Status:** approved  ·  **Approved-at:** 2026-10-24 (user, after critic round 4 `weak`)  ·  **Branch:** issue/5951-enforce-source-mapping-schema
**Schema:** `.claude/docs/work-plan.md`  ·  **Gates:** `.claude/docs/definition-of-done.md`

Tier L: two areas (the `Source/CodeGenerators` analyzer host and the `Internal/Linq/Builder` engine) plus tests. Closes [#5951](https://github.com/linq2db/linq2db/issues/5951) (milestone 6.6.0). `Builder/` = `Source/LinqToDB/Internal/Linq/Builder/`. Line numbers are against `origin/master` 602484aca.

## P1 Problem

A LINQ query can reach two mapping schemas while it is built. `ExpressionBuilder.MappingSchema` is the data context's schema, read live (`Builder/ExpressionBuilder.cs:218`, `=> DataContext.MappingSchema`; same alias at `Builder/ParametersContext.cs:34`). `IBuildContext.MappingSchema` is the source's snapshot, baked into the tree when the handle was created (`Source/LinqToDB/Internal/Linq/Table{T}.cs:18-21,37-40` → `SqlQueryRootExpression`; read back by `Builder/TableBuilder.cs:227-241`). They differ when a handle is obtained before `db.UseMappingSchema(ms)` / `AddMappingSchema` and the query is built inside the scope; that divergence is deliberate and pinned by `Tests/Linq/Mapping/UseMappingSchemaTests.cs:56-99` (`Test2`: the pre-scope handle keeps emitting `Field1`).

A build step that holds a source but reads the live schema mixes the two: the snapshot decides column names (resolved later through the source context), while the live read decides another facet of the same entity or type. Falsifiable shape from the issue's PR #5708 repro: an unpivot over a pre-scope table renamed in the scope read `[Q1]` while labelling the value `Q_RENAMED`. The facets the live reads on master decide (critic round 1, verified per site):

- column *set* / PK / skip-on-insert: `Builder/EntityInsertBuilder.cs:47`, `Builder/EntityUpdateBuilder.cs:49`, `Builder/UpsertBuilder.cs:57`, `Builder/MergeBuilder.InsertWhenNotMatched.cs:44`;
- association presence, child query filters, inheritance mapping and discriminator codes: `Builder/AssociationHelper.cs:150,174,274,321,337,343` (ignore their own `mappingSchema` parameter), `Builder/ExpressionBuilder.Associations.cs:37,64,150,154,167,174,182,208`;
- column names: `Builder/TableBuilder.RawSqlContext.cs:77` (`SqlRawSqlTable` fields from the live descriptor);
- aliases: `Builder/ExpressionBuilder.Expressions.cs:126`;
- type-level: default values (`Builder/ExpressionBuilder.SqlBuilder.cs:1313,1370,1710,1712,1758,1769,1826`), scalar-type registration (`Builder/GroupByBuilder.cs:389`, `Builder/TableBuilder.RawSqlContext.cs:48`), discriminator conversion (`Builder/ExpressionBuilder.SqlBuilder.cs:702,807`), DbDataType (`Builder/ExpressionBuilder.EagerLoad*.cs` `AdjustType`), parameter conversion (`Builder/ParametersContext.cs:278,292,325,336,340`);
- the schema a new context carries: `Builder/SelectBuilder.cs:71`, `Builder/EnumerableContextDynamic.cs:26`, `Builder/SelectContext.cs:42` (+ `Clone` `:209`), `Builder/GroupJoinBuilder.cs:52`, `Builder/TableBuilder.cs:276,283`, `Builder/SelectQueryBuilder.cs:15`.

Nothing enforces the rule, so new build steps keep adding such reads.

## P2 Success criteria

- SC-1 LINQ2DB0007 exists in `Source/CodeGenerators`, and on the unfixed master tree a Release build of `Source/LinqToDB` reports exactly the P7 rows marked `report` — no more, no fewer.  → TO-1, TO-2
- SC-2 After the fixes, `dotnet build Source/LinqToDB/LinqToDB.csproj -c Release -f net10.0` reports zero LINQ2DB0007 and the tree contains zero `#pragma warning disable LINQ2DB0007`.  → TO-3
- SC-3 Every trigger (R-def, R1–R5), the live-read derivation, the restricted E0 exemption and the drift diagnostic have analyzer fixtures that fail when that branch is mutated away.  → TO-4 … TO-21
- SC-4 For a handle obtained before a `UseMappingSchema` scope that changes one facet of its entity, the query built inside the scope follows the handle's snapshot for that facet. One cell per facet: skip-on-insert (entity Insert, Merge default insert), primary key (entity Update, Upsert native + Merge-lowered), child query filter (association join shape), association declared only in the scope, inheritance mapping declared only in the scope (association TPH root + `OfType`), column rename (`FromSql`), alias (`HandleAlias`), a two-handle join where the member belongs to the second handle (association detection, `is` predicate), eager-load column typing under a different detail snapshot.  → TO-22 … TO-32, TO-32b, TO-38
- SC-5 For the type-level facets D-3 moves — default values (`SetDefaultValue`), scalar-type registration, discriminator-value conversion, parameter conversion — a pre-scope handle built inside a scope that changes the facet follows the snapshot.  → TO-33 … TO-36
- SC-6 Outside any schema divergence, generated SQL is unchanged (no baseline diffs).  → TO-37

## P3 Constraints & anti-goals (M/L)

- No public API change: every touched type is `internal` (`Builder/ExpressionBuilder.cs:26`, `Builder/SelectContext.cs:18`, `Builder/BuildContextBase.cs:11`, `Builder/ParametersContext.cs`); PublicAPI grep for the changed members returned nothing.
- Generated SQL and baselines unchanged when snapshot == live (every fix substitutes the same instance then).
- Query-cache keying unchanged (`Source/LinqToDB/Internal/Linq/QueryCache.cs:516` keys on the live `ConfigurationID`).
- Anti-goal: extension / query-extension / table-function attribute lookups and member translation stay live (issue's class C; D-6). Expose-phase reads (`Builder/Visitors/ExposeExpressionVisitor.cs`, `Builder/ExpressionTreeOptimizationContext.cs`) are out of scope (P10 L-3).
- Anti-goal: reader-side type conversion is resolved at execution from the runtime context (`Source/LinqToDB/Internal/Expressions/ConvertFromDataReaderExpression.cs:63,77,82`) and is not changed (P10 L-4).
- Anti-goal: no derivation of the builder's schema from the query root (D-1 rejected).
- Narrowing / widening vs the issue, disclosed in the PR body: id `LINQ2DB0007` (0002 is taken, `Source/CodeGenerators/AnalyzerReleases.Unshipped.md:8-13`); class A is not handled by a marker or allowlist — true roots are silent by construction, and the root-seeding sites the issue called correct are fixed (D-4); the census is wider than the issue's (P7).
- User-visible deltas vs master — only for a handle created before a schema swap on the same context and queried inside it:
  - the facets listed in SC-4 / SC-5 follow the handle's snapshot instead of the scope's schema;
  - consequence: an association, inheritance mapping, filter, PK or skip flag declared *only* in the scope no longer applies to a pre-scope handle;
  - (A-3) everything `ExpressionBuildVisitor.MappingSchema` (`:79`, `BuildContext?.MappingSchema ?? …`) resolves inside a `SelectContext` follows the snapshot, because the `SelectContext` ctor now takes the source's schema;
  - (A-3) `CreateTempTable(…, setTable)` is a schema swap too: it sets the context's schema while the temp table lives (`DataExtensions.TempTable.cs:1158-1172`, restored `TempTable.cs:853,868`), so a handle created before it keeps its own key / column set (TO-39);
  - shipped prose to check: `UseMappingSchema` / `AddMappingSchema` XML docs (U-12).

## P4 Unknowns (M/L)

- U-1 Is every "in-scope" carrier actually the read's source? Non-sources: `IBuildContext.Parent` and ctor parameters named `parent` (assigned to `Parent`), and the dead `out parentContext` (`Builder/TableBuilder.cs:43-45,260`, verified always `null`). `GroupJoinBuilder.cs:52` falls back from `Parent` (verified: `Parent = buildInfo.Parent`, `:37,65`), so it is a defect, not a fallback. — resolved-by scout (D-5; E0 restricted, D-1)
- U-2 Does `SemanticModel.LookupSymbols(position)` give block-correct scoping with a declaration-start < read-start filter (eager-load methods declare contexts in closed `else` blocks, `Builder/ExpressionBuilder.EagerLoadDefault.cs:45,63`)? — resolved-by probe (TO-12, TO-13 fail on a wrong implementation)
- U-3 Instance members inside a constructor initializer and inside static members. — resolved-by probe (TO-15, TO-16)
- U-4 Which properties alias the live schema? Critic's full read of `MappingSchema` over `Builder/**` (326 hits): `=> DataContext.MappingSchema` at `Builder/ExpressionBuilder.cs:218`, `Builder/ParametersContext.cs:34`, `Builder/Visitors/ExposeExpressionVisitor.cs:39` (`_dataContext`); `Builder/ExpressionTreeOptimizationContext.cs:23,28` is an auto-property set from `dataContext.MappingSchema`. — resolved-by scout (D-1 derives the alias set from getter shape; the optimization context and Expose are P10 L-3)
- U-5 `GetRootMappingSchema` accepts `SqlQueryRootExpression`, `NewExpression` (arg 0), or an `IDataContext`-evaluable expression, and throws otherwise (`Builder/TableBuilder.cs:227-241`). Entity builders and `GroupJoin` hold a table / sequence expression, not the root. — resolved-by scout (D-4: a Try walker over the source-argument chain)
- U-6 Do the root-seeding calls carry a root when they reach the builders? Producers `Source/LinqToDB/DataExtensions.cs:1421,1480,1522,1566,1613,1640`, `Source/LinqToDB/LinqExtensions/LinqExtensions.cs:51,82,1237`, `Source/LinqToDB/LinqExtensions/LinqExtensions.AsQueryable.cs:55`; critic: `ExposeExpressionVisitor.cs:572,591,847` create live roots only for compiled-query roots and Member/Constant dc arguments, so a `FromSql`/`SelectQuery` root survives. — resolved-by scout (TO-27 red→green is the run observation)
- U-7 `ProcessProjection` is dead: `ProcessProjection\(` over the worktree hits only the declaration `Builder/ExpressionBuilder.SqlBuilder.cs:924` and self-recursion `:993-994`. — resolved-by scout (delete, E-10)
- U-8 Class-C "additive" argument (live attribute lookups are a superset of the snapshot's after `CombineSchemas(new, old)`, `Source/LinqToDB/Data/DataConnection.cs:1768`): reasoned only. — resolved-by user answer (D-6 keeps master behaviour; P10 L-1)
- U-9 Source choice at multi-context sites (eager load: parent `buildContext` vs `detailSequence`; `SelectManyBuilder.cs:103` wraps `expanded` built from `collection` at `:97`, verified). — resolved-by scout (D-7: the context whose expression produced the value; `:103` → `collection.MappingSchema`)
- U-10 Which input makes each SC-4/SC-5 cell red on master? A column rename separates only `RawSqlContext.cs:77`; every other site consumes a non-name facet (critic round 1: `ColumnName` absent from the entity-builder files; `AssociationHelper.cs:150-152` builds `MakeMemberAccess`, `:174` reads `QueryFilters`, `:321,:337` read `InheritanceMapping`). Each TO names the facet its read consumes. — resolved-by probe (each TO's red run; a cell found green on master is reclassified via P11 with the reason, never silently)
- U-11 Remote parity: client-side translation runs on `RemoteDataContextBase` (`Source/LinqToDB/Remote/RemoteDataContextBase.cs:55-67,790-803`), only the SQL AST is serialized. — resolved-by scout (tests use `[DataSources]` incl. `.LinqService`)
- U-12 Does a shipped XML doc on `UseMappingSchema` / `AddMappingSchema` promise behaviour this changes? — resolved-by probe (grep before implementation; a promise found gets an E-row via P11)
- U-13 Analyzer-own perf baseline has only LINQ2DB0001 for LinqToDB (`.claude/docs/analyzer-own-perf-baseline.json`). — resolved-by scout (G-01b records `/profile-analyzers rules`; baseline row is a corpus follow-up)
- U-14 `C:\Worktrees` is a junction to another volume and the C:-only hook blocks command text naming the resolved path. — resolved-by probe (all commands use `C:\Worktrees\…`; git/pwsh observed working)
- U-16 Where is `ExpressionBuildVisitor.BuildContext` null at the visitor's 45 reads of its source-first alias `MappingSchema => BuildContext?.MappingSchema ?? Builder.MappingSchema` (`Builder/ExpressionBuildVisitor.cs:79`)? `BuildContext` is set only through a state holder (`:244`), and the SQL/expression paths bail out when it is null (`:415,:2054,:3079,:3134,:3386,:3452,:4214,:4634`), so a null `BuildContext` means the visitor is not building inside a sequence — no carrier exists. — resolved-by scout (P10 L-5; the issue itself classes `:79` as the correct fallback)
- U-17 Does the override shape separate the type-level cells? The live schema is `CombineSchemas(added, old)` (`Source/LinqToDB/Data/DataConnection.cs:1768`), so it differs from the snapshot only where the scope adds or overrides a facet. Type-level cells therefore declare facet value A on the context's base schema (`DataOptions.UseMappingSchema`) and override it with B in the `db.UseMappingSchema` scope, asserting A; a scope-only addition would make the fix's assertion "the facet is absent". — resolved-by scout (TO-30, TO-32…TO-36 use the override shape)
- U-18 Does `DbDataType` equality between a descriptor-derived and a schema-derived `Int32` hold at `AllocateSlot` (`EagerLoadUnion.cs:612`), so the fix actually shares the slot in TO-32? — resolved-by probe (TO-32's first run is the observation; a cell that cannot separate is reclassified via P11 and joins P10 L-7)
- U-19 Do TO-36's two arms reach `ParametersContext.cs:278` / `:325` at all (descriptor survival under `Convert(t.Id, long)`; `Sql.AsSql` routing to `BuildParameter`)? — resolved-by probe (run before writing the assertion; reclassify via P11 if unreachable)
- U-15 Can the facets in SC-4/SC-5 be declared in a scope at all (fluent `HasSkipOnInsert`, `IsPrimaryKey`, `HasQueryFilter`, `Association`, `Inheritance`, `IsAlias`, `SetDefaultValue`, `AddScalarType`, `SetConverter`) on a `FluentMappingBuilder(new MappingSchema())` passed to `UseMappingSchema`? — resolved-by probe (each TO's setup compiles and the green arm passes; a facet not expressible is a P11 reclassification)

## P5 Decisions (M/L; rejected alternatives mandatory at L)

### D-1 — One analyzer, LINQ2DB0007, six triggers on reads of the live schema

*Live-schema property*: a property declared in namespace `LinqToDB.Internal.Linq.Builder` or a sub-namespace whose getter is expression-bodied `=> <IDataContext-typed expr>.MappingSchema` — derived at compilation start (today `ExpressionBuilder.MappingSchema`, `ParametersContext.MappingSchema`, `ExposeExpressionVisitor.MappingSchema`). *Live read*: an `IPropertyReferenceOperation` of a live-schema property, or of `IDataContext.MappingSchema` whose receiver chain reaches an `ExpressionBuilder`-typed expression (`builder.DataContext.MappingSchema`, `Builder.DataContext…`), not an assignment target, inside that namespace prefix, outside the alias getter itself. Symbols resolve from `Compilation.Assembly` (`Source/CodeGenerators/ProjectFlagsAnalyzer.cs:88-99`), so consumers pay nothing.

*Source carrier*: an `IBuildContext`, a `ContextRefExpression` (via `.BuildContext`), an `EntityDescriptor` / `ColumnDescriptor` / `AssociationDescriptor` (each has `.MappingSchema`: `Source/LinqToDB/Mapping/EntityDescriptor.cs:35`, `ColumnDescriptor.cs:241`, `AssociationDescriptor.cs:86`), or a `MappingSchema` value. A carrier is *in scope* if it is a parameter of the enclosing method / lambda / local function (outer ones included); a local or pattern variable declared before the read and in scope at it, other than the local whose own initializer contains the read (`var ms = builder.MappingSchema;` is not a carrier for itself); or an instance field/property of the containing type **only when that type implements `IBuildContext`**, the member is non-static and the position is not in a constructor initializer. `Parent`, the context's own `MappingSchema` property (A-1) and parameters named `parent` never count (D-5). The `IBuildContext`-only restriction on instance members exists because the alias owner itself exposes a carrier-typed property (`Builder/ExpressionBuilder.Expressions.cs:15` `ColumnDescriptor? CurrentDescriptor`) that would otherwise put a carrier in scope of every non-static `ExpressionBuilder` member.

*E0 (only exemption)*: the read is, after unwrapping conversions, the `WhenNull` operand of an `ICoalesceOperation` whose left operand is `<carrier>.MappingSchema` (other than `Parent`) or a `TryGetRootMappingSchema(...)` call. A read nested deeper in the right operand is not exempt.

- **R-def** — the read is a context type's own `MappingSchema` getter, or assigns the field that getter returns in a constructor: report iff the type declares or inherits an `IBuildContext`-typed instance member other than `Parent`. Separating inputs: `CounterContext` (`_sequence`) reports, `EnumerableContext` (only `Parent`) silent.
- **R1** — a `MappingSchema` carrier is in scope.
- **R2** — a descriptor carrier is in scope.
- **R3** — the receiver chain goes through an `IBuildContext`'s `Builder` (`x.Builder.MappingSchema`, implicit `Builder` in a context type), outside R-def's sites.
- **R4** — an `IBuildContext` / `ContextRefExpression` carrier is in scope.
- **R5** — the read is inside an override of `MethodCallBuilder.BuildMethodCall` (its source is `methodCall.Arguments[0]` even before it is built), unless it is an argument to a D-6 lookup.

The message names the carrier found (`'{0}' is in scope: read its MappingSchema instead of the data context's`).

- **chosen:** the above, one id, `Usage`/`Warning`, row in `AnalyzerReleases.Unshipped.md`, public analyzer class with `<summary>`/`<inheritdoc/>` (`Source/CodeGenerators/Directory.Build.props:10,20` sets `TreatWarningsAsErrors` + `GenerateDocumentationFile`).
- **rejected:** "context in scope" alone — recall 3/12 on the issue's class D (scout 2) and false positives on a dead `out` param and `: base(…)`. "Flag every read + annotate" — ~28 members, ~20 not capture points (user rejected). Split the accessor (rename, ban entity use) — 76 edits for the same outcome. Derive the builder's schema from the query root — multi-root joins have no single root, the cache is keyed on the live `ConfigurationID` (`QueryCache.cs:516`, `Query.cs:48-52`). `MappingSchema` as a ctor argument of every context (`TableContext.cs:55` style) — ~45 files. A hardcoded alias list — misses the next `=> DataContext.MappingSchema` (the critic found `ParametersContext` that way).
- **why this:** each trigger is a syntactic proxy for "a snapshot value is reachable here", the one condition under which a live read can be wrong; the alias set is derived, so a new alias is covered.
- **failure mode of the choice:** a source reachable only through an unbuilt `Expression` in a helper not named `BuildMethodCall` is invisible (P10 L-2); an alias written as an auto-property set in a ctor (the `ExpressionTreeOptimizationContext` shape) is not derived (P10 L-3).

### D-2 — Escape hatch is `#pragma warning disable LINQ2DB0007 // <reason>`

- **chosen:** `#pragma` with a reason (house hatch, `ProjectFlagsAnalyzer.cs:40`); zero instances after this PR (SC-2). E0 is a structural exemption, not a hatch: its left operand must be a source carrier, so `Parent?.MappingSchema ?? Builder.MappingSchema` is reported (TO-18).
- **rejected:** an internal marker attribute — member-level, so it exempts whole methods; withdrawn by the user once no site needed it. A named alternative accessor — a second alias needing judgement at every use.
- **why this:** expression-tight, greppable by id, no new type.
- **failure mode of the choice:** a pragma states no intent beyond its comment.

### D-3 — Type-level reads with a source in scope are reported and fixed (user decision)

- **chosen:** default values, scalar-type checks, discriminator-value conversion, DbDataType, parameter conversion at the P1 sites switch to the source's schema.
- **rejected:** leaving them silent as a policy class (fable's proposal) — the user chose consistency.
- **why this:** one rule everywhere; a scope that changes a type facet should not reach into a handle created before it.
- **failure mode of the choice:** a user relying on a scope's default value / scalar type applying to a pre-scope handle sees a change. Reader-side conversion is unaffected (P10 L-4), so the delta is build-time facets only; separating inputs in TO-33…TO-36.

### D-4 — Root-seeding and pre-sequence sites read the snapshot through `TryGetRootMappingSchema`

- **chosen:** move `GetRootMappingSchema` from `TableBuilder` to `ExpressionBuilder` (internal) and add `TryGetRootMappingSchema(Expression)`: walk the source-argument chain (method call `Arguments[0]` / `Object`, the table wrappers `ApplyTableName`/`ApplyTableOptions`/`ApplyTableDescriptor` from `Table{T}.cs:52-66`, `NewExpression` arg 0) to a `SqlQueryRootExpression` and return its schema, or `null`. Sites write `builder.TryGetRootMappingSchema(expr) ?? builder.MappingSchema` (E0-silent): `TableBuilder.cs:276,283`, `TableBuilder.RawSqlContext.cs:48,77`, `SelectQueryBuilder.cs:15` (via the new `SelectContext` arg), `EntityInsertBuilder.cs:47`, `EntityUpdateBuilder.cs:49`, `UpsertBuilder.cs:57`, and `GroupJoinBuilder.cs:37` (inner expression, falling back to `outerContext.MappingSchema`).
- **rejected:** keeping them as capture points — they carry a snapshot (U-6). Building the target sequence first in the entity builders — reorders their validation (`UpsertBuilder.cs:57-100`).
- **why this:** one helper owns "find the snapshot in an expression"; the fallback keeps master behaviour where no root exists.
- **failure mode of the choice:** a shape the walker misses silently falls back to live; TO-22…TO-27 are the observation for the public APIs.

### D-5 — False positives are removed at the root, not suppressed

- **chosen:** delete the dead `out IBuildContext? parentContext` (`TableBuilder.cs:43-45,260`); delete dead `ProcessProjection` (U-7); `SelectContext` ctor #1 (`:35`) takes a `MappingSchema`: callers pass `outerContext.MappingSchema` (`AllJoinsLinqBuilder.cs:97`, `JoinBuilder.cs:147`), `collection.MappingSchema` (`SelectManyBuilder.cs:103`), `sequence.MappingSchema` (`SelectManyBuilder.cs:126`, `DefaultIfEmptyBuilder.cs:75`, `InsertBuilder.cs:172`), the D-4 root (`SelectQueryBuilder.cs:15`), and `Clone` (`:209`) passes `_mappingSchema`; `GroupJoinInnerContext` takes its schema as a ctor argument (D-4); `Parent` / `parent` are not sources (U-1).
- **rejected:** a marker or pragma at those sites — they are dead code or real defects.
- **why this:** after these, every report on the tree is a real defect.
- **failure mode of the choice:** excluding `parent` by name misses a source parameter named `parent`; none in the census.

### D-6 — Class-C lookups stay live

- **chosen:** R5 exempts a live read that is an argument to `Sql.ExtensionAttribute.GetExtensionAttributes`, `Sql.QueryExtensionAttribute.GetExtensionAttributes`, `GetTableFunctionAttribute`, `SkipMethodChain` (closed list, `Guards`-table idiom of `SqlBuilderAliasAnalyzer.cs:39-45`); R1–R4 do not reach these sites (no carrier in scope, scout 2 + critic).
- **rejected:** switching them — no source exists before the sequence is built, and whether extensions should follow the snapshot is the issue's open question (U-8).
- **why this:** master behaviour is kept where the semantics are undecided.
- **failure mode of the choice:** a future entity lookup passed through one of these four methods would be exempt; the list is closed and named in the analyzer.

### D-7 — Per-site choice at multi-context sites

- **chosen:** use the carrier whose expression produced the value being typed or constructed (eager load: the detail sequence for detail values, the parent for keys; `SelectManyBuilder.cs:103` → `collection`); recorded per site in the commit body.
- **rejected:** always the first in-scope carrier — can pick the parent for a detail value.
- **why this:** the analyzer proves only that a snapshot exists; the right one is a code-reading decision.
- **failure mode of the choice:** a wrong pick is invisible unless the two snapshots differ. `LoadWith` cannot separate it (the detail root is built from the parent's schema, `AssociationHelper.cs:44,97-99`); TO-32 uses an explicit sub-query projection over a second handle (`tmp.Select(p => new { Details = tmp2.Where(...).ToList() })`).

### D-9 — Association detection takes the source's schema at every caller

- **chosen:** `ExpressionBuilder.IsAssociation(Expression, out MemberInfo?)` (`Builder/ExpressionBuilder.Associations.cs:99`) and `IsAssociationInRealization` take a `MappingSchema`; callers pass the member's own source (D-7), falling back to the visitor's source-first alias (`:79`) only when there is none: `ExpressionBuildVisitor.cs:1810,1822` `rootContext.BuildContext.MappingSchema` (`TryCreateAssociation`'s parameter `:1808`, the same schema the association query already uses at `:1878` → `AssociationHelper.cs:401`); `:1581` `(node.Expression as ContextRefExpression)?.BuildContext.MappingSchema ?? MappingSchema`; `:870` the receiver's `ContextRefExpression` (`node.Object` / `node.Arguments[0]`) the same way; `LoadWithBuilder.cs:252` `sequence.MappingSchema` threaded from `BuildMethodCall :41` through `ExtractAssociations`/`GetAssociations` (`:143,:178`), `TableLikeQueryContext.cs:218` `ctx.TargetContextRef.BuildContext.MappingSchema` (as `:132` already does).
- **rejected:** threading the schema only into `GetAssociationDescriptor` (`:1810`) — detection stays live while the descriptor goes snapshot, so `LoadWith(x => x.ScopeOnlyAssoc)` passes `LoadWithBuilder.cs:252` and then gets a null descriptor (critic round 2).
- **why this:** detection and resolution must agree; once the schema is a parameter, R1 guards the bodies.
- **failure mode of the choice:** a fifth caller added later without a schema would not compile — loud, acceptable.

### D-10 — Patch both `MakeIsPredicateExpression` copies; do not unify

- **chosen:** `Builder/ExpressionBuilder.SqlBuilder.cs:807` uses `table.MappingSchema` (the table built from `context.MappingSchema` at `:749`) and its near-verbatim twin `Builder/ExpressionBuildVisitor.cs:5723` uses `tableContext.MappingSchema`; both are the discriminator-code `Converter.ChangeType`. `x is Derived` reaches the visitor copy (`VisitTypeBinary` → `:3997`), the `TypeAs` projection reaches `:807` (`:1806-1812`).
- **rejected:** unify into one helper — the copies differ in how the table is obtained (the term combination `ExpressionBuildVisitor.cs:5729-5732` / `ExpressionBuilder.SqlBuilder.cs:813-816` is identical); merging them is a refactor with no observable effect, outside this issue.
- **why this:** both copies get the same one-token fix, so the twin cannot drift on this point.
- **failure mode of the choice:** the twin survives; a future fix to one copy can still miss the other (P10 L-6).

### D-8 — Drift is reported, not silent

- **chosen:** if `ExpressionBuilder` resolves in the compilation assembly but `IBuildContext`, `ContextRefExpression`, `MethodCallBuilder`, `EntityDescriptor`, `ColumnDescriptor` or `AssociationDescriptor` does not, or no live-schema property is derived, report LINQ2DB0007 once on `ExpressionBuilder` with a "model unreadable" message (`ProjectFlagsAnalyzer.cs:100-115` precedent).
- **rejected:** return silently — retires the rule with no signal.
- **why this:** a rename of a companion type must fail the build.
- **failure mode of the choice:** one id with two meanings; the message text distinguishes them.

## P6 Edit-points

- E-1 `Source/CodeGenerators/BuildContextMappingSchemaAnalyzer.cs` — new analyzer (D-1, D-6, D-8), XML docs.
- E-2 `Source/CodeGenerators/AnalyzerReleases.Unshipped.md` — `LINQ2DB0007 | Usage | Warning | BuildContextMappingSchemaAnalyzer`.
- E-3 `Tests/Tests.Analyzers.Internal/BuildContextMappingSchemaAnalyzerTests.cs` — new fixture with a miniature model.
- E-4 `Source/LinqToDB/Internal/Linq/Builder/ExpressionBuilder.cs` — `MappingSchema` remark naming LINQ2DB0007; host `GetRootMappingSchema` / `TryGetRootMappingSchema` (D-4).
- E-5 `Source/LinqToDB/Internal/Linq/Builder/TableBuilder.cs` — remove `out parentContext`; move the root helper; `:276,:283` use the call's root.
- E-6 `Source/LinqToDB/Internal/Linq/Builder/TableBuilder.RawSqlContext.cs` — `:48,:77` read the `FromSql` root.
- E-7 `Source/LinqToDB/Internal/Linq/Builder/AssociationHelper.cs` — six reads use the `mappingSchema` parameter.
- E-8 `Source/LinqToDB/Internal/Linq/Builder/ExpressionBuilder.Associations.cs` — `GetAssociationDescriptor(Expression…)`, `IsAssociation(Expression, out)`, `IsAssociationInRealization` take a `MappingSchema` (D-9); reads at `:37,:51,:64,:85,:150,:154,:167,:174,:182,:208` use it / `entityDescriptor.MappingSchema`.
- E-9 `Source/LinqToDB/Internal/Linq/Builder/ExpressionBuildVisitor.cs` — `:1810,:1822` pass `rootContext.BuildContext.MappingSchema`; `:870,:1581` pass the member's own `ContextRefExpression` schema with the visitor alias as fallback (D-9); `:5723` uses `tableContext.MappingSchema` (D-10).
- E-10 `Source/LinqToDB/Internal/Linq/Builder/ExpressionBuilder.SqlBuilder.cs` — delete `ProcessProjection`; `:807` uses `table.MappingSchema` (D-10); `Project` `:1313…:1826` use `context.MappingSchema`; `:328`, `:1876` use `columnDescriptor?.MappingSchema ?? MappingSchema`; `:702` uses `m.Discriminator.MappingSchema`.
- E-11 `Source/LinqToDB/Internal/Linq/Builder/ExpressionBuilder.Expressions.cs` — `HandleAlias :126` uses `(memberExpression.Expression as ContextRefExpression)?.BuildContext.MappingSchema ?? context.MappingSchema` (D-7: the member's own source in a join projection).
- E-12 `Source/LinqToDB/Internal/Linq/Builder/ExpressionBuilder.QueryBuilder.cs` — `:148` uses `_context.MappingSchema`; `:660,:682` use the `columnDescriptor` local (`:659`) with E0 fallback.
- E-13 `Source/LinqToDB/Internal/Linq/Builder/ExpressionBuilder.EagerLoadDefault.cs` — `:142` (D-7).
- E-14 `Source/LinqToDB/Internal/Linq/Builder/ExpressionBuilder.EagerLoadKeyedQuery.cs` — `:365` (D-7).
- E-15 `Source/LinqToDB/Internal/Linq/Builder/ExpressionBuilder.EagerLoadUnion.cs` — `:646,:751,:1050,:1256` (D-7).
- E-16 `Source/LinqToDB/Internal/Linq/Builder/SelectContext.cs` — ctor #1 takes `MappingSchema`; `Clone` passes `_mappingSchema`.
- E-17 `Source/LinqToDB/Internal/Linq/Builder/AllJoinsLinqBuilder.cs` — pass `outerContext.MappingSchema`.
- E-18 `Source/LinqToDB/Internal/Linq/Builder/JoinBuilder.cs` — pass `outerContext.MappingSchema`.
- E-19 `Source/LinqToDB/Internal/Linq/Builder/SelectManyBuilder.cs` — `:103` pass `collection.MappingSchema`; `:126` pass `sequence.MappingSchema`.
- E-20 `Source/LinqToDB/Internal/Linq/Builder/DefaultIfEmptyBuilder.cs` — pass `sequence.MappingSchema`.
- E-21 `Source/LinqToDB/Internal/Linq/Builder/InsertBuilder.cs` — `:172` pass `sequence.MappingSchema`.
- E-22 `Source/LinqToDB/Internal/Linq/Builder/SelectQueryBuilder.cs` — pass `builder.TryGetRootMappingSchema(methodCall.Arguments[0]) ?? builder.MappingSchema`.
- E-23 `Source/LinqToDB/Internal/Linq/Builder/SelectBuilder.cs` — `CounterContext.MappingSchema => _sequence.MappingSchema`.
- E-24 `Source/LinqToDB/Internal/Linq/Builder/EnumerableContextDynamic.cs` — `ValuesContext?.MappingSchema ?? Builder.MappingSchema`.
- E-25 `Source/LinqToDB/Internal/Linq/Builder/GroupByBuilder.cs` — `:389` uses the context's own `MappingSchema`.
- E-26 `Source/LinqToDB/Internal/Linq/Builder/MergeBuilder.InsertWhenNotMatched.cs` — `:44` uses `mergeContext.MappingSchema`.
- E-27 `Source/LinqToDB/Internal/Linq/Builder/EntityInsertBuilder.cs` — `:47` root of `tableArg` (D-4).
- E-28 `Source/LinqToDB/Internal/Linq/Builder/EntityUpdateBuilder.cs` — `:49` root of `tableArg` (D-4).
- E-29 `Source/LinqToDB/Internal/Linq/Builder/UpsertBuilder.cs` — `:57` root of `tableArg`; `:776` `Context.MappingSchema`.
- E-30 `Source/LinqToDB/Internal/Linq/Builder/InsertOrUpdateBuilder.cs` — `:152` the context's `MappingSchema`.
- E-31 `Source/LinqToDB/Internal/Linq/Builder/ParametersContext.cs` — `PrepareParameterCacheEntry` `:278,:292,:325,:336,:340` use its `mappingSchema` parameter.
- E-32 `Source/LinqToDB/Internal/Linq/Builder/GroupJoinBuilder.cs` — `GroupJoinInnerContext` takes a `MappingSchema` (D-4/D-5); `:52` returns it.
- E-33 `Tests/Linq/Mapping/UseMappingSchemaTests.cs` — SC-4 / SC-5 / SC-6 tests.
- E-34 `Source/LinqToDB/Internal/Linq/Builder/LoadWithBuilder.cs` — thread `sequence.MappingSchema` from `BuildMethodCall :41` through `ExtractAssociations`/`GetAssociations` to `IsAssociation :252` (D-9).
- E-35 `Source/LinqToDB/Internal/Linq/Builder/TableLikeQueryContext.cs` — `:218` passes `ctx.TargetContextRef.BuildContext.MappingSchema` (D-9).

## P7 Impact map (M/L)

Census verdict per site (`report` = LINQ2DB0007 expected on unfixed master; drives TO-1). Searches: scout 1 `MappingSchema` over `Builder/ExpressionBuilder*.cs` (59 hits, 41 reads); scout 2 `[Bb]uilder\??\.MappingSchema\b` over `Source/LinqToDB/**/*.cs` + receiver/alias sweeps (35 reads); critic round 1 `MappingSchema` over `Builder/**` (326 hits read in full); this session `SelectContext\(` callers, `ProcessProjection\(`, `SqlQueryRootExpression.Create`, `ParametersContext.cs`, `ExposeExpressionVisitor.cs`, `ExpressionTreeOptimizationContext.cs`.

- `Builder/AssociationHelper.cs:150,174,274,321,337,343` — report R1 — covered by E-7
- `Builder/ExpressionBuilder.Associations.cs:167,174,182,208` — report R2 (`entityDescriptor` param) — covered by E-8
- `Builder/ExpressionBuilder.Associations.cs:37,64` — report R4 (`contextRef` pattern variable) — covered by E-8
- `Builder/ExpressionBuilder.Associations.cs:51,85,150` — silent (no carrier; `CurrentDescriptor` excluded by the `IBuildContext`-only instance clause; `:150` is the self-initialiser of `entityDescriptor`); fixed by threading a schema parameter (D-9) — covered by E-8, E-9
- `Builder/ExpressionBuilder.Associations.cs:154` — report R2 (`entityDescriptor` local declared at `:150`, critic round 3) — covered by E-8
- `IsAssociation(Expression, out)` callers `Builder/ExpressionBuildVisitor.cs:870,1581`, `Builder/LoadWithBuilder.cs:252`, `Builder/TableLikeQueryContext.cs:218` (grep `\.IsAssociation\(` over `Source/LinqToDB`, critic round 2) — signature change, source per caller in D-9 — covered by E-9, E-34, E-35
- `Builder/TableLikeQueryContext.cs:132`, `Builder/TableBuilder.TableContext.cs:283` — `IsAssociation(MappingSchema)` extension already given the context's schema — out-of-scope
- `MakeIsPredicateExpression` twin `Builder/ExpressionBuildVisitor.cs:5663-5723` (grep `MakeIsPredicateExpression\(|MakeIsPredicate\(`; callers `:3997`, `SqlBuilder.cs:1812`) — the visitor alias at `:5723` is source-first, so silent; patched with `:807` (D-10) — covered by E-9, E-10
- `Builder/ExpressionBuildVisitor.cs:79` alias, 45 reads (grep `[^.\w]MappingSchema[^\w(]` over the file) — not a derived alias (source-first getter); null `BuildContext` means no sequence (U-16) — deferred: P10 L-5
- `Builder/ExpressionBuilder.QueryBuilder.cs:148` — report R3/R4 (`_context` field) — covered by E-12
- `Builder/ExpressionBuilder.QueryBuilder.cs:660,682` — report R2 (`columnDescriptor` local `:659`) — covered by E-12
- `Builder/ExpressionBuilder.QueryBuilder.cs:428,539,551,558,563,571` — silent (no carrier; translation/attribute lookups) — out-of-scope
- `Builder/GroupByBuilder.cs:389` — report R3 — covered by E-25
- `Builder/GroupJoinBuilder.cs:52` — silent (R-def: `GroupJoinInnerContext` holds only `Parent` among context members, `:65-73`); fixed by hand (D-5) — covered by E-32
- `Builder/InsertOrUpdateBuilder.cs:152` — report R3 (`Builder.DataContext.MappingSchema`) — covered by E-30
- `Builder/UpsertBuilder.cs:776` — report R3 — covered by E-29
- `Builder/UpsertBuilder.cs:57` — report R5 — covered by E-29
- `Builder/EntityInsertBuilder.cs:47` — report R5 — covered by E-27
- `Builder/EntityUpdateBuilder.cs:49` — report R5 — covered by E-28
- `Builder/MergeBuilder.InsertWhenNotMatched.cs:44` — report R4 (`mergeContext` local `:21`) — covered by E-26
- `Builder/ExpressionBuilder.Expressions.cs:126` — report R4 — covered by E-11
- `Builder/ExpressionBuilder.SqlBuilder.cs:807,1313,1370,1710,1712,1758,1769,1826` — report R4 — covered by E-10
- `Builder/ExpressionBuilder.SqlBuilder.cs:328,1876` — report R2 (`ColumnDescriptor?` param) — covered by E-10
- `Builder/ExpressionBuilder.SqlBuilder.cs:702` — silent (local `m` is an `InheritanceMapping`, not a carrier; `TContext` is unconstrained); fixed by hand to `m.Discriminator.MappingSchema` — covered by E-10
- `Builder/ExpressionBuilder.SqlBuilder.cs:1040,1080` — report R1 (dead `ProcessProjection`) — covered by E-10
- `Builder/ExpressionBuilder.SqlBuilder.cs:862,863` — silent (no carrier, local function in `RemoveNullPropagation`) — out-of-scope
- `Builder/ExpressionBuilder.EagerLoadDefault.cs:142` — report R4 — covered by E-13
- `Builder/ExpressionBuilder.EagerLoadKeyedQuery.cs:365` — report R4 — covered by E-14
- `Builder/ExpressionBuilder.EagerLoadUnion.cs:646,751,1050,1256` — report R4 (`:646`: local function, outer params count, nested in a `??` right operand → not E0) — covered by E-15
- `Builder/ParametersContext.cs:278,292,325,336,340` — report R1 (`mappingSchema` param of `PrepareParameterCacheEntry` `:212`; read via derived alias `:34`) — covered by E-31
- `Builder/ParametersContext.cs:129` — silent E0 (`context?.MappingSchema ?? MappingSchema`) — out-of-scope
- `Builder/SelectBuilder.cs:71` — report R-def (`_sequence`) — covered by E-23
- `Builder/EnumerableContextDynamic.cs:26` — report R-def (`ValuesContext`) — covered by E-24
- `Builder/SelectContext.cs:42` — report R-def + R4 (`innerContext` param) — covered by E-16
- `Builder/TableBuilder.cs:83,276,283` — report R4 on master via the dead `out parentContext` (the false positive D-5 removes) — covered by E-5
- `Builder/TableBuilder.RawSqlContext.cs:77` — silent (ctor initializer, no carrier param); fixed to the root (D-4) — covered by E-6
- `Builder/TableBuilder.RawSqlContext.cs:48` — silent (local `context` declared later `:58`); fixed to the root — covered by E-6
- `Builder/SelectQueryBuilder.cs:15` — silent today (the read is inside `SelectContext` ctor #1); after E-16 the caller writes the D-4 form, E0-silent — covered by E-22
- `Builder/EnumerableContext.cs:21`, `Builder/ScalarSelectBuilder.cs:30`, `Builder/SingleExpressionContext.cs:19`, `Builder/TableBuilder.RawSqlContext.cs:20` — silent R-def (only `Parent`): true roots — out-of-scope
- `Builder/CteContext.cs:23`, `Builder/ExpressionBuildVisitor.cs:79` — silent E0 (left operand a context) — out-of-scope
- `Builder/MethodChainBuilder.cs:21,32`, `Builder/QueryExtensionBuilder.cs:19`, `Builder/TableBuilder.cs:29` — silent (static `CanBuild`, no carrier) — out-of-scope
- `Builder/MethodChainBuilder.cs:58,60,67`, `Builder/QueryExtensionBuilder.cs:66` — silent R5 via D-6 list — out-of-scope
- `Builder/Visitors/ExposeExpressionVisitor.cs:39` alias and reads `:332,403,406,418,538,698,761,847,880,977,980,1071,1143,1203,1253,1332,1339` — expected silent (no carrier; expose runs before any context exists); TO-1 confirms — deferred: expose-phase, P10 L-3
- `Builder/ExpressionTreeOptimizationContext.cs:23,28` and reads `:119,253,503,526,538,545,550,558` — not a derived alias (auto-property) — deferred: P10 L-3
- `SelectContext` ctor #1 callers `AllJoinsLinqBuilder.cs:97`, `JoinBuilder.cs:147`, `SelectManyBuilder.cs:103,126`, `DefaultIfEmptyBuilder.cs:75`, `InsertBuilder.cs:172`, `SelectQueryBuilder.cs:15`, `SelectContext.cs:209` — signature change, all call sites (grep `SelectContext\(` over `Builder/`, 24 hits, rest use ctors #2–#4) — covered by E-16 … E-22
- `GroupJoinInnerContext` ctor caller `GroupJoinBuilder.cs:37` only (same file) — covered by E-32
- `GetRootMappingSchema` callers — `TableBuilder.cs:233,269` only (grep `GetRootMappingSchema`) — covered by E-4, E-5
- `FindBuildContext` callers — `TableBuilder.cs:260` only — covered by E-5
- `GetAssociationDescriptor(Expression…)` / `AssociationToRealization` callers — `ExpressionBuildVisitor.cs:1810,1822` only (grep over `Source/`) — covered by E-8, E-9
- `PrepareParameterCacheEntry` — Localized — searched `PrepareParameterCacheEntry\(` in `Builder/ParametersContext.cs`; signature unchanged, only reads inside switch.
- `MakeAlternativeInsertOrUpdate` (`Source/LinqToDB/Internal/Linq/QueryRunner.InsertOrReplace.cs:262-296`) — uses the schema for `GetDbDataType(typeof(int))` only (critic) — covered by E-29, E-30
- `BuildersGenerator.cs` — Localized — searched `ForAttributeWithMetadataName|GetAttributes\(\)|AttributeClass` across `Source/CodeGenerators`, no attribute added, no generator-output change.
- LinqService remote path — translation client-side, AST serialized (`RemoteDataContextBase.QueryRunner.cs:194,226,261`) — covered by E-33 (`.LinqService` contexts)
- Public API / baselines — Localized — searched `ProcessProjection|GetAssociationDescriptor|SelectContext|GetRootMappingSchema|ParametersContext|GroupJoinInnerContext` across `Source/LinqToDB/PublicAPI`, no entries.
- Shipped XML docs of `UseMappingSchema` / `AddMappingSchema` — deferred: U-12 probe; an E-row via P11 if a promise is found.

## P8 Test obligations (M/L)

Analyzer fixtures (E-3) use a miniature model in namespace `LinqToDB.Internal.Linq.Builder`: `IDataContext`, `MappingSchema`, `ExpressionBuilder` (`DataContext`, `MappingSchema => DataContext.MappingSchema`), a second alias owner (`ParametersContext` shape), `IBuildContext` (`Builder`, `Parent`, `MappingSchema`), `BuildContextBase`, `ContextRefExpression`, `MethodCallBuilder.BuildMethodCall`, `EntityDescriptor`/`ColumnDescriptor`/`AssociationDescriptor` with `MappingSchema`, `Sql.ExtensionAttribute.GetExtensionAttributes`. Stub reductions: getters in both expression- and statement-bodied form; two alias owners (the minimum that distinguishes a derived set from a hardcoded one); one file. Each `control` is proven with `.claude/scripts/mutation-run.ps1`; mutations recorded in G-01.

- TO-1 census: Release build of `Source/LinqToDB` with E-1 and before any fix reports exactly the P7 `report` rows (site list compared, not a count) — providers: n/a (compile) — proof: red→green
- TO-2 census negative: that build reports none of the P7 silent / out-of-scope / deferred rows — providers: n/a — proof: characterization
- TO-3 after fixes: Release net10.0 build has 0 LINQ2DB0007 and `git grep "disable LINQ2DB0007"` is empty — providers: n/a — proof: control (mutation "revert E-7 line :150" → build red)
- TO-4 R-def reports a getter `=> Builder.MappingSchema` in a type with a `_sequence` field; silent with only `Parent` — providers: n/a — proof: control (mutation `skip the member scan` → silent fixture reports)
- TO-5 R-def reports a ctor assigning the getter's backing field from the live schema while an `innerContext` member exists — providers: n/a — proof: control (mutation `skip ctor assignments`)
- TO-6 R1 reports with a `MappingSchema` parameter, including inside a lambda in the method — providers: n/a — proof: control (mutation `ignore outer-method parameters`)
- TO-7 R2 reports with `EntityDescriptor`, `ColumnDescriptor?` and `AssociationDescriptor` parameters and with a `ColumnDescriptor` local declared before — providers: n/a — proof: control (mutation `EntityDescriptor only` → ColumnDescriptor arm silent)
- TO-8 R3 reports `ctx.Builder.MappingSchema`, implicit `Builder.MappingSchema` in a context method, `Builder.DataContext.MappingSchema`, and `builder.DataContext.MappingSchema` on an `ExpressionBuilder` parameter inside `BuildMethodCall` — providers: n/a — proof: control (mutation `match ExpressionBuilder.MappingSchema only` → DataContext arms silent)
- TO-9 live-read derivation: a read of the second alias owner's `MappingSchema` with a `MappingSchema` parameter in scope reports — providers: n/a — proof: control (mutation `hardcode ExpressionBuilder as the only alias`)
- TO-10 R4 reports with an `IBuildContext` parameter and with a `ContextRefExpression` pattern variable — providers: n/a — proof: control (mutation `IBuildContext only` → ContextRef arm silent)
- TO-11 R4 reports with an instance `IBuildContext` field in a non-static member of a context type; silent in a static member, and silent for a `ColumnDescriptor?` instance property on the alias owner (the `CurrentDescriptor` shape) — providers: n/a — proof: control (mutation `ignore static`; mutation `count instance members of any type` → alias-owner arm reports)
- TO-12 R4 reports with a context local declared before; silent when declared after in the same block; R1 silent on `var ms = builder.MappingSchema;` with no other carrier — providers: n/a — proof: control (mutation `drop declaration-position filter`; mutation `count the initializer's own local` → self-initialiser arm reports)
- TO-13 R4 silent when the context local lives in a sibling block closed before the read — providers: n/a — proof: control (mutation `scan all locals of the method`)
- TO-14 R4 reports inside a local function / lambda capturing an outer context — providers: n/a — proof: control (mutation `stop at the local function boundary`)
- TO-15 R4 silent for `Parent` and a parameter named `parent` — providers: n/a — proof: control (mutation `drop the Parent exclusion`)
- TO-16 R4 silent in a `: base(...)` initializer that has only instance carriers — providers: n/a — proof: control (mutation `ignore ctor-initializer position`)
- TO-17 R5 reports inside `BuildMethodCall` with no carrier; silent when the read is an argument to `GetExtensionAttributes` — providers: n/a — proof: control (mutation `empty the D-6 list`)
- TO-18 E0 silent for `ctx?.MappingSchema ?? builder.MappingSchema` and `ExpressionBuilder.TryGetRootMappingSchema(e) ?? builder.MappingSchema` (static); reports for `Parent?.MappingSchema ?? Builder.MappingSchema` (with another carrier present) and for `a ?? F(builder.MappingSchema)` — providers: n/a — proof: control (mutation `accept any left operand` → Parent arm silent; mutation `exempt the whole right subtree` → nested arm silent)
- TO-19 silent outside the namespace prefix, and when `ExpressionBuilder` is not in the compilation assembly — providers: n/a — proof: control (mutation `drop namespace gate`)
- TO-20 silent on an assignment to a live-schema property and on the alias getter itself (A-3: the getter has no carrier in scope; the explicit exclusion was unobservable and is deleted) — providers: n/a — proof: control (mutation `drop write filter`)
- TO-21 D-8: a model with `ExpressionBuilder` but no `IBuildContext` reports the drift diagnostic once; (A-3) so does a full model whose `ExpressionBuilder.MappingSchema` is not alias-shaped (`AliasDriftIsReported`, message asserted) — providers: n/a — proof: control (mutation `return silently on drift`; mutation `silent on alias drift`)
- TO-22 entity `Insert(item, cfg)` on a pre-scope handle; scope marks a column `HasSkipOnInsert()` (separating input: master omits the column, snapshot inserts it) — providers: all `[DataSources]` incl. `.LinqService` — proof: red→green
- TO-23 entity `Update(item, cfg)` on a pre-scope handle; scope moves the primary key to another column (master's WHERE uses the scope PK) — providers: all — proof: red→green
- TO-24 `Upsert` on a pre-scope handle with the scope PK change; separating input per path: a native-upsert provider and a Merge-lowered one — providers: all — proof: red→green
- TO-25 `Merge(...).Using(...).InsertWhenNotMatched()` default setter; scope `HasSkipOnInsert` — providers: `MergeTests` data-source set (`Tests/Linq/Update/MergeTests*.cs` attribute cited at implementation) — proof: red→green
- TO-26 inline association with `CanBeNull = false` (and no `ForceOuter` / optional root — `ExpressionBuildVisitor.cs:1857` and `AssociationHelper.cs:117` otherwise set DefaultIfEmpty before `:172`) navigated on a pre-scope parent; scope adds a child `HasQueryFilter` (master switches the join to the DefaultIfEmpty / LEFT shape, `AssociationHelper.cs:172-179`) — providers: all — proof: red→green
- TO-27 `FromSql` entity read created before a scope that renames a column (`RawSqlContext.cs:77`; the one name-level cell) — providers: all — proof: red→green
- TO-28 association declared only in the scope (fluent `Association`), navigated on a pre-scope handle (`Associations.cs:150-208`): master resolves it, snapshot does not — providers: all — proof: red→green
- TO-29 inheritance mapping declared only in the scope; association to the TPH root on a pre-scope handle (`AssociationHelper.cs:321,337,343`) — providers: all — proof: red→green
- TO-30 two-handle join where `x is Derived` is on the second handle (`tmp1.Join(tmp2, …, (a, b) => new { a, b }).Where(x => x.b is Derived)`): the visitor's `BuildContext` is the join context (outer handle's snapshot after E-17/E-18) while `tableContext` is the second table — the shape that separates `:5723`'s D-7 pick (a single-handle `Where` is already snapshot on master via `:79`). Handles under different snapshots, override shape (U-17) on the discriminator conversion. Precondition for `:5723` to run: `left.Type != code.GetType()` (`:5722`; codes kept as declared, `EntityDescriptor.cs:479`) — e.g. `Code = 1` on a `string` discriminator column with `SetConvertExpression<int, string>` A/B. Project a scalar (`x.b.Id` / `Count()`), not `x.b`, so the reader's own discriminator check cannot decide the cell — providers: all — proof: red→green
- TO-38 D-9 picks: a two-handle join navigating an association declared only on the second handle's snapshot, built where the **live** schema lacks it (the query is built after the scope that gave `tmp2` its snapshot has closed). Master: `TableContext.cs:283` (snapshot) says association, `:1581` (live) says no → `HandleMember` fails; fix: `:1581` reads `tmp2`'s snapshot → `HandleAssociation :1641` → `TryCreateAssociation :1810` with `rootContext` = `tmp2`. Two arms: property form `x.b.Assoc` (via `HandleRoot :1682-1712` → `:1581`) and method form `x.b.AssocMethod()` (→ `:870`, P10 L-8) — providers: all — proof: red→green
- TO-31 member alias (`IsAlias`) declared only in the scope, used in a pre-scope handle's projection (`Expressions.cs:126`) — providers: all — proof: red→green
- TO-32 CTE-union eager load (`EagerLoadUnion`) of a computed detail column (`d.Id + 1`, `descriptor == null` → `ExpressionBuilder.EagerLoadUnion.cs:646` → `QueryHelper.GetDbDataType`, `QueryHelper.cs:823-826`) beside a parent-side column of the same nullable CLR type (`p.Id`, wrapped to `int?` at `:676-677`), override shape (U-17) on `SetDataType` for the CLR type, detail handle under a different snapshot. The observable is the carrier slot layout (`AllocateSlot :612`, `:667-681`), not rows: assert the generated SQL / carrier column count (master allocates an extra slot, the fix shares it) — U-18 — providers: all — proof: red→green
- TO-32b the `AdjustType` sites `EagerLoadDefault.cs:142`, `EagerLoadKeyedQuery.cs:365`, `EagerLoadUnion.cs:751,1050,1256` — no separating input: the eager-load producer's type is `IQueryable<T>` (`ExpressionBuildVisitor.cs:3245`) and `AdjustType` skips `IQueryable<>` (`ExpressionBuilder.Associations.cs:253`), so the converter is never consulted; fixed for consistency (P10 L-7) — providers: SQLite.MS — proof: characterization
- TO-33 `SetDefaultValue` for a member type, override shape (U-17: A on the base schema, B in the scope); LEFT JOIN with a missing row, projected through a `SelectContext` body that holds the `SqlDefaultIfEmptyExpression` (`select new { p, c }` then `.Select(x => x.c.Int)`, reaching `Project :1305-1313`) — a plain `select c.Int` goes through `ExpressionBuildVisitor.cs:2000-2019`, already snapshot on master — providers: all — proof: red→green
- TO-34 scalar-type registration, override shape (U-17: base schema registers the class as non-scalar, the scope as scalar), for a class used as a GroupBy key on a pre-scope handle (`GroupByBuilder.cs:389`) and as a `FromSql` element (`RawSqlContext.cs:48`) — providers: all — proof: red→green
- TO-35 discriminator-value conversion, override shape (U-17), two arms: `OfType<Derived>()` on a pre-scope handle with an **enum** discriminator (no `MapValue`) and a `SetConvertExpression<E, int>` registration A/B — a converter registration, not attributes, which are unioned under `CombineSchemas` (`ConvertBuilder.cs:646-672`) (→ `SqlBuilder.cs:702` `GetSqlValue` → `MappingExtensions.cs:44-50` → `Converter.ChangeType`, which converts only enum values without `Sql.EnumAttribute` / `ValueToSqlConverter` support, `MappingExtensions.GetSqlValue :37-61`); and a `TypeAs` projection `x as Derived` with a code/column type mismatch (→ `SqlBuilder.cs:807` via `:1806-1812`) — providers: all — proof: red→green
- TO-36 parameter conversion, override shape (U-17), one arm per read: a descriptor-less server-side value of type `T` (`Sql.AsSql(captured)` / `Sql.Parameter(captured)` — a bare projection constant is client-evaluated and never reaches `BuildParameter`) with base/scope `SetConvertExpression<T, DataParameter>` (→ `ParametersContext.cs:325,336,340`); a captured value compared to a column whose `MemberType` differs non-nullably from the value type, with base/scope converter override (→ `:278,:292`). Arm 2 needs the column descriptor to survive the compiler's widening `Convert(t.Id, long)` — probed first (U-19). Direction: master builds the parameter with the scope's conversion, the fix with the snapshot's; an arm found unreachable is reclassified via P11 — providers: all — proof: red→green
- TO-37 symmetry guard on the unchanged path: existing `UseMappingSchemaTests.Test1/Test2` and the full `Tests/Linq` on SQLite.MS stay green; baselines unchanged — providers: SQLite.MS full run + CI — proof: characterization
- TO-39 (A-3) entity `Update` on a handle created before `CreateTempTable(…, setTable)` that moves the key, run while the temp table lives (`EntityUpdateFollowsHandleSchemaUnderTempTable`) — providers: `[DataSources(false)]` (the IEnumerable overload bulk-copies, unsupported remote) — proof: red→green
- TO-40 (A-3) `FromSql` arguments convert under the handle's schema (`FromSqlArgumentFollowsHandleSchema`, `SimpleSelectContext` at `RawSqlContext.cs:60`) — providers: SQLite / SqlServer / DuckDB + `.LinqService` — proof: red→green
- TO-41 (A-3) A-1 narrowed: a root's own `MappingSchema` (`=> Builder.MappingSchema`, expression- or statement-bodied) is no carrier, any other context's is (`OwnSchemaIsASourceUnlessRoot`; TO-15 now uses a root getter) — providers: n/a — proof: control (mutations `exclude own schema everywhere`, `never root`, `expression-bodied root only`)
- TO-42 (A-3) a `foreach` variable is a carrier in its body, not in its collection expression (`ForEachVariablePosition`) — providers: n/a — proof: control (mutation `foreach declaring node span`)

## P9 Verification gates

- G-01: pass — CI on `c8f159f1d` (2026-10-25): Azure `test-all` [24705](https://dev.azure.com/linq2db/0dcc414b-ea54-451e-a54f-d63f05367c4b/_build/results?buildId=24705) succeeded, GH run [40194406299](https://github.com/linq2db/linq2db/actions/runs/40194406299) all legs green, Release `build` / `Build and pack` green; `ci-test-verdicts.ps1` over the GH legs: 0 failure / host-failure / signature-mismatch / gate-too-wide / gate-collision, `DerivedAssociationFollowsHandleSchema` gate-holds on all 10 gated configs (Access Ace/Jet × Odbc/OleDb, YDB — #6148, each + `.LinqService`). Earlier local results below (uncommitted tree on 602484aca, 2026-10-24):
  - TO-1: pass — Release build of `Source/LinqToDB` with E-1 before any fix reported exactly the 53 P7 `report` sites, 0 other errors (`.build/.agents/5951-census.ps1` over the build log).
  - TO-2: pass — same build, none of the silent / out-of-scope / deferred rows reported.
  - TO-3: pass — after the fixes, `dotnet build Source/LinqToDB/LinqToDB.csproj -c Release -f net10.0` exit 0, 0 × LINQ2DB0007; `git grep "disable LINQ2DB0007"` empty. Control: the TO-1 build is the unfixed tree reporting `AssociationHelper.cs:150` (mutation "revert E-7 line :150" equivalent, measured).
  - TO-4…TO-21: pass — `BuildContextMappingSchemaAnalyzerTests` 23/23 green; `mutation-run.ps1` (`.build/.agents/5951-mutations.json`, `5951-mutations-ctor.json`), restored byte-exact, every mutation caught by its named fixture: mutation `skip the member scan` (Getter…, StatementBodiedGetter…, CtorAssigning…WithSourceMember), mutation `skip ctor assignments` (CtorAssigning…), mutation `ignore outer-method parameters` (SchemaParameterInScope, CapturedContext — also TO-14's mutation `stop at the local function boundary`), mutation `drop parameters from lookup` (TO-9), mutation `EntityDescriptor only`, mutation `match ExpressionBuilder.MappingSchema only`, mutation `hardcode ExpressionBuilder as the only alias`, mutation `IBuildContext only`, mutation `ignore static`, mutation `count instance members of any type`, mutation `drop declaration-position filter`, mutation `count the initializer's own local`, mutation `drop the Parent exclusion` (parameter and property, two runs), mutation `ignore ctor-initializer position`, mutation `empty the D-6 list`, mutation `accept any left operand`, mutation `exempt the whole right subtree`, mutation `drop namespace gate`, mutation `drop write filter`, mutation `return silently on drift`. TO-13's mutation `scan all locals of the method` not run: the block scoping is `LookupSymbols`' own, not an analyzer branch — TO-13 is characterization.
  - TO-22…TO-38: per P11 A-2 — 11 cells red→green measured (red with the `Source/LinqToDB` changes stashed), TO-31 characterization, TO-26 / TO-33 / TO-35b dropped with measurements, TO-32 / TO-34 / TO-36 arm 1 / TO-38 method arm not written. Final run `UseMappingSchemaTests` 56/56 on SQLite.MS, DuckDB + `.LinqService`.
  - A-3 (2026-10-25, uncommitted tree on `1cb5e6038`): `BuildContextMappingSchemaAnalyzerTests` 26/26; `mutation-run.ps1` over the updated `5951-mutations.json` (25 mutations, anchors moved with the edits, plus `exclude own schema everywhere`, `never root`, `expression-bodied root only`, `foreach declaring node span`, `silent on alias drift`) and `5951-mutations-ctor.json` — all 26 caught, restored byte-exact. TO-1/TO-3 re-run: Release net10.0 `Source/LinqToDB` 0 × LINQ2DB0007 with A-1 narrowed (no new sites), no pragma; Release `Tests.Analyzers.Internal` and `-f netstandard2.0` exit 0. TO-39 / TO-40 / TO-35b / TO-36 arm 1 red on master builder code (and TO-40 red on the pre-fix HEAD), green after. `UseMappingSchemaTests` + `CreateDatabase`: 70/70 on SQLite.MS, DuckDB, each direct + `.LinqService`; with the `FromSql` / `SelectMany` suites 257/257 on SQLite.MS.
  - Access / SqlCe / server providers: pass — CI 24705 + 40194406299 (above).
  - TO-37: pass — CI full run 24705 + 40194406299 (above).
- G-01b: skipped — `/profile-analyzers rules` not run; LINQ2DB0007's build cost is unmeasured.
- G-02: pass — baselines PR [linq2db.baselines#2214](https://github.com/linq2db/linq2db.baselines/pull/2214): 969 files, all `added`, all under `Tests/Mapping/UseMappingSchemaTests/`; 0 existing baselines modified or removed (SC-6).
- G-03: n/a — every touched type is internal (P3); no new public surface.
- G-04: n/a — no public surface change, so no API baseline refresh.
- G-05: pass — `dotnet build Source/LinqToDB/LinqToDB.csproj -c Release -f netstandard2.0` exit 0; `-f net10.0` exit 0 (TO-3); `dotnet build Tests/Tests.Analyzers.Internal/Tests.Analyzers.Internal.csproj -c Release` exit 0.
- G-06: pass — `git diff --stat` identical with `--ignore-space-at-eol`; a stripped trailing-whitespace hunk in `GroupJoinBuilder.cs` was restored.
- G-07: pass — no `Tests/Tests.Playground` changes.
- G-08: pass — the builder change rests on the A-2 red→green cells; the unseparated sites are listed in P10 L-9.
- G-09: pass — adversarial diff read + critic delta walked 2026-10-25, 13 dispositions applied (P11 A-3, `walk.md`).

## P10 Adjudicated (M/L)

- L-1 Class-C lookups (extension / query-extension / table-function attributes, `SkipMethodChain`, member translation) stay live (D-6). Reason: no source exists at those sites before the sequence is built, and master behaviour is kept while the issue's open question is undecided; U-8 is reasoned only.
- L-2 The analyzer cannot see a source reachable only through an unbuilt `Expression` outside `BuildMethodCall` (D-1 failure mode); `ExpressionBuilder.Associations.cs:51,85,150,154` and `ExpressionBuilder.SqlBuilder.cs:702` are such sites, fixed by hand and guarded by TO-28 / TO-30.
- L-3 Expose-phase and optimization-context reads (`Builder/Visitors/ExposeExpressionVisitor.cs`, `Builder/ExpressionTreeOptimizationContext.cs`) are out of scope: they run before any build context exists and are member-translation / evaluation checks (class C); `ExposeExpressionVisitor.cs:847` is where a live root is minted for a dc reference by design. The optimization context's auto-property alias is not derived by D-1.
- L-4 Reader-side type conversion is resolved at execution from the runtime context (`ConvertFromDataReaderExpression.cs:63,77,82`); a scope `SetConverter` applies to a pre-scope handle's reads before and after this PR, and a column `ValueConverter` comes from the snapshot's `ColumnDescriptor` before and after (`ExpressionBuilder.QueryBuilder.cs:677-678`, critic). Not changed here — except the build-time `FromDatabase` fallback at `ExpressionBuilder.QueryBuilder.cs:682`, which E-12 moves to `columnDescriptor?.MappingSchema ?? MappingSchema`; expected inert for plain columns (`sqlType.SystemType == MemberType`, `:660-662`), not separately tested.
- L-5 `ExpressionBuildVisitor.MappingSchema` (`:79`) is the issue's documented source-first fallback; where `BuildContext` is null the visitor is not inside a sequence (U-16), so the live fallback has no source to prefer. Not covered by D-1 and not changed, except the `:5723` twin site (D-10).
- L-7 The eager-load `AdjustType` reads (`EagerLoadDefault.cs:142`, `EagerLoadKeyedQuery.cs:365`, `EagerLoadUnion.cs:751,1050,1256`) are switched for consistency with no separating input (TO-32b): the producer's type is `IQueryable<T>` and `AdjustType` skips it. After E-5, `TableBuilder.cs:276,283` sit in `ISequenceBuilder.BuildSequence` with no carrier, so their D-4 form is not analyzer-guarded (within L-2).
- L-8 `ExpressionBuildVisitor.cs:870` runs `IsAssociation` before `BuildAssociationRoot` (`:876,:884`), so for a member-chain receiver (`x.b.AssocMethod()`) the receiver is not yet a `ContextRefExpression` and detection on the first pass uses the visitor alias (the join context's schema); the re-visit at `:879,:889` uses the right one only if the first pass said yes. Accepted as D-9's documented fallback; TO-38's method-form arm measures it, and if it is red after the fix the remedy (resolve the receiver's root before detection) becomes a P11 amendment.
- L-9 (A-2, A-3) Sites fixed for consistency with no separating test: `ExpressionBuilder.SqlBuilder.cs:328`, `:1876`, the `Project` `DefaultValueExpression` sites, `ExpressionBuilder.QueryBuilder.cs:148,660,682`, the eager-load reads (L-7, `EagerLoadUnion.cs:646`), `TableBuilder.RawSqlContext.cs:48`, `TableBuilder.cs:276,283`, `GroupByBuilder.cs:389` (A-3: a contrived GroupBy-key cell is green on master), `SelectManyBuilder.cs:126` (A-3: a no-result-selector cell over a second handle is green on master), `AssociationHelper.cs:174,274`, `ExpressionBuilder.Associations.cs:37`, `UpsertBuilder.cs:776`, `InsertOrUpdateBuilder.cs:152`, `LoadWithBuilder.cs:252`, `TableLikeQueryContext.cs:218`, `ExpressionBuildVisitor.cs:870` (L-8), `ExpressionBuilder.Expressions.cs:126`, `SelectBuilder.cs:71`, `EnumerableContextDynamic.cs:26`, `GroupJoinBuilder.cs:52`, the `SelectContext` ctor #1 callers. (A-3 took `ExpressionBuilder.SqlBuilder.cs:807` off the list — TO-35b, reference member — and `ParametersContext.cs:325,336,340` — TO-36 arm 1.) Each substitutes the source's schema for the live one, which is the same instance outside a schema swap; CI's full run is their regression guard.
- L-6 The `MakeIsPredicateExpression` twin (`ExpressionBuildVisitor.cs:5663` / `ExpressionBuilder.SqlBuilder.cs:746`) stays duplicated (D-10); both copies get the same fix here.

## P11 Amendments (M/L)

- A-1 (2026-10-24, found writing TO-15) — D-1's instance-member carrier clause excludes the context's own `MappingSchema` property, as well as `Parent`. Every context has one, so counting it would put a carrier in scope of every member of every context, roots included, and the `Parent` exclusion could never be observed; whether a context's own schema is right is what R-def judges. No edit-point added.
  re-derives: P5 (D-1 carrier clause), P8 (TO-15 comment), P7 (no row changes: no census row relied on the own property — context-method reads are R3 or R-def)
- A-2 (2026-10-24, red-first runs on SQLite.MS + DuckDB, direct + LinqService; red measured with the `Source/LinqToDB` changes stashed) — obligations re-derived from measurement. Arrangement: the facet cells create the handle **inside** a scope that adds the facet and query **after** it (snapshot ⊃ live, so the fixed path is the one that works); the DML / FromSql cells keep the pre-scope shape. All in `Tests/Linq/Mapping/UseMappingSchemaTests.cs`.
  - red→green: TO-22 `EntityInsertFollowsHandleSchema`, TO-23 `EntityUpdateFollowsHandleSchema`, TO-24 `UpsertFollowsHandleSchema`, TO-25 `MergeDefaultInsertFollowsHandleSchema` (DuckDB only: `MergeDataContextSource` excludes SQLite), TO-27 `FromSqlFollowsHandleSchema`, TO-28 `AssociationFollowsHandleSchema`, TO-38 `AssociationOnSecondHandleFollowsItsSchema` (property form only), TO-29 `DerivedAssociationFollowsHandleSchema` (TPH declared only in the scope — the converter shape was wrong: the discriminator comparison converts the column with `int.Parse`), TO-30 `TypeTestOnSecondHandleFollowsItsSchema`, TO-35a `OfTypeFollowsHandleSchema` (enum discriminator, `SetConvertExpression<ShapeKind, int>`), TO-36 arm 2 `ParameterConversionFollowsHandleSchema`.
  - characterization (green on master too): TO-31 `AliasFollowsHandleSchema`.
  - dropped, measured non-separating: TO-26 (1 row on both arms; `AssociationHelper.cs:172-179` not reached by `Child.Parent1` + a target filter, mechanism not identified); TO-33 (the missing row's member is read as NULL and defaulted by the reader at execution, P10 L-4 — 0 on both arms).
  - dropped, blocked by an unrelated defect: TO-35b — `Select(s => s as Derived).Select(c => c.Id)` over a TPH table throws `ArgumentException: Argument types do not match` on master as well; a separate-issue candidate. `ExpressionBuilder.SqlBuilder.cs:807` has no separating test.
  - not written yet: TO-36 arm 1 (descriptor-less parameter), TO-32 (separates by CTE slot layout only), TO-34 (a snapshot-scalar `FromSql` reads through the runtime schema's converters, L-4), TO-38 method-form arm (P10 L-8 unmeasured).
  - TO-37 breadth: the full `Tests/Linq` run is CI's (local runs are filtered by standing rule) — G-01 `blocked — CI`.
  re-derives: P8 (TO-22…TO-38 as above), P9 (G-01), P10 (L-9)
- A-3 (2026-10-25, G-09 pre-PR walk + critic delta on A-1/A-2; 13 dispositions, `walk.md` in this folder) — supersedes A-2 where they differ.
  - engine fixed here, red-first: `FromSql` arguments translated in `SimpleSelectContext` under the live schema while the entity used the snapshot — the context now takes the source's schema (TO-40); `SelectManyBuilder.cs:126` without a result selector carries the collection's schema (fixed; its cell is green on master → L-9).
  - written red→green (were dropped / not written in A-2): TO-35b with a reference member (`Select(s => s as ShapeCircle).Select(c => (string?)c!.Kind)`), TO-36 arm 1 (`Sql.AsSql(token)`, base: read-back + `Token → DataParameter` A, scope: B), TO-39 `CreateTempTable(…, setTable)` (P3 delta). `ParameterConversionFollowsHandleSchema` moved to the shared `Parent`.
  - written, green on master, removed: TO-34 GroupBy-key arm (`GroupBy(c => c).Select(g => g.Key.Parent.Value1)` with `Child` scalar in the scope only), the `SelectMany` cell above → L-9.
  - analyzer: A-1 narrowed — a context's own `MappingSchema` is excluded as a carrier only when its getter is root-shaped (`=> <ExpressionBuilder member>.MappingSchema`), TO-41; `foreach` variables positioned by name, the initializer-containment check kept for `VariableDeclaratorSyntax` only, TO-42; the unobservable alias-getter exclusion in `IsLiveRead` deleted (TO-20); a fixture for the second drift branch (TO-21); R5's message names the static `ExpressionBuilder.TryGetRootMappingSchema`.
  - deviation from D-4, kept on purpose: two root helpers. `TableBuilder.GetRootMappingSchema` evaluates an `IDataContext`-typed expression and throws when none is found — a table source always has one; `ExpressionBuilder.TryGetRootMappingSchema` walks a method-call chain without evaluating and returns null for the live fallback. One helper would add evaluation to every Try caller or drop the table path's dc arm.
  - TO-26 mechanism (traced): a non-list association always gets a non-null `isOptional` (`ExpressionBuildVisitor.cs:1858-1861`), passed as `enforceDefault`. `true` already sets the flag (`AssociationHelper.cs:117`) and `false` resets it after the block (`:367-370`), so `:177`'s DefaultIfEmpty promotion never takes effect. `:178`'s cache check still does (`:229`). The dead promotion is a separate-issue draft, as is `ExpressionBuilder.SqlBuilder.cs:1655` (`Expression.Constant(null, truePath.Type)` throws for a value-type member under `TypeAs`, independent of schemas).
  - re-derived: P2 — SC-4's GroupBy / SelectMany cells and SC-5's default-value cell (TO-33) have no separating input (L-9, A-2); P3 — the mixed-defaults bullet is dropped (TO-33 measured 0 on both arms), the visitor-alias and `setTable` deltas added; P9 — TO-24's emulated (Merge-lowered) arm is unmeasured locally, TO-13 is characterization (P8), and the `UseMappingSchemaTests` case count is stated with the contexts it ran on (G-01).
  re-derives: P3, P8 (TO-15, TO-18, TO-20, TO-21, TO-39…TO-42), P9 (G-01, G-09), P10 (L-9)

## P12 Critic verdict (M/L)

### Round 1 — refuted (fable, on 602484aca; plan pre-revision)

Note: fable also contributed the trigger design before authoring (session design consult), so this critic is not independent of that part of the design.

Objections, all verified against the code before revising:
- E-22 wrote a bare `builder.MappingSchema` inside a `BuildMethodCall` (`SelectQueryBuilder.cs:13`), contradicting R5 and SC-2; and `DataExtensions.cs:1613` embeds a root there. → Changed: E-22 uses D-4; D-4 lists it.
- U-10's red mechanism (column rename) was wrong for 9 of 11 SC-4 cells; the live reads consume non-name facets (`AssociationHelper.cs:150-152,174,321,337`; no `ColumnName` in the entity builders). → Changed: SC-4 rewritten per facet; TO-22…TO-32 name the facet; U-10 reworded; U-15 added.
- SC-5 / TO-32 (value converter in projection) was unmeetable: reader conversion is runtime (`ConvertFromDataReaderExpression.cs:63,77,82`). → Changed: SC-5 reworded to default value / scalar type / discriminator conversion / parameter conversion; TO-33…TO-36; P10 L-4.
- Live alias `ParametersContext.MappingSchema` (`:34`) with reads `:278-340` inside a method that has `mappingSchema` was invisible. → Changed: D-1 derives the alias set; E-31; P7 rows; TO-9; P10 L-3 for Expose / optimization context.
- R2 ignored `ColumnDescriptor` / `AssociationDescriptor` carriers (`SqlBuilder.cs:328,702,1876`, `QueryBuilder.cs:660,682`). → Changed: R2 widened; E-10, E-12 widened; TO-7.
- E-19 `:103` violated D-7 (value from `collection`). → Changed: E-19, D-5, D-7.
- E0 accepted any left operand; `GroupJoinBuilder.cs:52` falls back from `Parent`. → Changed: E0 restricted; E-32; TO-18.
- TO-29 (LoadWith) could not separate D-7. → Changed: TO-32 sub-query projection over a second handle.
- `builder.DataContext.MappingSchema` receiver omitted; analyzer XML docs convention. → Changed: D-1 receiver chain; TO-8; D-1 chosen line.

### Round 2 — refuted (fable, on the round-1 revision; 602484aca)

Round-1 objections answered (critic confirmed: facet reclassification real, `ParametersContext` census complete, derived alias set works). New objections — verified: the first three against code this session; the rest unverified:
- D-1's instance-member carrier clause fires on every non-static `ExpressionBuilder` member via `ExpressionBuilder.Expressions.cs:15` `ColumnDescriptor? CurrentDescriptor` (verified), so P7's silent rows (incl. class-C lookups `QueryBuilder.cs:428-571`) would report; TO-1/TO-2/SC-2 unmeetable as written. Fix: instance-member carriers only on `IBuildContext` types.
- `IsAssociation(Expression, out)` has four more callers reaching the live reads (`ExpressionBuildVisitor.cs:870,1581`, `LoadWithBuilder.cs:252`, `TableLikeQueryContext.cs:218`, verified); E-8's "sole caller" is false.
- `ExpressionBuildVisitor.MappingSchema` (`:79`, E0-shaped) is read 45× (verified count), some D-3 facets, with `BuildContext` null at guarded sites; not covered by D-1.
- `GroupJoinBuilder.cs:52` is silent under R-def as written (only `Parent`).
- self-initialiser `var ms = builder.MappingSchema;` would report on itself.
- TO-26 green unless `CanBeNull = false`; TO-30 cannot separate (codes already from snapshot) and the `is` path goes through the twin `ExpressionBuildVisitor.cs:5663-5723`; TO-32 and TO-36 name no reachable facet.
- P3 misses the mixed-default delta (`DefaultValueExpression` snapshot vs runtime NULL-read default); L-4 overstated for `QueryBuilder.cs:682`; E-11 should prefer the member's own `ContextRefExpression`.

Revision cap reached (one round): stopped for user direction. User answered "a" (2026-10-24): apply every repair and run one more critic round.

Changed in response: D-1 carrier clause (instance members only on `IBuildContext` types; self-initialiser excluded); D-9 (all `IsAssociation` callers, E-34, E-35); D-10 (patch both `MakeIsPredicateExpression` copies, E-9 `:5723`); E-11 member's own `ContextRefExpression`; P7 rows for `GroupJoinBuilder.cs:52` (silent, fixed by hand), the `IsAssociation` callers, the twin, the visitor alias; U-16 / P10 L-5 (visitor alias), U-17 (override shape for type-level cells); TO-11, TO-12 new arms; TO-26 `CanBeNull = false`; TO-30 → the `is` twin path; TO-32 custom-collection converter facet; TO-33/34/35/36 override shape and per-read shapes; P3 mixed-default delta; P10 L-4 qualified for `:682`, L-6 twin.

### Round 3 — refuted (fable, on the round-2 revision; 602484aca)

Critic: "the analyzer rule as now written re-derives P7 correctly at every site I checked except one, and U-17's override shape is verified end to end — the design is sound; only obligations and three D-7 picks need re-targeting." Round-2 objections answered. New objections (the D-9 and `:154` ones verified this session; the rest reasoned by the critic from code, unrun):
- TO-30 single-handle `is` cannot go red (`:5723`'s alias is already the sequence's snapshot). → Changed: TO-30 two-handle join on the second handle.
- D-9 picks at `:1810,:1822,:1581,:870` used the visitor alias, disagreeing with `rootContext` (`:1808`, verified) used by the query (`:1878`). → Changed: D-9 / E-9 use the member's own source; TO-38 added.
- `Associations.cs:154` reports R2 under the written rule (local `:150`, verified). → Changed: P7 row.
- lead: TO-32 did not reach the live `AdjustType` with a custom type (`IQueryable<T>` producer, `:253` skip). → Changed: TO-32 re-targeted at `EagerLoadUnion.cs:646` `SetDataType`; TO-32b characterization + P10 L-7 for the `AdjustType` sites.
- lead: TO-33 route. → Changed: through a `SelectContext` body.
- TO-35 arm 1 facet. → Changed: enum discriminator.
- minor: D-10 wording; `TableBuilder.cs:276,283` unguarded after E-5. → Changed: D-10, P10 L-7.

### Round 4 — weak (fable, on the round-3 revision; 602484aca)

Every round-3 objection answered in the blocks; the D-9 picks change no P7 row; `:1581` pick sound by construction (`HandleRoot :1682-1712` rewrites the receiver before the read). Objections, carried visibly (all reasoned by the critic from code, unrun):
- `:870` first-pass detection still falls back to the visitor alias for a member-chain receiver. → Recorded P10 L-8; method-form arm added to TO-38; remedy reserved for P11 if that arm stays red.
- TO-38 misstated master (live reads) and left the build position open. → Changed: TO-38.
- TO-32 separates by SQL shape only and needs a parent-side same-type column. → Changed: TO-32 asserts slot layout; U-18.
- TO-30 needs `left.Type != code.GetType()` and a scalar projection; TO-35 arm 1 needs a converter registration; TO-36 arm 1 needs `Sql.AsSql`, arm 2 is undecidable without a run. → Changed: TO-30, TO-35, TO-36; U-19.
- Nits: D-10 line cite; `Project :1313` pick is right because it is entered from the DefaultIfEmpty `SelectContext` (E-20 → inner handle). → Changed: D-10 cite; the E-10 pick note goes in the commit body.

Residual risk carried to implementation: the TO routes in TO-30/32/33/35/36/38 are reasoned, not run; each is a red-first run, and a cell found green on master is reclassified via P11 with its reason (U-10).
