# Claude Code in tmux

For using the workflow day to day: how the windows, marks, pickers and review
popup in the [README's Claude Code section](../README.md#claude-code-in-tmux)
behave. The scripts live in `tmux/.config/tmux/scripts/`.

- [Windows and keys](#windows-and-keys)
- [Notifications](#notifications)
- [New window picker](#new-window-picker)
- [Removing worktrees](#removing-worktrees)
- [Status marks](#status-marks)
- [Resume after a restart](#resume-after-a-restart)
- [Review popup](#review-popup)

## Windows and keys

Each Claude Code session gets its own window, started in the repo or worktree
it works on: a running session cannot move, and `/diff` and the review popup
look at the directory it started in. Ghostty's `cmd` keys send the tmux
`prefix` keys, so they only work inside tmux. `prefix h`, `prefix v` and
`prefix c` open the new pane or window in the current pane's directory.

The status bar shows each window's mark; its right side counts the questions
and finished turns waiting in your other sessions.

The window picker (`cmd+p`) also shows the subagents each Claude window is
running: their count in the list, and in the preview each one's task, the tool
it last called and how long it has run, above the window's screen. A subagent
quiet for 15 minutes is left out, as one a crash left behind.

## Notifications

A question sends a Ghostty desktop notification unless its window is already
in front of you. A finished turn sends one with the first line of Claude's
reply, and a turn that fails on an API error sends a ⚠️ one with the error,
unless that session is already in front of you.

## New window picker

Lists the current directory, every worktree of its repo, then the directories
Claude Code has run in, most recent first. `enter` starts a new conversation
there, `ctrl-o` continues that directory's last one. A directory joins the list
once Claude Code has run in it; before that, `cd` there and pick the current
directory.

Worktrees show their PR's state (open, merged, closed) a moment after the list
opens, and `ctrl-x` [removes](#removing-worktrees) the highlighted one, which
is how to clear out worktrees whose PRs are done.

## Removing worktrees

Both pickers' `ctrl-x` use `tmux/.config/tmux/scripts/worktree-remove.sh`. It
only offers a worktree that loses nothing: no tmux pane is in it, nothing is
uncommitted or untracked, HEAD's commit is on a local or remote branch (so a
detached HEAD loses nothing), and every ignored file, such as
an `.env` copied in, is the same as the main worktree's copy. Only build output
skips that check: `node_modules`, `dist`, `.nx`, `.next`, `.turbo`,
`*.tsbuildinfo` and `.DS_Store`. The branch is deleted too when its PR is
merged or closed and the branch is still at the PR's last commit, so GitHub
keeps every commit; otherwise it stays.

## Status marks

`tmux/.config/tmux/scripts/claude-wait.sh` marks each tmux window with what its
Claude Code session is doing, as listed in the [README](../README.md#claude-code-in-tmux).

The mark belongs to the window, so each window runs one Claude Code session; a
second one in another pane of the same window would overwrite it. Claude Code's
hooks and tmux move it as follows. The rules are `next_mark` in
`scripts/claude-marks.sh`, and `tests/tmux.sh` checks each row against it:

| When | Mark before | Mark after |
|------|-------------|------------|
| A conversation starts or is cleared | any | idle |
| You send a prompt, or the conversation uses a tool | any | working |
| The subagent that asked a question uses a tool | needs an answer | working |
| Any other subagent uses a tool | any | unchanged |
| Claude asks for permission, or a dialog or agent waits on you | any | needs an answer |
| Claude's reminder after sitting idle | working, needs an answer | needs an answer |
| Claude's reminder after sitting idle | finished, idle | unchanged |
| Any other notification | any | unchanged; a new type is noted |
| A turn ends, or fails on an API error | a subagent's question | unchanged |
| A turn ends with subagents still running in the background | anything else | working, until the turn after the last one reports |
| A turn ends, or fails on an API error | anything else | finished, or idle when its window is on screen |
| You open the window (switching to it, `cmd+p`, `cmd+i`) | finished | idle |
| The conversation ends | any | no mark |

Which windows need you, in the order `cmd+p` lists them and `cmd+i` visits
them, is tmux.conf's `@claude_rank`: questions, then finished turns.

A notification type the script does not know yet is noted in
`~/.local/state/tmux/new-notification-types`, a sign that a newer Claude Code
may need it handled.

Interrupting Claude with `esc` leaves the working mark until the next prompt,
since Claude Code runs no hook for an interrupt. A turn that ends on an API
error is marked finished, with a ⚠️ desktop notification showing the error.

The icons come from the Nerd Font Ghostty uses. The right of the status bar
counts the questions and finished windows in your other sessions; `cmd+i`
visits those and the ones in the current session too.

Claude Code calls it from its hooks, which `install.sh` adds to
`~/.claude/settings.json`, leaving any other hooks there alone.

Windows are labelled by the conversation title Claude Code puts in the pane
title. A session that starts with a slash command never gets one, so a window
can override it with `@claude_label`, which stays until the window closes:

```sh
tmux set -w -t "$TMUX_PANE" @claude_label PROJ-123   # set
tmux set -wu @claude_label                           # back to the title
```

## Resume after a restart

The same hooks keep a list of the conversations running in each tmux server,
under `~/.local/state/tmux/claude-sessions/`. After a reboot or a killed tmux
server, the next tmux to start on the same socket reopens each one with
`claude --resume` in the directory it started in, as a new window in the
session it was in, so `tmux new -A -s main` attaches to them. Conversations
ended with `/exit`, `ctrl-c`, `ctrl-d` or `/clear`, or by killing their window,
and ones that never got a message, are not reopened.

## Review popup

The popup is two pieces: `tmux/.config/tmux/scripts/review.sh` picks the repo
or worktree, and the nvim package's `lua/review_popup.lua` shows it, so it
needs both packages.

`cmd+r` shows what the window's branch changed, in Neovim with diffview. It
opens on the branch diff: everything since the branch forked from its base,
committed or not. When Claude also edited other repos or worktrees from this
window, such as an autofix worktree, or another worktree of the same repo has
changes, it asks which to open; only directories with changes are offered.

| Key | Does |
|-----|------|
| `1` | Branch diff (where it starts) |
| `2` | Only the uncommitted changes |
| `3` | The branch's commits one at a time; `L` shows the full message |
| `<S-h>` / `<S-l>` | Previous / next changed file |
| `<leader>/`, `gd`, `gr` | Search or jump; opens in a new tab so the diff stays, `:q` comes back |
| `<leader>ge` | Toggle editing |
| `:qa` | Close the popup |

- It starts read-only so a stray key cannot change a file; `<leader>ge` allows
  edits, which go to the real files.
- `1` leaves out files that were never `git add`ed; `2` shows them.
- The base is the base branch of the branch's open PR, once that branch is
  fetched. Otherwise it is the newest `release/*` or the default branch,
  whichever the branch forked from more recently (fewer commits since).
  Without any, only `2` works.
