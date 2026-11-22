# Review rubric module: shipped agent guidance

Rules of the [`code-reviewer`](../../agents/code-reviewer.md) rubric that fire only on a path-identifiable change kind. Read when the briefing's `rubricModules` lists this module, or omits the field. Rule numbers are the core rubric's; "rule N" resolves through the core's **Focus scoping** index. In a multi-pass review, apply only the rules of your pass's focus:

| Rule | Focus |
|---|---|
| 35 | `api-and-test` |

35. **Every sentence of shipped agent guidance is a claim to verify, and a stated limitation is checked against the known issues.** `Source/Skills/**` ships inside the `linq2db` package, and agents write code from it, so a false sentence costs real code. The skill's own checks don't catch one: blind-check rounds measure outcomes, and `SkillContentTests` checks form (budgets, frontmatter, links). Walk the changed text sentence by sentence:
    - **An API name or signature** resolves at PR HEAD (`git grep … origin/pr/<n> -- Source`), and an "added in X.Y" claim holds against `PublicAPI.Shipped.txt` at the release tags (`git grep <member> v<X.Y-1>.0 v<X.Y>.0 -- '**/PublicAPI.Shipped.txt'`).
    - **A behaviour sentence** ("maps by name", "is `false` when an operand is `NULL`", "is not in `linq2db.xml`") cites the `file:line` that implements it or a run. A universal claim ("all", "never", "not in") is checked against every provider or family it spans, since one counter-example refutes it.
    - **A stated limitation** ("does not get it", "is not supported") is searched in the KB's `areas/<AREA>/issues.md` / `tech-debt.md` and with `gh issue list --repo linq2db/linq2db --search "<terms>" --state open`. A limitation that is an open bug must cite its issue as a known gap, never state it as a rule: it becomes wrong the day the issue is fixed.

    Flag `MIN` for a false or overstated sentence an agent would act on, and `SUG` for an unverified behaviour sentence or an uncited known gap. (Surfaced on #6430: `SKILL.md` said every public property maps without `[Table]`, while `EntityDescriptor.cs:363-364` maps scalar types only; `hints.md` said helpers are absent from `linq2db.xml`, while ClickHouse's are documented; and `hints.md:27` stated open bug #4321 as behaviour.)
