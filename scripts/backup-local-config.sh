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
#
# The config must NOT live inside the version-pinned plugin cache. It used to, and
# every plugin upgrade cloned a fresh versioned directory without it, so backups
# failed outright until someone re-created a symlink by hand. That is how the
# laptop-maintenance `reports/` entry was lost in April 2026 and stayed lost for four
# months (TT-452).
#
# Search order — first hit wins:
#   1. $BACKUP_CONFIG_FILE   explicit override; also the seam the test harness uses
#   2. $CLAUDE_CONFIG_DIR (or ~/.claude) /config/backup-config.json   <- canonical
#   3. $SCRIPT_DIR/../config/backup-config.json                       <- legacy
#
# Honouring CLAUDE_CONFIG_DIR gives per-profile configs for free.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
CANONICAL_CONFIG="$CLAUDE_DIR/config/backup-config.json"
# Normalised, so the path printed in warnings reads as a real location rather than
# ".../scripts/../config/...".
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LEGACY_CONFIG="$PLUGIN_ROOT/config/backup-config.json"

CONFIG_CANDIDATES=(
  "${BACKUP_CONFIG_FILE:-}"
  "$CANONICAL_CONFIG"
  "$LEGACY_CONFIG"
)

CONFIG_FILE=""
for candidate in "${CONFIG_CANDIDATES[@]}"; do
  if [[ -n "$candidate" && -f "$candidate" ]]; then
    CONFIG_FILE="$candidate"
    break
  fi
done

# Fail closed. Do NOT auto-create from the .example: that would install a config whose
# repoOverrides name "my-project", and the run would then report a clean "Failed (0)"
# while backing up nothing — the exact silent-success failure this script exists to
# stop. Do NOT auto-migrate the legacy file either: $SCRIPT_DIR resolves differently
# per install path, so a migration fired from the marketplaces/ clone would promote a
# stale config over the canonical one and silently drop entries.
if [[ -z "$CONFIG_FILE" ]]; then
  echo "Error: no backup config found. Searched, in order:" >&2
  if [[ -n "${BACKUP_CONFIG_FILE:-}" ]]; then
    echo "  1. \$BACKUP_CONFIG_FILE -> $BACKUP_CONFIG_FILE" >&2
  else
    echo "  1. \$BACKUP_CONFIG_FILE (unset)" >&2
  fi
  echo "  2. $CANONICAL_CONFIG" >&2
  echo "  3. $LEGACY_CONFIG" >&2
  echo "" >&2
  echo "Create the canonical config:" >&2
  echo "  mkdir -p $CLAUDE_DIR/config" >&2
  echo "  cp $PLUGIN_ROOT/config/backup-config.json.example $CANONICAL_CONFIG" >&2
  echo "  chmod 600 $CANONICAL_CONFIG" >&2
  echo "  \$EDITOR $CANONICAL_CONFIG" >&2
  exit 1
fi

# Printed on every run so the upgrade procedure is self-verifying: if this line does
# not name the canonical path, the config is somewhere an upgrade can destroy.
echo "Using config: $CONFIG_FILE"

