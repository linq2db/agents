---
area: GLOBAL
kind: decision
sources: [git]
confidence: medium
last_verified: 2026-10-21
last_verified_sha: 89b5ce16278728b9936ba374827fea002c76e962
---

# Remove unused RemapToNewPath helpers

## Context
`SequenceHelper.RemapToNewPath`, `SequenceHelper.RemapToNewPathSimple` and `ExpressionBuilder.RemapToNewPath` had no callers left, their only references were their own recursive calls. All three came in with the LINQ parser refactoring (#3401, `7ec71d5`). The last callers of the other two were removed in #4676 (`b7de32b`), when `SelectContext` stopped calling `RemapToNewPathSimple` and `UpdateBuilder`'s OUTPUT handling switched to plain `ContextRefExpressions`.

## Decision
PR #6096 (`feaabc9`) deletes the three helpers (403 lines removed, 0 added) from `SequenceHelper.cs` and `ExpressionBuilder.Generation.cs`.

## Why
Dead code. The commit body notes that no open issue or PR references the helpers.

## Consequences
- The builder no longer carries the old path-remapping helpers from the #3401 parser design.
- No behavior change, the helpers were unreachable.

## Sources
- Commit `feaabc9` -- Remove unused RemapToNewPath helpers (#6096) (Ivan Demchuk, 2026-10-21)
- File anchors: `Source/LinqToDB/Internal/Linq/Builder/SequenceHelper.cs`, `Source/LinqToDB/Internal/Linq/Builder/ExpressionBuilder.Generation.cs`
