# Toolkit v2.0.0 (agent-toolkit rename + AGENTS.md) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rename the plugin to `davidshaevel-agent-toolkit`, move this repo, its templates and `bootstrap-project` to the AGENTS.md layout, and prepare v2.0.0.

**Architecture:** Docs/config edits only. Each task opens with a check that fails now and closes with it passing. T1–T14 are one implementer dispatch; T15 waits for David's go; F1–F4 are sequenced here, not performed.

**Tech Stack:** Markdown, JSON (jq), Bash, `claude` CLI, `gh`.

**Spec:** `docs/superpowers/specs/2026-10-09-agent-toolkit-rename-and-agents-md-design.md` (the source of truth; read it alongside this plan)

## Global Constraints

- Id `davidshaevel-agent-toolkit`, version `2.0.0`; repo, marketplace name, GitHub URL and first cache-path segment stay `davidshaevel-marketplace`. Clean cut, no alias.
- Dated records stay as written: `CHANGELOG.md` history, the 2026-04-23 observations doc, the 2026-03-31 backup spec/plan, the spec, this plan.
- Worktree beside `main/`; conventional commits, every body ending `related-issues: TT-553`.
- **`g2ref`**, the §2 acceptance grep (define once per shell):
  ```bash
  g2ref() { git grep -n davidshaevel-claude-toolkit -- ':!CHANGELOG.md' \
    ':!docs/2026-04-23_cloud_environment_test_observations.md' \
    ':!docs/superpowers/specs/2026-03-31-backup-local-config-design.md' \
    ':!docs/superpowers/plans/2026-03-31-backup-local-config.md' \
    ':!docs/superpowers/specs/2026-10-09-agent-toolkit-rename-and-agents-md-design.md' \
    ':!docs/superpowers/plans/2026-10-09-agent-toolkit-rename-and-agents-md.md'; }
  ```
  The last exclusion is a spec inventory note (this plan must name the old id), approved by the orchestrator 2026-10-09.

## Review Focus

1. Mixed-name cleanup (worktree `AGENTS.local.md`, main `CLAUDE.local.md`): merge into main's name, no second file. T11.
2. Unmigrated repo backup with `AGENTS.local.md` in `globalFiles`: counted Missing, still `OK`, exit 0. T8.
3. `*.local.md` must not ignore a tracked file; `AGENTS.local.md.template`/`.example` stay tracked. T8.
4. Hook output stays valid JSON. T3.
5. A fresh session loads `AGENTS.md` through the import. T13.

---

### Task 1: Baseline

**Files:** none (no commit)

- [ ] `g2ref | wc -l` → `32`.
- [ ] `/bin/bash scripts/test-backup-local-config.sh` and `"$(brew --prefix)"/bin/bash scripts/test-backup-local-config.sh` pass, 109/0 at `e9fac84` (else stop and report). The spec names `/usr/local/bin/bash`, absent on this M1 (G5).
- [ ] `bash hooks/session-start.sh | jq -r .hookSpecificOutput.additionalContext | head -2` names the old plugin.

### Task 2: Manifests (spec §1)

**Files:** Modify `.claude-plugin/marketplace.json`, `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`

- [ ] Check (fails now): `jq -r '.plugins[0].name, .plugins[0].version' .claude-plugin/marketplace.json; jq -r '.name, .version' .claude-plugin/plugin.json .codex-plugin/plugin.json`
- [ ] Edit:
  ```bash
  N=davidshaevel-agent-toolkit V=2.0.0
  for f in .claude-plugin/plugin.json .codex-plugin/plugin.json; do jq --arg n $N --arg v $V '.name=$n|.version=$v' $f > tmp && mv tmp $f; done
  jq --arg n $N --arg v $V '.plugins[0].name=$n|.plugins[0].version=$v' .claude-plugin/marketplace.json > tmp && mv tmp .claude-plugin/marketplace.json
  ```
- [ ] Check passes: new name and `2.0.0` three times; `grep -rh '"version"' .claude-plugin/ .codex-plugin/` prints three `2.0.0` lines; `jq -r .name .claude-plugin/marketplace.json` is still `davidshaevel-marketplace`; `claude plugin validate .` passes.
- [ ] Commit `feat(plugin)!: rename plugin to davidshaevel-agent-toolkit, version 2.0.0`.

### Task 3: Functional references

**Files:** Modify `commands/bootstrap-project.md:5`, `commands/resolve-code-review.md:5`, `commands/self-hosted-review.md:5`, `hooks/session-start.sh:2,39`

