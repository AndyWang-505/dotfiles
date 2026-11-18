#!/usr/bin/env bash
# Window switcher for `prefix f` / cmd+p. Windows that need you come first:
# Claude questions, then finished turns you have not seen, then the rest. The
# cursor starts on the first of them, or else on the window you came from.
# ctrl-x closes the highlighted window. Windows are picked by tmux window id
# (@3): their numbers shift as windows close

here=$(dirname "${BASH_SOURCE[0]}")
# shellcheck source-path=SCRIPTDIR
. "$here/lib.sh"

# The subagents a window's Claude conversation is running (claude-agents.sh)
#   window_agents <window id>
window_agents() {
  local session dir
  IFS=$'\t' read -r session dir < <(tmux display -p -t "$1" '#{@claude_session}	#{@claude_dir}')
  [ -z "$session" ] || "$here/claude-agents.sh" "$(claude_agents_dir "$session" "$dir")"
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
  # The worktree the picker shows for it: the one Claude last edited, or the
  # pane's own directory
  path=$(tmux display -p -t "$2" '#{?@review_dir,#{@review_dir},#{pane_current_path}}')
  scripts=$(dirname "${BASH_SOURCE[0]}")
  # Off the resume list first: closing the server's last window ends tmux
  # before its own hook could do it
  "$scripts/claude-wait.sh" snapshot "$2"
  tmux kill-window -t "$2"
  # Then offers to remove the worktree it ran in, if nothing would be lost
  "$scripts/worktree-remove.sh" offer "$path"
  exit 0
fi

# Windows by how much they need you (tmux.conf's @claude_rank), otherwise in
# tmux's order. Fields: window id, session:index, mark (- when none),
# directory, title. The directory is the repo or worktree Claude last edited
# from the window (review-dirs.sh), which for a session started in the main
# repo is the worktree it works in; otherwise the pane's own
ranked() {
  tmux list-windows -a -F '#{E:@claude_rank}	#{window_id}	#{session_name}:#{window_index}	#{?@claude_wait,#{@claude_wait},-}	#{?@review_dir,#{@review_dir},#{pane_current_path}}	#{E:@win_title}' |
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
    # A worktree removed since, as autofix does once it is done, says so
    if [ -d "$dir" ]; then
      line="$dir"$'\t'$(git -C "$dir" branch --show-current 2>/dev/null)$'\t'$(tilde "$dir")
    else
      line="$dir"$'\t'removed$'\t'$(tilde "$dir")
    fi
    branches+=$'\n'$line
    [ -z "$2" ] || printf '%s\n' "$line" >>"$2"
  done <<<"$rows"
  # How many subagents each window runs, "window id <tab> count" per line
  agents=$(tmux list-windows -a -F '#{window_id}	#{@claude_session}	#{@claude_dir}' |
    while IFS=$'\t' read -r window session dir; do
      [ -n "$session" ] || continue
      count=$("$here/claude-agents.sh" "$(claude_agents_dir "$session" "$dir")" | wc -l)
      [ "$count" -eq 0 ] || printf '%s\t%d\n' "$window" "$count"
    done)
  # Marks and their colours as tmux.conf defines them, one "state icon #rrggbb" per line
  marks=$(tmux display -p "$(printf 'ask #{@mark_ask} #{@mark_ask_fg}\ndone #{@mark_done} #{@mark_done_fg}\nrunning #{@mark_running} #{@mark_running_fg}\nidle #{@mark_idle} #{@mark_idle_fg}')")
  AGENTS=$agents BRANCHES=$branches MARKS=$marks awk -F'\t' '
    function rgb(hex) {
      return sprintf("\033[38;2;%d;%d;%dm", hexbyte(substr(hex, 2, 2)), hexbyte(substr(hex, 4, 2)), hexbyte(substr(hex, 6, 2)))
    }
    function hexbyte(h) { return index("0123456789abcdef", tolower(substr(h, 1, 1))) * 16 + index("0123456789abcdef", tolower(substr(h, 2, 1))) - 17 }
    BEGIN {
      n = split(ENVIRON["BRANCHES"], lines, "\n")
      for (i = 1; i <= n; i++) { split(lines[i], f, "\t"); branch[f[1]] = f[2]; shown[f[1]] = f[3] }
      n = split(ENVIRON["MARKS"], lines, "\n")
      for (i = 1; i <= n; i++) { split(lines[i], f, " "); mark[f[1]] = rgb(f[3]) f[2] }
      n = split(ENVIRON["AGENTS"], lines, "\n")
      for (i = 1; i <= n; i++) { split(lines[i], f, "\t"); agents[f[1]] = f[2] }
      dim = "\033[38;2;84;92;126m"; reset = "\033[0m"
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
    IFS=' ' read -r icon fg < <(tmux display -p '#{@mark_running} #{@mark_running_fg}')
    colour=$(printf '\033[38;2;%d;%d;%dm' $((16#${fg:1:2})) $((16#${fg:3:2})) $((16#${fg:5:2})))
    while IFS=$'\t' read -r description tool secs; do
      printf '%s%s\033[0m \033[1m%s\033[0m\n    \033[38;2;84;92;126m%s%dm%02ds\033[0m\n' \
        "$colour" "$icon" "$description" "${tool:+ $tool   } " $((secs / 60)) $((secs % 60))
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
. "$(dirname "$self")/fzf-theme.sh"
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
