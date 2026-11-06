# PATH and brew live in conf.d/00-path.fish, Node in conf.d/fnm.fish — see the notes there about why.

# Credentials and work-only settings live here, outside the repo
set -l local_config (dirname (status --current-filename))/config-local.fish
test -f $local_config && source $local_config
