# Work plan: feature-expose-evaluate-all-expression-args — Evaluate every captured Expression<> argument in one pass

**Tier:** S  ·  **Status:** approved  ·  **Approved-at:** 2026-10-22  ·  **Branch:** feature/expose-evaluate-all-expression-args
**Schema:** `.claude/docs/work-plan.md`  ·  **Gates:** `.claude/docs/definition-of-done.md`

## P1 Problem

`ExposeExpressionVisitor.TryEvaluateArguments` (`Source/LinqToDB/Internal/Linq/Builder/Visitors/ExposeExpressionVisitor.cs:384`) replaces only the first evaluable non-quote `Expression<>`-typed argument per pass: the `if (evaluatedArgs == null)` guard skips every later one. Not observable in results (measured by session rework-pivot-aggregate-api, 2026-10-22, SQLite.Classic + LinqService, net10.0): the caller re-visits `node.Update(...)`, `Update` quotes the substituted lambda, and the next pass takes the next argument — one extra visit of the call per additional captured `Expression<>` argument. Reachable only from a correlated sub-query in a projection with captured `Expression<>` locals (`db.Patient.Where(pa => pa.PersonID == p.ID).Join(db.Person, innerKey, outerKey, result)`); an uncorrelated sub-query is evaluated client-side before reaching it. Behaviour-neutral cleanup, not a bug fix.

## P2 Success criteria

- SC-1 every evaluable `Expression<>` argument is replaced in the same pass (guard removed; a correlated `Join` with three captured `Expression<>` locals returns the same rows as LINQ to Objects) → TO-1
- SC-2 no regression in the existing suite on the changed path → G-01

## P6 Edit-points

- E-1 `Source/LinqToDB/Internal/Linq/Builder/Visitors/ExposeExpressionVisitor.cs:TryEvaluateArguments` — drop the `if (evaluatedArgs == null)` guard, keep `evaluatedArgs ??= node.Arguments.ToArray(); evaluatedArgs[i] = evaluatedExpr;`
- E-2 `Tests/Linq/Linq/JoinTests.cs:JoinWithCapturedExpressionsInCorrelatedSubquery` — characterization `AssertQuery` for the correlated `Join` with captured key/result selectors (green before and after; no red→green exists)

## P9 Verification gates

- G-01: pass — worktree-test.ps1, net10.0, SQLite.Classic + SQLite.Classic.LinqService: TO-1 4/4 green with CreateDatabase; control (master guard + `else throw`) failed both contexts with "skipped at 3", so TO-1 reaches the changed branch; JoinTests + SubQueryTests 267 passed, 0 failed, 3 skipped
- G-02: skipped — no local baselines snapshot taken; unverified locally: SQL of existing tests (expected unchanged, the rewrite is pre-SQL) and the new test's added baselines; CI baselines PR is the check
- G-05: pass — `dotnet build Source/LinqToDB/LinqToDB.csproj -c Release -f netstandard2.0`: 0 warnings, 0 errors
- G-06: pass — `git diff` touches only E-1 (guard removed, 2 lines re-indented) and E-2 (one test + `using System.Linq.Expressions`)
- G-07: pass — nothing under `Tests/Tests.Playground/` changed
