# Conducting a turn — batching, waiting, asking, scope

How to spend a turn: what to batch, when to stop, how to wait on work you launched, and how wide to make the
change you were asked for. Loaded on demand; [`agent-rules.md`](agent-rules.md) → *Batching and user interaction*
keeps the anchors — the rules that fire in most sessions — and this file keeps the rest.

Reply structure (prose / questions / next actions, and the fork test that decides when a section is warranted)
is not here: it lives in [`../CLAUDE.md`](../CLAUDE.md).

## Asking

- **One label space per turn.** When you number the options the user replies by number, do not also label anything else in the same turn with letters or numbers — sub-parts of the finding, halves of a defect, steps of a fix. The user answers with a bare token (`1`, `a`, `b fix`), and a turn carrying both `(a)`/`(b)` sub-parts *and* options `1`–`5` makes that token ambiguous: the reply has to be guessed at, and a wrong guess does the wrong work. Either fold the sub-parts into the option text, or give the options the same labels the sub-parts already use. (Surfaced on #5873: a defect was described as consequences `(a)` and `(b)` above a five-option disposition menu; the reply `a` was resolvable only because no option was lettered.)

- **Offering a narrow fix beside a systemic one? State how their *exposure* differs, not just the mechanism they share.** Two sites can share a defect's mechanism and be orders of magnitude apart in how often it can actually fire, and the option text is the only place the user sees that — they are choosing *scope*, so a description naming only the mechanism makes the systemic option read as the same bug at larger scale. On #5864 `CharTest11` re-read another provider's database **on every execution**, while the "same" hazard in `TestBase`'s reference-data layer is read **once and cached** for the process; only the first was failing. Presented as one class, the systemic option was picked and then reversed a turn later — *"I don't understand why you want to change somethng that works fine now?"* — after which the narrow fix was the whole change. The exposure difference was knowable before asking, and quantifying it is what makes the choice real rather than rhetorical.

- **Two-correction rule — stop repeating, reframe.** If the user corrects the same thing twice and the second attempt still misses, don't fire a third near-identical attempt or restate the correction louder. Stop and change the frame: state in one line what you believe the goal is, then split the task, ask for a concrete expected-output example, or surface a standing instruction that may be pulling against the correction. A third identical try usually signals a goal-level mismatch, not an execution slip — see [`bug-investigation.md`](bug-investigation.md) → *Repeated resistance to a correction signals goal misalignment*.

## Stopping and retrying

**"Surprising" means the *cause* is unknown — not that something went red.** A failure you predicted, a red test you wrote to be red, a probe that refuted its own hypothesis, or a build error whose fix is obvious from the message are all expected outcomes of the work: keep going and report what they showed. Stopping on those turns the rule into a per-step permission loop, which is its own failure mode (see the *Reply structure* fork test in [`../CLAUDE.md`](../CLAUDE.md)). Stop when you cannot explain the failure, when explaining it would need a decision that is the user's, or when the failure suggests the premise of the task is wrong.

- **Cap same-failure retry loops with a hard count, not just judgment.** When iterating on the *same* failing fix or a red CI leg, bound the retries numerically — roughly 3 local fix-and-retest attempts, fewer (1–2) for a full CI round-trip — then stop, summarize what was tried, and reconsider or ask rather than firing another near-identical attempt. A qualitative "am I flailing?" check misses slow token bleed across many almost-identical retries. This is the self-retry counterpart to *On a surprising failure* ([`agent-rules.md`](agent-rules.md) → *Batching and user interaction*), which stops on the *first* unexpected failure, and to the *two-correction rule* above, which counts *user* corrections; this one counts *your own* retries against one failure. The cap is a backstop, not a quota — stop earlier the moment attempts stop changing the outcome.

- **At the cap, ask for a budget rather than deciding alone.** Stopping and continuing are not the only options, and both are worse than the third: say what the next attempt would test, what it would cost, and what you'd conclude either way — then let the user grant or decline it. A probe that keeps *refuting hypotheses* is progress, not flailing, so a silent stop can abandon a live thread one build short of the answer; a silent continue spends the user's machine on your hunch. Announcing the cap also makes the spend legible. (#5737)

## Waiting on background work

- **After launching a background task, await its completion notification — don't poll the output file.** A `run_in_background` Bash task (a long build, a full test run) streams to its task-output file and fires an automatic `<task-notification>` when it exits. Re-`Read`ing that file before the notification arrives just returns *"Wasted call — file unchanged"* — pure round-trip waste with no new information. `Read` it once, when the notification lands (or when the user asks for progress). Poll only a genuine external heartbeat (e.g. `/test`'s `test-progress` JSON), never the captured stdout file of a task that will notify you anyway. **This covers any file the task writes — including your own `>` redirect target — and any tool you inspect it with.** The harness's *"Wasted call — file unchanged"* guard only fires for `Read`, so `Grep` / `grep -c` polling of a redirect log draws no pushback and silently burns a round-trip per call: the absence of a warning is not permission. And if a turn's only content would be "still waiting", don't emit it — the notification arrives on its own. (#1553, #5720)

**`ListAgents` and `sleep` are polling too, and they are the shapes that survive the rule above.** Waiting on a **subagent** feels different from waiting on a background Bash task — there is no output file to re-read, so the file-centric wording never fires — but `Agent` completions notify exactly the same way. `ListAgents` to see whether a subagent is still running, and `sleep N` to pass the time until it isn't, are both pure round-trip waste: the notification arrives on its own and neither call can make it arrive sooner. Reserve `ListAgents` for when you genuinely need the *roster* (which agents exist, what to `SendMessage`), never for liveness of something you just launched. The one exception is the liveness check in *Agent guardrails* — verifying that an agent claiming to be "still running" actually launched anything — which is a one-off probe against a specific claim, not a wait loop. (2026-09-01)

- **An unanswered question outranks a background notification — lead with the question, not the result.** When a `run_in_background` task completes while an interactive-walk item (or any question you posed) is still unanswered, the completion notification hands you a turn *the user never asked for*. Filling that turn with the task result silently buries the question: the user sees a wall of test output and no prompt, and the walk stalls until they ask what you were waiting on. Report the result in a line or two, then **restate the open item's question as the turn's last word**. Two corollaries: a notification is never an answer (the system-reminder says so, but the pull to read the turn as "progress" is strong), and if several notifications land in a row, name which item is still open rather than re-pasting the whole question each time. This is the interaction-side counterpart to the don't-poll rule above — same trigger, but the cost is the user's attention rather than a round-trip. (#5809)

- **Don't edit a source file while a background build / test run is in flight.** The compiler may read the file mid-edit and fail on a half-applied state, producing an error that describes your *intermediate* text rather than your change — so it reads as "the change is wrong" instead of "the build raced the editor". Queue the edit until the completion notification lands; if you've already started, expect to re-run rather than trusting the result. This is the write-side counterpart to the don't-poll rule above: same trigger (a `run_in_background` task you launched), opposite operation. (#5701)

## Spending context

- **Fetch an external binary document once, then mine it from disk.** When the authoritative answer lives in a `.docx` / `.pdf` / archive rather than a web page (LINQPad's `DataContextDrivers8.docx` is the recurring case — its macOS/XPF driver contract appears on no web page), download it **once** to `.build/.agents/`, extract the text, and `Grep` that file for each subsequent question. Re-downloading per question costs a multi-hundred-KB fetch plus a re-extract for every lookup. (#5786) Same logic as the `diff-reader.ps1` `writeDir` cache rule above: when the bytes are already on disk, read them.

- **Project the fields you need out of a script's JSON — never `ConvertTo-Json` a whole sub-object.** These payloads are large by design (`baselines-pr-scan.ps1` output has measured 1.7 MB) and the cost is invisible until it lands in context: dumping `$s.casts` at depth 3 spilled ~100 `perFileLosses` entries to obtain three aggregate numbers, where `$s.casts.perFileLosses | Group-Object <provider> | …` would have answered in three lines. Reach for `Group-Object` / `Measure-Object` / `Where-Object` + `Select-Object -First N` and print a formatted table; serialize a whole object only when you genuinely need every field. Same instinct as `Grep`'s default `head_limit`.

## Scope discipline

**"Hotfix" is a scope instruction, not just a description of urgency.** When the user frames work as a
hotfix — unblocking CI, stopping a bleed — ship only the change that unblocks, and nothing else. The
tempting additions are the *virtuous* ones: updating the doc table the change makes stale, fixing the
comment next to it, tidying the neighbouring entry. Those are ordinary good practice and exactly what
the framing excludes, because each one widens the diff a reviewer has to read while the tree is broken.
Note them and offer them as a follow-up instead. (Surfaced on #5845, a one-line CI provider disable, to
which a `Build/Azure/README.md` matrix-row update was added unprompted: *"dont touch azure readme, it's
hotfix"*.) The mirror still applies — a hotfix does not license leaving the prose wrong forever; it
licenses not fixing it *in this PR*.

**Write exactly the list you got approval for — widening it inside shared infrastructure needs its own ask.**
When the user approves a concrete set (processes to kill, files to delete, packages to bump) and you then
write it into a shared file — a CI template every job runs, `Directory.Packages.props`, a hook — put *that*
set in, not a superset you think is obviously implied. Additions you reasoned your way to were not part of
the analysis the user reviewed, so they land unreviewed in shared infrastructure. Propose them separately;
they're usually one sentence to describe and cheap to approve. (Surfaced on #5614: a reviewed list of 13
idle processes to kill was written into `test-workflow-windows.yml` together with four unreviewed
`Stop-Service -Force` calls on system services — `TrustedInstaller`, `wuauserv`, `WSearch`, `UsoSvc`. The
auto-mode classifier blocked the edit; re-proposed on its own, the same addition was approved immediately,
and it turned out to carry a real defect — `Stop-Service` has no `-NoWait`, so it blocks until the service
stops and hung five jobs inside the step.)
