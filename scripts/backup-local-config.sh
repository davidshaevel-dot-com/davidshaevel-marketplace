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
  echo "Copy config/backup-config.json.example to config/backup-config.json and edit it." >&2
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

# --- Tracking arrays ---
BACKED_UP_FILES=()
SKIPPED_FILES=()
FAILED_FILES=()

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
          BACKED_UP_FILES+=("$SRC")
        else
          FAILED_FILES+=("$SRC")
        fi
      else
        SKIPPED_FILES+=("$SRC")
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
        BACKED_UP_FILES+=("$SRC")
      else
        FAILED_FILES+=("$SRC")
      fi
    else
      SKIPPED_FILES+=("$SRC")
    fi
  done
fi

# --- Summary ---
echo ""
echo "backup-local-config complete:"
echo ""
echo "  Backed up (${#BACKED_UP_FILES[@]}):"
if [[ ${#BACKED_UP_FILES[@]} -gt 0 ]]; then
  for f in "${BACKED_UP_FILES[@]}"; do echo "    $f"; done
else
  echo "    (none)"
fi
echo ""
echo "  Skipped — not found (${#SKIPPED_FILES[@]}):"
if [[ ${#SKIPPED_FILES[@]} -gt 0 ]]; then
  for f in "${SKIPPED_FILES[@]}"; do echo "    $f"; done
else
  echo "    (none)"
fi
echo ""
echo "  Failed (${#FAILED_FILES[@]}):"
if [[ ${#FAILED_FILES[@]} -gt 0 ]]; then
  for f in "${FAILED_FILES[@]}"; do echo "    $f"; done
else
  echo "    (none)"
fi

if [[ ${#FAILED_FILES[@]} -gt 0 ]]; then
  exit 1
fi
