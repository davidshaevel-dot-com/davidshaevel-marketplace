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
claude/<issue-id>-<brief-description>
david/<issue-id>-<brief-description>
```

### Commit Message Format (Conventional Commits)

```
<type>(<scope>): <short description>

Longer description if needed.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>

related-issues: TT-XXX
```

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

1. **Create PR** with descriptive title and comprehensive description
2. **Wait for review** (Gemini Code Assist or human reviewer)
3. **Address feedback:**
   - CRITICAL and HIGH issues: Must fix
   - MEDIUM issues: Evaluate and decide
   - LOW issues: Fix if trivial, decline if YAGNI
4. **Post summary comment** with all fixes addressed
5. **Merge only after** all review feedback resolved

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

**Before removing a worktree**, copy any gitignored files to the main worktree:

```bash
cp <worktree-name>/.envrc main/.envrc
cp <worktree-name>/CLAUDE.local.md main/CLAUDE.local.md
cp <worktree-name>/SESSION_LOG.md main/SESSION_LOG.md
```

**Workflow:**
1. Merge PR: `gh pr merge <PR_NUMBER> --squash`
2. Pull changes into main worktree: `cd main && git pull`
3. Delete remote branch: `git push origin --delete <branch-name>`
4. Copy gitignored files from feature worktree to main
5. Remove the worktree: `git worktree remove <worktree-name>`

---

## Linear Conventions

**Team:** Team Tacocat

**Workflow:**
1. Create issue when starting new work
2. Update issue description as information evolves
3. Add comments for major milestones
4. Link related issues (blockers, related work)
5. Mark "Done" when phase complete

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
