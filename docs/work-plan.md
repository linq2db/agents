# Work plans — schema, tiers, lifecycle

A **work plan** is a per-branch design document written *before* the first source edit, kept current through implementation, and read by review as its primary statement of intent. This doc is the canonical schema; [`../skills/work-plan/SKILL.md`](../skills/work-plan/SKILL.md) is the workflow that produces one and [`work-plan-template.md`](work-plan-template.md) is the fillable template.

## Why the artifact exists

Review had no durable statement of intent. `code-reviewer`'s entire picture of design intent was the PR body, linked issues one level deep, a 3–8 bullet change summary written on the spot, and one user-typed sentence at the scope gate — **all four regenerated per review**. Successive reviews of one branch therefore measured against a different yardstick each round, which is why they re-raised settled points instead of converging. A plan fixes the yardstick.

The second cost was that an accepted trade-off had nowhere to live: a deferral adjudicated in round 1 left no artifact, so round 2 raised it again. That is what `P10` is for.

## Location and key

```
.claude/plans/<key>/plan.md
```

`<key>` is the branch name with `/` replaced by `-`: `issue/5818-fix-setop-concat` → `.claude/plans/issue-5818-fix-setop-concat/plan.md`.

Deterministic, derivable before a PR number exists, and never needs renaming.

**Plans live in the corpus submodule, not in linq2db.** They are committed inside `.claude/` and pushed to the agents repo's `master` like any other corpus change ([`agent-rules.md`](agent-rules.md) → *The corpus is a submodule*). Consequences worth knowing:

- The plan is present in **every** worktree with no merge, and readable while reviewing a PR that is not checked out — `/review-pr` reads it from disk, not from the branch.
- It is **never squashed away**. A linq2db PR squash-merges; the plan is unaffected because it was never on that branch.
- It is **invisible to GitHub-side reviewers** (Copilot, humans reading the diff). Accepted trade-off: our own review pipeline is the consumer.
- The plan is committed **on its own**, separately from any linq2db work, per the corpus commit rules.

## Tiers

Tier sets which blocks are mandatory and whether the critic runs.

| Tier | Trigger | Mandatory blocks | Critic |
|---|---|---|---|
| **S** | ≤3 files, one area, mechanical — a version pin, an `[ActiveIssue]` enable, a typo, doc-only, flipping a documented flag | `P1` `P2` `P6` `P9` | none |
| **M** | anything not S or L — the common case | all | advisory; verdict recorded in `P12` |
| **L** | ≥2 areas, **or** a path matching [`../rules/cross-cutting-core.md`](../rules/cross-cutting-core.md)'s `paths:` list (`Source/LinqToDB/**/SqlQuery/**`, `Source/LinqToDB/**/Translation/**`), **or** `IDataProvider` / SQL-builder base classes, **or** new public API outside `LinqToDB.Internal.*` | all, and `P5` must name rejected alternatives | **mandatory**; a missing `P12` is a `-Validate` error |

**Tier is a floor, not a ceiling.** Escalate through `P11` when the work turns out bigger than it looked. **Never de-escalate to dodge the critic** — that is the gaming shape this mechanism exists to prevent.

