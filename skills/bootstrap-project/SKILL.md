---
name: bootstrap-project
description: Use when creating a new project repository to initialize it with standard CLAUDE.md, .cursorrules, CLAUDE.local.md, SESSION_LOG.md, and gitignore entries
---

# Bootstrap Project

Initialize a new project with the standard file structure for Claude Code and Cursor development.

## Usage

```
/bootstrap-project
```

## Process

### 1. Gather Project Information

Ask the user for:
- **Project name** (e.g., `davidshaevel-k8s-platform`)
- **Brief description** (one sentence)
- **Tech stack** (e.g., Terraform, Kubernetes, Go)
- **Cloud providers** (e.g., Azure, GCP, AWS)
- **Linear project URL** (if exists)
- **GitHub organization** (default: `davidshaevel-dot-com`)

### 2. Generate CLAUDE.md

Create `CLAUDE.md` from the project template. Fill in the project-specific sections:

- Project Overview (name, description, technologies, project management)
- Architecture (placeholder diagram)
- Repository Structure (directory tree)
- Important File Locations (key paths)
- Helpful Commands (project-specific commands)
- Environment Variables (table of required vars)
- References (docs links, Linear project URL)

**What NOT to include:** Git workflow, commit format, PR process, code review handling, worktree conventions — these are injected by the davidshaevel-claude-toolkit plugin automatically.

### 3. Generate .cursorrules

Create `.cursorrules` with:
- Session continuity instructions (read/write SESSION_LOG.md)
- Development conventions (adapted from plugin conventions)
- Project-specific context

### 4. Generate CLAUDE.local.md

Create `CLAUDE.local.md` from the template:
- Cloud account details (placeholder table)
- Infrastructure details
- GitHub repository info
- Linear project info
- Cost summary

### 5. Generate SESSION_LOG.md

Create `SESSION_LOG.md` with the empty scaffold:
- Current State section (all fields set to initial values)
- Empty Session History section

### 6. Update .gitignore

Append to `.gitignore` (if not already present):
```
# Agent context files (sensitive/local)
CLAUDE.local.md
SESSION_LOG.md
```

### 7. Report

Output a checklist of what was created:
```
Project bootstrapped:
- [x] CLAUDE.md — project-specific context
- [x] .cursorrules — Cursor development rules
- [x] CLAUDE.local.md — sensitive config template (gitignored)
- [x] SESSION_LOG.md — cross-agent memory (gitignored)
- [x] .gitignore — updated with agent files

Next steps:
1. Fill in CLAUDE.local.md with actual account IDs and resource details
2. Review CLAUDE.md and customize for your project
3. Start your first session — conventions will be injected by the plugin
```
