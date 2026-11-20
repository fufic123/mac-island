#!/bin/bash
# Claude Code status line: saves the subscription usage limits Claude Code passes in
# (.rate_limits: 5-hour and weekly windows) to ~/.mac-island/limits.json for the island, then
# runs the status line the user had before Mac Island, if any, so it still shows.
# Nothing leaves the Mac: Claude Code already has these numbers and hands them to its status line.
DIR="$HOME/.mac-island"
input=$(cat)

limits=$(printf '%s' "$input" | jq -c --argjson now "$(date +%s)" \
  'select(.rate_limits != null) | {updated_at: $now, rate_limits: .rate_limits}' 2>/dev/null)
if [ -n "$limits" ]; then
  tmp=$(mktemp "$DIR/limits.XXXXXX" 2>/dev/null) && printf '%s\n' "$limits" > "$tmp" && mv -f "$tmp" "$DIR/limits.json"
fi

original="$DIR/statusline-original.json"
if [ -f "$original" ]; then
  cmd=$(jq -r '.command // empty' "$original" 2>/dev/null)
  [ -n "$cmd" ] && printf '%s' "$input" | /bin/bash -c "$cmd"
fi
exit 0
