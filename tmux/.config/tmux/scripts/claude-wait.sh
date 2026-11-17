#!/usr/bin/env bash
# Claude Code hook that sets the per-window @claude_wait flag tmux.conf turns
# into status bar marks. Wired up in ~/.claude/settings.json:
#   Notification -> ask, Stop -> done, StopFailure -> failed,
#   UserPromptSubmit / PostToolUse -> run,
#   SessionStart -> idle, SessionEnd -> clear
# `claude-wait.sh snapshot` only rewrites the list below, for the tmux hooks
# that fire when a window closes or moves or a session is renamed;
# `claude-wait.sh snapshot <window id>` leaves that window out, for
# window-picker.sh about to kill it.

# Each pane remembers the conversation it runs and the directory Claude started
# in, and every tmux server keeps a list of its running conversations, so
# claude-resume.sh can bring them back after the server goes down. The list is
# rewritten from the live panes when a pane's conversation changes or ends, and
# by tmux.conf's hooks when windows close or move or a session is renamed; not
# on every hook, since one runs on every tool call and Claude waits for it.
# While the server is shutting down that listing fails and the last list stays.
sessions=${XDG_STATE_HOME:-$HOME/.local/state}/tmux/claude-sessions
# Fails when nothing changed
remember() {
  local session cwd
  session=$(jq -r '.session_id // empty' <<<"$input" 2>/dev/null)
  [ -n "$session" ] || return 1
  [ "$session" = "$(tmux show -pv -t "$TMUX_PANE" @claude_session 2>/dev/null)" ] && return 1
  tmux set -p -t "$TMUX_PANE" @claude_session "$session"
  # Set once, from the directory Claude started in: its conversations stay
  # filed under it after Claude cd's elsewhere. /clear unsets it
  if [ -z "$(tmux show -pv -t "$TMUX_PANE" @claude_dir 2>/dev/null)" ]; then
    cwd=$(jq -r '.cwd // empty' <<<"$input" 2>/dev/null)
    tmux set -p -t "$TMUX_PANE" @claude_dir "${cwd:-$PWD}"
  fi
}
# Named by socket, server start time and pid: claude-resume.sh only takes lists
# from its own socket, and a new server that happens to reuse an old pid does
# not overwrite the old list. Hooks from several panes can run at once, so each
# writes its own temporary file before moving it into place.
snapshot() {
  local server panes
  server=$(tmux display -p '#{b:socket_path}-#{start_time}-#{pid}') || return
  panes=$(tmux list-panes -a -F '#{@claude_session}	#{@claude_dir}	#{session_name}	#{window_id}') || return
  mkdir -p "$sessions" &&
    awk -F'\t' -v except="$1" '$1 != "" && $4 != except && !seen[$1]++ { print $1 "\t" $2 "\t" $3 }' <<<"$panes" >"$sessions/.$server.$$" &&
    mv "$sessions/.$server.$$" "$sessions/$server.tsv"
}

# Desktop notification, skipped when a focused Ghostty already shows it: a
# question when its window is on screen, a finished or failed turn when its mark
# is on the status bar, that is, the window's session is on screen. The OSC 777
# sequence is written straight to the terminal of the most recently used
# client, whichever session it shows, so Ghostty shows it without tmux
# passthrough.
#   notify ask|done|failed
notify() {
  local label message title body client_tty
  if tmux list-clients -F '#{?#{m:*focused*,#{client_flags}},#{session_id},}' |
    grep -qxF "$(tmux display -p -t "$TMUX_PANE" '#{session_id}')"; then
    [ "$1" = ask ] || return
    [ "$(tmux display -p -t "$TMUX_PANE" '#{window_active}')" = 1 ] && return
  fi
  # Named by session and label: window numbers shift as windows close
  label=$(tmux display -p -t "$TMUX_PANE" '#{session_name} · #{?@claude_label,#{@claude_label},#{s/^. //:pane_title}}')
  case $1 in
  ask)
    message=$(jq -r '.message // empty' <<<"$input" 2>/dev/null)
    title="💬 $label"
    body=${message:-Claude is waiting for you}
    ;;
  done)
    # The first line of Claude's last reply says what it finished; macOS
    # shortens a long one
    message=$(jq -r '.last_assistant_message // empty' <<<"$input" 2>/dev/null | sed -n '/[^[:space:]]/{p;q;}')
    title="✅ $label"
    body=${message:-Claude has finished}
    ;;
  failed)
    # StopFailure puts the API error in last_assistant_message
    message=$(jq -r '.last_assistant_message // empty' <<<"$input" 2>/dev/null | sed -n '/[^[:space:]]/{p;q;}')
    title="⚠️ $label"
    body=${message:-Claude stopped on an API error}
    ;;
  esac
  # Control characters would end the escape sequence and a ; in the title would
  # be read as the start of the body
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
# Set on hooks from a subagent, empty for the main conversation
agent=$(jq -r '.agent_id // empty' <<<"$input" 2>/dev/null)
changed=
if [ "$1" = clear ] || remember; then
  changed=1
