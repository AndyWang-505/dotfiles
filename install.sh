#!/usr/bin/env bash
# Bootstrap a fresh macOS machine from this repo. Safe to re-run.
set -euo pipefail

if [ "$(uname)" != Darwin ]; then
  echo "This script is macOS-only: it assumes Homebrew paths, pbcopy and the keychain." >&2
  exit 1
fi

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGES=(home nvim tmux ghostty fish)

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
skip() { printf '    %s\n' "$*"; }

# Plugin installs are recoverable by hand and the most likely thing to fail on a
# flaky network, so they must not abort a run that already placed every config.
WARNINGS=()
try() { "$@" || WARNINGS+=("$*"); }

# ---------------------------------------------------------------- Homebrew ---
if command -v brew >/dev/null 2>&1; then
  skip "Homebrew already installed"
else
  log "Installing Homebrew"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

# The installer does not touch the current shell's PATH.
if [ -x /opt/homebrew/bin/brew ]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
elif [ -x /usr/local/bin/brew ]; then
  eval "$(/usr/local/bin/brew shellenv)"
fi

log "Installing packages from Brewfile"
# --no-upgrade so re-running does not silently bump everything already installed;
# HOMEBREW_NO_INSTALL_CLEANUP so it does not garbage-collect other formulae.
HOMEBREW_NO_INSTALL_CLEANUP=1 brew bundle install --no-upgrade --file="$DOTFILES_DIR/Brewfile"

# ------------------------------------------------------- machine-local files --
# git config is per-machine (identity, and URL rewrites that exist only because a
# given work repo cannot be cloned over SSH here), so the repo ships none of it.
# Written key by key rather than as one template: a ~/.gitconfig that another tool
# already created still has to end up with the URL rewrite, which is the one
# setting here that is painful to rediscover.
GITCONFIG="$HOME/.gitconfig"

if [ -f "$GITCONFIG" ]; then
  skip "~/.gitconfig exists"
else
  log "Creating ~/.gitconfig"
  printf '# Machine-local. Not tracked by the dotfiles repo.\n' >"$GITCONFIG"
fi

git config --file "$GITCONFIG" alias.co checkout
git config --file "$GITCONFIG" url."https://github.com/".insteadOf "git@github.com:"

# Deliberately no placeholder identity, but a missing one is not caught by git
# either: it falls back to the macOS account's full name and a hostname-based
# email and commits anyway. So warn when either key is missing.
if ! git config --file "$GITCONFIG" --get user.name >/dev/null ||
  ! git config --file "$GITCONFIG" --get user.email >/dev/null; then
  WARNINGS+=("set user.name and user.email in $GITCONFIG")
fi

# --------------------------------------------------------------------- stow --
# Simulate first: stow's own failure output is hard to act on mid-script.
if ! conflicts=$(stow --dir="$DOTFILES_DIR" --target="$HOME" --no --restow "${PACKAGES[@]}" 2>&1); then
  printf '%s\n' "$conflicts" >&2
  cat >&2 <<'EOF'

Files already exist where stow wants to put symlinks (see above). Move or delete
them, then re-run this script.
EOF
  exit 1
fi

log "Stowing packages: ${PACKAGES[*]}"
stow --dir="$DOTFILES_DIR" --target="$HOME" --restow "${PACKAGES[@]}"

# ---------------------------------------------------------------------- tmux --
# TPM has to exist before `prefix + I` does anything.
TPM_DIR="$HOME/.config/tmux/plugins/tpm"
if [ -d "$TPM_DIR" ]; then
  skip "TPM already cloned"
else
  log "Cloning TPM"
  try git clone --depth 1 https://github.com/tmux-plugins/tpm "$TPM_DIR"
fi

log "Installing tmux plugins"
try "$TPM_DIR/bin/install_plugins"

