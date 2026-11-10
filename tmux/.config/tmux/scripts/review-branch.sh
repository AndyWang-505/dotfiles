#!/usr/bin/env bash
# Opens diffview on everything the current branch changed since it forked from
# its base: committed work plus uncommitted edits to tracked files. Run by
# `prefix R` in a popup started in the window's current path.
#
# The base is the open PR's base branch, else the newest origin/release/*,
# else the remote's default branch. Diffing from the merge base leaves out
# commits that landed on the base after the branch was cut.

die() {
  echo "$*"
  read -rsn1 -p 'Press any key to close'
  exit 1
}

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "Not a git repository: $PWD"

echo 'Finding the base branch...'
base=$(gh pr view --json baseRefName -q .baseRefName 2>/dev/null)
base=${base:+origin/$base}
base=${base:-$(git for-each-ref --sort=-v:refname --count=1 --format='%(refname:short)' 'refs/remotes/origin/release/*')}
base=${base:-$(git symbolic-ref -q --short refs/remotes/origin/HEAD)}
[ -n "$base" ] || die 'No base branch found'

fork=$(git merge-base HEAD "$base") || die "No common history with $base"

exec nvim -c "DiffviewOpen $fork" -c "echo 'Changes since forking from $base'"
