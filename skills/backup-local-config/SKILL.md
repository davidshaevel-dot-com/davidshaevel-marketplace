---
name: backup-local-config
description: Back up gitignored local files (SESSION_LOG.md, CLAUDE.local.md, .envrc, etc.) to Google Drive via rclone
---

# Backup Local Config

Back up configured gitignored files from the current repository to Google Drive via rclone. Supports bare+worktree and standard repos.

## Usage

```
/davidshaevel-claude-toolkit:backup-local-config
```

## Prerequisites

- `rclone` installed (`brew install rclone`)
- `jq` installed (`brew install jq`)
- Google Drive remote configured in rclone (`rclone config`)
- `config/backup-config.json` configured in the plugin directory

## Process

### 1. Determine Target Repo

Use the current working directory to determine the repo to back up.

- If the cwd is inside a worktree, resolve to the repo root (parent of `.bare/` for bare+worktree repos, or the directory containing `.git/` for standard repos)
- If the cwd is ambiguous (e.g., not inside a git repo), ask the user which repo to back up

### 2. Execute Backup

Run the backup script:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/backup-local-config.sh" /path/to/repo
```

Replace `/path/to/repo` with the resolved repo root path from step 1.

For a dry run (preview without uploading):

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/backup-local-config.sh" --dry-run /path/to/repo
```

### 3. Report Results

Summarize the script output to the user:
- How many files were backed up
- How many were skipped (not found in the repo/worktree)
- Any failures and their causes

If there are failures, suggest troubleshooting steps:
- Check that rclone remote is configured: `rclone listremotes`
- Check that the backup directory exists: `rclone ls gdrive:session-backups`
- Verify file paths in `config/backup-config.json`
