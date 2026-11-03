#!/usr/bin/env bash
# Installs (or with --uninstall removes) the Mac Island hooks in ~/.claude/settings.json.
# Idempotent: existing Mac Island entries are replaced, other hooks are left untouched.
set -euo pipefail

cd "$(dirname "$0")/.."
DIR="$HOME/.mac-island"
HOOK="$DIR/hook.sh"
SETTINGS="$HOME/.claude/settings.json"
INSTALL=true
[ "${1:-}" = "--uninstall" ] && INSTALL=false

EVENTS='["SessionStart","SessionEnd","UserPromptSubmit","PreToolUse","PostToolUse","PermissionRequest","Notification","Stop","SubagentStop"]'
TOOL_EVENTS='["PreToolUse","PostToolUse","PermissionRequest"]'

if $INSTALL; then
  mkdir -p "$DIR"
  cp scripts/island-hook.sh "$HOOK"
  chmod +x "$HOOK"
fi

mkdir -p "$(dirname "$SETTINGS")"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
cp "$SETTINGS" "$SETTINGS.bak"

tmp=$(mktemp)
jq --arg cmd "$HOOK" --argjson events "$EVENTS" --argjson toolEvents "$TOOL_EVENTS" --argjson install "$INSTALL" '
  def ours: (.command // "") | contains(".mac-island/hook.sh");
  def strip: map(.hooks |= map(select(ours | not))) | map(select(.hooks | length > 0));
  def entry($e):
    { hooks: [{ type: "command", command: $cmd, timeout: 5 }] }
    + (if ($toolEvents | index($e)) then { matcher: "*" } else {} end);
  .hooks = (.hooks // {})
  | reduce $events[] as $e (.;
      .hooks[$e] = (((.hooks[$e] // []) | strip) + (if $install then [entry($e)] else [] end)))
  | .hooks |= with_entries(select(.value | length > 0))
  | if (.hooks | length) == 0 then del(.hooks) else . end
' "$SETTINGS" > "$tmp"
mv "$tmp" "$SETTINGS"

if $INSTALL; then
  echo "Installed Mac Island hooks -> $HOOK (backup: $SETTINGS.bak)"
else
  rm -f "$HOOK"
  echo "Removed Mac Island hooks (backup: $SETTINGS.bak)"
fi
