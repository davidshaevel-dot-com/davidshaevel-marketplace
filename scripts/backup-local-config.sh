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
