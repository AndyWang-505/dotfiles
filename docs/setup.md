# Setup

For setting up a new Mac: why each of the [README's install steps](../README.md#install)
is there, and what the optional settings do. The commands themselves are in the
README.

- [Before install.sh](#before-installsh)
- [While it runs](#while-it-runs)
- [After it finishes](#after-it-finishes)
- [Machine-local files](#machine-local-files)
- [Shell shortcuts](#shell-shortcuts)

## Before install.sh

A fresh Mac has no working `git` until the Xcode Command Line Tools are in: the
first `git` call only opens their installer, so `xcode-select --install` comes
first. Start from the built-in Terminal app, since Ghostty is one of the things
`install.sh` installs.

## While it runs

Homebrew's installer asks for your password and for Enter, and the first run
takes a while. Each step checks whether it is already done, so running
`install.sh` again skips those. Plugin installs, the steps most likely to fail
on a flaky network, are listed at the end when they fail instead of stopping
the run.

## After it finishes

Do the remaining steps in Ghostty: Terminal's zsh does not have Homebrew on its
PATH, so `brew`, `gh` and `nvim` are not found there.

- **`gh auth login`**: git reaches GitHub over HTTPS rather than SSH, so a new
  machine can clone and push without an SSH key; this signs it in. It also lets
  the review popup compare a branch with its PR's base; without it, the popup
  compares with the newest `release/*` or the default branch.
- **`claude`**: Claude Code signs in on its first run. Its tmux hooks are
  already in `~/.claude/settings.json`.
- **The login shell**: zsh stays the login shell and gets its PATH from
  `/etc/paths`, so it is not a package here. Ghostty starts fish directly, so
  making fish the login shell is optional.

## Machine-local files

The files in the [README's list](../README.md#machine-local-files) stay out of
this public repo. `install.sh` creates `~/.config/fish/config-local.fish` and
`~/.gitconfig` with commented examples, and `config.fish` and git read them
after the tracked config, so they win on conflict.

Git picks the email by the repo's remote. Repos under your own GitHub account
use the personal one; an `includeIf` in `~/.gitconfig` can send another
organisation's repos, such as work repos, to `~/.config/git/work.gitconfig`.
There is no default email: a repo that matches neither refuses to commit rather
than guess one.

## Shell shortcuts

fish abbreviations, in `fish/.config/fish/conf.d/abbr.fish`: `t` attaches the
shared `main` tmux session, `lg` opens lazygit, `gst` and `gl` run `git status`
and `git pull`.