if [[ "$CONFIG_FILE" == "$LEGACY_CONFIG" ]]; then
  echo "WARNING: using the plugin-local config at $CONFIG_FILE." >&2
  echo "WARNING: this path does not survive a plugin upgrade (TT-452)." >&2
  echo "WARNING: move it to $CANONICAL_CONFIG — see README 'Backup Local Config'." >&2
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
#
# The emptiness guards are not defensive habit. Expanding "${arr[@]}" on an EMPTY array
# is a fatal error under `set -u` on bash < 4.4, and /bin/bash on stock macOS is 3.2:
#   $ /bin/bash -c 'set -euo pipefail; F=(); for f in "${F[@]}"; do :; done'
#   /bin/bash: F[@]: unbound variable
# It only fires when globalFiles is empty, which is why it has never been hit in
# production — and why the test harness exercises exactly that case.
UNIQUE_FILES=()
if [[ ${#FILE_LIST[@]} -gt 0 ]]; then
  while IFS= read -r line; do
    [[ -n "$line" ]] && UNIQUE_FILES+=("$line")
  done < <(printf '%s\n' "${FILE_LIST[@]}" | sort -u)
fi
FILE_LIST=()
if [[ ${#UNIQUE_FILES[@]} -gt 0 ]]; then
  FILE_LIST=("${UNIQUE_FILES[@]}")
fi

# path_kind PATH → a human reason why a present path was not backed up
#
# "Unsupported" on its own would repeat the sin this release is fixing: a verdict
# without its basis. Name what the thing actually is.
path_kind() {
  if [[ -d "$1" ]]; then
    echo "directory — directory entries are not supported yet, see TT-372"
  elif [[ -L "$1" ]]; then
    echo "broken symlink"
  else
    echo "not a regular file"
  fi
}

# --- Backup function ---
#
# NOTE: this still flattens. A directory's contents would land loose in the worktree
# root, and two entries sharing a basename map to the same destination. That is TT-372,
# and it is deliberately NOT fixed in this release — directories are rejected as
# unsupported below, loudly, so the gap is visible before the behaviour changes.
backup_file() {
  local src="$1"
  local dest="$2"

  if [[ "$DRY_RUN" == "true" ]]; then
    echo "  [dry-run] would copy: $src -> $dest"
    return 0
  fi

  if rclone copy "$src" "$dest/"; then
    echo "  [ok] $src -> $dest"
  else
    echo "  [FAILED] $src -> $dest" >&2
    return 1
  fi
}

# --- Tracking arrays ---
#
# MISSING and UNSUPPORTED were a single "SKIPPED — not found" bucket. That label was a
# lie for anything that existed but was not a regular file: a directory entry was
# reported as "not found" while sitting on disk. The report asserted a conclusion its
# check could not support, and the laptop-maintenance `reports/` entry hid behind that
# wording for four months (TT-302).
BACKED_UP_FILES=()
MISSING_FILES=()       # genuinely absent — normal, e.g. no CLAUDE.local.md in a worktree
UNSUPPORTED_FILES=()   # present but neither file nor directory — never normal
FAILED_FILES=()

# Relative paths that resolved to something backable in at least one worktree. Bash 3.2
# has no associative arrays, so this is a newline-delimited string queried with grep.
FOUND_RELPATHS=""

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

      if [[ ${#FILE_LIST[@]} -gt 0 ]]; then
        for file in "${FILE_LIST[@]}"; do
          SRC="$WORKTREE_PATH/$file"
          if [[ -f "$SRC" ]]; then
            FOUND_RELPATHS="$FOUND_RELPATHS$file
"
            if backup_file "$SRC" "$DEST_DIR"; then
              BACKED_UP_FILES+=("$SRC")
            else
              FAILED_FILES+=("$SRC")
            fi
          elif [[ -e "$SRC" ]]; then
            UNSUPPORTED_FILES+=("$SRC ($(path_kind "$SRC"))")
          else
            MISSING_FILES+=("$SRC")
          fi
        done
      fi
      WORKTREE_PATH=""
    fi
  done < <(git -C "$REPO_PATH" worktree list --porcelain; echo "")
else
  # Standard repo: back up files from repo root
  DEST_DIR="$BACKUP_DIR/$REPO_NAME"

  if [[ ${#FILE_LIST[@]} -gt 0 ]]; then
    for file in "${FILE_LIST[@]}"; do
      SRC="$REPO_PATH/$file"
      if [[ -f "$SRC" ]]; then
        FOUND_RELPATHS="$FOUND_RELPATHS$file
"
        if backup_file "$SRC" "$DEST_DIR"; then
          BACKED_UP_FILES+=("$SRC")
        else
          FAILED_FILES+=("$SRC")
        fi
      elif [[ -e "$SRC" ]]; then
        UNSUPPORTED_FILES+=("$SRC ($(path_kind "$SRC"))")
      else
        MISSING_FILES+=("$SRC")
      fi
    done
  fi
fi

# --- Never-found roll-up ---
#
# The detector that would have caught this in April. A relabelled "Unsupported" line is
# still just a line in a wall of output; what makes a stale entry undeniable is noticing
# that a configured path resolved to nothing backable in ANY worktree of the repo it was
# configured for. That is never a normal state — it is a typo, a moved path, or an
# unsupported type.
WARNINGS=()
if [[ ${#FILE_LIST[@]} -gt 0 ]]; then
  for file in "${FILE_LIST[@]}"; do
    if ! printf '%s\n' "$FOUND_RELPATHS" | grep -Fxq -- "$file"; then
      WARNINGS+=("configured entry never backed up from any worktree: $file")
    fi
  done
fi

# --- Summary ---
#
# Leading status token, mirroring backup-dotfiles (TT-379): a health check reads the
# first token, not the body. `Failed (0)` on its own is not evidence of a good backup —
# that is exactly how this failure stayed invisible for four months.
STATUS="OK"
EXIT_CODE=0
if [[ ${#WARNINGS[@]} -gt 0 || ${#UNSUPPORTED_FILES[@]} -gt 0 ]]; then
  STATUS="PARTIAL"
  EXIT_CODE=2
fi
if [[ ${#FAILED_FILES[@]} -gt 0 ]]; then
  STATUS="FAILED"
  EXIT_CODE=1
fi

echo ""
echo "backup-local-config complete: $STATUS  backed_up=${#BACKED_UP_FILES[@]} missing=${#MISSING_FILES[@]} unsupported=${#UNSUPPORTED_FILES[@]} failed=${#FAILED_FILES[@]} warnings=${#WARNINGS[@]}"
echo ""
echo "  Backed up (${#BACKED_UP_FILES[@]}):"
if [[ ${#BACKED_UP_FILES[@]} -gt 0 ]]; then
  for f in "${BACKED_UP_FILES[@]}"; do echo "    $f"; done
else
  echo "    (none)"
fi
echo ""
echo "  Missing — no such path (${#MISSING_FILES[@]}):"
if [[ ${#MISSING_FILES[@]} -gt 0 ]]; then
  for f in "${MISSING_FILES[@]}"; do echo "    $f"; done
else
  echo "    (none)"
fi
echo ""
echo "  Unsupported — present but NOT backed up (${#UNSUPPORTED_FILES[@]}):"
if [[ ${#UNSUPPORTED_FILES[@]} -gt 0 ]]; then
  for f in "${UNSUPPORTED_FILES[@]}"; do echo "    $f"; done
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

if [[ ${#WARNINGS[@]} -gt 0 ]]; then
  echo ""
  for w in "${WARNINGS[@]}"; do echo "  WARNING: $w" >&2; done
fi

# 0 = OK, 2 = PARTIAL (backup ran, configuration is stale), 1 = FAILED (a copy failed).
# PARTIAL is distinct from FAILED so a caller can tell "fix your config" from "the
# transfer broke" — see the skill docs.
exit "$EXIT_CODE"
