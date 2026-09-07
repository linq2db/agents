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

## Round 2 — reviewed HEAD fedd126dfaa83c860ac42f4ac5facea70b7eeb0f

15 findings (12 MIN / 2 SUG / 2 NIT by posted id, one of them promoted from an out-of-scope
observation) against the same Tier-M plan after round 1's fixes landed. The plan now carries twelve
`P11` amendments; A-1…A-8 are the artifacts round 1 produced and A-9…A-12 are this round's fixes.
**Seven of the fifteen attribute to A-3, A-7 or A-8** — code written during round 1's own fix pass,
after `P12` had finished attacking the design and after `P9` was recorded, so none of it passed
through a critic, a probe row, a `TO-n` or a gate.

### Attribution

- **MIN011** — GAP-02 — `P11` A-3, an artifact that did not exist at plan time. A-3 replaced `D-4`'s per-call-site netfx reading with `_netFxRoundingPossible = timeSpan.GetMembers("FromMicroseconds").IsEmpty` on the asserted premise that "that member and the switch from whole-millisecond rounding to tick truncation both arrived in .NET 7". `P4` U-1 is the plan's *probe* row for exactly this BCL question, and it asked whether modern .NET truncates — reading `dotnet/runtime` `System/TimeSpan.cs` at tip — never *since which version*, so the amendment re-asserted from recall a fact the plan had already established the discipline for. Which gate the amendment skipped: all of them. A-3 introduced a new per-compilation capability marker with no `P4` row behind it, no `TO-n` in front of it, and no critic pass, because `P12` closed before it existed. Not a re-raise of MAJ001's disposition — MAJ001 attributed to `D-4`'s uncomputed loss set, and A-3 is its fix carrying the same defect forward on net5.0/net6.0. — preventable: yes
- **MIN012** — GAP-02 — `D-5` states its invariant over "**every** `[Duration]` on the member" and specifies the collection as an `IPropertySymbol.OverriddenProperty` walk, without ever establishing how linq2db assembles that set; the invariant is only sound if the set is complete. `P4` U-2 asked the narrower question (can more than one attribute reach a member) and stopped one hop short of the site it cited: `MappingSchema.GetAttribute<DurationAttribute>` resolves through `MappingAttributesCache.GetMappingAttributesTreeInternal`, which concatenates the member's own attributes with its interfaces' (`:85`) and its base's (`:103`). Second class with the same durable home: `P7` row 4's declaration-route sweep was scoped to `Source/LinqToDB/Mapping` while that file is `Source/LinqToDB/Internal/Mapping/MappingAttributesCache.cs`, so the search path structurally excluded the semantics `D-5` reasons over. — preventable: yes
- **MIN013** — GAP-05 — the control is `P11` A-7's own, added in round 1 to pin the type-check hazard A-7 discovered while widening `GetDurationAttributes`. No `TO-n` row was written for it and no red arm was recorded, so nothing required the tag constant to be a value the compared duration *cannot* represent — the one property that makes the snippet discriminate. The omission is specific rather than systemic: A-7 recorded a red arm for its sibling test in the same entry, so the discipline was in hand and applied to one of the two tests the amendment shipped. `G-01`'s recorded red arm cannot see this — mutating `IsBlocked` reddens the positives, never a control. — preventable: yes
- **MIN014** — GAP-05 — `D-6`'s six reportable table entries against `P8` `TO-1`/`TO-2`, which name units only as `SC-3` happens to list them; `Day` was the last `TryGetUnit` arm with no assertion anywhere, and `P7` row 15's census (`Day` ×1, declared fluently) makes it structurally unreachable by `TO-5`. **This is round-1 MIN003 recurring one row further along the same table**: round 1 fixed the `Microsecond` row and did not sweep the rest. Round 1's `GAP-05` recommendation, now `work-plan.md:112`, covers this outright — one `TO-n` per member of the unit table would have produced a `Day` row. — preventable: yes
- **MIN015** — GAP-05 — `P8` `TO-2` against `D-8`'s fourth rejected alternative, which names four escape shapes; the fourth (mutation through the local) still has no test, and `OnlySafelyEnumerated`'s refusal was reached by nothing in the fixture. Round 1's recommendation reaches this finding and then **releases it**: `work-plan.md:112` permits "an explicit line naming which members are unexercised and why", and A-4 used exactly that clause with a reason pointing at *code* — "it is the array case A-2 covers" — where A-2 covers the array local's *resolution* path and not its *refusal*. A-4's other half is the correct use of the same clause (`IAddressOfOperation`, unexercised because `&bound` on a captured local is `CS1686`). The distinction the wording is missing is that the reason must be an impossibility or a named test, never another code path. — preventable: yes
- **MIN016** — GAP-05 — `P11` A-3's own recorded-and-unclosed gap: "**Not covered by any test leg:** `Tests.Analyzers` compiles every snippet against `ReferenceAssemblies.Net.Net80` … Closing that needs a second reference set on the E-6 verifier." A-3 is what created the dead branch — before it, the netfx reading applied to every compilation, so the fixture did exercise it and there was no factor to vary; making it per-compilation turned `_netFxRoundingPossible` off in every leg. `P11` semantics let an amendment record an open test gap with neither a `TO-n` nor a `P10` disposition, so nothing adjudicated it between rounds and it reached review as a finding rather than as a declared limitation. Round 1's recommendation covers it partly — `D-4`'s three readings are an enumeration, so a row per reading would have obliged the netfx-shaped leg A-9 eventually built. — preventable: yes
- **MIN017** — GAP-01 — `E-1` specifies the descriptor by field list and nothing anywhere requires the descriptor's `title`/`description`, or the type's XML summary, to satisfy `SC-2` — the criterion that states the `!=` contract and its nullable qualification. The tell that this is a specification defect and not two slips: round-1 MIN008/MIN009 corrected the same wrong claim in both readmes and left the copy those rows are written from untouched. Round 1's `GAP-01` recommendation landed as `work-plan.md:85` and lists "a help string" as in scope, but exempts prose that lives inside a code edit-point, which is precisely where this prose lives — so it would have fired at `E-3`/`E-5`, where the round-1 fix already went, and not at `E-1`. The rule that should exist: the descriptor's title/message/description is the single upstream copy every downstream doc row is derived from, so an `E-n` creating one names the `SC-n`s it must jointly cover. — preventable: partly
- **MIN018** — GAP-06 — the convention was in the plan's always-loaded baseline and was cited by name in the amendment that violated it. `P11` A-8 added check 5 and proved it red by adding an id present in the release-tracking file and absent from the readmes — varying the *id source*, never the artifact the check exists to protect. `agent-rules.md` → *To prove an existing test cannot fail, inject the defect it claims to cover and re-run it unchanged* is the rule; A-8 quoted its neighbour instead (*a green run over an input set you assembled yourself is not evidence*), so the expensive half of the discipline was satisfied and the cheap half skipped. The do/don't example this needs: for a **coverage** gate the red arm deletes the covered row, it does not add an uncovered id. — preventable: yes
- **MIN019** — GAP-09 — the wiki page has no `E-n` (round-1 MIN007 already recorded that `P6` carries none) and no `P11` entry, while `P10`'s final entry takes a dependency on its content — "The wiki says the rule assumes a linq2db queryable … Not a gap to file." Why a reconcile pass could not stop it, which is the actual defect: the artifact is in a **different repository** (`linq2db.wiki`), so it can never appear in the branch diff such a pass reads — there is no path filter to widen and no ordering to fix — and the qualifier existed only as an uncommitted edit in that clone. Its repetition of MIN011's false boundary is a downstream copy of that finding, not a second gap. — preventable: partly
- **SUG005** — GAP-02 — `P11` A-7 widened `GetDurationAttributes` from an exact `AttributeClass` match to a `BaseType` walk, then re-derived exactly one of the two reads of the attribute application it had thereby loosened: `UnitMemberName` was type-checked against `DurationUnit` (A-7 records both the hazard and its test), while `HasConfiguration` kept reading `NamedArguments` only. The assumption — that admitting subclasses affects only the unit read — was checkable by enumerating the file's own reads of `AttributeData`, of which there are two, and the failure direction is the worse one: an unreadable unit degrades to silence, an unreadable `Configuration` degrades to a report. A-11 records the fix and that the obvious remedy was refuted by the suite. — preventable: yes
- **SUG007** — GAP-02 — `P11` A-8, with the assumption written down at the site: `Get-ShippedRuleIds` comments "the header and the `;`-prefixed preamble never match, so no row filtering beyond the id shape is needed" above a scan of every line matching an id followed by a pipe. The format A-8 harvested ids out of is the analyzer-release-tracking format RS2000/RS2001 define, which has `### Removed Rules` and `### Changed Rules` sections beside `### New Rules` — one read of that format settles whether section filtering is needed, and the amendment asserted the answer instead. — preventable: yes
- **SUG008** — GAP-05 — `P8` `TO-3` declared a proof mode it cannot deliver: "**control** (same source, reference set varied)". Every source that would report references linq2db for `[Duration]` itself, so removing the reference removes the *trigger*, not one factor — the declared control is unwritable, which the finding confirms. That the same row already dropped its other leg as unconstructible is the signal the proof mode needed rewriting rather than half-substituting; what shipped is a snippet with no member reference at all, silent with linq2db too. Second class, and the reason the substitute passed unexamined: `P9`'s `G-01` is recorded as a run total where `work-plan.md:110` requires one row per obligation with the observation proving it ran — round 1 attributed MIN004 to that same weakening, and the record was never re-derived, only re-run. — gate: G-01 — preventable: partly
- **SUG009** — GAP-05 — `D-5`'s "Walk `IPropertySymbol.OverriddenProperty` so an attribute on a base declaration is seen (`Inherited = true`)" is a named mechanism with no `TO-n` anywhere: `P8` `TO-1`/`TO-2` enumerate constant shapes, units, and configuration scoping, and never an inherited declaration — so stubbing the walk left the whole fixture green. Round 1's recommendation does **not** reach this: `work-plan.md:112` makes an *enumerated set* an obligation checklist, and this is a lone clause in a decision. The widening it implies is the `P8` counterpart of the existing "every `E-n` maps to at least one `TO-n`": every mechanism a `D-n` names, enumerated or not, needs an obligation or an explicit unexercised line. Overtaken mid-round by MIN012's own fix (`DoesNotReportWhenDeclaredUnitsDisagreeAcrossAnOverride`, A-10), which exercises the walk incidentally — confirming the gap was the obligation and not the edit, since the code was correct throughout. — preventable: yes
- **NIT001** — GAP-06 — `P11` A-8's new `-RepoRoot` default, `(Join-Path $PSScriptRoot '..\..\..')`, against the always-loaded convention that these scripts have "identical behavior on Windows / macOS / Linux" (`agent-rules.md` → *PowerShell Core scripts for complex operations*) — embedded by construction, violated anyway. No gate applies and none was skipped: `nuget-job.yml` passes only `-PackagesDir` and runs on a Windows pool, so CI is green on either spelling. The rule needs its do/don't example, and `script-authoring.md` — the authoring contract these scripts are held to — carries no path-portability clause at all today: multi-segment `Join-Path $PSScriptRoot '..' '..' '..'`, never a `'..\..\..'` literal segment. — preventable: partly
- **NIT002** — GAP-01 — `E-3` authorizes "diagnostics-table row plus a short `### L2DB1002` section", specifying position and not content, so a route list omitting one of `D-8`'s four resolution rules — the LINQ range variable, the one A-1 rewrote — satisfies the plan as written. Round 1's `GAP-01` recommendation covers this outright: `work-plan.md:85` now requires an `E-n` on user-facing documentation to name the `SC-n`/`D-n` it restates, and a section derived from `D-8`'s four bullets cannot omit one of them. — preventable: yes
- **PROMOTED-OOS** — GAP-02 — `D-3` enumerated the recognized shapes as "`new TimeSpan(...)` (all ctor overloads), `TimeSpan.FromTicks`, the `From*(double)` factories, `TimeSpan.Parse`/`ParseExact` …" — an enumeration of a BCL surface written from its remembered shape, against which the .NET 9 component arities were already shipped and public at plan time, including a `FromMilliseconds` with no single-parameter integer form. `P4` has no row asking what overloads each named factory carries on the newest supported target. Round 1's `GAP-02` recommendation covers this exactly: `plan-critic.md:48`'s third shape is "for a shape recognised by **method name**, enumerate that method's overloads and ask whether any carries an argument that changes the value". The CS0854 narrowing A-12 records (an expression tree may not use an optional argument, so only fully specified component calls are reachable) was knowable from the same enumeration and would have reduced the obligation rather than widened it. — preventable: yes

