#!/bin/bash
# Claude Code hook: forwards the hook's JSON payload to Mac Island over a Unix socket.
# Must never block or fail Claude, so every error path exits 0.
SOCK="$HOME/.mac-island/island.sock"
[ -S "$SOCK" ] || exit 0

payload=$(cat)
[ -n "$payload" ] || exit 0

# Controlling terminal of the Claude process (inherited by this hook), e.g. "ttys004".
tty=$(ps -o tty= -p $$ 2>/dev/null | tr -d ' ')
[ "$tty" = "??" ] && tty=""

printf '%s' "$payload" \
  | jq -c --arg term "${TERM_PROGRAM:-}" --arg tty "$tty" \
      '{source: "claude", term_program: $term, tty: $tty, payload: .}' 2>/dev/null \
  | nc -U -w 1 "$SOCK" >/dev/null 2>&1
exit 0
