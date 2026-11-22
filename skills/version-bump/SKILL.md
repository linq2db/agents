---
name: version-bump
description: Bump product and EF versions in Directory.Build.props to match the next release milestone. Creates an infra/bump-versions branch from origin/master, sets <Version> to the next milestone version, increments each <EFxVersion> minor by 1, and requires explicit user confirmation of the proposed diff.
---

# version-bump

User-triggered workflow to prepare a version-bump PR.

## When to run

Only when the user explicitly invokes this skill. Do not propose bumps during unrelated work.

## Steps

### 1. Verify bump is needed

1. `git fetch origin master`.
2. Read `<Version>` from `Directory.Build.props` on `origin/master`:
   ```
   git show origin/master:Directory.Build.props
   ```
   Extract the value of the `<Version>` property (not `<AssemblyVersion>`, `<PackageVersion>`, `<BaselineVersion>`, or any `<EFxVersion>`).
3. Fetch open milestones: `gh api repos/linq2db/linq2db/milestones?state=open --jq '.[] | .title'`.
4. Pick the **next release milestone** — the lowest versioned milestone (title starts with a digit, has the form `M.m.p`) that is `>= master <Version>`.
5. If master `<Version>` is already equal to or greater than the next milestone version, report the state and stop. No bump.
6. Otherwise continue.

### 2. Prepare the branch

Branch name is `infra/bump-versions`. Follow the **Creating a new branch** rules in `.claude/docs/agent-rules.md` for everything else (dirty-tree handling, basing off `origin/master`, etc.).

Do **not** create the branch yet — wait for user confirmation of the proposed changes in step 3.

### 3. Compute and present the diff

Read current values from `Directory.Build.props` on `origin/master`:

- `<Version>` → the next milestone's version (from step 1.4)
- every `<EF<n>Version>` present in the file (today `EF3`, `EF10`, `EF11`; the set changes as bands are added and dropped, so read it, don't assume it) → increment minor by 1, reset patch to 0 (e.g. `3.31.0` → `3.32.0`)

Present the proposal in this format, one row per property found:

```
Version       <old>  -> <new>
EF3Version    <old>  -> <new>
…
```

Wait for explicit user confirmation (e.g. "yes", "go", "apply") before editing.

### 4. Apply

**All-or-nothing precondition:** every `<EFxVersion>` value must end up different from its previous value. If any would remain unchanged, refuse the bump, explain which one didn't move, and stop. No partial updates.

Only after user confirmation of the diff in step 3:

1. Create branch `infra/bump-versions` from `origin/master`.
2. Edit `Directory.Build.props` in a **single** `Edit` call that covers all the `<Version>` / `<EFxVersion>` lines as one `old_string` / `new_string` block. Do **not** issue a separate Edit per property — that produces one diff and one permission prompt per line. The lines are contiguous in the file, so one Edit replaces them all at once. Preserve existing formatting (tabs, column alignment, comments).
3. Do **not** commit, push, or open a PR automatically. Per `.claude/docs/agent-rules.md` → **Git commit rules** / **Push to remote rules** / **Pull request rules**, each of those actions needs its own explicit user request.

## Don'ts

- Don't create `infra/bump-versions` before the user confirms the step-3 diff.
- Don't apply a partial bump — every `<EFxVersion>` moves, or nothing is edited.
- Don't split the `Directory.Build.props` change into one `Edit` per property.
- Don't commit, push, or open a PR without an explicit user request.
