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
│   │   ├── resolve-code-review.md     # /resolve-code-review command
│   │   └── self-hosted-review.md      # /self-hosted-review command
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
│   │   ├── resolve-code-review/SKILL.md # Bot-review resolution (Gemini-specific)
│   │   ├── self-hosted-review/SKILL.md # Subagent review when no bot responds
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
| `skills/*/SKILL.md` | Skill definitions (bootstrap, code review, self-hosted review, session handoff) |
| `skills/self-hosted-review/SKILL.md` | Multi-cycle subagent PR review for when no bot reviewer responds (TT-472) |
| `docs/superpowers/specs/2026-08-10-self-hosted-agent-review.md` | Rationale + worked example for the self-hosted review protocol |
| `skills/backup-local-config/SKILL.md` | On-demand backup skill definition |
| `templates/*` | Project bootstrap templates |

---

## Helpful Commands

```bash
# Test the session-start hook locally
bash hooks/session-start.sh

# Check plugin structure
cat .claude-plugin/plugin.json | jq .

# Version bump — THREE manifests, but marketplace.json keeps its version NESTED.
# Do NOT loop `jq '.version = ...'` over all three: marketplace.json has no top-level
# .version, so that creates a bogus key and leaves the real one at the old number.
V=X.Y.Z
jq --arg v "$V" '.version = $v'             .claude-plugin/plugin.json  > tmp && mv tmp .claude-plugin/plugin.json
jq --arg v "$V" '.version = $v'             .codex-plugin/plugin.json   > tmp && mv tmp .codex-plugin/plugin.json
jq --arg v "$V" '.plugins[0].version = $v'  .claude-plugin/marketplace.json > tmp && mv tmp .claude-plugin/marketplace.json

# Verify — must print the new version exactly three times and nothing else
grep -rh '"version"' .claude-plugin/ .codex-plugin/

# Test backup-local-config.sh — run under BOTH interpreters.
# Bash 5 silently hides the empty-array case that bash 3.2 dies on, and the harness
# runs the script under whichever bash runs the harness, so this is not ceremony.
/bin/bash           scripts/test-backup-local-config.sh   # 3.2, stock macOS
/usr/local/bin/bash scripts/test-backup-local-config.sh   # 5.x, Homebrew
```

---

## Gotchas

- **Three manifests carry a version, and one of them hides it.** `.claude-plugin/plugin.json`
  and `.codex-plugin/plugin.json` use a top-level `.version`; `.claude-plugin/marketplace.json`
  keeps it at `.plugins[0].version` and has **no** top-level `.version`. The bump loop
  documented here until 2026-08-11 ran `jq '.version = ...'` over all three, which invented a
  top-level key in marketplace.json and left the real plugin version at the previous number —
  a split release produced by the very command written to prevent one. Verify with
  `grep -rh '"version"' .claude-plugin/ .codex-plugin/`: exactly three lines, all equal.
  The v1.4.1 bump separately missed the Codex manifest mid-work; no tag ever carried the
  three out of sync, so the split was caught before release rather than shipped.
- **A plugin upgrade never affects the running session.** The skill registry is built at
  startup, so a newly added skill returns `Unknown skill` in the current session even when
  all three install locations are correct. Restart, then verify by invoking a skill that only
  exists in the new version — see README "Updating the Plugin" steps 4–5.
- **`skills/` is discovered as a directory** (`"skills": "./skills/"`), so a new skill needs
  no manifest registration — but a new **command** does need its own `commands/<name>.md`,
  and the Codex manifest declares no `commands` key at all, so slash commands are Claude
  Code-only.
- **Not every skill is portable.** `self-hosted-review` requires subagent dispatch,
  `/code-review`, `ReportFindings` and `superpowers` — Claude Code only. The other four are
  gh/rclone/file-editing and work under both agents.
- **The backup config lives outside the plugin, on purpose.** `backup-local-config.sh`
  resolves it in order: `$BACKUP_CONFIG_FILE`, then
  `${CLAUDE_CONFIG_DIR:-~/.claude}/config/backup-config.json`, then the legacy
  plugin-local path. It used to resolve *only* the last one, which sits inside the
  version-pinned cache — so every upgrade cloned a fresh copy without it and backups
  either failed outright or silently ran against a stale copy left at another install
  path. That is how `laptop-maintenance`'s `reports/` entry was lost in April 2026 and
  stayed lost for four months (TT-452). Every run prints `Using config: <path>`; if that
  is not the `~/.claude/config/` one, fix it before trusting the backup.
- **`Failed (0)` is not evidence of a good backup.** The script now ends with an
  `OK`/`PARTIAL`/`FAILED` token and exits 0/2/1. Exit 2 means the transfer worked but a
  configured entry is stale — not a failure, but not a success either. For anything that
  matters, check the bytes: `rclone check <local> <remote> --one-way`.
- **Never reserve a version number in advance.** An issue owns *"the next minor"*, never a
  specific number. Whichever qualifying change ships first takes the number; everything else
  shifts. Reserving collided three times before this rule existed: TT-372 was slated for
  v1.4.0 (TT-392 took it), re-slated to v1.4.1 (the self-hosted-review skill took it), and
  TT-393 carried `v1.5.0` in its own title until TT-473 reclaimed it. Refer to planned work
  by issue ID in titles, bodies and acceptance criteria — never by version.

---

## Versioning policy

Adopted 2026-08-11 (TT-473). Assign the number **at release time, from the change itself**.

| Bump | When |
|------|------|
| **MAJOR** | Removing or renaming a skill, command, or convention — anything a consumer must react to |
| **MINOR** | A new skill, a new command, or **any change to `conventions/development-standards.md`** |
| **PATCH** | A bug fix inside an existing skill or script: no new surface, no convention text change |

The convention-file rule is not a formality. `conventions/development-standards.md` is injected
by the SessionStart hook into **every session of every project**, including repos unrelated to
this plugin. Changing it changes behaviour everywhere without anyone opting in, which is the
opposite of what a patch release promises.

**v1.4.1 was misnumbered.** It shipped a skill (+352), a slash command (+12), and 90 changed
lines of injected conventions (+81/−9) — a minor on each of the three grounds independently. It was re-released as **v1.5.0** under
TT-473, and v1.4.1 is superseded. This is a deliberate exception to SemVer §3 ("released
contents must not be modified"), taken because the plugin has no dependents and no consumer
pins a version range; the release notes record the correction rather than hiding it.

---

## Environment Variables

No environment variables required for the plugin itself. Individual projects bootstrapped by this plugin use `.envrc` with direnv.

---

## References

- **GitHub Repository:** [davidshaevel-marketplace](https://github.com/davidshaevel-dot-com/davidshaevel-marketplace)
- **Linear Project:** [Team Tacocat](https://linear.app/davidshaevel-dot-com)
