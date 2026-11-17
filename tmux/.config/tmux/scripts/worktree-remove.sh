#!/usr/bin/env bash
# Removes the linked worktree a directory is in, after asking. Used by ctrl-x
# in the window picker, right after a window is killed (`offer`), and in the
# new window picker (`ask`):
#   worktree-remove.sh offer|ask <dir>
# It only offers a worktree that loses nothing when removed:
#   - no tmux pane is in it
#   - nothing is uncommitted or untracked
#   - no ignored file is missing from the main worktree or differs from its
#     copy there, such as an .env edited only here. Ignored directories
#     (node_modules, dist) and *.tsbuildinfo are build output and do not count
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

root=$(git -C "$2" rev-parse --show-toplevel 2>/dev/null) || refuse "${2/#$HOME/\~} is not in a git repository"
shown=${root/#$HOME/\~}
common=$(git -C "$root" rev-parse --path-format=absolute --git-common-dir)
[ "$(git -C "$root" rev-parse --path-format=absolute --git-dir)" != "$common" ] ||
  refuse "$shown is the repository's main worktree"
tmux list-panes -a -F '#{pane_current_path}' |
  awk -v root="$root" '$0 == root || index($0, root "/") == 1 { found = 1 } END { exit !found }' &&
  refuse "A tmux pane is still in $shown"
[ -z "$(git -C "$root" status --porcelain)" ] || refuse "$shown has uncommitted or untracked changes"

main=$(git -C "$root" worktree list --porcelain | sed -n '1s/^worktree //p')
only_here=$(
  git -C "$root" status --porcelain --ignored | sed -n 's/^!! //p' | grep -v -e '/$' -e '\.tsbuildinfo$' |
    while IFS= read -r file; do
      cmp -s "$root/$file" "$main/$file" || printf '  %s\n' "$file"
    done
)
[ -z "$only_here" ] ||
  refuse "These ignored files in $shown are not the same in ${main/#$HOME/\~}:" "$only_here"

branch=$(git -C "$root" branch --show-current)
pr=
[ -n "$branch" ] &&
  pr=$(cd "$root" && gh pr list --head "$branch" --state all --limit 1 \
    --json state,headRefOid -q '.[0] | "\(.state) \(.headRefOid)"' 2>/dev/null)
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
