#!/usr/bin/env bash
# Tests for the tmux scripts behind the Claude Code workflow: the window marks
# Claude's hooks set, the resume list and reopening it after a restart, the
# window picker's list and preview, and removing worktrees. Each runs on its own tmux server
# with a scratch HOME, so your tmux, ~/.claude and repos are left alone.
#   tests/tmux.sh
set -u

repo=$(cd "$(dirname "$0")/.." && pwd)
scripts=$repo/tmux/.config/tmux/scripts
# The resolved path: tmux reports pane directories without symlinks, and
# macOS's temp directory is under one
work=$(cd "$(mktemp -d "${TMPDIR:-/tmp}/tmux-tests.XXXXXX")" && pwd -P)
socket=tmux-tests-$$
export HOME=$work/home XDG_STATE_HOME=$work/state
mkdir -p "$HOME/.config" "$work/bin"
ln -s "$repo/tmux/.config/tmux" "$HOME/.config/tmux"
export PATH=$work/bin:$PATH
# The scripts' shared helpers and mark rules, tested directly below
# shellcheck source-path=SCRIPTDIR/../tmux/.config/tmux/scripts
. "$scripts/lib.sh"
# shellcheck source-path=SCRIPTDIR/../tmux/.config/tmux/scripts
. "$scripts/claude-marks.sh"

cleanup() {
  tmux -L "$socket" kill-server 2>/dev/null
  tmux -L "$socket-b" kill-server 2>/dev/null
  rm -rf "$work"
}
trap cleanup EXIT

failed=0
check() { # name expected actual
  if [ "$2" = "$3" ]; then
    printf 'ok    %s\n' "$1"
  else
    printf 'FAIL  %s\n      expected: %s\n      got:      %s\n' "$1" "$2" "$3"
    failed=$((failed + 1))
  fi
}

tm() { tmux -L "$socket" "$@"; }
# Waits up to 2s for a background tmux hook to make "$@" succeed
eventually() {
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    "$@" && return 0
    sleep 0.2
  done
  return 1
}

# A fresh server loading the real tmux.conf. TPM is not installed here, so its
# line only prints an error.
start() {
  tmux -L "$socket" kill-server 2>/dev/null
  rm -rf "$XDG_STATE_HOME"
  tm -f "$HOME/.config/tmux/tmux.conf" new -d -s main -x 160 -y 40 "$@" 2>/dev/null
  TMUX="$(tm display -p '#{socket_path}'),0,0"
  export TMUX
}

