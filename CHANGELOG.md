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
  `..` segment are rejected as Unsupported instead of being spliced into a
  destination that could escape the repo's backup namespace.
- `backup-local-config.sh`: trailing-slash entries (`reports/`) are normalized
  before deduplication, so `reports` and `reports/` no longer count (and copy)
  twice. A slash-only entry (`/`) survives normalization and is rejected loudly
  instead of vanishing from every bucket.
- `backup-local-config.sh`: rclone now runs with `--create-empty-src-dirs`
  (an empty directory entry previously reported `[ok]` while creating nothing
  at the destination) and `--copy-links` (symlinks inside a copied directory
  were previously skipped with only a NOTICE and exit 0; symlink-to-file
  entries were classified backable but then failed in rclone).
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