**A review that grows into infrastructure work crosses into plan territory, and nothing announces the crossing.** A `/review-pr` session starts read-only, so no plan is owed; the interactive walk then disposes findings one at a time, each fix small enough on its own to need no plan. There is no single turn at which the accumulated work declares itself non-trivial. Watch for the objective tells — the session pushes a **new** file rather than editing diffed lines, adds CI/workflow/packaging surface, or lands more than about three commits — and at that point either write the plan or record that you are proceeding without one and why. An interactive walk where the user approves each diff before it lands is a *legitimate* substitute for the plan's review function, because the design is being adjudicated turn by turn rather than up front; it is **not** a substitute for `P7`'s impact map, which is the block a walk cannot supply. (Surfaced on #5894: a metadata-PR review pushed four commits including a new `publish-mcp.yml` GitHub Actions workflow with no plan at any point. Every step was user-approved, and the impact question a `P7` would have forced — *what else consumes this manifest, and what fires this trigger* — happened to get asked anyway, by the maintainer.)

**Tier S omits `P7`, and that is exactly how a lockstep mirror ships.** A one-line change to a *matcher* — a provider capability flag, a type-keyed switch in a SQL builder, a `switch` over `DataType`, a message-literal predicate — is Tier S by every criterion while being the shape most likely to have a silent twin. linq2db is dense with these: a `SqlServerSqlBuilder` change with an unmoved counterpart in `SybaseSqlBuilder`, an `Insert` path without its `Update` mirror, a flag defaulted in one `SqlProviderFlags` initializer and not another. **When the edit adds a case to a match, search the matched value — the literal, the type, the enum member — tree-wide regardless of tier.**

**Tier S also omits `P5` and `P8`, which is how a multi-mode defect fix ships one fixture and an unexamined design choice.** A bug fix touching three files in one area reads as S on every criterion, and the trigger column's examples are all genuinely mechanical — a version pin, a typo, a flag flip. A *defect* fix is not that shape: it has failure modes to characterise and usually a choice about where the fix goes, and those are exactly the two blocks S deletes. The tell is in `P1` itself — when the problem statement names more than one failure mode, or when the fix has a plausible second location (patch the copy vs unify the twins), take **M** however few files it touches. (Surfaced on #5893: a 3-file, one-area, defect-driven branch that carried no plan at all. Its review produced five accepted changes, and an independent attribution traced two of them to blocks only M requires — a `P8` obligation per named failure mode, and a `P5` decision recording patch-vs-unify with its failure mode. The other three traced to no block at any tier, so the measured yield of a plan on this shape was one obligation and one decision: an argument for the light tier, not for more ceremony.)

## Blocks

Blocks marked (M/L) are omitted entirely on a Tier S plan — delete the heading rather than leaving it empty.

### P1 Problem

The observed failure or absent capability, stated **falsifiably**: a reproduction, a stack trace, the wrong SQL beside the right SQL. "It's broken" and "improve robustness" are not `P1` statements because they cannot be shown to be fixed.

### P2 Success criteria

One `SC-n` per criterion. Each must be **failable** — you can state the observation that would show it unmet — and each maps to a `TO-n` in `P8`.

**When the branch closes an issue, reconcile `P2` against that issue's stated scope line by line — and record every narrowing as a `P3` anti-goal with a disclosure obligation.** A plan derives its criteria from the *problem*, which is the right instinct and quietly drops whatever the issue asked for that the problem did not require. The drop is usually correct on the merits and measured; what is missing is that anyone said so. Since the PR will carry `Fixes #<n>`, the issue's text is the contract a reader compares against, so an unrecorded narrowing is discovered by whoever reads both — a reviewer, a bot, or a user hitting the gap after release. The cost of getting this right is one `P3` line plus a sentence in the PR body. (Surfaced on [#5877](https://github.com/linq2db/linq2db/pull/5877): [#5814](https://github.com/linq2db/linq2db/issues/5814) asked for three atom forms — `Is*()`, `HasFlag`, and bitmask — and `U-4` measured that bitmask had zero sites and dropped it, correctly. Nothing recorded the decision, and Copilot filed it against the PR before the review did.)

### P3 Constraints & anti-goals (M/L)

What must **not** change. For linq2db the recurring ones: the public API contract outside `LinqToDB.Internal.*`; generated SQL for providers the change does not target; existing baselines; query-cache behaviour; a perf budget where one was measured.

### P4 Unknowns (M/L)

The blind-spot pass that [`agent-rules.md`](agent-rules.md) → *Do a blind-spot pass before coding in an unfamiliar subsystem* already demands but produces no artifact for. One row per assumption, unresolvable unknown, or unmentioned edge case. Each row ends `resolved-by <user answer | scout | probe>` or `OPEN`.

**No `OPEN` row survives approval** — `-Validate` fails on one. Mark a row `OPEN` when it is genuinely unresolved; do **not** silently pick a plausible interpretation and build on it.

**When a `P5` decision *admits* an element into a detector's scope, the plan owes a `P4` row per admitted element — probed through *every consumer*, not just the detector.** The `P8` rules below catch a set the obligations name; this catches the set a decision *accepts*, where the danger is not a missing element but a missing **consumer**. A rule that admits a symbol kind, input class, node type or inheritance relationship hands that element to a detector, a code fix, and whatever renders its message — and the detector is the one everybody probes, because it is where the decision was written. The tell is a `P4` row, or a scout note, that reasons about an admitted element and mentions exactly one of those consumers. Two worked examples, both from the same branch one generalisation apart: `MethodKind.ExplicitInterfaceImplementation` was deliberately admitted and probed only through the detector, so nobody asked what `ISymbol.Name` returns for it (the dotted `I.M`, which kills a name-equality walk) or what `nameof(<bare identifier>)` renders inside one (`CS0103` — a code fix turning compiling code into a compile error); and the implemented-interface walk was admitted, then taught to the fixer for *one* remedy branch, leaving its structural sibling in the same `switch` to mark the implementation instead of the interface — silencing the rule while the call it was reported for still client-evaluated. (Surfaced on [#5870](https://github.com/linq2db/linq2db/pull/5870), whose round-1 and round-2 reviews each produced their only `MAJ` from this one shape.)

### P5 Decisions (M/L; rejected alternatives mandatory at L)

One `D-n` block per consequential decision:

- **chosen:** …
- **rejected:** … — why not
- **why this:** …
- **failure mode of the choice:** …

The `failure mode` line is what makes a decision defensible rather than merely explained, and is usually where the critic finds its objection.

### P6 Edit-points

The **authorized change surface**, not a prediction. One row per planned edit: `E-n <path>:<symbol> — what changes`. Touching anything not listed here needs a `P11` amendment.

**The new `E-n` row itself goes in `P6`; `P11` carries only the rationale.** Reconciliation reads `P6` and nothing else, so an edit-point recorded only in an amendment is invisible to it — the gate then reports authorized work as unplanned.

**An `E-n` on user-facing documentation must name the `SC-n` or `D-n` it restates — a position is not a specification.** For a code edit-point the symbol carries the intent, so `path:symbol — what changes` is enough. For a readme row, a help string, a wiki section or a CLI description, the same shape degrades to "put something at this line", and anything put there satisfies the plan. Nothing downstream catches it either: prose has no compiler and usually no gate, so a row that documents half the feature ships green. Write `E-n <path>:<line> — restates SC-n` and the reviewer has something to compare against. (Surfaced on [#5873](https://github.com/linq2db/linq2db/pull/5873): `SC-2` specified the `!=` contract including its nullable qualification, while `E-3`/`E-5` authorized only *"diagnostics-table row (`:26`)"*. Both readmes shipped a row describing `==` alone and stating the `!=` outcome backwards — identical wrong text in two files, which is the tell that the defect is in the specification rather than in two independent slips.)

### P7 Impact map (M/L)

**Searched, never reasoned.** Search for:

- callers of every changed symbol
- **mirrored / parallel sites that must move in lockstep** — the dominant linq2db shape: sibling `*SqlBuilder` / `*SqlOptimizer` / `*MemberTranslator` classes, a base-class default overridden per provider, `Insert` and `Update` paths, read and write converters
- serialized / wire shapes — `LinqService` remote contracts, serialized enums (append-only; see [`pr-and-push.md`](pr-and-push.md))
- contract changes where a caller must tolerate a new value — a `throw` that becomes a `return null`, an added enum member a `switch` does not handle

Every row carries exactly one verdict: `covered by E-n` | `deferred: <reason>` | `out-of-scope`. If a search finds nothing, write `Localized — searched <symbol> across <scope>, no callers or emitted-SQL change.` **A bare "localized" with no named search is invalid.**

**A registration-surface row lists paths, one per hit — never a role name.** "The package `readme.md`", "the release-notes file", "the analyzer registration" each collapse a set the sweep already enumerated, and the collapsed member is the one that gets missed. Write every path the search returned, even when they look interchangeable. The row must also name the surfaces a repo-wide grep **structurally cannot reach** — wiki pages, nuget.org-rendered metadata, external dashboards — since those are invisible to both the sweep and `-Action reconcile`. (Surfaced on #5870: "needs a row only in the two `AnalyzerReleases.Unshipped.md` files and the package `readme.md`" counted and pathed the first pair and collapsed the second, and linq2db has **two** packed readmes with an analyzer rule table. The unlisted one is the `linq2db` package's own — what nuget.org shows for the library — and it shipped stale.)

### P8 Test obligations (M/L)

One `TO-n` per `P2` criterion. Each names what it asserts and a proof mode:

- `red→green` — fails against the unfixed code **for the right reason**, then passes. Proven by running it, never by reading it.
- `control` — for an added guard: the same input accepted under the lenient path, rejected under the enforced one.
- `characterization` — behaviour-preserving; say plainly that it proves no new behaviour.

Where an `E-n` touches a helper reachable from more than one path, one obligation must be a **symmetry guard on the unchanged path**.

**An obligation that names a *set* is not one obligation — expand it to one named fixture per element.** "All four marker forms", "both options additive", "a trivia battery", "each remedy branch" all read as satisfied by a fixture set covering *some* of the set, because a subset is green and a subset is indistinguishable from the whole. Enumerate the elements in `P8` and record `G-01` as one row per element with the observation proving it ran, rather than as a run total — `78/78` cannot tell a covered element from an absent one. (Surfaced on #5870, where this single shape produced three of nine review findings: a marker form with no fixture, one of two option lists with no additivity guard, and a trivia battery covering one of the two branches it existed for.)

**The mirror of the rule above: an enumerated set inside a `P5` decision is itself an obligation checklist, even though it appears nowhere in `P8`.** The rule above catches a `TO-n` that *names* a set; this catches the set the obligations never mention. A decision that lists what the change will recognise — a shape list, a ratio or unit table, a message/outcome matrix, the escape shapes a *rejected alternative* enumerates — has committed to every member, and `P8` written afterwards reliably picks one or two representatives, because a representative reads as "this mechanism works". It does, for the member you picked. Write one `TO-n` row per member, or an explicit line naming which members are unexercised and why. The tell that this is unhandled: a `D-n` containing a bulleted list or a `switch`-shaped table whose element count exceeds the number of `TO-n` rows that mention it. **Corollary for `P11`:** an amendment that replaces a mechanism must re-derive every control whose discriminating factor it moved — a control written against the old mechanism can survive the change while no longer isolating anything. (Surfaced on [#5873](https://github.com/linq2db/linq2db/pull/5873), where this one shape produced **six of fifteen** review findings: `D-3`'s ten constant shapes had six positives, `D-6`'s six-entry unit table left the one hand-typed ratio unpinned, `D-8`'s four named escape shapes had one control — and the shipped code fell into another of the four — and `SC-1`/`SC-2`'s six-cell outcome matrix asserted four. A 35-test fixture with a genuine mutation-based red arm was blind to all of them. The corollary is from the same PR: a `Zip`-based control written against an ordinal rule kept passing after `P11` replaced that rule with a name allowlist, since `Zip` is refused by name before the ordinal is consulted.)

**A `P1` naming more than one failure mode for the same defect owes a `TO-n` per mode — and the mode left unfixtured is reliably the one the prose calls the more damaging.** The rules above are about an enumerated set inside `P8` or `P5`; this is the set hiding in the *problem statement*. A write-up that says "it throws on X, and worse, it masks the real error on Y" has named two behaviours, and obligations written from the reported repro cover the reported one: the second mode is the author's own deeper analysis, arrived at after the test list was already set, and it is usually the harder of the two to construct. Where a mode needs a precondition to be reachable at all, name that precondition in the row — that is what stops the obligation being discharged by a fixture which cannot enter the path. (Surfaced on #5893, a branch with no plan: the bare-dispose `NullReferenceException` and the exception-masking variant were both named in the PR body, six tests covered the first, and the masking mode was credited to a test that never invokes the initializer at all. Its precondition is a query **with preambles** — `Query.StartLoadTransactionAsync` returns null without beginning a transaction when there are none — so a cancelled token on a plain query, the trigger the write-up named first, cannot reach it.)

**One level below the two rules above: a fixture per element is not coverage unless the element's *input* can separate the arms — so record the discriminating input beside the decision.** The enumerated-set rules ask whether every member has a fixture. This asks whether the fixture can fail. A `P5` predicate with two clauses is decided by one clause for most inputs and by the other for the rest; only an input where they **disagree** exercises the choice between them, and that input is derivable from the decision's own wording. A `P8` row naming the case without naming that input gets satisfied by a fixture whose name says one thing and whose input tests another — which is *worse* than an absent fixture, because it reads as covered in `G-01`, in the file, and to a reviewer. So when a `D-n` defines a predicate, write the separating input into the decision, and have the `TO-n` cite it. The objective gate is a mutation: break the product and confirm only the intended fixture reddens. (Surfaced on #5870 round 3: `D-8` form 2 is "explicit `ServerSideOnly` argument, else the `Sql.ExtensionAttribute` ctor default", so the only separating input is an `ExtensionAttribute`-derived attribute carrying an explicit `= false`. The fixture named for that case used `Sql.Function`, which is not `ExtensionAttribute`-derived and so already yields `false` when unset — it stayed green under an inverted implementation, proved by mutation. Three of that round's eight items were this shape, after two earlier rounds had already produced the two rules above.)

**Where the assertion sits on a conditional path, the obligation must name what proves it fired.** "Proven by running it" is satisfied the moment the test executes and passes — which an assertion inside a `catch`, behind an `if`, or under a provider branch achieves without ever running. Say which observation distinguishes *asserted and held* from *never reached*: a value only the taken path can produce, a failure injected to force the branch, or a count the untaken path cannot yield.

**When a `P5` decision introduces a *check*, one `TO-n` must fail if that check is absent.** A decision of the form "the tool will also verify X" describes code that does not exist yet, and nothing else in the plan notices when the implementation quietly ships without it: the edit-point is a file that *was* edited, the gates go green because everything the tool does check still passes, and reconciliation sees no unplanned change. The obligation is the only artifact that can distinguish "X is verified and holds" from "X is never verified" — so write it against the check itself, by feeding the tool an input the check must reject. (Surfaced 2026-09-03 on `issue/5731-third-party-license-notices`: `D-7` specified a per-framework version comparison against each payload's `deps.json`, and `verify` shipped mapping files only — no version check at all. Every gate was green. `TO-6`, which injected a wrong version for one framework and required only that payload to fail, is the sole reason it was caught, and it was caught before review rather than after.)

**Every `E-n` in `P6` must map to at least one `TO-n` — an authorized edit-point that is silently dropped is invisible to every other check.** The plan's conformance machinery is asymmetric: `-Reconcile` flags files that were changed *without* authorization, and `G-01` reports pass/fail per named obligation. Neither notices an edit-point that was approved, agreed to be necessary, and then never implemented — there is no unplanned file to flag, and no failing obligation because none was ever written against it. The design says the fix exists, the diff doesn't contain it, and the gap surfaces at review as a defect rather than as a dropped commitment. Write the mapping explicitly, the same way `P2` already maps each `SC-n` to a `TO-n`. (Surfaced on #5844's round-2 review: `E-3` authorized *"both `CreateQuery` overloads copy `Parameters` onto the constructed query"* and was never implemented — both overloads still build a bare `ExpressionQueryImpl`. It became MIN009, a `NullReferenceException` on non-terminal composition over a compiled result. `P10`'s own text had pre-adjudicated the outcome — *"if it does not [work], that is a finding rather than a silent gap"* — and no obligation existed to make the omission visible before merge.)

**An obligation whose subject is what the change *excludes* must name where those subjects come from.** The obligations above are about inputs you construct; this is about the ones you have to go and find. A `TO-n` of the form "…and asserts that the things we deliberately left out are still left out" — untouched providers, packages outside the manifest, the unchanged half of a mirrored pair — reads as covered and is trivially satisfiable by an input set that contains none of them. It then reports green having asserted nothing, and every summary line it prints ("inspected N artifacts") is true. Write the source of the negative subjects into the obligation itself: *which* excluded item, produced *how*. If the answer is "a full solution pack" or "a provider we don't run locally", say so — a `skipped` that names what is therefore unverified is worth more than a `pass` that measured an empty set. (Surfaced 2026-09-03 on `issue/5731-third-party-license-notices`: `TO-4` claimed to assert that packages outside the notices manifest bundle no third-party binary, and was recorded `pass`. Every local run pointed at a directory holding only the sixteen artifacts that *are* in the manifest, so the assertion never executed once — and the code path it covered in fact crashed on the first excluded package it met. Both CI legs failed on it.)

**An obligation whose expected failure comes from a third-party still-open issue takes a `P4` row, not an assertion.** Writing *"the call still fails on #NNNN, so assert only that the failure changed shape"* encodes someone else's bug as this plan's premise, and that bug was filed against a different shape, a different model, or a different API. It may simply not reach yours — in which case the obligation's assertion is unreachable from the first day and the plan never notices, because the test is green. Probe the post-fix state and record the answer; do not specify around an unverified failure. (Surfaced on [#5840](https://github.com/linq2db/linq2db/pull/5840): `TO-8` asserted that an `UpdateWithOutput` over an inheritance root still throws on #5838 after the fix, and put its only assertion inside the `catch`. Measured later across six provider configurations, the call raises nothing at all — so the obligation had shipped a test that could not assert anything, and two review passes plus a green CI leg had accepted it.)

**For an `E-n` that adds a detector, an analyzer or a parser, the obligations must cover its own branches — not only the `SC-n` list.** `P8` is derived from `P2`, so it inherits `P2`'s shape: one obligation per user-visible criterion. An implementation has branches no criterion names — a two-mode predicate, a descent loop per nested-graph kind, a bail-out guard the code's own doc calls load-bearing — and those are invisible to every other check, because the code is *correct* and the gates are green. Before `G-01` reads `pass`, enumerate the conditionals, loops and guards in each `E-n` file and record, per branch, the fixture that fails when it is mutated. Note the asymmetry with the rule below: that one hardens a control the plan already has, so it cannot fire for a branch with no obligation at all. (Surfaced on [#5877](https://github.com/linq2db/linq2db/pull/5877) round 3: forcing `Atom.Holds` to one of its two modes, deleting either nested-graph descent, or removing the tracked-symbol write-drop guard each left all 26 fixtures green. Seven such branches; three were also *wrong* — a switch section skipped without testing for a `throw`, a braced case body read as unparseable drift, a lambda descent skipping `BranchValue` — and three sat in functions that rounds 1 and 2's own fix commits had edited, a few lines from the change being made at the time.)

**And `G-01` records that sweep as an enumeration with a *denominator*, never as a narrative.** The rule above says to sweep the implementation's branches; this says what the plan must then contain, and it is the half that decides whether the rule can be checked at all. A `P9` line of the form *"N fixtures were added, each closing a branch no fixture could see"* is true of the branches someone handed you and identical in wording to an exhaustive pass — so a reader cannot tell "swept the file" from "swept the items the reviewer listed", and neither can the next review. Write "N branches, M uncovered: `<list>`", with each uncovered entry either fixtured or waived with a reason; run the fixture project under branch coverage if the count is not small enough to enumerate by hand. The rule is not made stronger by better prose, it is made *falsifiable* by the count. (Surfaced on [#5877](https://github.com/linq2db/linq2db/pull/5877) round 4. Round 3's sweep rule was executed textbook-style against the seven branches that review named — each with its mutation and reddening fixture recorded — and landed in this file **43 minutes after** the fix commit it describes, so it never bound the branch's authoring. Round 4 then found three more unentered branches in the same two files, all of them original first-implementation code: a switch-section cardinality guard, a `ClimbNegations` arm an `SC-n` rested on, and a `ReadSymbol` arm the code's own doc claimed. Eight of that round's eleven findings sat in code three reviews and 37 fixtures had never reached.)

**A control obligation records the *mutation* that proved it can go red — a passing control proves nothing on its own.** `P8` already reaches for controls, and the discipline is real: a plan that rejects a candidate control for being non-discriminating is doing exactly the right thing. But the discipline is applied to the controls a plan *reasons* about and skipped for the ones it merely writes, so it lapses hardest on a control added **late** — in response to a critic objection, or alongside a fix — which never gets the scrutiny its siblings did. The remedy is one field, not more tests: beside each control's `pass`, name the defect that was injected and the arm that went red. A control with no recorded mutation is an unverified claim, and `G-01` should read it that way. (Surfaced on [#5877](https://github.com/linq2db/linq2db/pull/5877): `TO-5` existed *specifically* because two obvious controls could not discriminate — the plan identified and rejected both — yet the third arm added later to cover the `HasFlag` path could not fail either. Measured by injecting the defect: with the receiver-type guard defeated, **all 15 fixtures passed**. Six of that review's ten findings were this one shape.)

**A `TO-n` that pins a message, a reason argument or any other exact output takes its expected value from the `P1`/`D-n` block it cites — never from the first run.** The rule above catches a control that cannot go red; this catches its mirror, a control that goes red on *any* change and still encodes the wrong answer. The failure shape is specific and it looks like diligence: the expected value is read off a live run, written into the fixture, and the run's own surprise — *this emits the other message* — gets recorded in the commit body as an observation and dispositioned "left alone". The obligation now pins the behaviour rather than the intent, and the next reader finds a green fixture asserting something the design contradicts. Derive the value from the design first; if the run disagrees, that discrepancy is the finding, not the new expectation. Two corollaries: a residual risk `P12` names becomes a `P8` row **before** the verdict is recorded, since a risk with no obligation is a note; and a fix commit answering "no obligation can see X" carries the obligation, not only the code. (Surfaced on [#5877](https://github.com/linq2db/linq2db/pull/5877) round 2, against round 1's own fix: `5d98f183c` pinned the reason argument on the flagship fixture, recorded in its body that the shape emits the *dead-code* wording where the design assigns it the *modelling-mistake* one, and left it. Round 2 measured the branch firing **zero** times across all 22 census diagnostics. Separately, `P12`'s single carried residual risk — `!(a && b)` lowering — still had no fixture two rounds later, and round 1's fix for it edited a message string instead.)

**A stub standing in for a production artifact must mirror its actual shape, or say why the difference is immaterial.** A fixture that synthesises the thing under test — a miniature model, a stand-in schema, a hand-built manifest — is written for readability, so it drifts toward the *tidiest* form rather than the one production uses. Every reader then sees a "faithful miniature" and nobody re-checks the axis the code branches on. Three axes bite in practice: **syntactic form** (an expression-bodied member where every real one is statement-bodied, when the reader has a separate branch per form), **file layout** (one synthetic document where the real artifact spans two, when the behaviour under test is per-document), and **model cardinality** — the stub must carry at least the smallest count at which every combinatorial construct in the code under test does something, and say which count it chose. Below that threshold a correct implementation and a broken one produce identical output, so no fixture built on the stub can discriminate however carefully it is written. State the reductions the stub makes and which are load-bearing. (Same #5877 review: all nine stub predicates were expression-bodied against fourteen real statement-bodied ones, so the suite exercised only the branch production never takes; and the drift fixture's single document could not exercise the cross-file diagnostic-location behaviour that turned out to be a real defect.)

### P9 Verification gates

Gate ids are **not defined here** — they are the items of [`definition-of-done.md`](definition-of-done.md), which is the canonical exit checklist. `P9` records which of them applied and what they returned:

| Gate | Definition-of-done item |
|---|---|
| `G-01` | Tests run and pass via `/test`, with the declared proof mode observed |
| `G-02` | Baselines reviewed, not just regenerated |
| `G-03` | New public surface accounted for (`PublicAPI.Unshipped.txt`, XML doc, a test) |
| `G-04` | API baselines refreshed via `/api-baselines` when the surface changed |
| `G-05` | Builds on the portable TFMs, not just `net10.0` |
| `G-06` | No unrelated reformatting / renames |
| `G-07` | No playground scratch staged |
| `G-08` | Cross-cutting core change surfaced, and resting on a red→green test or CI rather than static reasoning |
| `G-09` | The diff got an adversarial read before the PR opened (Tier M/L only — `-Action gates` keys this one on tier, not on `P6` paths) |

Record each as `G-nn: pass | fail | n/a | skipped | blocked — <the command run and what it returned>`. **`skipped` must name what is therefore unverified; `blocked` must name the deferred dependency. Never dress either up as a pass.** A listed probe or extra gate left with **no result at all** is `fail`, not an omission — a blank line reads as "not important" to every later reader, which is precisely backwards for something the plan thought worth listing.

**Every `P9` row names the commit it describes, and is re-derived after the last commit touching any `E-n`.** `P9` is written once, at approval, and then the branch moves — a critic objection folds in, a review round pushes eight fixes, an amendment adds edit-points — while the block keeps reporting the tree it was written against. Nothing goes red, because the measurement already happened. The cost is not cosmetic: when no CI leg exercises the gate, `P9` *is* the only evidence for its `SC-n`, so a stale row is an unbacked success criterion, and its stale figures are the ones a later reader reconciles against and cannot. Date each row, and re-run the cheap ones before calling the branch done. (Surfaced on [#5877](https://github.com/linq2db/linq2db/pull/5877) round 2: `G-01` recorded `total: 12` against 18 shipped fixtures — the six missing were exactly the riskiest, added for a CFG-seeding fix — and its census split of `20 × LINQ2DB0004 + 2 × LINQ2DB0005` reconciled with nothing; re-measuring returned `14 + 8`, matching `P7`/`P11`'s own enumeration. The recorded split had been a transcription error carried unchallenged through a full review round.)

**An amendment answering a review finding owes a `TO-n` per input class its *own prose* names.** A `P11` entry written in response to review is where the branch's sharpest thinking about an input domain gets recorded — it enumerates the cases the fix must handle, often naming one explicitly as the case that motivated the finding. That sentence *is* a specification, and nothing checks it: the amendment ships, the enumeration stays prose, and the named case has no fixture. The next round then finds the defect in the very input the previous amendment described. Read back every amendment you write, list the input classes it names, and give each one a `TO-n` row — the cost is one fixture per named class and the alternative is a same-shape recurrence. (Surfaced on #5870 round 3, on round 2's own fix: `A-11` wrote *"An interface member declared in metadata yields no location and the fix declines rather than writing a marker the runtime will not read"* and shipped no fixture for the metadata case. It did not decline — it marked the implementation, silencing the diagnostic while the call it was reported for still evaluated client-side. Both of round 3's defects were inside `A-11`, the second being the multiplicity question its singular walk never raised, and round 2's ledger had already prescribed sweeping an admitted relationship across every sibling consumer path.)

**A `D-n` failure-mode line that makes a checkable claim about the language or a framework is a `P4` row, not prose.** A failure mode is where a decision states *why* a scope boundary is where it is, and an appealing form of that is a language rule — "the attribute cannot be applied there", "the compiler forbids this shape", "that overload does not exist". Such a claim is one compile away from being verified and, left in prose, it propagates: into `P10`, into a code comment at the site, and — for a shipped analyzer or public API — into user-facing documentation, where a reader who tests it finds it wrong. Put it in `P4` with a probe, or state the boundary as a scope decision and drop the justification. (Surfaced on #5870 round 3: `D-12` claimed constructors, operators and indexers are out of scope because `[ServerSideOnly]` "cannot be applied to them (`AttributeTargets.Property | Method`)". Measured, only the constructor half holds — an operator declaration takes method-targeted attributes and an indexer *is* a property — and the same wording had reached the shipped `L2DB1003` wiki page.)

**A mid-implementation `TO-n` correction that changes a *contract* is a `P11` amendment, and it must list every block restating that contract.** Correcting an obligation inline in `P8` is right when the fix is to the test; it is not enough when the obligation encoded a promise the rest of the plan also makes. `SC-n`, the owning `D-n`'s failure mode, and any user-facing text implementing it all keep the superseded wording, and each is now a claim the code contradicts — including, typically, a shipped diagnostic message or doc comment that a reader will trust over the code. (Same #5877 round 2: `TO-4` was corrected during implementation so an unreadable *predicate* keeps the condition rules running, with no `P11` entry. `SC-4` still promised the opposite, and so did `LINQ2DB0006`'s message text and the analyzer's class doc — the one path the message existed for was the path where it was false.)

**`G-01` records one row per `TO-n`, naming the test method — a run total is not evidence about an obligation.** The gate says "with the declared proof mode observed", and a green run looks like exactly that from the outside: `total: 13 succeeded: 13` counts *tests*, so an obligation with no test at all, one whose test exercises a different branch, and one whose assertion never executes are all indistinguishable from a satisfied proof mode. Name the method that satisfies each `TO-n` and the observation proving its proof mode ran. **An obligation with no named test is `fail`, never `pass, partially`** — and "the shape's red state was seen in the probe grid" discharges nothing when the grid has no cell for it. (Surfaced on [#5840](https://github.com/linq2db/linq2db/pull/5840): `G-01` was recorded `pass, partially` against 13/13, qualified only on an unreachable SQL Server leg. Review then found `TO-4` and `TO-6` had no test at all, `TO-3` covered one of the three positions it claimed, and `TO-8`'s assertion never fired — four of the round's seven findings, none visible to the gate as written.)

Analyzers are Release-only and `Testing` builds `net10.0` only, so `G-05` is not satisfied by a green `Testing` build ([`agent-rules.md`](agent-rules.md) → *Build & push gotchas*).

### P10 Adjudicated (M/L)

Accepted trade-offs and deliberate deferrals — **the do-not-flag set for this branch's reviews**. Each entry needs a reason, and where the reason is a measurement, the measurement.

Two guards keep this from becoming a silencer, and both are enforced in the reviewer's briefing:

- **An entry with no reason suppresses nothing.**
- **A reviewer who disagrees with an entry raises a finding *against the entry*,** quoting both sides. The user decides which stands.
- **An entry summarising a `D-n`'s failure mode may not drop a qualifier the `D-n` carries.** `P10` is written by compressing a decision into one line, and a dropped qualifier widens the accepted loss silently — the entry then reads as adjudicating more than was ever decided, and every downstream artifact inherits the wider claim, because `P10` is what user-facing prose gets written from. Quote or cite the `D-n` rather than paraphrasing it. (Surfaced on [#5873](https://github.com/linq2db/linq2db/pull/5873): `D-4`'s failure-mode line said *"sub-millisecond `double`-factory constants (`FromMilliseconds(0.5)` **against a `Millisecond` column**) are not diagnosed"*; `P10` restated it as *"sub-millisecond `double`-factory constants are not diagnosed"*, and the published wiki page carried that unqualified form — which is false, since the same constant against a `Second` column *is* reported.)

### P11 Amendments (M/L)

Append-only. One `A-n` per change to the plan after approval.

**Amendment voids approval.** A user approval is a final word on the *then-current* edit set. Adding an `E-n`, or materially changing one's scope, resets that part to unapproved and needs a `P11` entry — whoever makes the change. Never silently carry an approval across a widened edit set: that converts per-change consent into a blanket one.

**A refuted design is recorded as abandoned, not deferred.** "Deferred" asserts the design was sound and the timing was off, so the next reader picks it back up and re-derives the refutation from scratch.

### P12 Critic verdict (M/L)

The `plan-critic` result — `holds` | `weak` | `refuted` — its objections, and what changed in response.

**A `weak` verdict is carried forward with the objections visible, not silently absorbed.** The user approves knowing the strongest case against the design.

**A self-critique by the plan's author is not a verdict.** When the critic genuinely cannot run, record `waived-by-user: <reason>`, which makes the skip visible to the user instead of to nobody. A standing `criticModel: never` (see *Settings* below) is the same thing decided once instead of per plan — it still gets its own `waived-by-user` line naming the config, because the config is gitignored and the plan is not.

## Lifecycle

```
draft ──authored──> critiqued ──> approved ──> implementing ──> reviewed ──> closed
                        │                          │
                   refuted: one              amendment (P11)
                   re-author pass            voids affected approval
```

**A status advances only on evidence.** No block flips toward done without a resolvable `file:line`, a command output, or a commit citation. Process-artifact churn must not outrun real code churn — see [`agent-rules.md`](agent-rules.md) → *Don't let progress artifacts outpace real work*.

## Consumers

| Consumer | Reads | Writes |
|---|---|---|
| `/work-plan` | all | all |
| `plan-critic` | `P1`–`P9` | nothing (read-only; the skill records `P12`) |
| `/review-pr`, `/verify-review` | `P1`–`P3` (intent), `P7` (coverage), `P10` (do-not-flag), `P11`, `P12` | dispositions fold back into `P10` / `P11`; `gaps.md` |
| `review-gap-attributor` | the whole plan + `P9` results + the final findings | nothing (read-only; the skill writes `gaps.md`) |
| `work-plan.ps1` | `P4`, `P6`, `P7`, `P8`, `P12`, `gaps.md` | scaffold only |

**A plan states the *intended* contract, not verified fact.** It predates the code and may describe behaviour the diff never implements — deciding that is the review's job. Without this posture the plan launders the author's framing into the review's voice, which [`review-conventions.md`](review-conventions.md) names as the one thing a reviewer is there not to do, and it contradicts `code-reviewer`'s standing rule that *a PR's own root-cause account is a claim*.

## Settings — `.claude/plans/config.json` (gitignored, per user)

Two settings, asked once on the first planning session that needs them and persisted thereafter. [`../skills/work-plan/SKILL.md`](../skills/work-plan/SKILL.md) → step 7 owns the prompting.

**This file is gitignored and never committed.** It records one person's choices, not a project fact — the same reasoning that keeps `settings.local.json` and `CLAUDE.local.md` out of the repo. Every clone starts without it and gets the first-run prompt. The **plans** themselves (`plans/<key>/plan.md`) are the shared artifact and stay tracked; only the settings are personal.

```json
{
  "criticModel":  { "claude-code": "fable" },
  "criticTiming": "before"
}
```

| Key | Values | Meaning |
|---|---|---|
| `criticModel` | keyed by **host tool**; each value is a model id, `never`, or `ask` | Whether the critic runs, and on what. A model id must be a different family from the author's — that difference *is* the mechanism. Keyed per tool because the available models differ. |
| `criticTiming` | `before` \| `after` \| `ask` | When the critic runs relative to presenting the plan. Not keyed by tool: a workflow preference, not a capability. |

**`criticModel` carries three answers, not one:**

| Value | Effect |
|---|---|
| a model id (`fable`, …) | Dispatch `plan-critic` on that model, every Tier M/L plan. The recommendation. |
| `never` | Never dispatch. Every Tier M/L plan records `waived-by-user: criticModel=never (standing config)` in `P12`, and the skill says so when presenting. |
| `ask` | Ask per run — model, or skip this one. No standing commitment; one extra question each planning session. |

**`never` is a standing waiver, and the waiver line is what makes it visible.** This file is gitignored, so a reader of the plan — the user weeks later, `/review-pr`, `review-gap-attributor` — cannot see the setting. The `P12` line is the only place the skip is recorded, which is why it is still written per plan rather than inferred from the config. `never` does **not** license a self-critique in its place: the author attacking its own plan is not a verdict under any setting.

**`criticTiming`:** **`before`** (recommended) runs the critic first, so the user only ever sees a plan with the verdict folded in and approves knowing the strongest case against the design. **`after`** presents first so the user can kill an approach before a critic pass is spent — at the cost that the first approval is provisional and must be re-earned once the verdict lands. **`ask`** decides per run. It is moot under `criticModel: never`, so don't prompt for it.

Neither setting applies at Tier S, where no critic runs.

## Gap classes — closing the loop back to the plan

A review finding is also evidence about the *plan*. After a review's findings are final, [`review-gap-attributor`](../agents/review-gap-attributor.md) attributes each one to the upstream artifact that would have prevented it and writes `.claude/plans/<key>/gaps.md`. This is what makes review rounds converge **across** PRs rather than only within one — the rest of the mechanism sharpens a single branch, this is the only part that feeds back.

| id | Class | What was missing | Durable home for the fix |
|---|---|---|---|
| `GAP-01` | unstated requirement | `P1`/`P2` never named the behaviour the finding requires | the readiness gate; sometimes a new rule |
| `GAP-02` | unverified assumption | `P4` didn't ask; the plan asserted it | the scout brief / probe discipline |
| `GAP-03` | impact-map miss | a caller, mirrored provider site, type-keyed helper or wire shape `P7` never searched | the scout brief; a new `G-nn` when the shape recurs |
| `GAP-04` | wrong altitude | correct code at the wrong layer — a flag, mapping-schema registration or `Sql.Extension` already expressed it | `P5` — the altitude question wasn't asked |
| `GAP-05` | missing test obligation | no `TO-n` covered the path, or the one that did couldn't go red | `P8`; [`testing.md`](testing.md) when the shape recurs |
| `GAP-06` | convention not applied | the rule was embedded in the plan's baseline and violated anyway | the rule needs a do/don't example |
| `GAP-07` | convention not embedded | the rule exists but step 4 didn't put it in front of the author | the skill's embed step |
| `GAP-08` | gate not run | a `G-nn` would have caught it and was skipped, or recorded `fail` and ignored | `P9` derivation, or [`definition-of-done.md`](definition-of-done.md) |
| `GAP-09` | amendment not logged | code went outside `P6` with no `P11` entry | `-Reconcile` should have failed — find why it didn't |
| `GAP-10` | unpreventable | information that did not exist at plan time | nothing — this is the honest floor |

Two outcomes that are **not** gaps, reported as themselves rather than forced into a class:

- **`not-a-gap: reviewer-disagrees-with-P10`** — the finding contests an adjudicated entry. That is a legitimate finding *about the adjudication*, not a planning failure.
- **`not-a-gap: out-of-plan-scope`** — the finding concerns code `P7` deliberately marked `deferred:` or `out-of-scope`, **with a reason**. A deferral with no reason *is* a gap (`GAP-03`).

**Attribute to the earliest artifact in the chain, not the last.** A gate that would have caught something but was driven off a plan block that lacked the entry is `GAP-03`, not `GAP-08` — the gate could not catch what the map never listed, so the durable fix belongs in the scout brief rather than the gate.

**`GAP-10` is the calibration signal, not a dumping ground.** Use it only when you can name the information that did not exist at plan time. A dominant `GAP-10` means the design pass is not earning its cost, and the right response is to say so and **cut the ceremony** — not to defend the machinery.

**These rules bind at *authoring* time, so a rule added after a plan was written governs nothing already in it — and a recurrence check that ignores that reads the wrong lesson.** A ledger's continuity section asks whether a prior round's recommendation was applied, and "the same defect recurred" is not the answer: the recommendation may have been codified here *and* the branch's own `P8` never re-expanded, because the plan predates the rule. The two readings prescribe opposite fixes — one says adopt the rule, the other says re-walk long-lived plans against rules added since — so **read the destination file before writing either.** A `Grep` of this doc for the recommendation's own wording is the whole check. Where the rule did land and the defect still recurred, the durable fix is a re-walk of the plan's `P8` and `P4` against the current rule set, recorded as a `P11` amendment. (Surfaced on [#5870](https://github.com/linq2db/linq2db/pull/5870) round 2, whose ledger asserted that both round-1 recommendations went unapplied. One had been — as the `P8` enumerated-set rule above, which cites that very round as its source — and the defect recurred anyway because the plan was already written. The other genuinely had not, and the two needed different responses.)

## Backtesting the mechanism

The honest way to ask "does this pay for itself?" is to run it against a PR whose review history is already known: author a plan blind, critique it, and count how many of the real findings it would have carried. `gaps.md` measures the same thing prospectively; a backtest measures it on evidence you already have.

**A merged PR's body is a retrospective, not a brief — never use it as blind input.** This is the trap that invalidates the experiment, and it is invisible unless you look for it: a PR description is *edited during review*, so by merge time it routinely contains a "response to review" section, a release-notes block a finding asked for, and a defect list written **after** the review found them. Feeding that to a blind planner hands it the answers, and the resulting plan reproduces them almost verbatim while looking like a discovery.

Checking the body for leaked *implementation* details — internal type names, new APIs — does **not** catch this. Those can be absent while every defect the review found is stated in prose.

Use instead, in order of preference:

1. **The branch's first commit message**, plus the linked issue body. Both predate review, and the commit message carries the author's intended approach — including whatever about it later turned out to be wrong, which is exactly what you want the plan to have a chance at catching.
2. **The linked issue alone**, when no pre-review commit survives. A harder test, and the resulting plan may design something different from what shipped, which makes finding-by-finding scoring approximate.

**A squash-merged PR preserves no pre-review commit**, so option 1 is unavailable for one — check `git log <base>..<merge>` before planning the run rather than discovering it mid-experiment.

Verify the brief before dispatching: grep it for the review's finding ids, for "response to review" / "review round" headings, and for the specific defects you intend to score against. Zero hits, or the run is void.

(Established 2026-08-31: a two-case backtest of this mechanism was reported as catching the Blocker and most Majors on both PRs, then found invalid — one body named findings by id with their refutations, the other stated the whole defect list and carried the release-note line a finding had requested. The one result that survived was a *negative* one, which contamination could only have helped: both the plan and the critic swept `switch`/`case` sites, declared the map complete, and missed a type-keyed helper anyway.)

## No plan on the branch

External-contributor PRs, and any branch predating this mechanism, have no plan. **"No plan" is a first-class valid state.** Every consumer degrades to its previous behaviour: `/review-pr` falls back to the hand-typed scope sentence, and nothing reports an error.
