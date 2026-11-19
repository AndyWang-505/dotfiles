# dotfiles

Personal dotfiles for Apple Silicon macOS, managed with [GNU Stow](https://www.gnu.org/software/stow/).

One script sets up a new Mac with Ghostty, fish, tmux and Neovim, including a
tmux workflow for running several [Claude Code sessions side by side](#claude-code-in-tmux).

## Packages

Each package mirrors the layout of `$HOME` and is linked into it by stow, so a
config is edited in place and tracked here.

| Package | Description |
|---------|-------------|
| **ripgrep** | Default options for `rg` |
| **git** | Name and aliases; the personal email, or a work one for work repos if set, and no commit when neither fits |
| **claude** | Global Claude Code instructions; the rest of `~/.claude` stays on the machine |
| **fish** | Shell with the [Tide](https://github.com/IlanCosman/tide) prompt and each project's Node version; `t` opens the shared tmux session, `lg` lazygit |
| **nvim** | Neovim config based on [LazyVim](https://www.lazyvim.org/) |
| **tmux** | `C-a` prefix, vi copy mode, and the [Claude Code workflow](#claude-code-in-tmux) |
| **ghostty** | Terminal: tokyonight, see-through, starts fish; `cmd` keys for the [Claude Code workflow](#claude-code-in-tmux), inside tmux |

> **zsh** is intentionally not a package — it is only the login shell and gets its PATH from `/etc/paths`.

## Requirements

- macOS on Apple Silicon
- An administrator account, for Homebrew's installer

## Install

`install.sh` installs everything in the `Brewfile`, links the packages and sets
up their plugins. Start from the built-in Terminal app, since Ghostty is one of
the things it installs.

1. Install the Xcode Command Line Tools. A fresh Mac has no working `git` until
   they are in, and the first `git` call only opens their installer. Wait for
   the dialog to finish.

   ```sh
   xcode-select --install
   ```

2. Clone the repo and run the installer. Homebrew asks for your password and
   for Enter, and the first run takes a while.

   ```sh
   git clone https://github.com/AndyWang505/dotfiles.git ~/dotfiles
   cd ~/dotfiles
   ./install.sh
   ```

The script is safe to re-run: if it stops or ends with a list of failed steps,
fix what it names and run it again.

### After the first run

A few steps need you, and `install.sh` lists them when it finishes. Do them in
Ghostty, where Homebrew is on the PATH. More on each in [docs/setup.md](docs/setup.md).

1. Open Ghostty. It starts fish; `t` attaches the shared tmux session.
2. Run `gh auth login`: git reaches GitHub over HTTPS with it, so no SSH key is
   needed, and the [review popup](docs/claude-code-in-tmux.md#review-popup)
   compares a branch with its PR's base.
3. Run `claude` once to sign in.
4. Optional: fill in the [machine-local files](#machine-local-files), such as
   credentials for fish or a second git identity for work repos:

   ```sh
   nvim ~/.config/fish/config-local.fish  # credentials, env vars
   nvim ~/.gitconfig                      # uncomment the includeIf
   nvim ~/.config/git/work.gitconfig      # [user] email = ...
   ```

5. Optional: Ghostty already runs fish. Only if you also want it as the login
   shell:

   ```sh
   echo $(brew --prefix)/bin/fish | sudo tee -a /etc/shells
   chsh -s $(brew --prefix)/bin/fish
   ```

## Claude Code in tmux

![Claude Code sessions in tmux: status marks, jumping to the one that asks, the review popup, both pickers and removing a merged worktree](docs/assets/claude-code-in-tmux.gif)

Run several Claude Code sessions at once, each in its own tmux window in the
repo or worktree it works on. The status bar shows what each one is doing, and
a few keys take you straight to whichever needs you. See
[docs/claude-code-in-tmux.md](docs/claude-code-in-tmux.md) for how each piece
works.

| Ghostty | tmux | Does |
|---------|------|------|
| `cmd+p` | `prefix f` | Switch windows, the ones that need you first, with a live preview and the subagents each runs; `ctrl-x` closes one and offers to [remove its worktree](docs/claude-code-in-tmux.md#removing-worktrees) |
| `cmd+i` | `prefix a` | Next Claude window waiting for you, in any session |
| `cmd+shift+n` | `prefix C` | [New Claude Code window](docs/claude-code-in-tmux.md#new-window-picker) in a directory you pick; pick it there, since a running session cannot move. `ctrl-n` opens it in a new tmux session instead |
| `cmd+r` | `prefix e` | [Review popup](docs/claude-code-in-tmux.md#review-popup) for what the window's branch changed |
| `cmd+g` | `prefix g` | lazygit on the window's repo or worktree, in a popup |
| | `prefix v` / `prefix s` | Split the pane side by side / top and bottom, as vim's `<C-w>v` / `<C-w>s`, in the current pane's directory; `prefix c` opens a window there |
| | `prefix h` `j` `k` `l` | Move to the pane left / below / above / right |
| | `prefix [` | Copy mode with vi keys; `v` selects, `y` copies to the clipboard |

| Mark | Means |
|------|-------|
| ⣾ | Working; a spinner on the status bar, still in the window picker |
| <img src="docs/assets/marks/ask.svg" height="16" alt="question"> | Needs an answer; also a Ghostty desktop notification, unless that window is already in front of you |
| <img src="docs/assets/marks/done.svg" height="16" alt="finished"> | Finished, and you have not looked yet; also a desktop notification with the first line of Claude's reply, unless that session is already in front of you |
| <img src="docs/assets/marks/idle.svg" height="16" alt="idle"> | Idle: you have looked, or no prompt yet. A window with no mark is not running Claude |

The right of the status bar counts the questions and finished windows in your
other sessions. After a reboot, the next tmux reopens the conversations that
were running ([how](docs/claude-code-in-tmux.md#resume-after-a-restart)).

## Day to day

Configs are symlinks into `~/dotfiles`, so an edit to `~/.config/...` is an
edit to the repo. Running programs pick it up as follows:

| Config | Takes effect |
|--------|--------------|
| tmux | `tmux source-file ~/.config/tmux/tmux.conf` |
| Ghostty | `cmd+shift+,` |
| nvim | Next time nvim starts |
| fish | New shell, or `exec fish` |

After `:Lazy update`, commit `nvim/.config/nvim/lazy-lock.json`: `install.sh`
puts plugins back to the versions in it.

Adding a package, running the tests and getting changes in are covered in
[docs/maintaining.md](docs/maintaining.md).

## Machine-local files

The repo is public, so credentials and anything specific to one machine or
to work live in untracked files instead:

| File | Purpose |
|------|---------|
| `~/.gitconfig` | GitHub over HTTPS, and an optional `includeIf` that points work repos at `work.gitconfig` |
| `~/.config/git/work.gitconfig` | The email for work repos, if any |
| `~/.config/fish/config-local.fish` | Credentials and env vars |
| `nvim/.../lua/plugins/local/` | Editor plugins only some repos need |
| `nvim/.../lua/config/local.lua` | Editor settings and keymaps for this machine only |
| `~/.claude/settings.json` | Claude Code settings; holds work context. `install.sh` only adds the tmux hooks to it |
