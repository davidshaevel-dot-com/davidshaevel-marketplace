---
name: session-handoff
description: Use at the start and end of every coding session, or when switching between Claude Code and Cursor, to maintain cross-agent memory persistence via SESSION_LOG.md
---

# Session Handoff

Read and write SESSION_LOG.md for cross-agent memory persistence. Enables seamless switching between Claude Code and Cursor sessions.

## Usage

This skill is used automatically:
- **Session start:** Read SESSION_LOG.md to restore context
- **Session end:** Update SESSION_LOG.md to preserve context for the next session

## Process

### At Session Start

#### Standard repos (no worktrees)

1. Check if `SESSION_LOG.md` exists in the project root
2. If it exists, read the **Current State** section
3. Summarize the context for continuity:
   - What was the last agent and session?
   - What branch are we on?
   - What work is active?
   - Are there any blockers?
   - What are the next steps?

#### Bare + worktree repos

1. Check if `.bare/` directory exists at cwd — if so, this is a bare+worktree repo
2. Run `git worktree list` to discover all worktrees
3. Check each worktree directory for a `SESSION_LOG.md`
4. Based on how many are found:
   - **Zero found:** This is a fresh start, no context to restore
   - **One found:** Read it automatically and confirm with the user
   - **Multiple found:** Show a summary of each (worktree name, branch, active work from the "Current State" `Active work:` line) and ask the user which worktree to resume in
5. Read the selected worktree's SESSION_LOG.md and summarize as usual

### At Session End

#### Standard repos (no worktrees)

1. **Overwrite** the "Current State" section with current information
2. **Prepend** a new entry to the "Session History" section
3. **Trim** Session History to the last 10 sessions (remove oldest entries beyond 10)

#### Bare + worktree repos

1. Determine which worktree the session worked in by checking the branch used throughout the conversation
2. Map that branch to its worktree directory (via `git worktree list`)
3. Write SESSION_LOG.md **only** to that worktree's directory
4. **Never** update another worktree's SESSION_LOG.md

### Worktree Cleanup (Merging Session History)

When a feature worktree is being removed after a PR merge, the worktree's session history must be **merged** into main's SESSION_LOG.md — never copied with `cp`.

**Merge process:**

1. Read `main/SESSION_LOG.md` Session History entries
2. Read `<worktree>/SESSION_LOG.md` Session History entries
3. **Interleave** both sets of entries by date (newest first)
4. Update main's **Current State** to reflect the post-merge project state (e.g., mark the completed work as done, update next steps)
5. Write the merged result to `main/SESSION_LOG.md`
6. **Trim** Session History to the last 10 entries

**Important:** Do NOT use `cp <worktree>/SESSION_LOG.md main/SESSION_LOG.md` — this destroys session history from other worktrees that was previously merged into main.

### SESSION_LOG.md Format

```markdown
# Session Log

## Current State
- Agent: [Claude Code | Cursor]
- Session ID: [session/conversation ID]
- Branch: [current branch]
- Last session: [ISO timestamp]
- Active work: [issue ID and description]
- Blockers: [list or "None"]
- Next steps: [bullet list]

## Session History

### YYYY-MM-DD HH:MM — [Agent Name] (Session: [ID])
**What was done:**
- [bullet list]

**Decisions made:**
- [bullet list]

**Open questions:**
- [list or "None"]
```

### Finding the Session ID

- **Claude Code:** The session ID is in the JSONL transcript filename, typically a UUID like `9e8d2ac4-d0a0-4563-b79e-2a7dc416a1ad`. You can find it from the `CLAUDE_SESSION_ID` environment variable if available, or from the transcript path.
- **Cursor:** Use the conversation/composer ID from the Cursor IDE.

### Rules

- Keep entries concise — bullet points, not paragraphs
- Focus on **decisions** and **blockers**, not play-by-play
- The "Current State" section should be enough to resume work without reading history
- Session History provides deeper context if needed
- Always update SESSION_LOG.md before ending a session, even if work was minor

#### Worktree Rules

- **One worktree, one SESSION_LOG.md** — each worktree maintains its own independent session log. Never read or write another worktree's SESSION_LOG.md.
- **Branch determines the target** — at session end, the branch you worked on determines which worktree's SESSION_LOG.md to update. If you're unsure, ask the user.
- **Bare repo root has no SESSION_LOG.md** — in bare+worktree repos, SESSION_LOG.md lives inside worktree directories (e.g., `main/SESSION_LOG.md`, `tt-154.../SESSION_LOG.md`), never at the bare repo root.
- **Merge, never copy** — during worktree cleanup, interleave session history entries by date into main's SESSION_LOG.md. Never use `cp` to overwrite.
- **When in doubt, ask** — if you cannot determine which worktree the session belongs to, ask the user rather than guessing.
