# dotfiles

Personal dotfiles for Apple Silicon macOS, managed with [GNU Stow](https://www.gnu.org/software/stow/).

## Packages

| Package | Description |
|---------|-------------|
| **ripgrep** | ripgrep config (`~/.ripgreprc`), loaded through `RIPGREP_CONFIG_PATH` set in the fish package |
| **git** | Name, aliases and the personal identity, picked by the repo's remote via `includeIf`. `user.useConfigOnly` makes git refuse to commit in a repo that matches no identity instead of guessing an email |
| **claude** | Global Claude Code instructions (`~/.claude/CLAUDE.md`) only — the rest of `~/.claude` holds work context and stays machine-local |
| **fish** | Interactive shell — [Fisher](https://github.com/jorgebucaran/fisher), [Tide](https://github.com/IlanCosman/tide) prompt, [fnm](https://github.com/Schniz/fnm) (switches Node to a project's `.nvmrc` on `cd`), abbreviations in `conf.d/abbr.fish` (`t` attaches the shared `main` tmux session, `lg` opens lazygit, `gst` / `gl` run `git status` / `git pull`) |
| **nvim** | Neovim config based on [LazyVim](https://www.lazyvim.org/) |
| **tmux** | `C-a` prefix, vi-style copy mode, plugins via [TPM](https://github.com/tmux-plugins/tpm), and the [Claude Code workflow](#claude-code-in-tmux): window picker, new-window picker, status marks and the review popup |
| **ghostty** | Terminal — tokyonight-night, transparent background, launches fish; `cmd` shortcuts for the [Claude Code workflow](#claude-code-in-tmux) |

> **zsh** is intentionally not a package — it is only the login shell and gets its PATH from `/etc/paths`.

## Requirements

- macOS on Apple Silicon
- An administrator account, for Homebrew's installer

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
4. Optional: run `gh auth login`, so the [review popup](#review-popup) can find
   a branch's PR and diff against its base. Without it, the popup falls back to
   the newest `release/*` or the default branch.
5. Optional: Ghostty already runs fish. Only if you also want it as the login
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
| nvim | Next time nvim starts, the review popup included |
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
| `~/.claude/settings.json` | Claude Code settings; holds work context. `install.sh` only adds the tmux hooks to it |

## Claude Code in tmux

Every Claude Code session gets its own tmux window, started in the repo or
worktree it works on. Pick that directory with `cmd+shift+n` when opening the
window: a running session cannot move, and `/diff` looks at the directory it
started in. The review popup also follows the repos and worktrees Claude edits
from the window, such as an autofix worktree.

| Ghostty | tmux | Does |
|---------|------|------|
| `cmd+p` | `prefix f` | Switch windows, with a live preview of each; `ctrl-x` kills one, asking first if Claude is still active in it |
| `cmd+shift+n` | `prefix C` | New Claude Code window in a directory you pick |
| `cmd+r` | `prefix e` | [Review popup](#review-popup) for what the window's branch changed |
| | `prefix h` / `prefix v` | Split the pane side by side / top and bottom |
| | `prefix [` | Copy mode with vi keys; `v` selects, `y` copies to the clipboard |

### New window picker

Lists the current directory, every worktree of its repo, then the directories
Claude Code has run in, most recent first. `enter` starts a new conversation
there, `ctrl-o` continues that directory's last one. A directory joins the list
once Claude Code has run in it; before that, `cd` there and pick the current
directory.

### Status marks

`tmux/.config/tmux/scripts/claude-wait.sh` marks each tmux window with what its
Claude Code session is doing:

| Mark | Means |
|------|-------|
| 🔄 | Working |
| 💬 | Needs an answer; also a Ghostty desktop notification, unless that window is already in front of you |
| ✅ | Finished, and you have not looked yet |
| 💤 | You have looked, or no prompt yet |

Claude Code calls it from its hooks, which `install.sh` adds to
`~/.claude/settings.json`, leaving any other hooks there alone.

Windows are labelled by the conversation title Claude Code puts in the pane
title. A session that starts with a slash command never gets one, so a window
can override it with `@claude_label`, which stays until the window closes:

```sh
tmux set -w -t "$TMUX_PANE" @claude_label PROJ-123   # set
tmux set -wu @claude_label                           # back to the title
```

### Review popup

`cmd+r` shows what the window's branch changed, in Neovim with diffview. It
opens on the branch diff: everything since the branch forked from its base,
committed or not. When Claude also edited other repos or worktrees from this
window, such as an autofix worktree, and more than one has changes, it asks
which to open.

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
- The base is the PR's base branch, or else the newest `release/*` or the
  default branch. Without any, only `2` works.
