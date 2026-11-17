# shellcheck shell=bash
# Helpers the tmux scripts and tests/tmux.sh share, so each rule has one copy.
# Sourced, not run.

# Where the scripts keep state: the resume lists, new notification types and
# the hook error log
state_dir=${XDG_STATE_HOME:-$HOME/.local/state}/tmux

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

# Notes a failure in the hook error log. The hooks never stop Claude Code
# over one, so this is where it shows up
log_error() {
  mkdir -p "$state_dir" &&
    printf '%s %s: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "${0##*/}" "$*" >>"$state_dir/claude-hooks.log"
}
