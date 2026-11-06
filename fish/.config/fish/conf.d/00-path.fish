# PATH is built here rather than in config.fish because conf.d runs first:
# fnm.fish puts its Node in front from conf.d, and anything that rebuilds or
# reorders PATH afterwards would bury it behind brew's node.

# ghostty starts fish directly rather than through a login shell, so nothing has
# run path_helper and PATH is the bare launchd default: no /usr/local/bin, no
# cryptex paths, no /Library/Apple/usr/bin. Has to stay above the additions below,
# because path_helper moves whatever is already on PATH to the end.
if test -x /usr/libexec/path_helper
    set -gx PATH (/usr/libexec/path_helper -s | string match -rg '^PATH="(.*)";' | string split ":")
end

if test -x /opt/homebrew/bin/brew
    /opt/homebrew/bin/brew shellenv fish | source
end

set -gx PNPM_HOME $HOME/Library/pnpm
# --move because brew shellenv emits `fish_add_path --move`, so in a fish started
# from fish these entries are already on PATH and would otherwise keep brew's
# position ahead of them — putting brew's node and claude back in front.
fish_add_path --global --move --path $HOME/.local/bin $PNPM_HOME
