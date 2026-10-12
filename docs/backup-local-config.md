# Backup Local Config — the detail behind the README's [Backup Local Config](../README.md#backup-local-config) summary

### Prerequisites

1. **Install rclone:**
   ```bash
   brew install rclone
   ```

2. **Install jq:**
   ```bash
   brew install jq
   ```

3. **Configure a Google Drive remote in rclone:**
   ```bash
   rclone config
   ```
   When prompted:
   - Choose `n` for new remote
   - Name it `gdrive` (or whatever name you use in `backupDir`)
   - Choose `Google Drive` as the storage type
   - Follow the OAuth flow to authorize access
   - Confirm the configuration

   Verify with: `rclone listremotes` (should show `gdrive:`)

### Configuration

The config lives in **`~/.claude/config/backup-config.json`** — outside the plugin, on
purpose. It used to live at `config/backup-config.json` inside the plugin, which sits in
the version-pinned cache, so every upgrade destroyed it (TT-452).

```bash
mkdir -p ~/.claude/config
cp config/backup-config.json.example ~/.claude/config/backup-config.json
chmod 600 ~/.claude/config/backup-config.json
```

Resolution order, first hit wins: `$BACKUP_CONFIG_FILE`, then
`${CLAUDE_CONFIG_DIR:-~/.claude}/config/backup-config.json`, then the old plugin-local
path (which still works but warns and reports `PARTIAL`). Every run prints
`Using config: <path>` as its first line.

**Migrating from the old location:** move it, don't copy — leaving a second config behind
means one of them is silently stale.

```bash
mv config/backup-config.json ~/.claude/config/backup-config.json
```

Then edit `~/.claude/config/backup-config.json` (gitignored wherever it lives, since it
contains repo-specific names):

```json
{
  "backupDir": "gdrive:session-backups",
  "globalFiles": [
    "SESSION_LOG.md",
    "CLAUDE.local.md",
    "AGENTS.local.md"
  ],
  "repoOverrides": {
    "my-project": {
      "additionalFiles": [
        ".envrc",
        ".env"
      ]
    }
  }
}
```

| Field | Description |
|-------|-------------|
| `backupDir` | rclone remote and path (e.g., `gdrive:session-backups`) |
| `globalFiles` | Files to back up in every repo |
| `repoOverrides.<repo>.additionalFiles` | Extra files for a specific repo (merged with `globalFiles`) |

**To add a new file to back up everywhere:** Add it to `globalFiles`.

**To add a file for one repo only:** Add it to that repo's `additionalFiles` in `repoOverrides`. The repo key is the directory name (e.g., `my-infra-platform`).

### Usage

**On-demand (from Claude Code):**
```
/davidshaevel-agent-toolkit:backup-local-config
```

**Automatic:** Runs at every session end via session-handoff.

**Dry run (preview without uploading):**
```bash
~/.claude/plugins/cache/davidshaevel-marketplace/davidshaevel-agent-toolkit/<VERSION>/scripts/backup-local-config.sh --dry-run /path/to/repo
```

**Manual CLI (outside Claude Code):**
```bash
~/.claude/plugins/cache/davidshaevel-marketplace/davidshaevel-agent-toolkit/<VERSION>/scripts/backup-local-config.sh /path/to/repo
```

`<VERSION>` must match the installed version in `~/.claude/plugins/installed_plugins.json`.
Use the `cache/` path, not `marketplaces/` — the marketplace clone tracks `main` and can be
ahead of the version the skills actually run, so it is a different program.

**Exit codes:** `0` = `OK`, `2` = `PARTIAL` (backup succeeded, a config entry is stale —
read the `WARNING:` lines), `1` = `FAILED` (a copy failed). A clean `Failed (0)` on its own
is not evidence of a good backup; verify the bytes with
`rclone check <local> <remote> --one-way`.

### Google Drive Folder Structure

Files are organized by repo and worktree:

```
session-backups/
├── my-web-app/
│   ├── main/
│   │   ├── SESSION_LOG.md
│   │   └── AGENTS.local.md
│   ├── feature-auth/
│   │   └── ...
│   └── feature-payments/
│       └── ...
├── my-infra-platform/
│   ├── main/
│   │   ├── SESSION_LOG.md
│   │   ├── AGENTS.local.md
│   │   ├── .envrc
│   │   └── .env
│   └── ...
└── my-cli-tool/
    ├── SESSION_LOG.md
    └── AGENTS.local.md
```

- **Bare+worktree repos:** `<repo-name>/<worktree-name>/<file>`
- **Standard repos:** `<repo-name>/<file>`

## After an upgrade

Why this mattered: the config used to live inside the versioned cache directory, so every
upgrade cloned a fresh copy without it. Backups then failed outright, or — worse — kept
running against a stale copy left behind at another install path. The `laptop-maintenance`
`reports/` entry was lost that way in April 2026 and stayed lost for four months.

> **Directory entries are supported as of TT-372**, and every destination now carries the
> entry's relative path — `jobs/co-a/.work` and `jobs/co-b/.work` land at distinct
> destinations instead of colliding on their basename. This is backwards-incompatible for
> existing backups: anything previously backed up from a nested path sits at an old
> basename destination that no future run will update. Clean those up on Drive only after
> **every machine** that backs up to the remote is on the new version — a machine still on
> the old plugin recreates the basename destinations after cleanup and its stale writes
> then look current. To find orphans, list the repo's folder (`rclone lsd <backupDir>/<repo>`)
> and compare against the relative paths in the config; anything sitting at a bare
> basename with a nested twin alongside it is an orphan.
