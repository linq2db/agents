---
area: T4-TEMPLATES
kind: issues
sources: [gh-issues, gh-prs, gh-discussions]
confidence: high
last_verified: 2026-10-21
last_verified_sha: 89b5ce16278728b9936ba374827fea002c76e962
---

# T4-TEMPLATES -- GitHub themes

## Open themes
- **Schema metadata exposure** -- [#2037](https://github.com/linq2db/linq2db/issues/2037) requests exposing unique constraint metadata to the T4 model generator (AlternateKey attribute).
- **Modern C# syntax** -- [#5183](https://github.com/linq2db/linq2db/issues/5183) requests file-scoped namespace support in generated T4 scaffold output.
- **F# output for the scaffolder** -- [#1553](https://github.com/linq2db/linq2db/issues/1553) asks whether the T4 generator can emit F# records. The CLI scaffolder F# data-model work is in draft [#5707](https://github.com/linq2db/linq2db/pull/5707) (`scaffold --target-language f#`, AST and code-generation path only; the T4 template mode stays C#-only). The draft test harness [#6037](https://github.com/linq2db/linq2db/pull/6037) is stacked on that branch.
- **Template customization errors** -- draft [#6036](https://github.com/linq2db/linq2db/pull/6036) fixes `scaffold --customize <template.tt>` crashing with a NullReferenceException (exit -2) on a compile error in the template control blocks. The compiler diagnostics are reported after `T4 compilation failed:` with exit code -3. Single item so far.
- **Golden output regenerated only by hand** -- [#6021](https://github.com/linq2db/linq2db/issues/6021) notes that scaffolder output is checked only against committed goldens (`Tests/Tests.T4/Cli/**`, regenerated manually through the T4 `RunCliTool()` templates), which CI never regenerates. Draft [#6037](https://github.com/linq2db/linq2db/pull/6037) adds a schema -> generate -> compile -> execute harness for C# and F#.

## Resolved themes
- **table** -- 10 closed issues share this keyword. Sample: #1161, #1191, #1450, #1451, #1640, #1586, #2168, #2752.
- **generated** -- 7 closed issues share this keyword. Sample: #1236, #1479, #1515, #1551, #2629, #1165, #4375.
- **stored** -- 7 closed issues share this keyword. Sample: #244, #1236, #1062, #1451, #1479, #2256, #399.
- **generation** -- 7 closed issues share this keyword. Sample: #1161, #1295, #1427, #1667, #2168, #761, #2791.
- **generate** -- 7 closed issues share this keyword. Sample: #1162, #1062, #1115, #1490, #2049, #2679, #2485.
- **name** -- 7 closed issues share this keyword. Sample: #1161, #1191, #1295, #1515, #1516, #1633, #2168.
- **postgresql** -- 6 closed issues share this keyword. Sample: #871, #1191, #1919, #2485, #3563, #4854.
- **template** -- 6 closed issues share this keyword. Sample: #1427, #1550, #1551, #1866, #1897, #2485.
- **code** -- 6 closed issues share this keyword. Sample: #871, #1191, #1489, #2633, #3374, #4375.
- **generates** -- 5 closed issues share this keyword. Sample: #1191, #1450, #1919, #3374, #4854.

## Active discussions
- No active discussions.

## Stats
- Open issues: 4 (area-tagged: #2037, #5183, #1553; cross-referenced: #6021)
- Closed issues: 66
- Open PRs: 3 (cross-referenced, all draft: #5707, #6036, #6037)
- Total PRs: 27 (24 area-tagged + 3 cross-referenced)
- Discussions: 1
- Last fetched: 2026-10-21

<details><summary>Coverage</summary>

- Index entries scanned: 97 (69 issues + 27 PRs + 1 discussions)
- Themes extracted: 15 (5 open, 10 resolved)
</details>
