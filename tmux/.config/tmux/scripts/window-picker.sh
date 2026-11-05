#!/usr/bin/env bash
# fzf window switcher for `prefix f`. Windows flagged by Claude Code's hooks
# (@claude_wait) are marked so the ones waiting for input stand out.
target=$(
  tmux list-windows -a -F '#{session_name}:#{window_index} #{?@claude_wait,⏳ ,}#{window_name}' |
    fzf --reverse --prompt 'window> ' \
      --preview 'tmux capture-pane -ep -t {1}' --preview-window 'right:60%'
) || exit 0
tmux switch-client -t "${target%% *}"
