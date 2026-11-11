#!/usr/bin/env bash
# Review popup for `prefix e`, on the window's repo or worktree or one Claude
# edited from this window. nvim (lua/review_popup.lua) starts on the branch diff
# since the fork point; 1 / 2 / 3 there switch to it, the uncommitted changes or
# the branch's commits.
#
# The base is the open PR's base branch, if it is fetched. Otherwise it is
# whichever of the newest release/* and the default branch HEAD forked from most
# recently. Remote branches come from upstream in a fork and origin otherwise.

die() {
  echo "$*"
  read -rsn1 -p 'Press any key to close'
  exit 1
}

review() {
  exec nvim --cmd 'let g:review_popup = 1' "$@"
}

# Uncommitted changes, or commits not yet in any release/* or default branch.
# With no remote branches to compare against, only uncommitted changes count.
has_changes() {
  [ -n "$(git -C "$1" status --porcelain 2>/dev/null | head -1)" ] && return 0
  local bases
  bases=$(git -C "$1" for-each-ref --format='%(refname)' refs/remotes/origin/release/ refs/remotes/upstream/release/
    git -C "$1" symbolic-ref -q refs/remotes/origin/HEAD
    git -C "$1" symbolic-ref -q refs/remotes/upstream/HEAD)
  [ -n "$bases" ] || return 1
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

# Prints "<fork point> <base>"
find_fork() {
  local remote=origin base candidate fork ahead best_fork best_ahead
  git remote get-url upstream >/dev/null 2>&1 && remote=upstream

  base=$(gh pr view --json state,baseRefName -q 'select(.state == "OPEN") | .baseRefName' 2>/dev/null)
  if [ -n "$base" ] && fork=$(git merge-base HEAD "$remote/$base" 2>/dev/null); then
    printf '%s %s\n' "$fork" "$remote/$base"
    return
  fi

  for candidate in \
    "$(git for-each-ref --sort=-v:refname --count=1 --format='%(refname:short)' "refs/remotes/$remote/release/*")" \
    "$(git symbolic-ref -q --short "refs/remotes/$remote/HEAD")"; do
    [ -n "$candidate" ] && fork=$(git merge-base HEAD "$candidate" 2>/dev/null) || continue
    ahead=$(git rev-list --count "$fork..HEAD")
    if [ -z "$best_ahead" ] || [ "$ahead" -lt "$best_ahead" ]; then
      base=$candidate best_fork=$fork best_ahead=$ahead
    fi
  done
  [ -n "$best_fork" ] || return 1
  printf '%s %s\n' "$best_fork" "$base"
}

# Without a base, nvim gets no fork point and shows only the uncommitted changes
open_review() {
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "Not a git repository: $PWD"

  echo 'Finding the base branch...'
  local fork base quote="'"
  read -r fork base <<<"$(find_fork)"
  [ -n "$fork" ] || review -c 'ReviewMode uncommitted'
  # Doubling ' keeps a branch name like it's inside the vimscript string
  review --cmd "let g:review_fork = '$fork' | let g:review_base = '${base//$quote/$quote$quote}'" -c 'ReviewMode branch'
}

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
