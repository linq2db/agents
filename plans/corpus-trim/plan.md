# Work plan: corpus-trim — Compress always-loaded agent-rules.md to triggers

**Tier:** M  ·  **Status:** approved  ·  **Approved-at:** 2026-10-13 (user; P6 E-1…E-12 as written after critic round 1)  ·  **Branch:** n/a (corpus-only, linq2db/agents master)
**Schema:** `.claude/docs/work-plan.md`  ·  **Gates:** `.claude/docs/definition-of-done.md`

## P1 Problem

The always-loaded instruction set is resent as prompt prefix on every request and every subagent, and is at its own budget's red line. Measured 2026-10-13 at corpus `37e1c4b` (LF blobs, `git cat-file -s`): `docs/agent-rules.md` 62,536 B / 252 lines; the four-file set (root `CLAUDE.md` + `.claude/CLAUDE.md` + `AGENTS.md` + `agent-rules.md`) = 89,751 B as LF blobs (62,536 + 22,461 + 3,580 + 1,174; ≈90.2 KB on disk with CRLF), against the 60 KB info / 90 KB warning budget in `docs/audit-agents-checks.md:89` and `skills/chores/SKILL.md:40`. `agent-rules.md` alone is ~16 k tokens — the largest single block of always-loaded instructions.

Most of its bytes are not triggers but bodies: incident narratives (`(#NNNN: …)`), multi-sentence mechanics and rationale. The file's own header (`agent-rules.md:3`) and `session-reflect/SKILL.md:93` already say it should hold one-line triggers pointing at the owning doc; the destination scout found the narrative for ~25 bullets exists **only** in `agent-rules.md`, and ~12 bullets are full duplicates of `turn-conduct.md` / `ci-tests.md` / `windows-dev-gotchas.md` / `acting-on-findings.md` / `evidence-discipline.md` sections.

Triggering source: Anthropic's "New rules of context engineering for Claude 5" (Claude Code's system prompt cut >80% with no eval loss; prefer progressive disclosure; don't restate the harness) — external guidance, not a measurement on this repo.

## P2 Success criteria

- SC-1 `docs/agent-rules.md` is ≤ 40,000 B (LF blob) and the four-file always-loaded set is ≤ 68,000 B, measured with `git cat-file -s` on the committed blobs. → TO-1
- SC-2 Every one of the 26 `#`-headings in `agent-rules.md` survives byte-identical, and every bold lead-in that any other corpus file references survives verbatim — the referenced set pinned in the ledger, built by grepping each of the ~98 lead-in texts corpus-wide in `*…*` / `**…**` form (not from lines containing `agent-rules`); a referenced lead-in that D-2 deletes has its reference retargeted in the same commit. → TO-2
- SC-3 No rule is lost: every bullet whose body leaves `agent-rules.md` either keeps a trigger there naming the action and the owning doc, or is listed in the ledger as a harness duplicate with the harness text quoted; every moved body's distinctive token (ledger column; a quoted phrase wherever the issue number already appears in the destination) is absent from the destination at `37e1c4b` and present after. → TO-3
- SC-4 No rule changes meaning: the ledger records each bullet's obligations as numbered clauses (what to do / not do, and when), and every clause is still stated by the bullet's trigger or sub-trigger after the trim. → TO-4
- SC-5 No new broken corpus link: `scripts/check-corpus-links.ps1` reports `broken.count` ≤ 142 (measured at `37e1c4b`, 3,233 links checked) after every section commit. → TO-5

## P3 Constraints & anti-goals (M/L)

