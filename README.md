# davidshaevel-marketplace

Personal multi-agent development plugin providing development conventions, skills, and project templates. Works with **Claude Code** and **OpenAI Codex CLI**.

## What This Plugin Provides

- **Development conventions** injected automatically at session start via hook
- **Skills** for code review — both resolving bot feedback and producing a review when no bot responds — plus session handoff (cross-agent memory), local-config backup, and project bootstrapping
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

**v1.4.0 status: foundational support only.** This release ships the Codex-side infrastructure — `.codex-plugin/plugin.json` manifest, `hooks/hooks-codex.json` (uses Codex-canonical `$PLUGIN_ROOT`), shared `conventions/development-standards.md`, and shared `skills/`. **Remote git-source marketplace install is not yet working** because two architectural changes are required:

1. **Plugin layout.** Codex's local source resolver rejects entries that resolve to the marketplace root; the plugin needs to live in a `./plugins/<plugin-name>/` subdirectory per the Codex `plugin-json-spec`. Our current repo uses a root layout (which Claude Code supports natively).
2. **Skill path resolution.** Several skills (`backup-local-config`, `session-handoff` backup step) invoke scripts via `${CLAUDE_PLUGIN_ROOT}/scripts/...`. In a Codex session that variable is not populated; the commands fail. Need to make skill path resolution agent-agnostic (or detect `$PLUGIN_ROOT` first).

Both blockers are tracked in **[TT-393 — Codex remote git-source marketplace install support](https://linear.app/davidshaevel-dot-com/issue/TT-393)**.

**For now (v1.4.0):** if you want to experiment with the plugin in Codex, clone the repo locally and register a personal-marketplace entry pointing at the local path (Codex's `~/.agents/plugins/marketplace.json`). When the SessionStart hook fires for the first time, Codex will surface a trust prompt — accept it to enable `conventions/development-standards.md` injection. Skills that don't depend on `${CLAUDE_PLUGIN_ROOT}` (`resolve-code-review`, `bootstrap-project`) work; skills that do (`backup-local-config`, `session-handoff` backup step) won't until TT-393 lands.

**For full multi-agent install parity:** track [TT-393](https://linear.app/davidshaevel-dot-com/issue/TT-393), which will restore the remote git-source install path (`[marketplaces.davidshaevel-marketplace] source_type = "git"` in `~/.codex/config.toml`) once the architectural work lands.

## Skills

| Skill | Description |
|-------|-------------|
| `resolve-code-review` | Read PR feedback from `gemini-code-assist`, fix or decline each item, reply in threads, post summary |
| `self-hosted-review` | Produce a review with subagents when **no bot reviewer responded** — three cycles (architectural, line-level, verification) |
| `session-handoff` | Read/write SESSION_LOG.md for cross-agent memory persistence |
| `backup-local-config` | Back up gitignored local files to Google Drive via rclone |
| `bootstrap-project` | Initialize new projects with CLAUDE.md, .cursorrules, CLAUDE.local.md, SESSION_LOG.md |

### Which review skill?

| PR state | Skill |
|---|---|
| `gemini-code-assist[bot]` reviewed | `resolve-code-review` — it filters for that bot specifically |
| Another bot reviewed (Codex, Qodo, …) | `self-hosted-review` — `resolve-code-review` would match nothing |
| **No bot reviewed** | `self-hosted-review` |

Gemini Code Assist sunset **2026-07-17**, so on `davidshaevel-dot-com` the last two rows
are the common case. `self-hosted-review` is written to trigger automatically when a PR
has zero bot reviews, though invocation is model-mediated — invoke it explicitly if it
doesn't fire. Merging on "no bot responded" is not review.

<!-- Routing table above is temporary — remove when TT-367 ships multi-bot support.
     Canonical source: skills/self-hosted-review/SKILL.md "When this applies". -->

Consolidating both into one multi-bot resolver is tracked as TT-367.

## Commands

| Command | Description |
|---------|-------------|
| `/resolve-code-review` | Invoke the resolve-code-review skill |
| `/self-hosted-review` | Invoke the self-hosted-review skill (optionally `/self-hosted-review <PR>`) |
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

**This is not optional and there is no workaround.** A session builds its skill registry at
startup. Updating all three locations above while a session is running leaves that session on
the old skill set — invoking a newly added skill returns `Unknown skill` even though every
file on disk is correct. Verified on 2026-08-11 upgrading 1.4.0 → 1.5.0.

### 5. Confirm the backup config resolves

**This step used to be "re-create the symlink by hand", and it no longer is** (TT-452).
`backup-local-config.sh` now looks for its config outside the version-pinned cache, so an
upgrade cannot take it away. Confirm that is what actually happens:

```bash
~/.claude/plugins/cache/davidshaevel-marketplace/davidshaevel-claude-toolkit/<NEW_VERSION>/scripts/backup-local-config.sh \
  --dry-run ~/workspace-ds/laptop-maintenance
```

The **first line** must read:

```
Using config: /Users/<you>/.claude/config/backup-config.json
```

If it names a path under `plugins/cache/` or `plugins/marketplaces/` instead, the config is
somewhere the next upgrade will destroy — move it to `~/.claude/config/` and re-run. A
`WARNING:` block will tell you the same thing.

Why this mattered: the config used to live inside the versioned cache directory, so every
upgrade cloned a fresh copy without it. Backups then failed outright, or — worse — kept
running against a stale copy left behind at another install path. The `laptop-maintenance`
`reports/` entry was lost that way in April 2026 and stayed lost for four months.

**Then delete every other copy.** A config that loses is invisible; the script now names
one when it finds it, and that warning is the cue to clean up:

```bash
rm -f ~/.claude/plugins/marketplaces/davidshaevel-marketplace/config/backup-config.json
rm -f ~/.claude/plugins/cache/davidshaevel-marketplace/davidshaevel-claude-toolkit/*/config/backup-config.json
```

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

### 6. Verify the new version actually loaded

Updating the files is not evidence the session picked them up. In the **new** session:

```bash
# all three locations should agree
grep -h '"version"' ~/.claude/plugins/marketplaces/davidshaevel-marketplace/.claude-plugin/plugin.json
ls ~/.claude/plugins/cache/davidshaevel-marketplace/davidshaevel-claude-toolkit/
```

Then invoke a skill that only exists in the new version. If it returns `Unknown skill`, the
session is still on the old registry — restart again rather than assuming it worked.

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
~/.claude/plugins/cache/davidshaevel-marketplace/davidshaevel-claude-toolkit/<VERSION>/scripts/backup-local-config.sh --dry-run /path/to/repo
```

**Manual CLI (outside Claude Code):**
```bash
~/.claude/plugins/cache/davidshaevel-marketplace/davidshaevel-claude-toolkit/<VERSION>/scripts/backup-local-config.sh /path/to/repo
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
