# Toolkit v2.0.0: rename to `davidshaevel-agent-toolkit` and adopt AGENTS.md

**Issue:** TT-553 · **Related:** TT-499, TT-538, TT-537 · **Design approved:** David Shaevel, 2026-10-09

## Summary

Two changes ship as one release:

1. The plugin `davidshaevel-claude-toolkit` becomes `davidshaevel-agent-toolkit`, since it already serves Claude Code and Codex.
2. This repo, the bootstrap skill and the templates adopt the harness-neutral layout: `AGENTS.md` is canonical, `CLAUDE.md` is a one-line import, and private context lives in `AGENTS.local.md`.

The release is v2.0.0 (MAJOR). Renaming the plugin renames every namespaced skill and command id, which the versioning policy in `CLAUDE.md` classifies as MAJOR. The template removals add a second break.

## Decisions (David, 2026-10-09)

- 08:19 — The name is `davidshaevel-agent-toolkit`.
- 08:25 — Only the plugin is renamed. The repo, the marketplace name, the GitHub URL and the first cache-path segment stay `davidshaevel-marketplace`.
- 09:04 — Clean cut in one release, with no transitional dual entry.
- 09:12 — Ship as v2.0.0 with a one-line history note that v1.x shipped as `davidshaevel-claude-toolkit`. Rollups, Linear records and past release notes stay as written.
- 09:16, 09:18 — The repo adopts AGENTS.md + AGENTS.local.md, and so do the bootstrap skill and the templates.

## Scope

**In:** Sections 1, 2 and 6, the release, and the runbook text.

**Out:**
- Migrating other repos to AGENTS.md (TT-499).
- Cross-repo reference PRs (follow-ons).
- The orchestrator's roster and memory.
- `scripts/backup-local-config.sh` and its tests, which mention `CLAUDE.local.md` only in comments and fixtures.

**Dated records stay as written:** `CHANGELOG.md`, the README history note, `docs/2026-04-23_cloud_environment_test_observations.md`, `docs/superpowers/specs/2026-03-31-backup-local-config-design.md`, `docs/superpowers/plans/2026-03-31-backup-local-config.md`, and this spec.

## Design

### 1. Identifiers

Set the name to `davidshaevel-agent-toolkit` and the version to `2.0.0` in:

- `.claude-plugin/marketplace.json` (`.plugins[0].name` and `.plugins[0].version`; the top-level `name` stays `davidshaevel-marketplace`)
- `.claude-plugin/plugin.json` (`.name`, `.version`)
- `.codex-plugin/plugin.json` (`.name`, `.version`)

The README note that the id was "retained (despite 'claude' in the name) for install-command and marketplace-registration stability" is reversed on purpose. There are no external consumers, so the rename costs one migration on one machine.

### 2. This repo's references

Swap `davidshaevel-claude-toolkit` for `davidshaevel-agent-toolkit`. The baseline is `git grep` at `90ca52e`: 55 hits in 19 files.

| File | Lines |
|---|---|
| `hooks/session-start.sh` | 2 (header), 39 (injected "conventions are provided by the … plugin") |
| `README.md` | 24 (install), 90–175 (cache paths), 269 (skill invocation), 276, 281 |
| `scripts/cloud_setup_script.sh` | 10, 46 |
| `commands/bootstrap-project.md`, `resolve-code-review.md`, `self-hosted-review.md` | 5. **Functional:** each invokes `<plugin>:<skill>` |
| `skills/backup-local-config/SKILL.md` | 13 |
| `skills/bootstrap-project/SKILL.md` | 40 ("What NOT to include") |
| `conventions/development-standards.md` | 3 |
| `docs/cloud_session_setup.md` | 13, 43, 63, 153, 194 |
| `docs/cloud_backup_setup.md` | 3 |
| `CHANGELOG.md` | 3 (header sentence) |

Three more lines change:

- **`CLAUDE.md:9`** (moving to `AGENTS.md`): the retained-name sentence becomes "The plugin `name` is `davidshaevel-agent-toolkit` (v2.0.0+)." The old name does not appear in it.
- **`README.md:13`:** becomes the history note (see Release).
- **`README.md:24`:** it is reversed today (marketplace@plugin) and becomes `/plugin install davidshaevel-agent-toolkit@davidshaevel-marketplace`.

