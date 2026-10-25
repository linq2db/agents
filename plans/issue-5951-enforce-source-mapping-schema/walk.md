# #5951 pre-PR walk (G-09 review + critic delta), dispositions 2026-10-25

1. MIN001 FromSql args translate in SimpleSelectContext (live) while entity uses snapshot (RawSqlContext.cs:60, :20) -> FIX HERE, red test first (FromSql created in scope with SetConvertExpression<ShapeKind,int>, WHERE Kind = {ShapeKind.Circle}, run after scope); SimpleSelectContext takes MappingSchema ctor arg.
2. MIN002 SelectManyBuilder.cs:126 uses sequence.MappingSchema when resultSelector == null (value is collection's) -> FIX HERE + attempt red test (SelectMany over second handle whose snapshot alone maps an extra column); else L-9.
3. MIN003 analyzer: no fixture for second drift branch (ExpressionBuilder.MappingSchema not alias-shaped) + alias-getter exclusion in IsLiveRead unobservable -> ADD drift fixture, DELETE exclusion.
4. SUG001 foreach iteration variable never a carrier (DeclaredBefore span) -> FIX: identifier location; containment check only for VariableDeclaratorSyntax; foreach ColumnDescriptor fixture.
5. SUG002 two root helpers (TableBuilder.GetRootMappingSchema vs ExpressionBuilder.TryGetRootMappingSchema) -> KEEP BOTH, record deviation from D-4 in P11 with reason.
6. NIT001 R5 message suggests builder.TryGetRootMappingSchema (static -> CS0176); model instance -> FIX message to ExpressionBuilder.TryGetRootMappingSchema(...), model static.
7. NIT002 ParameterConversionFollowsHandleSchema uses CreateLocalTable -> SWITCH to shared Parent (ParentID == 1L -> [2]); comment on hand-written expected in both association tests.
8. Obs1 CreateTempTable(..., setTable) is a hidden schema swap (DataExtensions.TempTable.cs:1158-1171, TempTable.cs:850-853) -> VERIFY, P3 delta + PR body, red test (handle before setTable temp table, entity Update while alive).
9. TO-35b writable with a reference member (Select(s => s as ShapeCircle).Select(c => c!.Kind)) -> WRITE red-first; if separates, take SqlBuilder.cs:807 off L-9.
10. TO-36 arm 1 writable (Sql.AsSql(captured) of non-scalar T, override arrangement: base has read-back + T->DataParameter A, scope overrides B) -> WRITE red-first; if separates, take ParametersContext.cs:325/336/340 off L-9.
11. A-1 exclusion too wide (own MappingSchema excluded for every context; fixture pins non-root as silent) -> NARROW: exclude only root-shaped own getter; fixtures root silent / non-root reports; mutation.
12. TO-34 GroupBy arm (GroupByBuilder.cs:389) -> WRITE contrived cell red-first (GroupBy(x => x).Select(g => g.Key.Assoc.Member), key type scalar in one schema only).
13. AssociationHelper.cs:172-180 dead since ExpressionBuildVisitor.cs:1858-1861 (required association + target filter stays INNER) -> VERIFY trace, DRAFT separate issue for approval, alongside SqlBuilder.cs:1655 value-type TypeAs issue.

Record-keeping (no decision): TO-26 mechanism; A-2 re-derives P2 (SC-4/SC-5 cells dropped) + P3 (drop/re-measure mixed-default bullet; add visitor-alias facet class moved by SelectContext ctor change); complete L-9 (AssociationHelper.cs:174,:274, Associations.cs:37, EagerLoadUnion.cs:646, QueryBuilder.cs:148, UpsertBuilder.cs:776, InsertOrUpdateBuilder.cs:152, TableBuilder.cs:276,283, LoadWithBuilder.cs:252, TableLikeQueryContext.cs:218, ExpressionBuildVisitor.cs:870); P9: TO-24 emulated arm unmeasured, TO-13 characterization in P8, case count 54 with contexts named.

After: commit, push, PR title/body for user confirmation, /azp run test-all.

## Progress (2026-10-25)

Done:
- Item 8 verified (DataExtensions.TempTable.cs:1158-1172 SetMappingSchema; TempTable.cs:853/868 restore).
- Item 13 TypeAs part verified: SqlBuilder.cs:1655 `Expression.Constant(null, truePath.Type)` throws for a value-type member; Playground probe (string codes, no scope) throws on the branch; master engine run threw too. AssociationHelper :172-180 trace NOT yet verified by me.
- Tests written (uncommitted) in Tests/Linq/Mapping/UseMappingSchemaTests.cs: FromSqlArgumentFollowsHandleSchema (1), SelectManyFollowsCollectionSchema (2), EntityUpdateFollowsHandleSchemaUnderTempTable (8), TypeAsFollowsHandleSchema ref member (9), UnboundParameterFollowsHandleSchema (10), GroupKeyAssociationFollowsHandleSchema (12); ParameterConversion switched to Parent + comments on both association tests (7).
- Red vs master builder code (checkout origin/master -- Builder, then restored from HEAD; tree verified): RED = items 1, 7, 8, 9, 10. GREEN on master = SelectManyFollowsCollectionSchema (2), GroupKeyAssociationFollowsHandleSchema (12) -> do not separate: remove both tests, record in A-2/L-9 (SelectManyBuilder.cs:126, GroupByBuilder.cs:389).

Next:
1. Remove tests for items 2 and 12. Run new tests on HEAD: expect 1 red (FromSql arg, fix not applied), 7/8/9/10 green.
2. Fix item 1 (SimpleSelectContext MappingSchema ctor arg from BuildRawSqlTable) and item 2 (SelectManyBuilder.cs:126 collection.MappingSchema when resultSelector == null). Re-run all UseMappingSchemaTests green.
3. Analyzer: items 3 (drift fixture for non-alias ExpressionBuilder.MappingSchema; delete IsLiveRead alias-getter exclusion), 4 (foreach carrier via local.Locations[0]; containment only for VariableDeclaratorSyntax; fixture), 6 (R5 message ExpressionBuilder.TryGetRootMappingSchema; model method static), 11 (own MappingSchema excluded only when its getter is root-shaped; fixtures root silent / non-root reports; mutation). Run analyzer tests + mutation-run (.build/.agents/5951-mutations.json + new mutation); Release build of Source/LinqToDB (must stay 0 LINQ2DB0007).
4. Plan: P11 A-3 (walk dispositions, item 5 deviation from D-4), record-keeping list above, A-2 updates (TO-35b/TO-36a written, items 2/12 non-separating), P9 refresh. Commit corpus.
5. Commit linq2db (engine follow-up; analyzer follow-up). Verify item 13 AssociationHelper trace; draft two issues (SqlBuilder:1655 TypeAs value-type; AssociationHelper :172-180 dead filter promotion) for user approval.
6. Push, show PR title/body for confirmation (draft, milestone 6.6.0, Fixes #5951, P3 deltas incl. setTable temp tables), then /azp run test-all; re-request Copilot only if quota allows.
