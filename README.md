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
| **tmux** | `C-a` prefix, vi-style copy mode, plugins via [TPM](https://github.com/tmux-plugins/tpm), and the [Claude Code workflow](#claude-code-in-tmux): window picker, new-window picker, status marks and the review popup |
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
| `cmd+r` | `prefix e` | Review what the window's branch changed |

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

### Review popup

`cmd+r` opens nvim with diffview on the window's repo or worktree, starting on
everything the branch changed since it forked from its base. The line at the
top shows the view, the base and whether editing is on. In the diffview's
windows, number keys switch the view and keep the file you were reading:

| Key | Shows |
|-----|-------|
| `1` | The branch diff it starts on, uncommitted changes included but not untracked files (git cannot diff those against a commit) |
| `2` | Only the uncommitted changes, untracked files included |
| `3` | The branch's commits, newest first; pick one to see its diff. Merge commits are left out, so merging the base in does not list its changes |
| `<leader>ge` | Toggle editing |

The popup starts read-only, so a stray key cannot change a file. That covers
diffview's own restore (`X`) and stage (`s`, `-`, `S`, `U`) keys, and search
and replace (`<leader>sr`) is off. With editing on, the right side of `1` and
`2` is the real file.

The number keys only work in the diffview's own windows, so counts like `5j`
still work in other tabs; go back to the diff (`gT`) to switch.

The base is the open PR's base branch, if it is fetched; otherwise whichever of
the newest `release/*` and the default branch the branch forked from most
recently, taken from `upstream` in a fork and from `origin` otherwise. Without
any base, for example in a repo with no remote, only `2` works. Finding the base
asks GitHub for the PR, so the popup takes about a second to open.

`<S-h>` / `<S-l>` step through the changed files in the diff windows; in the
commit list, `L` shows the full commit message. `/` searches the side the cursor
is on. From the diff's tab, whatever you pick in a search (`<leader>/`,
`<leader>sg`, `<leader><space>` for files) or jump to (`gd`, `gr`) opens in a
new tab, so the diff stays; in that tab they work as usual, and `:q` goes back.
Each popup starts a fresh nvim, so the first go-to-definition waits for the
language server.

Closing the diffview (`:qa`, `<leader>gq` or `:DiffviewClose`) closes the popup,
other tabs included, asking first about unsaved edits.

`tmux/.config/tmux/scripts/review-dirs.sh` records every repo or worktree
Claude Code edits a file in (`Edit`, `Write`, `NotebookEdit`) in the window
option `@review_dirs`; `install.sh` adds it to the hooks. Files changed only
through shell commands are not recorded. When any recorded directory has
uncommitted changes or commits of its own, the popup lists them, newest first,
with the window's own directory on top if it has changes too and left out if it
has none; a single choice opens directly. Closing the diffview then returns to
the list, and `esc` closes the popup.
