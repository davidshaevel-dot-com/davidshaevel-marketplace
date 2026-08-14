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

# Warnings raised during config resolution. Merged into the run's warning list later, so
# a config problem degrades the STATUS token instead of scrolling past on stderr.
CONFIG_WARNINGS=()

# An explicit override is a statement of intent. If it is set and does not resolve, that
# is a typo, not a reason to quietly use something else — failing open here would also
# mean a mistyped test fixture path silently runs the suite against the real config and
# the real Drive remote.
if [[ -n "${BACKUP_CONFIG_FILE:-}" && ! -f "${BACKUP_CONFIG_FILE:-}" ]]; then
  echo "Error: \$BACKUP_CONFIG_FILE is set but does not name a readable file:" >&2
  echo "  $BACKUP_CONFIG_FILE" >&2
  echo "Unset it to fall back to $CANONICAL_CONFIG." >&2
  exit 1
fi

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

# Using the legacy path IS the TT-452 condition. It must not report OK: this run works,
# and the next upgrade deletes the config out from under it. That is precisely what
# PARTIAL means here, so it goes in the warning list rather than scrolling past on stderr.
if [[ "$CONFIG_FILE" == "$LEGACY_CONFIG" ]]; then
  CONFIG_WARNINGS+=("config lives inside the plugin at $CONFIG_FILE — the next upgrade will delete it (TT-452); move it to $CANONICAL_CONFIG")
fi

# A plugin-local config that exists but LOST is invisible otherwise, and the TT-452
# migration deliberately leaves stale copies on disk until the upgrade is verified.
# Naming it is what drives the cleanup — and it is not auto-migration.
#
# Scoped to the legacy path only. A canonical config shadowed by an explicit
# $BACKUP_CONFIG_FILE is the override working as designed, and warning about it would
# fire on every deliberate override — including every test run.
if [[ -f "$LEGACY_CONFIG" && "$LEGACY_CONFIG" != "$CONFIG_FILE" ]]; then
  CONFIG_WARNINGS+=("a stale plugin-local config exists and was IGNORED: $LEGACY_CONFIG — delete it (TT-452)")
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

# --- Validate config shape ---
#
# jq's `?` operator swallows a missing or wrong-typed key, so `.globalFiles[]?` yields
# nothing for `globalfiles` (wrong case), for a string where an array was meant, and for
# a key that is simply absent. The run then backs up zero files and reports a clean OK —
# a silent success, which is the single failure mode this script exists to eliminate.
# Check the shape explicitly and fail closed.
if ! jq -e . "$CONFIG_FILE" >/dev/null 2>&1; then
  echo "Error: $CONFIG_FILE is not valid JSON." >&2
  echo "Check it with: jq . $CONFIG_FILE" >&2
  exit 1
fi

