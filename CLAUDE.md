# davidshaevel-marketplace - Claude Context

<!-- If CLAUDE.local.md exists, read it for additional context (account IDs, resource details, etc.) -->

## Project Overview

Personal multi-agent development plugin providing development conventions, skills, and project templates. It standardizes development workflows across all of David Shaevel's projects by injecting conventions at session start, providing reusable skills, and offering project bootstrapping templates.

**As of v1.4.0, the plugin supports both Claude Code and OpenAI Codex CLI.** The same `hooks/hooks.json`, `conventions/development-standards.md`, and `skills/` serve both agents — Claude Code loads them via `.claude-plugin/plugin.json`, Codex via `.codex-plugin/plugin.json`. The plugin `name` remains `davidshaevel-claude-toolkit` for install-command and marketplace-registration stability; a vendor-neutral rename is a future v2.0.0 consideration.

**Key Technologies:**
- **Languages:** Shell (Bash/Zsh), Markdown
- **Platforms:** Claude Code Plugin System + Codex CLI plugin system
- **Tooling:** jq, gh CLI, direnv

**Project Management:**
- **Issue Tracking:** Linear (Team Tacocat)
- **Version Control:** GitHub
- **Branching Strategy:** Feature branches with PR workflow

---

## Architecture

```
Plugin Load Flow (both agents share hooks/, conventions/, skills/):
  Claude Code starts            Codex starts
    → .claude-plugin/plugin.json   → .codex-plugin/plugin.json
    → Registers skills, commands, hooks
    → session-start hook fires (hooks/hooks.json → hooks/session-start.sh)
      → Injects conventions/development-standards.md into context
    → Skills and commands available for the session
```

Both manifests point at the same `skills/` directory and the same `hooks/hooks.json`. The hook output contract (JSON with `hookSpecificOutput.additionalContext`) is identical across agents, so `session-start.sh` is unchanged.

---

## Repository Structure

```
davidshaevel-marketplace/
│
├── .bare/                             # Bare git repository
├── .git                               # Points to .bare
│
├── main/                              # Main branch worktree
│   ├── .claude-plugin/                # Claude Code plugin manifest
│   │   ├── plugin.json                # Plugin definition (skills, hooks, commands)
│   │   └── marketplace.json           # Marketplace metadata
│   │
│   ├── .codex-plugin/                 # Codex CLI plugin manifest (v1.4.0+)
│   │   └── plugin.json                # Codex plugin definition (skills key + interface)
│   │
│   ├── commands/                      # Slash commands
│   │   ├── bootstrap-project.md       # /bootstrap-project command
│   │   └── resolve-code-review.md     # /resolve-code-review command
│   │
│   ├── conventions/                   # Auto-injected conventions
│   │   └── development-standards.md   # Git, PR, worktree, Linear conventions
│   │
│   ├── config/                        # Plugin configuration
│   │   ├── backup-config.json         # Backup config (gitignored, repo-specific)
│   │   └── backup-config.json.example # Backup config template (committed)
│   │
│   ├── scripts/                       # Plugin scripts
│   │   ├── backup-local-config.sh     # Backs up gitignored files to Google Drive
│   │   └── cloud_setup_script.sh      # One-time cloud-environment snapshot setup
│   │
│   ├── docs/                          # Internal documentation
│   │   ├── 2026-04-23_cloud_environment_test_observations.md  # Cloud-env fix list (TT-338..344)
│   │   ├── cloud_backup_setup.md      # rclone Shared-Drive backup setup
│   │   ├── cloud_session_setup.md     # Cloud session bootstrap walkthrough
│   │   └── superpowers/               # Notes on the superpowers plugin (separate)
│   │
│   ├── hooks/                         # Plugin hooks
│   │   ├── hooks.json                 # Hook definitions
│   │   ├── session-start.sh           # Session start hook script
│   │   └── run-hook.cmd               # Windows hook runner
│   │
│   ├── skills/                        # Plugin skills
│   │   ├── bootstrap-project/SKILL.md # Project initialization skill
│   │   ├── resolve-code-review/SKILL.md # Code review resolution skill
│   │   ├── session-handoff/SKILL.md   # Session handoff skill
│   │   └── backup-local-config/SKILL.md # Local file backup skill
│   │
│   ├── templates/                     # Project templates
│   │   ├── CLAUDE.md.template         # CLAUDE.md template
│   │   ├── CLAUDE.local.md.template   # CLAUDE.local.md template
│   │   ├── CLAUDE.local.md.example    # Example CLAUDE.local.md
│   │   ├── SESSION_LOG.md.template    # SESSION_LOG.md template
│   │   ├── cursorrules.template       # .cursorrules template
│   │   └── gitignore-additions.txt    # Gitignore entries for agent files
│   │
│   ├── CLAUDE.md                      # Public project context (this file)
│   ├── CLAUDE.local.md                # Sensitive project context (gitignored)
│   ├── SESSION_LOG.md                 # Cross-agent memory (gitignored)
│   ├── README.md                      # Public documentation
│   └── LICENSE                        # MIT License
│
└── <feature-worktrees>/               # Feature branch worktrees (flat!)
```

---

## Important File Locations

| File | Purpose |
|------|---------|
| `.claude-plugin/plugin.json` | Plugin manifest — defines skills, commands, hooks |
| `conventions/development-standards.md` | Development conventions injected at session start |
| `config/backup-config.json` | Backup destination and file list configuration |
| `scripts/backup-local-config.sh` | Shell script that backs up gitignored files via rclone |
| `scripts/cloud_setup_script.sh` | One-time cloud-environment snapshot setup (gstack, bun, rclone) |
| `docs/2026-04-23_cloud_environment_test_observations.md` | Cloud-session bootstrap fix list (tracked via TT-338..TT-344) |
| `docs/cloud_backup_setup.md` | rclone Shared-Drive backup setup walkthrough |
| `docs/cloud_session_setup.md` | Cloud session bootstrap walkthrough |
| `hooks/session-start.sh` | Hook that injects conventions into Claude context |
| `skills/*/SKILL.md` | Skill definitions (bootstrap, code review, session handoff) |
| `skills/backup-local-config/SKILL.md` | On-demand backup skill definition |
| `templates/*` | Project bootstrap templates |

---

## Helpful Commands

```bash
# Test the session-start hook locally
bash hooks/session-start.sh

# Check plugin structure
cat .claude-plugin/plugin.json | jq .

# Version bump (update plugin.json version field)
jq '.version = "X.Y.Z"' .claude-plugin/plugin.json > tmp && mv tmp .claude-plugin/plugin.json
```

---

## Environment Variables

No environment variables required for the plugin itself. Individual projects bootstrapped by this plugin use `.envrc` with direnv.

---

## References

- **GitHub Repository:** [davidshaevel-marketplace](https://github.com/davidshaevel-dot-com/davidshaevel-marketplace)
- **Linear Project:** [Team Tacocat](https://linear.app/davidshaevel-dot-com)
