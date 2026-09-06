# Review gap ledger: issue-5779-analyzer-duration-comparison

Produced by `review-gap-attributor` (dispatched from `/review-pr`). Attributes each finalized review
finding to the upstream artifact that would have prevented it. Not a re-review — it does not argue a
finding is wrong and does not propose a different fix.

## Round 1 — reviewed HEAD efd843e5f5a701f5afd59119d6039b259a7ff817

15 findings (1 MAJ / 10 MIN / 4 SUG) from three parallel `code-reviewer` passes plus one audited
prior-review claim, against a Tier-M plan whose every declared `P9` gate passed — including a
mutation-based red arm on the test suite and a `TO-5` dogfood that matched its pre-declared 7-site
expectation exactly.

### Attribution

- **MAJ001** — GAP-02 — `D-4` asserted its own loss set ("sub-millisecond `double`-factory constants … not diagnosed") without computing what the three-reading union does per declared unit; the netfx reading it specifies is `(long)millis * TimeSpan.TicksPerMillisecond` (`:534-539`), i.e. ≡ 0 mod 10 000 **by construction**, so `IsRepresentable`'s any-of-three test (`:104-107`) is unconditionally true for every `perUnit` dividing 10 000 — one line of arithmetic at plan time, in a `P4` with eight rows none of which asks it. `P12` records the critic probing `D-4` only in the false-**positive** direction ("the ±1-tick drift … cannot produce a false positive"). The `FromMicroseconds` half is a genuine divergence from `D-4`'s "not applied to … `FromMicroseconds`/`FromNanoseconds`" (`FactoryScale` at `:495` routes it with `allowDouble: true`), but consequence (b) survives that divergence being fixed, so the earliest artifact is the decision, not the edit. Not a `P10` dispute: `P10`'s entry adjudicates the sub-millisecond class only. No gate could see it — `P7` row 16 shows the four compared members are `InSeconds`/`InTicks`/`Grace`/`Budget`, so `TO-5`'s corpus contains no Millisecond- or Microsecond-declared comparison at all. — preventable: yes
- **MIN001** — GAP-05 — `D-8`'s fourth rejected alternative names **four** escape shapes (`IDeconstructionAssignmentOperation`, `IAddressOfOperation`, an `ILocalSymbol.IsRef` local, mutation through the local) and `P8` `TO-2` turned exactly **one** of them into a control ("a local reassigned by deconstruction"). `IsPlainRead` (`:785-800`) handles precisely that one — the tuple walk at `:789-791` — and ends `_ => true`, so the obligation set cannot distinguish the shipped denylist from the allowlist `D-8` adopted. The plan block is right and the code diverges; the earliest artifact that could have made the divergence impossible is the missing per-shape obligation, not the code. (`P11` A-2's `OnlySafelyEnumerated` at `:806` shows the author could write the allowlist when an obligation — `ReportsRangeVariable` — forced it.) — preventable: yes
- **MIN002** — GAP-02 — `D-2` assumed "inside an `Expression<T>`" implies "a translated column", stated its failure mode as false-negatives-only ("A false negative, not a false positive"), and `P3` simultaneously demands "no false positive at any cost in recall"; no `P4` row asks what else can sit under an expression-tree lambda holding a `[Duration]` member, and `GetReferencedMember`/`TryReport` (`:172-181`) tests nothing about the reference's root. `P12` objection #1 was "made moot rather than adjudicated" and `D-2` is recorded as unprobed, so the assumption entered approval unexamined. The wider boundary (any expression tree, not just a linq2db query) is inherent to the design the user chose, which is why this is partly rather than fully preventable. — preventable: partly
- **MIN003** — GAP-05 — `D-6`'s table has six reportable entries and `P8` `TO-1`/`TO-2` name units only as they appear in `SC-3` (`Second`, `Millisecond`, `Tick`, `Nanosecond`); nothing obliges one assertion per table entry, so `Microsecond` — the single entry whose ratio is a hand-rolled literal (`TicksPerMicrosecond = 10L`, `:30`, against five `TimeSpan.TicksPer*` reads at `:336-341`) — has no test and no corpus instance (`P7` row 15 lists no `Microsecond` member). `G-01`'s mutation red arm reddened 17 positives and still could not see an absent unit. — preventable: yes
- **MIN004** — GAP-08 — `P8` `TO-2` names "a `foreach` over a non-constant collection" and no test implements it; `P9` records `G-01` as `dotnet test … total: 86, failed: 0` plus a mutation arm, i.e. a **run total**, where `work-plan.md` → `P9` requires "one row per `TO-n`, naming the test method — a run total is not evidence about an obligation". The gate was applicable, run in a weakened form, and the missing control is the one pinning the `List<T>`/method-call refusal the code documents as deliberate (`:680-683`). — gate: G-01 — preventable: yes
- **MIN005** — GAP-05 — `P8` `TO-2`'s second critic-added control was written as "a two-parameter LINQ lambda (**`Zip`**, or a `Join` key selector)" against `D-8`'s *ordinal-0* rule; `P11` A-1 then replaced that rule with the `IsElementSelector` name allowlist (`:743-755`), from which `Zip` is deliberately absent — so the control as written passes with or without the `Parameters.Length != 1` guard it is named for. A-1 added `DoesNotReportInnerKeySelectorParameter` for the `Join` case but did not re-derive the sibling control whose discriminating factor it had just moved. — preventable: partly
- **MIN006** — GAP-05 — `D-3` enumerates ten constant shapes and `P8` `TO-1` writes positives for six of them; `ParseExact`, `MinValue`, binary `-`, unary `-` and four of five constructor arities have no obligation, although `D-3` calls operator folding "load-bearing, not a nicety" and binary `-` is what two of the seven `TO-5` dogfood sites (`Queries.cs:821`/`:822`) rest on — leaving them proven only by one manual characterization run. — preventable: yes
- **MIN007** — GAP-01 — no `SC-n` requires the user-facing exclusion list to restate `D-4` with its qualifiers, `P6` carries no `E-n` for the wiki page, and `P10`'s own restatement — "Sub-millisecond `double`-factory constants are not diagnosed" — drops the "against a `Millisecond` column" qualifier that `D-4`'s failure-mode line carries; the wiki bullet mirrors the lossy summary. The rule that should exist: a `P10` entry summarising a `D-n` failure mode must not widen it, and any prose restating a decision names the `D-n` it must agree with. Not out-of-plan-scope: `P10`'s wiki entry defers the page's *creation*, not its content. — preventable: partly
- **MIN008** — GAP-01 — `SC-2` states the `!=` contract (including the nullable qualification) but `E-3` authorizes only "diagnostics-table row (`:26`) plus a short `### L2DB1002` section" and names a content requirement solely for the *intro prose*; a row describing `==` alone therefore satisfies the plan as written. No obligation, and nothing in the build compares the two diagnostics tables to anything. — preventable: partly
- **MIN009** — GAP-01 — same missing requirement at `E-5` (`Source/LinqToDB/readme.md:700`), which `P7` row 7 correctly classified as "silently omissible docs" and then covered with an edit-point that specifies position, not content. That both readmes carry the identical wrong sentence is the tell that the defect is in the row's specification, not in two independent slips. — preventable: partly
- **MIN010** — GAP-06 — the falsified-comment rule (`agent-rules.md` → *the mirror applies to your own changes*) was embedded in the plan's baseline and cited by name inside `E-3` ("Leaving the prose is the mirror of the falsified-comment rule"), then applied to the two readmes and not to the header of the file `E-6` itself edits (`AnalyzerVerifier.cs:13-15`). `G-06` passed correctly — it checks unrelated reformatting/renames, not whether a comment is still true. — preventable: partly
- **SUG001** — GAP-02 — `D-3` names `Parse`/`ParseExact` by method name and its failure-mode line considers only culture sensitivity; no `P4` row or `D-n` clause asks which overloads of a recognized shape carry value-changing arguments, so `FromParse` (`:552-562`) reads arguments 0 and 1 and drops `TimeSpanStyles`. The same enumeration discipline exists in the shipped code for the factories ("Only the single-argument overloads are folded", `:500-501`) but no plan row required it here. — preventable: partly
- **SUG002** — GAP-02 — `D-8`'s "an inline `IArrayCreationOperation` (**or collection-expression literal**)" clause was never checked against `P3`'s own Roslyn-4.8 constraint, which the plan *did* apply to the neighbouring case (`ImmutableArray.Create(...)` not collection expressions, `P3`). `P4` has no row for it, so the plan asserted a shape whose availability on the pinned surface is still unsettled and the implementation silently narrowed to the array arm (`:680-683`). The divergence is real, but the clause it diverges from was itself unverified, which is the earlier artifact. — preventable: partly
- **SUG003** — GAP-05 — `D-2`'s failure mode says "should the parent chain interpose a node the walk does not expect, the rule degrades to silence — `TO-1`'s expression-tree positives are what prove it fires at all", yet `P8` `TO-1` enumerates constant shapes and member shapes and never enumerates the *positions* an `Expression<T>` conversion can occupy, so every positive reaches the gate through an argument. The one decision `P12` records as resting on reasoning rather than observation is the one whose obligation is position-monoculture. — preventable: yes
- **SUG004** — GAP-05 — `SC-1`/`SC-2` define an outcome matrix (operator × nullability × mixed-vs-total candidate set) and `P8` `TO-1` obliges no assertion per cell; `P9`'s `TO-5` record notes the dogfood "exercised all four `Outcome` branches on real code", which is how a characterization run came to be the only evidence for wordings the fixture never asserts. — preventable: yes