fi

case "$1" in
ask)
  # Only notifications that wait on you are questions; others, such as a
  # background agent finishing or a sign-in, leave the mark alone. Claude also
  # notifies after sitting idle (idle_prompt, or no type from an older Claude
  # Code), which must not turn a finished or idle session back into a
  # question. A permission prompt always is one, even from a background agent
  # after the turn ended
  question=
  case "$(jq -r '.notification_type // empty' <<<"$input" 2>/dev/null)" in
  permission_prompt | elicitation_dialog | elicitation_url_dialog | agent_needs_input) question=1 ;;
  "" | idle_prompt)
    case "$(tmux show -wv -t "$TMUX_PANE" @claude_wait 2>/dev/null)" in
    done | idle) ;;
    *) question=1 ;;
    esac
    ;;
  esac
  # @claude_asker remembers which agent asked (empty for the main
  # conversation), so only that agent's next step clears the question
  if [ -n "$question" ]; then
    tmux set -w -t "$TMUX_PANE" @claude_wait ask \; set -w -t "$TMUX_PANE" @claude_asker "$agent"
    notify ask
  fi
  ;;
run)
  # A subagent's tool calls carry its agent_id. They do not move the mark, so a
  # background agent still working after the turn ended does not turn a
  # finished window back to working; but the agent that asked a question
  # answers it with its next tool call, which clears the question mark
  if [ -z "$agent" ] || [ "$(tmux show -wv -t "$TMUX_PANE" @claude_wait 2>/dev/null)/$(tmux show -wv -t "$TMUX_PANE" @claude_asker 2>/dev/null)" = "ask/$agent" ]; then
    tmux set -w -t "$TMUX_PANE" @claude_wait running
  fi
  ;;
idle)
  tmux set -w -t "$TMUX_PANE" @claude_wait idle
  ;;
done | failed)
  # A subagent's question outlives the main turn ending; it is still waiting
  [ "$(tmux display -p -t "$TMUX_PANE" '#{@claude_wait}/#{?@claude_asker,agent,}')" = ask/agent ] && exit 0
  # The window is already on screen, so nothing is left unseen to flag. A
  # failed turn takes the same mark: it ended and its error waits to be read
  if [ "$(tmux display -p -t "$TMUX_PANE" '#{&&:#{window_active},#{session_attached}}')" = 1 ]; then
    tmux set -w -t "$TMUX_PANE" @claude_wait idle
  else
    tmux set -w -t "$TMUX_PANE" @claude_wait "done"
  fi
  notify "$1"
  ;;
clear)
  tmux set -wu -t "$TMUX_PANE" @claude_wait \; set -wu -t "$TMUX_PANE" @claude_asker
  # Only a conversation you ended leaves the list. Any other reason, such as
  # the SIGTERM a shutdown sends before tmux goes down, keeps it so it comes
  # back; a killed window drops out anyway, through tmux.conf's hooks
  case "$(jq -r '.reason // empty' <<<"$input" 2>/dev/null)" in
  prompt_input_exit | clear | logout)
    tmux set -pu -t "$TMUX_PANE" @claude_session \; set -pu -t "$TMUX_PANE" @claude_dir
    ;;
  esac
  ;;
esac
[ -z "$changed" ] || snapshot
exit 0
