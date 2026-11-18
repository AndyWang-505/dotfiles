# Maintaining

For changing this repo: how edits reach `$HOME`, adding a package, the colour
files, the tests and how changes go in.

- [Editing configs](#editing-configs)
- [Adding a package](#adding-a-package)
- [Colours](#colours)
- [Tests](#tests)
- [Changes](#changes)

## Editing configs

Every config is a symlink into `~/dotfiles`. A new file shows up in `$HOME`
after `stow --restow <package>`, run from `~/dotfiles`.

After `:Lazy update`, commit `nvim/.config/nvim/lazy-lock.json`: `install.sh`
puts plugins back to the versions in it.

## Adding a package

A package is a directory laid out like `$HOME`, listed in `PACKAGES` in
`install.sh`. When a directory it stows into does not exist yet, stow links the
whole directory into the repo, so whatever the program later writes there lands
in `~/dotfiles`. If the program writes into that directory, create it before
stowing and add the same `mkdir -p` to `install.sh`, as it does for
`~/.claude`; `.gitignore` lists what plugin managers write into folded
directories.

## Colours

Everything uses tokyonight-night. Ghostty and nvim name the theme; three files
spell out its colours, so a new theme changes them too:
`fish/.config/fish/conf.d/theme.fish`, `tmux/.config/tmux/tmux.conf` and
`tmux/.config/tmux/scripts/fzf-theme.sh`.

## Tests

Before a PR that touches `tmux/`, run `tests/tmux.sh`. It checks the scripts
behind the [Claude Code workflow](claude-code-in-tmux.md) on its own tmux
server with a scratch home, so it is safe to run any time. CI also runs it,
shellcheck, stylua, a fish syntax check and, when a PR changes a package's
config, the Brewfile or the installer, a full `install.sh` on macOS.

## Changes

Changes go in through PRs. The author's clone pushes branches to a fork
(`origin`) and opens PRs against `upstream`; a clone made by the README has
only `origin`, so set the two up first:

```sh
git remote rename origin upstream
git remote add origin https://github.com/<you>/dotfiles.git
```

Once a PR merges:

```sh
git switch main && git pull upstream main
git push origin main   # bring the fork along
```
