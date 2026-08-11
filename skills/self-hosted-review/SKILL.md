---
name: self-hosted-review
description: Use before merging any PR when no automated bot reviewer has responded, OR when the only reviews came from a bot other than gemini-code-assist (Codex, Qodo) since resolve-code-review cannot process those. Check with `gh pr view <N> --json reviews,comments`. Also use for pre-push review of destructive, scheduled, or security-relevant changes, and for any change to review process, conventions, or files injected into other repos. Produces the review with subagents rather than waiting for a bot.
---

# Self-Hosted Agent Review

Produce a code review using subagents when no bot reviewer exists. Three cycles with
different lenses, each given an explicit exclusion list so they complement rather than
duplicate each other.

> **Requires Claude Code.** This procedure depends on subagent dispatch, the
> `/code-review` command, the `ReportFindings` tool, and the `superpowers` plugin. Codex
> CLI has none of these — the other skills in this plugin are portable, this one is not.

**Canonical rationale and worked example:** in the plugin repo at
`docs/superpowers/specs/2026-08-10-self-hosted-agent-review.md` (TT-472). That file does
not ship to consuming repos; this one is the procedure and stands alone.

## When this applies

Find the PR if the user did not name one, then inspect it — separate commands, per the
permission rule below:

```bash
gh pr view --json number -q .number
```

```bash
gh pr view <N> --json reviews,comments
```

| Observed | Action |
|---|---|
| **`gemini-code-assist[bot]` reviewed** | Use `resolve-code-review` — it is built for that bot specifically |
| **Another bot reviewed** (Codex, Qodo, …) | **Address its comments here.** See below — `resolve-code-review` cannot process them yet |
| **Zero bot reviews** | **Run this** |
| No PR yet | Run this pre-push |

As of 2026-08-10 on `davidshaevel-dot-com`, zero is the common case: Gemini Code Assist
sunset 2026-07-17, Qodo Merge is not installed, Codex is quota-limited.

**"No bot responded" is not review.** Do not merge on it.

This table decides **which protocol** applies. How many cycles to run is decided solely by
"Scale to the change" below — the two never overlap, so they cannot disagree.

### Why non-Gemini bots are handled here

`resolve-code-review` hardcodes `gemini-code-assist[bot]` in its comment filters and
instructs replies to `@gemini-code-assist`. Handing a Codex or Qodo review to it means
its filter matches nothing and any reply @-mentions a bot that no longer exists. Until
TT-367 lands multi-bot support, handle those reviews in this skill:

1. Read bot feedback from **all three** endpoints. They hold different things and none is
   a superset of the others. **Paginate everywhere:** default `per_page` is 30, so a PR
   with several review rounds silently drops later items.

   **a. Review bodies** — a bot's overall verdict and severity summary. Missing this reads
   only the nits and calls it "all feedback addressed":
   ```bash
   gh api "repos/<owner>/<repo>/pulls/<PR>/reviews?per_page=100" --paginate \
     --jq '.[] | select(.user.type == "Bot") | select(.body != "") | {id, user: .user.login, state, body}'
   ```

   **b. Inline review comments** — the per-line findings:
   ```bash
   gh api "repos/<owner>/<repo>/pulls/<PR>/comments?per_page=100" --paginate \
     --jq '.[] | select(.user.type == "Bot") | {id, user: .user.login, path, line, in_reply_to_id, body}'
   ```

   **c. Issue-level comments** — standalone conversation comments, and often where a
   **quota-exhaustion notice** lands:
   ```bash
   gh api "repos/<owner>/<repo>/issues/<PR>/comments?per_page=100" --paginate \
     --jq '.[] | select(.user.type == "Bot") | {id, user: .user.login, body}'
   ```

   **Do not filter on `in_reply_to_id == null`.** A bot's in-thread follow-up ("this is
   still wrong") carries a non-null value and would be discarded, so the thread reads as
   resolved when it isn't. Instead fetch every comment, group by thread, and skip only
   threads whose **last** comment is already your reply — that also prevents duplicate
   replies when the skill is re-run.

   **If any bot reports a usage or quota limit, stop and surface the choice** rather than
   quietly proceeding on the reviewers that remain. Three valid responses — merge on the
   remaining reviewers with explicit acknowledgement, top up that reviewer, or hold until
   it recovers. The user decides; do not converge silently. (This mirrors TT-367's
   reviewer-exhausted escalation so the interim path doesn't establish a habit TT-367
   would have to unwind.)
