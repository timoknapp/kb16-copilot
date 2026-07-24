#!/bin/bash
# Copilot CLI status hook -> writes a single status word to a state file.
# Hammerspoon watches this file and updates the menubar color.
#
# Usage (from ~/.copilot/hooks/*.json): ./copilot-status.sh <STATUS>
#   STATUS one of: idle thinking running done error
#
# Copilot pipes event JSON on stdin; we ignore it here and just record STATUS.

STATE_FILE="$HOME/.copilot-kb16-status"
STATUS="${1:-idle}"

# Drain stdin so Copilot's hook pipe never blocks.
cat >/dev/null 2>&1 || true

printf '%s' "$STATUS" > "$STATE_FILE"

# Hooks may emit JSON on stdout; empty object = no changes requested.
printf '{}'
