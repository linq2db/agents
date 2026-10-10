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
