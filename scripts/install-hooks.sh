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

EVENTS='["SessionStart","SessionEnd","UserPromptSubmit","PreToolUse","PostToolUse","PermissionRequest","Notification","Stop","SubagentStart","SubagentStop"]'
TOOL_EVENTS='["PreToolUse","PostToolUse","PermissionRequest"]'

if $INSTALL; then
  mkdir -p "$DIR"
  chmod +x scripts/island-hook.sh
  # Symlink, so edits to the hook in the repo take effect without reinstalling.
  ln -sf "$PWD/scripts/island-hook.sh" "$HOOK"
fi

mkdir -p "$(dirname "$SETTINGS")"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
cp "$SETTINGS" "$SETTINGS.bak"

tmp=$(mktemp)
jq --arg cmd "$HOOK" --argjson events "$EVENTS" --argjson toolEvents "$TOOL_EVENTS" --argjson install "$INSTALL" '
  def ours: (.command // "") | contains(".mac-island/hook.sh");
  def strip: map(.hooks |= map(select(ours | not))) | map(select(.hooks | length > 0));
  # PermissionRequest waits for Allow/Deny from the island, as long as a terminal prompt would.
  def entry($e):
    { hooks: [{ type: "command", command: $cmd, timeout: (if $e == "PermissionRequest" then 86400 else 5 end) }] }
    + (if ($toolEvents | index($e)) then { matcher: "*" } else {} end);
  # Background Stop hook that waits for a reply typed in the island and wakes Claude with it.
  def awaitEntry:
    { hooks: [{ type: "command", command: ($cmd + " --await-reply"), async: true, asyncRewake: true }] };
  .hooks = (.hooks // {})
  | reduce $events[] as $e (.;
      .hooks[$e] = (((.hooks[$e] // []) | strip)
        + (if $install then [entry($e)] + (if $e == "Stop" then [awaitEntry] else [] end) else [] end)))
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