- Do not change what any rule requires. This is relocation and compression, not rewording of policy; a rule that looks wrong is noted in the ledger for a separate pass, not fixed here.
- Do not rename, reorder or remove any heading in `agent-rules.md` (≈170 inbound heading references, P7 row 1).
- Do not touch `AGENTS.md`, `.claude/CLAUDE.md`, the root `CLAUDE.md` trampoline, or the user-global `~/.claude-oss/CLAUDE.md` (user decision 2026-10-13: *Reply structure* stays in both CLAUDE.md files).
- Narrowing vs the draft (`.build/.agents/trim-plan.md`): skill-description trimming (release-* frontmatter) and the AGENTS.md Meziantou move are dropped from this plan — different surfaces (skill triggering; cross-agent canonical file) with their own risks.
- No new hook or mechanical size gate in this plan (D-3).
- Do not fix the ~18 pre-existing dangling references (P7 row 4) or the `code-reviewer.md:523` add_item contradiction here.

## P4 Unknowns (M/L)

- U-1 Which agent-rules bullets restate the Claude Code harness system prompt verbatim enough to delete outright? — resolved-by probe: this session's system prompt (Opus 5.5, Claude Code, 2026-10-13) contains "If you intend to call multiple tools and there are no dependencies between the calls, make all of the independent calls in the same … block" (= *Batch independent tool calls*), "Prefer the dedicated file/search tools over shell commands when one fits" (= the premise of *Dedicated tools over raw CLI*, not its repo-specific table), "match its comment density, naming, and idiom" (= the premise of *Comments justify decisions*, not its artifact rule), and the PowerShell/Bash tool text "you will be notified when it completes — do not poll" (= the premise of *After launching a background task*). Only *Batch independent tool calls* is a full duplicate; the others keep their repo-specific remainder.
- U-2 Does moving a rule's body to an on-demand doc degrade compliance? — resolved-by scout: one recorded precedent. The in-flight-edit rule was moved wholly out to `turn-conduct.md:38` by `5df804b` (2026-09-09), broken in the #5943 session, and repaired by `b7d3ce0` restoring a one-line trigger in agent-rules. No other move-back in 60 commits. Design keeps a trigger for every rule (D-1).
- U-3 Is any agent-rules text parsed mechanically? — resolved-by scout: no script/hook parses it; `hooks/require-test-progress.ps1:58` quotes the lead-in "Every hand-run `dotnet test` / test-exe invocation carries `--test-progress`" in a user-visible message, which SC-2 keeps verbatim.
- U-4 Is the budget KB 1000 or 1024 bytes? — resolved-by author decision: SC-1 is stated in bytes, so the ambiguity does not reach the criterion.
- U-5 Is 40,000 B reachable while keeping every heading, every referenced lead-in and a trigger per rule? — resolved-by probe: headings total ≈1.4 k chars (section-size script, `.build/.agents/section-sizes.ps1`); the destination scout's "full duplicate" bullets plus the narrative-only bodies account for the bulk of the 7.4 k / 5.8 k / 4.9 k / 4.3 k / 3.9 k sections. Estimate, not a measurement — if the first three sections land above budget pro rata, the SC-1 number is revisited via P11 rather than met by cutting triggers.
- U-6 Agent-rules cites #5943 for the two background-task traps while `turn-conduct.md:34,38` cites #5701 / #6026. — resolved-by scout: both traps are fully present in turn-conduct.md with their own citations; the agent-rules sub-bullet becomes a pointer and carries no issue number, so the discrepancy is not propagated.

## P5 Decisions (M/L; rejected alternatives mandatory at L)

### D-1 — Trigger stays, body moves

- **chosen:** each bullet keeps its bold lead-in plus one sentence per obligation clause (SC-4; e.g. *Verify subagent output* keeps three, *The corpus moves under you* two, *Docker containers* three) and a pointer to the owning doc (`→ <doc>.md → *Section*`). Bodies (narratives, mechanics, rationale) move to the destination the scout identified; where the destination already holds the body in full, the agent-rules copy is simply cut to the trigger.
- **rejected:** delete narratives outright — they are the only record for ~25 rules and the corpus treats them as evidence (`maintaining-the-corpus.md`). Rejected: split agent-rules into several always-imported files — saves no tokens. Rejected: move whole rules out with no trigger — the one measured precedent (U-2) failed exactly that way.
- **why this:** matches the file's own stated contract (`agent-rules.md:3`) and `session-reflect/SKILL.md:93`'s "one-line trigger … never the paragraph, never the war story".
- **failure mode of the choice:** a rule whose compliance depended on the vivid story being always loaded degrades silently; nothing in this plan can measure that (no eval harness, `agent-evals.md` is unbuilt). Mitigation is bisectability only: one commit per section group (D-4).

