#!/bin/bash
# Copilot CLI status hook -> records agent status for the KB16 LEDs + menubar.
#
# Usage (from ~/.copilot/hooks/*.json): ./copilot-status.sh <STATUS>
#   STATUS one of: idle thinking running done error
#
# Copilot pipes event JSON on stdin. It contains a stable per-session UUID,
# which is what lets several concurrent agents each own their own LED.
#
# Two things are written:
#   ~/.copilot-kb16-status                 aggregate word -> Hammerspoon dot
#   ~/.copilot-kb16-status.d/<session_id>  per session    -> one LED per agent

set -u

STATE_FILE="$HOME/.copilot-kb16-status"
SESSION_DIR="$HOME/.copilot-kb16-status.d"
STATUS="${1:-idle}"

# Read stdin fully so Copilot's hook pipe never blocks.
PAYLOAD=$(cat 2>/dev/null || true)

# Minimal string-field extraction; avoids depending on jq being installed.
json_field() {
  printf '%s' "$PAYLOAD" |
    sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" |
    head -n 1
}

# Copilot frontends do not agree on field naming, so check both conventions:
#   VS Code Copilot Chat : session_id / hook_event_name  (snake_case)
#   Copilot CLI          : sessionId  / no event field   (camelCase)
# Looking only for session_id silently drops every CLI session -- the menubar
# dot keeps working (it uses the aggregate file) while the LED never lights.
SESSION_ID=$(json_field session_id)
[ -z "$SESSION_ID" ] && SESSION_ID=$(json_field sessionId)

EVENT_RAW=$(json_field hook_event_name)
[ -z "$EVENT_RAW" ] && EVENT_RAW=$(json_field hookEventName)
EVENT=$(printf '%s' "$EVENT_RAW" | tr '[:upper:]' '[:lower:]')

# Where this agent lives, so the host can jump to its window.
#
# Copilot CLI runs in a terminal, so the hook inherits that controlling tty even
# though its stdin is a pipe -- `ps` still reports it, and iTerm2 exposes the
# same value per session, which makes the match exact. The VS Code extension
# host has no tty and reports "??", so those sessions fall back to matching on
# cwd, which can only identify the window, not the chat inside it.
TTY=$(ps -o tty= -p $$ 2>/dev/null | tr -d ' ')
case "$TTY" in
  ttys*) TTY="/dev/$TTY"; CLIENT="cli" ;;
  *)     TTY="-";         CLIENT="vscode" ;;
esac
CWD=$(json_field cwd)

# Opt-in payload capture: `touch ~/.copilot-kb16-debug` to record what each
# client actually sends. Different Copilot frontends (VS Code, CLI) do not
# necessarily emit the same fields, and this is the quickest way to see it.
if [ -e "$HOME/.copilot-kb16-debug" ]; then
  printf '%s\t%s\t%s\t%s\n' \
    "$(date '+%H:%M:%S')" "$STATUS" "${SESSION_ID:-<no-session_id>}" "$PAYLOAD" \
    >> "$HOME/.copilot-kb16-debug.log" 2>/dev/null || true
fi

# Aggregate file keeps the existing single-dot behaviour working unchanged.
printf '%s' "$STATUS" > "$STATE_FILE"

# Per-session file drives one LED each. Reject anything that is not a bare
# UUID, so a malformed or hostile session_id cannot escape SESSION_DIR.
case "$SESSION_ID" in
  "")
    ;;
  *[!0-9a-fA-F-]*)
    ;;
  *)
    mkdir -p "$SESSION_DIR"
    if [ "$EVENT" = "sessionend" ]; then
      # Session is over: drop the file so the bridge frees its LED slot.
      rm -f "$SESSION_DIR/$SESSION_ID"
    else
      # Line 1 is the status, so older readers still work. Lines 2-4 tell the
      # host where to focus when the matching key is pressed.
      printf '%s\n%s\n%s\n%s\n' "$STATUS" "$TTY" "$CWD" "$CLIENT" \
        > "$SESSION_DIR/$SESSION_ID"
    fi
    ;;
esac

# Hooks may emit JSON on stdout; empty object = no changes requested.
printf '{}'
