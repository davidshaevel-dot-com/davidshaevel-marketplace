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

# Run the script from a HERMETIC plugin root, not from the repo.
#
# The script's legacy config candidate is "$SCRIPT_DIR/../config/backup-config.json".
# Running the repo copy makes that the developer's own gitignored config — so whether a
# case passes depends on what happens to exist on this machine, and every case inherits
# a "stale plugin-local config" warning. Copying into a throwaway plugin root gives the
# legacy candidate a path that does not exist, which is what a clean install looks like.
PLUGIN="$TMP/plugin"
mkdir -p "$PLUGIN/scripts" "$PLUGIN/config"
cp "$SCRIPT" "$PLUGIN/scripts/"
cp "$SCRIPT_DIR/../config/backup-config.json.example" "$PLUGIN/config/" 2>/dev/null || true
SCRIPT="$PLUGIN/scripts/backup-local-config.sh"

# Fixtures must not depend on ambient global git identity, or the suite fails on a clean
# machine or in CI.
export GIT_AUTHOR_NAME="test" GIT_AUTHOR_EMAIL="test@example.invalid"
export GIT_COMMITTER_NAME="test" GIT_COMMITTER_EMAIL="test@example.invalid"

# Isolate from the real user config: without this, HOME's canonical config would win
# whenever a case does not set BACKUP_CONFIG_FILE.
export CLAUDE_CONFIG_DIR="$TMP/claude-home"
mkdir -p "$CLAUDE_CONFIG_DIR/config"

# An ambient BACKUP_CONFIG_FILE — this repo uses direnv, so an exported value is a
# realistic developer state — wins the candidate search for every case that deliberately
# runs WITHOUT an override. Those cases would then exercise the developer's real config,
# whose backupDir is a live gdrive: remote, and this suite would perform real uploads to
# Google Drive while its header promises nothing outside $TMP is touched.
unset BACKUP_CONFIG_FILE

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

# -F: patterns here are literal output text containing (, ), ', / and — . Treating them
# as regexes makes some assertions match more loosely than intended.
assert_grep() {  # $1 file, $2 literal, $3 label
  if grep -qF -- "$2" "$1"; then ok "$3"; else bad "$3 (no match for '$2')"; fi
}

assert_not_grep() {
  if grep -qF -- "$2" "$1"; then bad "$3 (unexpected match for '$2')"; else ok "$3"; fi
}

