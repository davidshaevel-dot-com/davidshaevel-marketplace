---
name: self-hosted-review
description: Use before merging any PR when no automated bot reviewer has responded — check with `gh pr view <N> --json reviews,comments` and if there are zero bot reviews, run this instead of merging unreviewed. Also use for pre-push review of destructive, scheduled, or security-relevant changes. Produces the review with subagents rather than waiting for a bot.
---

# Self-Hosted Agent Review

Produce a code review using subagents when no bot reviewer exists. Three cycles with
different lenses, each given an explicit exclusion list so they complement rather than
duplicate each other.

**Canonical rationale and worked example:** `docs/superpowers/specs/2026-08-10-self-hosted-agent-review.md`
(TT-472). Read it if you need the reasoning; this file is the procedure.

## When this applies

Run `gh pr view <N> --json reviews,comments,additions,deletions` first.

| Observed | Action |
|---|---|
| **`gemini-code-assist[bot]` reviewed** | Use `resolve-code-review` — it is built for that bot specifically |
| **Another bot reviewed** (Codex, Qodo, …) | **Address its comments here.** See below — `resolve-code-review` cannot process them yet |
| **Zero bot reviews** | **Run this** |
| No PR yet, destructive change | Run cycles 1–2 pre-push |

As of 2026-08-10 on `davidshaevel-dot-com`, zero is the common case: Gemini Code Assist
sunset 2026-07-17, Qodo Merge is not installed, Codex is quota-limited.

**"No bot responded" is not review.** Do not merge on it.

### Why non-Gemini bots are handled here

`resolve-code-review` hardcodes `gemini-code-assist[bot]` in its comment filters and
instructs replies to `@gemini-code-assist`. Handing a Codex or Qodo review to it means
its filter matches nothing and any reply @-mentions a bot that no longer exists. Until
TT-367 lands multi-bot support, handle those reviews in this skill:

1. Read every bot's comments — filter by the actual reviewer, not a hardcoded login:
   ```bash
   gh api "repos/$REPO/pulls/$PR/comments" \
     --jq '.[] | select(.user.type == "Bot") | {id, user: .user.login, path, line, body}'
   ```
2. Fix or decline each, then reply **in-thread @-mentioning the bot that wrote it**:
   ```bash
   gh api "repos/$REPO/pulls/$PR/comments/$COMMENT_ID/replies" \
     -f body="@<that-bot> Fixed. <what changed and why>"
   ```
3. Post a summary comment tagging every bot that reviewed.
4. A single bot's review is **not** a substitute for the cycles below on destructive or
   scheduled changes — it is one lens. Run the cycles it did not cover.

## Scale to the change

Every PR gets at least one review pass. The convention is *never merge without code
review*; this table decides how much, not whether.

| Change | Cycles |
|---|---|
| Docs, comments, config text | Cycle 1 only |
| Ordinary code edits | 1 and 2 |
| Destructive, scheduled, unattended, security-relevant, or touching backups | All three |
| Already has a substantive bot or human review | Judgement — run the cycles that review did not cover; none is acceptable if it genuinely covered the change |

Cycle 2 alone can use 20+ agents. That is right for a script that deletes files on a
schedule and wrong for a typo fix. **Scaling down is not the same as skipping** — a PR
with no review record at all should not merge.

## Procedure

### Before starting

Take the base and head from the **PR itself**, not from a hardcoded branch. A PR may not
target `main`, and a local `origin/main` ref can be stale or absent — in a bare+worktree
checkout `git rev-parse origin/main` can fail outright.

```bash
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
eval "$(gh pr view "$PR" --json baseRefOid,headRefOid,baseRefName \
  -q '"BASE_SHA=\(.baseRefOid)\nHEAD_SHA=\(.headRefOid)\nBASE_REF=\(.baseRefName)"')"
```

Reviewing pre-push with no PR yet? Then use the merge base against the branch you will
target, not `HEAD~1`:

```bash
BASE_SHA=$(git merge-base HEAD origin/"$BASE_REF")
HEAD_SHA=$(git rev-parse HEAD)
```

Create a todo per cycle you intend to run.

### Cycle 1 — architectural

Invoke `superpowers:requesting-code-review` and dispatch a `general-purpose` subagent
with its template. Supply the SHAs, what was built, and the original requirements.

Point it at:

- Plan alignment — does this match what was asked? Are deviations justified or creep?
- Does the fix hold on configurations other than this machine?
- Failure-mode and observability design — if this breaks, how would anyone find out?
- Deployment model — how does the change reach production, what can drift?
- Documentation accuracy — do the doc claims match the code?

**Steer it away from** shell style, local simplification, and micro-efficiency. State
that a line-level pass follows. Omitting this is the main cause of duplicate findings.

**Fix the findings before cycle 2.**

### Cycle 2 — line-level

```
/code-review high <branch>
```

Append to the args:

1. A **SCOPE NOTE** listing every cycle-1 finding already fixed, marked do-not-report.
2. The specific line-level concerns that matter here — quoting and word-splitting, flag
   semantics, path handling, blast radius of destructive operations, exit-code and
   `set -e` interactions, counter edge cases.
3. An instruction to review the **whole file as it now stands**, not only the diff —
   cycle-1 fixes introduce code outside the original diff.

Call `ReportFindings` once with the verified findings. **Fix them before cycle 3.**

### Cycle 3 — verification pass

**Required whenever cycle 2's fixes materially changed the code.** Skip only if the
fixes were trivial.

Dispatch one `general-purpose` subagent scoped to the **final state of the changed files
only**. Give it:

- A **do-not-relitigate list**: accepted risks, deliberate trade-offs, anything the user
  has already decided.
- An instruction to reproduce findings **by execution**, not by reading.
- Explicit permission for "no new issues found" to be the answer. A verification pass
  that manufactures findings to look useful is worse than none.

### After the cycles

1. Re-call `ReportFindings` with an `outcome` per finding (`fixed`, `skipped`,
   `no_change_needed`).
2. **Post each cycle's findings to the PR as a comment**, including what was declined and
   why. Without bots this is the only record that review happened.
3. **Update the PR title and body if scope grew.** A PR that started as one line and
   ended at +374/−34 has a misleading title.
4. Merge per the repo's convention (squash), then clean up worktree and branches.

## Rules

1. **Fix between cycles.** Each reviewer sees improved code, not a backlog.
2. **Verify by content, not by shape.** Line counts, file sizes and exit codes are
   proxies. Compare against a known-good baseline. A fix once "passed" because the output
   had five lines — it did, the wrong five.
3. **Carry decisions forward as exclusions.** Anything the user decided is settled and
   must be named, or reviewers reopen it.
4. **Review your own fixes.** Cycle 3 exists because cycle-2 fixes are unreviewed code.
5. **Never merge on "no bot responded."**

## Relationship to `resolve-code-review`

`resolve-code-review` handles the case where bots *do* respond — bounded loop, per-bot
@-mentions, reviewer-exhausted escalation (TT-367).

This skill handles N=0. They are complementary. Once TT-367 ships, its reviewer
auto-detection should delegate here when it finds zero bots, giving one entry point
regardless.

## Permissions

Needs `Bash(gh pr view *)`, `Bash(gh pr comment *)`, `Bash(gh pr edit *)`,
`Bash(gh pr merge *)`, `Bash(git rev-parse *)`, plus whatever the repo's tests and
linters require. See `resolve-code-review/PERMISSIONS.md` once TT-367 establishes that
pattern.
