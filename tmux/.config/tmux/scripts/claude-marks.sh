# shellcheck shell=bash
# The rules for a window's Claude mark, kept apart from tmux so tests can check
# them as a table (docs/claude-code-in-tmux.md lists the same rows).
# claude-wait.sh reads the window, asks next_mark, and applies its answer.
# Sourced, not run.

# What a Claude Code notification type means for the mark:
#   question  something waits on you
#   reminder  Claude's reminder after sitting idle; an older Claude Code sends no type
#   other     a known type that never asks
#   unknown   a type added since, worth noting so it gets handled
notification_kind() {
  case $1 in
  permission_prompt | elicitation_dialog | elicitation_url_dialog | agent_needs_input) echo question ;;
  "" | idle_prompt) echo reminder ;;
  auth_success | auth_storage_failure | agent_completed | elicitation_complete | elicitation_response | quota_* | plugin_notification) echo other ;;
  *) echo unknown ;;
  esac
}

# The mark after a hook, from the one before it.
#   next_mark <event> <notification type> <mark> <asker> <agent> <on screen>
# event is the hook's argument: ask, run, idle, done, failed or clear. asker is
# the agent that asked the open question and agent the one this hook came from,
# both empty for the main conversation. on screen is 1 when the window is in
# front of an attached client. Prints "<mark> <asker>", - standing for none, or
# nothing when the mark stays as it is.
next_mark() {
  local event=$1 type=$2 mark=$3 asker=$4 agent=$5 on_screen=$6
  case $event in
  idle)
    echo "idle ${asker:--}"
    ;;
  run)
    # A subagent's steps leave the mark, so a background agent does not turn a
    # finished window back to working, except that the agent that asked a
    # question answers it with its next step
    if [ -z "$agent" ] || [ "$mark/$asker" = "ask/$agent" ]; then
      echo "running ${asker:--}"
    fi
    ;;
  ask)
    case $(notification_kind "$type")/$mark in
    question/*) echo "ask ${agent:--}" ;;
    reminder/done | reminder/idle) ;;
    reminder/*) echo "ask ${agent:--}" ;;
    esac
    ;;
  done | failed)
    # A subagent's question still waits after the main turn ends. A failed turn
    # takes the same mark: it ended and its error waits to be read
    [ "$mark" = ask ] && [ -n "$asker" ] && return
    if [ "$on_screen" = 1 ]; then
      echo "idle ${asker:--}"
    else
      echo "done ${asker:--}"
    fi
    ;;
  clear)
    echo "- -"
    ;;
  esac
}
