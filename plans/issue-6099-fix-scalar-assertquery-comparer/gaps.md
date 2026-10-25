## Round 1 — reviewed HEAD 1faaee0a117b3356554fe0b2f9b60faa11645fc6

## Attribution

- **MIN001** — GAP-10 (honest floor, narrow) — The PR body was drafted at plan time from U-5 / P7 deferral ("currently-green tests that go red ... unknown set, CI test-all, triaged per D-4", plan.md:40, :101). The information that did not exist then: the CI result (24655 / 40119233045 fully green, empty fallout set) and G-01's measurement that TO-5/6/9/10 were green pre-fix. The body claim "proven red before the fix" contradicts G-01 once it was measured, which is a prose-sync miss after P9, not a design-block gap. No P-block governs PR body wording. — — — preventable: no (partly if a "PR body re-read after G-01 and CI" step existed; that would be a process note, not a plan block)
- **NIT001** — GAP-06 (convention was in the plan and violated in prose) — The plan's D-4(c) (plan.md:69) explicitly separates "vacuous equality -> reference equality" for zero-member reference T from value equality. The doc comment at Tests/Base/TestComparers.cs:17-18 still calls that arm "value equality". The distinction was in the plan baseline and was not carried into the XML doc, so it is not a missing design block. It is a doc-wording slip with no gate covering it. — — — preventable: partly (a G-09 prompt to cross-check new XML docs against D-1..D-4 terminology might catch it, but this is prose precision, near GAP-10)

## Aggregate

Two prose-level findings, zero code or design findings. Neither traces to a missing plan block, map row or skipped gate: the plan's D-4 already stated the correct distinction, and the CI-fallout and characterization facts (MIN001) only became known after P9/CI. The plan and gates did their job here; the residual is wording drift between plan decisions, measured results and outward text (PR body, XML doc). That is the expected floor, so there is no systemic fix. The one mildly actionable pattern is that PR body claims about red/green history are not re-checked against G-01 results.

## Recommended durable fixes

- GAP-10 × 1 (MIN001) → `pr-and-push.md` / `/work-plan` PR-creation step — before `gh pr create`, check every "proven red before the fix" and "expected to go red" sentence in the body against the recorded G-01 and CI outcomes; use "characterization (green pre-fix)" when G-01 measured green.
- GAP-06 × 1 (NIT001) → no durable fix recommended; a one-off wording slip. Do not add a rule for it.
