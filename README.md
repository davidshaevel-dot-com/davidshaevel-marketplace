# davidshaevel-marketplace

A plugin marketplace holding one plugin, `davidshaevel-agent-toolkit`. The plugin injects a
set of development conventions (git workflow, commit and PR format, worktree layout, issue
tracking) into every agent session through a session-start hook, and ships skills for code
review, cross-agent session handoff, local-config backup and project bootstrapping, plus
templates for new repositories.

It is fully supported in **Claude Code**. In **OpenAI Codex CLI**, the conventions hook and
the skills that do not call plugin scripts work; [Codex CLI](#codex-cli) lists exactly which.

> **Name history:** v1.x shipped as `davidshaevel-claude-toolkit`; v2.0.0 renamed the plugin to `davidshaevel-agent-toolkit`. The repository and marketplace keep the name `davidshaevel-marketplace`.

## Installation

### Claude Code

In a session:

```
/plugin marketplace add davidshaevel-dot-com/davidshaevel-marketplace
/plugin install davidshaevel-agent-toolkit@davidshaevel-marketplace
```

Or from a shell:

```bash
claude plugin marketplace add davidshaevel-dot-com/davidshaevel-marketplace
claude plugin install davidshaevel-agent-toolkit@davidshaevel-marketplace
```

To verify, `claude plugin list` shows `davidshaevel-agent-toolkit@davidshaevel-marketplace`
as enabled, and a fresh session's injected conventions begin "Your development conventions
are provided by the davidshaevel-agent-toolkit plugin."

### Codex CLI

1. Register the marketplace, either from a shell:

   ```bash
   codex plugin marketplace add davidshaevel-dot-com/davidshaevel-marketplace
   ```

   or by adding this table to `~/.codex/config.toml`:

   ```toml
   [marketplaces.davidshaevel-marketplace]
   source_type = "git"
   source = "https://github.com/davidshaevel-dot-com/davidshaevel-marketplace.git"
   ```

2. Install the plugin:

   ```bash
   codex plugin add davidshaevel-agent-toolkit@davidshaevel-marketplace
   ```

3. Restart Codex. The first time the session-start hook fires, Codex asks you to trust it;
   accept once. `codex plugin list` then shows the plugin as `installed, enabled`.

What works under Codex:

- **Works:** conventions injection at session start; `resolve-code-review`;
  `bootstrap-project`; `session-handoff` reading and writing SESSION_LOG.md.
- **Does not work:** `backup-local-config` and the backup step of `session-handoff`. Their
  SKILL.md files call `${CLAUDE_PLUGIN_ROOT}/scripts/backup-local-config.sh`, and that
  variable is empty under Codex, so the command fails.
- **Claude Code only:** `self-hosted-review`, which needs subagent dispatch, and the slash
  commands (the Codex manifest declares none).

Making the backup scripts resolve under Codex is a known gap.

## Skills

| Skill | Description |
|-------|-------------|
| `resolve-code-review` | Read PR feedback from `gemini-code-assist`, fix or decline each item, reply in threads, post summary |
| `self-hosted-review` | **Claude Code only.** Produce a review with subagents when **no bot reviewer responded** — three cycles (architectural, line-level, verification) |
| `session-handoff` | Read/write SESSION_LOG.md for cross-agent memory persistence |
| `backup-local-config` | Back up gitignored local files to Google Drive via rclone |
| `bootstrap-project` | Initialize new projects with AGENTS.md, CLAUDE.md (import), .cursorrules, AGENTS.local.md, SESSION_LOG.md |

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

Consolidating both into one multi-bot resolver is planned.

## Commands

Slash commands are Claude Code only.

| Command | Description |
|---------|-------------|
| `/resolve-code-review` | Invoke the resolve-code-review skill |
| `/self-hosted-review` | Invoke the self-hosted-review skill (optionally `/self-hosted-review <PR>`) |
| `/bootstrap-project` | Invoke the bootstrap-project skill |

## Updating the Plugin

### Claude Code

1. **Refresh the marketplace, then update the plugin:**

   ```bash
   claude plugin marketplace update davidshaevel-marketplace
   claude plugin update davidshaevel-agent-toolkit@davidshaevel-marketplace
   ```

   `update` moves an installed plugin to the latest version. `install` is for a first
   install, or for a new plugin id after a rename (with `uninstall` of the old id).

2. **Restart Claude Code.** This is not optional and there is no workaround. A session
   builds its skill registry at startup, so a running session keeps the old skill set: a
   newly added skill returns `Unknown skill` even though every file on disk is correct.

3. **If you use `backup-local-config`, confirm its config still resolves:**

   ```bash
   ~/.claude/plugins/cache/davidshaevel-marketplace/davidshaevel-agent-toolkit/<NEW_VERSION>/scripts/backup-local-config.sh \
     --dry-run /path/to/repo
   ```

   The first line must read `Using config: /Users/<you>/.claude/config/backup-config.json`.
   If it names a path under `plugins/cache/` or `plugins/marketplaces/`, the config sits
   where the next upgrade will destroy it: move it to `~/.claude/config/`, re-run, then
   delete every other copy:

   ```bash
   rm -f ~/.claude/plugins/marketplaces/davidshaevel-marketplace/config/backup-config.json
   rm -f ~/.claude/plugins/cache/davidshaevel-marketplace/davidshaevel-agent-toolkit/*/config/backup-config.json
   ```

   [After an upgrade](docs/backup-local-config.md#after-an-upgrade) explains why, and how
   to clean up backups written by older versions.

4. **Verify the new version loaded.** In the new session, `claude plugin list` shows the
   new version. Then invoke a skill that only exists in that version; `Unknown skill` means
   the session is still on the old registry, so restart again rather than assuming it
   worked.

### Codex CLI

```bash
codex plugin marketplace upgrade davidshaevel-marketplace
codex plugin add davidshaevel-agent-toolkit@davidshaevel-marketplace
```

Then restart Codex; `codex plugin list` shows the new version.

## Backup Local Config

`backup-local-config` backs up gitignored files (SESSION_LOG.md, AGENTS.local.md, .envrc,
.env and the like) to Google Drive with rclone, automatically at session end through
`session-handoff` or on demand. Its config lives in `~/.claude/config/backup-config.json`,
outside the plugin, so an upgrade cannot remove it. Exit codes: `0` = `OK`, `2` = `PARTIAL`
(the backup ran, but a config entry needs attention; read the `WARNING:` lines), `1` =
`FAILED`. Prerequisites, configuration, usage and the Drive folder layout are in
[docs/backup-local-config.md](docs/backup-local-config.md).

## Convention Change Propagation

- **Claude Code:** Follow the update steps above, then restart the session
- **Codex:** `codex plugin marketplace upgrade davidshaevel-marketplace`, then `codex plugin add davidshaevel-agent-toolkit@davidshaevel-marketplace`, then restart Codex
- **Cursor:** Re-run `/bootstrap-project` to regenerate `.cursorrules`

## License

MIT
