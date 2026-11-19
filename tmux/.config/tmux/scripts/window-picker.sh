#!/usr/bin/env bash
# Window switcher for `prefix f` / cmd+p. Windows that need you come first:
# Claude questions, then finished turns you have not seen, then the rest. The
# cursor starts on the first of them, or else on the window you came from.
# ctrl-x closes the highlighted window. Windows are picked by tmux window id
# (@3): their numbers shift as windows close

here=$(dirname "${BASH_SOURCE[0]}")
# shellcheck source-path=SCRIPTDIR
. "$here/lib.sh"

# The text colour of everything secondary, tmux.conf's idle mark colour
dim=$(hex_fg "$(tmux show -gv @mark_idle_fg)")

# The directory the picker shows for a window, and ctrl-x offers to remove: the
# repo or worktree Claude last edited from it (review-dirs.sh), which for a
# session started in the main repo is the worktree it works in; otherwise, or
# once that is removed, as autofix does when it is done, the pane's own. Both
# fields are - when empty
dir_fields='#{?@review_dir,#{@review_dir},-}	#{?pane_current_path,#{pane_current_path},-}'
#   shown_dir <edited> <own>
shown_dir() {
  if [ "$1" != - ] && [ -d "$1" ]; then
    printf '%s' "$1"
  else
    printf '%s' "$2"
  fi
}

# Each window's Claude conversation, from the pane that runs it rather than
# the window's active one: "window id <tab> session <tab> dir <tab> transcript"
claude_panes() {
  tmux list-panes "${@:--a}" -F '#{window_id}	#{@claude_session}	#{@claude_dir}	#{@claude_transcript}' |
    awk -F'\t' '$2 != "" && !seen[$1]++'
}

# The subagents a window's Claude conversation is running (claude-agents.sh)
#   window_agents <window id>
window_agents() {
  local session dir transcript
  IFS=$'\t' read -r _ session dir transcript < <(claude_panes -t "$1")
  [ -z "$session" ] || "$here/claude-agents.sh" "$(claude_agents_dir "$session" "$dir" "$transcript")"
}

if [ "$1" = kill ]; then
  name=$(tmux display -p -t "$2" '#{session_name}:#{window_index}') || exit 0
  # Closing a Claude window that is working, asking or holding an unread
  # result loses that work, so it asks first
  case "$(tmux show -wv -t "$2" @claude_wait 2>/dev/null)" in
  running | ask | done)
    printf 'Claude is still active in %s. Kill it? [y/N] ' "$name"
    read -rn1 answer
    [ "$answer" = y ] || exit 0
    ;;
  esac
  IFS=$'\t' read -r edited own < <(tmux display -p -t "$2" "$dir_fields")
  path=$(shown_dir "$edited" "$own")
  # Off the resume list first: closing the server's last window ends tmux
  # before its own hook could do it
  "$here/claude-wait.sh" snapshot "$2"
  tmux kill-window -t "$2"
  # Then offers to remove the worktree it ran in, if nothing would be lost
  "$here/worktree-remove.sh" offer "$path"
  exit 0
fi

# Windows by how much they need you (tmux.conf's @claude_rank), otherwise in
# tmux's order. Fields: window id, session:index, mark (- when none), the
# directory shown_dir picks, title
ranked() {
  tmux list-windows -a -F "#{E:@claude_rank}	#{window_id}	#{session_name}:#{window_index}	#{?@claude_wait,#{@claude_wait},-}	$dir_fields	#{E:@win_title}" |
    sort -s -n -k1,1 | cut -f2- |
    while IFS=$'\t' read -r id target mark edited own title; do
      printf '%s\t%s\t%s\t%s\t%s\n' "$id" "$target" "$mark" "$(shown_dir "$edited" "$own")" "$title"
    done
}

# Each shown directory's branch, once per directory while the picker is open:
# "directory <tab> branch, or removed <tab> directory with ~" per line. Lines
# already in the cache file are reused, new ones added to it
#   branch_lines <rows> [cache file]
branch_lines() {
  local branches line dir
  branches=$(cat "$2" 2>/dev/null)
  while IFS=$'\t' read -r _ _ _ dir _; do
    case $'\n'$branches$'\n' in *$'\n'"$dir"$'\t'*) continue ;; esac
    # The pane's own directory removed from under it says so
    if [ -d "$dir" ]; then
      line="$dir"$'\t'$(git -C "$dir" branch --show-current 2>/dev/null)$'\t'$(tilde "$dir")
    else
      line="$dir"$'\t'removed$'\t'$(tilde "$dir")
    fi
    branches+=$'\n'$line
    [ -z "$2" ] || printf '%s\n' "$line" >>"$2"
  done <<<"$1"
  printf '%s\n' "$branches"
}

# How many subagents each window runs: "window id <tab> count" per line
agent_counts() {
  local window session dir transcript count
  claude_panes | while IFS=$'\t' read -r window session dir transcript; do
    count=$("$here/claude-agents.sh" "$(claude_agents_dir "$session" "$dir" "$transcript")" | wc -l)
    [ "$count" -eq 0 ] || printf '%s\t%d\n' "$window" "$count"
  done
}

# Each mark as tmux.conf defines it, coloured: "state <tab> mark" per line
mark_escapes() {
  local format='' state icon fg
  for state in ask 'done' running idle; do
    format+="$state	#{@mark_$state}	#{@mark_${state}_fg}"$'\n'
  done
  tmux display -p "$format" |
    while IFS=$'\t' read -r state icon fg; do
      printf '%s\t%s%s\n' "$state" "$(hex_fg "$fg")" "$icon"
    done
}

