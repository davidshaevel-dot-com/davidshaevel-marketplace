---
description: "Review a PR with subagents when no bot reviewer responded — three cycles (architectural, line-level, verification), each scoped to avoid duplicating the others"
---

Invoke the davidshaevel-claude-toolkit:self-hosted-review skill and follow it exactly as presented to you.

If the user named a PR number, review that PR. Otherwise detect the current branch's PR.

**Do not decide the handoff here — the skill's "When this applies" table decides it.**
Only `gemini-code-assist[bot]` reviews go to `resolve-code-review`; Codex, Qodo and any
other bot are handled inside this skill, because `resolve-code-review` filters on
`gemini-code-assist[bot]` and would match nothing.