# assert_in_bucket — the entry must appear under a SPECIFIC summary bucket.
#
# `assert_grep "$OUT" "Unsupported — present but NOT backed up"` proves nothing: that
# header is printed unconditionally, even when the bucket is empty and reads "(none)".
# And grepping for a filename anywhere in the output matches it under ANY bucket, so a
# misclassification passes. Both mistakes were live in this suite and made it report
# green over behaviour it never exercised. Extract the bucket, then match inside it.
assert_in_bucket() {  # $1 bucket header prefix, $2 literal entry, $3 label
  # Bucket headers are "  <Header> (N):" and their entries are indented four spaces.
  local section
  section=$(awk -v h="$1" '
    index($0, h) > 0 && /:$/ { inb = 1; next }
    inb && /^    / { print; next }
    inb { inb = 0 }
  ' "$OUT")
  if printf '%s\n' "$section" | grep -qF -- "$2"; then
    ok "$3"
  else
    bad "$3 ('$2' not under '$1')"
  fi
}

# documents_bug — pins CURRENT, KNOWN-WRONG behaviour so the release that fixes it has
# to change this line. The assertion passing does not mean the behaviour is good; it
# means the bug is still exactly where we think it is. When TT-372 lands, every
# documents_bug call below flips to a real assertion, and that diff IS the record of
# what the behaviour change was.
# $4 records what this assertion BECOMES once the bug is fixed, so the fixing release
# has the target written down rather than having to infer it from a failing test.
documents_bug() {  # $1 condition (0/1), $2 issue, $3 label, $4 becomes
  if [[ "$1" -eq 0 ]]; then
    PASS=$((PASS + 1)); echo "   ok   [documents $2] $3"
  else
    FAIL=$((FAIL + 1))
    echo "   FAIL [documents $2] $3"
    echo "        behaviour changed — this test should now assert: ${4:-<not recorded>}"
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
  "nested file flattens to the destination root" \
  "repo-files/a/x/swap.py exists and repo-files/swap.py does not"
[[ "$(cat "$DRIVE/repo-files/swap.py" 2>/dev/null)" == "BBB" ]]; documents_bug $? "TT-372" \
  "same-basename file A is destroyed by B (last write wins)" \
  "a/x/swap.py contains AAA and b/y/swap.py contains BBB"
[[ -f "$DRIVE/repo-files/notes.md" ]]; documents_bug $? "TT-372" \
  "path with a space flattens but is not corrupted" \
  "repo-files/my docs/notes.md exists"

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
ln -s "./does-not-exist" "$R/dangling.md"     # broken symlink: lstat succeeds, stat fails
mkfifo "$R/afifo"
ln -s "./afifo" "$R/pipe-link"                # INTACT symlink to a non-regular file
mkdir -p "$R/realdir"
ln -s "./realdir" "$R/dirlink"                # intact symlink to a directory
write_config "$TMP/c-classify.json" "testlocal:$DRIVE" \
  '["SESSION_LOG.md"]' \
  '{"repo-classify":{"additionalFiles":["nope.md","dangling.md","pipe-link","dirlink"]}}'
RC=$(run_backup "$TMP/c-classify.json" "$R")

# Bucket-scoped: grepping the whole output would match a filename under ANY bucket, so a
# misclassification would pass. These assertions must be able to fail.
assert_in_bucket "Missing — no such path" "nope.md" "absent entry is Missing"
assert_in_bucket "Unsupported — present but NOT backed up" "dangling.md" \
  "broken symlink is Unsupported, NOT 'no such path'"
assert_in_bucket "Unsupported — present but NOT backed up" "pipe-link" \
  "intact symlink to a fifo is Unsupported"
assert_in_bucket "Unsupported — present but NOT backed up" "dirlink" \
  "symlink to a directory is Unsupported"

# The REASON must match the actual type — a wrong reason is a verdict without a basis,
# which is the whole defect class this release addresses.
assert_grep "$OUT" "dangling.md (broken symlink — its target does not exist)" \
  "broken symlink's reason is accurate"
assert_grep "$OUT" "pipe-link (symlink to something that is not a regular file)" \
  "intact symlink is NOT called broken"
assert_grep "$OUT" "dirlink (directory — directory entries are not supported yet" \
  "symlink-to-directory reads as a directory"

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
# NOT exit 0. A config resolving zero entries backs up nothing, and reporting that as a
# clean success is the silent-success failure this script is a reaction to.
assert_grep "$OUT" "resolved ZERO entries" "zero resolved entries is called out"
assert_exit "$RC" 2 "backing up nothing is PARTIAL, never OK"

# ==============================================================================
# Config hazards — every silent-success path must be loud
# ==============================================================================
start_case "config hazards: typo'd key, wrong type, malformed JSON, bad override"
reset_drive hazard
R="$TMP/repo-hazard"
mk_standard_repo "$R"
echo "log" > "$R/SESSION_LOG.md"

# jq's `?` cannot tell a misspelled key from an absent one.
cat > "$TMP/c-typo.json" <<EOF
{"backupDir":"testlocal:$DRIVE","globalfiles":["SESSION_LOG.md"],"repoOverrides":{}}
EOF
RC=$(run_backup "$TMP/c-typo.json" "$R")
assert_grep "$OUT" "unrecognised key 'globalfiles'" "misspelled key is named"
assert_grep "$OUT" "resolved ZERO entries" "and its consequence is stated"
assert_exit "$RC" 2 "misspelled key does not report OK"

cat > "$TMP/c-type.json" <<EOF
{"backupDir":"testlocal:$DRIVE","globalFiles":"SESSION_LOG.md","repoOverrides":{}}
EOF
RC=$(run_backup "$TMP/c-type.json" "$R")
assert_grep "$OUT" "globalFiles must be an array, found string" "wrong-typed globalFiles rejected"
assert_exit "$RC" 1 "wrong type fails closed"

echo '{ not json' > "$TMP/c-bad.json"
RC=$(run_backup "$TMP/c-bad.json" "$R")
assert_grep "$OUT" "not valid JSON" "malformed config is diagnosed"
assert_exit "$RC" 1 "malformed config exits 1, not an unclassified crash"

BACKUP_CONFIG_FILE="$TMP/does-not-exist.json" "$BASH" "$SCRIPT" "$R" > "$OUT" 2>&1
RC=$?
assert_grep "$OUT" "is set but does not name a readable file" "bad override is fatal"
assert_exit "$RC" 1 "bad override does not silently fall through"

# ==============================================================================
# Config precedence and the TT-452 condition
# ==============================================================================
start_case "config precedence: canonical beats legacy; legacy is never OK"
reset_drive precedence
R="$TMP/repo-prec"
mk_standard_repo "$R"
echo "log" > "$R/SESSION_LOG.md"
write_config "$PLUGIN/config/backup-config.json" "testlocal:$DRIVE" '["SESSION_LOG.md"]' '{}'
write_config "$CLAUDE_CONFIG_DIR/config/backup-config.json" "testlocal:$DRIVE" '["SESSION_LOG.md"]' '{}'

"$BASH" "$SCRIPT" "$R" > "$OUT" 2>&1
RC=$?
assert_grep "$OUT" "Using config: $CLAUDE_CONFIG_DIR/config/backup-config.json" "canonical beats legacy"
assert_grep "$OUT" "stale plugin-local config exists and was IGNORED" "the shadowed copy is named"
assert_exit "$RC" 2 "a stale copy left on disk is not a clean run"

rm -f "$CLAUDE_CONFIG_DIR/config/backup-config.json"
"$BASH" "$SCRIPT" "$R" > "$OUT" 2>&1
RC=$?
assert_grep "$OUT" "Using config: $PLUGIN/config/backup-config.json" "legacy used when canonical absent"
assert_grep "$OUT" "the next upgrade will delete it" "TT-452 condition is stated"
assert_exit "$RC" 2 "TT-452 condition is PARTIAL, not OK"
rm -f "$PLUGIN/config/backup-config.json"

# ==============================================================================
# Dry run reports intent, never success
# ==============================================================================
start_case "dry run: never reads as a completed backup"
reset_drive dryrun
R="$TMP/repo-dry"
mk_standard_repo "$R"
echo "log" > "$R/SESSION_LOG.md"
write_config "$TMP/c-dry.json" "testlocal:$DRIVE" '["SESSION_LOG.md"]' '{}'
BACKUP_CONFIG_FILE="$TMP/c-dry.json" "$BASH" "$SCRIPT" --dry-run "$R" > "$OUT" 2>&1

assert_grep "$OUT" "DRY-RUN" "status token marks it a preview"
assert_grep "$OUT" "Would back up" "bucket is not labelled 'Backed up'"
assert_absent "repo-dry/SESSION_LOG.md" "dry run wrote nothing to the destination"

# ==============================================================================
# A real copy failure is FAILED, not PARTIAL
# ==============================================================================
start_case "copy failure: FAILED and exit 1"
reset_drive failure
R="$TMP/repo-fail"
mk_standard_repo "$R"
echo "log" > "$R/SESSION_LOG.md"
# /dev/null/x cannot be created as a directory, so the copy genuinely fails.
write_config "$TMP/c-fail.json" "testlocal:/dev/null/x" '["SESSION_LOG.md"]' '{}'
RC=$(run_backup "$TMP/c-fail.json" "$R")
assert_grep "$OUT" "FAILED" "status token is FAILED"
assert_exit "$RC" 1 "a copy failure exits 1, distinct from PARTIAL"

# ==============================================================================
# Unsupported alone must degrade the status — no roll-up warning to lean on
# ==============================================================================
# Both of these survived deliberate mutation before this case existed: deleting
# UNSUPPORTED_FILES from either the PARTIAL condition or the "wrong repo?" guard left the
# suite green at 60/60, because every other unsupported fixture also trips the never-found
# roll-up. Sourcing the entry from globalFiles removes that crutch — the roll-up is scoped
# to repoOverrides by design, so UNSUPPORTED_FILES is the ONLY thing that can degrade this
# run.
start_case "unsupported entry alone degrades status, without a roll-up warning"
reset_drive unsuponly
R="$TMP/repo-unsuponly"
mk_standard_repo "$R"
echo "log" > "$R/SESSION_LOG.md"
mkdir -p "$R/reports"; echo "r" > "$R/reports/a.md"
write_config "$TMP/c-unsuponly.json" "testlocal:$DRIVE" \
  '["SESSION_LOG.md","reports"]' \
  '{}'
RC=$(run_backup "$TMP/c-unsuponly.json" "$R")

assert_grep "$OUT" "warnings=0" "no roll-up warning fires (globalFiles are out of its scope)"
assert_in_bucket "Unsupported — present but NOT backed up" "reports" "the directory is Unsupported"
assert_grep "$OUT" "PARTIAL" "an unsupported entry alone is enough for PARTIAL"
assert_exit "$RC" 2 "and enough for exit 2"
# The "wrong repo?" guard only fires when NOTHING was backed up, so a fixture that also
# backs up a file cannot test it — that crutch let the guard's UNSUPPORTED_FILES term
# survive deliberate deletion. Configure ONLY the unsupported directory: backed_up=0,
# failed=0, unsupported=1, which is exactly the laptop-maintenance/reports shape.
reset_drive unsuponly2
write_config "$TMP/c-unsuponly2.json" "testlocal:$DRIVE" '["reports"]' '{}'
RC=$(run_backup "$TMP/c-unsuponly2.json" "$R")

assert_grep "$OUT" "backed_up=0" "nothing was backed up"
assert_grep "$OUT" "unsupported=1" "the only entry is unsupported"
assert_not_grep "$OUT" "is this the repo you meant" \
  "an entry that RESOLVED is never called a wrong-repo mistake"
assert_exit "$RC" 2 "still PARTIAL on the strength of the unsupported entry alone"

# ==============================================================================
# Config validator — the headline cycle-2 fix, previously untested
# ==============================================================================
start_case "config validator: whole-document shape checking"
reset_drive validator
R="$TMP/repo-val"
mk_standard_repo "$R"
echo "log" > "$R/SESSION_LOG.md"

val_case() {  # $1 json, $2 want-exit, $3 expected literal, $4 label
  printf '%s' "$1" > "$TMP/c-val.json"
  local rc
  rc=$(run_backup "$TMP/c-val.json" "$R")
  assert_exit "$rc" "$2" "$4"
  [[ -n "$3" ]] && assert_grep "$OUT" "$3" "$4 — message names the problem"
}

# The typo that motivated whole-document validation: cycle 1's top-level-only check
# passed this, and the run reported a clean OK while dropping the entry entirely.
val_case "{\"backupDir\":\"testlocal:$DRIVE\",\"globalFiles\":[\"SESSION_LOG.md\"],\"repoOverrides\":{\"repo-val\":{\"additionalfiles\":[\"reports\"]}}}" \
  1 "additionalfiles is not a recognised key" "nested misspelled key is rejected"

val_case "[\"SESSION_LOG.md\"]" \
  1 "must be a JSON object" "top-level array is rejected"

val_case "{\"backupDir\":\"testlocal:$DRIVE\",\"globalFiles\":[{\"a\":1}]}" \
  1 "every entry must be a string" "non-string array element is rejected"

val_case "{\"backupDir\":\"testlocal:$DRIVE\",\"repoOverrides\":{\"repo-val\":{\"additionalFiles\":\"x.md\"}}}" \
  1 "additionalFiles must be an array" "wrong-typed additionalFiles is rejected"

val_case "{\"backupDir\":\"testlocal:$DRIVE\",\"repoOverrides\":\"nope\"}" \
  1 "repoOverrides must be an object" "wrong-typed repoOverrides is rejected"

# REGRESSION GUARD. The first version of the validator piped a bare `.repoOverrides` into
# to_entries, which is a jq runtime error when the key is absent — so a perfectly valid
# config without repoOverrides could not run AT ALL. Caught by cycle 3, not by this suite,
# because nothing here exercised a config lacking that key.
val_case "{\"backupDir\":\"testlocal:$DRIVE\",\"globalFiles\":[\"SESSION_LOG.md\"]}" \
  0 "" "a config with NO repoOverrides is valid and runs"

# --- summary ------------------------------------------------------------------
echo ""
echo "=============================================="
echo "  bash $BASH_VERSION"
echo "  passed: $PASS   failed: $FAIL"
echo "=============================================="
[[ "$FAIL" -eq 0 ]] || exit 1