### D-2 — Harness duplicates

- **chosen:** delete *Batch independent tool calls* (full duplicate, U-1). For *Dedicated tools*, *Comments*, *After launching a background task*: drop only the sentence the harness states, keep the repo-specific remainder as trigger(s).
- **rejected:** treat every harness-adjacent rule as deletable — the repo-specific parts (allowlist reasons, artifact-rationale rule, Grep-polling a redirect log) are not in the harness.
- **why this:** smallest deletion the probe supports.
- **failure mode of the choice:** the harness prompt is versioned by Anthropic and can drop the sentence later; the deleted bullet would then be silently missing. Recorded in the ledger with the quoted harness text and date so a later audit can re-check.

### D-3 — No regrowth gate in this plan

- **chosen:** compress only; leave the existing advisory budget (`chores` / `audit-agents`) as the regrowth signal.
- **rejected:** a corpus pre-commit size warning — a new hook surface; `agent-guardrails.md` → *Default to script + doc guardrails before hooks* requires an explicit user ask.
- **why this:** keeps this plan a pure relocation; the gate is a separate decision for the user.
- **failure mode of the choice:** this is the third shrink (151→64 KB 2026-09-09, 70→61 KB 2026-10-10, +1.5 KB in the three days since); without a gate the file will regrow. Surfaced to the user as a follow-up, not silently accepted.

### D-4 — Commit granularity

- **chosen:** one commit per agent-rules section group, each carrying its destination edits, plus a ledger at `.claude/plans/corpus-trim/ledger.md` (bullet → disposition → destination → distinctive phrase).
- **rejected:** one squashed commit — a compliance regression could not be bisected to a section.
- **why this:** the only available mitigation for D-1's failure mode.
- **failure mode of the choice:** ~10 commits of corpus churn while the user curates in parallel; each must be committed promptly to avoid being wiped (agent-rules → *The corpus moves under you*).

### D-5 — Inbound references: retarget only inside files P6 already edits

- **chosen:** keep headings and referenced lead-ins verbatim (SC-2), so inbound pointers land on a trigger that points onward. Retarget the owner back-references that sit in files P6 already edits — `bug-investigation.md:39`, `claude-setup.md:74`, `claude-setup.md:76` (names *Batch independent tool calls*, which D-2 deletes), `turn-conduct.md:24`, `windows-dev-gotchas.md:542`, `testing.md:110` — to the body's new home or the harness.
- **rejected:** retarget all 14 owner back-references — the remaining eight sit in skills/scripts/agents P6 does not otherwise touch. Rejected: no retargeting at all — `claude-setup.md:76` would dangle (critic, measured) and `bug-investigation.md:39` would point away from a body placed two lines above it.
- **why this:** no new dangling reference, and no file edited only for a pointer.
- **failure mode of the choice:** the other eight owner pointers (e.g. `agents/code-reviewer.md:523` "full rule") become one hop longer; left for the separate dangling-reference pass. Two historical plan records whose references resolve today to agent-rules *body* text (`plans/issue-5814-projectflags-condition-analyzer/plan.md:139`, `plans/issue-5779-analyzer-duration-comparison/gaps.md:26`) dangle because of this change; they are frozen records, so the ledger names the body's destination (`evidence-discipline.md:120`) instead of editing them.

## P6 Edit-points

