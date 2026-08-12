#!/usr/bin/env bash
# test-backup-local-config.sh — end-to-end tests for backup-local-config.sh
#
# Run under BOTH interpreters. Bash 5 hides the empty-array case that bash 3.2 fails on:
#   /bin/bash            scripts/test-backup-local-config.sh   # 3.2 on stock macOS
#   /usr/local/bin/bash  scripts/test-backup-local-config.sh   # 5.x from Homebrew
#
# These are REAL copies, not dry-run assertions. `RCLONE_CONFIG_TESTLOCAL_TYPE=local`
# defines an rclone remote via environment variable, so `backupDir: "testlocal:/tmp/..."`
# satisfies the script's remote check AND writes into a temp directory we can inspect.
# No network, no Google Drive, nothing outside $TMP is touched.
#
# That distinction is the whole point: a dry-run assertion only tests the destination
# string the script builds. The TT-372 bug lived in what rclone actually DID with that
# string — `rclone copy dir/ dest/` flattens. Only a real copy catches it.

# Deliberately NOT `set -e`: every case must run so the summary is complete.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/backup-local-config.sh"

if [[ ! -x "$SCRIPT" ]]; then
  echo "Error: $SCRIPT not found or not executable" >&2
  exit 1
fi
if ! command -v rclone >/dev/null 2>&1; then
  echo "Error: rclone is required to run these tests" >&2
  exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "Error: jq is required to run these tests" >&2
  exit 1
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export RCLONE_CONFIG_TESTLOCAL_TYPE=local

PASS=0
FAIL=0
CURRENT_CASE=""

# --- assertions ---------------------------------------------------------------

start_case() { CURRENT_CASE="$1"; echo ""; echo "== $CURRENT_CASE"; }

ok()   { PASS=$((PASS + 1)); echo "   ok   $1"; }
bad()  { FAIL=$((FAIL + 1)); echo "   FAIL $1"; }

assert_file() {  # $1 path under drive root, $2 label
  if [[ -f "$DRIVE/$1" ]]; then ok "$2"; else bad "$2 (missing: $1)"; fi
}

assert_absent() {
  if [[ -e "$DRIVE/$1" ]]; then bad "$2 (unexpectedly present: $1)"; else ok "$2"; fi
}

assert_content() {  # $1 path, $2 expected content, $3 label
  local actual
  actual="$(cat "$DRIVE/$1" 2>/dev/null || true)"
  if [[ "$actual" == "$2" ]]; then ok "$3"; else bad "$3 (got '$actual', want '$2')"; fi
}

assert_exit() {  # $1 actual, $2 expected, $3 label
  if [[ "$1" == "$2" ]]; then ok "$3 (exit $1)"; else bad "$3 (exit $1, want $2)"; fi
}

assert_grep() {  # $1 file, $2 pattern, $3 label
  if grep -q -- "$2" "$1"; then ok "$3"; else bad "$3 (no match for '$2')"; fi
}

assert_not_grep() {
  if grep -q -- "$2" "$1"; then bad "$3 (unexpected match for '$2')"; else ok "$3"; fi
}

# documents_bug — pins CURRENT, KNOWN-WRONG behaviour so the release that fixes it has
# to change this line. The assertion passing does not mean the behaviour is good; it
# means the bug is still exactly where we think it is. When TT-372 lands, every
# documents_bug call below flips to a real assertion, and that diff IS the record of
# what the behaviour change was.
documents_bug() {  # $1 condition-already-evaluated (0/1), $2 issue, $3 label
  if [[ "$1" -eq 0 ]]; then
    PASS=$((PASS + 1)); echo "   ok   [documents $2] $3"
  else
    FAIL=$((FAIL + 1)); echo "   FAIL [documents $2] $3 — behaviour changed, update this test"
  fi
}

# --- fixtures -----------------------------------------------------------------

DRIVE=""
OUT=""

reset_drive() {  # fresh drive root + output capture per case
  DRIVE="$TMP/drive/$1"
  rm -rf "$DRIVE"
  mkdir -p "$DRIVE"
  OUT="$TMP/out-$1.txt"
}

write_config() {  # $1 config path, $2 backupDir, $3 globals json, $4 overrides json
  cat > "$1" <<EOF
{
  "backupDir": "$2",
  "globalFiles": $3,
  "repoOverrides": $4
}
EOF
}

mk_standard_repo() {  # $1 path
  mkdir -p "$1"
  git -C "$1" init -q
  git -C "$1" commit -q --allow-empty -m init
}

mk_bare_worktree_repo() {  # $1 root; creates .bare + main + feature worktrees
  local root="$1"
  mkdir -p "$root"
  git -C "$root" init -q --bare .bare
  git -C "$root" clone -q .bare seed 2>/dev/null
  git -C "$root/seed" commit -q --allow-empty -m init
  git -C "$root/seed" branch -M main
  git -C "$root/seed" push -q origin main
  rm -rf "$root/seed"
  git -C "$root/.bare" worktree add -q "$root/main" main
  git -C "$root/.bare" worktree add -q -b feature "$root/feature" main
  # The root itself must be a git dir pointing at .bare, or `git -C <root>` fails and
  # the script cannot detect the layout. This is what the real repos look like.
  echo "gitdir: ./.bare" > "$root/.git"
}

