# Self-Hosted Agent PR Review — interim protocol

**Date:** 2026-08-10
**Linear issue:** [TT-472](https://linear.app/davidshaevel-dot-com/issue/TT-472)
**Linear project:** [Agentic Code Review Setup](https://linear.app/davidshaevel-dot-com/project/agentic-code-review-setup-410658537fa3)
**Status:** Shipped in plugin v1.4.1 as `skills/self-hosted-review/` + `/self-hosted-review`.
**Companion to:** `2026-05-13-multi-agent-pr-review-design.md` (TT-367) — currently on branch `claude/tt-367-multi-agent-pr-review`, not yet on `main`

---

## Why this exists

TT-367's design assumes reviewers are **external GitHub bots** that post reviews, with
the skill orchestrating *responses*. Its acceptance criterion #1 is "all three reviewers
post within 5 minutes of PR open."

That premise is currently false on `davidshaevel-dot-com`:

| Reviewer | State |
|---|---|
| Gemini Code Assist | Sunset **2026-07-17** |
| Qodo Merge | Never installed — TT-396 missed its cutoff |
| ChatGPT Codex | Quota-limited, single reviewer |

`laptop-maintenance` PR #3 (2026-08-10) reported `reviews=0` with zero bot comments. On
this org, PR-review coverage has been effectively **nil for ~4 weeks**.

This protocol needs no bot, no app install, and no quota. It produces the review instead
of responding to one.

**It does not replace TT-367.** TT-367 is the destination. This is the branch that
should be taken when reviewer auto-detection finds zero bots — and it stays useful
afterwards for pre-push review and for repos where bots aren't installed.

---

## Protocol

Three cycles, each with a **different lens** and an **explicit exclusion list**.

### Cycle 1 — architectural

Dispatch a `general-purpose` subagent using the `superpowers:requesting-code-review`
template. Give it the base/head SHAs, the change description, and the original
requirements or plan.

**Derive the base with `git merge-base`, not the PR's `baseRefOid`.** `baseRefOid` is the
base-branch tip; if the target branch advanced after the PR opened, a two-dot diff against
it renders every intervening commit as a reversion and the subagent reviews files the PR
never touched. Fetch the base ref first — a local `origin/<base>` may not exist in a
bare+worktree checkout.

Direct it toward:

* Plan alignment — does the implementation match what was asked? Are deviations
  justified or scope creep?
* Does the fix actually hold, including on machines/configs other than this one?
* Failure-mode and observability design — if this breaks, how would anyone find out?
* Deployment model — how does the change reach production, and what can drift?
* Documentation accuracy — do the doc claims match what the code does?

**Direct it away from** shell/style nits, local simplification, and micro-efficiency.
Tell it explicitly that a line-level pass will follow. Without this, cycles 1 and 2
overlap heavily.

### Cycle 2 — line-level

Run `/code-review high <branch>` (workflow-backed: multiple finder angles plus an
independent verifier per finding).

**Pass it an explicit do-not-report list** naming every cycle-1 finding that has already
been fixed. Then name the specific line-level concerns worth attention — quoting and
word-splitting, flag semantics, path handling, blast radius of destructive operations,
exit-code and `set -e` interactions, edge cases in counters.

Tell it to review the **whole file as it now stands**, not only the diff. Bugs introduced
by cycle-1 fixes live outside the original diff.

### Cycle 3 — verification pass

**Always runs.** It is the one lens no prior reviewer can have applied, because it
reviews the fixes made in response to them. On PR #3 the script went from ~100 to ~180
lines, and cycle 3 found four defects in code written to fix cycle 2.

If cycle 3 itself finds material issues, fix and re-run it scoped to those fixes. If a
re-run still finds material issues, stop and escalate — the change is too large to review
as one unit, or the design is wrong.

Scope it to the **final state of the changed files only**, and give it a
**do-not-relitigate list**: accepted risks, deliberate trade-offs, and anything the user
has already decided. Ask explicitly for "no new issues found" to be an acceptable answer
— a verification pass that manufactures findings to look useful is worse than useless.

Tell it to reproduce findings by execution rather than by reading.

### Between every cycle

Fix the findings before starting the next cycle. The next reviewer should see improved
code, not a backlog. This is what makes the cycles complementary rather than redundant.

---

## The load-bearing technique: negative scoping

Three cycles produced **near-zero duplicate findings** because each was told what *not*
to look at. This is the single most important part of the protocol.

| Cycle | Exclusion given |
|---|---|
| 1 | "Skip shell nits, local simplification, line-level efficiency — a separate pass covers those" |
| 2 | An explicit list of cycle-1 findings already fixed, marked do-not-report |
| 3 | A list of settled decisions, marked do-not-relitigate |

Without this, later cycles re-derive earlier findings and burn budget re-arguing
decisions the user already made.

---

## What each cycle actually caught on PR #3

15 findings, 14 fixed, on a change that began as a one-line plist edit.

**Cycle 1 — a regression the fix itself introduced.** The change moved `brew` from
never-reached to reached-every-run under launchd, while it sat *before* the rsync under
`set -euo pipefail`. Since `brew bundle dump` does network I/O, an offline run would have
aborted the script and skipped the dotfile backup entirely — strictly worse than the bug
being fixed. No line-level review would have found this; it required understanding what
the change did to the program's failure modes.

**Cycle 2 — two findings worth more than the original bug.**

* **7 of 19 backup entries pointed at paths that did not exist.** Five were never-existing
  paths; two pointed at the wrong location for an editor's config. Editor settings had
  never once been backed up, and every run still reported `OK`.
* **A trailing slash in the include list would have destroyed the entire backup.**
  `dirname ".config/"` is `.`, collapsing the destination to the backup root and turning
  `--delete` loose on it. Reproduced in a sandbox: three unrelated files were deleted.
  The comment directly above that list invites people to add entries.

**Cycle 3 — a wrong fix, and a wrong verification.** A cycle-2 fix used
`sort -t. -k1,1V` to pick the newest runtime version. That makes the sort key the leading
path component, identical for every candidate, so all keys tie and the lexicographic
fallback picks the *oldest*. The fix selected precisely the version its own comment said
to avoid.

Worse, the verification of that fix had been wrong: it checked that the output contained
five entries and stopped there. It did — the wrong five. **A count is not a content
check.**

---

## Rules that fall out of this

1. **Fix between cycles.** Each reviewer sees improved code.
2. **Always run the verification pass.** Reviewing your own fixes is a distinct step, not
   paranoia — and cycle-3 fixes need the same treatment, bounded by one re-run.
3. **Verify by content, not by shape.** Line counts, file sizes and exit codes are
   proxies. Compare against a known-good baseline.
4. **Carry decisions forward as exclusions.** Anything the user has decided is settled and
   must be named as do-not-relitigate, or reviewers will reopen it.
5. **"No new issues found" is a valid result.** Say so in the prompt.
6. **Post each cycle's findings to the PR** as a comment, including what was declined and
   why. Without bots there is no other record that review happened.
7. **Update the PR title and body when scope grows.** PR #3 ended at +374/−34 from a
   one-line change; its original title had become misleading.

---

## When to use which protocol

| Situation | Protocol |
|---|---|
| `gemini-code-assist` responding | `resolve-code-review` |
| Bots responding, multi-bot loop | TT-367 bounded loop — **not yet implemented**; use this protocol until it ships |
| Bot quota-exhausted | TT-367 escalation — **not yet implemented**; this protocol surfaces the same three choices |
| **A non-Gemini bot reviewed** (Codex, Qodo) | **This protocol** — `resolve-code-review` filters for Gemini and matches nothing |
| **No bots respond at all** | **This protocol** |
| Pre-push, before a PR exists | This protocol; cycle count per the scaling rules, not fixed at two |
| Repo with no bot install (personal, private, new) | This protocol |

TT-367's branch holds a spec and an implementation plan; nothing under `skills/` has
changed. Treat every TT-367 row above as a forward reference.

---

## Cost

PR #3's cycle 2 alone used 23 agents and ~900k subagent tokens. That is appropriate for a
change that runs unattended daily against a backup with `--delete`, and disproportionate
for a docs-only change.

Scale it: cycle 1 only for small changes; all three for anything destructive, scheduled,
or security-relevant.

---

## Shipped as a skill

**Resolved 2026-08-10: standalone skill now, delegation later.**

The protocol ships as `skills/self-hosted-review/` plus `commands/self-hosted-review.md`,
invocable as `/self-hosted-review`. Standalone rather than folded into
`resolve-code-review` for one practical reason: TT-367 is approved and will rewrite that
skill, so editing it now creates a conflict later. (Its branch holds only a spec and a
plan today — no `skills/` changes yet.) Once TT-367 ships, its
reviewer auto-detection should **delegate** to this skill when it finds zero bots — one
entry point, two implementations behind it.

A process that only exists as a doc is invoked by someone remembering it exists. That is
the same failure mode this repo's specs keep identifying elsewhere. The skill's
`description` field is the actual trigger: it names the observable condition (a PR with
zero bot reviews) so the situation invokes the process rather than the person having to.

## Open questions for implementation

1. **How much can be automated?** The negative-scoping lists are currently hand-written
   per cycle. Cycle 1's findings could be fed to cycle 2 programmatically, since
   `ReportFindings` already returns them structured.
3. ~~**Does this satisfy "never merge without code review"?**~~ **Answered** — ruled on in
   `conventions/development-standards.md`, which now names this protocol as the required
   path when no bot responds.
4. **Should findings be posted as inline PR comments** rather than summary comments?
   `/code-review --comment` supports this.

---

## References

* **Companion spec:** `2026-05-13-multi-agent-pr-review-design.md` (TT-367 bot orchestration)
* **Worked example:** [laptop-maintenance PR #3](https://github.com/davidshaevel-dot-com/laptop-maintenance/pull/3) — three cycle summaries posted as comments
* **Skills used:** `superpowers:requesting-code-review` (cycle 1), `/code-review high` (cycle 2), direct subagent dispatch (cycle 3)
