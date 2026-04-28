# 2026-04-23 — Cloud Environment Test Observations

**Branch:** `claude/test-cloud-config-o8PJZ`
**Environment:** Claude Code on iOS / cloud session, project `job-searches-2026-q2`
**Scope:** Gaps discovered while smoke-testing cloud environment configuration. Each item is a to-fix with enough context to work from in a future implementation session.

---

## 1. Plugin cache is empty at cloud session start — needs population in SessionStart workflow

### What we observed

- `~/.claude/plugins/installed_plugins.json` correctly lists both plugins at project scope:
  - `davidshaevel-claude-toolkit@davidshaevel-marketplace` v1.3.1 → expected at `~/.claude/plugins/cache/davidshaevel-marketplace/davidshaevel-claude-toolkit/1.3.1/`
  - `superpowers@superpowers-dev` v5.0.7 → expected at `~/.claude/plugins/cache/superpowers-dev/superpowers/5.0.7/`
- Marketplace source is present at `~/.claude/plugins/marketplaces/davidshaevel-marketplace/` and `~/.claude/plugins/marketplaces/superpowers-dev/` (both with full `skills/`, `commands/`, `hooks/`, `.claude-plugin/` contents).
- The **cache directory was completely empty** (`~/.claude/plugins/cache/` did not exist). As a result:
  - davidshaevel-claude-toolkit skills (`session-handoff`, `resolve-code-review`, `bootstrap-project`, `backup-local-config`) did not surface in the session's available-skills list.
  - superpowers skills (`brainstorming`, `systematic-debugging`, `test-driven-development`, `writing-plans`, `verification-before-completion`, `requesting-code-review`, `using-git-worktrees`, etc.) also did not surface.
  - Plugin slash commands (`/brainstorm`, `/write-plan`, `/execute-plan`, `/bootstrap-project`, `/resolve-code-review`, `/davidshaevel-claude-toolkit:session-handoff`) could not be invoked until the cache was populated.
- After manually copying the marketplace contents into the expected cache paths (excluding `.git`), the `/davidshaevel-claude-toolkit:session-handoff` slash command worked immediately — confirming cache population was the missing step.

### What to fix

Add a step to the cloud SessionStart workflow (same hook that already materializes `rclone.conf` from `RCLONE_CONF_B64`) that:

1. Reads `~/.claude/plugins/installed_plugins.json` to enumerate installed plugins and their expected cache paths.
2. For each entry, if the cache path does not exist or is empty, copy the corresponding marketplace source (`~/.claude/plugins/marketplaces/<marketplace-name>/`) into it, excluding `.git`.
3. Also copy required runtime configs that live outside the plugin's own tree if needed (see item 2 below for the backup-config example).

**Reference commands used for the manual workaround (good starting point for the hook logic):**

```bash
jq -r '.plugins | to_entries[] | .value[0].installPath' "$HOME/.claude/plugins/installed_plugins.json" | while IFS= read -r dst; do
  # dst = $HOME/.claude/plugins/cache/<marketplace>/<plugin>/<version>
  marketplace=$(basename "$(dirname "$(dirname "$dst")")")
  src="$HOME/.claude/plugins/marketplaces/$marketplace"
  # idempotency: skip if destination already populated
  if [ -d "$dst" ] && [ -n "$(ls -A "$dst" 2>/dev/null)" ]; then
    continue
  fi
  mkdir -p "$dst"
  rsync -a --exclude='.git' "$src/" "$dst/"
done
```

The exact layout assumption (marketplace root == plugin root, i.e. `"source": "./"` in `marketplace.json`) should be verified per entry — read each marketplace's `.claude-plugin/marketplace.json` and resolve the `source` relative path before copying.

### Why it belongs in SessionStart

- Cloud sandboxes are ephemeral — `~/.claude/plugins/cache/` does not persist between sessions.
- The `rclone.conf` materialization already establishes the "rehydrate config at session start from immutable inputs" pattern. Cache population fits the same pattern.
- Without this, every cloud session loses access to plugin skills and commands until manually fixed.

---

## 2. SESSION_LOG.md backup did not go to the right location — needs env-aware backup config

### What we observed

