# dotfiles

Personal dotfiles managed with [GNU Stow](https://www.gnu.org/software/stow/).

## Packages

| Package | Description |
|---------|-------------|
| **home** | Files stowed directly to `$HOME` — ripgrep config (`~/.ripgreprc`) |
| **fish** | Interactive shell — [Fisher](https://github.com/jorgebucaran/fisher), [Tide](https://github.com/IlanCosman/tide) prompt, [nvm.fish](https://github.com/jorgebucaran/nvm.fish) |
| **nvim** | Neovim config based on [LazyVim](https://www.lazyvim.org/) |
| **tmux** | `C-a` prefix, vi-style copy mode, plugins via [TPM](https://github.com/tmux-plugins/tpm), fzf window picker on `prefix f` (`ctrl-x` kills a window), new Claude Code window on `prefix C`, [Claude Code status](#claude-code-status-in-tmux) in the status bar |
| **ghostty** | Terminal — tokyonight-night, transparent background, launches fish |

> **git** and **zsh** are intentionally not packages — git identity and URL rewrites differ per machine; zsh is only the login shell and gets its PATH from `/etc/paths`. `install.sh` writes `~/.gitconfig` once and never tracks it.

## Install

```sh
git clone https://github.com/AndyWang-505/dotfiles.git ~/dotfiles
cd ~/dotfiles
./install.sh
```

`install.sh` is idempotent. After it runs, fill in machine-local values:

```sh
$EDITOR ~/.gitconfig                      # user.name, user.email
$EDITOR ~/.config/fish/config-local.fish  # credentials, work env vars
```

## Machine-local files

These are untracked on purpose (repo is public):

| File | Purpose |
|------|---------|
| `~/.gitconfig` | Identity and URL rewrites |
| `~/.config/fish/config-local.fish` | Credentials and work env vars |
| `nvim/.../lua/plugins/local/` | Editor config tied to a specific employer |
| `~/.claude/settings.json` | Claude Code settings; holds work context, so only its hooks are documented below |

## Claude Code status in tmux

`tmux/.config/tmux/scripts/claude-wait.sh` marks each tmux window with what its
Claude Code session is doing: yellow ⏳ when it needs an answer, blue ✓ when it
finished and you have not looked yet. Claude Code has to call it, so add these
hooks to `~/.claude/settings.json` on a new machine:

```json
"hooks": {
  "Notification":     [{ "hooks": [{ "type": "command", "command": "\"$HOME/.config/tmux/scripts/claude-wait.sh\" ask" }] }],
  "Stop":             [{ "hooks": [{ "type": "command", "command": "\"$HOME/.config/tmux/scripts/claude-wait.sh\" done" }] }],
  "UserPromptSubmit": [{ "hooks": [{ "type": "command", "command": "\"$HOME/.config/tmux/scripts/claude-wait.sh\" clear" }] }],
  "PostToolUse":      [{ "matcher": "*", "hooks": [{ "type": "command", "command": "\"$HOME/.config/tmux/scripts/claude-wait.sh\" clear" }] }]
}
```
