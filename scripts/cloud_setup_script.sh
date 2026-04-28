#!/bin/bash
# Cloud environment Setup Script — paste into claude.ai/code → environment
# dropdown → gear icon → Setup Script. Runs once when the environment
# snapshot is built and is cached; session-start no longer pays this cost.
#
# What this does:
#   1. Clones garrytan/gstack into ~/.local/share/gstack (clean slate).
#   2. Installs bun (prerequisite for gstack's build step).
#   3. Runs `./setup --prefix -q` so skills register as /gstack-qa etc.
#   4. Installs rclone (required by the davidshaevel-claude-toolkit
#      backup-local-config skill to push session backups to Drive).
#
# What this does NOT do:
#   - Materialize rclone.conf. That stays in .claude/hooks/session-start.sh
#     because it depends on the RCLONE_CONF_B64 env var, which can rotate
#     between sessions without rebuilding the snapshot.
#
# Failures abort the environment build — full stdout/stderr is visible
# in the build log for troubleshooting.

set -euo pipefail

REPO_DIR="$HOME/.local/share/gstack"

# Clean slate: drop anything left behind by a previous install attempt
# so `git clone` into an existing non-repo directory can't fail.
rm -rf "$REPO_DIR"
mkdir -p "$(dirname "$REPO_DIR")"

git clone --depth 1 https://github.com/garrytan/gstack.git "$REPO_DIR"

# Binary dependencies — install before the project build so a failed
# install aborts the snapshot fast, without waiting on gstack to finish.
#
# Retry flags: the claude.ai/code TLS-inspecting egress proxy has been
# observed to return transient 5xx (503, "DNS cache overflow", etc.) for
# upstream CDN requests. --retry 5 --retry-delay 1 adds cheap insurance
# against those blips; curl's default retry set already covers 408/429/
# 5xx and transient DNS, and --retry-connrefused adds early-connection
# failures. Worst case: ~5s added latency on failure.
if ! command -v bun >/dev/null 2>&1; then
  curl -fsSL --retry 5 --retry-delay 1 --retry-connrefused https://bun.sh/install | bash
fi
[ -d "$HOME/.bun/bin" ] && export PATH="$HOME/.bun/bin:$PATH"

# rclone — required by the davidshaevel-claude-toolkit backup-local-config
# skill for pushing session backups to Google Drive. SessionStart materializes
# rclone.conf from RCLONE_CONF_B64; this script installs the binary itself.
#
# Source: pinned .deb from rclone's GitHub release, not rclone.org/install.sh
# and not downloads.rclone.org, because both have been observed to return
# intermittent 503s through claude.ai/code's TLS-inspecting egress sandbox
# even when properly allowlisted. GitHub's release-assets CDN has been
# consistently reliable through the same proxy.
#
# Version is pinned: the GitHub release URL requires the version in the
# filename. To bump, either update the default below and rebuild the
# snapshot, or export RCLONE_VER=v<new-version> in the cloud environment
# variables pane and rebuild (no script edit needed).
#
# Arch detection is on its own short line so the resulting curl URL stays
# short enough to survive paste-to-UI line wrapping; a long line with an
# embedded $(...) was previously observed to be split by the paste pipeline.
#
# install.sh also shells out to `unzip`, which isn't guaranteed to be on
# minimal base images. dpkg -i needs no extra extractor.
RCLONE_VER="${RCLONE_VER:-v1.73.5}"
if ! command -v rclone >/dev/null 2>&1; then
  arch=$(dpkg --print-architecture)
  deb_url="https://github.com/rclone/rclone/releases/download/${RCLONE_VER}/rclone-${RCLONE_VER}-linux-${arch}.deb"
  tmp_deb=$(mktemp --suffix=.deb)
  curl -fsSL --retry 5 --retry-delay 1 --retry-connrefused "$deb_url" -o "$tmp_deb"
  dpkg -i "$tmp_deb"
  rm -f "$tmp_deb"
fi

cd "$REPO_DIR"
./setup --prefix -q

echo "cloud_setup: gstack installed with gstack- prefix; rclone installed"
