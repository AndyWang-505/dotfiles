#!/usr/bin/env bash
# Review popup for `prefix e` and `prefix R`: opens diffview on the repo or
# worktree the popup started in.
#   review.sh          uncommitted changes, untracked files included
#   review.sh branch   everything the branch changed since it forked from its
#                      base, committed or not; untracked files are not listed
#
# The base is the open PR's base branch. Without a PR it is whichever of the
# newest release/* and the remote's default branch the current branch forked
# from most recently. Remote branches come from upstream when the repo is a
# fork and from origin otherwise. Commits that reached the base after the fork
# are left out.

die() {
  echo "$*"
  read -rsn1 -p 'Press any key to close'
  exit 1
}

review() {
  exec nvim --cmd 'let g:review_popup = 1' "$@"
}

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "Not a git repository: $PWD"

[ "$1" = branch ] || review -c DiffviewOpen

remote=origin
git remote get-url upstream >/dev/null 2>&1 && remote=upstream

echo 'Finding the base branch...'
base=$(gh pr view --json baseRefName -q .baseRefName 2>/dev/null)
base=${base:+$remote/$base}
if [ -z "$base" ]; then
  closest=
  for candidate in \
    "$(git for-each-ref --sort=-v:refname --count=1 --format='%(refname:short)' "refs/remotes/$remote/release/*")" \
    "$(git symbolic-ref -q --short "refs/remotes/$remote/HEAD")"; do
    [ -n "$candidate" ] || continue
    ahead=$(git rev-list --count "$(git merge-base HEAD "$candidate")..HEAD" 2>/dev/null) || continue
    if [ -z "$closest" ] || [ "$ahead" -lt "$closest" ]; then
      base=$candidate
      closest=$ahead
    fi
  done
fi
[ -n "$base" ] || die 'No base branch found'

fork=$(git merge-base HEAD "$base") || die "No common history with $base"

review -c "DiffviewOpen $fork" -c "echo 'Changes since forking from $base'"
