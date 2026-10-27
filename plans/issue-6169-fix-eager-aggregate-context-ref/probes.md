# issue-6169 — probes (work halted, handed over to #5901)

Not a work plan: no plan was authored. Work on [#6169](https://github.com/linq2db/linq2db/issues/6169) stopped on 2026-10-26 and the issue was assigned to sdanyliv as part of [#5901](https://github.com/linq2db/linq2db/pull/5901), which changes the same `HandleSubquery` fallback for a failed `AggregateExecute`. Findings posted there: https://github.com/linq2db/linq2db/pull/5901#issuecomment-6427611650. The local worktree `C:\Worktrees\linq2db\6169-eager-aggregate-context-ref` (branch `issue/6169-fix-eager-aggregate-context-ref`, no commits) was removed after these files were saved.

## Files

- `probe-TestTemplate.cs` — the playground repro (`Tests/Tests.Playground/TestTemplate.cs`), 11 shapes, `[IncludeDataSources(AllSQLite, AllPostgreSQL, DuckDB)]`. It captures the mapper that fails to compile via `Compilation.SetExpressionCompiler` + the BCL `Expression.DebugView` (`MAPPER>>` lines), and dumps `LastQuery` (`SQLDUMP>>`).
- `probe-lambda-resolve-visitor.patch` — mechanism (1) probe: `LambdaResolveVisitor.VisitMember` / `VisitMethodCall` visit the children when the whole node does not become a placeholder. Base: master `12bc7fe14`.

## Measured (master `12bc7fe14`)

| Shape (correlated on `g.ParentID == p.ParentID`) | SQLite.MS / DuckDB / PostgreSQL.18 | with the patch (SQLite.MS, PostgreSQL.18) |
|---|---|---|
| `.Where(… && IsBig(g.ChildID)).Count()` | `must be reducible node` | `no method 'AggregateExecute'` |
| `.Count(x => IsBig(x.ChildID))` | `must be reducible node` | `no method 'AggregateExecute'` |
| `.Where(… && IsBig(g.ChildID)).Sum(g => g.ChildID)` | `must be reducible node` | `no method 'AggregateExecute'` |
| association `p.Children.Where(c => IsBig(c.ChildID)).Count()` | `no method 'AggregateExecute'` | same |
| `.Where(… && IsBig(g.ChildID)).Any()` | works | works |
| `.Where(… && IsBig(g.ChildID)).ToList()` (projected collection) | works (SQLite.MS, PostgreSQL.18) | works |
| `.ToList().Count(x => IsBig(x.ChildID))` | works | works |
| `.Where(… && IsBig(g.ChildID)).ToList().Count()` | works | works |
| `.AsEnumerable().Count(x => IsBig(x.ChildID))` | `must be reducible node` | `no method 'AggregateExecute'` |
| `.ToList().Count(x => IsBig(x.ChildID + p.ParentID))` | `must be reducible node` | **works** |

DuckDB was run for the first four rows only.

## Mechanisms

1. **Outer references inside client lambdas are not built.** `LambdaResolveVisitor.cs:49` / `:73` return a node containing a `ContextRef` unvisited when the whole node is not a placeholder. Fixed by the patch (last table row).
2. **A failed `AggregateExecute` survives into the mapper.** `BuildAggregationFunction`'s `contextRef == null` branch (`ExpressionBuilder.Aggregation.cs:621`) puts the whole correlated chain in the lambda and only the bare table in argument 0; the build fails, `base.VisitMethodCall` eager-loads the bare table uncorrelated, and at run time the BCL `EnumerableRewriter` cannot rebind `AggregateExecute` over `IEnumerable` (only `LinqExtensions.AggregateExecute(IQueryable<T>, …)` exists, `LinqExtensions.cs:1795`). The working target form is `.ToList().Agg(…)`: keyed eager load of the correlated sequence, `Enumerable.Agg` on the client.

Scout trace of the path, with file:line, is in the #5901 comment above.