- [ ] Check (fails now): `git grep -c davidshaevel-claude-toolkit -- commands hooks` returns 5 hits.
- [ ] Edit: `sed -i '' 's/davidshaevel-claude-toolkit/davidshaevel-agent-toolkit/g'` on the four files.
- [ ] Check passes: grep empty; `bash hooks/session-start.sh | jq -e . >/dev/null` exits 0; T1's `head -2` names the new plugin.
- [ ] Commit `fix(commands,hooks): invoke and announce davidshaevel-agent-toolkit`.

### Task 4: Documentation references (spec §2)

**Files:** Modify `README.md:13,24,90–175,269,276,281`, `CLAUDE.md:9`, `scripts/cloud_setup_script.sh:10,46`, `skills/backup-local-config/SKILL.md:13`, `skills/bootstrap-project/SKILL.md:40`, `conventions/development-standards.md:3`, `docs/cloud_session_setup.md:13,43,63,153,194`, `docs/cloud_backup_setup.md:3`, `CHANGELOG.md:3`

- [ ] Check (fails now): `g2ref | wc -l` → `24`.
- [ ] sed every listed file except `CHANGELOG.md`; edit `CHANGELOG.md:3` (header sentence only) by hand.
- [ ] `README.md:13` becomes the spec's history note, verbatim:
  > **Name history:** v1.x shipped as `davidshaevel-claude-toolkit`; v2.0.0 renamed the plugin to `davidshaevel-agent-toolkit` (TT-553). The repository and marketplace keep the name `davidshaevel-marketplace`.
- [ ] `README.md:24` → `/plugin install davidshaevel-agent-toolkit@davidshaevel-marketplace`; `CLAUDE.md:9` sentence → "The plugin `name` is `davidshaevel-agent-toolkit` (v2.0.0+)."
- [ ] Check passes: `g2ref` prints exactly `README.md:13`; `bash -n scripts/cloud_setup_script.sh` exits 0.
- [ ] Commit `docs: rename references to davidshaevel-agent-toolkit`.

### Task 5: Create AGENTS.md from CLAUDE.md (operator order step 1)

**Files:** Rename `CLAUDE.md` → `AGENTS.md`

**Produces:** `AGENTS.md`, which T6 and T7 consume

- [ ] Check (fails now): `test -f AGENTS.md`
- [ ] `git mv CLAUDE.md AGENTS.md`; line 1 → `# davidshaevel-marketplace - Agent Context`; tree (lines 90–99): templates `AGENTS.md.template`, `AGENTS.local.md.template`, `AGENTS.local.md.example`, `CLAUDE.md.template` (import); root `AGENTS.md` (this file), `CLAUDE.md` (`@AGENTS.md`), `AGENTS.local.md` (gitignored).
- [ ] The spec's line-3 comment removal is a **no-op here**: only the template has it (inventory note).
- [ ] Check passes: `head -1 AGENTS.md`; `grep -n 'CLAUDE.local' AGENTS.md` empty.
- [ ] Commit `docs(agents)!: move project context to AGENTS.md`.

### Task 6: Shrink CLAUDE.md to the import line

**Files:** Create `CLAUDE.md`

- [ ] Check (fails now): `test "$(cat CLAUDE.md)" = "@AGENTS.md"`
- [ ] `printf '@AGENTS.md\n' > CLAUDE.md`; check passes.
- [ ] Commit `docs(agents): CLAUDE.md imports AGENTS.md`.

### Task 7: Private policy block

**Files:** Modify `AGENTS.md` (append at the end)

- [ ] Check (fails now): `grep -c '^## Private policy' AGENTS.md` = 0
- [ ] Append the spec §6 block verbatim:
  ```
  ## Private policy

  Operator-private rules live in `AGENTS.local.md` beside this file (gitignored).
  Harnesses with import support load it here: @AGENTS.local.md
  Otherwise: if `AGENTS.local.md` exists, read it before acting; if not, continue without it.
  ```
- [ ] Check passes: `tail -5 AGENTS.md` is the block.
- [ ] Commit `docs(agents): add Private policy block`.

### Task 8: .gitignore, backup config example, README local-file mentions

**Files:** Modify `.gitignore`, `config/backup-config.json.example`, `README.md:48,183,242,302–316`

