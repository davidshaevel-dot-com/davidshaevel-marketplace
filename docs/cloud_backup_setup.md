# Cloud Backup Setup — Google Drive via rclone

Operational guide for wiring the `davidshaevel-claude-toolkit` backup skill into Claude Code cloud sessions. Covers credential choice, encoding, and per-environment provisioning.

## Context

The plugin's `skills/backup-local-config/` skill calls `rclone copy` against a remote named `gdrive` (configurable in `config/backup-config.json`). rclone needs `~/.config/rclone/rclone.conf` to resolve that remote — but cloud sessions start with a clean home directory, so nothing is there by default.

The repo's SessionStart hook (`.claude/hooks/session-start.sh`) materializes that file at session start from a single env var, `RCLONE_CONF_B64`, holding the base64-encoded contents of `rclone.conf`. This doc is the operational companion to that hook — it covers what to put inside the config before encoding it.

> **Related.** The gstack/bun install runs once at environment-build time via the Setup Script in `docs/cloud_setup_script.sh`, not at session start. See that file's header for paste-in instructions.

## Credential options

Two credential shapes fit in `rclone.conf`. Pick one based on blast-radius tolerance.

### Option 1 — Service account + Shared Drive (recommended)

A Google Cloud service account scoped to a single Shared Drive. If the credential leaks, the attacker gets read/write on that one Shared Drive and nothing else.

**One-time setup (local machine):**