# The picker's items, two lines each: the mark and title, then session:index,
# directory and branch. Marks match the status bar, except that working does
# not spin: animating the list would redraw it every second and make the text
# cursor jump. Branches are looked up once per directory while it is open.
#   window-picker.sh list [branch cache]
if [ "$1" = list ]; then
  rows=$(ranked)
  AGENTS=$(agent_counts) BRANCHES=$(branch_lines "$rows" "$2") MARKS=$(mark_escapes) DIM=$dim awk -F'\t' '
    BEGIN {
      n = split(ENVIRON["BRANCHES"], lines, "\n")
      for (i = 1; i <= n; i++) { split(lines[i], f, "\t"); branch[f[1]] = f[2]; shown[f[1]] = f[3] }
      n = split(ENVIRON["MARKS"], lines, "\n")
      for (i = 1; i <= n; i++) { split(lines[i], f, "\t"); mark[f[1]] = f[2] }
      n = split(ENVIRON["AGENTS"], lines, "\n")
      for (i = 1; i <= n; i++) { split(lines[i], f, "\t"); agents[f[1]] = f[2] }
      dim = ENVIRON["DIM"]; reset = "\033[0m"
      branch_fg = "\033[38;2;157;124;216m"; removed_fg = "\033[38;2;219;75;75m"
    }
    {
      id = $1; target = $2; state = $3; dir = $4; title = $5
      icon = state in mark ? mark[state] : " "
      # Each field after the window is named by its icon and colour, as the
      # shell prompt and Neovim show them:  directory,  branch, subagents
      extra = ""
      if (branch[dir] == "removed") extra = "   " removed_fg " removed" dim
      else if (branch[dir] != "") extra = "   " branch_fg " " branch[dir] dim
      if (id in agents) extra = extra "   " mark["running"] " " agents[id] (agents[id] > 1 ? " agents" : " agent") dim
      printf "%s\t %s%s  \033[1m%s%s\n    %s%s    %s%s%s%c", id, icon, reset, title, reset, dim, target, shown[dir], extra, reset, 0
    }' <<<"$rows"
  exit 0
fi

# The preview: the window's running subagents, if any, above its screen. The
# screen loses as many lines from its top, so Claude's prompt stays in view
#   window-picker.sh preview <window id>
if [ "$1" = preview ]; then
  rows=$(window_agents "$2")
  if [ -n "$rows" ]; then
    IFS=$'\t' read -r icon fg < <(tmux display -p '#{@mark_running}	#{@mark_running_fg}')
    colour=$(hex_fg "$fg")
    while IFS=$'\t' read -r description tool secs; do
      [ "$tool" != - ] || tool=
      printf '%s%s\033[0m \033[1m%s\033[0m\n    %s%s%dm%02ds\033[0m\n' \
        "$colour" "$icon" "$description" "$dim" "${tool:+ $tool   } " $((secs / 60)) $((secs % 60))
    done <<<"$rows"
    echo
    tmux capture-pane -ep -t "$2" | tail -n +$(($(wc -l <<<"$rows") * 2 + 2))
  else
    tmux capture-pane -ep -t "$2"
  fi
  exit 0
fi

self=${BASH_SOURCE[0]}
# shellcheck source-path=SCRIPTDIR
. "$here/fzf-theme.sh"
# Rank 0 or 1 is a window that needs you (tmux.conf's @claude_rank)
if tmux list-windows -a -F '#{E:@claude_rank}' | grep -qx '[01]'; then
  position=1
else
  current=$(tmux display -p '#{window_id}')
  position=$(ranked | awk -F'\t' -v window="$current" '$1 == window { print NR; exit }')
fi

# While it is open, the list and the preview follow what Claude does, checked
# once a second and redrawn only when they changed: redrawing every second
# flickers and makes the text cursor jump. The cursor stays on the same window
# when the order changes
work=${TMPDIR:-/tmp}/window-picker.$$
socket=$work.sock cache=$work.branches items=$work.items
list="\"$self\" list \"$cache\""
eval "$list" >"$items"
fzf_do() { curl -s --unix-socket "$socket" http://localhost -d "$1" >/dev/null 2>&1; }
last_items=$(cksum <"$items")
while sleep 1; do
  now=$(eval "$list" | cksum)
  [ "$now" = "$last_items" ] || fzf_do "reload($list)"
  last_items=$now
  shown=$(curl -s --unix-socket "$socket" 'http://localhost?limit=0' 2>/dev/null | jq -r '.current.text // "" | split("\t")[0]')
  [ -n "$shown" ] || continue
  screen=$("$self" preview "$shown" 2>/dev/null | cksum)
  [ "$shown $screen" = "${last_screen:=$shown $screen}" ] || fzf_do refresh-preview
  last_screen="$shown $screen"
done &
refresher=$!
trap 'kill $refresher 2>/dev/null; rm -f "$socket" "$cache" "$items"' EXIT

target=$(
  fzf <"$items" "${fzf_theme[@]}" --read0 --ansi --sync --layout reverse --listen "$socket" \
    --delimiter '\t' --with-nth 2.. --id-nth 1 --track --no-hscroll --gap --input-label ' Windows ' \
    --list-label "$(key_hints enter switch ctrl-x 'close window, asks before anything is lost')" --list-label-pos bottom \
    --bind "start:pos(${position:-1})" \
    --bind "ctrl-x:execute(\"$self\" kill {1})+reload($list)" \
    --bind 'focus:transform-preview-label:tmux display -p -t {1} " #{session_name}:#{window_index} "' \
    --preview "\"$self\" preview {1}" --preview-window 'right,55%'
) || exit 0
tmux switch-client -t "${target%%$'\t'*}"
