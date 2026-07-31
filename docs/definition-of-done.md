# Definition of done

A consolidated completion checklist for a code change on linq2db. The completion gates already live, canonically, in the rules this doc points at — they were scattered, so this file gathers them in one place to walk before declaring a change "done" or proposing to commit / push. **Nothing here is a new rule; each item links its owner.** Not every item applies to every change — skip the ones that don't, but skip them knowingly.

Referenced from [`agent-rules.md`](agent-rules.md) → *Definition of done*.

## The checklist

- [ ] **Tests run and pass via `/test`.** Don't `dotnet build` / `dotnet test` by hand around the skill — it injects the `CreateDatabase` filter and runs the baselines diff. New behavior has a red→green test; a fix that clearly needs a test has one. ([`agent-rules.md`](agent-rules.md) → *Running tests*; [`testing.md`](testing.md).)
- [ ] **Baselines reviewed, not just regenerated.** A moved baseline is reviewed for intent; a baseline that drifts on every run (embedded `DateTime.Now` / `Guid` / clock) is a test bug to fix at the source, not noise to wave through. ([`bug-investigation.md`](bug-investigation.md) → *Non-deterministic baselines*.)
- [ ] **New public surface is accounted for.** Any added / changed public (non-`Internal.*`) member: `PublicAPI.Unshipped.txt` updated, XML doc present, and at least one test exercising it. ([`code-design.md`](code-design.md) → *Public API is a contract*; CLAUDE.md → *Code conventions*.)
- [ ] **API baselines refreshed when the surface changed.** `Source/**/CompatibilitySuppressions.xml` is regenerated through the `/api-baselines` skill — never hand-edited. ([`agent-rules.md`](agent-rules.md) → *Agent guardrails (anchor set)* → never hand-edit API baseline files.)
- [ ] **Builds on the portable TFMs**, not just `net10.0`. The `Testing` config is net10.0-only; a BCL API newer than netstandard2.0 needs a `Directory.Build.props` polyfill or a CI-red `build` leg. ([`agent-rules.md`](agent-rules.md) → *TFM API availability*.)
- [ ] **No unrelated reformatting / renames.** Only lines the task touches are changed; intentional column alignment is preserved. ([`agent-guardrails.md`](agent-guardrails.md); [`code-design.md`](code-design.md) → *Column-aligned formatting is intentional*.)
- [ ] **No playground scratch staged.** No new `.cs` under `Tests/Tests.Playground/` (beyond `TestTemplate.cs`) and no new `<Compile Include>` test-fixture links committed. ([`agent-rules.md`](agent-rules.md) → *Git commit rules*.)
- [ ] **Cross-cutting core changes were surfaced, not made silently**, and rest on a red→green test or CI — not static reasoning. ([`agent-rules.md`](agent-rules.md) → *Before coding a fix or feature*; [`agent-guardrails.md`](agent-guardrails.md) → *Cross-model verification for high-blast-radius core changes*.)
- [ ] **Subagent output verified** with `git status` **and `git -C .claude status`** after each invocation — the only modified files are the ones the task justifies (the superproject's status is blind to the corpus). ([`agent-rules.md`](agent-rules.md) → *Agent guardrails (anchor set)*.)
- [ ] **Parked for review, not published.** "Done" means staged and ready for the user to review / commit; commit / push / PR / comment each need an explicit go-ahead this turn. ([`agent-rules.md`](agent-rules.md) → *Git commit rules*.)

## When it's not code

For a corpus change, a release task, or a GitHub-authoring action, the gates differ. This checklist is scoped to changes under `Source/` / `Tests/`; use the owning skill's completion criteria for the rest — the release sub-skill's own checklist, or the wording / verify-after-PATCH rules in [`github-authoring.md`](github-authoring.md).

A **corpus change** (anything under `.claude/`) is done when: the edit is committed **inside the submodule** and pushed to the agents repo's `master` (an uncommitted corpus edit is invisible to the superproject's `git status` and can be wiped by the user's parallel curation); no linq2db branch carries it and the `.claude` gitlink is unbumped; and cross-references still resolve — a moved or renamed doc/skill leaves dangling links elsewhere in the corpus, which `/audit-agents` checks.
