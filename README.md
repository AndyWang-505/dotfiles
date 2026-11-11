# dotfiles

A macOS setup for working with Claude Code in the terminal: Ghostty, tmux, fish
and Neovim (LazyVim), wired so that every Claude Code session gets its own tmux
window you can watch, switch to and review.

Configs are symlinked into `$HOME` with
[GNU Stow](https://www.gnu.org/software/stow/). The repo is public, so anything
tied to an employer or holding credentials stays in
[local configuration](#local-configuration).

## Features

- **Terminal**: Ghostty with the TokyoNight theme runs fish with the
  [Tide](https://github.com/IlanCosman/tide) prompt, and
  [fnm](https://github.com/Schniz/fnm) switches Node to a project's `.nvmrc` on
  `cd`.
- **[Claude Code in tmux](#claude-code-in-tmux)**: one window per session,
  started in the repo or worktree you pick. Marks on each window show which
  session is working, waiting for an answer or done, and a desktop notification
  tells you when one asks something.
- **[Review popup](#review-popup)**: `cmd+r` shows what a window's branch
  changed, as one diff, as uncommitted changes only, or commit by commit,
  including worktrees Claude edited from that window.
- **Neovim**: [LazyVim](https://www.lazyvim.org/) with the TypeScript, ESLint,
  Prettier, JSON, YAML and Markdown extras, inline git blame and image paste
  into Markdown.
- **Git identity by remote**: personal repos commit with the personal identity,
  employer repos with the work one, and a repo that matches neither refuses to
  commit instead of guessing an email.
- **One-step install**: `install.sh` sets up everything, Homebrew included, and
  is safe to run again.

## Requirements

- macOS on Apple Silicon
- An administrator account, for Homebrew's installer

## Installation

Run these from the built-in Terminal app, since Ghostty is not installed yet.

1. Install the Xcode Command Line Tools, which provide `git`, and wait for the
   dialog to finish:

   ```sh
   xcode-select --install
   ```

2. Clone the repo and run the installer. Homebrew asks for your password, and
   the first run takes a while.

   ```sh
   git clone https://github.com/AndyWang505/dotfiles.git ~/dotfiles
   cd ~/dotfiles
   ./install.sh
   ```

If it stops, or ends with a list of failed steps, fix what it names and run it
again.

### Post-installation

`install.sh` prints these steps when it finishes. Do them in Ghostty, since
Terminal's shell does not have Homebrew on its PATH.

1. Open Ghostty.
2. Fill in the [local configuration](#local-configuration). Until
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

## Usage

### Keybindings

The tmux prefix is `C-a`. Ghostty's `cmd` shortcuts send the same prefix keys.

| Ghostty | tmux | Does |
|---------|------|------|
| `cmd+p` | `prefix f` | Switch windows, with a live preview of each; `ctrl-x` kills one |
| `cmd+shift+n` | `prefix C` | New Claude Code window in a directory you pick |
| `cmd+r` | `prefix e` | [Review popup](#review-popup) |
| | `prefix h` / `prefix v` | Split the pane side by side / top and bottom |
| | `prefix [` | Copy mode with vi keys; `v` selects, `y` copies |

In fish, `t` attaches the shared `main` tmux session, `lg` opens lazygit, and
`gst` / `gl` run `git status` / `git pull`. In Neovim, `<leader>p` pastes an
image from the clipboard; everything else is LazyVim's defaults.

### Claude Code in tmux

Open each session with `cmd+shift+n` and pick the repo or worktree it works on:
a running session cannot move to another directory. The picker lists the
current directory, the repo's worktrees and the directories Claude Code has run
in; `enter` starts a new conversation, `ctrl-o` continues the last one there.

Each window is marked with what its session is doing:

| Mark | Means |
|------|-------|
| 🔄 | Working |
| 💬 | Waiting for your answer; also a desktop notification |
| ✅ | Finished, not looked at yet |
| 💤 | Idle |

Windows are labelled by the conversation title. A session started with a slash
command has none, so set a label yourself:

```sh
tmux set -w -t "$TMUX_PANE" @claude_label PROJ-123   # set
tmux set -wu @claude_label                           # back to the title
```

### Review popup

`cmd+r` shows what the window's branch changed, in Neovim with diffview. It
opens on the branch diff: everything since the branch forked from its base,
committed or not. When Claude also edited other repos or worktrees from this
window and more than one has changes, it asks which to open.

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

## Configuration

### Repository structure

Each top-level directory is a Stow package, laid out like `$HOME`.

| Package | Configures |
|---------|------------|
| **ghostty** | Ghostty |
| **tmux** | tmux, and the Claude Code scripts in `scripts/` |
| **fish** | fish and its abbreviations |
| **nvim** | Neovim (LazyVim) |
| **git** | git, including the per-remote identities |
| **claude** | The global `~/.claude/CLAUDE.md` |
| **ripgrep** | `~/.ripgreprc` |

### Local configuration

These files are untracked on purpose, since the repo is public:

| File | Holds |
|------|-------|
| `~/.gitconfig` | The `includeIf` that points an employer's repos at `work.gitconfig` |
| `~/.config/git/work.gitconfig` | Employer email |
| `~/.config/fish/config-local.fish` | Credentials and work env vars |
| `nvim/.../lua/plugins/local/` | Editor config tied to a specific employer |
| `~/.claude/settings.json` | Claude Code settings; `install.sh` only adds its hooks |

## Development

Every config is a symlink into `~/dotfiles`, so editing `~/.config/...` edits
the repo. A new file needs `stow --restow <package>` before it shows up.

| Config | Takes effect |
|--------|--------------|
| tmux | `tmux source-file ~/.config/tmux/tmux.conf` |
| Ghostty | `cmd+shift+,` |
| Neovim | Next start |
| fish | A new shell, or `exec fish` |

- **New package**: add the directory to `PACKAGES` in `install.sh`. If the
  program writes into a directory that does not exist yet, create it first, or
  stow links the whole directory into the repo.
- **Neovim plugins**: `install.sh` pins them to `lazy-lock.json`, so commit that
  file after `:Lazy update`.
- **Pull requests**: branches go to a fork (`origin`) and PRs to `upstream`.
  After one merges, `git switch main && git pull upstream main && git push
  origin main`.