2. Fix or decline each, then reply **@-mentioning the bot that wrote it**.

   **Route the reply by where the comment came from — the ID namespaces are disjoint.**
   An issue-comment ID sent to the pulls endpoint 404s (observed: pulls IDs ~3.7e9,
   issues IDs ~5.2e9).

   From query **b** (inline) — reply in-thread. Note the path includes the PR number;
   omitting it also 404s:
   ```bash
   gh api "repos/<owner>/<repo>/pulls/<PR>/comments/<COMMENT_ID>/replies" \
     -f body="@<that-bot> Fixed. <what changed and why>"
   ```

   From query **a** (review body) or **c** (issue comment) — there is no thread to reply
   into. Post an issue-level comment instead:
   ```bash
   gh api "repos/<owner>/<repo>/issues/<PR>/comments" \
     -f body="@<that-bot> Re: your review — <what changed and why>"
   ```
3. Post a summary comment tagging every bot that reviewed.
4. A single bot's review is **not** a substitute for the cycles below on destructive or
   scheduled changes — it is one lens. Run the cycles it did not cover.

## Scale to the change

Every PR gets at least one review pass. The convention is *never merge without code
review*; this table decides how much, not whether.

Scale by **reach and reversibility**, not file extension. A one-line change to a file
injected into every consuming repo outranks a hundred lines in a throwaway script.

| Change | Cycles |
|---|---|
| Docs, comments, config text local to one repo | Cycles 1 and 3 |
| Ordinary code edits | Cycles 1, 2 and 3 |
| Destructive, scheduled, unattended, security-relevant, or touching backups | All three |
| **Review process, conventions, or anything injected into other repos** | **All three**, regardless of file type |
| Already reviewed by a bot or human | Run the lenses that review did not cover — see below. **Cycle 3 always runs** on the final state |

**Cycle 3 is the floor.** Whatever else is skipped, the final state gets a verification
pass. That is the one cycle no prior reviewer can have performed, because it reviews the
fixes made in response to them.

Judge "already covered" by **lens**, not by volume — architectural, line-level,
verification are checkable; "substantive" is not. One bot's inline comments are the
line-level lens and nothing more.

Cycle 2 alone can use 20+ agents. That is right for a script that deletes files on a
schedule and wrong for a typo fix. **Scaling down is not the same as skipping.**

## Procedure

### Before starting

Take the base and head from the **PR itself**, not from a hardcoded branch. A PR may not
target `main`, and a local `origin/main` ref can be stale or absent — in a bare+worktree
checkout `git rev-parse origin/main` fails outright with *"ambiguous argument"*.

> **Run each `gh` command standalone.** Do not wrap them in `$(...)`, `eval`, or chain
> with `&&`. Claude Code evaluates each part of a chain independently for permission
> matching, so `REPO=$(gh repo view ...)` will not match a `Bash(gh repo view *)`
> permission even though the bare command would. Run the command alone and read the
> values from the tool result.

```bash
gh repo view --json nameWithOwner -q .nameWithOwner
```

```bash
gh pr view <PR> --json headRefOid,baseRefName
```

`headRefOid` is the head SHA. **Do not use `baseRefOid` as the base** — it is the
base-branch *tip*, not the branch point. If `main` has advanced since the PR opened (the
common case here, since branches sit waiting for a bot that never answers), a two-dot diff
against it shows every intervening commit as a *reversion*, and subagents review files the
PR never touched.

Derive the real base with `merge-base` against the ref named by `baseRefName`:

```bash
git fetch origin <baseRefName>
```

```bash
git merge-base HEAD FETCH_HEAD
```

The `fetch` is not optional. A local `origin/<base>` ref may not exist at all — in a
bare+worktree checkout `git rev-parse origin/main` fails outright — and `FETCH_HEAD`
sidesteps that by not depending on a local remote-tracking ref.

Reviewing pre-push with no PR yet? Same two commands, naming the branch you will target.
Take each separately, per the permission rule above.

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

**Always runs.** It is the one lens no prior reviewer can have applied, because it
reviews the fixes made in response to them.

Dispatch one `general-purpose` subagent scoped to the **final state of the changed files
only**. Give it:

- A **do-not-relitigate list**: accepted risks, deliberate trade-offs, anything the user
  has already decided.
- An instruction to reproduce findings **by execution**, not by reading.
- Explicit permission for "no new issues found" to be the answer. A verification pass
  that manufactures findings to look useful is worse than none.

