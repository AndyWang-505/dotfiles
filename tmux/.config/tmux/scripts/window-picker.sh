#!/usr/bin/env bash
# fzf window switcher for `prefix f`. Windows flagged by Claude Code's hooks
# (@claude_wait) are marked so the ones waiting for input stand out.
# ctrl-x kills the highlighted window and refreshes the list in place.
# The cursor starts on the window you opened the picker from.
list="tmux list-windows -a -F '#{session_name}:#{window_index} #{?#{==:#{@claude_wait},ask},💬 ,#{?#{==:#{@claude_wait},done},✅ ,#{?#{==:#{@claude_wait},running},🔄 ,#{?#{==:#{@claude_wait},idle},💤 ,}}}}#{window_name} │ #{pane_title}'"
windows=$(eval "$list")
current=$(tmux display -p '#{session_name}:#{window_index}')
position=$(awk -v window="$current" '$1 == window { print NR; exit }' <<<"$windows")
target=$(
  printf '%s\n' "$windows" |
    fzf --reverse --prompt 'window> ' --header 'enter: switch  ctrl-x: kill' \
      --bind "start:pos(${position:-1})" \
      --bind "ctrl-x:execute-silent(tmux kill-window -t {1})+reload($list)" \
      --preview 'tmux capture-pane -ep -t {1}' --preview-window 'right:60%'
) || exit 0
tmux switch-client -t "${target%% *}"
