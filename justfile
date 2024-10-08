
# use '[no-cd]' attribute to run from working directory
# set fallback = true     # search parent dir for justfile rules

hostname := shell('hostname -s')
alias rb := rebuild

_default:
    just --list

# rebuild nixos for current host
rebuild:
    just {{hostname}}

comet:
    darwin-rebuild switch --flake .#comet
    #sudo nixos-rebuild switch --flake .#comet

