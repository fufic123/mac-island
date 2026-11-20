#!/usr/bin/env bash
# Installs (or with --uninstall removes) the Mac Island hooks in ~/.claude/settings.json, plus a
# status line that hands the island the subscription usage limits. A status line you already had
# keeps showing: ours runs it, and --uninstall puts it back.
# Idempotent: existing Mac Island entries are replaced, other hooks are left untouched.
set -euo pipefail

# The hook script sits next to this one (scripts/ in the repo, Resources/ in the app bundle).
SRC="$(cd "$(dirname "$0")" && pwd)/island-hook.sh"
STATUS_SRC="$(cd "$(dirname "$0")" && pwd)/island-statusline.sh"
DIR="$HOME/.mac-island"
HOOK="$DIR/hook.sh"
STATUS="$DIR/statusline.sh"
ORIGINAL_STATUS="$DIR/statusline-original.json"
SETTINGS="$HOME/.claude/settings.json"
INSTALL=true
for arg in "$@"; do
  case "$arg" in
    --uninstall) INSTALL=false ;;
    --copy) ;; # Kept for older callers; the hook is always copied now.
  esac
done

EVENTS='["SessionStart","SessionEnd","UserPromptSubmit","PreToolUse","PostToolUse","PermissionRequest","Notification","Stop","StopFailure","SubagentStart","SubagentStop"]'
TOOL_EVENTS='["PreToolUse","PostToolUse","PermissionRequest"]'

if $INSTALL; then
  mkdir -p "$DIR"
  # Always a copy, never a symlink into the checkout: Claude Desktop runs Claude Code without
  # access to ~/Documents, so a hook that lives there fails with "Operation not permitted".
  rm -f "$HOOK"
  cp "$SRC" "$HOOK"
  chmod +x "$HOOK"
  rm -f "$STATUS"
  cp "$STATUS_SRC" "$STATUS"
  chmod +x "$STATUS"
fi

mkdir -p "$(dirname "$SETTINGS")"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
cp "$SETTINGS" "$SETTINGS.bak"

# Someone else's status line is kept aside for ours to run (and to restore on uninstall).
current_status=$(jq -c '.statusLine // empty' "$SETTINGS")
if $INSTALL && [ -n "$current_status" ] && ! printf '%s' "$current_status" | grep -q '.mac-island/statusline.sh'; then
  printf '%s\n' "$current_status" > "$ORIGINAL_STATUS"
fi
original_status=$( [ -f "$ORIGINAL_STATUS" ] && cat "$ORIGINAL_STATUS" || echo null)

tmp=$(mktemp)
jq --arg cmd "$HOOK" --arg status "$STATUS" --argjson original "$original_status" --argjson events "$EVENTS" --argjson toolEvents "$TOOL_EVENTS" --argjson install "$INSTALL" '
  def ours: (.command // "") | contains(".mac-island/hook.sh");
  def strip: map(.hooks |= map(select(ours | not))) | map(select(.hooks | length > 0));
  # PermissionRequest waits for Allow/Deny from the island, as long as a terminal prompt would.
  def entry($e):
    { hooks: [{ type: "command", command: $cmd, timeout: (if $e == "PermissionRequest" then 86400 else 5 end) }] }
    + (if ($toolEvents | index($e)) then { matcher: "*" } else {} end);
  # Background Stop hook that waits for a reply typed in the island and wakes Claude with it.
  # Without a long timeout Claude kills it after 10 minutes and later replies go nowhere.
  def awaitEntry:
    { hooks: [{ type: "command", command: ($cmd + " --await-reply"), async: true, asyncRewake: true, timeout: 86400 }] };
  .hooks = (.hooks // {})
  | reduce $events[] as $e (.;
      .hooks[$e] = (((.hooks[$e] // []) | strip)
        + (if $install then [entry($e)] + (if $e == "Stop" then [awaitEntry] else [] end) else [] end)))
  | .hooks |= with_entries(select(.value | length > 0))
  | if (.hooks | length) == 0 then del(.hooks) else . end
  | if $install then
      .statusLine = ({ type: "command", command: $status } + (if $original.padding != null then { padding: $original.padding } else {} end))
    elif ((.statusLine.command // "") | contains(".mac-island/statusline.sh")) then
      (if $original != null then .statusLine = $original else del(.statusLine) end)
    else . end
' "$SETTINGS" > "$tmp"
mv "$tmp" "$SETTINGS"

if $INSTALL; then
  echo "Installed Mac Island hooks -> $HOOK (backup: $SETTINGS.bak)"
else
  rm -f "$HOOK" "$STATUS" "$ORIGINAL_STATUS" "$DIR/limits.json"
  echo "Removed Mac Island hooks (backup: $SETTINGS.bak)"
fi
