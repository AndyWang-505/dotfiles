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
| **tmux** | `C-a` prefix, vi-style copy mode, plugins via [TPM](https://github.com/tmux-plugins/tpm), fzf window picker on `prefix f` (`ctrl-x` kills a window, asking first if Claude is still active in it), new Claude Code window on `prefix C` in a directory picked from the current one, its repo's worktrees and where Claude Code has run before (`ctrl-o` continues that directory's last conversation), uncommitted changes of the window's repo or worktree in a diffview popup on `prefix e`, and everything the branch changed since it forked from its base (the PR's base branch, else whichever of the newest `release/*` and the default branch it forked from most recently) on `prefix R`, [Claude Code status](#claude-code-status-in-tmux) in the status bar |
| **ghostty** | Terminal — tokyonight-night, transparent background, launches fish; `cmd+p` opens the tmux window picker, `cmd+shift+n` opens the new Claude Code window picker, `cmd+r` / `cmd+shift+r` open the uncommitted / whole-branch diffview popups |

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