- The `session-handoff` skill wrote `SESSION_LOG.md` correctly at `/home/user/job-searches-2026-q2/SESSION_LOG.md`.
- The backup script `backup-local-config.sh` required a config file at `<marketplace>/config/backup-config.json` which did not exist (only `.example` was present). Manual step: `cp backup-config.json.example backup-config.json`.
- The example defaults (`"backupDir": "gdrive:session-backups"`) matched the cloud environment's rclone remote (`gdrive:` — configured from `RCLONE_CONF_B64`), so the backup technically succeeded — but it uploaded to the wrong destination for a cloud session.
- Verified upload: `rclone ls gdrive:session-backups/job-searches-2026-q2/SESSION_LOG.md` → file present.

### What to fix

The backup needs to differentiate environments:

**Cloud environment:**
- Use a **service account** (authenticated via `RCLONE_CONF_B64` — already works)
- Use a **shared drive** (Team Drive) as the destination — not a personal My Drive, since the service account may not have quota on a personal drive and persistence belongs to the shared space
- Example destination: `gdrive-service:<shared-drive-id>/session-backups/<repo-name>/`

**Local environment (macOS / laptop):**
- Use the user's **personal Google account** OAuth remote
- Destination in **My Drive**: `gdrive:session-backups/<repo-name>/` (current behavior)

### Proposed config shape

Extend `backup-config.json` to support environment-scoped overrides:

```json
{
  "default": {
    "backupDir": "gdrive:session-backups"
  },
  "environments": {
    "cloud": {
      "backupDir": "gdrive-service:<shared-drive-id>/session-backups",
      "detectWhen": "env:CLAUDE_CODE_CLOUD_SESSION=true"
    },
    "local": {
      "backupDir": "gdrive:session-backups"
    }
  },
  "globalFiles": ["SESSION_LOG.md", "CLAUDE.local.md"],
  "repoOverrides": {
    "my-project": { "additionalFiles": [".envrc", ".env"] }
  }
}
```

### Detection strategy

Pick one signal (in preference order):

1. Explicit env var set by the cloud runner (`CLAUDE_CODE_CLOUD_SESSION=true` or similar) — cleanest.
2. Hostname / filesystem layout heuristic — cloud-session sentinel values: cwd under `/home/user/` combined with effective UID being 0 (`[ "$(id -u)" = "0" ]`). These are signals the script reads to detect environment, not hardcoded assumptions for the script's own paths.
3. Presence of `RCLONE_CONF_B64` in env (implies cloud rehydration path).

### Related cleanup

- Ship a real `backup-config.json` (not just `.example`) with sensible defaults, OR have the SessionStart hook create `backup-config.json` from `.example` if missing. Tying this to item 1 (cache population) makes sense.
- The cloud `rclone.conf` needs a second remote (`gdrive-service:` or whatever name) configured for the service account + shared drive. The local `rclone.conf` keeps the personal-OAuth `gdrive:` remote only.

---

## 3. Verify all three plugin skill sources are callable at end of SessionStart

### What we observed

