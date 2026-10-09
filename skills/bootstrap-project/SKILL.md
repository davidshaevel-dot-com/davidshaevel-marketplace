---
name: bootstrap-project
description: Use when creating a new project repository to initialize it with standard AGENTS.md, CLAUDE.md (import), .cursorrules, AGENTS.local.md, SESSION_LOG.md, and gitignore entries
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

### 2. Generate AGENTS.md

Create `AGENTS.md` from the project template (`templates/AGENTS.md.template`). Fill in the project-specific sections:

- Project Overview (name, description, technologies, project management)
- Architecture (placeholder diagram)
- Repository Structure (directory tree)
- Important File Locations (key paths)
- Helpful Commands (project-specific commands)
- Environment Variables (table of required vars)
- References (docs links, Linear project URL)

Keep the template's closing **Private policy** block as written.

**What NOT to include:** Git workflow, commit format, PR process, code review handling, worktree conventions — these are injected by the davidshaevel-agent-toolkit plugin automatically.

### 3. Generate CLAUDE.md

Create `CLAUDE.md` from `templates/CLAUDE.md.template`. It is exactly one line, `@AGENTS.md`, so Claude Code loads `AGENTS.md` through its import. Put no other content in it.

### 4. Generate .cursorrules

Create `.cursorrules` with:
- Session continuity instructions (read/write SESSION_LOG.md)
- Development conventions (adapted from plugin conventions)
- Project-specific context

### 5. Generate AGENTS.local.md

Create `AGENTS.local.md` from the template (`templates/AGENTS.local.md.template`; `templates/AGENTS.local.md.example` shows a filled-in one):
- Cloud account details (placeholder table)
- Infrastructure details
- GitHub repository info
- Linear project info
- Cost summary

### 6. Generate SESSION_LOG.md

Create `SESSION_LOG.md` with the empty scaffold:
- Current State section (all fields set to initial values)
- Empty Session History section

### 7. Update .gitignore

Append to `.gitignore` (if not already present):
```
# Agent context files (sensitive/local)
AGENTS.local.md
# legacy
CLAUDE.local.md
SESSION_LOG.md
```

### 8. Report

Output a checklist of what was created:
```
Project bootstrapped:
- [x] AGENTS.md — project-specific context
- [x] CLAUDE.md — imports AGENTS.md (@AGENTS.md)
- [x] .cursorrules — Cursor development rules
- [x] AGENTS.local.md — sensitive config template (gitignored)
- [x] SESSION_LOG.md — cross-agent memory (gitignored)
- [x] .gitignore — updated with agent files

Next steps:
1. Fill in AGENTS.local.md with actual account IDs and resource details
2. Review AGENTS.md and customize for your project
3. Start your first session — conventions will be injected by the plugin
```