1. Create or reuse a Google Cloud project at https://console.cloud.google.com/.
2. Enable the Drive API: APIs & Services → Library → Google Drive API → Enable.
3. IAM & Admin → Service Accounts → Create service account. Name it descriptively (e.g. `claude-code-backups`). Skip the "grant this service account access to project" step — it does not need project-level roles.
4. On the new service account, Keys → Add Key → Create new key → JSON. Save the downloaded file as `~/.config/rclone/gdrive-sa.json`, mode 600.
5. Copy the service account's email (ends in `@<project>.iam.gserviceaccount.com`).
6. In Google Drive (browser), create a **Shared Drive** named `session-backups` (left sidebar → Shared drives → + New). Open it → Manage members → add the service account email as **Content manager**. A Shared Drive — not a folder in "My Drive" — is required: service accounts have no personal storage quota of their own, so writes into My Drive fail with `storageQuotaExceeded`. Shared Drives own their own quota, which the service account can consume. Requires Google Workspace.
7. Get the Shared Drive's ID from the browser URL — it's the path segment after `/folders/` when you have the Shared Drive open.
8. Run `rclone config`:
   - `n` — new remote
   - Name: `gdrive`
   - Storage: `drive`
   - `client_id` / `client_secret`: leave blank (the service account replaces these).
   - Scope: pick `drive`. The narrower `drive.file` scope does not work reliably against a Shared Drive with a service account — listing the Shared Drive root and resolving `team_drive` need broader access. Blast radius stays tight regardless: the service account is only a member of this one Shared Drive, so `drive` scope still grants it access to nothing else.
   - Service account credentials: paste the absolute path to `gdrive-sa.json`.
   - Root folder ID: leave blank (rclone will root at the Shared Drive's top level).
   - Configure as team drive: `y`, then paste the Shared Drive ID from step 7.
   - Skip the OAuth browser step when prompted — it's not needed with a service account.
9. Verify: `rclone lsd gdrive:` should list the contents of the Shared Drive (empty is fine if you just created it).

**Result:** `~/.config/rclone/rclone.conf` now has a `[gdrive]` section with `service_account_file = …`. For cloud use, you'll inline the JSON key instead (next section).

### Option 2 — User OAuth with narrow scope (simpler, larger blast radius)

Falls back to a refresh token against your personal Drive. If leaked, an attacker gets whatever the scope allowed across your entire Drive.

1. Install rclone locally.
2. Run `rclone config`:
   - `n` — new remote, name `gdrive`, type `drive`.
   - Scope: pick `drive.file` (token can only touch files rclone creates) — not `drive` (full access).
   - Optionally paste your own OAuth `client_id` / `client_secret` registered in Google Cloud Console so you can see and revoke the grant independently under https://myaccount.google.com/permissions.
   - Complete the browser OAuth flow.
3. Verify: `rclone lsd gdrive:`.

## Preparing for the cloud

Cloud sessions can't read files from your laptop. The config needs to be inlined into `rclone.conf` so a single base64 blob contains everything rclone needs.

### If using Option 1 (service account)

The default `rclone config` writes `service_account_file = /path/to/gdrive-sa.json` — a path that won't exist in the cloud container. Replace it with `service_account_credentials` (inline JSON) so the config is self-contained:

```
[gdrive]
type = drive
scope = drive
service_account_credentials = {"type":"service_account","project_id":"…","private_key_id":"…","private_key":"-----BEGIN PRIVATE KEY-----\n…\n-----END PRIVATE KEY-----\n","client_email":"…@….iam.gserviceaccount.com","client_id":"…","auth_uri":"https://accounts.google.com/o/oauth2/auth","token_uri":"https://oauth2.googleapis.com/token","auth_provider_x509_cert_url":"…","client_x509_cert_url":"…"}
team_drive = <shared-drive-id>
```

Paste the entire JSON file as a single line (no actual newlines inside the value — the `\n` sequences inside the private key stay as literal `\n`). Drop `service_account_file` entirely.

Test locally by pointing rclone at this modified file:

```bash
cp ~/.config/rclone/rclone.conf /tmp/rclone-cloud.conf
# edit /tmp/rclone-cloud.conf to use service_account_credentials as above
RCLONE_CONFIG=/tmp/rclone-cloud.conf rclone lsd gdrive:
```

If that lists the shared folder contents, the config is cloud-ready.

### If using Option 2 (OAuth)

No edits needed — the default rclone.conf already contains the `token = {…}` blob inline.

## Base64 encode and install in the cloud

1. Encode the cloud-ready config to a single line:

   ```bash
   # macOS (BSD base64 — no -w flag, use input redirection for portability)
   base64 < /tmp/rclone-cloud.conf | tr -d '\n' | pbcopy

   # Linux
   base64 -w0 /tmp/rclone-cloud.conf | xclip -selection clipboard
   ```

2. In claude.ai/code, open the environment dropdown → gear icon → Environment variables. Add one line:

   ```
   RCLONE_CONF_B64=<paste>
   ```

   No quotes. No trailing newline.

3. Start or reload a cloud session. Look for this line in the SessionStart output:

   ```
   [session-start] rclone.conf materialized from RCLONE_CONF_B64
   ```

4. Verify from the cloud session:

   ```bash
   rclone listremotes                 # gdrive:
   rclone lsd gdrive:                 # lists folder contents
   DRY_RUN=1 "$CLAUDE_PLUGIN_ROOT/scripts/backup-local-config.sh" "$PWD"
   ```

## Rotation and revocation

**Service account (Option 1):**
- Rotate: in the Google Cloud Console service account page, create a new key, update `service_account_credentials` in the local rclone.conf, re-encode, replace `RCLONE_CONF_B64`, then delete the old key.
- Revoke a leaked key: delete the specific key under the service account. The service account itself stays intact.
- Nuclear option: delete the entire service account and the service-account-to-folder share evaporates.

**OAuth (Option 2):**
- Rotate: `rclone config reconnect gdrive:` locally, re-encode, replace the env var.
- Revoke: https://myaccount.google.com/permissions → remove rclone's access.

Do both a rotate and a revoke if a leak is suspected — revoke cuts off the old credential, rotate installs a new one.

## Troubleshooting

**`rclone listremotes` is empty in cloud sessions.**
- Check the SessionStart output. If the `rclone.conf materialized` line is missing, `RCLONE_CONF_B64` is unset or empty in the environment.
- If the line is present but `listremotes` is still empty, inspect the materialized file: `cat ~/.config/rclone/rclone.conf`. Truncated contents usually mean the pasted env var was wrapped or split across lines.

**`rclone lsd gdrive:` returns "failed to make fs: directory not found" or similar.**
- Option 1: the service account isn't a member of the Shared Drive, or `team_drive` doesn't match. Re-open Manage members on the Shared Drive and confirm the SA is listed as Content manager (or higher); double-check the Shared Drive ID.
- Option 2: `drive.file` scope cannot see folders you created manually. Let rclone create its own destination folder, or widen the scope.

**`googleapi: Error 403: Service Accounts do not have storage quota` / `storageQuotaExceeded` on write.**
- The `gdrive` remote is pointed at a folder in "My Drive" instead of a Shared Drive. Service accounts own no personal storage. Fix: create a Shared Drive, add the SA as Content manager, and in `rclone.conf` replace `root_folder_id` with `team_drive = <shared-drive-id>` and set `scope = drive` (the narrower `drive.file` scope does not work with Shared Drives + service accounts).

**`oauth2: cannot fetch token: 400 Bad Request` / `invalid_grant`.**
- The refresh token was revoked or expired. Rerun `rclone config reconnect gdrive:` locally and reinstall the env var.

**Backup skill runs but nothing appears in Drive.**
- Check `backup-config.json` — `backupDir` should be `gdrive:<path-inside-shared-drive>`, not an absolute Drive path.
- Run with `DRY_RUN=1` first to see which files would be copied from where to where.

## Security notes

- The env var value is plaintext to anyone with edit access to the cloud environment. Treat it accordingly.
- Prefer Option 1 over Option 2 whenever practical — a leaked service account key scoped to one folder is recoverable; a leaked OAuth token against your whole Drive is not.
- Do not commit `rclone.conf`, `gdrive-sa.json`, or the base64 blob to this repo. None of them belong in git.
- The plugin's own `config/backup-config.json` is gitignored by the plugin — keep it that way; `backupDir` is sensitive because it names your remote folder.