- [ ] Check (fails now): `git check-ignore -v AGENTS.local.md CLAUDE.pre-tt553.local.md`
- [ ] `.gitignore`: keep `CLAUDE.local.md`, add `AGENTS.local.md`, `*.local.md`. Example config and `README.md:242`: add `"AGENTS.local.md"` after `"CLAUDE.local.md"`.
- [ ] README inventory correction (orchestrator, 2026-10-09): line 48 bootstrap row → `AGENTS.md, CLAUDE.md (import), .cursorrules, AGENTS.local.md, SESSION_LOG.md`; line 183 → `SESSION_LOG.md, AGENTS.local.md (or legacy CLAUDE.local.md), .envrc, .env`; lines 302–316 example → `AGENTS.local.md`.
- [ ] Check passes: `git check-ignore -v AGENTS.local.md CLAUDE.pre-tt553.local.md CLAUDE.local.md` matches all three; `git ls-files -ci --exclude-standard` empty; `jq -e '.globalFiles | index("AGENTS.local.md")' config/backup-config.json.example`.
- [ ] Review Focus 2: `D=$(mktemp -d) && git -C $D init`, touch only `CLAUDE.local.md` and `SESSION_LOG.md`, then `BACKUP_CONFIG_FILE=config/backup-config.json.example bash scripts/backup-local-config.sh --dry-run $D` → `DRY-RUN(OK) … missing=1 … warnings=0`, exit 0.
- [ ] Commit `chore(gitignore): ignore AGENTS.local.md and *.local.md`.

### Task 9: Templates

**Files:** Rename `templates/CLAUDE.md.template` → `AGENTS.md.template`, `CLAUDE.local.md.template` → `AGENTS.local.md.template`, `CLAUDE.local.md.example` → `AGENTS.local.md.example`. Create `templates/CLAUDE.md.template`. Modify `templates/gitignore-additions.txt`.

**Produces:** the template names that T10 references

- [ ] Check (fails now): `ls templates/ | grep -c 'CLAUDE.local'` = 0
- [ ] Three `git mv`s. `AGENTS.md.template`: title `# [Project Name] - Agent Context`, delete the line-3 comment, tree lists `AGENTS.md`/`CLAUDE.md`/`AGENTS.local.md`, append the T7 block.
- [ ] Create `templates/CLAUDE.md.template`: exactly `@AGENTS.md`.
- [ ] `gitignore-additions.txt`: header, `AGENTS.local.md`, `# legacy` + `CLAUDE.local.md`, `SESSION_LOG.md`.
- [ ] Check passes: `cat CLAUDE.md templates/CLAUDE.md.template` prints `@AGENTS.md` twice; no `CLAUDE.local.*` in `ls templates/`; `cursorrules.template` untouched.
- [ ] Commit `feat(templates)!: AGENTS.md layout templates`.

### Task 10: bootstrap-project skill

**Files:** Modify `skills/bootstrap-project/SKILL.md`

- [ ] Check (fails now): `grep -n 'CLAUDE.local' skills/bootstrap-project/SKILL.md` has hits.
- [ ] Edit: description names `AGENTS.md, CLAUDE.md (import), .cursorrules, AGENTS.local.md, SESSION_LOG.md`; step 2 generates `AGENTS.md`; new step 3 writes `CLAUDE.md` (`@AGENTS.md`); private step generates `AGENTS.local.md`; the `.gitignore` block equals `gitignore-additions.txt`; checklist and next steps name `AGENTS.local.md` ("What NOT to include" done in T4).
- [ ] Dry run: `D=$(mktemp -d) && git -C "$D" init`; follow the edited skill by hand into `$D` with the worktree's `templates/`. Expect `AGENTS.md CLAUDE.md .cursorrules AGENTS.local.md SESSION_LOG.md .gitignore`, `cat $D/CLAUDE.md` = `@AGENTS.md`, and `git -C $D status --porcelain` listing neither local file.
- [ ] Commit `feat(bootstrap-project)!: generate AGENTS.md layout`.

### Task 11: session-handoff legacy handling

**Files:** Modify `skills/session-handoff/SKILL.md:115–133,175`

- [ ] Check (fails now): `grep -c 'Merging AGENTS.local.md' skills/session-handoff/SKILL.md` = 0
- [ ] Rewrite all 10 mentions under `### Worktree Cleanup (Merging AGENTS.local.md)`: the private file is `AGENTS.local.md`, or `CLAUDE.local.md` in an unmigrated repo; merge into the name main uses; if the worktree's file has the other name, merge its content into main's file and don't create a second name. Line 175 matches.
- [ ] Check passes (Review Focus 1): every remaining `CLAUDE.local.md` hit is a legacy clause; `grep -n "don't create a second name"` hits.
- [ ] Commit `feat(session-handoff): AGENTS.local.md primary, CLAUDE.local.md legacy`.

### Task 12: backup-local-config description and conventions

**Files:** Modify `skills/backup-local-config/SKILL.md:3`, `conventions/development-standards.md:245,254,342`

