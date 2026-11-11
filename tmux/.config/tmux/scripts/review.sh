#!/usr/bin/env bash
# Review popup for `prefix e` and `prefix R`: opens diffview on the repo or
# worktree the popup started in, or on one Claude edited from this window.
#   review.sh          uncommitted changes, untracked files included
#   review.sh branch   the commits the branch added since it forked from its
#                      base, one at a time; uncommitted changes are not listed
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

has_changes() {
  if [ "$mode" != branch ]; then
    [ -n "$(git -C "$1" status --porcelain 2>/dev/null | head -1)" ]
    return
  fi
  local bases
  bases=$(git -C "$1" for-each-ref --format='%(refname)' refs/remotes/origin/release/ refs/remotes/upstream/release/
    git -C "$1" symbolic-ref -q refs/remotes/origin/HEAD
    git -C "$1" symbolic-ref -q refs/remotes/upstream/HEAD)
  # shellcheck disable=SC2086
  [ -n "$(git -C "$1" rev-list -1 --no-merges HEAD --not $bases 2>/dev/null)" ]
}

# The window's own directory, unless Claude edited other repos or worktrees
# from this window (recorded by review-dirs.sh): those with changes are offered
# too, and the window's directory is skipped when it has nothing to show.
candidates() {
  local current others dir
  current=$(git rev-parse --show-toplevel 2>/dev/null) || current=$PWD
  others=$(tmux show -wv @review_dirs 2>/dev/null | while IFS= read -r dir; do
    [ "$dir" != "$current" ] && [ -d "$dir" ] && has_changes "$dir" && printf '%s\n' "$dir"
  done)
  if [ -z "$others" ]; then
    printf '%s\n' "$current"
  elif has_changes "$current"; then
    printf '%s\n%s\n' "$current" "$others"
  else
    printf '%s\n' "$others"
  fi
}

choose() {
  awk -v home="$HOME" '{ shown = $0; sub("^" home, "~", shown); print $0 "\t" shown }' |
    fzf --reverse --delimiter '\t' --with-nth 2 --prompt 'review> ' --bind "load:pos($1)" \
      --header 'enter: review  esc: close  (quitting nvim comes back here)' |
    cut -f1
}

open_review() {
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "Not a git repository: $PWD"

  [ "$mode" = branch ] || review -c DiffviewOpen

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
  # Merges are left out: one that brought the base in would list every change
  # the base made since the fork
  [ "$(git rev-list --count --no-merges "$fork..HEAD")" -gt 0 ] || die "No commits since forking from $base"

  review -c "DiffviewFileHistory --range=$fork..HEAD --no-merges" -c "echo 'Commits since forking from $base'"
}

mode=$1
dirs=$(candidates)

if [ "$(wc -l <<<"$dirs")" -eq 1 ]; then
  cd "$dirs" || die "Cannot open $dirs"
  open_review
fi

# Several to choose from: each review runs in a subshell, so quitting nvim
# returns to the list, with the cursor on the one just reviewed
position=1
while dir=$(choose "$position" <<<"$dirs") && [ -n "$dir" ]; do
  position=$(grep -nxF "$dir" <<<"$dirs" | cut -d: -f1)
  (cd "$dir" && open_review)
done