**Acceptance:** this command prints exactly one line, the README history note.

```bash
git grep -n davidshaevel-claude-toolkit -- ':!CHANGELOG.md' \
  ':!docs/2026-04-23_cloud_environment_test_observations.md' \
  ':!docs/superpowers/specs/2026-03-31-backup-local-config-design.md' \
  ':!docs/superpowers/plans/2026-03-31-backup-local-config.md' \
  ':!docs/superpowers/specs/2026-10-09-agent-toolkit-rename-and-agents-md-design.md'
```

### 3. Tracked references in other repos

One PR per repo, after the release. Each is a mechanical swap, verified by a grep showing zero old-name hits.

- **job-searches-2026-q4 `main`:** `.claude/settings.json` (`enabledPlugins` key), `.claude/hooks/session-start.sh`, `README.md`.
- **job-searches-2026-q3 `main`:** `.claude/settings.json`, `.claude/hooks/session-start.sh`. It's an archive, but a session launched there must still resolve the plugin.
- **development-tooling-2026-q4 `main`:** `README.md`.

### 4. David's migration on the M1

The model cannot write permission files, so every step except 9 is a `!` line David runs. The full list is in the Migration runbook below.

### 5. Order and verification

1. This repo's PR merges, and v2.0.0 is tagged and released.
2. David runs the runbook.
3. The three cross-repo PRs land, because tracked settings should name only a plugin the marketplace already serves.

Sessions open during the swap keep the old cache until they restart. The checks are listed under Verification.

### 6. AGENTS.md adoption (TT-537 layout is the model)

**This repo**

- `git mv CLAUDE.md AGENTS.md`. Then in `AGENTS.md`:
  - The title becomes `# davidshaevel-marketplace - Agent Context`.
  - The `<!-- If CLAUDE.local.md exists … -->` comment (line 3) is removed.
  - The repository tree (lines 91–98) lists `AGENTS.md`, `CLAUDE.md`, `AGENTS.local.md` and the new templates.
  - The file ends with mission-control's block, verbatim:

    ```
    ## Private policy

    Operator-private rules live in `AGENTS.local.md` beside this file (gitignored).
    Harnesses with import support load it here: @AGENTS.local.md
    Otherwise: if `AGENTS.local.md` exists, read it before acting; if not, continue without it.
    ```

- New `CLAUDE.md`: exactly `@AGENTS.md`.
- `.gitignore` keeps `CLAUDE.local.md` and adds `AGENTS.local.md` and `*.local.md`. The glob covers the kept copy.
- `config/backup-config.json.example` and the README config example (line 242) add `"AGENTS.local.md"` after `"CLAUDE.local.md"`.
- The private file in `main/` moves post-merge (runbook step 9) and is kept as `CLAUDE.pre-tt553.local.md`.

**Templates**

- `git mv` the existing templates:
  - `CLAUDE.md.template` → `AGENTS.md.template`, with the same title/comment/tree edits plus the Private policy block.
  - `CLAUDE.local.md.template` → `AGENTS.local.md.template`.
  - `CLAUDE.local.md.example` → `AGENTS.local.md.example`.
- New `templates/CLAUDE.md.template`: exactly `@AGENTS.md`.
- `gitignore-additions.txt` lists `AGENTS.local.md`, `CLAUDE.local.md` (legacy) and `SESSION_LOG.md`.
- `cursorrules.template` is untouched.

**Skills and conventions**

- **`bootstrap-project`:**
  - The description lists the new file set.
  - Step 2 generates `AGENTS.md`.
  - A new step generates the import-only `CLAUDE.md`.
  - The private step generates `AGENTS.local.md`.
  - The `.gitignore` block, the checklist and the next steps name `AGENTS.local.md`.
  - "What NOT to include" names `davidshaevel-agent-toolkit`.
- **`session-handoff`:**
  - All 10 `CLAUDE.local.md` mentions (lines 115–133, 175) are rewritten under the heading "Worktree Cleanup (Merging AGENTS.local.md)".
  - The private file is `AGENTS.local.md`, or `CLAUDE.local.md` in an unmigrated repo.
  - Merge into the name main uses. If the worktree's file has the other name, merge its content into main's file and don't create a second name.