# Invoke the script under THE SAME interpreter running this harness.
#
# Calling "$SCRIPT" directly would honour its `#!/usr/bin/env bash` shebang, which
# resolves to Homebrew bash 5 — so running this file under /bin/bash would test the
# harness on 3.2 while the script under test still ran on 5, and every 3.2-specific
# assertion would be silently vacuous. $BASH is the absolute path of the current shell.
run_backup() {  # $1 config, $2 repo path ; captures output, echoes exit code
  local rc
  BACKUP_CONFIG_FILE="$1" "$BASH" "$SCRIPT" "$2" > "$OUT" 2>&1
  rc=$?
  echo "$rc"
}

# ==============================================================================
# Case 1-3, 12: file entries — top-level, nested, same-basename, spaces
# ==============================================================================
start_case "file entries: top-level, nested, same-basename collision, spaces"
reset_drive files
R="$TMP/repo-files"
mk_standard_repo "$R"
echo "top" > "$R/SESSION_LOG.md"
mkdir -p "$R/a/x" "$R/b/y" "$R/my docs"
echo "AAA" > "$R/a/x/swap.py"
echo "BBB" > "$R/b/y/swap.py"
echo "spaced" > "$R/my docs/notes.md"
write_config "$TMP/c-files.json" "testlocal:$DRIVE" \
  '["SESSION_LOG.md"]' \
  '{"repo-files":{"additionalFiles":["a/x/swap.py","b/y/swap.py","my docs/notes.md"]}}'
RC=$(run_backup "$TMP/c-files.json" "$R")

assert_file "repo-files/SESSION_LOG.md" "top-level file keeps its place (no extra nesting)"
assert_exit "$RC" 0 "all entries resolved"

# TT-372 is NOT fixed in this release. backup_file has no relative-path component, so
# every file lands at the destination root: nested paths lose their parent, and two
# entries sharing a basename map to the same destination — the second silently
# overwrites the first. Pinned here so the fix has to change these three lines.
[[ -f "$DRIVE/repo-files/swap.py" && ! -e "$DRIVE/repo-files/a/x/swap.py" ]]; documents_bug $? "TT-372" \
  "nested file flattens to the destination root"
[[ "$(cat "$DRIVE/repo-files/swap.py" 2>/dev/null)" == "BBB" ]]; documents_bug $? "TT-372" \
  "same-basename file A is destroyed by B (last write wins)"
[[ -f "$DRIVE/repo-files/notes.md" ]]; documents_bug $? "TT-372" \
  "path with a space flattens but is not corrupted"

# ==============================================================================
# Case 4-7: directory entries — top-level, trailing slash, nested, same-basename
# ==============================================================================
start_case "directory entries: nesting, trailing slash, same-basename"
reset_drive dirs
R="$TMP/repo-dirs"
mk_standard_repo "$R"
echo "log" > "$R/SESSION_LOG.md"
mkdir -p "$R/reports" "$R/jobs/co-a/.work" "$R/jobs/co-b/.work"
echo "r1" > "$R/reports/disk-audit-2026-08-11.md"
echo "wa" > "$R/jobs/co-a/.work/notes.md"
echo "wb" > "$R/jobs/co-b/.work/notes.md"
write_config "$TMP/c-dirs.json" "testlocal:$DRIVE" \
  '["SESSION_LOG.md"]' \
  '{"repo-dirs":{"additionalFiles":["reports/","jobs/co-a/.work","jobs/co-b/.work"]}}'
RC=$(run_backup "$TMP/c-dirs.json" "$R")

# Directory support is TT-302/TT-372, deliberately not in this release. What this
# release guarantees is that a directory entry is now IMPOSSIBLE TO MISS: it is never
# copied, never mislabelled "not found", and it forces a non-zero exit.
assert_grep "$OUT" "Unsupported — present but NOT backed up" "directory lands in the Unsupported bucket"
assert_grep "$OUT" "directory entries are not supported yet" "the reason names the actual type"
assert_grep "$OUT" "TT-372" "the reason points at the tracking issue"
assert_not_grep "$OUT" "Missing — no such path (3)" "an existing directory is NOT called missing"
assert_grep "$OUT" "never backed up from any worktree: reports/" "never-found roll-up catches it"
assert_absent "repo-dirs/disk-audit-2026-08-11.md" "no directory contents leaked into the root"
assert_absent "repo-dirs/reports" "directory not copied at all"
assert_exit "$RC" 2 "directory entry forces PARTIAL, not a silent success"

# ==============================================================================
# Case 8-10: missing vs unsupported vs never-found
# ==============================================================================
start_case "classification: missing, unsupported, never-found roll-up"
reset_drive classify
R="$TMP/repo-classify"
mk_standard_repo "$R"
echo "log" > "$R/SESSION_LOG.md"
ln -s "$R/does-not-exist" "$R/dangling.md"
write_config "$TMP/c-classify.json" "testlocal:$DRIVE" \
  '["SESSION_LOG.md"]' \
  '{"repo-classify":{"additionalFiles":["nope.md","dangling.md"]}}'
