# Development Standards

These conventions apply to all projects by David Shaevel. They are injected automatically via the davidshaevel-claude-toolkit plugin session-start hook.

---

## Development Approach

Use the **superpowers skills** whenever they are relevant. This includes but is not limited to:
- `superpowers:brainstorming` - Before any creative work or feature implementation
- `superpowers:writing-plans` - When planning multi-step tasks
- `superpowers:test-driven-development` - When implementing features or bugfixes
- `superpowers:systematic-debugging` - When encountering bugs or unexpected behavior
- `superpowers:verification-before-completion` - Before claiming work is complete
- `superpowers:requesting-code-review` - When completing major features
- `superpowers:using-git-worktrees` - When starting feature work that needs isolation

If there's even a 1% chance a skill applies, invoke it.

---

## Git Workflow

### Branch Naming Convention

```
claude/<issue-id>-<brief-description>    # branches created in Claude Code
codex/<issue-id>-<brief-description>     # branches created in Codex
david/<issue-id>-<brief-description>     # branches created by hand
```

Use the prefix matching the agent that created the branch. All three are valid; the prefix records provenance.

### Commit Message Format (Conventional Commits)

```
<type>(<scope>): <short description>

Longer description if needed.

Co-authored-by: <agent attribution — see below>

related-issues: TT-XXX
```

**Co-authored-by by agent** (use the current model/version of whichever agent authored the commit). The trailer key is lowercase `Co-authored-by:` per the standard Git trailer convention; the value must follow `Name <email>` format so GitHub can attribute the co-authorship:

| Agent | Trailer format |
| -- | -- |
| Claude Code | `Co-authored-by: Claude <model> <noreply@anthropic.com>` (e.g., `Co-authored-by: Claude Opus 4.7 <noreply@anthropic.com>`) |
| Codex | `Co-authored-by: OpenAI Codex (<model> <effort>) <noreply@openai.com>` (e.g., `Co-authored-by: OpenAI Codex (gpt-5.5 medium) <noreply@openai.com>`) |

Do not pin a stale model version — use the model actually running the session.

**Types:** `feat`, `fix`, `docs`, `chore`, `refactor`, `test`

**Scope Guidelines:**
- The scope should be a **descriptive word or hyphenated phrase** that identifies the feature or area being changed
- **DO NOT** use issue numbers (e.g., `TT-95`) as the scope — issue numbers go in `related-issues:`
- **DO NOT** use generic technology names (e.g., `terraform`) — be specific to the feature
- Good scopes: `pilot-light`, `portainer`, `contact-form`, `worktrees`
- Bad scopes: `TT-95`, `terraform`, `aws`

---

## Pull Request Process

**CRITICAL: NEVER MERGE WITHOUT CODE REVIEW**

1. **Push branch** to remote before creating the PR: `git push -u origin <branch-name>`
2. **Create PR** with descriptive title and comprehensive description (always use `--head <branch-name>` in worktree repos):
   ```bash
   gh pr create --head <branch-name> --title "..." --body "..."
   ```
3. **Wait for review** (Gemini Code Assist or human reviewer)
4. **Address feedback:**
   - CRITICAL and HIGH issues: Must fix
   - MEDIUM issues: Evaluate and decide
   - LOW issues: Fix if trivial, decline if YAGNI
5. **Post summary comment** with all fixes addressed
6. **Merge only after** all review feedback resolved

**Merge Strategy:** Always use **Squash and Merge** for pull requests.

```bash
# Merge PR with squash
gh pr merge <PR_NUMBER> --squash

# Delete the remote branch (--delete-branch doesn't work with worktrees)
git push origin --delete <branch-name>
```

---

## Code Review Replies

Reply **in the comment thread** (not top-level).

**IMPORTANT: Always start with `@gemini-code-assist` so they are notified of your response.**

```bash
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
gh api repos/${REPO}/pulls/<PR>/comments/<COMMENT_ID>/replies \
  -f body="@gemini-code-assist Fixed. Changed X to Y."
```

Every inline reply must include:
- **`@gemini-code-assist` at the start** (required for notification)
- What was fixed and how
- Technical reasoning if declining

### Post Summary Comment

Add a summary comment to the PR:

**IMPORTANT: Always start with `@gemini-code-assist` so they are notified.**

```markdown
@gemini-code-assist Review addressed:

| # | Feedback | Resolution |
|---|----------|------------|
| 1 | Issue X | Fixed in abc123 - Added validation for edge case |
| 2 | Issue Y | Fixed in abc123 - Refactored to use recommended pattern |
| 3 | Issue Z | Declined - YAGNI, feature not currently used |
```

