# Gap ledger — feature/cli-credential-helpers (PR #5991)

## Round 1 — reviewed HEAD 5e419bd05e8d2822e1c92b16f1dc35c3ef5d55c6

No plan on branch (external contribution, no linked issue).

| ID | Gap | Missing block | Preventable |
|---|---|---|---|
| MIN001 | GAP-02 | P4 unknown: does `secret-tool search --all` trigger the unlock prompt on a locked keyring? (probe) | partly |
| MIN002 | GAP-02 | P4 unknown: which `IOException`s the lock-file open raises besides sharing violation (EROFS, read path opening ReadWrite) | partly |
| MIN003 | GAP-03 | P7 row: shipped 6.5 Credential Manager record shapes (`linq2db/a//b`) as persisted data the new segment validation must accept | yes |
| MIN004 | GAP-03 | P7 row: 6.5 `--profile` meaning reused with new semantics; forces migration message or P5 decision | yes |
| MIN005 | GAP-03 | P7 row: `credentials list` output shape (PROFILE→RECORD) | yes |
| MIN006 | GAP-05 | P8 TO-n with red→green mutation proof for the lock-less reader test | yes |
| SUG001 | GAP-01 | P2/P3 constraint: nothing derived from helper stdout (content, length) in errors / MCP responses | yes |
| SUG002 | GAP-03 | P7 row: every write entry point of `cli init` (`--output` sibling) | yes |
| SUG003 | GAP-10 | prose omission (XDG step) inside a section a P7 row would only list | no |
| SUG004 | GAP-03 | P7 row: `ConfigInitCommand` as a second producer of `credentialsCli` that skips the consumer's validator | yes |
| SUG005 | GAP-01 | P3 anti-goal on platform / vault scope (would have made it a recorded deferral) | partly |
| NIT001 | GAP-01 | P2 criterion: `@keyring` refused on every non-Linux host | yes |

### Aggregate

11/12 trace to blocks a Tier M plan requires; only SUG003 is GAP-10. GAP-03 dominates (5): three (MIN003-005) from one missing P7 sweep of already-shipped 6.5 surface (persisted record names, flag meanings, list output), two (SUG002, SUG004) from sibling producer/entry-point sites of a value validated in only one place. Rest: GAP-01 ×3, GAP-02 ×2, GAP-05 ×1.

### Recommended durable fixes (route to /session-reflect plan-rule bucket)

- GAP-03 ×5 → `work-plan/SKILL.md` step 5 scout brief: for CLI/tooling changes require P7 rows for (a) shipped persisted data the new code reads/validates, (b) prior meaning of every reused flag and shape of every changed output column, (c) every producer of a value some consumer validates.
- GAP-01 ×3 → doc rule (CLI/credentials) + `code-reviewer.md` rubric: errors and MCP responses carry nothing derived from a secret source, length included; a documented platform restriction needs a P2 criterion covering every excluded OS.
- GAP-02 ×2 → `plan-critic.md` attack vector: challenge assumed external-tool / OS-primitive behaviour (keyring unlock, IOException classes) not backed by a P4 probe, especially where CI lacks the environment.

## Round 2 — verification at HEAD f03eba7772141d4df6d7399f60de591eee90c8d7

No attribution run (verification round). Round-1 findings: 10 fixed; SUG004 partial → SUG006; SUG005 partial → MIN007, MIN008, NIT002.

## Round 3 — reviewed HEAD f03eba7772141d4df6d7399f60de591eee90c8d7

Fresh full review after round 2. Still no plan on branch.

| ID | Gap | Missing block | Preventable |
|---|---|---|---|
| SUG007 | GAP-01 | P1/P2 criterion: `credentials cli init` semantics when script and config entry are in different states; one `--force` covers overwrite-script and replace-config | yes |
| SUG008 | GAP-01 | P1/P2 criterion: `credentials clear` partial-failure behaviour on a credentials-CLI store (stop vs continue, what is reported) | yes |
| SUG009 | GAP-02 | P7 row: SKILL.md / MCP consumer of `--credentials-cli` path resolution (resolver uses cwd, `CredentialsCliCommandResolver.cs:114`) | yes |
| SUG010 | GAP-03 | P7 row: observable output change of existing commands ("Using <store>" on stderr) against the 6.6 breaking-change notes | yes |
| SUG011 | GAP-06 | convention: sibling `GetSecretHelperSource` content-keyed cache + cross-process lock not followed by the argecho cache | partly |
| SUG012 | GAP-05 | P8 TO-n: MCP `linq2db_schema` credentials wiring (`McpQueryTool.cs:250`) and the MCP failure path through the server | yes |
| NIT003 | GAP-10 | synopsis wording written after code and §16; no design artifact prevents it | no |

### Aggregate

6/7 preventable or partly; only NIT003 is GAP-10. GAP-01 leads (2): unnamed behaviour in partial-state and mid-sequence-failure paths of state-writing commands. Rest: GAP-02, GAP-03, GAP-05, GAP-06 ×1 each.

### Recommended durable fixes (route to /session-reflect plan-rule bucket)

- GAP-01 ×2 → `work-plan.md` P1/P2 note or `plan-critic.md` attack vector: for any command that writes or erases state, require criteria for each pre-existing-state combination and for mid-sequence failure; one flag covering two effects is a prompt to split.
- GAP-02/GAP-03 ×2 → `work-plan/SKILL.md` step 5 scout brief: sweep every doc, skill and MCP consumer of a changed CLI surface — path-resolution base, stdout/stderr changes against breaking-change notes.
- GAP-05 ×1 (+GAP-06) → `code-reviewer.md` rubric: each new integration entry point (MCP tool, CLI command) needs an end-to-end obligation; test-helper caches follow the sibling content-keyed + cross-process-lock pattern.

## Continuity

- **Round-1 fix (c) recurs, and its fix was aimed short.** Round 1 attributed SUG004 to GAP-03 "every producer of a value some consumer validates". The author's fix added a second validator (`ValidateValue`) instead of reusing the consumer's (`TryParseCommandLine`), so round 2 re-found the gap as SUG006. The recommendation should read "call the consumer's validator", not "validate in the producer".
- **Round-1 fix (b) recurs.** SUG010 (stderr line not in the 6.6 notes) is the same class as MIN005 (`list` output shape not in the notes): the fix documented the one changed output it was told about, not the sweep. A sweep rule, not a per-finding doc fix, is what prevents the next one.
- **New class this round:** GAP-01 in state-transition / partial-failure semantics (SUG007, SUG008), not seen in round 1.
