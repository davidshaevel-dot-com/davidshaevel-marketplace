# Changelog

Notable changes to the davidshaevel-agent-toolkit plugin. Version numbers are
assigned at release time (see the policy in AGENTS.md); changes accumulate under
**Unreleased** until a release folds them into a numbered section.

## 2.0.1 — 2026-10-12

### Changed

- README accuracy pass for an external reader (TT-669, PR #15, `a804dba`): the
  README now says what works where, installs and updates through the plugin CLIs,
  and moves operator detail to `docs/`.
  - Codex CLI section rewritten to the verified state: register the git
    marketplace, `codex plugin add`, accept the hook trust prompt; a works / does
    not work list (`backup-local-config` and the `session-handoff` backup step
    fail because `${CLAUDE_PLUGIN_ROOT}` is empty under Codex;
    `self-hosted-review` and the slash commands are Claude Code only).
  - CLI-first install and update: `claude plugin marketplace add|update`,
    `claude plugin install|update`, `codex plugin marketplace add|upgrade`,
    `codex plugin add`, replacing the hand steps (cache clone, editing
    `installed_plugins.json`).
  - Private links and issue ids removed from the README.
  - Backup detail moved verbatim to `docs/backup-local-config.md`; the README
    keeps a summary and the link.
  - The TT-553 spec's migration runbook step 7 gains `codex plugin add` and
    `codex plugin remove` (renaming the config keys is not an install).
  - Verification: `claude plugin validate .` passes, backup suite 109/0 under
    `/bin/bash` 3.2 and Homebrew bash 5.3, one `codex exec` check with no hook
    error.

No runtime change: conventions, hooks, skills and manifests are unchanged apart from the version.

## 2.0.0 — 2026-10-09

### Changed (breaking)

- Plugin renamed `davidshaevel-claude-toolkit` → `davidshaevel-agent-toolkit`
  (TT-553). Every namespaced skill and command id changes, as does the cache
  path (`~/.claude/plugins/cache/davidshaevel-marketplace/davidshaevel-agent-toolkit/`).
  Repository, marketplace name and GitHub URL are unchanged. No alias for the
  old id: uninstall it and install the new one.
- AGENTS.md layout: context in `AGENTS.md`, `CLAUDE.md` is `@AGENTS.md`, private
  context in `AGENTS.local.md`. `bootstrap-project` and `templates/` generate it;
  `CLAUDE.local.md.template`/`.example` become `AGENTS.local.md.*`.
  `session-handoff`, `backup-local-config` and the conventions treat
  `AGENTS.local.md` as primary, `CLAUDE.local.md` as legacy.

MAJOR: renaming the plugin renames every skill and command.

## 1.7.0 — 2026-08-14

### Changed

- `conventions/development-standards.md`: Linear Conventions now carry an explicit
  Done policy (TT-478) — Done is set only when acceptance criteria are verified
  (by David, or by an agent with David's approval), never by PR-merge automation;
  multi-PR issues stay open until closing criteria are met, and branch-prefix
  linking of follow-up PRs must not imply closure. Documents that Team Tacocat's
  Linear "On merge" automation is set to No action as of 2026-08-14 after it
  falsely closed TT-476/TT-477 ("On PR open → In Progress" remains enabled).
  Convention text change → MINOR bump per policy, hence 1.7.0.

## 1.6.0 — 2026-08-14

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
