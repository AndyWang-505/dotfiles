#!/usr/bin/env bash
# Window switcher for `prefix f` / cmd+p. Windows that need you come first:
# Claude questions, then finished turns you have not seen, then the rest. The
# cursor starts on the first of them, or else on the window you came from.
# ctrl-x closes the highlighted window. Windows are picked by tmux window id
# (@3): their numbers shift as windows close

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
  path=$(tmux display -p -t "$2" '#{pane_current_path}')
  scripts=$(dirname "${BASH_SOURCE[0]}")
  # Off the resume list first: closing the server's last window ends tmux
  # before its own hook could do it
  "$scripts/claude-wait.sh" snapshot "$2"
  tmux kill-window -t "$2"
  # Then offers to remove the worktree it ran in, if nothing would be lost
  "$scripts/worktree-remove.sh" offer "$path"
  exit 0
fi

# Windows needing you first, otherwise in tmux's order. Fields: window id,
# session:index, mark (- when none), directory, title
ranked() {
  tmux list-windows -a -F '#{?#{==:#{@claude_wait},ask},0,#{?#{==:#{@claude_wait},done},1,2}}	#{window_id}	#{session_name}:#{window_index}	#{?@claude_wait,#{@claude_wait},-}	#{pane_current_path}	#{E:@win_title}' |
    sort -s -n -k1,1 | cut -f2-
}

# The picker's items, two lines each: the mark and title, then session:index,
# directory and branch. Marks match the status bar, except that working does
# not spin: animating the list would redraw it every second and make the text
# cursor jump. Branches are looked up once per directory while it is open.
#   window-picker.sh list [branch cache]
if [ "$1" = list ]; then
  rows=$(ranked)
  branches=$(cat "$2" 2>/dev/null)
  while IFS=$'\t' read -r _ _ _ dir _; do
    case $'\n'$branches$'\n' in *$'\n'"$dir"$'\t'*) continue ;; esac
    line="$dir"$'\t'$(git -C "$dir" branch --show-current 2>/dev/null)
    branches+=$'\n'$line
    [ -z "$2" ] || printf '%s\n' "$line" >>"$2"
  done <<<"$rows"
  BRANCHES=$branches awk -F'\t' -v home="$HOME" '
    BEGIN {
      n = split(ENVIRON["BRANCHES"], lines, "\n")
      for (i = 1; i <= n; i++) { split(lines[i], f, "\t"); branch[f[1]] = f[2] }
      dim = "\033[38;2;84;92;126m"; reset = "\033[0m"
    }
    {
      id = $1; target = $2; state = $3; dir = $4; title = $5
      icon = " "
      if (state == "ask") icon = "\033[33m󰍡"
      else if (state == "done") icon = "\033[32m󰗠"
      else if (state == "running") icon = "\033[36m⣾"
      else if (state == "idle") icon = dim "󰖔"
      shown = dir
      if (dir == home || index(dir, home "/") == 1) shown = "~" substr(dir, length(home) + 1)
      extra = branch[dir] == "" ? "" : "  ·  " branch[dir]
      printf "%s\t %s%s  \033[1m%s%s\n    %s%s  ·  %s%s%s%c", id, icon, reset, title, reset, dim, target, shown, extra, reset, 0
    }' <<<"$rows"
  exit 0
fi

self=${BASH_SOURCE[0]}
if [ "$(tmux list-windows -a -F '#{@claude_wait}' | grep -cxE 'ask|done')" -gt 0 ]; then
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
  screen=$(tmux capture-pane -ep -t "$shown" 2>/dev/null | cksum)
  [ "$shown $screen" = "${last_screen:=$shown $screen}" ] || fzf_do refresh-preview
  last_screen="$shown $screen"
done &
refresher=$!
trap 'kill $refresher 2>/dev/null; rm -f "$socket" "$cache" "$items"' EXIT

key=$'\e[1;38;2;122;162;247m' does=$'\e[22;38;2;115;122;162m' sep=$'\e[38;2;59;66;97m'
keys=" ${key}enter ${does}switch  ${sep}·  ${key}ctrl-x ${does}close window, asks before anything is lost "

target=$(
  fzf <"$items" --read0 --ansi --sync --layout reverse --style full:sharp --listen "$socket" \
    --delimiter '\t' --with-nth 2.. --id-nth 1 --track --highlight-line --no-hscroll \
    --prompt '❯ ' --pointer '▌' --gutter ' ' --gap --info hidden --input-label ' Windows ' \
    --list-label "$keys" --list-label-pos bottom \
    --color 'fg:#a9b1d6,fg+:#7aa2f7,bg+:-1,hl:#7aa2f7,hl+:#7aa2f7,prompt:#7aa2f7,pointer:#7aa2f7' \
    --color 'border:#7aa2f7,gap-line:#3b4261,label:#7aa2f7,query:#c0caf5,gutter:-1' \
    --bind "start:pos(${position:-1})" \
    --bind "ctrl-x:execute(\"$self\" kill {1})+reload($list)" \
    --bind 'focus:transform-preview-label:tmux display -p -t {1} " #{session_name}:#{window_index} "' \
    --preview 'tmux capture-pane -ep -t {1}' --preview-window 'right,55%'
) || exit 0
tmux switch-client -t "${target%%$'\t'*}"