*Withdrawn before finalization, not attributed:* a `decimal` overflow in `FromScaledArgument`,
unreachable because `FromDays`/`FromHours` take `int`. `D-3` already bounded this — "checked
arithmetic, bail on overflow" — and the code implements the bound, so the plan block was right and
there is no gap to record.

### Aggregate

The class distribution is `GAP-02` ×5, `GAP-05` ×5, `GAP-06` ×2, `GAP-01` ×1, `GAP-09` ×1 — the same
two dominant clusters as round 1 (`GAP-05` ×6, `GAP-02` ×4), so the *kinds* of gap are stable. What
moved is the **artifact**: seven of fifteen attribute to a `P11` amendment written during round 1's
own fix pass — A-3 (MIN011, MIN016), A-7 (MIN013, SUG005), A-8 (MIN018, SUG007, NIT001) — where round
1 had none. This is not a new gap class; it is the existing classes arriving through a stage with no
machinery. An amendment gets no `P4` probe row for the facts it rests on (A-3's ".NET 7" boundary), no
`TO-n` for the controls and gates it adds (A-7's tag control, A-8's check 5, neither of which could
fail), no `P7` re-sweep of the sites its widening touches (A-7's second read of `AttributeData`), and
no critic pass, because `P12` closed before the amendment existed.

The single change that would have prevented the most of these is therefore a `P11` sub-schema: treat
an amendment that introduces a new mechanism, capability marker, control or gate as a plan in
miniature and require the same three artifacts of it. That covers seven findings. The next-largest
lever is not a new rule at all but a wording fix to one already in the corpus — `work-plan.md:112`'s
"or an explicit line naming which members are unexercised and why", which A-4 satisfied with a reason
pointing at another code path and which is the only thing standing between MIN015 and prevention.

The plan-block half of the round divides cleanly: `D-5` was under-specified about the *set* its
invariant runs over (MIN012) and unobliged about the mechanism it names (SUG009); `D-3` and `D-6`
enumerated surfaces and left members unpinned (PROMOTED-OOS, MIN014); `E-1` and `E-3` specified
user-facing prose by position (MIN017, NIT002); and `TO-3` declared a control that cannot be built
(SUG008).

`G-01` is the one gate implicated, and for the second consecutive round in the same form — but the
defect is staleness, not a wrong figure. Its `P9` record reads `total: 86, failed: 0`, which was
accurate when taken at `efd843e5`; the suite reported **114** at `fedd126d` (CI's `Analyzer tests`
leg on the reviewed HEAD) and **125** at `35997639a`. The rule at `work-plan.md:110` forbids a run
total precisely because a total cannot go stale *visibly* — a per-`TO-n` row would have had to be
re-derived when the fixture grew, and a total merely reads as an old number nobody re-ran.

### Recommended durable fixes

Route to `/session-reflect`'s `plan-rule` bucket — not applied from inside the review.

- **GAP-02 ×3 + GAP-05 ×2 + GAP-06 ×2 (7 findings, every one a `P11` amendment)** → `P11` semantics
  in `.claude/docs/work-plan.md`, generalising the corollary round 1 already added at `:112`. That
  corollary covers one shape (a control whose discriminating factor an amendment moved); the three
  round-2 shapes need the same treatment. **An amendment that introduces a new mechanism, capability
  marker, control or gate carries the plan's own three artifacts in miniature:** (1) a probe row for
  every factual claim it rests on, cited to the artifact read — A-3 asserted a runtime version
  boundary that `P4` U-1 had already established the discipline for, and got it wrong by two major
  versions; (2) a `TO-n` with a demonstrated red arm for every control or gate it adds — A-7's control
  and A-8's check 5 both shipped unable to fail; (3) a re-derivation of every sibling read, control or
  doc row the widening touches — A-7 type-checked one of two `AttributeData` reads. Corollary for the
  baseline: when an amendment widens `P6` into a file class the plan's embedded conventions never
  covered (a pwsh script, here), embed that class's conventions before editing (NIT001).
- **GAP-05 ×3 (MIN014, MIN015, SUG009)** → tighten the existing `work-plan.md:112` rather than add a
  fourth rule: (a) the escape clause must name an **impossibility** (a compile error, an
  unconstructible shape) or a **test**, never another code path that "covers" the shape — this is the
  only round-1 recommendation round 2 shows actively defeated; (b) the checklist applies to every
  mechanism a `D-n` names, not only to enumerated sets, which is what left `D-5`'s
  `OverriddenProperty` walk with no obligation; (c) fixing one member of an enumeration obliges a
  sweep of the rest, since MIN014 is round-1 MIN003 one table row along.
- **GAP-05 (SUG008) + round-1 GAP-08 (MIN004)** → `definition-of-done.md`'s `G-01`, plus a `P8`
  clause. `work-plan.md:110` already forbids recording `G-01` as a run total and this plan's `P9` did
  it twice, so the missing half is the re-run rule: **re-recording `G-01` after a review round means
  re-deriving the per-`TO-n` rows, not re-pasting the total** — a stale total is what let a
  non-discriminating control stand as `TO-3`'s proof. And in `P8`: a `TO-n` whose declared proof mode
  turns out undeliverable is **amended in `P8`** (as `TO-3` correctly did for its second leg), never
  silently substituted at the fixture.

## Continuity — round 1 → round 2

All three of round 1's recommended durable fixes were applied to the corpus, each carrying a #5873
backtest note: the `GAP-05` checklist plus its `P11` corollary at `.claude/docs/work-plan.md:112`, the
unstated-failure-surface attack vector at `.claude/agents/plan-critic.md:48` (whose worked example is
`D-4`'s three readings), and the user-facing-documentation rule at `.claude/docs/work-plan.md:85`. They
landed *after* the round-1 fix commits they would have governed, so this round measures their reach
rather than their enforcement.

Measured against the fifteen: **three would have prevented the finding outright** — MIN014
(`work-plan.md:112`, one `TO-n` per unit-table row), NIT002 (`work-plan.md:85`, a readme section
derived from `D-8`), PROMOTED-OOS (`plan-critic.md:48`, "enumerate that method's overloads").
**Two partly** — MIN016 (`:112` applied to `D-4`'s three readings obliges a leg per reading, which is
the leg A-3 recorded as missing) and MIN012 (the attack vector's spirit reaches it, but none of its
four named shapes asks whether a *set* the design quantifies over is complete). **One was reached and
then released** — MIN015, by `:112`'s own "unexercised, and why" escape clause; that is the one wording
change round 2 demands of a round-1 rule. **One is exempted by design** — MIN017, because
`work-plan.md:85` covers "a help string" but excludes prose sitting inside a code edit-point, which is
where the descriptor's title and description live.

**Nine were out of reach**, and for two distinct reasons worth separating. Seven (MIN011, MIN013,
MIN016's residue, MIN018, SUG005, SUG007, NIT001) are amendment-shaped: every round-1 recommendation
attaches to a `P1`–`P8` block, and a mid-round `P11` entry bypasses all of them — which is why the
first durable fix above is a `P11` sub-schema rather than another plan-block rule. The remaining two
are plan-block findings the recommendations simply do not describe: SUG009 (a lone named mechanism is
not an enumerated set) and SUG008 (whose second class is `G-01`'s run-total recording, a rule already
in the corpus at `work-plan.md:110` and violated in this plan's `P9` across both rounds).

Round 1's ledger closed with "only **one** finding traces to a gate". Round 2 adds a second at the
same gate and in the same form, and the sharpest continuity signal is what happened in between: the
`G-01` figure was named as a defect in round 1, the suite then grew from 86 cases to 114 to 125, and
the record still reads `total: 86, failed: 0`. Nothing re-derived it, because a total has no rows to
re-derive.
