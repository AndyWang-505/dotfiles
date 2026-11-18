#!/usr/bin/env bash
# Claude Code hook that keeps each window's Claude mark (@claude_wait) for the
# status bar and the window picker, sends desktop notifications, and keeps the
# list of running conversations claude-resume.sh reopens after a restart.
# Wired up in ~/.claude/settings.json:
#   Notification -> ask, Stop -> done, StopFailure -> failed,
#   UserPromptSubmit / PostToolUse -> run,
#   SessionStart -> idle, SessionEnd -> clear
# `claude-wait.sh snapshot [window id]` only rewrites that list, leaving the
# window out; tmux.conf's hooks and window-picker.sh use it. `claude-wait.sh
# sweep` drops the mark from windows no Claude runs in any more.

here=$(dirname "${BASH_SOURCE[0]}")
# shellcheck source-path=SCRIPTDIR
. "$here/lib.sh"
# shellcheck source-path=SCRIPTDIR
. "$here/claude-marks.sh"

# Records the conversation a pane runs, the directory to reopen it in and its
# transcript. A new conversation in the pane replaces all three. Fails when the
# pane already had it
remember() {
  [ -n "$session" ] || return 1
  [ "$session" = "$(tmux show -pv -t "$TMUX_PANE" @claude_session 2>/dev/null)" ] && return 1
  tmux set -p -t "$TMUX_PANE" @claude_session "$session" \; \
    set -p -t "$TMUX_PANE" @claude_dir "${cwd:-$PWD}" \; \
    set -p -t "$TMUX_PANE" @claude_transcript "$transcript"
}

# One list per server, so a second server (tmux -L) never takes the main one's
# conversations. Written to a temporary file first, since hooks from several
# panes can run at once
snapshot() {
  local server panes
  server=$(server_list_name) || return
  panes=$(tmux list-panes -a -F '#{@claude_session}	#{@claude_dir}	#{session_name}	#{window_id}	#{?@claude_transcript,#{@claude_transcript},-}') || return
  mkdir -p "$sessions_dir" &&
    awk -F'\t' -v except="$1" '$1 != "" && $4 != except && !seen[$1]++ { print $1 "\t" $2 "\t" $3 "\t" $5 }' <<<"$panes" >"$sessions_dir/.$server.$$" &&
    mv "$sessions_dir/.$server.$$" "$sessions_dir/$server.tsv"
}

# Desktop notification through the most recently used Ghostty, unless a
# focused one already shows it: a question when its window is on screen, a
# finished or failed turn when its session is.
#   notify ask|done|failed
notify() {
  local label reply title body client_tty
  if tmux list-clients -F '#{?#{m:*focused*,#{client_flags}},#{session_id},}' |
    grep -qxF "$(tmux display -p -t "$TMUX_PANE" '#{session_id}')"; then
    [ "$1" = ask ] || return
    [ "$(tmux display -p -t "$TMUX_PANE" '#{window_active}')" = 1 ] && return
  fi
  label=$(tmux display -p -t "$TMUX_PANE" '#{session_name} · #{?@claude_label,#{@claude_label},#{s/^. //:pane_title}}')
  # The first line of Claude's last reply: what it finished, or the API error
  reply=$(jq -r '.last_assistant_message // empty' <<<"$input" 2>/dev/null | sed -n '/[^[:space:]]/{p;q;}')
  case $1 in
  ask) title="💬 $label" body=$(jq -r '.message // "Claude is waiting for you"' <<<"$input" 2>/dev/null) ;;
  done) title="✅ $label" body=${reply:-Claude has finished} ;;
  failed) title="⚠️ $label" body=${reply:-Claude stopped on an API error} ;;
  esac
  # Control characters would end the escape sequence, and a ; in the title
  # would start the body
  title=$(printf '%s' "$title" | tr -d '\000-\037;')
  body=$(printf '%s' "$body" | tr -d '\000-\037')
  client_tty=$(tmux list-clients -F '#{client_activity} #{client_tty}' | sort -rn | sed -n '1s/^[^ ]* //p')
  [ -z "$client_tty" ] || printf '\033]777;notify;%s;%s\a' "$title" "$body" >"$client_tty"
}

