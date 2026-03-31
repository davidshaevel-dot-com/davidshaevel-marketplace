# backup-local-config Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `backup-local-config` skill to the davidshaevel-claude-toolkit plugin that backs up configured gitignored files to Google Drive via rclone.

**Architecture:** A shell script (`scripts/backup-local-config.sh`) reads a JSON config file (`config/backup-config.json`) to determine which files to back up, detects bare+worktree vs standard repo structure, and copies files to Google Drive via `rclone copy`. A skill definition makes it invocable on-demand, and session-handoff is updated to trigger it automatically at session end.

**Tech Stack:** Bash, jq, rclone, Claude Code Plugin System (SKILL.md format)

---

## File Structure

| File | Action | Responsibility |
|------|--------|---------------|
| `config/backup-config.json` | Create | User-editable config: Drive path, global file list, per-repo overrides |
| `scripts/backup-local-config.sh` | Create | Core backup logic: detect repo structure, build file list, rclone copy |
| `skills/backup-local-config/SKILL.md` | Create | Skill definition for on-demand invocation |
| `skills/session-handoff/SKILL.md` | Modify | Add backup invocation at session end |
| `README.md` | Modify | Add prerequisites, configuration, and usage documentation |
| `CLAUDE.md` | Modify | Add new files to repository structure and important file locations |

---

### Task 1: Create backup-config.json

**Files:**
- Create: `config/backup-config.json`

- [ ] **Step 1: Create the config directory and file**

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

Write this to `config/backup-config.json`.

- [ ] **Step 2: Validate JSON is well-formed**

Run: `jq . config/backup-config.json`

Expected: Pretty-printed JSON output matching the file contents, exit code 0.

- [ ] **Step 3: Commit**

```bash
git add config/backup-config.json
git commit -m "feat(backup-local-config): add backup configuration file

Default config backs up SESSION_LOG.md and CLAUDE.local.md globally,
with .envrc and .env overrides for davidshaevel-k8s-platform.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>

related-issues: TT-270"
```

---

### Task 2: Create backup-local-config.sh — Argument Parsing and Dependency Checks

**Files:**
- Create: `scripts/backup-local-config.sh`

- [ ] **Step 1: Write the script with argument parsing and dependency checks**

```bash
#!/usr/bin/env bash
# backup-local-config.sh — Back up configured gitignored files to Google Drive via rclone
#
# Usage:
#   backup-local-config.sh                     # Back up from current repo
#   backup-local-config.sh /path/to/repo       # Back up from specific repo
#   backup-local-config.sh --dry-run            # Preview without uploading
#   backup-local-config.sh --dry-run /path/to/repo

set -euo pipefail

# --- Argument parsing ---
DRY_RUN=false
REPO_PATH=""

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    *)
      if [[ -z "$REPO_PATH" ]]; then
        REPO_PATH="$arg"
      else
        echo "Error: unexpected argument '$arg'" >&2
        echo "Usage: backup-local-config.sh [--dry-run] [/path/to/repo]" >&2
        exit 1
      fi
      ;;
  esac
done

# Default to current directory if no path given
REPO_PATH="${REPO_PATH:-$(pwd)}"

# --- Resolve config path ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/../config/backup-config.json"

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "Error: config file not found at $CONFIG_FILE" >&2
  echo "Create config/backup-config.json in the plugin directory." >&2
  exit 1
fi

# --- Dependency checks ---
if ! command -v rclone &>/dev/null; then
  echo "Error: rclone is not installed." >&2
  echo "Install with: brew install rclone" >&2
  echo "Then configure a Google Drive remote: rclone config" >&2
  exit 1
fi

if ! command -v jq &>/dev/null; then
  echo "Error: jq is not installed." >&2
  echo "Install with: brew install jq" >&2
  exit 1
fi

# --- Read config ---
BACKUP_DIR=$(jq -r '.backupDir' "$CONFIG_FILE")
if [[ -z "$BACKUP_DIR" || "$BACKUP_DIR" == "null" ]]; then
  echo "Error: backupDir not set in $CONFIG_FILE" >&2
  exit 1
fi

# Validate rclone remote is configured
REMOTE_NAME="${BACKUP_DIR%%:*}"
if ! rclone listremotes | grep -q "^${REMOTE_NAME}:$"; then
  echo "Error: rclone remote '$REMOTE_NAME' is not configured." >&2
  echo "Run 'rclone config' to set up a Google Drive remote named '$REMOTE_NAME'." >&2
  exit 1
fi

echo "backup-local-config: argument parsing and dependency checks passed"
echo "  Repo path: $REPO_PATH"
echo "  Config: $CONFIG_FILE"
echo "  Backup dir: $BACKUP_DIR"
echo "  Dry run: $DRY_RUN"
```