- E-1 `docs/agent-rules.md` — compress every section per D-1/D-2; headings and referenced lead-ins unchanged.
- E-2 `docs/turn-conduct.md` — receive: background-task output file → Grep/Read (agent-rules L47 body), *Batch edits on a single config file* body; retarget :24 (D-5).
- E-3 `docs/pr-and-push.md` — receive: structural-migration → filed issue (#5731/#5861/#5862), no recovery branch mid-rebase, stale-base large-deletion illusion (#5860), deletion reference sweep + NuGet-id publication check (#5711/#5720).
- E-4 `docs/claude-setup.md` — receive: corpus checkout advances under you (script contract changes, re-read header, third-repetition signal, #5880) under *The corpus is a git submodule*; retarget :74 and :76 (D-5).
- E-5 `docs/worktree.md` — receive: the stale `file:line` citation mirror (#5936) beside the commits-behind text at :40.
- E-6 `docs/windows-gotchas.md` — receive: Edit "string not found" → re-anchor on the first non-whitespace char (#5877).
- E-7 `docs/windows-dev-gotchas.md` — receive: ls-tree enumeration fix + #5764; add_item rest-of-session rule, 6.5.0 story, hook-running commit/push exception (#6003); commit-message hook-scanning (`-F` for `;`/`&&`/banned names, #5723); retarget :542 (D-5).
- E-8 `docs/testing.md` — receive: `test-status.ps1` vs `ls -t` reason; repro blocked by a separate known engine bug → gate on the blocker (#5704/#1813/#5701); retarget :110 (D-5).
- E-9 `docs/bug-investigation.md` — receive: repairing dead or broken code — payload and conditions in scope (#5841); core-layer regression test rule body (#5296) above the existing :39 recipe; retarget :39 (D-5).
- E-10 `docs/code-design.md` — receive: new *Code comments* section (artifact-rationale rule, ≤3 lines, #5614/#5858/#5882 examples); beneficiary survey (#5675).
- E-11 `docs/agent-guardrails.md` — receive: subagent `git status` absolute-path detail; subagent-result-is-a-claim narrative (3.066 s, stale heartbeat); effort-vs-capability diagnosis.
- E-12 `plans/corpus-trim/ledger.md` — new: per-bullet disposition ledger (SC-3's checklist).

## P7 Impact map (M/L)

- Inbound heading references (≈170 across skills/, agents/, docs/, scripts/, hooks/, plans/, knowledge-base/, auto-memory; scout pattern `agent-rules` + `overlay\W{0,5}(→|->)`) — covered by E-1 (SC-2 keeps all 26 headings byte-identical)
- Inbound bold lead-in references found via lines naming agent-rules (27 names, e.g. *Frame subagent prompts to allow failure* ×5, *A working-tree search is evidence about your checkout* ×4, *Every hand-run `dotnet test` … carries `--test-progress`* ×3 incl. `hooks/require-test-progress.ps1:58`) — covered by E-1 (SC-2 keeps each verbatim)
- Bare lead-in references with no `agent-rules` token on the line (critic search `\*(<lead-in>)\*` corpus-wide: `claude-setup.md:75-76`, `agent-evals.md:15`, `skills/release-deps/SKILL.md:244`, `skills/session-reflect/SKILL.md:103-104`, `agents/code-reviewer.md:518,523`, `ci-tests.md:109`) — covered by E-12 (ledger pins the full referenced set per SC-2) and E-4 (`claude-setup.md:76` names *Batch independent tool calls*, which D-2 deletes)
- Owner back-references in files P6 edits (`bug-investigation.md:39`, `claude-setup.md:74`, `turn-conduct.md:24`, `windows-dev-gotchas.md:542`, `testing.md:110`) — covered by E-9, E-4, E-2, E-7, E-8 (D-5 retarget)
- Owner back-references in files P6 does not edit (`windows-gotchas.md:36`, `scripts/ref-file.ps1:11,16`, `work-plan.md:80,253`, `skills/create-issue/SKILL.md:96`, `agents/code-reviewer.md:523`, `ci-tests.md:125,149`, `skills/release-deps/SKILL.md:244`, `agent-evals.md:14`) — deferred: D-5, pointers still resolve to the kept trigger
- References resolving today to agent-rules body text the trim removes (`plans/issue-5814-projectflags-condition-analyzer/plan.md:139` *A comment a change has falsified…*, `plans/issue-5779-analyzer-duration-comparison/gaps.md:26` *the mirror applies to your own changes*) — deferred: frozen plan records; ledger names `evidence-discipline.md:120` as the body's home (D-5)
- Pre-existing dangling references (~16 names matching no heading or lead-in, e.g. `review-pr/SKILL.md:550` *Provider behavior claims…*, `hooks/track-docker-start.ps1:10-12` *Scope-change prompt…*, `plans/feature-activeissue-verify-attribute/plan.md:496` line numbers 257/278) — out-of-scope
- Markdown link paths added by D-1 triggers (~90 new `→ <doc>.md` links) and destination edits — covered by E-1 (SC-5 / TO-5 via `scripts/check-corpus-links.ps1`)
- Unscoped prose mentions (no section named; scout list in skills/agents/docs/scripts/memory) — Localized — searched `agent-rules` across `.claude/` and memory, mentions name the file only and are unaffected while the file and its headings remain
- Mechanical consumers of agent-rules text — Localized — searched hooks/ and scripts/ for agent-rules/budget/always-loaded, only doc-comment mentions and the require-test-progress message (row 2)
- Size-budget tooling (`docs/audit-agents-checks.md:84,85,89`, `skills/chores/SKILL.md:40`) — out-of-scope: thresholds unchanged; the 2026-10-10 footprint note at :89 goes stale and is left for the next `/audit-agents` run to refresh
- Superproject files (`CLAUDE.md:21` imports the whole file; `AGENTS.md`, `.github/copilot-instructions.md` have no matches) — Localized — searched `agent-rules` in all three, import is file-level
- Destination docs already holding the body in full (`turn-conduct.md:14,16,18,22,24,26,30,32,34,38,46,48,52-72`; `ci-tests.md:123-131`; `windows-dev-gotchas.md:118-138`; `acting-on-findings.md`; `evidence-discipline.md`; `agent-guardrails.md:98,104`) — covered by E-1 (cut to trigger, no destination edit)

## P8 Test obligations (M/L)

- TO-1 Size check: `git cat-file -s` on the committed `docs/agent-rules.md` ≤ 40,000 and the four-file sum ≤ 68,000. Red against `37e1c4b` (62,536 / 89,751) — measured 2026-10-13 before any edit. — proof: red→green
- TO-2 Heading + lead-in check: a script diffs the `^#{1,4} ` lines of `agent-rules.md` at `37e1c4b` vs HEAD (must be identical) and greps HEAD for each lead-in in the ledger's referenced set (all must match, except rows marked deleted-and-retargeted, whose old reference must be gone from the referencing file). Mutation to record: rename one heading and drop one referenced lead-in in a scratch copy; both must fail the script. — proof: control
- TO-3 Ledger move check, two arms per `moved` row: the row's distinctive token is **absent** from the destination at `37e1c4b` (red arm, run against the baseline blob) and **present** at HEAD (green arm). A row whose token already exists in the destination at baseline (#5675 in `code-design.md:84`, #5296/#5841 in `bug-investigation.md`, #5704 in `testing.md`, #5614 in `code-design.md:357`/`turn-conduct.md:67`) must pick a quoted phrase instead, or the script rejects the row. `trigger-only` rows: lead-in present in agent-rules; `harness-duplicate` rows: quoted harness text recorded. — proof: red→green
- TO-4 Clause check: per bullet, the ledger lists obligation clauses (C1…Cn) taken from the body at `37e1c4b`; a reviewer marks each clause found / missing in the post-trim trigger, section by section, and every multi-clause bullet (at least `agent-rules.md:20`, `:245`, `:230-234`) is recorded clause by clause. Characterization only — cannot detect a compliance regression in live sessions (D-1 failure mode). — proof: characterization
- TO-5 Link check: `pwsh -File scripts/check-corpus-links.ps1` `broken.count` ≤ 142 after each section commit (baseline 142 / 3,233 checked at `37e1c4b`, measured 2026-10-13). Mutation to record: a trigger with a misspelt doc link in a scratch copy raises the count. — proof: control

## P9 Verification gates

- G-01: — (pending) — no product tests apply (corpus docs only); the obligations are TO-1…TO-5, run as scripts under `.build/.agents/` plus `scripts/check-corpus-links.ps1`, one row per TO with its observation recorded here
- G-06: — (pending) — no unrelated reformatting: diff limited to E-1…E-12
- G-07: n/a — corpus-only change, no linq2db working tree involved
- G-09: — (pending) — adversarial read: plan-critic on the plan; user review of each section commit before push

## P10 Adjudicated (M/L)

- Behavioural compliance after the trim is unmeasured (no eval harness; `agent-evals.md` is a design spec). Accepted: the plan relies on keeping a trigger per rule (D-1) and section-level bisectability (D-4).
- Regrowth is not prevented by this plan (D-3); the third-shrink history is the measurement. User decision 2026-10-13: no new gate — the existing `/chores` context-budget row (`skills/chores/SKILL.md:40`) is the regrowth signal.
- One-hop pointer indirection for the eight owner back-references outside P6 files (D-5). Accepted to keep the edit surface to the destination docs.
- Two frozen plan records (`plans/issue-5814-…/plan.md:139`, `plans/issue-5779-…/gaps.md:26`) lose their body-text target (D-5). Accepted: historical artifacts are not edited; the ledger records the new home.

## P11 Amendments (M/L)

_None._

## P12 Critic verdict (M/L)

**Round 1 — weak** (plan-critic on `fable`, 2026-10-13). Searched: `agent-rules` corpus-wide (282 lines) and every `→ *X*` target; headings and bold lead-ins in agent-rules.md (26 / 98); superproject + `.github/`; anchor and line-number refs; bare `*<lead-in>*` refs corpus-wide; `scripts/ref-file.ps1`, `hooks/require-test-progress.ps1`; issue numbers across the ten destination docs; `windows-gotchas.md`, `claude-setup.md`, `windows-dev-gotchas.md:110-141`, `turn-conduct.md`; its own Fable 5.1 subagent system prompt (U-1 holds there too). Rated SC-1's 40 k reachable (~30 k by trigger arithmetic).

Objections and responses:
1. `claude-setup.md:76` names *Batch independent tool calls* (D-2 deletes it) without an `agent-rules` token, so the census missed it; lead-in list not pinned. → SC-2 rebuilt from a corpus-wide grep of each lead-in, pinned in the ledger; `:76` retargeted under E-4 (D-5).
2. TO-3 could not go red where the issue number pre-exists in the destination (#5675, #5296, #5841, #5704, #5614). → TO-3 now has an explicit absent-at-baseline arm and forces a quoted phrase for those rows.
3. D-1's one-sentence cap vs multi-clause bullets (`:20`, `:245`, `:230-234`); TO-4 had no per-clause instrument. → D-1 is now one sentence per clause; SC-4/TO-4 are clause-numbered in the ledger.
4. G-01 did not run `scripts/check-corpus-links.ps1`. → Added SC-5/TO-5; baseline measured at 142 broken / 3,233 checked.
5. Two plan-record references resolve today to body text the trim removes. → Moved out of "pre-existing" into their own P7 row and P10 entry; ledger names the new home.
6. D-5's rejection reason did not hold for back-references in files P6 already edits. → D-5 now retargets those six.

Not re-sent to the critic: the verdict was `weak`, not `refuted`, and every response narrows or instruments the existing design rather than changing a decision.
