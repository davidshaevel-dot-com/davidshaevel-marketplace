# Changelog

Notable changes to the davidshaevel-claude-toolkit plugin. Version numbers are
assigned at release time (see the policy in CLAUDE.md); changes accumulate under
**Unreleased** until a release folds them into a numbered section.

## Unreleased

### Fixed

- `backup-local-config.sh`: backup destinations now preserve each config entry's
  full relative path (TT-372). Previously the destination carried only the
  entry's basename — for file entries, nothing at all — so two entries sharing a
  basename (`jobs/co-a/.work`, `jobs/co-b/.work`) mapped to the **same** remote
  destination and the second copy silently destroyed the first.
- `backup-local-config.sh`: directory entries in `globalFiles`/`additionalFiles`
  are now backed up (TT-302; superseded by TT-372). Fifos, sockets, and broken
  symlinks keep their "Unsupported" classification with a stated reason.
- `backup-local-config.sh`: config entries that are absolute paths or contain a
  `.` or `..` segment are rejected as Unsupported instead of being spliced into
  a destination that could escape the repo's backup namespace (`..`) or upload
  the entire repository including `.git` (`.`). Validation happens once at
  config level, so a bad entry is counted once — not once per worktree.
- `backup-local-config.sh`: trailing-slash entries (`reports/`) are normalized
  before deduplication, so `reports` and `reports/` no longer count (and copy)
  twice. A slash-only entry (`/`) survives normalization and is rejected loudly
  instead of vanishing from every bucket.
- `backup-local-config.sh`: an empty directory entry previously reported `[ok]`
  while creating nothing at the destination — fixed by an explicit idempotent
  `rclone mkdir` after the copy (`--create-empty-src-dirs` is also passed, but
  it covers empty *sub*directories only, never an empty copy root; do not
  remove the mkdir on its account).
- `backup-local-config.sh`: symlink handling is now explicit in both copy
  modes. A symlink *entry* is followed (`--copy-links`) — previously it was
  classified backable and then failed in rclone. Symlinks *inside* a directory
  entry are preserved as links (`--links`) — previously they were silently
  skipped (NOTICE, exit 0); following them instead would leak content from
  outside the repo and expand link cycles.
- `backup-local-config.sh`: fifos and sockets inside a directory entry — which
  rclone skips with only a NOTICE and exit 0 — are now detected, named in a
  warning, and degrade the run to PARTIAL instead of reporting `[ok]` over an
  incomplete copy.
- `backup-local-config.sh`: the destination parent is computed with shell
  expansion instead of `dirname(1)`, which option-parses a leading `-` and
  flattened entries like `-cache/x.md` to the destination root.

### ⚠ Backwards-incompatible for existing backups (TT-372)

Nested entries previously backed up sit at old basename destinations
(`…/<basename>`) that **no future run will update** — the new
hierarchy-preserving destinations populate alongside them. Clean up the orphaned
basename destinations on the remote only after **every machine** backing up to
it runs the new version; see README §"Directory entries are supported as of
TT-372" for how to identify orphans. Release notes for the version that ships
this change must carry this warning.
