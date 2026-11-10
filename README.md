# dotfiles

Personal dotfiles for Apple Silicon macOS, managed with [GNU Stow](https://www.gnu.org/software/stow/).

## Packages

| Package | Description |
|---------|-------------|
| **ripgrep** | ripgrep config (`~/.ripgreprc`), loaded through `RIPGREP_CONFIG_PATH` set in the fish package |
| **git** | Name, aliases and the personal identity, picked by the repo's remote via `includeIf`. `user.useConfigOnly` makes git refuse to commit in a repo that matches no identity instead of guessing an email |
| **claude** | Global Claude Code instructions (`~/.claude/CLAUDE.md`) only — the rest of `~/.claude` holds work context and stays machine-local |
| **fish** | Interactive shell — [Fisher](https://github.com/jorgebucaran/fisher), [Tide](https://github.com/IlanCosman/tide) prompt, [fnm](https://github.com/Schniz/fnm) (switches Node to a project's `.nvmrc` on `cd`), abbreviations in `conf.d/abbr.fish` (`t` attaches the shared `main` tmux session) |
| **nvim** | Neovim config based on [LazyVim](https://www.lazyvim.org/) |
| **tmux** | `C-a` prefix, vi-style copy mode, plugins via [TPM](https://github.com/tmux-plugins/tpm), and the [Claude Code workflow](#claude-code-in-tmux): window picker, new-window picker, review popups and [status marks](#claude-code-status-in-tmux) in the status bar |
| **ghostty** | Terminal — tokyonight-night, transparent background, launches fish; `cmd` shortcuts for the [Claude Code workflow](#claude-code-in-tmux) |

> **zsh** is intentionally not a package — it is only the login shell and gets its PATH from `/etc/paths`.

## Install

```sh
git clone https://github.com/AndyWang505/dotfiles.git ~/dotfiles
cd ~/dotfiles
./install.sh
```

`install.sh` is idempotent. After it runs, fill in machine-local values:

```sh
$EDITOR ~/.gitconfig                      # employer includeIf, see below
$EDITOR ~/.config/git/work.gitconfig      # [user] email = ...
$EDITOR ~/.config/fish/config-local.fish  # credentials, work env vars
```

## Day to day

Every tracked config is a symlink into `~/dotfiles`, so editing `~/.config/...`
edits the repo. Commit from `~/dotfiles` afterwards. A new file needs
`stow --restow <package>` from `~/dotfiles` before it shows up in `$HOME`.

## Machine-local files

These are untracked on purpose (repo is public):

| File | Purpose |
|------|---------|
| `~/.gitconfig` | URL rewrites, and the `includeIf` that points an employer's repos at `work.gitconfig` |
| `~/.config/git/work.gitconfig` | Employer email |
| `~/.config/fish/config-local.fish` | Credentials and work env vars |
| `nvim/.../lua/plugins/local/` | Editor config tied to a specific employer |
| `~/.claude/settings.json` | Claude Code settings; holds work context. `install.sh` only adds the tmux status hooks to it |

## Claude Code in tmux

Each Claude Code session runs as its own tmux window, started in the repo or
worktree it works on. The window's directory decides what its status mark, its
review popups and Claude Code's own `/diff` show, so a session meant for a
worktree is started there rather than pointed at it from the main repo.

| Ghostty | tmux | Does |
|---------|------|------|
| `cmd+p` | `prefix f` | Window picker with a live preview of each window; `ctrl-x` kills a window, asking first if Claude is still active in it |
| `cmd+shift+n` | `prefix C` | New Claude Code window in a directory picked from the current one, every worktree of its repo, and where Claude Code has run before (most recent first). `enter` starts a new conversation, `ctrl-o` continues that directory's last one |
| `cmd+r` | `prefix e` | Review popup with the window's uncommitted changes, untracked files included |
| `cmd+shift+r` | `prefix R` | Review popup with everything the branch changed since it forked from its base, committed or not; untracked files are not listed |

The branch review's base is the open PR's base branch. Without a PR it is
whichever of the newest `release/*` and the default branch the current branch
forked from most recently, taken from `upstream` in a fork and from `origin`
otherwise.

The review popups open nvim with diffview and nothing else: no bufferline,
`<S-h>` / `<S-l>` step through the changed files, and closing the diffview
(`:qa`, `<leader>gq` or `:DiffviewClose`) closes the popup. Edits in the diff
are real files; unsaved ones are asked about before it closes.

## Claude Code status in tmux

`tmux/.config/tmux/scripts/claude-wait.sh` marks each tmux window with what its
Claude Code session is doing: 🔄 while it works, yellow 💬 when it needs an
answer, blue ✅ when it finished and you have not looked yet, 💤 once you have
(or before the first prompt). A 💬 also raises a Ghostty desktop notification
(OSC 777) unless that window is already in front of you. Claude Code has to call
it from its hooks, which `install.sh` adds to `~/.claude/settings.json`, leaving
any other hooks there alone.

Windows are labelled by the conversation title Claude Code puts in the pane
title. A session that starts with a slash command never gets one, so a window
can override it with `@claude_label`, which stays until the window closes:

```sh
tmux set -w -t "$TMUX_PANE" @claude_label PROJ-123   # set
tmux set -wu @claude_label                           # back to the title
```
