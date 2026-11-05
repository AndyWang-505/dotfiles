#!/usr/bin/env bash
# fzf window switcher for `prefix f`. Windows flagged by Claude Code's hooks
# (@claude_wait) are marked so the ones waiting for input stand out.
# ctrl-x kills the highlighted window and refreshes the list in place.
# The cursor starts on the window you opened the picker from.

if [ "$1" = kill ]; then
  # A Claude window that is running, waiting for an answer or holding an
  # unread result would lose that work, so it takes a confirmation
  case "$(tmux show -wv -t "$2" @claude_wait 2>/dev/null)" in
  running | ask | done)
    printf 'Claude is still active in %s. Kill it? [y/N] ' "$2"
    read -rn1 answer
    [ "$answer" = y ] || exit 0
    ;;
  esac
  tmux kill-window -t "$2"
  exit 0
fi

list="tmux list-windows -a -F '#{session_name}:#{window_index} #{?#{==:#{@claude_wait},ask},💬 ,#{?#{==:#{@claude_wait},done},✅ ,#{?#{==:#{@claude_wait},running},🔄 ,#{?#{==:#{@claude_wait},idle},💤 ,}}}}#{window_name} │ #{pane_title}'"
windows=$(eval "$list")
current=$(tmux display -p '#{session_name}:#{window_index}')
position=$(awk -v window="$current" '$1 == window { print NR; exit }' <<<"$windows")
target=$(
  printf '%s\n' "$windows" |
    fzf --sync --reverse --prompt 'window> ' --header 'enter: switch  ctrl-x: kill (asks first if Claude is active)' \
      --bind "start:pos(${position:-1})" \
      --bind "ctrl-x:execute(\"${BASH_SOURCE[0]}\" kill {1})+reload($list)" \
      --preview 'tmux capture-pane -ep -t {1}' --preview-window 'right:60%'
) || exit 0
tmux switch-client -t "${target%% *}"