- gstack skills surfaced fine out-of-the-box (they're installed at `~/.claude/skills/gstack-*`, separate from the plugin cache system).
- davidshaevel-claude-toolkit and superpowers skills were **not** callable until cache was populated manually.
- There was no automated end-of-SessionStart verification — I had to discover the gap by trying to invoke a skill and watching it fail.

### What to fix

Add an end-of-SessionStart verification step that:

1. Enumerates expected skills from each source:
   - **gstack:** glob `~/.claude/skills/gstack-*` (or parse gstack's own manifest if one exists)
   - **davidshaevel-claude-toolkit:** glob `<cache>/davidshaevel-marketplace/davidshaevel-claude-toolkit/<version>/skills/*`
   - **superpowers:** glob `<cache>/superpowers-dev/superpowers/<version>/skills/*`
2. For each expected skill, confirm the expected file path exists (e.g., `skills/<name>/SKILL.md`).
3. On mismatch, print a clear warning naming the missing skill and its expected path.

### Stretch: runtime verification

Beyond file-presence, the hook could attempt a dry invocation check — but that's expensive and probably overkill. File-presence + version match against `installed_plugins.json` should be enough.

---

## 4. Print available slash commands at end of SessionStart

### What we observed

- iOS Claude Code does not autocomplete slash commands when `/` is typed. Discovery is manual: the user has to already know the command names to invoke them.
- `/help` was not tested but `gstack` skills use the `/gstack-<name>` prefix (with `skill_prefix: true` set), so which prefix applies isn't obvious without inspecting config.
- The `davidshaevel-claude-toolkit:session-handoff` command needed the namespaced form (`/davidshaevel-claude-toolkit:session-handoff`) rather than just `/session-handoff`. This wasn't discoverable from within the session.

### What to fix

At the end of SessionStart, print a grouped, ready-to-copy list of every slash command the user can invoke:

```
Available slash commands in this session:

gstack (prefix: gstack-):
  /gstack-qa, /gstack-ship, /gstack-investigate, /gstack-review, /gstack-brainstorm, ...

davidshaevel-claude-toolkit:
  /davidshaevel-claude-toolkit:session-handoff
  /davidshaevel-claude-toolkit:resolve-code-review
  /davidshaevel-claude-toolkit:bootstrap-project
  /davidshaevel-claude-toolkit:backup-local-config

superpowers:
  /brainstorm
  /write-plan
  /execute-plan
```

### Source-of-truth

- **gstack:** glob `~/.claude/skills/gstack-*` → derive `/gstack-<name>` if `SKILL_PREFIX=true`, else `/<name>`.
- **davidshaevel-claude-toolkit:** glob `<cache>/.../1.3.1/commands/*.md` — these are the real slash commands. Use namespaced form.
- **superpowers:** glob `<cache>/.../5.0.7/commands/*.md` → these appear to use unprefixed form (`/brainstorm`, `/write-plan`, `/execute-plan`).

Format as a single block at the very end of SessionStart so it's the last thing the user sees before typing their first message.

### Stretch: show skill-backed commands separately

Some skills are invocable via slash even if there's no `commands/*.md` entry (via namespace `/plugin:skill-name`). The output could also enumerate these — though that list will be much longer. Start with just the explicit `commands/*.md` files and iterate.

---

## 5. Cloud-session commits and branch names don't follow project conventions — enforce or formalize exceptions

### What we observed

The davidshaevel-claude-toolkit session-start hook injects `conventions/development-standards.md` into every cloud session (visible in the `<IMPORTANT>` block at the top of each turn). Despite that, the cloud-session agents (including this session) have not been consistently applying the conventions when committing or naming branches.

**Conventions documented in the toolkit** (sources: `conventions/development-standards.md`, `skills/bootstrap-project/SKILL.md`):

- **Branch naming:** `claude/<issue-id>-<brief-description>` or `david/<issue-id>-<brief-description>`. Issue ID is required (Linear `TT-XXX`).
- **Commit message format (Conventional Commits):**
  ```
  <type>(<scope>): <short description>

  Longer description if needed.

  Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>

  related-issues: TT-XXX
  ```
- **Types:** `feat`, `fix`, `docs`, `chore`, `refactor`, `test`
- **Scope:** descriptive feature word/phrase, never the issue ID, never a generic tech name
- **`related-issues: TT-XXX` trailer is required** — issue numbers belong here, not in the scope
- **Co-Authored-By trailer is required** with the agent identity
- **Squash and merge** for all PRs; never merge without code review
- **Code review replies** must start with `@gemini-code-assist` to trigger notification
- **Bootstrap-project skill expects these files:** `CLAUDE.md`, `.cursorrules`, `CLAUDE.local.md` (gitignored), `SESSION_LOG.md` (gitignored), with `.gitignore` entries for the agent-context files

**Where the cloud session has been deviating:**

- **Branch name:** `claude/test-cloud-config-o8PJZ` — the `o8PJZ` suffix is a random ID generated by the cloud runner, not an `issue-id` and not a brief description. There is no Linear `TT-XXX` for this work.
- **`related-issues:` trailer omitted:** Recent commits on this branch (and on `main` — see `93e4376`, `28c9d8b`, `14f01aa`) all omit the `related-issues:` trailer entirely. There is no documented fallback for "this work has no Linear issue."
- **Co-Authored-By model version drift:** Convention specifies `Claude Opus 4.6`, but commits have been authored by `Claude Opus 4.7` (the actual model in use). The convention text is stale, or the trailer should be model-agnostic.
- **No CLAUDE.local.md or SESSION_LOG.md** present in the cloud sandbox at session start. They are gitignored and only persist via the Google Drive backup (see item 2). The bootstrap-project skill assumes they exist for a normal project; the cloud session needs to either restore them at start or accept their absence as a known gap.

### What to fix

This is partially a **process/documentation** fix and partially a **tooling** fix.

**Documentation decisions needed (write into `conventions/development-standards.md`):**

1. **No-issue commits:** Decide the rule for commits that have no Linear issue. Options:
   - **(a) Require an issue** — agent must create a Linear issue before any commit (heavy for tooling/meta-work).
   - **(b) Allow `related-issues: none`** — explicit placeholder; trailer always present, value can be `none` for infra/meta work.
   - **(c) Allow omission** — make the trailer required only when a real issue applies; current de facto behavior.

   Recommendation: **(b)** — keeps the trailer present for grep/audit consistency, costs nothing.

2. **Cloud-generated branch suffixes:** Decide how the random suffix (`-o8PJZ`) maps to the convention. Options:
   - **(a) Reject** — require cloud branches to be renamed to follow `claude/TT-XXX-<desc>` before commit (high friction).
   - **(b) Treat the suffix as the issue-id slot** — e.g., document that `claude/<random>-<desc>` is the cloud-session-allowed form when no TT issue exists.
   - **(c) Document a `claude/cloud-test-<desc>` or similar reserved prefix** for meta/test work.

   Recommendation: **(b) + (c)** — reserve `claude/test-<desc>` and `claude/cloud-<desc>` prefixes for meta-work; otherwise enforce `claude/TT-XXX-<desc>`.

3. **Co-Authored-By model version:** Either (a) update the convention to the current Opus version on each release, or (b) make the trailer model-agnostic with `Claude Code <noreply@anthropic.com>`. Recommendation: **(b)** — won't go stale.

**Tooling fix (should land alongside item 1's SessionStart cache work):**

- After injecting `development-standards.md` into the session, the SessionStart hook should also write a short **"agent commit checklist"** as a first-message note (or include it in the printed slash-command list from item 4):

  ```
  Commit checklist for this branch (claude/test-cloud-config-o8PJZ):
    - Conventional Commit format: <type>(<scope>): <description>
    - related-issues: trailer required (use "none" if no TT issue applies)
    - Co-Authored-By: <agent identity> trailer required
    - Squash and merge for all PRs
    - Never merge without review
  ```

- Optionally: a pre-commit hook (or a stop-hook check) that validates the in-progress commit message against the format and rejects with a clear error.

### Cross-references for the implementer

- Convention source of truth: `~/.claude/plugins/marketplaces/davidshaevel-marketplace/conventions/development-standards.md`
- Bootstrap-project skill: `~/.claude/plugins/marketplaces/davidshaevel-marketplace/skills/bootstrap-project/SKILL.md`
- Slash command: `/davidshaevel-claude-toolkit:bootstrap-project` (creates the standard file scaffold for new projects; reference for what files are expected to exist)
- Session-start hook: same plugin repo, `hooks/` directory

---

## 6. SESSION_LOG.md timestamps use UTC instead of the user's local time

### What we observed

The session-handoff skill's SKILL.md requires timestamps in local time:

> **Timestamps are required** — both `Last session:` in Current State and every session history heading MUST include `HH:MM` (24-hour local time), not just the date. Run `date +"%Y-%m-%d %H:%M"` to get the current timestamp.

But the skill's prescribed command — `date +"%Y-%m-%d %H:%M"` — returns the **server's** local time, which in the Claude Code cloud sandbox is UTC (`Etc/UTC`):

```
$ date
Fri Apr 24 03:17:12 UTC 2026
$ cat /etc/timezone
Etc/UTC
```

The user running this session is in Austin (`America/Chicago`, CDT = UTC-5 in April). Every SESSION_LOG.md written from a cloud session therefore has timestamps offset by +5 hours from the user's wall clock — and in the small hours, the **date** also shifts. Observed in this session:

| Entry as written (cloud UTC) | Actual user local time (CDT) |
|---|---|
| `2026-04-23 21:46` | `2026-04-23 16:46` |
| `2026-04-24 02:44` | `2026-04-23 21:44` |

When the user reviewed the backup from Google Drive, the "02:44 today" stamp didn't match their memory of when the session happened, which is how the bug surfaced.

### What to fix

The SKILL.md instruction for getting a timestamp needs to either:

1. **Use the user's configured timezone explicitly** when generating the date:
   ```bash
   TZ="America/Chicago" date +"%Y-%m-%d %H:%M"
   ```
   Hardcodes per-user; not portable across a shared skill.

2. **Read the user's timezone from a config** (e.g., a `userTimezone` field in `backup-config.json`, or a separate `session-handoff-config.json`). The cloud-runtime setup then needs to inject that value at session start (similar to how `RCLONE_CONF_B64` is materialized into `rclone.conf`).

3. **Write in UTC with an explicit label** (`HH:MM UTC` or ISO 8601 `Z` suffix). Keeps timestamps unambiguous without needing to know the user's TZ. Downside: the skill spec explicitly says "local time," and a UTC timestamp requires the reader to do timezone math to connect it to their memory.

4. **Detect the cloud environment** (same UID=0 or env-var signal as item 2's backup-config detection) and fall back to an explicitly-configured user TZ for cloud sessions only, keeping `date +"%Y-%m-%d %H:%M"` as-is for local sessions where the server's TZ matches the user's.

**Recommendation: (4) with (2) as the underlying mechanism.** Inject a `USER_TIMEZONE` env var from the cloud-runner secrets alongside `RCLONE_CONF_B64` (or extend `backup-config.json` to carry it). `USER_TIMEZONE` is provided by the environment, not set by the command itself — cloud sessions receive it from the runner, local sessions leave it unset. The skill's timestamp command then uses `env` to apply the assignment only when the variable is set:

```bash
env ${USER_TIMEZONE:+TZ="$USER_TIMEZONE"} date +"%Y-%m-%d %H:%M"
```

The `env` prefix is required: when `USER_TIMEZONE` is set, `${USER_TIMEZONE:+TZ="$USER_TIMEZONE"}` expands to a word like `TZ=America/Chicago`, which the shell treats as a command name rather than an assignment (shell assignment recognition happens before parameter expansion). `env` accepts `NAME=value` arguments as real env-var assignments for the child command it execs, so it handles the expansion correctly in both bash and POSIX sh/dash. When `USER_TIMEZONE` is unset, the `:+` expansion emits nothing and `env` runs `date` with the inherited environment — no need to inspect `/etc/localtime` or parse zoneinfo paths.

### Secondary fix

Also update existing SESSION_LOG.md files written from cloud sessions so their prior-entry timestamps don't stay misleading. This session's log has already been corrected locally (entries relabeled as CDT with `(CDT)` annotation next to the timestamp), but future cloud sessions shouldn't require manual fixup.

### Cross-references for the implementer

- SKILL.md timestamp instruction: `skills/session-handoff/SKILL.md`, in the "Rules" section
- Cloud-runtime TZ source: `/etc/timezone` reads `Etc/UTC`; no user-level override
- Related cloud-detection work: this pairs with item 2's env-detection mechanism — both need a reliable "am I in cloud?" signal and a user-config source
- This session's corrective annotations: SESSION_LOG.md entries now use `HH:MM (CDT)` suffix for manual clarity until the root fix lands

---

## Priority ordering (for a future implementation session)

1. **Item 1 (cache population)** — blocks everything else. Without the cache, no plugin skills work.
2. **Item 2 (env-aware backup)** — data persistence. Right now cloud sessions' logs leak into the personal drive.
3. **Item 5 (commit/branch convention enforcement)** — pure documentation decisions; fixes the "we say one thing, do another" gap with low effort. The agent-commit-checklist printout pairs naturally with item 4.
4. **Item 4 (slash command list)** — small, high-value UX win. Easy.
5. **Item 6 (SESSION_LOG.md timezone)** — small scope, affects every cloud-session handoff; pairs naturally with item 2's cloud-detection infrastructure.
6. **Item 3 (verification step)** — catches regressions but needs items 1 and 4 to have meaningful output.

## Implementation home

The session-start hook lives in the **davidshaevel-claude-toolkit** plugin repo (`davidshaevel-dot-com/davidshaevel-marketplace`), so items 1, 3, 4, 6, and the tooling half of item 5 are edits there. Item 2 spans both the toolkit repo (config schema + detection) and whatever manages the cloud `rclone.conf` secret (adds the service-account remote to `RCLONE_CONF_B64`). The documentation half of item 5 is pure edits to `conventions/development-standards.md`. Item 6 shares item 2's cloud-detection infrastructure and may also need a `USER_TIMEZONE` injection at the cloud-runner secret layer.
