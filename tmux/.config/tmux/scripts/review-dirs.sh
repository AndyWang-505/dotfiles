#!/usr/bin/env bash
# Claude Code PostToolUse hook for Edit / Write / MultiEdit / NotebookEdit.
# Remembers which repos or worktrees Claude edited from this tmux window, so
# review.sh can offer them even when they are not the window's own directory
# (autofix worktrees, EnterWorktree, other projects).
# The list lives in the window option @review_dirs, newest first, one per line.
[ -n "$TMUX_PANE" ] || exit 0

file=$(jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' 2>/dev/null)
[ -n "$file" ] || exit 0

root=$(git -C "$(dirname "$file")" rev-parse --show-toplevel 2>/dev/null) || exit 0

old=$(tmux show -wv -t "$TMUX_PANE" @review_dirs 2>/dev/null)
new=$(printf '%s\n%s\n' "$root" "$old" | awk 'NF && !seen[$0]++' | head -10)
tmux set -w -t "$TMUX_PANE" @review_dirs "$new"
