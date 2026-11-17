#!/usr/bin/env bash
# Jumps to the next Claude window waiting for you, for `prefix a`: one asking a
# question first, then one holding a result you have not seen (tmux.conf's
# @claude_rank). Searches every session, starting after the current window, so
# pressing it again moves on. Arriving marks a result seen, through tmux.conf's
# hooks.

windows=$(tmux list-windows -a -F '#{session_name}:#{window_index}	#{E:@claude_rank}')
current=$(tmux display -p '#{session_name}:#{window_index}')

# The first window of the given rank after the current one, wrapping around
next() {
  awk -F'\t' -v current="$current" -v rank="$1" '
    $1 == current { past = 1; next }
    $2 == rank {
      if (past) { print $1; found = 1; exit }
      if (first == "") first = $1
    }
    END { if (!found && first != "") print first }' <<<"$windows"
}

target=$(next 0)
[ -n "$target" ] || target=$(next 1)
if [ -z "$target" ]; then
  tmux display-message 'No Claude window is waiting for you'
  exit 0
fi
tmux switch-client -t "$target"
