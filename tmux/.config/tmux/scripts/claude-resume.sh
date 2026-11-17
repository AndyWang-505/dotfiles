#!/usr/bin/env bash
# Brings back the Claude conversations that were open when the previous tmux
# server went down; tmux.conf runs it as the server starts. claude-wait.sh keeps
# one list per server, named <socket>-<start time>-<pid>; this reads the newest
# one from a server on the same socket that is no longer running, so a second
# server (tmux -L) never takes the main one's conversations. Each conversation
# opens as a new window in the session it was in, which is created if missing.
# Prints nothing, since tmux would show any output in a pane.

# shellcheck source-path=SCRIPTDIR
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
dir=$state_dir/claude-sessions
# The server has no session yet, so the socket comes from $TMUX
socket=$(basename "${TMUX%%,*}")

# A list belongs to a running server when its pid is still a tmux process
running_server() {
  local pid=${1##*-}
  [ "$(ps -p "$pid" -o comm= 2>/dev/null | sed 's|.*/||')" = tmux ]
}

list=
stale=()
for file in "$dir/$socket"-*.tsv; do
  [ -e "$file" ] || continue
  base=$(basename "$file" .tsv)
  # A socket named like this one plus "-something" matches the glob too
  [ "${base%-*-*}" = "$socket" ] || continue
  running_server "$base" && continue
  stale+=("$file")
  { [ -z "$list" ] || [ "$file" -nt "$list" ]; } && list=$file
done
[ -n "$list" ] || exit 0

# A conversation that never got a message has no transcript, and
# `claude --resume` would exit at once
transcript() { printf '%s/%s.jsonl' "$(claude_project_dir "$1")" "$2"; }

running=$(tmux list-panes -a -F '#{@claude_session}')
while IFS=$'\t' read -r session cwd name; do
  [ -n "$session" ] && [ -d "$cwd" ] && [ -f "$(transcript "$cwd" "$session")" ] || continue
  grep -qxF "$session" <<<"$running" && continue
  if tmux has-session -t "=$name" 2>/dev/null; then
    tmux new-window -d -t "=$name:" -c "$cwd" claude --resume "$session"
  else
    tmux new-session -d -s "$name" -c "$cwd" claude --resume "$session"
  fi
done <"$list"

# Lists from servers that are gone are used up, older ones included
rm -f "${stale[@]}"
