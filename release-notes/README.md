# Release-notes drafts

One file per linq2db PR, `<pr>.md`, holding its release-notes draft: the full (wiki) text, the brief (GitHub release highlight) text, the **Omit** / **Include in highlights** checkboxes, and a hidden `release-notes:state` block whose `lastSha` records the PR HEAD the draft was written from. This is the durable per-PR store used from 6.6.0 onward; earlier releases kept the same body in a marker comment on the PR.

Owned by [`/release-notes`](../skills/release-notes/SKILL.md) and written by [`release-notes-draft.ps1`](../scripts/release-notes-draft.ps1). Hand edits are fine for the checkboxes and for prose corrections inside the `rn:full` / `rn:brief` markers; leave the markers and the state block alone. Files are keyed by PR number only — a PR moving between milestones needs no file move.
