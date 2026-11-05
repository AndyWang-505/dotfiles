#!/usr/bin/env bash
# Claude Code hook that sets the per-window @claude_wait flag tmux.conf turns
# into status bar marks. Wired up in ~/.claude/settings.json:
#   Notification -> ask, Stop -> done, UserPromptSubmit / PostToolUse -> clear
[ -n "$TMUX_PANE" ] || exit 0

case "$1" in
ask)
  # Claude also notifies after sitting idle, which must not turn an unseen
  # "done" back into a question
  [ "$(tmux show -wv -t "$TMUX_PANE" @claude_wait 2>/dev/null)" = done ] ||
    tmux set -w -t "$TMUX_PANE" @claude_wait ask
  ;;
done)
  # The window is already on screen, so nothing is left unseen to flag
  [ "$(tmux display -p -t "$TMUX_PANE" '#{&&:#{window_active},#{session_attached}}')" = 1 ] ||
    tmux set -w -t "$TMUX_PANE" @claude_wait done
  ;;
clear)
  tmux set -wu -t "$TMUX_PANE" @claude_wait
  ;;
esac
exit 0
