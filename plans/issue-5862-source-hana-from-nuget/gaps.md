# Gap ledger: issue-5862-source-hana-from-nuget

## Round 1 — reviewed HEAD 5ab7af3b9

## Attribution

- **MIN001** — GAP-01 — P6 `E-7` / `E-8` (plan.md:170-171) set the CLI text as "list v10.0 in the :287 error text" and "list `Sap.Data.Hana.Net.v10.0.dll` in the `--provider-location` help" with no TFM qualifier. Yet `E-7` itself puts the probe under `#if NET10_0_OR_GREATER`, and D-5 (plan.md:86,89) argues that a net8/net9 build "has no reason to probe it". No block said that user-facing text naming a TFM-gated capability has to carry the same gate. — — — preventable: yes
  - The contradiction sits inside one `E-7` line. The sibling string `E-9` (`McpInfoTool.cs:48`) came out qualified ("on .NET 10"), so the qualifier was available and got applied to one of the three strings only.
  - Secondary (GAP-05): `E-7`…`E-9` are waived from `TO-n` "verified by the Release build and by reading the diff" (plan.md:252). Neither check can go red on a wrong help string.
  - Critic side: `plan-critic.md:125` already says to check prose claims "against the plan's own `U-n`". It was not applied here. Round 1 objection 4 looked at `E-7`…`E-9` and only asked for a `TO-n` map.
- **NIT001** — GAP-10 — `Tests/Tests.Wasm/ProviderMatrix.cs` did not exist on the plan's base c82e21c35. It came in with the master merge of #6178 (head 5ab7af3b9), after P7 was swept, so no P7 row could have listed it. — — — preventable: no
  - The plan-time sweep (`Sap\.Data\.Hana|libadonetHDB|SapHana[\\/]|HANASTUBS`, P12 round 1) would have matched the row's "Sap.Data.Hana is a Redist assembly" text if it had been re-run on the merged head.
  - No step asks for that re-run. `Grep` of `master|merge` over `docs/work-plan.md`, `skills/work-plan/SKILL.md` and `agents/plan-critic.md` finds no post-merge P7 re-sweep rule. This was fixed in A-5 by adding `E-34` and the P7 row at plan.md:228.

## Aggregate

There are two findings, and they have nothing in common, so no single systemic fix covers both. MIN001 was a real design-pass miss. The plan had the TFM gate (D-5, `E-7`'s `#if`) and the prose specification side by side and never related them. A single cross-check of each P6 user-facing string against the `#if` gates and D-n decisions in the same plan would have prevented it. NIT001 is a true floor case at plan time, because the file it concerns arrived with a later master merge. A cheap re-run of the recorded P7 sweep after each merge would still have caught it before review.

The observation about D-11's wording comes from a `re-derives:` miss. A-3 finding 5 changed the handler's unsubscribe semantics (plan.md:318), but A-3's `re-derives:` line names P6 `E-26` and the P7 LINQPad row, not P5 D-11 (plan.md:323). So D-11's prose drifted from the code until A-5 reworded it.

## Recommended durable fixes

- GAP-01 × 1 → an attack vector in `plan-critic.md`: extend the existing prose-claim vector at `plan-critic.md:125` instead of adding a new one. Add a do/don't example saying that an `E-n` writing user-facing text (help, error message, readme) about a capability must be checked against every `#if` / TFM gate and D-n scope on that capability in the same plan, and that sibling strings in one group must agree. Example: `E-7` gated the v10.0 probe to `NET10_0_OR_GREATER` but specified the error text unqualified.
- GAP-10 × 1 → the scout brief in `work-plan/SKILL.md` step 5, or P7's semantics in `work-plan.md`. After merging master into a planned branch, re-run P7's recorded `searched` patterns over the files the merge brought in (`git diff --name-only <pre-merge>..<merge>`), and add a row plus an `E-n` / `P11` entry for any hit before review.