RC=$(run_backup "$TMP/c-classify.json" "$R")

assert_grep "$OUT" "Missing — no such path" "missing bucket present"
assert_grep "$OUT" "nope.md" "absent entry classified"
assert_grep "$OUT" "Unsupported — present but NOT backed up" "unsupported bucket present"
assert_grep "$OUT" "dangling.md" "broken symlink reported"
assert_not_grep "$OUT" "Skipped — not found" "the old misleading label is gone"
assert_grep "$OUT" "never backed up from any worktree" "never-found roll-up fired"
assert_grep "$OUT" "PARTIAL" "status token is PARTIAL"
assert_exit "$RC" 2 "stale config exits 2, not 0"

# ==============================================================================
# Case 11: bare+worktree — per-worktree destinations, no false warning
# ==============================================================================
start_case "bare+worktree: per-worktree destinations"
reset_drive bare
R="$TMP/repo-bare"
mk_bare_worktree_repo "$R"
echo "m" > "$R/main/SESSION_LOG.md"
echo "f" > "$R/feature/SESSION_LOG.md"
echo "only-main" > "$R/main/CLAUDE.local.md"
write_config "$TMP/c-bare.json" "testlocal:$DRIVE" \
  '["SESSION_LOG.md","CLAUDE.local.md"]' \
  '{}'
RC=$(run_backup "$TMP/c-bare.json" "$R")

assert_file "repo-bare/main/SESSION_LOG.md" "main worktree file"
assert_file "repo-bare/feature/SESSION_LOG.md" "feature worktree file"
assert_content "repo-bare/feature/SESSION_LOG.md" "f" "worktrees not cross-contaminated"
assert_grep "$OUT" "feature/CLAUDE.local.md" "absent-in-one-worktree reported as Missing"
assert_not_grep "$OUT" "never backed up from any worktree: CLAUDE.local.md" \
  "entry found in ONE worktree raises no warning"
assert_exit "$RC" 0 "present-in-one-worktree is not a stale config"

# ==============================================================================
# Case 13-15: config resolution
# ==============================================================================
start_case "config resolution: override, CLAUDE_CONFIG_DIR, none"
reset_drive config
R="$TMP/repo-config"
mk_standard_repo "$R"
echo "log" > "$R/SESSION_LOG.md"

PROFILE="$TMP/profile"; mkdir -p "$PROFILE/config"
write_config "$PROFILE/config/backup-config.json" "testlocal:$DRIVE" '["SESSION_LOG.md"]' '{}'
write_config "$TMP/c-override.json" "testlocal:$DRIVE" '["SESSION_LOG.md"]' '{}'

CLAUDE_CONFIG_DIR="$PROFILE" BACKUP_CONFIG_FILE="$TMP/c-override.json" \
  "$BASH" "$SCRIPT" "$R" > "$OUT" 2>&1
assert_grep "$OUT" "Using config: $TMP/c-override.json" "BACKUP_CONFIG_FILE wins over CLAUDE_CONFIG_DIR"

CLAUDE_CONFIG_DIR="$PROFILE" "$BASH" "$SCRIPT" "$R" > "$OUT" 2>&1
assert_grep "$OUT" "Using config: $PROFILE/config/backup-config.json" "CLAUDE_CONFIG_DIR profile honoured"

EMPTY="$TMP/empty-home"; mkdir -p "$EMPTY"
ISOLATED="$TMP/isolated"; mkdir -p "$ISOLATED/scripts" "$ISOLATED/config"
cp "$SCRIPT" "$ISOLATED/scripts/"
CLAUDE_CONFIG_DIR="$EMPTY" "$BASH" "$ISOLATED/scripts/backup-local-config.sh" "$R" > "$OUT" 2>&1
RC=$?
assert_exit "$RC" 1 "no config anywhere fails closed"
assert_grep "$OUT" 'BACKUP_CONFIG_FILE' "error names the env override"
assert_grep "$OUT" "$EMPTY/config/backup-config.json" "error names the canonical path"
assert_grep "$OUT" "$ISOLATED/config/backup-config.json" "error names the legacy path"

# ==============================================================================
# Case 16: empty globalFiles — the bash 3.2 empty-array trap
# ==============================================================================
start_case "empty config: no entries at all (bash 3.2 empty-array guard)"
reset_drive empty
R="$TMP/repo-empty"
mk_standard_repo "$R"
write_config "$TMP/c-empty.json" "testlocal:$DRIVE" '[]' '{}'
RC=$(run_backup "$TMP/c-empty.json" "$R")

assert_not_grep "$OUT" "unbound variable" "no unbound-variable error on empty array"
assert_grep "$OUT" "backup-local-config complete" "script reached its summary"
assert_exit "$RC" 0 "empty config is a clean no-op"

# --- summary ------------------------------------------------------------------
echo ""
echo "=============================================="
echo "  bash $BASH_VERSION"
echo "  passed: $PASS   failed: $FAIL"
echo "=============================================="
[[ "$FAIL" -eq 0 ]] || exit 1
