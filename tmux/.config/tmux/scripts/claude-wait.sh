#!/usr/bin/env bash
# Claude Code hook that sets the per-window @claude_wait flag tmux.conf turns
# into status bar marks. Wired up in ~/.claude/settings.json:
#   Notification -> ask, Stop -> done, UserPromptSubmit / PostToolUse -> run,
#   SessionStart -> idle, SessionEnd -> clear
[ -n "$TMUX_PANE" ] || exit 0

case "$1" in
ask)
  # Claude also notifies after sitting idle, which must not turn a finished
  # or idle session back into a question
  case "$(tmux show -wv -t "$TMUX_PANE" @claude_wait 2>/dev/null)" in
  done | idle) ;;
  *) tmux set -w -t "$TMUX_PANE" @claude_wait ask ;;
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
    tmux set -w -t "$TMUX_PANE" @claude_wait done
  fi
  ;;
clear)
  tmux set -wu -t "$TMUX_PANE" @claude_wait
  ;;
esac
exit 0
