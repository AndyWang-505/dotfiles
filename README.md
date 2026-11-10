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
| **tmux** | `C-a` prefix, vi-style copy mode, plugins via [TPM](https://github.com/tmux-plugins/tpm), and the [Claude Code workflow](#claude-code-in-tmux): window picker, new-window picker, status marks and review popups |
| **ghostty** | Terminal — tokyonight-night, transparent background, launches fish; `cmd` shortcuts for the [Claude Code workflow](#claude-code-in-tmux) |

> **zsh** is intentionally not a package — it is only the login shell and gets its PATH from `/etc/paths`.

## Install

Run these from the built-in Terminal app: Ghostty is one of the things
`install.sh` installs.

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

`install.sh` is idempotent. When it stops, or ends with a list of failed steps,
fix what it names and run it again.

### After the first run

`install.sh` prints the same list when it finishes. Do these in Ghostty:
Terminal's zsh does not have Homebrew on its PATH, so `nvim` and `brew` are not
found there.

1. Open Ghostty. It starts fish; `t` attaches the shared tmux session.
2. Fill in the [machine-local files](#machine-local-files). Until
   `work.gitconfig` has an email, git refuses to commit in work repos.

   ```sh
   nvim ~/.gitconfig                      # uncomment the employer includeIf
   nvim ~/.config/git/work.gitconfig      # [user] email = ...
   nvim ~/.config/fish/config-local.fish  # credentials, work env vars
   ```

3. Run `claude` once to sign in.
4. Optional: Ghostty already runs fish. Only if you also want it as the login
   shell:

   ```sh
   echo $(brew --prefix)/bin/fish | sudo tee -a /etc/shells
   chsh -s $(brew --prefix)/bin/fish
   ```

## Day to day

Every tracked config is a symlink into `~/dotfiles`, so editing `~/.config/...`
edits the repo. A new file needs `stow --restow <package>` from `~/dotfiles`
before it shows up in `$HOME`.

A new package is a directory laid out like `$HOME`, added to `PACKAGES` in
`install.sh`. When a directory it stows into does not exist yet, stow links the
whole directory into the repo, so whatever the program later writes there lands
in `~/dotfiles`. If the program writes into that directory, create it before
stowing and add the same `mkdir -p` to `install.sh`, as it does for
`~/.claude`.

Running programs pick up an edit as follows:

| Config | Takes effect |
|--------|--------------|
| tmux | `tmux source-file ~/.config/tmux/tmux.conf` |
| Ghostty | `cmd+shift+,` |
| nvim | Next time nvim starts, review popups included |
| fish | New shell, or `exec fish` |

`install.sh` puts nvim plugins back to the versions in
`nvim/.config/nvim/lazy-lock.json`, so after `:Lazy update` commit that file, or
the next run rolls the plugins back.

Changes go in through PRs. This clone pushes branches to a fork (`origin`) and
opens PRs against `upstream`. Once one merges:

```sh
git switch main && git pull upstream main
git push origin main   # bring the fork along
```

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

Every Claude Code session gets its own tmux window, started in the repo or
worktree it works on. Pick that directory with `cmd+shift+n` when opening the
window: a running session cannot move, and its review popups and `/diff` look
at the directory it started in.

| Ghostty | tmux | Does |
|---------|------|------|
| `cmd+p` | `prefix f` | Switch windows, with a live preview of each; `ctrl-x` kills one, asking first if Claude is still active in it |
| `cmd+shift+n` | `prefix C` | New Claude Code window in a directory you pick |
| `cmd+r` | `prefix e` | Review the window's uncommitted changes |
| `cmd+shift+r` | `prefix R` | Review everything the window's branch changed |

### New window picker

Lists the current directory, every worktree of its repo, then the directories
Claude Code has run in, most recent first. `enter` starts a new conversation
there, `ctrl-o` continues that directory's last one. A directory joins the list
once Claude Code has run in it; before that, `cd` there and pick the current
directory.

### Status marks

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

### Review popups

Both open nvim with diffview on the window's repo or worktree. The right side
is the real file, so it can be edited and saved there. `<S-h>` / `<S-l>` step
through the changed files, and closing the diffview (`:qa`, `<leader>gq` or
`:DiffviewClose`) closes the popup, asking first about unsaved edits.

`cmd+r` lists the uncommitted changes, untracked files included. `cmd+shift+r`
lists everything since the branch forked from its base, committed or not, but
not untracked files. The base is the open PR's base branch; without a PR it is
whichever of the newest `release/*` and the default branch the branch forked
from most recently, taken from `upstream` in a fork and from `origin`
otherwise.