- [ ] Check (fails now): `grep -c 'AGENTS.local.md' skills/backup-local-config/SKILL.md conventions/development-standards.md` = 0 each
- [ ] Description → "…(SESSION_LOG.md, AGENTS.local.md (or legacy CLAUDE.local.md), .envrc, etc.)…"; same wording at conventions 245, 254, 342.
- [ ] Check passes: every `CLAUDE.local.md` hit is labelled legacy.
- [ ] Commit `docs(conventions): AGENTS.local.md primary, CLAUDE.local.md legacy`.

### Task 13: Fresh-session and full PR verification

**Files:** none

- [ ] From the worktree: `claude -p "Quote the first line of your project instructions verbatim."` → `# davidshaevel-marketplace - Agent Context` (Review Focus 5).
- [ ] Run every spec "In the PR" check (`g2ref` for the grep; backup tests under both bashes, as in T1).

### Task 14: Release prep and PR

**Files:** Modify `CHANGELOG.md`

- [ ] Insert the spec's `## 2.0.0 — <date>` section verbatim above `## 1.7.0`, dated the PR's open day (never Unreleased).
- [ ] Commit `chore(release): 2.0.0`, push, open a PR against `main`. **Do not merge.**
- [ ] On David's go, before merge: if the merge day differs, `chore(changelog): set 2.0.0 date`.

### Task 15: Tag and GitHub release (gated: David's go, after merge)

- [ ] `git tag -a v2.0.0 -m "v2.0.0" <merge sha> && git push origin v2.0.0`
- [ ] `gh release create v2.0.0 --title "v2.0.0 — Renamed to davidshaevel-agent-toolkit; AGENTS.md layout (TT-553)" --notes-file <notes>`; notes in v1.7.0's shape: H2 sections with bullets, the MAJOR rationale, a "Migrating from 1.x" callout pointing at the runbook, `related-issues: TT-553`.
- [ ] Check passes: `gh release view v2.0.0`; `git cat-file -t v2.0.0` = `tag`.

---

## Follow-on sequence (not performed here)

Spec §5, verbatim:
1. This repo's PR merges, and v2.0.0 is tagged and released.
2. David runs the runbook.
3. The three cross-repo PRs land, because tracked settings should name only a plugin the marketplace already serves.

- **F1 David's runbook** (spec "Migration runbook", steps by number): 1 uninstall user scope; 2 uninstall job-searches-2026-q4 project scope; 3 `marketplace update`; 4 install new id; 5 `~/.claude/settings.json` lines 19–20 + `enabledPlugins` check; 6 `AGENTS.local.md` into `~/.claude/config/backup-config.json`; 7 two `~/.codex/config.toml` keys; 8 laptop-maintenance `settings.local.json`; 9 `main/` private file → `AGENTS.local.md`, kept as `CLAUDE.pre-tt553.local.md`; 10 delete old cache; 11 restart every session.
- **F2 Cross-repo PRs** (spec §3): job-searches-2026-q4, job-searches-2026-q3, development-tooling-2026-q4; each verified by zero old-name hits.
- **F3** The spec's "After the migration" verification list.
- **F4** The orchestrator updates `config/roster.local.json` and its memory file.

## Open questions / spec inventory notes

- G1 (orchestrator-resolved): this plan excluded from the §2 grep.
- G2: line-3 comment removal is a no-op for the repo's `CLAUDE.md` (T5).
- G3 (orchestrator-resolved): README 48, 183, 302–316 added to T8.
- G4 (orchestrator-resolved): T14 dates the CHANGELOG, fixed pre-merge if needed.
- G5 (open): the spec's Verification and `CLAUDE.md` Helpful Commands name `/usr/local/bin/bash`; on this M1 Homebrew bash is `/opt/homebrew/bin/bash`. T1/T13 use `$(brew --prefix)`; whether `AGENTS.md` should correct the path is David's call.

## Self-review

- Coverage: §1→T2; §2→T3, T4; §3→F2; §4→F1; §5→follow-on sequence; §6→T5–T12; Release→T14, T15; Verification→T13, F3; Risks→F1, F2.
- Operator order: AGENTS.md (T5) → CLAUDE.md import (T6) → Private policy (T7) → `.gitignore` (T8) → templates, bootstrap (T9, T10) → session-handoff, backup legacy (T11, T12) → fresh-session check (T13).
- Ordering: no task uses a file a later task creates (T6, T7 need T5; T10 needs T9).
- Placeholders: none; `<date>`, `<merge sha>`, `<notes>` are filled at run time per T14/T15.
