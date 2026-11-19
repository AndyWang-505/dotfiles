# shellcheck shell=bash
# Helpers the tmux scripts and tests/tmux.sh share, so each rule has one copy.
# Sourced, not run.
#
# Tab-separated fields passed between commands: IFS=$'\t' read merges an empty
# field with the next, so tmux and awk output writes - for an empty one. jq
# output is joined with \x1f instead, which read keeps empty fields for.

# Where the scripts keep state: the resume lists, new notification types and
# the hook error log
state_dir=${XDG_STATE_HOME:-$HOME/.local/state}/tmux

# Each tmux server's list of the conversations it runs: claude-wait.sh writes
# the running server's, claude-resume.sh reads the one before after a restart
# shellcheck disable=SC2034 # used by the scripts that source this
sessions_dir=$state_dir/claude-sessions
# A newline, and the unit separator the resume lists put in its place in a
# window's @review_dirs
# shellcheck disable=SC2034 # used by the scripts that source this
nl=$'\n' us=$'\x1f'

# The running server's list name: socket, start time and pid, so no two
# servers share one
server_list_name() {
  tmux display -p '#{b:socket_path}-#{start_time}-#{pid}'
}

# A path with the home directory shown as ~. Only a whole home directory
# matches, so /Users/andy2 stays as it is for /Users/andy
tilde() {
  case $1 in
  "$HOME" | "$HOME"/*) printf '~%s' "${1#"$HOME"}" ;;
  *) printf '%s' "$1" ;;
  esac
}

# Where Claude Code keeps a directory's conversations: its path with every
# character other than a letter or digit turned into "-"
claude_project_dir() {
  printf '%s/.claude/projects/%s' "$HOME" "$(printf '%s' "$1" | sed 's/[^A-Za-z0-9]/-/g')"
}

# Where Claude Code keeps a conversation's transcript, worked out from the
# directory it started in. Hooks report the real path, which panes record;
# this is for when there is none
#   claude_transcript <session id> <directory>
claude_transcript() {
  printf '%s/%s.jsonl' "$(claude_project_dir "$2")" "$1"
}

# Where Claude Code keeps a conversation's subagents: beside its transcript
#   claude_agents_dir <session id> <directory> [transcript]
claude_agents_dir() {
  local transcript=${3:-}
  [ -n "$transcript" ] && [ "$transcript" != - ] || transcript=$(claude_transcript "$1" "$2")
  printf '%s/subagents' "${transcript%.jsonl}"
}

# The escape that sets the text colour to a "#rrggbb" one, as tmux.conf
# defines colours
hex_fg() {
  printf '\033[38;2;%d;%d;%dm' $((16#${1:1:2})) $((16#${1:3:2})) $((16#${1:5:2}))
}

# Notes a failure in the hook error log. The hooks never stop Claude Code
# over one, so this is where it shows up
log_error() {
  mkdir -p "$state_dir" &&
    printf '%s %s: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "${0##*/}" "$*" >>"$state_dir/claude-hooks.log"
}
