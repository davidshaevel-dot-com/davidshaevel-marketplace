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
3. **Trim** Session History to the last 30 sessions (remove oldest entries beyond 30)

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
6. **Trim** Session History to the last 30 entries

**Important:** Do NOT use `cp <worktree>/SESSION_LOG.md main/SESSION_LOG.md` — this destroys session history from other worktrees that was previously merged into main.

### Worktree Cleanup (Merging .envrc)

When a feature worktree is being removed after a PR merge, the worktree's `.envrc` must be **merged** into main's `.envrc` — never copied with `cp`.

`.envrc` is a flat key=value shell file. Compare line by line.

**Merge process:**

1. Read `main/.envrc`
2. Read `<worktree>/.envrc`
3. Compare **line by line**:
   - If only one version has a real value (the other has a placeholder or is empty), keep the real value
   - If both have the same value, keep it as-is
   - If values differ and one is clearly more recent or complete, keep the more complete/recent value
   - If values differ and neither is clearly "better", keep main's value and add a comment flagging the conflict: `# MERGE CONFLICT: worktree had "<worktree value>"`
4. If the worktree version has variables that main does not, append them
5. Write the merged result to `main/.envrc`

**Important:** Do NOT use `cp <worktree>/.envrc main/.envrc` — main's copy may contain updates made independently while the feature worktree was active.

### Worktree Cleanup (Merging CLAUDE.local.md)

When a feature worktree is being removed after a PR merge, the worktree's `CLAUDE.local.md` must be **merged** into main's `CLAUDE.local.md` — never copied with `cp`.

`CLAUDE.local.md` is a structured markdown document with tables and sections. Unlike SESSION_LOG.md, it is not chronological — it requires section-by-section comparison.

**Merge process:**

1. Read `main/CLAUDE.local.md`
2. Read `<worktree>/CLAUDE.local.md`
3. Compare **section by section** (e.g., "Cloud Account Details", "Infrastructure Details", "Cost Summary")
4. For each section:
   - If only one version has content (the other has placeholders like `[account ID or name]` or `...`), keep the version with real content
   - If both have the same value, keep it as-is
   - If values differ and one is clearly more recent or complete (e.g., an updated cost figure, a filled-in URL replacing a placeholder), keep the more complete/recent value
   - If values differ and neither is clearly "better", keep main's value and add a comment flagging the conflict: `<!-- MERGE CONFLICT: worktree had "value" -->`
5. Write the merged result to `main/CLAUDE.local.md`

**Important:** Do NOT use `cp <worktree>/CLAUDE.local.md main/CLAUDE.local.md` — main's copy may contain updates made independently while the feature worktree was active.

### SESSION_LOG.md Format

```markdown
# Session Log

## Current State
- Agent: [Claude Code | Cursor]
- Branch: [current branch]
- Last session: [ISO timestamp]
- Active work: [issue ID and description]
- Blockers: [list or "None"]
- Next steps: [bullet list]

## Session History

### YYYY-MM-DD HH:MM — [Agent Name]
**What was done:**
- [bullet list]

**Decisions made:**
- [bullet list]

**Open questions:**
- [list or "None"]
```

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
- **Merge, never copy** — during worktree cleanup, merge all gitignored files into main: `.envrc` (line-by-line), `CLAUDE.local.md` (section-by-section), and `SESSION_LOG.md` (interleave by date). Never use `cp` to overwrite.
- **When in doubt, ask** — if you cannot determine which worktree the session belongs to, ask the user rather than guessing.
