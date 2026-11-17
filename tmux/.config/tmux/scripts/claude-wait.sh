#!/usr/bin/env bash
# Claude Code hook that sets the per-window @claude_wait flag tmux.conf turns
# into status bar marks. Wired up in ~/.claude/settings.json:
#   Notification -> ask, Stop -> done, UserPromptSubmit / PostToolUse -> run,
#   SessionStart -> idle, SessionEnd -> clear
# `claude-wait.sh snapshot` only rewrites the list below, for window-picker.sh
# after it kills a window.

# Each pane remembers the conversation it runs and the directory Claude started
# in, and every tmux server keeps a list of its running conversations, so
# claude-resume.sh can bring them back after the server goes down. The list is
# rewritten from the live panes; while the server is shutting down that listing
# fails and the last list stays.
sessions=${XDG_STATE_HOME:-$HOME/.local/state}/tmux/claude-sessions
remember() {
  local session cwd
  session=$(jq -r '.session_id // empty' <<<"$input" 2>/dev/null)
  [ -n "$session" ] || return
  [ "$session" = "$(tmux show -pv -t "$TMUX_PANE" @claude_session 2>/dev/null)" ] && return
  tmux set -p -t "$TMUX_PANE" @claude_session "$session"
  # Set once, from the directory Claude started in: its conversations stay
  # filed under it after Claude cd's elsewhere. /clear unsets it
  if [ -z "$(tmux show -pv -t "$TMUX_PANE" @claude_dir 2>/dev/null)" ]; then
    cwd=$(jq -r '.cwd // empty' <<<"$input" 2>/dev/null)
    tmux set -p -t "$TMUX_PANE" @claude_dir "${cwd:-$PWD}"
  fi
}
# Named by socket, server start time and pid: claude-resume.sh only takes lists
# from its own socket, and a new server that happens to reuse an old pid does
# not overwrite the old list. Hooks from several panes can run at once, so each
# writes its own temporary file before moving it into place.
snapshot() {
  local server panes
  server=$(tmux display -p '#{b:socket_path}-#{start_time}-#{pid}') || return
  panes=$(tmux list-panes -a -F '#{@claude_session}	#{@claude_dir}	#{session_name}') || return
  mkdir -p "$sessions" &&
    awk -F'\t' '$1 != "" && !seen[$1]++' <<<"$panes" >"$sessions/.$server.$$" &&
    mv "$sessions/.$server.$$" "$sessions/$server.tsv"
}

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
  message=$(jq -r '.message // empty' <<<"$input" 2>/dev/null)
  # Control characters would end the escape sequence and a ; in the title would
  # be read as the start of the body
  title=$(printf '💬 %s · %s' "$target" "$label" | tr -d '\000-\037;')
  body=$(printf '%s' "${message:-Claude is waiting for you}" | tr -d '\000-\037')
  tmux list-clients -t "$TMUX_PANE" -F '#{client_tty}' | while read -r client_tty; do
    printf '\033]777;notify;%s;%s\a' "$title" "$body" >"$client_tty"
  done
}

if [ "$1" = snapshot ]; then
  snapshot
  exit 0
fi
[ -n "$TMUX_PANE" ] || exit 0
input=$(cat)
[ "$1" = clear ] || remember

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
  # Only a conversation you ended leaves the list. Any other reason, such as
  # the SIGTERM a shutdown sends before tmux goes down, keeps it so it comes
  # back; a killed window drops out anyway, since its pane is gone
  case "$(jq -r '.reason // empty' <<<"$input" 2>/dev/null)" in
  prompt_input_exit | clear | logout)
    tmux set -pu -t "$TMUX_PANE" @claude_session \; set -pu -t "$TMUX_PANE" @claude_dir
    ;;
  esac
  ;;
esac
snapshot
exit 0