# One jq program validates the WHOLE shape, including inside repoOverrides. Checking only
# the two top-level keys left `repoOverrides.<repo>.additionalfiles` (wrong case) invisible
# — the entry was silently dropped and the run reported a clean OK, which is the very
# failure this release exists to eliminate, reproduced through the release itself.
#
# It also runs inside `if !` so a jq RUNTIME error cannot abort the script through set -e.
# Unguarded, a top-level array (`has()` on a non-object) or a wrong-typed additionalFiles
# killed the run with a raw jq message and exit 5 — outside the documented 0/1/2 contract,
# so the skill docs told the agent to report a config typo as a tool crash.
CONFIG_ERRORS=$(jq -r '
  def kind: if type == "null" then "absent" else type end;
  [
    (if type != "object" then "the config must be a JSON object, found \(type)" else empty end),

    (if type == "object" then
      (if has("globalFiles") and (.globalFiles | type) != "array"
         then "globalFiles must be an array, found \(.globalFiles | type)" else empty end),
      (if (.globalFiles? // []) | type == "array" then
         (.globalFiles[]? | select(type != "string")
            | "globalFiles contains a \(type) — every entry must be a string")
       else empty end),

      (if has("repoOverrides") and (.repoOverrides | type) != "object"
         then "repoOverrides must be an object, found \(.repoOverrides | type)" else empty end),
      (if (.repoOverrides? // {}) | type == "object" then
         ((.repoOverrides // {}) | to_entries[]
            | . as $e
            | (if ($e.value | type) != "object"
                 then "repoOverrides.\($e.key) must be an object, found \($e.value | type)"
                 else empty end),
              (if ($e.value | type) == "object" then
                 ($e.value | keys[] | select(. != "additionalFiles")
                    | "repoOverrides.\($e.key).\(.) is not a recognised key — did you mean additionalFiles?"),
                 (if ($e.value | has("additionalFiles")) and (($e.value.additionalFiles | type) != "array")
                    then "repoOverrides.\($e.key).additionalFiles must be an array, found \($e.value.additionalFiles | type)"
                    else empty end),
                 (if (($e.value.additionalFiles? // []) | type) == "array" then
                    ($e.value.additionalFiles[]? | select(type != "string")
                       | "repoOverrides.\($e.key).additionalFiles contains a \(type) — every entry must be a string")
                  else empty end)
               else empty end))
       else empty end)
     else empty end)
  ] | .[]
' "$CONFIG_FILE" 2>&1) || {
  echo "Error: could not validate $CONFIG_FILE" >&2
  echo "$CONFIG_ERRORS" >&2
  exit 1
}

if [[ -n "$CONFIG_ERRORS" ]]; then
  echo "Error: $CONFIG_FILE is not shaped correctly:" >&2
  while IFS= read -r e; do
    [[ -n "$e" ]] && echo "  - $e" >&2
  done <<< "$CONFIG_ERRORS"
  exit 1
fi

# A key that is present-but-misspelled looks identical to one that is absent, so warn on
# anything unrecognised rather than ignoring it. (Nested unknown keys are hard errors
# above; top-level ones are only warnings because a future version may add keys.)
UNKNOWN_KEYS=$(jq -r 'keys[] | select(. != "backupDir" and . != "globalFiles" and . != "repoOverrides")' "$CONFIG_FILE" 2>/dev/null || true)
if [[ -n "$UNKNOWN_KEYS" ]]; then
  while IFS= read -r k; do
    [[ -n "$k" ]] && CONFIG_WARNINGS+=("unrecognised key '$k' in $CONFIG_FILE — misspelled? it is being ignored")
  done <<< "$UNKNOWN_KEYS"
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

# Repo-specific entries are tracked separately. The never-found roll-up applies only to
# THESE, because the two kinds of entry mean different things:
#   globalFiles      — speculative. "back this up wherever it exists." A repo with no
#                      CLAUDE.local.md is completely normal, and warning about it would
#                      fire forever on every session end until the operator learns to
#                      ignore warnings — destroying the signal this release adds.
#   additionalFiles  — written FOR this repo by name. Never resolving is definitionally
#                      a config error: a typo, or a path that moved.
REPO_SPECIFIC=""

# Merge repo-specific additional files if configured
ADDITIONAL=$(jq -r --arg repo "$REPO_NAME" '.repoOverrides?[$repo]?.additionalFiles? // [] | .[]' "$CONFIG_FILE")
if [[ -n "$ADDITIONAL" ]]; then
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    FILE_LIST+=("$f")
    REPO_SPECIFIC="$REPO_SPECIFIC$f
"
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

# path_exists PATH → 0 if anything is there, INCLUDING a dangling symlink
#
# `[[ -e ]]` follows the link and is FALSE for a broken symlink, so a path that plainly
# exists (lstat succeeds, ls shows it) would be reported as "no such path" — the very
# verdict-without-a-basis this release exists to stop, just relocated. `-L` catches the
# link itself.
path_exists() {
  [[ -e "$1" || -L "$1" ]]
}

# path_kind PATH → a human reason why a present path was not backed up
#
# "Unsupported" on its own would repeat the sin the v1.5.1 relabelling fixed: a verdict
# without its basis. Name what the thing actually is.
#
# Directories never reach here — scan_tree backs them up (TT-372). Order still matters:
# a dangling symlink must be identified before the intact -L branch, and an intact
# symlink must not be called "broken" merely because its target is not a regular file.
path_kind() {
  if [[ -L "$1" && ! -e "$1" ]]; then
    echo "broken symlink — its target does not exist"
  elif [[ -L "$1" ]]; then
    echo "symlink to something that is not a regular file"
  else
    echo "not a regular file (socket, fifo, or device)"
  fi
}

# --- Backup function ---
#
# The destination carries the entry's RELATIVE PATH (TT-372). It used to carry only the
# basename — for files, nothing at all — so jobs/co-a/.work and jobs/co-b/.work both
# landed at .work/ and the second copy silently destroyed the first. Directories nest
# under the full relpath (rclone copies a directory's CONTENTS into the destination);
# files nest under the relpath's parent, which for a top-level entry is "." — no extra
# nesting, so existing top-level destinations are unchanged.
backup_file() {
  local src="$1"
  local dest="$2"
  local relpath="${3%/}"   # config entries may carry a trailing slash ("reports/")
  local rclone_dest

  if [[ -d "$src" ]]; then
    rclone_dest="$dest/$relpath/"
  else
    local relparent
    relparent="$(dirname "$relpath")"
    if [[ "$relparent" == "." ]]; then
      rclone_dest="$dest/"
    else
      rclone_dest="$dest/$relparent/"
    fi
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    echo "  [dry-run] would copy: $src -> $rclone_dest"
    return 0
  fi

  if rclone copy "$src" "$rclone_dest"; then
    echo "  [ok] $src -> $rclone_dest"
  else
    echo "  [FAILED] $src -> $rclone_dest" >&2
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

# scan_tree ROOT DEST_DIR — classify and back up every configured entry under ROOT
#
# ONE implementation, called once per worktree and once for a standard repo. It used to
# be two verbatim copies differing only in the root variable, which meant every fix had
# to be applied twice and a fix applied once made a standard repo and a bare+worktree
# repo classify the same file differently. Divergence like that is the mechanism by which
# `reports/` stayed mislabelled for four months.
scan_tree() {
  local root="$1" dest="$2" file src
  [[ ${#FILE_LIST[@]} -gt 0 ]] || return 0
  for file in "${FILE_LIST[@]}"; do
    src="$root/$file"
    # Backable = regular file or directory, through symlinks (-f and -d dereference).
    # This is TT-302's `-e` restricted to the types rclone can actually copy: a fifo,
    # socket, or broken symlink still gets classified below instead of handed to rclone
    # to fail on.
    if [[ -f "$src" || -d "$src" ]]; then
      FOUND_RELPATHS="$FOUND_RELPATHS$file
"
      if backup_file "$src" "$dest" "$file"; then
        BACKED_UP_FILES+=("$src")
      else
        FAILED_FILES+=("$src")
      fi
    elif path_exists "$src"; then
      UNSUPPORTED_FILES+=("$src ($(path_kind "$src"))")
    else
      MISSING_FILES+=("$src")
    fi
  done
}

# --- Execute backup ---
if [[ "$IS_BARE_WORKTREE" == "true" ]]; then
  # Enumerate first and check the status. Inside a process substitution the failure is
  # invisible: git exits 128, the loop body never runs, and the summary reads like an
  # ordinary empty result — "your layout defeated the enumerator" is then
  # indistinguishable from "nothing you configured exists here".
  if ! WORKTREE_LIST=$(git -C "$REPO_PATH" worktree list --porcelain 2>&1); then
    echo "Error: could not enumerate worktrees in $REPO_PATH" >&2
    echo "$WORKTREE_LIST" >&2
    exit 1
  fi

  WORKTREE_PATH=""
  while IFS= read -r line; do
    if [[ "$line" == "worktree "* ]]; then
      WORKTREE_PATH="${line#worktree }"
    elif [[ "$line" == "bare" ]]; then
      # This is the bare repo entry — skip it
      WORKTREE_PATH=""
    elif [[ -z "$line" && -n "$WORKTREE_PATH" ]]; then
      # Blank line marks end of a worktree block — process it
      WORKTREE_NAME=$(basename "$WORKTREE_PATH")
      scan_tree "$WORKTREE_PATH" "$BACKUP_DIR/$REPO_NAME/$WORKTREE_NAME"
      WORKTREE_PATH=""
    fi
  done <<< "$WORKTREE_LIST

"
else
  # Standard repo: back up files from repo root
  scan_tree "$REPO_PATH" "$BACKUP_DIR/$REPO_NAME"
fi

# --- Never-found roll-up ---
#
# The detector that would have caught this in April. A relabelled "Unsupported" line is
# still just a line in a wall of output; what makes a stale entry undeniable is noticing
# that a configured path resolved to nothing backable in ANY worktree of the repo it was
# configured for. That is never a normal state — it is a typo, a moved path, or an
# unsupported type.
# Scoped to repo-specific entries ONLY. A globalFile that resolves nowhere in this repo
# is routine (plenty of repos have no CLAUDE.local.md); warning about it would fire at
# every session end forever and train the reader to ignore warnings, which is the exact
# alarm-fatigue outcome this release exists to prevent.
WARNINGS=()
if [[ ${#CONFIG_WARNINGS[@]} -gt 0 ]]; then
  WARNINGS=("${CONFIG_WARNINGS[@]}")
fi

if [[ -n "$REPO_SPECIFIC" ]]; then
  while IFS= read -r file; do
    [[ -n "$file" ]] || continue
    # Here-string, not `printf | grep`. Under pipefail, grep -q exits on the first
    # match while printf is still writing; once the string exceeds the ~64KB pipe
    # buffer printf dies with EPIPE and the pipeline reports 141 EVEN ON A MATCH,
    # inverting this test and reporting successfully-backed-up entries as never found.
    # Reproduced on bash 3.2 with a 259KB string whose first line matched.
    if ! grep -Fxq -- "$file" <<< "$FOUND_RELPATHS"; then
      WARNINGS+=("configured entry for '$REPO_NAME' never backed up from any worktree: $file")
    fi
  done <<< "$REPO_SPECIFIC"
fi

# A config that resolves to no entries at all backs up nothing while looking healthy.
# That is a silent success, and it is the failure this whole script is a reaction to.
if [[ ${#FILE_LIST[@]} -eq 0 ]]; then
  WARNINGS+=("config resolved ZERO entries for '$REPO_NAME' — nothing was backed up; check globalFiles and repoOverrides in $CONFIG_FILE")
fi

# Every globalFile missing everywhere is not proof of a bad config, but it is worth one
# line: it usually means the repo is not what the operator thought it was.
# UNSUPPORTED_FILES must be in this condition. Without it, a repo whose entries all
# resolved but are unsupported — exactly the laptop-maintenance/reports shape — is told
# "is this the repo you meant?", which asserts a conclusion the check cannot support and
# points at the wrong diagnosis. That is the same defect the MISSING/UNSUPPORTED split
# was introduced to fix.
if [[ ${#FILE_LIST[@]} -gt 0 && ${#BACKED_UP_FILES[@]} -eq 0 \
      && ${#FAILED_FILES[@]} -eq 0 && ${#UNSUPPORTED_FILES[@]} -eq 0 ]]; then
  WARNINGS+=("no configured entry resolved anywhere in '$REPO_NAME' — is this the repo you meant?")
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

# A dry run must never read as a successful backup. README makes --dry-run the standard
# post-upgrade check, so this is the output seen most often, and "OK / Backed up (2)"
# would assert bytes reached Drive when nothing was written at all.
BACKED_LABEL="Backed up"
if [[ "$DRY_RUN" == "true" ]]; then
  STATUS="DRY-RUN($STATUS)"
  BACKED_LABEL="Would back up"
fi

echo ""
echo "backup-local-config complete: $STATUS  backed_up=${#BACKED_UP_FILES[@]} missing=${#MISSING_FILES[@]} unsupported=${#UNSUPPORTED_FILES[@]} failed=${#FAILED_FILES[@]} warnings=${#WARNINGS[@]}"
echo ""
echo "  $BACKED_LABEL (${#BACKED_UP_FILES[@]}):"
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
