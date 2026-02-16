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

1. Check if `SESSION_LOG.md` exists in the project root (or worktree root)
2. If it exists, read the **Current State** section
3. Summarize the context for continuity:
   - What was the last agent and session?
   - What branch are we on?
   - What work is active?
   - Are there any blockers?
   - What are the next steps?

### At Session End

1. **Overwrite** the "Current State" section with current information
2. **Prepend** a new entry to the "Session History" section
3. **Trim** Session History to the last 10 sessions (remove oldest entries beyond 10)

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
