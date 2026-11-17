#!/usr/bin/env bash
# Picks the directory a new Claude Code window starts in, for `prefix C`. Runs
# in a popup started in the current pane's path. Nothing is hardcoded, so the
# list follows where you actually work:
#   1. the current directory
#   2. every worktree of the current repo
#   3. directories Claude Code has run in, most recent session first; those
#      whose sessions Claude Code has already cleaned up come last
# enter starts a new conversation, ctrl-o continues the directory's last one,
# ctrl-x removes a worktree (worktree-remove.sh). Worktrees show their PR's
# state once GitHub answers, so the list opens without waiting for it.

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
  # A prunable worktree's directory is gone
  git worktree list --porcelain 2>/dev/null |
    awk '/^worktree /{ dir = substr($0, 10); branch = ""; gone = 0 }
      /^branch /{ branch = substr($0, 19) }
      /^prunable/{ gone = 1 }
      /^$/ && !gone { printf "worktree\t%s\t%s\n", dir, branch }'
  claude_dirs
}

# Each worktree branch's latest PR state, looked up the same way as
# worktree-remove.sh does, all branches at once
pr_states() {
  # shellcheck disable=SC2016 # $1 is expanded by the inner sh
  git worktree list --porcelain 2>/dev/null | sed -n 's|^branch refs/heads/||p' |
    xargs -P 8 -I {} sh -c 'printf "%s\t%s\n" "$1" \
      "$(gh pr list --head "$1" --state all --limit 1 --json state -q ".[].state" 2>/dev/null)"' _ {}
}

# `list pr` adds each worktree's PR state. The first listing of a directory
# wins, so the current one keeps its tag
list() {
  {
    [ "$1" = pr ] && pr_states | sed 's/^/pr	/'
    candidates
  } | awk -F'\t' -v home="$HOME" '
    $1 == "pr" { if ($3 != "") state[$2] = tolower($3); next }
    seen[$2]++ { next }
    {
      shown = $2; sub("^" home, "~", shown)
      pr = ($1 == "worktree" && $3 in state) ? "  · PR " state[$3] : ""
      printf "%s\t%-9s %s%s\n", $2, $1, shown, pr
    }'
}

if [ "$1" = list ]; then
  list "$2"
  exit 0
fi

self=${BASH_SOURCE[0]}
# Key hints for the list's bottom edge, styled like the window picker's
key=$'\e[1;38;2;122;162;247m' does=$'\e[22;38;2;115;122;162m' sep=$'\e[38;2;59;66;97m'
keys=" ${key}enter ${does}new conversation  ${sep}·  ${key}ctrl-o ${does}continue its last conversation  ${sep}·  ${key}ctrl-x ${does}remove worktree "
choice=$(
  list |
    fzf --reverse --delimiter '\t' --with-nth 2 --expect ctrl-o \
      --bind "start:reload(\"$self\" list pr)" \
      --bind "ctrl-x:execute(\"$(dirname "$self")/worktree-remove.sh\" ask {1})+reload(\"$self\" list pr)" \
      --style full:sharp --info hidden --input-label ' New Claude window ' \
      --list-label "$keys" --list-label-pos bottom \
      --prompt '❯ ' --pointer '▌' --gutter ' ' --highlight-line \
      --color 'fg:#a9b1d6,fg+:#7aa2f7,bg+:-1,hl:#7aa2f7,hl+:#7aa2f7,prompt:#7aa2f7,pointer:#7aa2f7' \
      --color 'border:#7aa2f7,label:#7aa2f7,query:#c0caf5,gutter:-1'
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