- [ ] **Step 2: Make the script executable**

Run: `chmod +x scripts/backup-local-config.sh`

- [ ] **Step 3: Test argument parsing manually**

Run from the worktree root:

```bash
# Test with no args (should show cwd as repo path)
bash scripts/backup-local-config.sh --dry-run 2>&1 || true

# Test with explicit path
bash scripts/backup-local-config.sh --dry-run /tmp 2>&1 || true

# Test with unexpected arg (should show usage error)
bash scripts/backup-local-config.sh --dry-run /tmp extra 2>&1 || true
```

The first two should print the parsed values (and may fail at rclone remote check — that's expected at this stage). The third should print the usage error.

- [ ] **Step 4: Commit**

```bash
git add scripts/backup-local-config.sh
git commit -m "feat(backup-local-config): add script with arg parsing and dependency checks

Handles --dry-run flag, optional repo path argument, config file
resolution, and checks for rclone/jq installation and remote config.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>

related-issues: TT-270"
```

---

### Task 3: Add Repo Detection and File List Building

**Files:**
- Modify: `scripts/backup-local-config.sh`

- [ ] **Step 1: Add repo detection and file list building after the dependency checks**

Append the following to `scripts/backup-local-config.sh`, replacing the final echo block:

```bash
# --- Detect repo name ---
# For bare+worktree repos, the repo root contains .bare/
# For standard repos, the repo root contains .git/
if [[ -d "$REPO_PATH/.bare" ]]; then
  REPO_NAME=$(basename "$REPO_PATH")
  IS_BARE_WORKTREE=true
elif [[ -d "$REPO_PATH/.git" ]] || [[ -f "$REPO_PATH/.git" ]]; then
  REPO_NAME=$(basename "$REPO_PATH")
  IS_BARE_WORKTREE=false
else
  echo "Error: $REPO_PATH does not appear to be a git repository." >&2
  echo "No .bare/ or .git/ directory found." >&2
  exit 1
fi

# --- Build file list ---
# Start with global files
mapfile -t FILE_LIST < <(jq -r '.globalFiles[]' "$CONFIG_FILE")

# Merge repo-specific additional files if configured
ADDITIONAL=$(jq -r --arg repo "$REPO_NAME" '.repoOverrides[$repo].additionalFiles // [] | .[]' "$CONFIG_FILE")
if [[ -n "$ADDITIONAL" ]]; then
  while IFS= read -r f; do
    FILE_LIST+=("$f")
  done <<< "$ADDITIONAL"
fi

# Deduplicate
mapfile -t FILE_LIST < <(printf '%s\n' "${FILE_LIST[@]}" | sort -u)

echo "backup-local-config: repo detection complete"
echo "  Repo name: $REPO_NAME"
echo "  Bare+worktree: $IS_BARE_WORKTREE"
echo "  Files to back up: ${FILE_LIST[*]}"
```

- [ ] **Step 2: Test repo detection**

Run:

```bash
# Test against a bare+worktree repo
bash scripts/backup-local-config.sh --dry-run /Users/dshaevel/workspace-ds/job-searches-2026-q1 2>&1 || true

# Test against the plugin repo itself (also bare+worktree)
bash scripts/backup-local-config.sh --dry-run /Users/dshaevel/workspace-ds/davidshaevel-marketplace 2>&1 || true
```

Expected: Both should show `Bare+worktree: true`, correct repo names, and the file list. May fail at rclone remote check — that's fine.

- [ ] **Step 3: Commit**

```bash
git add scripts/backup-local-config.sh
git commit -m "feat(backup-local-config): add repo detection and file list building

Detects bare+worktree vs standard repo structure. Builds file list
by merging globalFiles with per-repo additionalFiles from config.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>

related-issues: TT-270"
```

---

### Task 4: Add Backup Logic (rclone copy)

**Files:**
- Modify: `scripts/backup-local-config.sh`

- [ ] **Step 1: Add the backup function and main loop**

Append to `scripts/backup-local-config.sh`, replacing the final echo block:

```bash
# --- Backup function ---
backup_file() {
  local src="$1"
  local dest="$2"

  if [[ "$DRY_RUN" == "true" ]]; then
    echo "  [dry-run] would copy: $src -> $dest"
    return 0
  fi

  if rclone copy "$src" "$dest" 2>&1; then
    echo "  [ok] $src -> $dest"
  else
    echo "  [FAILED] $src -> $dest" >&2
    return 1
  fi
}

# --- Counters ---
BACKED_UP=0
SKIPPED=0
FAILED=0

# --- Execute backup ---
if [[ "$IS_BARE_WORKTREE" == "true" ]]; then
  # Bare+worktree: back up files from each worktree
  while IFS= read -r line; do
    WORKTREE_PATH=$(echo "$line" | awk '{print $1}')
    # Skip the bare repo entry itself
    if [[ "$WORKTREE_PATH" == *"/.bare" ]] || [[ "$WORKTREE_PATH" == "$REPO_PATH/.bare" ]]; then
      continue
    fi
    WORKTREE_NAME=$(basename "$WORKTREE_PATH")
    DEST_DIR="$BACKUP_DIR/$REPO_NAME/$WORKTREE_NAME"

    for file in "${FILE_LIST[@]}"; do
      SRC="$WORKTREE_PATH/$file"
      if [[ -f "$SRC" ]]; then
        if backup_file "$SRC" "$DEST_DIR"; then
          ((BACKED_UP++))
        else
          ((FAILED++))
        fi
      else
        ((SKIPPED++))
      fi
    done
  done < <(git -C "$REPO_PATH" worktree list)
else
  # Standard repo: back up files from repo root
  DEST_DIR="$BACKUP_DIR/$REPO_NAME"

  for file in "${FILE_LIST[@]}"; do
    SRC="$REPO_PATH/$file"
    if [[ -f "$SRC" ]]; then
      if backup_file "$SRC" "$DEST_DIR"; then
        ((BACKED_UP++))
      else
        ((FAILED++))
      fi
    else
      ((SKIPPED++))
    fi
  done
fi

# --- Summary ---
echo ""
echo "backup-local-config complete:"
echo "  Backed up: $BACKED_UP"
echo "  Skipped (not found): $SKIPPED"
echo "  Failed: $FAILED"

if [[ "$FAILED" -gt 0 ]]; then
  exit 1
fi
```

- [ ] **Step 2: Test dry run against a real repo**

Run:

```bash
bash scripts/backup-local-config.sh --dry-run /Users/dshaevel/workspace-ds/job-searches-2026-q1
```

Expected output should show `[dry-run] would copy:` lines for each SESSION_LOG.md and CLAUDE.local.md found across the worktrees (main, tt-269-centre-technologies, career-pivot-exploration, fastest-to-start-income, personal-finance-2026-q1), with a summary at the end.

- [ ] **Step 3: Commit**

```bash
git add scripts/backup-local-config.sh
git commit -m "feat(backup-local-config): add backup logic with rclone copy

Iterates worktrees (bare+worktree) or repo root (standard) and copies
each configured file to Google Drive. Supports --dry-run mode.
Logs per-file results and prints summary with counts.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>

related-issues: TT-270"
```

---

### Task 5: Create the Skill Definition

**Files:**
- Create: `skills/backup-local-config/SKILL.md`

- [ ] **Step 1: Create the skill file**

Create `skills/backup-local-config/SKILL.md`:

```markdown
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
```

- [ ] **Step 2: Commit**

```bash
git add skills/backup-local-config/SKILL.md
git commit -m "feat(backup-local-config): add skill definition for on-demand backup

Skill instructs Claude to resolve the repo path, execute the backup
script, and report results with troubleshooting guidance on failure.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>

related-issues: TT-270"
```

---

### Task 6: Update Session-Handoff to Trigger Backup

**Files:**
- Modify: `skills/session-handoff/SKILL.md`

- [ ] **Step 1: Add backup step to "At Session End" sections**

In `skills/session-handoff/SKILL.md`, add a new step at the end of both the "Standard repos" and "Bare + worktree repos" session-end sections.

After the existing step 3 in "Standard repos (no worktrees)" under "At Session End":

```markdown
4. **Back up local config** — Run the backup script to sync gitignored files to Google Drive:
   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/backup-local-config.sh" /path/to/repo
   ```
   Replace `/path/to/repo` with the project root. If the backup fails, log the error but do not block the session handoff.
```

After the existing step 4 in "Bare + worktree repos" under "At Session End":

```markdown
5. **Back up local config** — Run the backup script to sync gitignored files to Google Drive:
   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/backup-local-config.sh" /path/to/repo-root
   ```
   Replace `/path/to/repo-root` with the bare repo root (the directory containing `.bare/`). This backs up files from all worktrees in a single call. If the backup fails, log the error but do not block the session handoff.
```

- [ ] **Step 2: Verify the modified file is valid markdown**

Read the modified `skills/session-handoff/SKILL.md` and verify the new steps are correctly placed and the markdown structure is intact.

- [ ] **Step 3: Commit**

```bash
git add skills/session-handoff/SKILL.md
git commit -m "feat(backup-local-config): integrate backup into session-handoff

Session-handoff now triggers backup-local-config.sh at session end
for both standard and bare+worktree repos. Backup failures are logged
but do not block the handoff.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>

related-issues: TT-270"
```

---

### Task 7: Update README.md with Documentation

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Add backup-local-config to the Skills table**

In `README.md`, add a row to the Skills table:

```markdown
| `backup-local-config` | Back up gitignored local files to Google Drive via rclone |
```

- [ ] **Step 2: Add a new "Backup Local Config" section after the "Updating the Plugin" section**

Add the following section to `README.md`:

```markdown
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

Edit `config/backup-config.json` in the plugin directory:

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
| `backupDir` | rclone remote and path (e.g., `gdrive:session-backups`) |
| `globalFiles` | Files to back up in every repo |
| `repoOverrides.<repo>.additionalFiles` | Extra files for a specific repo (merged with `globalFiles`) |

**To add a new file to back up everywhere:** Add it to `globalFiles`.

**To add a file for one repo only:** Add it to that repo's `additionalFiles` in `repoOverrides`. The repo key is the directory name (e.g., `davidshaevel-k8s-platform`).

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
├── job-searches-2026-q1/
│   ├── main/
│   │   ├── SESSION_LOG.md
│   │   └── CLAUDE.local.md
│   ├── tt-269-centre-technologies/
│   │   └── ...
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

- **Bare+worktree repos:** `<repo-name>/<worktree-name>/<file>`
- **Standard repos:** `<repo-name>/<file>`
```

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs(backup-local-config): add setup, configuration, and usage docs

Covers prerequisites (rclone, jq, Google Drive remote setup),
configuration format, on-demand/automatic/CLI usage, and
Google Drive folder structure.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>

related-issues: TT-270"
```

---

### Task 8: Update CLAUDE.md with New Files

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Add new directories and files to the Repository Structure tree**

In the Repository Structure section of `CLAUDE.md`, add the `config/` and `scripts/` directories:

```
│   ├── config/                        # Plugin configuration
│   │   └── backup-config.json         # Backup file list and destination config
│   │
│   ├── scripts/                       # Plugin scripts
│   │   └── backup-local-config.sh     # Backs up gitignored files to Google Drive
```

Add them after the `conventions/` block, before `hooks/`.

Also add the new skill to the `skills/` tree:

```
│   │   ├── backup-local-config/SKILL.md # Local file backup skill
```

- [ ] **Step 2: Add new entries to the Important File Locations table**

Add these rows:

```markdown
| `config/backup-config.json` | Backup destination and file list configuration |
| `scripts/backup-local-config.sh` | Shell script that backs up gitignored files via rclone |
| `skills/backup-local-config/SKILL.md` | On-demand backup skill definition |
```

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs(backup-local-config): update CLAUDE.md with new files and structure

Added config/, scripts/, and backup-local-config skill to the
repository structure and important file locations table.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>

related-issues: TT-270"
```

---

### Task 9: End-to-End Dry Run Test

**Files:** None (testing only)

- [ ] **Step 1: Run a dry-run backup against the job-searches repo**

Run:

```bash
cd /Users/dshaevel/workspace-ds/davidshaevel-marketplace/tt-270-backup-local-config
bash scripts/backup-local-config.sh --dry-run /Users/dshaevel/workspace-ds/job-searches-2026-q1
```

Expected: `[dry-run] would copy:` lines for SESSION_LOG.md and CLAUDE.local.md in each of the 5 worktrees (main, tt-269-centre-technologies, career-pivot-exploration, fastest-to-start-income, personal-finance-2026-q1). Summary should show backed up count and 0 failures.

- [ ] **Step 2: Run a dry-run backup against the k8s-platform repo**

Run:

```bash
bash scripts/backup-local-config.sh --dry-run /Users/dshaevel/workspace-ds/davidshaevel-k8s-platform
```

Expected: Should show SESSION_LOG.md, CLAUDE.local.md, .envrc, and .env files (the additional files from repoOverrides) for each worktree in that repo.

- [ ] **Step 3: Run a dry-run backup against the plugin repo itself**

Run:

```bash
bash scripts/backup-local-config.sh --dry-run /Users/dshaevel/workspace-ds/davidshaevel-marketplace
```

Expected: Should show SESSION_LOG.md and CLAUDE.local.md for each worktree (main, tt-270-backup-local-config).

- [ ] **Step 4: Test error cases**

Run:

```bash
# Non-git directory
bash scripts/backup-local-config.sh --dry-run /tmp 2>&1
echo "Exit code: $?"

# Unexpected argument
bash scripts/backup-local-config.sh --dry-run /tmp extra 2>&1
echo "Exit code: $?"
```

Expected: First should show "does not appear to be a git repository" error, exit code 1. Second should show "unexpected argument" error, exit code 1.

- [ ] **Step 5: Verify all files are committed and clean**

Run:

```bash
cd /Users/dshaevel/workspace-ds/davidshaevel-marketplace/tt-270-backup-local-config
git status
git log --oneline -10
```

Expected: Clean working tree. Log should show all commits from Tasks 1-8.
