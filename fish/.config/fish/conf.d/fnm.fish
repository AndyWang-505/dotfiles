# Runs after 00-path.fish so fnm's Node lands in front of brew's. --use-on-cd
# switches to a project's .nvmrc on cd and offers to install a missing version
# instead of silently staying on the current one. --log-level quiet drops the
# "Using Node" line on every switch; the install prompt still shows.
#
# Interactive shells only: Tide renders every prompt in a background `fish -c`
# that loads this file too, and would print after each prompt and leave another
# directory under fnm_multishells. It gets PATH from its parent.
if status is-interactive; and type -q fnm
    fnm env --use-on-cd --log-level quiet --shell fish | source
end
