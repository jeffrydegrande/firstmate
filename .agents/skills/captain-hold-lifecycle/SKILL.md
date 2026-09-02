---
name: captain-hold-lifecycle
description: >-
  Agent-only policy for completing investigations and visual reviews without losing unresolved user calls, and for closing what the user owns with his actual words.
  Load before treating an investigation, scout report, structured review, or Lavish review as complete, before ending a visual review that exposed a user decision, when recording or routing the user's answer, and on any RECORD DIVERGENCE line the wake drain prints.
user-invocable: false
metadata:
  internal: true
---

# User-hold lifecycle

A decision is not a separate thing: it is simply a task waiting on the user.
The one primitive is an ordinary backlog task held for the user through `bin/fm-captain-hold.sh hold`; its identity is the task id, and that wrapper owns the deterministic mechanics this policy relies on.
The agent performs the semantic inventory because scripts must not infer user calls from report prose, visual-review artifacts, terminal output, or chat.

## Policy

Every unresolved question that belongs to the user and is discovered while producing, reading, presenting, or ending an investigation or visual review must be carried by a user-held task in the authoritative backlog of the home that owns the originating work before that work or review may be treated as complete.
Prefer holding the work item the question gates over minting a new row; create a new task only when no work item exists to hold.
Put the question and its options in the hold reason, and keep one held task per genuine gate: a multi-question review is one held task pointing at its report, not a row per question. Represent that task with exactly one board card that consolidates its questions and options; never fan one task id into duplicate same-key cards.
Register or re-hold through `bin/fm-captain-hold.sh hold`, which is idempotent per task id.
After inventorying the whole report and review surface, run `bin/fm-captain-hold.sh complete` with every user-held task id, or with `--none` only when the reviewed surface leaves nothing waiting on the user.
A completed investigation and an ended visual review use this same owner and completion command; a visual tool, including Lavish, never owns a parallel completion policy.
Run the command in the originating work's authoritative `FM_HOME`; secondmate-owned work registers in that secondmate home's backlog, and a question already held anywhere is never re-registered as a second row.
Do not close a user-held task merely because the originating investigation completed, its report was archived, its visual review ended, or its task was torn down.
Holding the work item the question gates is safe for exactly that reason: cleanup keeps such a row open with the finished work's deliverable recorded and returns it to the queue, so it still reads as the user's own call and only `answer` closes it.

Never close anything the user owns without recording what he actually said: `bin/fm-captain-hold.sh answer` writes his exact words into the task and closes it in the same act, with `--release` when the answer frees a user-gated work item to proceed instead of completing a question.
When the answer changes what a task must build, follow `AGENTS.md` section 7's Validate contract to preserve the user's words in the brief and steer the worker.
When the user says "later", that is an answer too: re-hold with `bin/fm-captain-hold.sh hold <id> --reason "<reason>" --until <date>` so the item leaves the live Needs You and resurfaces on its date, instead of leaving a live-looking card or fabricating a closure.
"A keyed answer closes its matching user-held task" is one capability with one owner, `bin/fm-captain-hold.sh answers`, and every channel that carries a user answer feeds it the same task id and answer; a channel never maps keys to tasks, records a decision, or closes anything itself.
Chat already feeds it through `bin/fm-send.sh --resolve-key`, and a captured-answer source feeds it once bound with `bin/fm-captain-hold.sh bind <source-id>`; bind before arming the source, and key each structured question by the held task's id.
An unbound source and a key that names no user-held task both simply feed nothing: the answer is still captured and firstmate is still woken, and closing falls back to the direct command above.
A user-held task closed outside this owner leaves no durable answer, so the completion gate keeps failing until `answer` records the decision the user actually gave.
Resolved findings, recommendations that need no user choice, and prose that merely sounds decision-like do not create held tasks.
Bearings reads the resulting structured state and must never compensate by scraping historical reports, visual-review artifacts, terminal output, chat, or other prose.

A user call can be written down twice - as the keyed status decision the fold reads, and as the backlog task held for the user - and those two records can disagree without either surface saying so.
`bin/fm-captain-hold.sh diverged` reports that contradiction and the wake drain prints it as `RECORD DIVERGENCE`; it closes nothing, because a user call closed wrongly leaves review entirely, which is worse than the noise.
Read such a line as "these two records disagree", never as "the user ruled and someone forgot to file it": a call can dissolve because its premise was false, or turn out to have been a question of fact rather than the user's to answer.
Reconcile it with what actually happened - `answer` when the user's own words exist to record, and a fresh `needs-decision` line re-opening the status decision when that resolution was not the user's word.
The absence of a routed work item is not a divergence and the guard never requires one: when the decision IS the deliverable there is nothing to route.

## Operating sequence

1. Read the complete investigation result and complete the visual review before declaring either complete.
2. Inventory only genuine unresolved choices that require the user, and find the task each one gates.
3. Hold that task - or create one user-held task for the review's open questions - with a concise reason carrying the question and options.
4. Run `complete` with the full user-held inventory for that review pass.
5. Relay the choices to the user as decisions from Bearings' Needs You section under `AGENTS.md` section 9; do not use the word hold in user chat.
6. Close each call only through `answer` (or a channel that feeds `answers`), through `--until` when the user defers it, or confirm a channel already closed it.
7. Confirm Bearings reflects the outcome: answered calls leave Needs You, released work resumes, and deferred calls sit in Charted Next with their date.

`bin/fm-captain-hold.sh --help` owns command syntax, close modes, legacy-identity compatibility, completion attestation, retry behavior, and close ordering.
`docs/captain-hold-lifecycle.md` records the mechanism and regression evidence without restating this policy.
