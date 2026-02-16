#!/usr/bin/env bash
# SessionStart hook for davidshaevel-claude-toolkit plugin

set -euo pipefail

# Determine plugin root directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Read development conventions
conventions_content=$(cat "${PLUGIN_ROOT}/conventions/development-standards.md" 2>&1 || echo "Error reading development-standards.md")

# Escape outputs for JSON using pure bash
escape_for_json() {
    local input="$1"
    local output=""
    local i char
    for (( i=0; i<${#input}; i++ )); do
        char="${input:$i:1}"
        case "$char" in
            $'\\') output+='\\' ;;
            '"') output+='\"' ;;
            $'\n') output+='\n' ;;
            $'\r') output+='\r' ;;
            $'\t') output+='\t' ;;
            *) output+="$char" ;;
        esac
    done
    printf '%s' "$output"
}

conventions_escaped=$(escape_for_json "$conventions_content")

# Output context injection as JSON
cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "<IMPORTANT>\nYour development conventions are provided by the davidshaevel-claude-toolkit plugin.\n\n${conventions_escaped}\n</IMPORTANT>"
  }
}
EOF

exit 0
