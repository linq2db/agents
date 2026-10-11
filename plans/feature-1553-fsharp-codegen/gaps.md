# Gap ledger — feature/1553-fsharp-codegen (PR #5707)

## Round 1 — reviewed HEAD 36caa4908

No work plan exists for this branch; findings are attributed to the block that would have carried them.

| Finding | Class | Would-be block | Gate | Preventable |
|---|---|---|---|---|
| MAJ001 type initializer dropped | GAP-03 | P7 parity row per C# `CodeClass` member visited | — | yes |
| MAJ002 7 options silently overridden | GAP-03 (+GAP-01) | P7 row per `ScaffoldOptions` member with F# disposition | — | yes |
| MAJ003 option values at `DataParameter` | GAP-02 (+GAP-03) | P4 probe of option handling at value boundaries | — | partly |
| MAJ004 CI never runs generator | GAP-05 | TO-n regenerate + diff goldens in CI | G-01 | yes |
| MAJ005 missing XML doc | GAP-08 | G-03 new public surface | G-03 | yes |
| MIN001 OCaml-reserved keywords | GAP-02 | P4 check keyword list vs spec | — | yes |
| MIN002 bare `#nowarn` | GAP-05 | TO-n for `--no-xmldoc-warn` | — | partly |
| MIN003 `--base-entity` dropped | GAP-03 | P7 per-option row | — | yes |
| MIN004 stale CLI in generate.ps1 | GAP-05 | regenerate-and-diff TO-n | G-01 | partly |
| MIN005 runtime tests on hand mirror | GAP-05 | TO-n consuming generator output | G-01 | yes |
| MIN006 no CLI fail-fast tests | GAP-05 | negative TO-n per rejected option | G-01 | yes |
| SUG001 CT defaults / outref | GAP-03 | P7 method-signature parity rows | — | partly |
| NIT001/NIT002 `module rec` doc drift | GAP-10 | — | — | no |
| NIT003 stale PR body (`--nrt`) | GAP-10 | — | — | no |

### Aggregate

12 of 15 trace to blocks a Tier M plan would have required. Dominant: GAP-05 (×5) and GAP-03 (×4), with one root cause: an alternative back-end built against an existing reference implementation without enumerating its surface, and verified against artifacts not produced by the generator (committed goldens, hand mirror). Largest single prevention: a P8 obligation that tests consume generator output produced in the same CI run.

### Recommended durable fixes (route to /session-reflect plan-rule bucket)

- GAP-05 → `work-plan.md` P8 semantics: for a code generator, a TO-n must exercise output of the current generator in the same run; every rejected option gets a negative TO-n.
- GAP-03 → `work-plan` SKILL scout brief: an alternative implementation of an existing abstraction enumerates the reference's full surface in P7, each row implemented / fail-fast / deferred-with-reason.
- GAP-02 → `plan-critic.md` attack vector: target-language wrapper types crossing runtime value boundaries; keyword lists sourced from the language spec.
