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

# Default to current directory if no path given, then resolve to absolute path
REPO_PATH="${REPO_PATH:-$(pwd)}"
if [[ ! -d "$REPO_PATH" ]]; then
  echo "Error: '$REPO_PATH' is not a directory." >&2
  exit 1
fi
REPO_PATH="$(cd "$REPO_PATH" && pwd)"

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

# --- Detect repo type and resolve root ---
# Use git to detect repo structure (works even if invoked from inside a worktree)
if ! git -C "$REPO_PATH" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Error: $REPO_PATH does not appear to be a git repository." >&2
  exit 1
fi

COMMON_DIR=$(git -C "$REPO_PATH" rev-parse --git-common-dir)
if [[ "$COMMON_DIR" == */.bare || "$COMMON_DIR" == */.bare/* ]]; then
  # Bare+worktree: resolve to the parent of the .bare directory
  REPO_PATH="$(cd "$COMMON_DIR/.." && pwd)"
  IS_BARE_WORKTREE=true
else
  # Standard repo: resolve to the worktree root
  REPO_PATH="$(git -C "$REPO_PATH" rev-parse --show-toplevel)"
  IS_BARE_WORKTREE=false
fi
REPO_NAME=$(basename "$REPO_PATH")

# --- Build file list ---
# Start with global files (use while-read for Bash 3.2 compatibility)
FILE_LIST=()
while IFS= read -r line; do
  [[ -n "$line" ]] && FILE_LIST+=("$line")
done < <(jq -r '.globalFiles[]?' "$CONFIG_FILE")

# Merge repo-specific additional files if configured
ADDITIONAL=$(jq -r --arg repo "$REPO_NAME" '.repoOverrides?[$repo]?.additionalFiles? // [] | .[]' "$CONFIG_FILE")
if [[ -n "$ADDITIONAL" ]]; then
  while IFS= read -r f; do
    FILE_LIST+=("$f")
  done <<< "$ADDITIONAL"
fi

# Deduplicate (use while-read for Bash 3.2 compatibility)
UNIQUE_FILES=()
while IFS= read -r line; do
  [[ -n "$line" ]] && UNIQUE_FILES+=("$line")
done < <(printf '%s\n' "${FILE_LIST[@]}" | sort -u)
FILE_LIST=("${UNIQUE_FILES[@]}")

# --- Backup function ---
backup_file() {
  local src="$1"
  local dest="$2"

  if [[ "$DRY_RUN" == "true" ]]; then
    echo "  [dry-run] would copy: $src -> $dest"
    return 0
  fi

  if rclone copy "$src" "$dest/" 2>&1; then
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
  # Use --porcelain for reliable parsing (handles spaces in paths)
  while IFS= read -r line; do
    if [[ "$line" == "worktree "* ]]; then
      WORKTREE_PATH="${line#worktree }"
    elif [[ "$line" == "bare" ]]; then
      # This is the bare repo entry — skip it
      WORKTREE_PATH=""
    elif [[ -z "$line" && -n "$WORKTREE_PATH" ]]; then
      # Blank line marks end of a worktree block — process it
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
      WORKTREE_PATH=""
    fi
  done < <(git -C "$REPO_PATH" worktree list --porcelain; echo "")
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