### Aggregate

The dominant class is `GAP-05` (6 of 15), and it is concentrated on **enumerations the plan itself
wrote down and then never turned into obligations**: `D-3`'s ten constant shapes, `D-6`'s six-entry
unit table, `D-8`'s four named escape shapes, and `SC-1`/`SC-2`'s six-cell outcome matrix each became
one or two representative tests instead of a checklist — which is why a 35-test fixture with a genuine
mutation-based red arm was blind to all of them.

The second cluster is `GAP-02` (4), all one shape: a `D-n`'s *stated* failure mode was treated as its
*complete* failure surface, so `D-4`'s loss set was never computed per unit, `D-2`'s gate was never
asked what else satisfies it, `D-3`'s shapes were never expanded to overloads, and `D-8`'s
collection-expression clause was never checked against `P3`'s own Roslyn-4.8 constraint.

Only **one** finding (MIN004) traces to a gate, and not because a gate failed — `G-01` was recorded as
a run total where `work-plan.md` already requires one row per `TO-n` naming the test method; the other
fourteen were invisible to every gate this plan could have declared, and `TO-5`'s corpus structurally
cannot contain the MAJ001 shape at all.

Of the three implementation-divergence findings, MIN001 attributes to the obligation set (the plan
block was right and only a per-shape `TO-n` could have exposed the slip), while MAJ001 and SUG002
attribute to the decisions, because each survives its divergence being corrected.