- **`backup-local-config`:** the description (line 3) reads "AGENTS.local.md (or legacy CLAUDE.local.md)".
- **`conventions/development-standards.md`:** lines 245, 254 and 342 follow the same primary/legacy rule.

Only this repo migrates now. An unmigrated repo still merges and backs up through the legacy case.

## Migration runbook (after the release)

Subcommands were verified with `claude plugin help <cmd>` on Claude Code 2.1.295: `uninstall`, `install`, `list`, and `marketplace update [name]`. `uninstall` and `install` take `-s user|project|local`, defaulting to `user`.

1. Uninstall at user scope:
   ```bash
   claude plugin uninstall davidshaevel-claude-toolkit@davidshaevel-marketplace --scope user
   ```
2. Uninstall the project-scope copy:
   ```bash
   cd ~/workspace/job-searches-2026-q4/main && claude plugin uninstall davidshaevel-claude-toolkit@davidshaevel-marketplace --scope project
   ```
3. Refresh the marketplace:
   ```bash
   claude plugin marketplace update davidshaevel-marketplace
   ```
4. Install the new id:
   ```bash
   claude plugin install davidshaevel-agent-toolkit@davidshaevel-marketplace --scope user
   ```
5. In `~/.claude/settings.json`:
   - **Verify `enabledPlugins` first:** `grep -n 'toolkit@davidshaevel-marketplace' ~/.claude/settings.json` should show `"davidshaevel-agent-toolkit@davidshaevel-marketplace": true` and no old key. Edit only if the CLI didn't.
   - **Line 19:** `Bash("/Users/dshaevel/.claude/plugins/cache/davidshaevel-marketplace/davidshaevel-claude-toolkit/*/scripts/backup-local-config.sh" *)` → `Bash("/Users/dshaevel/.claude/plugins/cache/davidshaevel-marketplace/davidshaevel-agent-toolkit/*/scripts/backup-local-config.sh" *)`
   - **Line 20:** `Bash(/Users/dshaevel/.claude/plugins/cache/davidshaevel-marketplace/davidshaevel-claude-toolkit/*/scripts/backup-local-config.sh *)` → `Bash(/Users/dshaevel/.claude/plugins/cache/davidshaevel-marketplace/davidshaevel-agent-toolkit/*/scripts/backup-local-config.sh *)`
6. In `~/.claude/config/backup-config.json`, add `"AGENTS.local.md"` to `globalFiles` after `"CLAUDE.local.md"`.
7. In `~/.codex/config.toml`, rename two keys:
   - `[plugins."davidshaevel-claude-toolkit@davidshaevel-marketplace"]` → `[plugins."davidshaevel-agent-toolkit@davidshaevel-marketplace"]`
   - `[hooks.state."davidshaevel-claude-toolkit@davidshaevel-marketplace:hooks/hooks-codex.json:session_start:0:0"]` → `[hooks.state."davidshaevel-agent-toolkit@davidshaevel-marketplace:hooks/hooks-codex.json:session_start:0:0"]`
8. Swap the name in laptop-maintenance's local settings:
   ```bash
   F=~/workspace/laptop-maintenance/main/.claude/settings.local.json
   grep -n davidshaevel-claude-toolkit "$F"
   sed -i '' 's/davidshaevel-claude-toolkit/davidshaevel-agent-toolkit/g' "$F"
   grep -c davidshaevel-claude-toolkit "$F"   # expect 0
   ```
9. Move this repo's private file (orchestrator or David; workers don't write `main/`):
   ```bash
   cd ~/workspace/davidshaevel-marketplace/main && git pull && cp CLAUDE.local.md CLAUDE.pre-tt553.local.md && mv CLAUDE.local.md AGENTS.local.md
   ```
10. Delete the old cache:
    ```bash
    rm -rf ~/.claude/plugins/cache/davidshaevel-marketplace/davidshaevel-claude-toolkit
    ```
11. Restart every Claude Code and Codex session.

**Order check:** each step uses only existing paths. Step 5's new cache path comes from step 4. Step 9's `*.local.md` ignore rule arrives with its own `git pull`. Step 10 removes only what step 1 left behind.

## Release

The implementation PR carries everything for the release:

