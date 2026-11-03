#!/bin/bash
# Claude Code hook: forwards the hook's JSON payload to Mac Island over a Unix socket.
# Must never block or fail Claude, so every error path exits 0.
# For PermissionRequest it waits for the island's Allow/Deny and prints that decision;
# if the island answers nothing (or isn't running), Claude's normal prompt applies.
SOCK="$HOME/.mac-island/island.sock"
[ -S "$SOCK" ] || exit 0

payload=$(cat)
[ -n "$payload" ] || exit 0

# Controlling terminal of the Claude process (inherited by this hook), e.g. "ttys004".
tty=$(ps -o tty= -p $$ 2>/dev/null | tr -d ' ')
[ "$tty" = "??" ] && tty=""

# Claude's own pid: the first ancestor that isn't the shell wrapping this hook.
pid=$PPID
for _ in 1 2 3 4; do
  comm=$(ps -o comm= -p "$pid" 2>/dev/null) || break
  case "${comm##*/}" in
    sh|bash|zsh|dash|-sh|-bash|-zsh) pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ') ;;
    *) break ;;
  esac
done
case "$pid" in ''|*[!0-9]*) pid=null ;; esac

event=$(printf '%s' "$payload" | jq -r '.hook_event_name // empty' 2>/dev/null)
cwd=$(printf '%s' "$payload" | jq -r '.cwd // empty' 2>/dev/null)

# Resolved here rather than in the app: the terminal already has access to protected
# folders like ~/Documents, while the app reading them would trigger a TCC prompt.
branch=""
if [ -n "$cwd" ]; then
  branch=$(git -C "$cwd" symbolic-ref --short -q HEAD 2>/dev/null || git -C "$cwd" rev-parse --short HEAD 2>/dev/null)
fi

envelope=$(printf '%s' "$payload" \
  | jq -c --arg term "${TERM_PROGRAM:-}" --arg tty "$tty" --argjson pid "$pid" --arg branch "$branch" \
      '{source: "claude", term_program: $term, tty: $tty, claude_pid: $pid, git_branch: $branch, payload: .}' 2>/dev/null)
[ -n "$envelope" ] || exit 0

if [ "$event" = "PermissionRequest" ]; then
  # Blocks until the island replies or drops the connection; the reply is the hook's output.
  printf '%s\n' "$envelope" | nc -U "$SOCK" 2>/dev/null
else
  printf '%s\n' "$envelope" | nc -U -w 1 "$SOCK" >/dev/null 2>&1
fi
exit 0