# Puts next_mark's answer on the window. Fails when the mark stays as it is
apply_mark() {
  local result new_mark new_asker
  result=$(next_mark "$1" "$type" "$mark" "$asker" "$agent" "$on_screen" "$busy")
  [ -n "$result" ] || return 1
  read -r new_mark new_asker <<<"$result"
  if [ "$new_mark" = - ]; then
    tmux set -wu -t "$TMUX_PANE" @claude_wait \; set -wu -t "$TMUX_PANE" @claude_asker
  elif [ "$new_asker" = - ]; then
    tmux set -w -t "$TMUX_PANE" @claude_wait "$new_mark" \; set -wu -t "$TMUX_PANE" @claude_asker
  else
    tmux set -w -t "$TMUX_PANE" @claude_wait "$new_mark" \; set -w -t "$TMUX_PANE" @claude_asker "$new_asker"
  fi
}

# A notification type Claude Code added since, noted once for review
note_new_type() {
  mkdir -p "$state_dir" &&
    { grep -qxF "$1" "$state_dir/new-notification-types" 2>/dev/null ||
      echo "$1" >>"$state_dir/new-notification-types"; }
}

if [ "$1" = snapshot ]; then
  snapshot "$2"
  exit 0
fi
# A window whose Claude pane was killed or moved to another window keeps its
# mark, since Claude Code runs no hook for that; tmux.conf's pane hooks run
# `claude-wait.sh sweep` to drop the mark from windows no Claude runs in
if [ "$1" = sweep ]; then
  tmux list-panes -a -F '#{window_id}	#{@claude_wait}	#{m/r:#{@claude_command},#{pane_current_command}}' |
    awk -F'\t' '$2 != "" { marked[$1] = 1 } $3 == 1 { claude[$1] = 1 } END { for (w in marked) if (!(w in claude)) print w }' |
    while read -r window; do
      tmux set -wu -t "$window" @claude_wait \; set -wu -t "$window" @claude_asker
    done
  exit 0
fi
[ -n "$TMUX_PANE" ] || exit 0
input=$(cat)
# agent is set on a subagent's hooks and empty for the main conversation
IFS=$'\x1f' read -r session cwd agent type reason transcript source < <(
  jq -r '[.session_id, .cwd, .agent_id, .notification_type, .reason, .transcript_path, .source] | map(. // "") | join("\u001f")' <<<"$input" 2>/dev/null
) || log_error "$1: unreadable hook input"
# The window's mark, the agent that asked while it is a question, and whether
# the window is in front of an attached client
IFS=/ read -r mark asker on_screen < <(
  tmux display -p -t "$TMUX_PANE" '#{@claude_wait}/#{@claude_asker}/#{&&:#{window_active},#{session_attached}}'
) || log_error "$1: cannot read window $TMUX_PANE"

# Whether a turn ends with subagents still running in the background
busy=
if [ "$1" = 'done' ] && [ -n "$transcript" ] &&
  [ -n "$("$here/claude-agents.sh" "$(claude_agents_dir "$session" "$cwd" "$transcript")" | head -1)" ]; then
  busy=1
fi

changed=
if [ "$1" = clear ] || remember; then
  changed=1
fi

[ "$1" = ask ] && [ "$(notification_kind "$type")" = unknown ] && note_new_type "$type"
if apply_mark "$1"; then
  case $1 in
  ask) notify ask ;;
  'done') [ -n "$busy" ] || notify 'done' ;;
  failed) notify failed ;;
  esac
fi

# A new or cleared conversation is a new task: the last one's ticket label and
# the repos it edited would otherwise stay on the window. A resumed one carries on
if [ "$1" = idle ]; then
  case $source in
  startup | clear)
    tmux set -wu -t "$TMUX_PANE" @claude_label \; set -wu -t "$TMUX_PANE" @review_dir \; set -wu -t "$TMUX_PANE" @review_dirs
    ;;
  esac
fi

# Only a conversation you ended leaves the resume list; one stopped by a
# shutdown comes back
if [ "$1" = clear ]; then
  case $reason in
  prompt_input_exit | clear | logout)
    tmux set -pu -t "$TMUX_PANE" @claude_session \; set -pu -t "$TMUX_PANE" @claude_dir \; \
      set -pu -t "$TMUX_PANE" @claude_transcript
    ;;
  esac
fi
[ -z "$changed" ] || snapshot
exit 0
