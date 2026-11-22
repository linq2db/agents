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

## Round 4 — reviewed HEAD 97ccbe1ce18b7c8556bd40261a27c05f2acd9c78

No plan on the branch; each row names the block a Tier M plan would have needed. Review posted 2026-11-19 as review 5980139489 (COMMENT).

- **MIN010** (stale 6.6 labels for the breaking --profile change) — GAP-10 — labels were right when written (4872cc357, 2433d2fa8, 2026-10-10); 6.6.0 shipped without this PR on 2026-11-18 (d141f5671, #6344) and the PR moved to milestone 6.7.0 — — — preventable: no
- **MIN011** (list keeps mixed-case linq2db targets that get/erase lower-case) — GAP-03 — needed a P7 row for CredentialTargets.TryNormalize consumers split by whether they keep its output; CredentialsCliStore.cs:204-208 (round-1 fix 8d0e76271) validates only, TryRead/TryRemove/TryStore use the lower-cased form; second class GAP-05 (no TO-n removed a record by the exact name list printed); probe red — — — preventable: yes
- **MIN012** (dead Describe chain on the credentials-CLI runner) — GAP-03 — needed a P7 row for the redesign 730a2a87f listing each carried-over member of ICredentialsCliRunner with its callers; CredentialStoreChoice.Describe (CredentialsCommand.cs:251) took over the Using line — — — preventable: partly
- **MIN013** (switching a profile's store via cli init --config strands records silently) — GAP-01 — needed a P1/P2 criterion for cli init --config over a profile that already resolves to a store with records, incl. the implicit OS default where existing == null skips the --force refusal (CredentialsCommand.cs:625-627, 752); same class as round 3 SUG007 — — — preventable: yes
- **MIN014** (PR body out of date) — GAP-10 — body predates @vault (1c26977c6), the macOS CLI leg (#6017, merged in 2026-10-17) and every later test-count change; no plan block owns the PR body — — — preventable: no
- **SUG015** (no detach path, Windows asymmetry) — GAP-01 — needed a P2 criterion for returning a profile to the OS default per OS; cli init --store has no credential-manager value — — — preventable: yes
- **SUG016** (generated scripts carry no template version) — GAP-01 — needed a P2/P3 line on upgrading an installed generated artifact against the template embedded in a newer tool — — — preventable: partly
- **SUG017** (local-store overwrite untested) — GAP-05 — needed a P8 TO-n storing one target twice (incl. a case variant) and reading back the new values with count 1 — — — preventable: yes
- **SUG018** (key rotation / store removal undocumented) — GAP-01 — needed a lifecycle criterion or P3 anti-goal for credentials.key rotation, removal, and what clear / uninstall leave behind — — — preventable: partly
- **SUG019** (pwsh naming hides cross-platform; CI guard Windows-only) — GAP-05 — the PowerShell row's TO-n cannot go red off Windows (CredentialsCliProcessTests.cs:527 Assert.Fail only on Windows CI); wording half is GAP-10 prose — — — preventable: partly
- **NIT005** (script headers reference an unshipped doc) — GAP-10 — prose; wrong since 730a2a87f while readme.md already used the absolute URL — — — preventable: no
- **NIT006** (stale class summary) — GAP-10 — prose staleness after @vault and cli init --store local were added — — — preventable: no
- **NIT007** (514 one-line call chains in new tests) — GAP-10 — most tests predate the rule (testing.md rule 1 landed 2026-10-12, CONTRIBUTING.md 2026-11-08); second class GAP-07 for ~370 lines added after the rule — — — preventable: partly
- **NIT008** (raw U+FFFD/U+FEFF char literals) — GAP-10 — style; agent-guardrails.md:124 scope omits format chars and U+FFFD, MA0243 disabled repo-wide — — — preventable: no
- **NIT009** (header byte array could be a u8 literal) — GAP-10 — style preference, no rule or precedent in Source/ — — — preventable: no

### Aggregate

8 of 15 trace to blocks a Tier M plan would have required (9 with NIT007's post-rule slice); the rest is GAP-10 (post-plan events and prose/style nits). Dominant design class: GAP-01 x4 (MIN013, SUG015, SUG016, SUG018), all from the user-requested lifecycle walk — no block enumerates transitions (switch, detach, upgrade, rotate, remove) for the four persisted artifacts (profile-store binding, generated scripts, local key, records).

### Continuity

- Round 3's GAP-01 recommendation (per-pre-existing-state criteria for state-writing commands, gaps.md round 3) did not land in plan-critic.md / work-plan.md / work-plan SKILL.md (grep verified 2026-11-19), and the same class recurs here 4 times (MIN013 is round 3 SUG007's sibling).
- Round 1 SUG004 → round 2 SUG006 → round 4 MIN011: the validator-versus-transform split recurs one level over each round.
- #5995 round 2's optional "sweep enumerations after a mid-branch addition" rule did not land; MIN014 and NIT006 repeat it.

## Round 5 — reviewed HEAD d0224b1873851c23587d6fd5ca6c55137b7447d1

No plan on the branch; each row names the block a Tier M plan would have needed. All three findings sit in round-4 fix commits. Review posted 2026-11-22 as review 6013350799 (COMMENT).

- **SUG020** (Windows arm of the store-change note untested) — GAP-05 — needed a P8 TO-n per OS-default arm of CredentialsCommand.cs:637-638 (Windows: @credential-manager → cli init --store local --config, the only transition Windows reaches); all five note tests in 88ea86322 / f7a40616a / d0224b187 inherit the fixture's RequirePosix() guard (CredentialsCliInitTests.cs:55-59, reason "keyring, gpg and vault are POSIX sh scripts"), which does not apply to --store local; LocalStoreRecordsTheReservedValue (:712-721) runs the exact Windows transition and asserts nothing on stderr — — — preventable: yes
- **SUG021** (note names a different program than the one that ran) — GAP-03 — needed a P7 row naming CredentialsCliCommandResolver.TryResolve's relative-path join (:112-117, IsRooted :305-311) as the authority the new ToPortableStoreValue / GetStoreIdentity (CredentialsCommand.cs:825, :846) must call, not re-derive; the fix reused HasDirectory and IsRooted but replaced the join with Path.Combine, which treats root-relative and drive-relative paths differently; second class GAP-05 (no TO-n with Windows root- or drive-relative spellings) — — — preventable: yes
- **NIT010** (doc says scripts "start with" the template revision line) — GAP-10 — prose; the SUG016 fix 73c40a238 describes the header loosely, the line sits at 4-6 after the shebang — — — preventable: no

### Aggregate

2 of 3 trace to blocks a Tier M plan would have required (one P8 obligation, one P7 row); NIT010 is prose. No dominant class. The common factor is provenance: every finding is new code written to close a round-4 finding. The author works outside this corpus, so the posted finding text is the only design artifact he receives; the change that would have prevented both preventable rows is round-4 finding text carrying the rest of the fix's design ("test the note on both OS-default arms"; "resolve the previous value through the resolver, not a copy").

### Continuity

- Fix-of-a-fix is now the dominant source: all three round-5 findings are in round-4 fix commits (88ea86322, f7a40616a, d0224b187, 73c40a238); same pattern as round 2 (SUG004 → SUG006) and round 4 (MIN011 in round-1 fix 8d0e76271).
- SUG021 is the fourth instance of "a second copy of the consumer's logic": round 1 SUG004 → round 2 SUG006 → round 4 MIN011; round 3 SUG009 was the same resolver's path-base divergence. Round 1's recommended wording ("call the consumer's function") still exists nowhere in skills/work-plan, docs/ or agents/.
- SUG020 mirrors round 4 SUG019 on the opposite OS: SUG019 could not go red off Windows; SUG020 cannot go red on Windows because a blanket fixture guard skips it.
- NIT010 is the prose share of a round-4 fix (SUG016), same kind as NIT005/NIT006; no systemic action.

### Recommended durable fixes

- GAP-05 + GAP-03 → agents/code-reviewer.md finding-text rubric: on a PR without a plan, a finding's Fix names (a) a test obligation per arm the fix will add (per-OS defaults, per-store values), and (b) the existing function the fix must call when it re-derives a value another component computes.
- GAP-03 (recurring rounds 1/2/4/5) → skills/work-plan/SKILL.md step 5 scout brief: when a change re-derives a value another component computes (path resolution, normalization, validation), add a P7 row naming that function as the authority and requiring a call to it.
- acting-on-findings.md:49 addendum: a copied platform guard (RequirePosix / RequireWindows) must still hold for the code under test.