#### When cycle 3 finds material issues

Cycle-3 fixes are themselves unreviewed code — the same argument that justifies this
cycle. So:

1. Fix them, then **re-run cycle 3 scoped to those fixes only**.
2. If a re-run still produces material findings, **stop and escalate.** Two failed
   verification passes means the change is too large to review as one unit or the design
   is wrong. Split the PR or revisit the approach — do not keep looping.

A trivial re-run finding (a typo, a doc wording fix) does not require another pass. Use
the same "material" test as elsewhere: would it change behaviour or mislead a reader?

### Handling a finding you disagree with

Do not silently drop it. Invoke `superpowers:receiving-code-review` for rigor, then
either fix it or record it via `ReportFindings` as `skipped` / `no_change_needed` **with
the reason**. A finding you cannot reproduce is `no_change_needed` plus a note on what
you tried — not a deletion. Otherwise "14 of 15 fixed" is a number with no audit trail.

### After the cycles

1. Re-call `ReportFindings` with an `outcome` per finding (`fixed`, `skipped`,
   `no_change_needed`).
2. **Post each cycle's findings to the PR as a comment**, including what was declined and
   why. Without bots this is the only record that review happened.
3. **Update the PR title and body if scope grew.** A PR that started as one line and
   ended at +374/−34 has a misleading title.
4. **Commit and push the fixes.** Everything above happened in the working tree; none of
   it is on the PR yet.
   ```bash
   git add -A
   ```
   ```bash
   git commit -m "fix(<scope>): address review findings"
   ```
   ```bash
   git push
   ```
5. **Confirm the PR reflects the fixes before merging.** `gh pr merge --squash` squashes
   the last *pushed* head — merging with unpushed fixes puts the unfixed branch on `main`
   while the summary comment claims otherwise, and step 6's cleanup then deletes them.
   ```bash
   gh pr view <PR> --json headRefOid -q .headRefOid
   ```
   ```bash
   git rev-parse HEAD
   ```
   These must match. If they don't, go back to step 4.
6. Merge per the repo's convention (squash), then clean up worktree and branches.

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

This skill handles N=0 and non-Gemini bots. They are complementary. Once TT-367 ships,
its reviewer auto-detection should delegate here when it finds zero bots, giving one
entry point regardless.

**The two "threes" are unrelated.** TT-367 locks 3 **rounds** — bot feedback round-trips
with 60-second polling between them. This skill has 3 **cycles** — review lenses applied
within a single round, no polling, nothing to wait for. The counts coinciding is a
coincidence; do not try to reconcile them.

## Permissions

Every command this skill instructs, and why. An incomplete list here blocks the skill
mid-run — and because wrapped commands don't satisfy permission matching (see "Before
starting"), there is no workaround by composing them.

```jsonc
{
  "permissions": {
    "allow": [
      "Bash(gh repo view *)",     // resolve owner/repo
      "Bash(gh pr view *)",       // PR metadata: headRefOid, baseRefName
      "Bash(gh pr comment *)",    // post each cycle's findings
      "Bash(gh pr edit *)",       // update title/body when scope grows
      "Bash(gh pr merge *)",      // squash merge after acceptance
      "Bash(gh api *)",           // read bot comments, post in-thread replies
      "Bash(git rev-parse *)",    // confirm HEAD matches the pushed PR head
      "Bash(git merge-base *)",   // derive the real base (never baseRefOid)
      "Bash(git fetch *)",        // fetch the base ref; local origin/<base> may not exist
      "Bash(git diff *)",         // cycles 1 and 3 read the diff between base and head
      "Bash(git add *)",          // stage fixes made between cycles
      "Bash(git commit *)",       // commit them
      "Bash(git push *)",         // push fixes so the PR reflects them before merge
      "Bash(git worktree *)"      // cleanup after merge
    ]
  }
}
```

Plus whatever the repo's own tests and linters require, since cycles reproduce findings
by execution.

**`Bash(gh api *)` is broad** — it covers mutations, not just reads. A tighter
`Bash(gh api repos/*)` would express the intent better, but the calls here quote their
path (`gh api "repos/..."`), and prefix matching against a quoted argument is not
something to assume works. Verify on a real run before narrowing it; a pattern that looks
tighter but silently fails to match is worse than an honest broad one.

This list is provisional. When TT-367 establishes the `PERMISSIONS.md` pattern, move it
there with rationale and merge instructions, alongside `resolve-code-review`'s.
