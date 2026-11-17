#!/usr/bin/env bash
# Brings back the Claude conversations that were open when the previous tmux
# server went down; tmux.conf runs it as the server starts. claude-wait.sh keeps
# one list per server, named <start time>-<pid>; this reads the newest one from
# a server that is no longer running. Each conversation opens as a new window in
# the session it was in, which is created if missing. Prints nothing, since
# tmux would show any output in a pane.

dir=${XDG_STATE_HOME:-$HOME/.local/state}/tmux/claude-sessions

# A list belongs to a running server when its pid is still a tmux process; a
# second server (tmux -L) is left alone
running_server() {
  local pid=${1##*-}
  [ "$(ps -p "$pid" -o comm= 2>/dev/null | sed 's|.*/||')" = tmux ]
}

list=
stale=()
for file in "$dir"/*.tsv; do
  [ -e "$file" ] || continue
  running_server "$(basename "$file" .tsv)" && continue
  stale+=("$file")
  { [ -z "$list" ] || [ "$file" -nt "$list" ]; } && list=$file
done
[ -n "$list" ] || exit 0

# Claude Code keeps each directory's conversations under its path with every
# character other than a letter or digit turned into "-". A conversation that
# never got a message has no file there, and `claude --resume` would exit at once
transcript() {
  printf '%s/.claude/projects/%s/%s.jsonl' "$HOME" "$(printf '%s' "$1" | sed 's/[^A-Za-z0-9]/-/g')" "$2"
}

running=$(tmux list-panes -a -F '#{@claude_session}')
while IFS=$'\t' read -r session cwd name; do
  [ -n "$session" ] && [ -d "$cwd" ] && [ -f "$(transcript "$cwd" "$session")" ] || continue
  grep -qxF "$session" <<<"$running" && continue
  tmux has-session -t "=$name" 2>/dev/null || tmux new-session -d -s "$name" -c "$cwd"
  tmux new-window -d -t "=$name:" -c "$cwd" claude --resume "$session"
done <"$list"

# Lists from servers that are gone are used up, older ones included
rm -f "${stale[@]}"
