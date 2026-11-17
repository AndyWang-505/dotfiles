#!/usr/bin/env bash
# Claude Code hook that keeps each window's Claude mark (@claude_wait) for the
# status bar and the window picker, sends desktop notifications, and keeps the
# list of running conversations claude-resume.sh reopens after a restart.
# Wired up in ~/.claude/settings.json:
#   Notification -> ask, Stop -> done, StopFailure -> failed,
#   UserPromptSubmit / PostToolUse -> run,
#   SessionStart -> idle, SessionEnd -> clear
# `claude-wait.sh snapshot [window id]` only rewrites that list, leaving the
# window out; tmux.conf's hooks and window-picker.sh use it.

state=${XDG_STATE_HOME:-$HOME/.local/state}/tmux
sessions=$state/claude-sessions

# Records the conversation a pane runs and the directory it started in, which
# is where Claude files it. Fails when the pane already had it
remember() {
  [ -n "$session" ] || return 1
  [ "$session" = "$(tmux show -pv -t "$TMUX_PANE" @claude_session 2>/dev/null)" ] && return 1
  tmux set -p -t "$TMUX_PANE" @claude_session "$session"
  [ -n "$(tmux show -pv -t "$TMUX_PANE" @claude_dir 2>/dev/null)" ] ||
    tmux set -p -t "$TMUX_PANE" @claude_dir "${cwd:-$PWD}"
}

# One list per server, so a second server (tmux -L) never takes the main one's
# conversations. Written to a temporary file first, since hooks from several
# panes can run at once
snapshot() {
  local server panes
  server=$(tmux display -p '#{b:socket_path}-#{start_time}-#{pid}') || return
  panes=$(tmux list-panes -a -F '#{@claude_session}	#{@claude_dir}	#{session_name}	#{window_id}') || return
  mkdir -p "$sessions" &&
    awk -F'\t' -v except="$1" '$1 != "" && $4 != except && !seen[$1]++ { print $1 "\t" $2 "\t" $3 }' <<<"$panes" >"$sessions/.$server.$$" &&
    mv "$sessions/.$server.$$" "$sessions/$server.tsv"
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

if [ "$1" = snapshot ]; then
  snapshot "$2"
  exit 0
fi
[ -n "$TMUX_PANE" ] || exit 0
input=$(cat)
# agent is set on a subagent's hooks and empty for the main conversation
IFS=$'\x1f' read -r session cwd agent type reason < <(
  jq -r '[.session_id, .cwd, .agent_id, .notification_type, .reason] | map(. // "") | join("\u001f")' <<<"$input" 2>/dev/null
)
# The window's mark and, while it is a question, the agent that asked
IFS=/ read -r mark asker < <(tmux display -p -t "$TMUX_PANE" '#{@claude_wait}/#{@claude_asker}')
changed=
if [ "$1" = clear ] || remember; then
  changed=1
fi

case "$1" in
ask)
  # Questions are what waits on you; a permission prompt is one even from a
  # background agent after the turn ended. Claude's reminder after sitting idle
  # (idle_prompt, or no type from an older Claude Code) is not one once the
  # turn has finished. Other notifications leave the mark alone
  case "$type/$mark" in
  permission_prompt/* | elicitation_dialog/* | elicitation_url_dialog/* | agent_needs_input/*) question=1 ;;
  /done | /idle | idle_prompt/done | idle_prompt/idle) question= ;;
  /* | idle_prompt/*) question=1 ;;
  auth_success/* | auth_storage_failure/* | agent_completed/* | elicitation_complete/* | elicitation_response/* | quota_*/* | plugin_notification/*) question= ;;
  *)
    # A type Claude Code added since: noted once, so a missed question shows up
    question=
    mkdir -p "$state"
    grep -qxF "$type" "$state/new-notification-types" 2>/dev/null || echo "$type" >>"$state/new-notification-types"
    ;;
  esac
  if [ -n "$question" ]; then
    tmux set -w -t "$TMUX_PANE" @claude_wait ask \; set -w -t "$TMUX_PANE" @claude_asker "$agent"
    notify ask
  fi
  ;;
run)
  # The main conversation's steps mean it is working. A subagent's do not, so
  # a background agent after the turn ended keeps the window finished; but the
  # agent that asked a question answers it with its next step
  if [ -z "$agent" ] || [ "$mark/$asker" = "ask/$agent" ]; then
    tmux set -w -t "$TMUX_PANE" @claude_wait running
  fi
  ;;
idle)
  tmux set -w -t "$TMUX_PANE" @claude_wait idle
  ;;
done | failed)
  # A subagent's question still waits after the main turn ends. A finished or
  # failed turn is marked unseen unless its window is on screen
  if [ "$mark" != ask ] || [ -z "$asker" ]; then
    if [ "$(tmux display -p -t "$TMUX_PANE" '#{&&:#{window_active},#{session_attached}}')" = 1 ]; then
      tmux set -w -t "$TMUX_PANE" @claude_wait idle
    else
      tmux set -w -t "$TMUX_PANE" @claude_wait "done"
    fi
    notify "$1"
  fi
  ;;
clear)
  tmux set -wu -t "$TMUX_PANE" @claude_wait \; set -wu -t "$TMUX_PANE" @claude_asker
  # Only a conversation you ended leaves the resume list; one stopped by a
  # shutdown comes back
  case $reason in
  prompt_input_exit | clear | logout)
    tmux set -pu -t "$TMUX_PANE" @claude_session \; set -pu -t "$TMUX_PANE" @claude_dir
    ;;
  esac
  ;;
esac
[ -z "$changed" ] || snapshot
exit 0
