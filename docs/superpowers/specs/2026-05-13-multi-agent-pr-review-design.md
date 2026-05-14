# Design Spec — Multi-Agent Bounded PR-Review (Q2 2026 re-frame of TT-301)

**Date:** 2026-05-13 (revised 2026-05-14)
**Linear project:** [Agentic Code Review Setup](https://linear.app/davidshaevel-dot-com/project/agentic-code-review-setup-410658537fa3)
**Linear initiative:** [Development Tooling 2026 Q2](https://linear.app/davidshaevel-dot-com/initiative/development-tooling-2026-q2-ad16a7a0da98)
**Status:** Approved with 2026-05-14 revisions (Qodo row provisional + denylist deferred + cross-repo handoff explicit). Ready for `superpowers:writing-plans`.
**Issues:** TT-301 (davidshaevel-dot-com install + AC), TT-365 (CareLogue-org install), TT-367 (skill enhancement in davidshaevel-marketplace)
**Supersedes:** the original 2026-04-13 design (uninstall Codex / replace with Qodo)

---

## Goal

Codify CareLogue's converged bounded PR-review protocol — **3-round cap, 60-second polling, per-bot @-mentions, summary tagged to all reviewers, 4-wake-up extended-idle escalation, reviewer-exhausted handling** — into the canonical `davidshaevel-marketplace:resolve-code-review` skill so the protocol applies uniformly to every consuming repo across both GitHub orgs.

The skill, not any single repo's workflow doc, becomes the single source of truth. Existing per-repo workflow docs shrink to thin pointers + repo-specific overrides. The `chatgpt-codex-connector` install is retained (it remains valuable while credits exist); `qodo-merge` is added as the third reviewer alongside `gemini-code-assist` + `chatgpt-codex-connector`.

This is a **re-frame** of TT-301's original scope. The original "uninstall Codex / replace with Qodo" plan was based on a single quota-exhaustion event in CareLogue PR #8. Subsequent CareLogue work converged on treating the quota event as an **escalation case**, not a reason to uninstall. The valuable signal Codex provides during its credit window outweighs the periodic interruption.

---

## Why now

The 2026-05-13 audit flagged TT-301 as 18 days past due. Re-dating in place would have left the original (now-obsolete) scope. Instead, this re-frame:

* Captures evidence from 4+ weeks of CareLogue PR-review work (commits b381cbb, 67f367b, 844855e, 0856401)
* Reflects the real direction of automated multi-agent code review: more reviewers, bounded loop, generalized escalation
* Pulls the canonical protocol into the plugin where it can be inherited by future consumers (CareLogue, davidshaevel-dot-com, future repos in either org)

---

## Scope

### In scope (TT-367 — skill enhancement, davidshaevel-marketplace repo)

1. **Refactor `skills/resolve-code-review/SKILL.md`** to embed the bounded-loop procedure
2. **Add `skills/resolve-code-review/WORKFLOW.md`** — human-facing canonical reference (3-round rationale, polling cadence reasoning, escalation framework, per-reviewer config table)
3. **Add `skills/resolve-code-review/scripts/pr-bot-status.sh`** — bash gh-api wrapper for reviewer state + usage-limit phrase detection (ported from CareLogue_App)
4. **Add `skills/resolve-code-review/PERMISSIONS.md`** — required `Bash(...)` allow patterns, rationale, and merge instructions for consuming repos
5. **Update plugin version** + release
6. **Establish the PERMISSIONS.md pattern** as the template for future plugin skill cleanups

### In scope (TT-301 — davidshaevel-dot-com install + acceptance)

1. Install `qodo-merge` GitHub App on `davidshaevel-dot-com` (all repos)
2. Configure Qodo account (David's, scoped to davidshaevel-dot-com); add Christina + David as licensed users
3. Merge TT-367's `PERMISSIONS.md` content into this repo's `.claude/settings.local.json`
4. Open a no-op test PR in `development-tooling-2026-q2`
5. Invoke the enhanced `resolve-code-review` skill end-to-end
6. Acceptance criteria below

### In scope (TT-365 — CareLogue-org install)

1. Install `qodo-merge` GitHub App on `CareLogue-org` (all repos)
2. Configure Qodo account (Christina's, scoped to CareLogue-org); add Christina + David as licensed users
3. Merge TT-367's `PERMISSIONS.md` content into CareLogue_App's `.claude/settings.local.json`
4. Verify on a fresh test PR in CareLogue_App
5. Owner: Christina

### Out of scope (deferred)

* **Retrofit `session-handoff`, `backup-local-config`, `bootstrap-project` with PERMISSIONS.md pattern** — file as separate Backlog issue under Agentic Code Review Setup project after TT-367 ships
* **Self-hosted PR-Agent via GitHub Actions** (Option B from original 2026-04-13 design) — still deferred until real-world usage data warrants it
* **Decision on expanding Codex credit allocation** — separate spending decision
* **Automated merge of PERMISSIONS.md into .claude/settings.local.json** (e.g., a helper script) — manual merge only in v1; revisit if friction is high

### Non-goals

* Building a multi-agent reviewer *product*. This is a workflow protocol + per-org install + plugin skill update, not a new system.
* Replacing any reviewer that's working. Codex stays installed.
* Changing the reviewer mix for repos with non-default needs. Per-repo allowlist override handles this.

---

## Architecture (layered)

The skill enhancement adds four artifacts under `skills/resolve-code-review/` in the `davidshaevel-marketplace` repo:

| # | Layer | Artifact | Audience | Role |
|---|---|---|---|---|
| 1 | Procedure | `SKILL.md` | Agent | Bounded-loop orchestration. References WORKFLOW.md for deeper rationale and pr-bot-status.sh for state detection. |
| 2 | Reference | `WORKFLOW.md` | Human | Canonical protocol doc: 3-round rationale, polling cadence reasoning, escalation framework, per-reviewer config table. Replaces the role of CareLogue's local workflow doc. |
| 3 | Detection | `scripts/pr-bot-status.sh` | Agent (via skill) | gh-api wrapper. Detects reviewer comments, classifies state (active / silent / exhausted), surfaces usage-limit phrases. Bash, no Python. |
| 4 | Permissions | `PERMISSIONS.md` | Consuming-repo owner | Required `Bash(...)` allow patterns + rationale + manual merge instructions for `.claude/settings.local.json`. |

The per-reviewer config — `{bot_user, mention, usage_limit_phrases[], severity_taxonomy}` — lives **inside WORKFLOW.md** as a markdown table (not a separate JSON file), so the skill and human-facing doc share one source of truth.

Per-repo workflow docs (CareLogue's `docs/CareLogue_PR_Review_Workflow_v1_2026-05-07.md`, future davidshaevel-dot-com equivalent) shrink to **thin pointers** to WORKFLOW.md plus repo-specific overrides (e.g., "Codex intentionally excluded here" or "Qodo not installed yet").

---

## Bounded loop semantics (locked, not configurable)

* **Max 3 review rounds per PR.** Round 1 = first feedback. Round 2 = re-review of fixes. Round 3 = final pass. >3 rounds signals a structural problem (PR too large / fundamental disagreement / stylistic-only) and triggers escalation.
* **60-second polling cadence.** Locked. Aligns with the Anthropic prompt-cache 5-min TTL (keeps cache warm), is the runtime floor for `ScheduleWakeup`, and the rigor of the loop comes from per-bot tracking + idle-window logic, not from interval tuning.
* **4-wake-up extended-idle limit.** If a bot has been silent across 4 wake-ups while others have ack'd, treat as escalation.
* **Round = (push → wait → resolve-code-review → reply per-thread → summary → push fix → wait for ack).**
* **Per-bot @-mention** required in inline replies. The agent identifies which bot left the comment and addresses the reply to that bot.
* **Summary comment tagged to all observed reviewers** (e.g., `@gemini-code-assist @chatgpt-codex-connector @qodo-merge`).

---

## Reviewer model

### Auto-detection

The skill discovers reviewers by querying the PR's `issues/<PR>/comments` and `pulls/<PR>/comments` endpoints and selecting authors with `type: Bot` (or matching the per-reviewer config table). No hardcoded reviewer list.

This handles all three reviewer counts (1, 2, 3) gracefully without skill changes. A repo with only Gemini installed produces the same bounded loop with N=1.

### Per-reviewer config table (in WORKFLOW.md)

| Reviewer | Bot user | Mention | Severity taxonomy | Usage-limit phrase(s) |
|---|---|---|---|---|
| Gemini Code Assist | `gemini-code-assist[bot]` | `@gemini-code-assist` | CRITICAL / HIGH / MEDIUM / LOW | (none observed) |
| ChatGPT Codex | `chatgpt-codex-connector[bot]` | `@chatgpt-codex-connector` | P0 / P1 / P2 / P3 | `Codex usage limits have been reached` |
| Qodo Merge | `qodo-merge-pro[bot]` (provisional — confirm during install) | `@qodo-merge-pro` for reply notifications; primary invocation is slash commands `/review` `/improve` `/describe` `/ask` typed directly in PR comments | v1: Critical / High / Medium / Low. v2: numeric rank 1/2/3 (informational / remediation_recommended / action_required) with High/Medium/Low filter thresholds. Confirm which is active during install. | Not documented verbatim; free tier cap is 30 PRs/month/org. Observe and capture exact text on first quota event. |

Qodo's row carries **provisional values** sourced from documentation review (2026-05-14) rather than the original "fully TBD" framing. They are still subject to final confirmation during TT-301's install step because:

1. **Recent rebrand.** Qodo Merge (v1) was rebranded to Qodo / Qodo Review (v2) on 2026-02-04. v1 docs are now marked legacy. The install will reveal which version the marketplace app currently provisions and which severity scheme is in effect.
2. **Slash-command interaction model.** Unlike Gemini and Codex, Qodo's primary interaction pattern is slash commands (`/review`, `/improve`, etc.) typed as PR comments, not @-mention replies. The `@qodo-merge-pro` mention is for notification only; the skill's reply-to-bot loop must accommodate this dual model (auto-review on PR-open + on-demand slash commands).
3. **Usage-limit phrase requires observation.** Documentation describes the quota (30 PRs/month/org free tier) but does not publish the exact comment text the bot posts on quota exhaustion. Captured empirically on first occurrence, then committed to this table.

### Per-repo allowlist override

A consuming repo can override discovery by adding to `.claude/settings.local.json`:

```jsonc
{
  "resolve-code-review": {
    "reviewers": {
      "exclude": ["chatgpt-codex-connector[bot]"]   // explicitly not in use here
    }
  }
}
```

This is the escape hatch for repos that intentionally run a subset.

---

## Reviewer-exhausted escalation (generalized from CareLogue §4.2)

When `pr-bot-status.sh` detects any reviewer's usage-limit phrase in a comment, the skill **classifies the PR as an escalation case** and surfaces three valid responses to the user (without picking one automatically):

1. **Merge on remaining reviewers with explicit human ack.** Used when the credit-exhausted reviewer is non-critical and the remaining reviewers have signed off.
2. **Top up that reviewer's credits / upgrade plan.** Used when the reviewer is providing valuable signal and credit-exhaustion is causing frequent escalations.
3. **Hold PR until reviewer is back.** Used when the reviewer is critical and a non-trivial wait (e.g., until the weekly Codex quota refresh) is acceptable.

The skill does **not** silently converge on the surviving reviewers. The user makes the explicit decision per PR.

This logic generalizes — any reviewer added in the future (CodeRabbit, future Anthropic-hosted bot, etc.) inherits the same escalation framework by adding a row to the per-reviewer config table.

---

## Permissions manifest pattern (new, established by TT-367)

Each plugin skill ships a `PERMISSIONS.md` file declaring the `Bash(...)` allow patterns it requires to run end-to-end without prompting. The file has:

1. **Required patterns** — exact `Bash(...)` strings matching Claude Code's prefix-matching rules
2. **Rationale** — why each pattern is safe (defense-in-depth context)
3. **Merge instructions** — copy-paste path into the consuming repo's `.claude/settings.local.json`
4. **Validation procedure** — how to confirm YOLO mode works after merging (see TT-301's AC #4)

**v1 is manual merge.** The user copies the documented patterns into their consuming repo's settings. Future automation (a `setup-permissions.sh` helper) is deferred until friction warrants it.

### Critical patterns the skill needs

These are example patterns the resolve-code-review skill needs (final list lives in PERMISSIONS.md):

* `Bash(gh pr view *)` — read PR metadata
* `Bash(gh pr diff *)` — read PR diff
* `Bash(gh pr comment *)` — post summary comment
* `Bash(gh pr merge *)` — squash merge after acceptance
* `Bash(gh api repos/*/pulls/*)` — paginated comments, replies, reviews
* `Bash(gh api repos/*/issues/*)` — issue-level PR comments (Codex usage-limit notice lands here)
* `Bash(gh repo view *)` — detect current repo
* `Bash(git push)`, `Bash(git push origin *)` — push fix commits
* `Bash(*pr-bot-status.sh*)` — invoke the detection script (final path matches the plugin install location; exact pattern discovered during implementation)

### Deny patterns — deferred

Explicit deny patterns are **deferred from v1**. The earlier draft of this spec proposed `Bash(gh api -X*)` to block HTTP-method-override mutations, but prefix matching can't reliably filter mid-command flags (e.g., `--method POST`, or endpoints that mutate via default HTTP verbs without `-X`), so a partial denylist provides decorative rather than load-bearing defense. v1 of PERMISSIONS.md ships allow-patterns only; the design of meaningful deny rules (or a tighter allow-only approach) is **out of scope for TT-367** and will be revisited when concrete attack patterns or near-miss incidents surface.

### Why per-skill, not plugin-wide

Each skill has different permission needs. `resolve-code-review` needs gh + git. `backup-local-config` needs rclone. `session-handoff` may need none. Per-skill manifests keep the consuming repo's `.claude/settings.local.json` minimal — only merge the patterns for skills you actually use.

---

## Acceptance criteria (TT-301 — refined)

On a fresh test PR in `davidshaevel-dot-com/development-tooling-2026-q2`:

1. **All three reviewers post within 5 minutes of PR open.** `gemini-code-assist` posts a code review. `chatgpt-codex-connector` posts a code review OR an issue-level "Codex usage limits have been reached" notice. `qodo-merge` posts a code review.
2. **Enhanced skill orchestrates the bounded loop:** 60-second polling cadence, max 3 rounds, per-bot @-mention replies in each comment thread, summary comment tagged to all 3 reviewers, 4-wake-up extended-idle escalation.
3. **Codex usage-limit handling correctly classifies as escalation.** When the limit is hit (real-world or simulated), the skill does NOT silently converge — it surfaces the 3 valid responses to the user.
4. **YOLO-mode validation passes:** zero permission prompts during end-to-end skill execution on the test PR. All required Bash patterns covered by PERMISSIONS.md merged into `.claude/settings.local.json`.
5. **Plugin release:** enhanced `resolve-code-review` skill is committed and merged to `main` in `davidshaevel-marketplace` (Claude Code loads from the marketplace dir; no tagging required).
6. **Evidence:** screenshots of the 3 reviews + the orchestrated loop + the merged PR attached to TT-301.

TT-365's acceptance mirrors #1, #2, #3 for `CareLogue-org/CareLogue_App` once TT-367 ships.

---

## Decision log

| # | Question | Decision | Rationale |
|---|---|---|---|
| Q1 | Is the skill enhancement its own Linear issue? | Yes — TT-367 (own issue) blocks TT-301 + TT-365 | Skill change is mechanically different from the install (different repo, different commit/release cycle). Lets the enhancement ship first and both installs exercise it. |
| Q2 | Where does the canonical workflow doc live? | `skills/resolve-code-review/WORKFLOW.md` in `davidshaevel-marketplace` | Aligns with CareLogue workflow doc's stated intent (§3): the skill is canonical. Per-repo docs become thin pointers + overrides. |
| Q3 | How does the skill determine reviewers? | Auto-detect bot-typed authors from PR comments; per-repo allowlist override | Handles 1/2/3+ reviewers gracefully without redesign. Explicit override for intentional exclusions. |
| Q4 | Is the 3-round cap configurable? | No — locked at 3 in the skill | CareLogue's reasoning generalizes: >3 rounds signals PR-too-large / fundamental-disagreement / stylistic-only. Per-PR overrides would defeat the bound. |
| Q5 | How is Qodo's usage-limit handled? | Same generalized escalation framework as Codex | Consistent UX across reviewers; user makes explicit per-PR decision; no silent coverage loss. |
| Q6 | How is `pr-bot-status.sh` ported? | As-is — bash port to plugin's `scripts/` dir | Bash is good for gh-api orchestration; no Python dep for plugin consumers; CareLogue's script works today. |
| Q7 | Where do per-skill permissions live? | `PERMISSIONS.md` per skill + manual merge into consuming repo's `.claude/settings.local.json` | Simplest, transparent, works today. Automation deferred until friction warrants it. |
| Q8 | How is YOLO mode validated? | Test-PR-based acceptance criterion in TT-301 (#4) | Real conditions, end-to-end. Ties validation to a concrete deliverable rather than a synthetic smoke test. |
| Q-split | How is the cross-cutting permissions pattern scoped? | α — TT-367 grows to cover resolve-code-review only | Smallest blast radius. Other 3 plugin skills retrofit in a separate Backlog issue. |
| Q9 (2026-05-14) | Qodo row in config table — leave fully TBD, or fill with provisional values from docs review? | Provisional values + explicit confirmation step during install | Documentation review on 2026-05-14 surfaced enough partial signal (bot user pattern, slash-command interaction model, v1 Critical/High/Medium/Low taxonomy) to fill the table with confidence intervals. Qodo v1→v2 rebrand (2026-02-04) means values may have shifted; install step verifies. |
| Q10 (2026-05-14) | Deny-pattern guidance in PERMISSIONS.md — include in v1 or defer? | Defer. Allow-patterns only in v1; deny-pattern design is out of scope for TT-367 | Prefix matching can't reliably filter mid-command flags (`--method POST`, default-verb mutations on non-`-X` calls). Partial denylist provides decorative rather than load-bearing defense. Revisit when concrete attack patterns surface. |
| Q11 (2026-05-14) | Spec/plan colocation — keep both here, both in plugin, or split? | Copy spec to plugin repo before writing-plans; plugin copy is authoritative post-handoff; this repo's copy is historical | This repo owns Q2 initiative narrative; plugin repo owns plan execution. Cross-repo copy + drift discipline aligns with the spec's own "kill per-repo docs drift" principle, applied to the spec itself. |

---

## References

* **Original spec (pre-reframe):** `docs/superpowers/specs/2026-04-13-agentic-code-review-setup-design.md`
* **CareLogue workflow doc:** `docs/CareLogue_PR_Review_Workflow_v1_2026-05-07.md` (387 lines) in CareLogue_App repo
* **CareLogue bot-status script:** `scripts/pr-bot-status.sh` in CareLogue_App repo
* **Current plugin skill (pre-enhancement):** `~/.claude/plugins/marketplaces/davidshaevel-marketplace/skills/resolve-code-review/SKILL.md` (164 lines)
* **Sibling Linear issues:** TT-301 (davidshaevel-dot-com install), TT-365 (CareLogue-org install), TT-367 (skill enhancement — to be filed)
* **Driver audit:** `weekly-agendas/audits/2026-05-13-davidshaevel-dot-com.md`

---

## Spec/plan colocation (cross-repo handoff)

The spec and the implementation plan live in **different repos** because the design straddles two scopes: this repo owns the Q2 initiative narrative, while `davidshaevel-marketplace` owns the plugin code. Without a clear rule, that split risks the same per-repo-docs-drift pattern this spec is trying to kill.

**Rule:** before invoking `superpowers:writing-plans` for TT-367, copy this spec from `development-tooling-2026-q2/main/docs/superpowers/specs/` to `davidshaevel-marketplace/main/docs/superpowers/specs/` with the same filename. After that copy:

1. **`davidshaevel-marketplace`** owns the **plan execution** artifacts:
   * The copied spec (canonical for implementation)
   * The plan doc generated by `superpowers:writing-plans` at `docs/superpowers/plans/2026-05-13-multi-agent-pr-review-design.plan.md` (filename mirrors the spec)
   * The feature worktree, PR, and merged commits
2. **`development-tooling-2026-q2`** keeps **the original spec** as Q2-initiative history. A short trailer is appended noting "Implementation continues in `davidshaevel-marketplace`" with a link to the copied spec.
3. **Drift discipline:** if the spec needs revision after the cross-repo copy, edit the plugin-repo copy first (where implementation is happening), then mirror back to this repo with a follow-up commit. The plugin-repo copy is **authoritative** post-handoff; this repo's copy is **historical**.

This handoff is documented as part of the implementation plan's "Setup" section so future readers who land in either repo can trace it.

---

## Next steps after spec approval

1. **User reviews this spec** (you are here — 2026-05-14).
2. ~~**File TT-367**~~ — **Already done 2026-05-13.** TT-367 filed, marked blocking TT-301 + TT-365.
3. **Cross-repo spec copy.** Copy this file from `development-tooling-2026-q2/main/docs/superpowers/specs/` to `davidshaevel-marketplace/main/docs/superpowers/specs/` with the same filename. Append the implementation-handoff trailer to this repo's copy.
4. **Invoke `superpowers:writing-plans`** in `davidshaevel-marketplace` to convert the copied spec → implementation plan. Plan doc lands at `davidshaevel-marketplace/main/docs/superpowers/plans/2026-05-13-multi-agent-pr-review-design.plan.md`.
5. **Plan execution** in a new worktree on `davidshaevel-marketplace` (ships independently from this repo). Includes filling in the Qodo row's provisional values with empirically-confirmed ones during the install acceptance phase.
6. **TT-301 + TT-365 unblock** once TT-367 ships and the plugin marketplace pulls the updated skill.