- the rename and the AGENTS.md layout
- the `2.0.0` bump (CLAUDE.md's jq commands plus the name edits)
- a dated `2.0.0` CHANGELOG section instead of an `Unreleased` one, so `main` never serves the new name under a 1.x version

Right after the merge come the annotated tag `v2.0.0` and the GitHub release "v2.0.0 — Renamed to davidshaevel-agent-toolkit; AGENTS.md layout (TT-553)". The notes follow v1.7.0's shape: H2 sections, the MAJOR rationale, a "Migrating from 1.x" callout pointing at the runbook, and `related-issues: TT-553`.

**README history note (line 13):**

> **Name history:** v1.x shipped as `davidshaevel-claude-toolkit`; v2.0.0 renamed the plugin to `davidshaevel-agent-toolkit` (TT-553). The repository and marketplace keep the name `davidshaevel-marketplace`.

**CHANGELOG entry.** The heading date is the merge day, written by the implementer at merge time.

```markdown
## 2.0.0 — <merge date>

### Changed (breaking)

- Plugin renamed `davidshaevel-claude-toolkit` → `davidshaevel-agent-toolkit`
  (TT-553). Every namespaced skill and command id changes, as does the cache
  path (`~/.claude/plugins/cache/davidshaevel-marketplace/davidshaevel-agent-toolkit/`).
  Repository, marketplace name and GitHub URL are unchanged. No alias for the
  old id: uninstall it and install the new one.
- AGENTS.md layout: context in `AGENTS.md`, `CLAUDE.md` is `@AGENTS.md`, private
  context in `AGENTS.local.md`. `bootstrap-project` and `templates/` generate it;
  `CLAUDE.local.md.template`/`.example` become `AGENTS.local.md.*`.
  `session-handoff`, `backup-local-config` and the conventions treat
  `AGENTS.local.md` as primary, `CLAUDE.local.md` as legacy.

MAJOR: renaming the plugin renames every skill and command.
```

## Verification

**In the PR:**

- The Section 2 grep prints one line.
- `jq -r '.plugins[0].name, .plugins[0].version' .claude-plugin/marketplace.json` and `jq -r '.name, .version' .claude-plugin/plugin.json .codex-plugin/plugin.json` show the new name and `2.0.0` three times.
- `grep -rh '"version"' .claude-plugin/ .codex-plugin/` prints three `2.0.0` lines.
- `claude plugin validate .` passes.
- `bash hooks/session-start.sh | jq -r .hookSpecificOutput.additionalContext | head -2` names the new plugin.
- `cat CLAUDE.md templates/CLAUDE.md.template` prints `@AGENTS.md` twice.
- `ls templates/` shows no `CLAUDE.local.*`.
- The backup test script passes under `/bin/bash` and `/usr/local/bin/bash`.

**After the migration:**

- Fresh Claude Code sessions in mission-control, job-searches-2026-q4 and this repo inject the conventions under the new name.
- `claude plugin list` shows only the new id.
- `backup-local-config.sh` runs from `…/davidshaevel-agent-toolkit/2.0.0/scripts/` and prints `Using config: ~/.claude/config/backup-config.json`.
- A Codex session starts without a hook error.

## Follow-on dispatches

1. The implementation plan (writing-plans), after David approves this spec.
2. The job-searches-2026-q4, job-searches-2026-q3 and development-tooling-2026-q4 reference PRs (Section 3).
3. The orchestrator updates `config/roster.local.json` and its memory file.

## Risks

- **Settings writes are classifier-blocked.** Steps 5–8 are David's `!` lines.
- **Open sessions keep the old cache.** Their `${CLAUDE_PLUGIN_ROOT}` points at the path step 10 deletes. Restart everything, and never run a session-end handoff from a pre-migration session.
- **Worktrees carry copies of tracked settings.** Feature worktrees in job-searches-2026-q4/-q3 that branched before their Section 3 PR still name the old id until they pick up `main`.
- **Codex hook-state key mismatch.** Renaming the plugin table without the `hooks.state` key leaves the hook's stored state under the old id, and the conventions may stop injecting. Step 7 renames both together.
- **Dirty tracked file.** Step 2 modifies job-searches-2026-q4/main's tracked `.claude/settings.json` until its Section 3 PR lands. That PR is the cure; don't commit the CLI's edit.
