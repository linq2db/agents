# Gap ledger — issue/6311-refuse-tuple-join-overloads (#6316)

No work plan on this branch (no-plan); attribution names the block a Tier M plan would have required.

## Round 1 — reviewed HEAD 47614ebd1f45e6f585865aff6edd450fd44850e6

- **SUG001** (test-coverage) — GAP-05 — `IsTupleJoin` (`JoinBuilder.cs:47-50`) admits `Queryable` or `Enumerable`; a `P8` `TO-n` per admitted declaring type, proven by a mutation dropping one disjunct, would have required the `Enumerable` navigation tuple join (bare and `comparer: null`); the arm arrived in self-review fix 2b04c453b, tested only for what it refuses (the `[IsQueryable]` lookalike) — G-01 — preventable: yes

### Aggregate

1 of 1 finding traces to a `P8` obligation per admitted arm of a recogniser predicate. The rule listing those arms exists (`work-plan/SKILL.md`, `plan-critic.md`), but no plan applied it, and the walk-time *attack its own new condition* rule checks a new guard's semantics, not its per-arm test coverage.

### Recommended durable fixes

- GAP-05 → `.claude/docs/acting-on-findings.md` (*attack its own new condition*): a fix that widens or narrows an admission predicate tests each arm it admits, not only the shape it refuses; deleting any one disjunct must turn a test red. (#6316 SUG001)
- GAP-05 → `.claude/docs/work-plan.md` `P8` semantics: a recogniser row's admitted declaring types / overloads become one `TO-n` each, with a mutation removing that entry.
