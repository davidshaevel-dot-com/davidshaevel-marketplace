# davidshaevel-marketplace

Personal multi-agent development plugin providing development conventions, skills, and project templates. Works with **Claude Code** and **OpenAI Codex CLI**.

## What This Plugin Provides

- **Development conventions** injected automatically at session start via hook
- **Skills** for code review resolution, session handoff (cross-agent memory), and project bootstrapping
- **Templates** for initializing new projects with standard structure

The same conventions, hooks, and skills serve both agents. Claude Code loads them via `.claude-plugin/plugin.json`; Codex loads them via `.codex-plugin/plugin.json` (v1.4.0+).

> **Plugin name:** the plugin identifier is `davidshaevel-claude-toolkit`. It is retained (despite "claude" in the name) for install-command and marketplace-registration stability across both agents. A vendor-neutral rename is a future v2.0.0 consideration.

## Installation

### Claude Code

```bash
# Add as a marketplace
/plugin marketplace add davidshaevel-dot-com/davidshaevel-marketplace

# Install the plugin
/plugin install davidshaevel-marketplace@davidshaevel-claude-toolkit
```

### Codex CLI

Register the marketplace as a git source in `~/.codex/config.toml`:

```toml
[marketplaces.davidshaevel-marketplace]
source_type = "git"
source = "https://github.com/davidshaevel-dot-com/davidshaevel-marketplace.git"
```

Then enable the plugin (`[plugins."davidshaevel-claude-toolkit@davidshaevel-marketplace"] enabled = true`) and restart Codex. The SessionStart hook injects conventions and the four skills become discoverable. Codex also reads `CLAUDE.md`, `CLAUDE.local.md`, and `SESSION_LOG.md` via `project_doc_fallback_filenames`.

## Skills

| Skill | Description |
|-------|-------------|
| `resolve-code-review` | Read PR feedback, fix or decline each item, reply in threads, post summary |
| `session-handoff` | Read/write SESSION_LOG.md for cross-agent memory persistence |
| `backup-local-config` | Back up gitignored local files to Google Drive via rclone |
| `bootstrap-project` | Initialize new projects with CLAUDE.md, .cursorrules, CLAUDE.local.md, SESSION_LOG.md |

## Commands

| Command | Description |
|---------|-------------|
| `/resolve-code-review` | Invoke the resolve-code-review skill |
| `/bootstrap-project` | Invoke the bootstrap-project skill |

## Updating the Plugin

After pushing a new version to the repository, three locations must be updated for Claude Code to load the new version.

### 1. Marketplace directory

The marketplace directory is a git clone that needs to be pulled:

```bash
git -C ~/.claude/plugins/marketplaces/davidshaevel-marketplace pull origin main
```

### 2. Plugin cache

The cache stores versioned clones at `~/.claude/plugins/cache/davidshaevel-marketplace/davidshaevel-claude-toolkit/<version>/`. Create a new directory for the new version:

```bash
# Clone the new version tag into the cache
git clone --branch v<NEW_VERSION> --depth 1 \
  git@github.com:davidshaevel-dot-com/davidshaevel-marketplace.git \
  ~/.claude/plugins/cache/davidshaevel-marketplace/davidshaevel-claude-toolkit/<NEW_VERSION>

# Optionally recreate the old version directory from its tag (keeps it clean)
rm -rf ~/.claude/plugins/cache/davidshaevel-marketplace/davidshaevel-claude-toolkit/<OLD_VERSION>
git clone --branch v<OLD_VERSION> --depth 1 \
  git@github.com:davidshaevel-dot-com/davidshaevel-marketplace.git \
  ~/.claude/plugins/cache/davidshaevel-marketplace/davidshaevel-claude-toolkit/<OLD_VERSION>
```

### 3. Installed plugins registry

Update `~/.claude/plugins/installed_plugins.json` to point to the new version:

- `installPath` → update the version in the path
- `version` → new version string
- `gitCommitSha` → commit SHA of the new version
- `lastUpdated` → current ISO timestamp

### 4. Restart Claude Code

Permission changes and plugin updates require a session restart to take effect.

## Backup Local Config

Back up gitignored files (SESSION_LOG.md, CLAUDE.local.md, .envrc, .env, etc.) to Google Drive. Runs automatically at session end via session-handoff, or on-demand.

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

Copy the example config and edit it:

```bash
cp config/backup-config.json.example config/backup-config.json
```

Then edit `config/backup-config.json` (this file is gitignored since it contains repo-specific names):

```json
{
  "backupDir": "gdrive:session-backups",
  "globalFiles": [
    "SESSION_LOG.md",
    "CLAUDE.local.md"
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
/davidshaevel-claude-toolkit:backup-local-config
```

**Automatic:** Runs at every session end via session-handoff.

**Dry run (preview without uploading):**
```bash
~/.claude/plugins/marketplaces/davidshaevel-marketplace/scripts/backup-local-config.sh --dry-run /path/to/repo
```

**Manual CLI (outside Claude Code):**
```bash
~/.claude/plugins/marketplaces/davidshaevel-marketplace/scripts/backup-local-config.sh /path/to/repo
```

### Google Drive Folder Structure

Files are organized by repo and worktree:

```
session-backups/
├── my-web-app/
│   ├── main/
│   │   ├── SESSION_LOG.md
│   │   └── CLAUDE.local.md
│   ├── feature-auth/
│   │   └── ...
│   └── feature-payments/
│       └── ...
├── my-infra-platform/
│   ├── main/
│   │   ├── SESSION_LOG.md
│   │   ├── CLAUDE.local.md
│   │   ├── .envrc
│   │   └── .env
│   └── ...
└── my-cli-tool/
    ├── SESSION_LOG.md
    └── CLAUDE.local.md
```

- **Bare+worktree repos:** `<repo-name>/<worktree-name>/<file>`
- **Standard repos:** `<repo-name>/<file>`

## Convention Change Propagation

- **Claude Code:** Follow the update steps above, then restart the session
- **Codex:** Pull the marketplace git source (`~/.codex/plugins/cache/...`) or re-sync the marketplace, then restart Codex
- **Cursor:** Re-run `/bootstrap-project` to regenerate `.cursorrules`

## License

MIT
