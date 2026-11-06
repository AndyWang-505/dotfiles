# Runs after 00-path.fish so fnm's Node lands in front of brew's. --use-on-cd
# switches to a project's .nvmrc on cd and offers to install a missing version
# instead of silently staying on the current one.
if type -q fnm
    fnm env --use-on-cd --shell fish | source
end