# Runs claude-wait.sh as Claude Code's hook would from a pane
hook() { # pane event json
  TMUX_PANE=$1 "$scripts/claude-wait.sh" "$2" <<<"$3"
}
mark() { tm show -wv -t "$1" @claude_wait 2>/dev/null; }
resume_list() { cat "$XDG_STATE_HOME"/tmux/claude-sessions/*.tsv 2>/dev/null | tr '\t' ' ' | sort | tr '\n' '|'; }

echo '# Mark rules (next_mark, one row per case in docs/claude-code-in-tmux.md)'
rule() { # name event type mark asker agent on_screen expected
  check "$1" "$8" "$(next_mark "$2" "$3" "$4" "$5" "$6" "$7")"
}
rule 'a conversation starts' idle '' running '' '' 0 'idle -'
rule 'a prompt or tool call works' run '' idle '' '' 0 'running -'
rule 'the subagent that asked answers' run '' ask a1 a1 0 'running a1'
rule "another subagent's step leaves a question" run '' ask '' a1 0 ''
rule 'a background step leaves a finished turn' run '' 'done' '' a2 0 ''
rule 'a permission prompt asks, even after the turn' ask permission_prompt 'done' '' a2 0 'ask a2'
rule 'an agent waiting on input asks' ask agent_needs_input idle '' '' 0 'ask -'
rule 'a reminder while working asks' ask idle_prompt running '' '' 0 'ask -'
rule 'an untyped reminder while asking asks' ask '' ask '' '' 0 'ask -'
rule 'a reminder after a finished turn does not' ask idle_prompt 'done' '' '' 0 ''
rule 'an untyped reminder when idle does not' ask '' idle '' '' 0 ''
rule 'a known other notification leaves it' ask agent_completed running '' '' 0 ''
rule 'an unknown notification leaves it' ask brand_new_type running '' '' 0 ''
check 'and is recognised as unknown' unknown "$(notification_kind brand_new_type)"
rule "a turn ending keeps a subagent's question" 'done' '' ask a1 '' 0 ''
rule 'a turn ending is finished' 'done' '' running '' '' 0 'done -'
rule 'a failed turn is finished too' failed '' running '' '' 0 'done -'
rule 'a turn ending on screen is seen' 'done' '' running '' '' 1 'idle -'
rule 'an ended conversation has no mark' clear '' running '' '' 0 '- -'

echo '# Shared helpers'
# shellcheck disable=SC2088 # the literal ~ is what tilde prints
check 'the home directory is shown as ~' '~/code' "$(tilde "$HOME/code")"
check 'a sibling of home is not' "${HOME}2/code" "$(tilde "${HOME}2/code")"
check "Claude's project directory for a path" "$HOME/.claude/projects/-a-b-c-d" "$(claude_project_dir /a/b.c_d)"

echo '# Claude marks'

start
pane=$(tm display -p -t main:0 '#{pane_id}')
step() { # json event expected name
  hook "$pane" "$2" "$1"
  check "$4" "$3" "$(mark main:0)"
}
step '{"session_id":"s"}' idle idle 'a new conversation is idle'
step '{"session_id":"s"}' ask idle 'an idle reminder does not ask'
step '{"session_id":"s"}' run running 'a prompt or tool call is working'
step '{"session_id":"s","notification_type":"agent_completed"}' ask running 'other notifications leave the mark'
step '{"session_id":"s","notification_type":"idle_prompt"}' ask ask 'an idle reminder while working asks'
step '{"session_id":"s","notification_type":"brand_new_type"}' ask ask 'an unknown notification leaves the mark'
check 'and is noted for review' brand_new_type "$(cat "$XDG_STATE_HOME/tmux/new-notification-types" 2>/dev/null)"
step '{"session_id":"s"}' run running 'the next step answers it'
step '{"session_id":"s","notification_type":"permission_prompt"}' ask ask 'a permission prompt asks'
step '{"session_id":"s","agent_id":"a1"}' run ask "another agent's step leaves the question"
step '{"session_id":"s"}' run running "the main conversation's step answers it"
step '{"session_id":"s","agent_id":"a1","notification_type":"permission_prompt"}' ask ask 'a subagent asks'
step '{"session_id":"s"}' 'done' ask "the subagent's question outlives the turn"
step '{"session_id":"s","agent_id":"a1"}' run running "the subagent's step answers it"
step '{"session_id":"s"}' 'done' 'done' 'a finished turn is unseen'
step '{"session_id":"s","notification_type":"idle_prompt"}' ask 'done' 'an idle reminder after it does not ask'
step '{"session_id":"s","agent_id":"a2"}' run 'done' 'a background agent keeps it finished'
step '{"session_id":"s","agent_id":"a2","notification_type":"agent_needs_input"}' ask ask 'a background agent can still ask'
step '{"session_id":"s","agent_id":"a2"}' run running 'its step answers it'
step '{"session_id":"s","last_assistant_message":"API Error: Rate limit reached"}' failed 'done' 'a failed turn is marked finished'
step '{"session_id":"s","reason":"other"}' clear '' 'an ended conversation has no mark'
hook "$pane" run '{"session_id":"s"}'
hook "$pane" 'done' '{"session_id":"s"}'
tm new-window -t main \; select-window -t main:0
check 'visiting a finished window marks it seen' idle "$(mark main:0)"
hook "$pane" run 'not json'
check 'unreadable hook input is logged' 1 "$(grep -c 'run: unreadable hook input' "$XDG_STATE_HOME/tmux/claude-hooks.log" 2>/dev/null)"

echo '# Jumping to the window that waits (prefix a)'
start -n w0 \; new-window -t main -n w1 \; new-window -t main -n w2 \; new-session -d -s other -n o0 \; select-window -t main:0
tm set -w -t main:1 @claude_wait 'done' \; set -w -t main:2 @claude_wait ask \; set -w -t other:0 @claude_wait 'done'
# A client to move; it lives as long as its input stays open. tmux will not
# attach without a terminal type, which CI does not set
(sleep 30 | TERM=xterm-256color script -q /dev/null tmux -L "$socket" attach -t main >/dev/null 2>&1 &)
eventually sh -c "[ -n \"\$(tmux -L '$socket' list-clients)\" ]" ||
  check 'a client attaches for these tests' attached none
jump() { "$scripts/claude-jump.sh"; sleep 0.3; tm display -p -c "$(tm list-clients -F '#{client_name}' | head -1)" '#{session_name}:#{window_index}'; }
check 'a question comes first' main:2 "$(jump)"
tm set -w -t main:2 @claude_wait running
check 'then a finished turn, searching on from the current window' other:0 "$(jump)"
check 'arriving in another session marks it seen' idle "$(mark other:0)"
check 'and wraps around to the next' main:1 "$(jump)"
check 'arriving in the same session marks it seen' idle "$(mark main:1)"
on_screen=$(tm display -p -t main:1 '#{pane_id}')
hook "$on_screen" run '{"session_id":"t"}'
hook "$on_screen" 'done' '{"session_id":"t"}'
check 'a turn that finishes on screen is already seen' idle "$(mark main:1)"
"$scripts/claude-jump.sh"
check 'with nothing left it stays put' main:1 "$(tm display -p -c "$(tm list-clients -F '#{client_name}' | head -1)" '#{session_name}:#{window_index}')"

echo '# Resume list'
start \; new-window -t main \; new-window -t main \; new-session -d -s other
for w in 0 1 2; do
  hook "$(tm display -p -t main:$w '#{pane_id}')" idle "{\"session_id\":\"S$w\",\"cwd\":\"/tmp/dir $w\"}"
done
check 'running conversations are listed' 'S0 /tmp/dir 0 main|S1 /tmp/dir 1 main|S2 /tmp/dir 2 main|' "$(resume_list)"
tm rename-session -t main api
eventually grep -q api "$XDG_STATE_HOME"/tmux/claude-sessions/*.tsv
check 'a renamed session is followed' 'S0 /tmp/dir 0 api|S1 /tmp/dir 1 api|S2 /tmp/dir 2 api|' "$(resume_list)"
tm move-window -s api:2 -t other:
eventually grep -q other "$XDG_STATE_HOME"/tmux/claude-sessions/*.tsv
check 'a window moved to another session is followed' 'S0 /tmp/dir 0 api|S1 /tmp/dir 1 api|S2 /tmp/dir 2 other|' "$(resume_list)"
tm kill-window -t api:1
eventually sh -c "! grep -q S1 '$XDG_STATE_HOME'/tmux/claude-sessions/*.tsv"
check 'a killed window leaves' 'S0 /tmp/dir 0 api|S2 /tmp/dir 2 other|' "$(resume_list)"
hook "$(tm display -p -t api:0 '#{pane_id}')" clear '{"session_id":"S0","reason":"other"}'
check 'a conversation stopped by a shutdown stays' 'S0 /tmp/dir 0 api|S2 /tmp/dir 2 other|' "$(resume_list)"
hook "$(tm display -p -t api:0 '#{pane_id}')" clear '{"session_id":"S0","reason":"prompt_input_exit"}'
check 'a conversation ended with /exit leaves' 'S2 /tmp/dir 2 other|' "$(resume_list)"
"$scripts/claude-wait.sh" snapshot "$(tm display -p -t other:1 '#{window_id}')"
check 'the picker can leave out a window it is about to kill' '' "$(resume_list)"

echo '# Reopening after a restart'
printf '#!/bin/sh\nexec sleep 300\n' >"$work/bin/claude"
chmod +x "$work/bin/claude"
start \; new-window -t main \; new-session -d -s work
for t in main:0 main:1 work:0; do
  id=conv-${t/:/-}
  mkdir -p "$work/proj"
  mkdir -p "$(claude_project_dir "$work/proj")"
  touch "$(claude_project_dir "$work/proj")/$id.jsonl"
  hook "$(tm display -p -t $t '#{pane_id}')" idle "{\"session_id\":\"$id\",\"cwd\":\"$work/proj\"}"
done
saved=$(cat "$XDG_STATE_HOME"/tmux/claude-sessions/*.tsv)
tm kill-server
mkdir -p "$XDG_STATE_HOME/tmux/claude-sessions"
tmux -L "$socket-b" -f "$HOME/.config/tmux/tmux.conf" new -d -s main 2>/dev/null
check 'another tmux server leaves the list alone' 0 "$(tmux -L "$socket-b" list-windows -a -F '#{pane_start_command}' | grep -c 'claude --resume')"
tmux -L "$socket-b" kill-server
printf '%s\n' "$saved" >"$XDG_STATE_HOME/tmux/claude-sessions/$socket-1-999999.tsv"
tm -f "$HOME/.config/tmux/tmux.conf" new -A -d -s main 2>/dev/null
check 'each conversation reopens in its session' 'main claude --resume conv-main-0|main claude --resume conv-main-1|work claude --resume conv-work-0|' \
  "$(tm list-windows -a -F '#{session_name} #{pane_start_command}' | grep 'claude --resume' | sort | tr '\n' '|')"

echo '# Window picker list'
start -n shell -c "$HOME" \; new-window -t main -n w1 \; new-window -t main -n w2 \; new-window -t main -n w3
tm set -w -t main:1 @claude_wait 'done' \; set -w -t main:2 @claude_wait ask \; set -w -t main:3 @claude_wait running
listed=$("$scripts/window-picker.sh" list | tr '\0' '\n' | sed $'s/\e\\[[0-9;]*m//g')
check 'questions first, then finished, then the rest' 'main:2|main:1|main:0|main:3|' \
  "$(sed -n 's/^ *\(main:[0-9]\).*/\1/p' <<<"$listed" | tr '\n' '|')"
check 'items are keyed by window id' "$(tm display -p -t main:2 '#{window_id}')" "$(head -1 <<<"$listed" | cut -f1)"
check 'the home directory is shortened' '~' "$(awk -F '  ·  ' '/main:0/ { print $2 }' <<<"$listed")"
# A session started in the main repo that edits a worktree shows the worktree
git init -q "$HOME/edited" && git -C "$HOME/edited" checkout -q -b feature/edited
review_pane=$(tm display -p -t main:1 '#{pane_id}')
TMUX_PANE=$review_pane "$scripts/review-dirs.sh" <<<"{\"tool_input\":{\"file_path\":\"$HOME/edited/a.ts\"}}"
listed=$("$scripts/window-picker.sh" list | tr '\0' '\n' | sed $'s/\e\\[[0-9;]*m//g')
# shellcheck disable=SC2088 # the literal ~ is what the picker prints
check 'a window shows the repo Claude last edited from it' '~/edited  ·  feature/edited' \
  "$(awk -F '  ·  ' '/main:1/ { print $2 "  ·  " $3 }' <<<"$listed")"
rm -rf "$HOME/edited"
listed=$("$scripts/window-picker.sh" list | tr '\0' '\n' | sed $'s/\e\\[[0-9;]*m//g')
check 'a worktree removed since says so' removed "$(awk -F '  ·  ' '/main:1/ { print $3 }' <<<"$listed")"
check 'a window without edits shows its own directory' '~' "$(awk -F '  ·  ' '/main:0/ { print $2 }' <<<"$listed")"
# The subagents a Claude window runs: the list counts them, the preview names them
agents=$(claude_agents_dir conv-a "$work/proj")
mkdir -p "$agents" && cd "$agents" || exit 1
echo 'not json' >a0.meta.json && touch a0.jsonl
echo '{"description":"Running","finished":false}' >a1.meta.json && touch a1.jsonl
echo '{"description":"Done","finished":true}' >a2.meta.json && touch a2.jsonl
echo '{"description":"Stale","finished":false}' >a3.meta.json && touch -t 202001010000 a3.jsonl
echo '{"description":"Second"}' >a4.meta.json
echo '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Grep"}]}}' >a4.jsonl
cd "$repo" || exit 1
check 'running subagents are listed with their last tool' 'Running||Second|Grep|' \
  "$("$scripts/claude-agents.sh" "$agents" | cut -f1,2 | tr '\t\n' '||')"
tm set -p -t main:2 @claude_session conv-a \; set -p -t main:2 @claude_dir "$work/proj"
listed=$("$scripts/window-picker.sh" list | tr '\0' '\n' | sed $'s/\e\\[[0-9;]*m//g')
check 'the list counts the subagents a window runs' 1 "$(grep 'main:2' <<<"$listed" | grep -c '2 agents$')"
check 'and only there' 1 "$(grep -c 'agent' <<<"$listed")"
preview=$("$scripts/window-picker.sh" preview "$(tm display -p -t main:2 '#{window_id}')" | sed $'s/\e\\[[0-9;]*m//g')
check 'the preview names them above the screen' 'Running|Second|Grep · 0m00s|' \
  "$(sed -n '1p;3,4p' <<<"$preview" | sed 's/^[^ ]* //; s/^ *//' | tr '\n' '|')"

echo '# Removing worktrees'
printf '#!/bin/sh\n[ -n "${FAKE_PR:-}" ] && printf "%%s\\n" "$FAKE_PR"\nexit 0\n' >"$work/bin/gh"
chmod +x "$work/bin/gh"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
repos=$work/repos
mkdir -p "$repos" && cd "$repos" || exit 1
git init -q main
printf '.env\nnode_modules/\nsecrets/\n' >main/.gitignore
echo same >main/.env
git -C main add . && git -C main commit -qm init
worktree() { git -C main worktree add -q "$repos/$1" -b "$1" && cp main/.env "$1/"; }
remove() { # name expected-outcome
  echo y | "$scripts/worktree-remove.sh" ask "$repos/$1" >/dev/null 2>&1
  if [ -d "$repos/$1" ]; then check "$2" "$3" kept; else check "$2" "$3" removed; fi
}
worktree clean && mkdir -p clean/node_modules/x && touch clean/node_modules/x/a
remove clean 'build output alone does not block removal' removed
worktree secret && mkdir secret/secrets && echo key >secret/secrets/k
remove secret 'an ignored file only in the worktree blocks removal' kept
worktree env && echo other >env/.env
remove env 'an ignored file that differs from main blocks removal' kept
worktree untracked && echo new >untracked/new
remove untracked 'an untracked file blocks removal' kept
git -C main worktree add -q --detach "$repos/detached" && git -C detached commit -q --allow-empty -m x
remove detached 'commits on no branch block removal' kept
worktree merged
FAKE_PR="MERGED $(git -C merged rev-parse HEAD)" remove merged 'a worktree whose PR merged is removed' removed
check 'and its branch is deleted' '' "$(git -C main branch --list merged)"
cd "$repo" || exit 1

echo
if [ "$failed" -gt 0 ]; then
  echo "$failed failed"
  exit 1
fi
echo 'all passed'
