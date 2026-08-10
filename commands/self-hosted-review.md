---
description: "Review a PR with subagents when no bot reviewer responded — three cycles (architectural, line-level, verification), each scoped to avoid duplicating the others"
---

Invoke the davidshaevel-claude-toolkit:self-hosted-review skill and follow it exactly as presented to you.

If the user named a PR number, review that PR. Otherwise detect the current branch's PR
with `gh pr view --json number,reviews,comments`. Confirm there are zero bot reviews
before proceeding — if a bot has reviewed, use `resolve-code-review` instead.
