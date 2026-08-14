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

assert_dir() {  # $1 path under drive root, $2 label — the DIRECTORY itself must exist
  if [[ -d "$DRIVE/$1" ]]; then ok "$2"; else bad "$2 (no directory: $1)"; fi
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

# documents_bug() lived here until TT-372 landed: it pinned the known-wrong flattening
# behaviour so the fixing release had to change those lines. Every call flipped to a
# real assertion in that release — the helper went with them.

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
mkdir -p "$R/-cache"
echo "dash" > "$R/-cache/x.md"
write_config "$TMP/c-files.json" "testlocal:$DRIVE" \
  '["SESSION_LOG.md"]' \
  '{"repo-files":{"additionalFiles":["a/x/swap.py","b/y/swap.py","my docs/notes.md","-cache/x.md"]}}'
RC=$(run_backup "$TMP/c-files.json" "$R")

assert_file "repo-files/SESSION_LOG.md" "top-level file keeps its place (no extra nesting)"
assert_exit "$RC" 0 "all entries resolved"

# TT-372: a file entry nests under its parent directory, so entries sharing a basename
# keep distinct destinations. These three assertions replaced the documents_bug() calls
# that pinned the old flattening behaviour — this diff IS the behaviour-change record.
assert_file "repo-files/a/x/swap.py" "nested file preserves its parent path"
assert_absent "repo-files/swap.py" "nothing flattens to the destination root"
assert_content "repo-files/a/x/swap.py" "AAA" "same-basename file A survives"
assert_content "repo-files/b/y/swap.py" "BBB" "same-basename file B survives"
assert_file "repo-files/my docs/notes.md" "path with a space preserves its parent"
# dirname(1) option-parses a leading "-", emptying relparent and flattening the file to
# the destination root — the collision class this PR fixes, resurrected via a helper.
# relparent is computed with pure expansion instead; this entry pins that.
assert_content "repo-files/-cache/x.md" "dash" "leading-dash component nests under its parent"
assert_absent "repo-files/x.md" "leading-dash entry does not flatten to the root"

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
ln -s "./notes.md" "$R/jobs/co-a/.work/latest.md"   # symlink INSIDE a copied directory
mkdir -p "$R/emptydir"                              # empty dir: must EXIST at the dest
write_config "$TMP/c-dirs.json" "testlocal:$DRIVE" \
  '["SESSION_LOG.md"]' \
  '{"repo-dirs":{"additionalFiles":["reports/","reports","jobs/co-a/.work","jobs/co-b/.work","emptydir"]}}'
RC=$(run_backup "$TMP/c-dirs.json" "$R")

# Directory support (TT-302/TT-372): a directory entry nests under its FULL relative
# path, so two directories sharing a basename land at distinct destinations instead of
# the second silently destroying the first. `rclone copy dir dest/` copies dir's
# CONTENTS into dest/, which is why the destination must carry the relpath itself.
assert_file "repo-dirs/reports/disk-audit-2026-08-11.md" "trailing-slash directory nests under its relpath"
assert_content "repo-dirs/jobs/co-a/.work/notes.md" "wa" "same-basename directory A keeps its hierarchy"
assert_content "repo-dirs/jobs/co-b/.work/notes.md" "wb" "same-basename directory B keeps its hierarchy"
assert_absent "repo-dirs/.work" "no basename-collision destination is created"
assert_absent "repo-dirs/disk-audit-2026-08-11.md" "no directory contents leaked into the root"
assert_not_grep "$OUT" "never backed up from any worktree" "backed-up directories satisfy the roll-up"
assert_not_grep "$OUT" "Unsupported — present but NOT backed up (3)" "directories are no longer Unsupported"
# A backed_up count that includes an entry with NOTHING at its destination is "[ok]"
# over a backup that does not exist. --create-empty-src-dirs makes the claim true.
assert_dir "repo-dirs/emptydir" "empty directory EXISTS at its destination (not a silent no-op)"
# Without --copy-links rclone skips symlinks inside a copied directory with a NOTICE
# and exit 0 — a silent partial copy. Followed content must be present.
assert_content "repo-dirs/jobs/co-a/.work/latest.md" "wa" "symlink inside a directory is followed, not skipped"
# "reports/" and "reports" are one entry: trailing slashes are stripped BEFORE dedupe,
# so the copy runs once and the count says so (5 = SESSION_LOG + reports + two .work + emptydir).
assert_grep "$OUT" "backed_up=5 missing" "trailing-slash duplicate deduplicates to one entry"
assert_exit "$RC" 0 "directory entries are a clean success"

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
mkdir -p "$R/realdir"; echo "rd" > "$R/realdir/inner.md"
ln -s "./realdir" "$R/dirlink"                # intact symlink to a directory
ln -s "./realdir/inner.md" "$R/filelink.md"   # intact symlink to a regular file
write_config "$TMP/c-classify.json" "testlocal:$DRIVE" \
  '["SESSION_LOG.md"]' \
  '{"repo-classify":{"additionalFiles":["nope.md","dangling.md","pipe-link","dirlink","filelink.md"]}}'
RC=$(run_backup "$TMP/c-classify.json" "$R")

# Bucket-scoped: grepping the whole output would match a filename under ANY bucket, so a
# misclassification would pass. These assertions must be able to fail.
assert_in_bucket "Missing — no such path" "nope.md" "absent entry is Missing"
assert_in_bucket "Unsupported — present but NOT backed up" "dangling.md" \
  "broken symlink is Unsupported, NOT 'no such path'"
assert_in_bucket "Unsupported — present but NOT backed up" "pipe-link" \
  "intact symlink to a fifo is Unsupported"
# `-d` dereferences and rclone runs with --copy-links, so a symlink to a directory is
# backable the same way a symlink to a regular file is — followed, and nested under
# the ENTRY's relpath. (Before --copy-links, a file-symlink entry was classified
# backable and then FAILED in rclone — classification and copy disagreed.)
assert_content "repo-classify/dirlink/inner.md" "rd" \
  "symlink to a directory is followed and backed up"
assert_content "repo-classify/filelink.md" "rd" \
  "symlink to a regular file is followed and backed up (classification and copy agree)"

# The REASON must match the actual type — a wrong reason is a verdict without a basis,
# which is the whole defect class the v1.5.1 relabelling addressed.
assert_grep "$OUT" "dangling.md (broken symlink — its target does not exist)" \
  "broken symlink's reason is accurate"
assert_grep "$OUT" "pipe-link (symlink to something that is not a regular file)" \
  "intact symlink is NOT called broken"

assert_not_grep "$OUT" "Skipped — not found" "the old misleading label is gone"
assert_grep "$OUT" "never backed up from any worktree" "never-found roll-up fired"
assert_grep "$OUT" "PARTIAL" "status token is PARTIAL"
assert_exit "$RC" 2 "stale config exits 2, not 0"

# ==============================================================================
# Case 17: unsafe entries — ".." and absolute paths cannot escape the namespace
# ==============================================================================
# The entry string is spliced into the destination, so "../x" would path-clean into
# the PARENT of this repo's backup folder — a silent cross-repo overwrite. Rejection
# is conservative: "a/../x" is refused even though its cleaned path stays inside.
start_case "unsafe entries: .. and absolute paths refuse to escape the namespace"
reset_drive unsafe
R="$TMP/repo-unsafe"
mk_standard_repo "$R"
echo "log" > "$R/SESSION_LOG.md"
echo "outside" > "$TMP/escape-target.md"   # sibling of the repo, reachable via ..
write_config "$TMP/c-unsafe.json" "testlocal:$DRIVE" \
  '["SESSION_LOG.md"]' \
  '{"repo-unsafe":{"additionalFiles":["../escape-target.md","/etc/hosts","a/../SESSION_LOG.md","/"]}}'
RC=$(run_backup "$TMP/c-unsafe.json" "$R")

assert_in_bucket "Unsupported — present but NOT backed up" "../escape-target.md" \
  "parent-escape entry is refused, not copied"
assert_in_bucket "Unsupported — present but NOT backed up" "/etc/hosts" \
  "absolute-path entry is refused"
assert_in_bucket "Unsupported — present but NOT backed up" "a/../SESSION_LOG.md" \
  "inner .. is refused conservatively"
# Trailing-slash normalization must NOT reduce "/" to the empty string — an empty
# entry is deleted by the dedupe -n guard and vanishes from every bucket and warning.
assert_in_bucket "Unsupported — present but NOT backed up" "/ (unsafe config entry" \
  "slash-only entry is refused loudly, not silently dropped"
assert_grep "$OUT" "unsafe config entry" "the reason names the basis for refusal"
assert_absent "escape-target.md" "nothing landed OUTSIDE the repo's backup namespace"
assert_file "repo-unsafe/SESSION_LOG.md" "safe entries still back up alongside refusals"
assert_grep "$OUT" "PARTIAL" "unsafe entries degrade status loudly"
assert_exit "$RC" 2 "unsafe entries exit 2, not 0"

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
# Nested directory entry under the bare+worktree layout: the headline TT-372
# criteria must hold on BOTH layouts, not be proven on standard repos only.
mkdir -p "$R/main/jobs/co-a/.work"
echo "bw" > "$R/main/jobs/co-a/.work/notes.md"
write_config "$TMP/c-bare.json" "testlocal:$DRIVE" \
  '["SESSION_LOG.md","CLAUDE.local.md"]' \
  '{"repo-bare":{"additionalFiles":["jobs/co-a/.work"]}}'
RC=$(run_backup "$TMP/c-bare.json" "$R")

assert_file "repo-bare/main/SESSION_LOG.md" "main worktree file"
assert_content "repo-bare/main/jobs/co-a/.work/notes.md" "bw" \
  "nested directory preserves hierarchy under a worktree destination"
assert_absent "repo-bare/main/.work" "no basename-collision destination in a worktree"
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
# Directories became backable in TT-372, so the unsupported fixture is now a fifo —
# still present, still never backable, still outside the roll-up's repoOverrides scope.
mkfifo "$R/afifo"
write_config "$TMP/c-unsuponly.json" "testlocal:$DRIVE" \
  '["SESSION_LOG.md","afifo"]' \
  '{}'
RC=$(run_backup "$TMP/c-unsuponly.json" "$R")

assert_grep "$OUT" "warnings=0" "no roll-up warning fires (globalFiles are out of its scope)"
assert_in_bucket "Unsupported — present but NOT backed up" "afifo" "the fifo is Unsupported"
assert_grep "$OUT" "PARTIAL" "an unsupported entry alone is enough for PARTIAL"
assert_exit "$RC" 2 "and enough for exit 2"
# The "wrong repo?" guard only fires when NOTHING was backed up, so a fixture that also
# backs up a file cannot test it — that crutch let the guard's UNSUPPORTED_FILES term
# survive deliberate deletion. Configure ONLY the unsupported entry: backed_up=0,
# failed=0, unsupported=1 — the shape laptop-maintenance/reports had before TT-372.
reset_drive unsuponly2
write_config "$TMP/c-unsuponly2.json" "testlocal:$DRIVE" '["afifo"]' '{}'
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
  # `if`, not a trailing `&&`: the && form returns 1 when $3 is empty, which is inert
  # only because this harness deliberately omits `set -e`. It would become a real bug
  # the moment that changed, or if such a call ended the file.
  if [[ -n "$3" ]]; then
    assert_grep "$OUT" "$3" "$4 — message names the problem"
  fi
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
