# Claude Code Cloud Environment — Setup & Gaps

**Purpose:** Steps to get plugins, skills, and slash commands working from a **new Claude Code cloud session** (the Code tab in the desktop app, or claude.ai/code in a browser), plus gaps and improvement opportunities identified during setup.

**Tested:** Thursday, April 23, 2026 against `davidshaevel-dot-com/job-searches-2026-q2`.

**Companion doc:** [`cloud_backup_setup.md`](cloud_backup_setup.md) covers the one-time provisioning of the service-account + shared drive + `RCLONE_CONF_B64` env var. This doc assumes that work is already done and focuses on what happens inside the cloud session.

---

## TL;DR

**What works in cloud:** gstack, superpowers, davidshaevel-claude-toolkit, rclone (gdrive: shared drive via service account), GitHub MCP, session-start hooks.

**What does not work in cloud:** Linear MCP (blocked at network egress and not loaded from `.mcp.json`), any non-allowlisted third-party SaaS domain, headed browser handoff (no display).

**Only path for Linear:** local Claude Code CLI or desktop app local mode.

---

## 1. Prerequisites

- A GitHub repository with:
  - `.claude/settings.json` declaring `enabledMcpjsonServers`, `enabledPlugins`, `extraKnownMarketplaces`, and a `SessionStart` hook
  - `.mcp.json` declaring MCP servers (note: SSE servers listed here won't load in cloud — see "Gaps" below)
  - A session-start hook script (e.g. `.claude/hooks/session-start.sh`) that materializes secrets like `rclone.conf` from env vars (e.g. `RCLONE_CONF_B64`)
- Marketplace repos reachable from the cloud allowlist (GitHub is allowed).

Example `.claude/settings.json` shape:

```json
{
  "enabledMcpjsonServers": ["linear"],
  "extraKnownMarketplaces": {
    "davidshaevel-marketplace": {
      "source": { "source": "github", "repo": "davidshaevel-dot-com/davidshaevel-marketplace" }
    },
    "superpowers-dev": {
      "source": { "source": "github", "repo": "obra/superpowers" }
    }
  },
  "enabledPlugins": {
    "davidshaevel-claude-toolkit@davidshaevel-marketplace": true,
    "superpowers@superpowers-dev": true
  },
  "hooks": {
    "SessionStart": [{
      "hooks": [{ "type": "command", "command": "./.claude/hooks/session-start.sh" }]
    }]
  }
}
```

---

## 2. What Happens Automatically on Session Start

1. Cloud container spawns, repo cloned as a **standard (non-bare) checkout** on the designated branch (e.g. `claude/begin-session-<id>`).
2. Claude Code reads `.claude/settings.json`, installs plugins from the declared marketplaces into `~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/`.
3. SessionStart hook runs:
   - Materializes `rclone.conf` from `RCLONE_CONF_B64` environment variable
   - Prints the repo summary banner
4. Plugins inject their conventions (davidshaevel-claude-toolkit injects development standards as `<IMPORTANT>` context; gstack skills become available under `/gstack-*` prefixes).

**Verify installation:**

```bash
cat ~/.claude/plugins/installed_plugins.json
ls ~/.claude/plugins/marketplaces/
```

---

## 3. Step-by-Step Setup (First Session)

### 3.1 Confirm GitHub MCP is live

```bash
# From within Claude, check deferred tools registry for mcp__github__*
# Should see: mcp__github__add_issue_comment, mcp__github__issue_read, etc.
```

### 3.2 First gstack skill invocation — one-time prompts

Running any `/gstack-*` skill triggers the gstack preamble which asks (once per user/project):

- **Lake intro** — "Boil the Lake" completeness principle
- **Telemetry** — community / anonymous / off
- **Proactive mode** — auto-invoke skills on matching requests
- **CLAUDE.md routing rules** — appends ~40 lines of skill-routing directives and commits them

Defaults chosen in this test: telemetry=anonymous, proactive=true, routing added.

### 3.3 gstack browse — Chromium sandbox workaround

**Symptom:** first `gstack browse` command fails with `Chromium sandboxing failed! Running as root without --no-sandbox is not supported.`

**Cause:** gstack's `browser-manager.ts` only passes `--no-sandbox` if `process.env.CI` or `process.env.CONTAINER` is set. Cloud sessions set neither.

**Fix:** set `CONTAINER=1` in the shell before invoking browse. `$B` is the resolved path to the gstack browse binary — either the repo-local copy under `.claude/skills/gstack/browse/dist/browse` or the fallback at `~/.claude/skills/gstack/browse/dist/browse`:

```bash
export CONTAINER=1
B="$(git rev-parse --show-toplevel)/.claude/skills/gstack/browse/dist/browse"
[ -f "$B" ] || B="$HOME/.claude/skills/gstack/browse/dist/browse"
"$B" goto https://github.com
```

For persistence within the session, consider exporting both in `.envrc`.

### 3.4 backup-local-config — seed config file

The `backup-local-config.sh` script requires `config/backup-config.json`, which ships only as `.example`:

```bash
CONFIG_DIR="$HOME/.claude/plugins/marketplaces/davidshaevel-marketplace/config"
[ -f "$CONFIG_DIR/backup-config.json" ] || cp "$CONFIG_DIR/backup-config.json.example" "$CONFIG_DIR/backup-config.json"
```

Then dry-run verify:

```bash
export CLAUDE_PLUGIN_ROOT="$HOME/.claude/plugins/marketplaces/davidshaevel-marketplace"
DRY_RUN=1 "$CLAUDE_PLUGIN_ROOT/scripts/backup-local-config.sh" "$PWD"
```

### 3.5 Restore SESSION_LOG.md from Google Drive (manual)

Cloud containers are ephemeral, so `SESSION_LOG.md` (gitignored) does not persist across sessions. It must be pulled from gdrive manually:

```bash
# Path in gdrive follows: gdrive:<repo-name>/<worktree-name>/SESSION_LOG.md
# (no "session-backups/" prefix in cloud — see Gap #1)
REPO_ROOT=$(git rev-parse --show-toplevel)
REPO_NAME=$(basename "$REPO_ROOT")
# Cloud sessions are a flat clone (not bare+worktree), so `git worktree list`
# returns the repo root and would give WORKTREE=REPO_NAME. Hardcode "main"
# to match where the local desktop session pushes its SESSION_LOG.md backup.
WORKTREE="main"
rclone copy "gdrive:${REPO_NAME}/${WORKTREE}/SESSION_LOG.md" "$REPO_ROOT/" || echo "No existing backup found."
```

Then Claude/you read it and pick up context.

---

## 4. Plugins & Skills Confirmed Working in Cloud

| Plugin | Version | Notes |
|---|---|---|
| `gstack` (base install at `~/.claude/skills/gstack`) | — | Browse binary works with `CONTAINER=1` |
| `superpowers@superpowers-dev` | 5.0.7 | Skills like `brainstorming`, `test-driven-development`, `systematic-debugging` available |
| `davidshaevel-claude-toolkit@davidshaevel-marketplace` | 1.3.1 | `backup-local-config`, `bootstrap-project`, `resolve-code-review`, `session-handoff` |

---

## 5. Gaps & Improvement Opportunities

### Gap 1 — `session-backups` path redundancy in cloud (local vs cloud env divergence)

**Observation:** `backup-config.json.example` sets `"backupDir": "gdrive:session-backups"`. This works cleanly on **local** (personal Google account), but produces a redundant nested path in **cloud** (service-account + shared drive).

| Environment | Auth | `gdrive:` resolves to | `gdrive:session-backups/` resolves to |
|---|---|---|---|
| **Local** | Personal OAuth | "My Drive" root | A folder named `session-backups` inside My Drive — clean |
| **Cloud** | Service account w/ `team_drive = 0AEap5R-Wlj8wUk9PVA` | Root of the `session-backups` **shared drive** | A folder named `session-backups` **inside the shared drive named session-backups** — doubly nested |

**Actual backup path observed in cloud:** `gdrive:job-searches-2026-q2/main/SESSION_LOG.md` (no `session-backups` prefix, because the config drops it when writing under the service-account remote — evidence of runtime inconsistency worth investigating).

**Recommendation (one of):**
1. Environment-aware config: detect whether `gdrive:` is a personal My Drive vs a shared drive (check for a configured `team_drive` in rclone.conf) and adjust `backupDir` accordingly.
2. Rename the cloud shared drive to a neutral name (e.g. `claude-code-backups`) and use `backupDir: "gdrive:session-backups"` consistently — the local My Drive folder also named `session-backups` stays, and cloud shared drive gets its own top-level `session-backups` folder.
3. Make `backupDir` support a placeholder like `{root}/session-backups` that resolves to `session-backups` on personal Drive and `.` on shared drive.

### Gap 2 — session-handoff does not restore SESSION_LOG.md at session start

**Observation:** `session-handoff` skill's "At Session Start" step only reads local `SESSION_LOG.md`. The backup is one-way (local → gdrive at session end). In ephemeral cloud containers this means context is silently lost every session.

**Recommendation:** extend the skill's "At Session Start" process to:
1. Detect cloud/ephemeral environment (e.g. `[ -n "$CLAUDE_CODE_CLOUD" ]` or container heuristic)
2. Run `rclone copy gdrive:<repo-name>/<worktree>/SESSION_LOG.md <repo-root>/<worktree>/` before the local file check
3. If pull fails (no backup exists, network blocked), fall through to the existing "no file" path

### Gap 3 — gstack browse Chromium sandbox detection

**Observation:** gstack's `browser-manager.ts` checks `process.env.CI || process.env.CONTAINER`. Cloud sessions don't set either — they run as root without user namespaces, which is the exact case `--no-sandbox` addresses.

**Recommendation:** add a third detection path in browser-manager.ts — e.g. `process.getuid?.() === 0` (running as root) or a positive check on `/.dockerenv` / `/proc/1/cgroup`. Or have the cloud session-start hook export `CONTAINER=1` automatically.

### Gap 4 — Conventional Commits format not enforced by autocommit

**Observation:** gstack auto-committed `chore: add gstack skill routing rules to CLAUDE.md` (and similarly for `.gstack/` gitignore entry). Neither commit matched the davidshaevel dev standards (no `Co-Authored-By:` line with Opus model id, no `related-issues: TT-XXX`).

**Recommendation:** gstack skills that auto-commit should read the project's commit conventions (e.g. from `CLAUDE.md` or a `.commitrules` file) and conform. Alternately, davidshaevel-claude-toolkit could provide a `commit-with-standards` helper that gstack skills invoke instead of raw `git commit`.

### Gap 5 — Linear MCP completely unreachable in cloud (multi-layer block)

This is the **biggest gap** and worth its own subsection.

#### Layer 1 — `.mcp.json` SSE servers not loaded by cloud runtime

The repo's `.mcp.json` declares:

```json
{
  "mcpServers": {
    "linear": {
      "type": "sse",
      "url": "https://mcp.linear.app/sse"
    }
  }
}
```

And `settings.json` has `"enabledMcpjsonServers": ["linear"]`. Both are correct for local CLI. In cloud, only `mcp__github__*` tools are surfaced — the SSE server is never started. This is architecturally built into cloud Claude Code; the container can't reach the user's local machine or load `.mcp.json` servers.

**Evidence:** `ToolSearch` for `mcp__linear` or `linear` returns no matches. `/mcp` in the Claude UI shows only the connected GitHub MCP.

**Open issue:** [anthropics/claude-code#11146](https://github.com/anthropics/claude-code/issues/11146) — "Web session mode lacks MCP server access despite configuration"

#### Layer 2 — `linear.app` blocked at sandbox network egress

Even if Layer 1 were fixed, the cloud sandbox enforces a **hardcoded domain allowlist** via TLS inspection:

```
$ curl -sI https://github.com
HTTP/2 200

$ curl -sI https://linear.app
HTTP/2 403
x-deny-reason: host_not_allowed

$ curl -sI https://anthropic.com
HTTP/2 403
x-deny-reason: host_not_allowed
```

The intercepting CA is `O=Anthropic; CN=sandbox-egress-production TLS Inspection CA`.

#### Layer 3 — Allowlist is not user-configurable

The `sandbox.network.allowedDomains` key in `settings.json` works for **desktop local** sessions but is **ignored in cloud**. Three open GitHub issues confirm:

- [#30112](https://github.com/anthropics/claude-code/issues/30112) — Custom domains aren't propagated to cloud container JWT
- [#38984](https://github.com/anthropics/claude-code/issues/38984) — "Additional allowed domains" setting non-functional
- [#51400](https://github.com/anthropics/claude-code/issues/51400) — Wildcard matching inconsistent

No admin UI, no account-level connector panel, no org admin console — the allowlist is fixed by Anthropic.

#### Workaround options

1. **Use local Claude Code CLI or desktop app (local mode)** for Linear work — `.mcp.json` works fully, no egress restriction. This is the only thing that works today.
2. **Manual sync** — in cloud, work against repo + GitHub; user tells Claude Linear state as needed; sync back to Linear from a local session later.
3. **Future: proxy service on allowlisted host.** Since GitHub is allowed, a GitHub-hosted serverless bridge could relay Linear API calls. Non-trivial; has authentication and security implications; would need a separate project.
4. **File a feature request** for user-configurable cloud egress. No open issue specifically requests this; could be filed at https://github.com/anthropics/claude-code/issues.

### Gap 6 — Slash command registry lags after SessionStart:resume

**Observation:** When a cloud session is resumed (e.g., after closing and reopening the Code tab), the `SessionStart:resume` hook fires and the Claude Code UI appears to drop plugin-provided slash commands. Typing `/` shows only built-ins; `/gstack-*`, `/brainstorm`, `/resolve-code-review`, etc. are missing.

**Not a filesystem issue:** the plugin state on disk is fully intact — `~/.claude/plugins/installed_plugins.json`, `known_marketplaces.json`, and the `marketplaces/<m>/commands/*.md` files are all present and unchanged. This is a client-side registration lag, not a plugin corruption.

**Reproduction observed:** On two separate session resumes in the same session, slash commands initially did not autocomplete. After a short delay and interacting with the input (typing `/` alone, or invoking a built-in like `/help`), the plugin commands reappeared in the autocomplete list without any filesystem intervention.

**Recommendation:** Claude Code should re-scan `~/.claude/plugins/` on `SessionStart:resume` to rebuild the slash-command registry, not just on fresh session start. Until that's fixed, the user-side workaround is simply to wait a few seconds and retry the `/` trigger — no configuration change or file modification is needed.

---

## 6. State That Does Not Persist Across Cloud Sessions

Anything not committed to git or backed up to `gdrive:` is lost when the container is destroyed:

- `~/.gstack/` — all gstack config (telemetry, proactive, routing_declined markers, session timeline)
- `.envrc` (gitignored)
- `CLAUDE.local.md` (gitignored)
- `SESSION_LOG.md` (gitignored — but currently ONLY backed up at session end via `session-handoff`; not restored at start — see Gap 2)
- `/tmp/` contents

The gstack one-time prompts (lake, telemetry, proactive, routing) re-fire every session unless the marker files in `~/.gstack/` persist — which they won't in cloud.

**Recommendation:** expand `backup-local-config.json` globals or add a gstack-aware path to sync `~/.gstack/.completeness-intro-seen`, `.telemetry-prompted`, `.proactive-prompted` flags to gdrive too.

---

## 7. Reproduction Checklist — New Cloud Session

For future "fresh cloud session" boot-ups, run:

```bash
# 1. Verify plugins loaded
cat ~/.claude/plugins/installed_plugins.json

# 2. Verify rclone + remote
command -v rclone && rclone listremotes

# 3. Restore SESSION_LOG.md (cloud is flat checkout, hardcode main — see Section 3.5)
REPO_ROOT=$(git rev-parse --show-toplevel)
REPO_NAME=$(basename "$REPO_ROOT")
WORKTREE="main"
rclone copy "gdrive:${REPO_NAME}/${WORKTREE}/SESSION_LOG.md" "$REPO_ROOT/" || echo "no backup"

# 4. Export CONTAINER=1 for gstack browse
export CONTAINER=1

# 5. Seed backup-config if missing
CONFIG_DIR="$HOME/.claude/plugins/marketplaces/davidshaevel-marketplace/config"
[ -f "$CONFIG_DIR/backup-config.json" ] || cp "$CONFIG_DIR/backup-config.json.example" "$CONFIG_DIR/backup-config.json"

# 6. Verify GitHub MCP (no action; tools show up automatically)

# 7. Accept that Linear is unreachable — defer Linear work to local CLI
```

Consider moving items 1-5 into the session-start hook itself so future cloud sessions boot clean without manual steps.

---

## 8. Open Questions for Follow-Up Project

1. Should `session-handoff` auto-restore from gdrive at session start? (almost certainly yes for cloud)
2. Should gstack's `CONTAINER=1` detection be fixed upstream in `browser-manager.ts` or worked around per-project in the session-start hook?
3. Should the cloud shared drive be renamed to avoid Gap 1's double-nesting?
4. Is a Linear API proxy worth building, or is "use local CLI for Linear" an acceptable workflow permanently?
5. Should auto-commits from gstack conform to the davidshaevel commit conventions? If yes, how do skills discover the convention?
