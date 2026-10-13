# Work plan: agents-md-trim — Conservative trim of always-loaded AGENTS.md

**Tier:** S  ·  **Status:** draft  ·  **Approved-at:** —  ·  **Branch:** n/a (corpus-only, linq2db/agents master)
**Schema:** `.claude/docs/work-plan.md`  ·  **Gates:** `.claude/docs/definition-of-done.md`

## P1 Problem

`.claude/AGENTS.md` is 22,461 B (LF blob at `92624c8`), always loaded by Claude Code and Codex's primary instruction set; at the measured ~2.6 chars/token (`/context` on 2026-10-13: 35.3 k tokens for the six instruction files) it is ~8.6 k tokens per request. Part of it is not rule wording: a loading-mechanics blockquote that `## Per-agent overlays` and `docs/claude-setup.md` repeat, incident / attack-vector parentheticals, one rationale sentence `docs/work-plan.md:9` already states, and a `NU1201` explanation given twice. User decision 2026-10-13: Codex is used, so **every rule's full wording stays** — only that non-rule text may move. Small mechanical edit; Tier S with no critic chosen by the user over the Tier M option.

## P2 Success criteria

- SC-1 `.claude/AGENTS.md` is smaller and every `##`/`###` heading and every referenced bold lead-in at `92624c8` is present byte-identical (checked by script). The authoring estimate was ≤ 21,000 B; measured 21,463 B — the remaining non-rule text is clarification of rule scope, which the user's constraint keeps. → G-01
- SC-2 No rule changes: every removed span is one of — the loading blockquote's duplicated mechanics, an incident / vector parenthetical (moved verbatim to `docs/security.md` or dropped as provenance only), the `P10` rationale sentence, the second `NU1201` mention — and the user reviews the full diff before commit. → G-01
- SC-3 `check-corpus-anchors.ps1` reports 0 broken and `check-corpus-links.ps1` stays at 142 broken. → G-01

## P6 Edit-points

- E-1 `AGENTS.md` — compress the loading blockquote (keep: canonical location, don't edit the root trampoline, Codex's primary-instruction-set line, docs-on-demand, path convention); drop the repeated `NU1201` clause in the Codex test recipe; drop the `P10` rationale sentence in the work-plan bullet; drop the Meziantou walk count; move the three Security parentheticals to `docs/security.md` and link it; correct the *Per-agent overlays* Copilot line ("review heuristics + pointer here" contradicts the self-contained statement).
- E-2 `docs/security.md` — new: background for `AGENTS.md` → *Security* (exfiltration chain, the 2025 folder-open vector, *Friendly Fire* / *Ghostcommit*). The `code-reviewer` diff-gate notes stay in `AGENTS.md`: they state each rule's scope.

## P9 Verification gates

- G-01: pass (2026-10-13, working tree on `92624c8`) — `.build/.agents/agents-md-check.ps1`: 22,460 → 21,463 B LF (−997 B, −4.4%); 0 heading diffs; 59 of 60 bold spans unchanged, the one changed is the blockquote's own label (*Where this file lives and how each agent loads it* → *Where this file lives.*), referenced nowhere (`Grep` over the superproject and corpus: no files). `check-corpus-anchors.ps1`: 0 broken / 456 checked; `check-corpus-links.ps1`: 142 broken (unchanged). User diff review: pending.
- G-06: pass — `git -C .claude diff --stat`: `AGENTS.md` (+13 / −15) and new `docs/security.md` only, plus this plan.
