#!/usr/bin/env bash
# Jumps to the next Claude window waiting for you, for `prefix a`: one asking a
# question first, then one holding a result you have not seen. Searches every
# session, starting after the current window, so pressing it again moves on.

windows=$(tmux list-windows -a -F '#{session_name}:#{window_index}	#{@claude_wait}')
current=$(tmux display -p '#{session_name}:#{window_index}')

# The first window in the given state after the current one, wrapping around
next() {
  awk -F'\t' -v current="$current" -v state="$1" '
    $1 == current { past = 1; next }
    $2 == state {
      if (past) { print $1; found = 1; exit }
      if (first == "") first = $1
    }
    END { if (!found && first != "") print first }' <<<"$windows"
}

state=ask
target=$(next ask)
if [ -z "$target" ]; then
  state="done"
  target=$(next "done")
fi
if [ -z "$target" ]; then
  tmux display-message 'No Claude window is waiting for you'
  exit 0
fi

tmux switch-client -t "$target"
# session-window-changed does not fire when the window was already the current
# one of its session, so mark the result as seen here
[ "$state" = "done" ] && tmux set -w -t "$target" @claude_wait idle
exit 0
