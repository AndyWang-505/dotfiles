# shellcheck shell=bash disable=SC2034
# Shared look of the fzf popups (window-picker.sh, claude-launcher.sh): sharp
# blue boxes in the tokyonight-night palette, the selected line in blue, and
# key hints on the list's bottom edge. Sourced, not run.

fzf_theme=(
  --style full:sharp --info hidden --highlight-line
  --prompt '❯ ' --pointer '▌' --gutter ' '
  --color 'fg:#a9b1d6,fg+:#7aa2f7,bg+:-1,hl:#7aa2f7,hl+:#7aa2f7,prompt:#7aa2f7,pointer:#7aa2f7'
  --color 'border:#7aa2f7,gap-line:#3b4261,label:#7aa2f7,query:#c0caf5,gutter:-1'
)

# The list's bottom edge label: keys in blue, what they do in grey.
#   key_hints <key> <does> [<key> <does>...]
key_hints() {
  local key=$'\e[1;38;2;122;162;247m' does=$'\e[22;38;2;115;122;162m' sep=$'\e[38;2;59;66;97m'
  local hints=
  while [ $# -ge 2 ]; do
    hints+="${hints:+  ${sep}·  }${key}$1 ${does}$2"
    shift 2
  done
  printf ' %s ' "$hints"
}