**Resolution column format:** Include both the commit reference AND a brief summary of how the feedback was addressed.

For the full code review resolution workflow, use the `resolve-code-review` skill.

---

## Worktree Usage

This project uses a bare repository with git worktrees, allowing multiple branches to be checked out simultaneously.

**IMPORTANT: Flattened Folder Structure**

Worktrees are created directly in the project root, NOT in nested subdirectories.

```bash
# Correct structure:
project-name/
├── .bare                       # Bare repository
├── main                        # Main branch worktree
├── tt-140-feature-name         # Feature worktree (flat!)
└── tt-141-another-feature      # Another feature (flat!)

# WRONG - do not create nested structures like:
project-name/claude/tt-140-feature-name  # NO!
```

**Commands:**

```bash
# Create a new feature branch worktree (FLAT structure!)
cd /Users/dshaevel/workspace-ds/<project-name>
git worktree add <issue-id>-<brief-description> -b claude/<issue-id>-<brief-description>

# Remove a worktree when done
git worktree remove <worktree-folder-name>
```

### Worktree Cleanup - IMPORTANT

**Before removing a worktree**, merge all gitignored files from the feature worktree into main:

```bash
# NEVER use cp for gitignored files — always MERGE
# Use the session-handoff skill's "Worktree Cleanup" sections to merge:
#   - .envrc: line-by-line comparison
#   - CLAUDE.local.md: section-by-section comparison
#   - SESSION_LOG.md: interleave session history entries by date
```

**Workflow:**
1. Merge PR: `gh pr merge <PR_NUMBER> --squash`
2. Pull changes into main worktree: `cd main && git pull`
3. Delete remote branch: `git push origin --delete <branch-name>`
4. **Merge** worktree's `.envrc` into main's `.envrc` (see `session-handoff` skill — Worktree Cleanup section)
5. **Merge** worktree's `CLAUDE.local.md` into main's `CLAUDE.local.md` (see `session-handoff` skill — Worktree Cleanup section)
6. **Merge** worktree's `SESSION_LOG.md` into main's `SESSION_LOG.md` (see `session-handoff` skill — Worktree Cleanup section)
7. Remove the worktree: `git worktree remove <worktree-name>`

---

## Linear Conventions

**Team:** Team Tacocat

**Workflow:**
1. Create issue when starting new work
2. Update issue description as information evolves
3. Add comments for major milestones
4. Link related issues (blockers, related work)
5. Mark "Done" when phase complete

### Formatting (Issues, Projects, Initiatives)

**Critical: Never copy the `description` field from Linear API responses (e.g., `get_issue`, `get_project`, `get_initiative`) back into update calls.** The API returns descriptions with escaped characters (`\\n`, `\\*`, `\\|`) that compound with each read/write cycle, destroying formatting.

**When updating any Linear description (issues, projects, initiatives, status updates):**
1. **Write fresh markdown from scratch** — compose the full description as clean markdown, using the API response only as a reference for content
2. **Use actual newlines** — not `\n` escape sequences
3. **Use standard markdown** — `*`, `-`, `#`, `|` etc. without backslash escaping
4. **Links use standard markdown** — `[text](url)`, not `[text](<url>)` (Linear doesn't need angle brackets around URLs)

**Example — correct:**
```
## Section Header

**Bold text** and a [link](https://example.com)

| Col 1 | Col 2 |
| -- | -- |
| data | data |

* Bullet item
* Another item
```

**Example — wrong (what happens when you copy from get_issue):**
```
## Section Header\\\\n\\\\n**Bold text** and a [link](<https://example.com>)\\\\n\\\\n| Col 1 | Col 2 |\\\\n| -- | -- |\\\\n
```

---

## Environment Variables

- `.envrc` pattern with direnv for auto-sourcing
- `.envrc.example` committed as template with placeholder values
- Scripts error with a clear message if a required env var is missing
- **Never commit sensitive data** (kubeconfig, .envrc, credentials)

---

## Session Management

- Read `SESSION_LOG.md` at session start for context continuity
- Update `SESSION_LOG.md` at session end (use `session-handoff` skill)
- This enables seamless switching between Claude Code and Cursor sessions

---

## Key Conventions Summary

- **Always use feature branches** named `claude/<issue>-<description>` or `david/<issue>-<description>`
- **Conventional Commits** with `related-issues: TT-XXX`
- **Squash and merge** for all PRs
- **Never commit sensitive data** (use .envrc, CLAUDE.local.md — both gitignored)
- **Use superpowers skills** when they apply (1% chance = invoke)
- **Document decisions** in session notes / SESSION_LOG.md
