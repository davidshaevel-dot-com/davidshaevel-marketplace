# davidshaevel-claude-toolkit

Personal Claude Code plugin providing development conventions, skills, and project templates.

## What This Plugin Provides

- **Development conventions** injected automatically at session start via hook
- **Skills** for code review resolution, session handoff (cross-agent memory), and project bootstrapping
- **Templates** for initializing new projects with standard structure

## Installation

```bash
# Add as a marketplace
/plugin marketplace add davidshaevel-dot-com/davidshaevel-claude-toolkit

# Install the plugin
/plugin install davidshaevel-claude-toolkit@davidshaevel-claude-toolkit
```

## Skills

| Skill | Description |
|-------|-------------|
| `resolve-code-review` | Read PR feedback, fix or decline each item, reply in threads, post summary |
| `session-handoff` | Read/write SESSION_LOG.md for cross-agent memory persistence |
| `bootstrap-project` | Initialize new projects with CLAUDE.md, .cursorrules, CLAUDE.local.md, SESSION_LOG.md |

## Commands

| Command | Description |
|---------|-------------|
| `/resolve-code-review` | Invoke the resolve-code-review skill |
| `/bootstrap-project` | Invoke the bootstrap-project skill |

## Convention Change Propagation

- **Claude Code:** `plugin update` → next session gets new conventions automatically
- **Cursor:** Re-run `/bootstrap-project` to regenerate `.cursorrules`

## License

MIT
