# Design: backup-local-config Skill

**Date:** 2026-03-31
**Issue:** TT-270
**Status:** Draft

## Problem

SESSION_LOG.md, CLAUDE.local.md, .envrc, .env, and other gitignored files contain valuable session context and sensitive configuration that is not version-controlled. They are at risk of loss from:

- Accidental deletion (e.g., `git worktree remove` before merging, `rm -rf`)
- Machine loss or failure (disk corruption, hardware death)
- Need for cross-machine access (working from a different machine)

No backup mechanism currently exists for these files.

## Solution

A new `backup-local-config` skill in the davidshaevel-claude-toolkit plugin that backs up configured gitignored files to Google Drive via `rclone`.

## Architecture

### Components

1. **`config/backup-config.json`** — User-editable configuration file
2. **`scripts/backup-local-config.sh`** — Shell script that performs the backup
3. **`skills/backup-local-config/skill.md`** — Skill definition for on-demand invocation
4. **`skills/session-handoff/skill.md`** — Updated to invoke backup at session end

### Google Drive Folder Structure

```
session-backups/
├── job-searches-2026-q1/
│   ├── main/
│   │   ├── SESSION_LOG.md
│   │   └── CLAUDE.local.md
│   ├── tt-269-centre-technologies/
│   │   ├── SESSION_LOG.md
│   │   └── CLAUDE.local.md
│   └── fastest-to-start-income/
│       └── ...
├── davidshaevel-k8s-platform/
│   ├── main/
│   │   ├── SESSION_LOG.md
│   │   ├── CLAUDE.local.md
│   │   ├── .envrc
│   │   └── .env
│   └── ...
└── dochound/
    └── ...
```

- Bare+worktree repos: `<repo-name>/<worktree-name>/<file>`
- Standard repos: `<repo-name>/<file>`

## Configuration

### File: `config/backup-config.json`

```json
{
  "backupDir": "gdrive:session-backups",
  "globalFiles": [
    "SESSION_LOG.md",
    "CLAUDE.local.md"
  ],
  "repoOverrides": {
    "davidshaevel-k8s-platform": {
      "additionalFiles": [".envrc", ".env"]
    }
  }
}
```

| Field | Description |
|-------|-------------|
| `backupDir` | rclone remote destination (remote-name:path format) |
| `globalFiles` | Files to back up in every repo |
| `repoOverrides` | Per-repo additional files, keyed by repo directory name |
| `repoOverrides.<repo>.additionalFiles` | Extra files to back up for this repo, merged with `globalFiles` |

### Adding new files to back up

- **All repos:** Add the filename to `globalFiles`
- **Specific repo:** Add the filename to that repo's `additionalFiles` in `repoOverrides`

## Shell Script Behavior

### File: `scripts/backup-local-config.sh`

**Invocation:**

```bash
# From current repo (uses cwd)
backup-local-config.sh

# From a specific path
backup-local-config.sh /path/to/repo

# Dry run (preview without uploading)
backup-local-config.sh --dry-run

# Dry run with specific path
backup-local-config.sh --dry-run /path/to/repo
```

Arguments are parsed positionally: `--dry-run` is an optional flag, and the remaining non-flag argument is treated as the repo path (defaults to cwd if omitted).

**Logic:**

1. **Resolve config path** — Reads `backup-config.json` relative to the script's own location (`$SCRIPT_DIR/../config/backup-config.json`)
2. **Determine repo context** — Detects repo name from the working directory (basename of the repo root)
3. **Detect worktree structure** — Checks for `.bare/` directory:
   - If bare+worktree: runs `git worktree list` and backs up files from each worktree
   - If standard repo: backs up files from the repo root
4. **Build file list** — Merges `globalFiles` with any `repoOverrides.additionalFiles` for this repo
5. **Copy files** — For each file that exists, runs `rclone copy` to `<backupDir>/<repo-name>/<worktree-name>/<file>` (worktree) or `<backupDir>/<repo-name>/<file>` (standard)
6. **Output summary** — Prints which files were backed up and which were skipped (not found)

**Error handling:**

- `rclone` not installed: prints error with `brew install rclone` instructions, exits 1
- `jq` not installed: prints error with `brew install jq` instructions, exits 1
- `backup-config.json` missing or malformed: exits with clear message
- rclone remote not configured: prints `rclone config` instructions, exits 1
- Individual file upload failures: logged but do not stop the rest of the backup

**Dependencies:**

- `rclone` (for Google Drive upload)
- `jq` (for JSON config parsing)

## Skill Definition

### File: `skills/backup-local-config/skill.md`

The skill instructs Claude to:

1. Determine the target repo from the current working directory (or ask if ambiguous)
2. Execute `backup-local-config.sh` with the appropriate path
3. Report results — summarize what was backed up, flag any errors

Invocable as: `/davidshaevel-claude-toolkit:backup-local-config`

## Session-Handoff Integration

### File: `skills/session-handoff/skill.md` (updated)

At the end of the "At Session End" process, after writing SESSION_LOG.md:

1. *(existing)* Write/update SESSION_LOG.md in the appropriate worktree
2. **(new)** Invoke `backup-local-config.sh` for the current repo

The backup uses the same shell script as the standalone skill — no code duplication.

## Documentation

### README.md updates

**Prerequisites:**
- Install `rclone` (`brew install rclone`)
- Install `jq` (`brew install jq`)
- One-time `rclone config` setup for Google Drive (step-by-step for creating the `gdrive` remote)

**Configuration:**
- Location and format of `backup-config.json`
- How to set `backupDir` (rclone remote syntax)
- How to add files to `globalFiles`
- How to add per-repo overrides with `additionalFiles`
- Example config with common patterns

**Usage:**
- On-demand: `/davidshaevel-claude-toolkit:backup-local-config`
- Automatic: triggered at session end via session-handoff
- Dry run: preview what would be backed up
- Manual CLI: run the script directly outside Claude Code

**Google Drive folder structure:**
- Explains the `<repo-name>/<worktree-name>/<file>` layout
- What to expect in Drive after backups run

## Plugin File Changes Summary

| File | Action | Description |
|------|--------|-------------|
| `config/backup-config.json` | New | Backup configuration |
| `scripts/backup-local-config.sh` | New | Shell script for backup logic |
| `skills/backup-local-config/skill.md` | New | On-demand skill definition |
| `skills/session-handoff/skill.md` | Update | Add backup step at session end |
| `README.md` | Update | Add prerequisites, configuration, and usage docs |