# ---------------------------------------------------------------------- fish --
# fisher lists itself in fish_plugins, so bootstrapping it is enough.
if fish -c 'functions -q fisher' 2>/dev/null; then
  skip "fisher already installed"
else
  log "Installing fisher"
  try fish -c 'curl -sL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish | source && fisher install jorgebucaran/fisher'
fi

log "Installing fish plugins from fish_plugins"
try fish -c 'fisher update'

# Written after stow so the stowed config.fish is already in place to source it.
FISH_LOCAL="$HOME/.config/fish/config-local.fish"
if [ -f "$FISH_LOCAL" ]; then
  skip "$FISH_LOCAL exists"
else
  log "Creating $FISH_LOCAL"
  cat >"$FISH_LOCAL" <<'EOF'
# Machine-local fish config. Not tracked by the dotfiles repo.
# set -gx MY_VAR value
EOF
fi

# ---------------------------------------------------------------------- node --
# The Brewfile installs nvm, which ships no Node version of its own. Without one
# mason cannot install the npm-backed tooling the typescript, eslint and prettier
# extras rely on.
#
# nvm.fish creates ~/.nvm/versions/node (holding only an .index) when fisher
# installs it above, so only an actual version under it counts.
if ls -d "$HOME"/.nvm/versions/node/v*/ >/dev/null 2>&1; then
  skip "Node already installed"
else
  log "Installing the LTS Node version"
  try bash -c 'export NVM_DIR="$HOME/.nvm"; mkdir -p "$NVM_DIR"; . "$(brew --prefix nvm)/nvm.sh"; nvm install --lts'
fi

# nvm.fish puts a version on PATH only when nvm_default_version is set, and the
# bash nvm install above sets just nvm's own default alias. Pinning fish to that
# alias keeps both shells on the same Node.
if fish -c 'set -q nvm_default_version' 2>/dev/null; then
  skip "nvm_default_version already set"
else
  node_default=$(bash -c 'export NVM_DIR="$HOME/.nvm"; . "$(brew --prefix nvm)/nvm.sh"; nvm version default' 2>/dev/null || true)
  if [ -n "$node_default" ] && [ "$node_default" != N/A ]; then
    log "Setting nvm_default_version to $node_default"
    try fish -c "set -U nvm_default_version $node_default"
  else
    WARNINGS+=("set nvm_default_version in fish: no default Node version found")
  fi
fi

# ---------------------------------------------------------------------- nvim --
LOCKFILE="$DOTFILES_DIR/nvim/.config/nvim/lazy-lock.json"

# After a restore lazy.nvim rewrites lazy-lock.json from the plugins in the
# current spec, so on a machine without plugins/local it drops the pins of the
# employer-only plugins. The plugins themselves are already at the pinned
# commits, so putting the tracked file back loses nothing. Only done when we are
# the ones who dirtied it.
lock_was_clean=false
git -C "$DOTFILES_DIR" diff --quiet -- "$LOCKFILE" && lock_was_clean=true

log "Installing Neovim plugins"
try nvim --headless "+Lazy! restore" +qa

if [ "$lock_was_clean" = true ] && ! git -C "$DOTFILES_DIR" diff --quiet -- "$LOCKFILE"; then
  git -C "$DOTFILES_DIR" checkout -- "$LOCKFILE"
fi

# --------------------------------------------------------------------- done ---
log "Done"

if [ ${#WARNINGS[@]} -gt 0 ]; then
  printf '\n\033[1;33mThese steps failed and need a re-run or a manual fix:\033[0m\n'
  printf '  - %s\n' "${WARNINGS[@]}"
fi

cat <<EOF

Left for you to do by hand:
  - Put your real values in ~/.gitconfig and ~/.config/fish/config-local.fish
  - ghostty runs fish already. Only chsh if you also want it as the login shell:
      echo \$(brew --prefix)/bin/fish | sudo tee -a /etc/shells
      chsh -s \$(brew --prefix)/bin/fish
EOF
