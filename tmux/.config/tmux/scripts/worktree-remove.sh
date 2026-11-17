#!/usr/bin/env bash
# Removes the linked worktree a directory is in, after asking. Used by ctrl-x
# in the window picker, right after a window is killed (`offer`), and in the
# new window picker (`ask`):
#   worktree-remove.sh offer|ask <dir>
# It only offers a worktree that loses nothing when removed:
#   - no tmux pane is in it
#   - nothing is uncommitted or untracked
#   - HEAD is on a branch or remote branch, so a detached HEAD's commits stay
#   - every ignored file is the same as the main worktree's copy, such as an
#     .env copied in. Only what `build_output` names is let go unchecked
# The branch goes too when its PR is merged or closed and the branch is still
# at the PR's last commit, so GitHub keeps every commit; otherwise it stays.
# `offer` says nothing when the worktree cannot go, `ask` says why.

mode=$1

refuse() {
  if [ "$mode" = ask ]; then
    printf '%s\n' "$@"
    read -rsn1 -p 'Press any key to continue'
  fi
  exit 0
}

# ${var/#$HOME/~} would print "\~" inside quotes in bash 3.2
tilde() {
  case $1 in
  "$HOME" | "$HOME"/*) printf '~%s' "${1#"$HOME"}" ;;
  *) printf '%s' "$1" ;;
  esac
}

root=$(git -C "$2" rev-parse --show-toplevel 2>/dev/null) || refuse "$(tilde "$2") is not in a git repository"
shown=$(tilde "$root")
common=$(git -C "$root" rev-parse --path-format=absolute --git-common-dir)
[ "$(git -C "$root" rev-parse --path-format=absolute --git-dir)" != "$common" ] ||
  refuse "$shown is the repository's main worktree"
tmux list-panes -a -F '#{pane_current_path}' |
  awk -v root="$root" '$0 == root || index($0, root "/") == 1 { found = 1 } END { exit !found }' &&
  refuse "A tmux pane is still in $shown"
# --untracked-files=all overrides a status.showUntrackedFiles=no config, which
# would hide new files from git worktree remove as well
[ -z "$(git -C "$root" status --porcelain --untracked-files=all)" ] ||
  refuse "$shown has uncommitted or untracked changes"
[ -n "$(git -C "$root" for-each-ref --contains HEAD --count 1 refs/heads refs/remotes)" ] ||
  refuse "$shown has commits on no branch; put them on one first"

build_output() {
  case ${1##*/} in
  node_modules | dist | .nx | .next | .turbo | *.tsbuildinfo | .DS_Store) return 0 ;;
  esac
  return 1
}

# The main worktree is the first listed; a bare repository has none, so every
# ignored file there counts as missing
main=$(git -C "$root" worktree list --porcelain | sed -n '1s/^worktree //p')
# Ignored directories are listed once, not file by file, so node_modules is
# skipped whole and any other ignored directory is compared file by file
only_here=$(
  git -C "$root" status --porcelain -z --ignored=matching --untracked-files=all |
    while IFS= read -r -d '' entry; do
      [ "${entry:0:3}" = '!! ' ] || continue
      path=${entry:3}
      path=${path%/}
      if [ -d "$root/$path" ]; then
        build_output "$path" || (cd "$root" && find "$path" -type f -o -type l)
      else
        printf '%s\n' "$path"
      fi
    done |
    while IFS= read -r file; do
      build_output "$file" || cmp -s "$root/$file" "$main/$file" || printf '  %s\n' "$file"
    done
)
[ -z "$only_here" ] ||
  refuse "These ignored files in $shown would be lost; they are missing from or different in $(tilde "$main"):" "$only_here"

branch=$(git -C "$root" branch --show-current)
pr=
[ -n "$branch" ] &&
  pr=$(cd "$root" && gh pr list --head "$branch" --state all --limit 1 \
    --json state,headRefOid -q '.[] | "\(.state) \(.headRefOid)"' 2>/dev/null)
state=$(printf '%s' "${pr%% *}" | tr '[:upper:]' '[:lower:]')
delete_branch=
case $state in
merged | closed) [ "$(git -C "$root" rev-parse HEAD)" = "${pr#* }" ] && delete_branch=1 ;;
esac

about="branch ${branch:-none}${state:+, PR $state}"
if [ -n "$delete_branch" ]; then
  about="$about; the branch is deleted too"
elif [ -n "$branch" ]; then
  about="$about; the branch stays"
fi
printf '\nRemove worktree %s (%s)? [y/N] ' "$shown" "$about"
read -rn1 answer
echo
[ "$answer" = y ] || exit 0

if ! git --git-dir="$common" worktree remove "$root"; then
  read -rsn1 -p 'Press any key to continue'
  exit 1
fi
[ -z "$delete_branch" ] || git --git-dir="$common" branch -D "$branch" >/dev/null