### Recommended durable fixes

Route to `/session-reflect`'s `plan-rule` bucket — not applied from inside the review.

- **GAP-05 × 6** → a `P8` semantics addition in `.claude/docs/work-plan.md`, extending the existing
  "every `E-n` maps to at least one `TO-n`" rule: **an enumerated set inside a `D-n` is an obligation
  checklist**. A shape list, a ratio/unit table, a message/outcome matrix, or the escape shapes a
  *rejected alternative* names each need one `TO-n` row per member, or an explicit line saying which
  members are unexercised and why. Amendment corollary: a `P11` entry that moves a mechanism must
  re-derive every control whose discriminating factor it moved (MIN005).
- **GAP-02 × 4** → an attack vector in `.claude/agents/plan-critic.md`: attack a decision's *unstated*
  failure surface, not its stated one. For a guard that unions or intersects readings, name the inputs
  for which it is unconditionally satisfied; for a gate, name what else satisfies it besides the
  intended subject; for a shape recognised by method name, enumerate its overloads; for a clause naming
  a syntax/API shape, check it against the plan's own pinned-surface constraint. `P12` shows this
  critic probing `D-4`'s false-positive direction only.
- **GAP-01 × 3** → `P6`/`P10` semantics in `.claude/docs/work-plan.md`: an `E-n` on user-facing
  documentation (readme row, wiki page, help text) must name the `SC-n` or `D-n` it restates and is not
  satisfied by a position alone; and a `P10` entry summarising a `D-n` failure mode may not drop a
  qualifier the `D-n` carries, since the `P10` line is what downstream prose is written from.
