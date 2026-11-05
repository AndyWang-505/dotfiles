#!/usr/bin/env bash
# fzf window switcher for `prefix f`. Windows flagged by Claude Code's hooks
# (@claude_wait) are marked so the ones waiting for input stand out.
# ctrl-x kills the highlighted window and refreshes the list in place.
list="tmux list-windows -a -F '#{session_name}:#{window_index} #{?@claude_wait,⏳ ,}#{window_name} │ #{pane_title}'"
target=$(
  eval "$list" |
    fzf --reverse --prompt 'window> ' --header 'enter: switch  ctrl-x: kill' \
      --bind "ctrl-x:execute-silent(tmux kill-window -t {1})+reload($list)" \
      --preview 'tmux capture-pane -ep -t {1}' --preview-window 'right:60%'
) || exit 0
tmux switch-client -t "${target%% *}"
