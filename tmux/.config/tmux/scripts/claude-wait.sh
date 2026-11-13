#!/usr/bin/env bash
# Claude Code hook that sets the per-window @claude_wait flag tmux.conf turns
# into status bar marks. Wired up in ~/.claude/settings.json:
#   Notification -> ask, Stop -> done, UserPromptSubmit / PostToolUse -> run,
#   SessionStart -> idle, SessionEnd -> clear
[ -n "$TMUX_PANE" ] || exit 0

# Desktop notification for a question, skipped when the window is already in
# front of you. The OSC 777 sequence is written straight to the attached
# clients' terminals, so Ghostty shows it without tmux passthrough.
notify() {
  [ "$(tmux display -p -t "$TMUX_PANE" '#{window_active}')" = 1 ] &&
    tmux list-clients -t "$TMUX_PANE" -F '#{client_flags}' | grep -q focused &&
    return
  local target label message title body client_tty
  target=$(tmux display -p -t "$TMUX_PANE" '#{session_name}:#{window_index}')
  label=$(tmux display -p -t "$TMUX_PANE" '#{?@claude_label,#{@claude_label},#{s/^. //:pane_title}}')
  message=$(jq -r '.message // empty' 2>/dev/null)
  # Control characters would end the escape sequence and a ; in the title would
  # be read as the start of the body
  title=$(printf '💬 %s · %s' "$target" "$label" | tr -d '\000-\037;')
  body=$(printf '%s' "${message:-Claude is waiting for you}" | tr -d '\000-\037')
  tmux list-clients -t "$TMUX_PANE" -F '#{client_tty}' | while read -r client_tty; do
    printf '\033]777;notify;%s;%s\a' "$title" "$body" >"$client_tty"
  done
}

case "$1" in
ask)
  # Claude also notifies after sitting idle, which must not turn a finished
  # or idle session back into a question
  case "$(tmux show -wv -t "$TMUX_PANE" @claude_wait 2>/dev/null)" in
  done | idle) ;;
  *)
    tmux set -w -t "$TMUX_PANE" @claude_wait ask
    notify
    ;;
  esac
  ;;
run)
  tmux set -w -t "$TMUX_PANE" @claude_wait running
  ;;
idle)
  tmux set -w -t "$TMUX_PANE" @claude_wait idle
  ;;
done)
  # The window is already on screen, so nothing is left unseen to flag
  if [ "$(tmux display -p -t "$TMUX_PANE" '#{&&:#{window_active},#{session_attached}}')" = 1 ]; then
    tmux set -w -t "$TMUX_PANE" @claude_wait idle
  else
    tmux set -w -t "$TMUX_PANE" @claude_wait "done"
  fi
  ;;
clear)
  tmux set -wu -t "$TMUX_PANE" @claude_wait
  ;;
esac
exit 0
