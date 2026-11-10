#!/usr/bin/env bash
# Picks the directory a new Claude Code window starts in, for `prefix C`. Runs
# in a popup started in the current pane's path. Nothing is hardcoded, so the
# list follows where you actually work:
#   1. the current directory
#   2. every worktree of the current repo
#   3. directories Claude Code has run in, most recent session first; those
#      whose sessions Claude Code has already cleaned up come last
# enter starts a new conversation, ctrl-o continues the directory's last one.

projects="$HOME/.claude/projects"

# Claude Code keeps each directory's sessions under its path with every
# character other than a letter or digit turned into "-"
history_dir() { printf '%s/%s' "$projects" "$(printf '%s' "$1" | sed 's/[^A-Za-z0-9]/-/g')"; }

last_session() {
  find "$(history_dir "$1")" -maxdepth 1 -name '*.jsonl' -exec stat -f '%m' {} + 2>/dev/null | sort -n | tail -1
}

claude_dirs() {
  jq -r '.projects // {} | keys[]' "$HOME/.claude.json" 2>/dev/null | while IFS= read -r dir; do
    [ -d "$dir" ] || continue
    time=$(last_session "$dir")
    if [ -n "$time" ]; then
      printf '%s\trecent\t%s\n' "$time" "$dir"
    else
      printf '0\tolder\t%s\n' "$dir"
    fi
  done | sort -t "$(printf '\t')" -k1,1rn -k3,3 | cut -f2-
}

candidates() {
  printf 'current\t%s\n' "$PWD"
  git worktree list --porcelain 2>/dev/null | sed -n 's/^worktree /worktree\t/p'
  claude_dirs
}

# The first listing of a directory wins, so the current one keeps its tag
choice=$(
  candidates | awk -F'\t' '!seen[$2]++' |
    awk -F'\t' -v home="$HOME" '{ shown = $2; sub("^" home, "~", shown); printf "%s\t%-9s %s\n", $2, $1, shown }' |
    fzf --reverse --delimiter '\t' --with-nth 2 --expect ctrl-o \
      --prompt 'claude> ' --header 'enter: new conversation  ctrl-o: continue the last one'
) || exit 0

key=$(head -1 <<<"$choice")
dir=$(sed -n 2p <<<"$choice" | cut -f1)
[ -n "$dir" ] || exit 0

if [ "$key" = ctrl-o ]; then
  if [ -z "$(last_session "$dir")" ]; then
    echo "No earlier conversation in $dir"
    read -rsn1 -p 'Press any key to close'
    exit 0
  fi
  tmux new-window -c "$dir" claude --continue
else
  tmux new-window -c "$dir" claude
fi
