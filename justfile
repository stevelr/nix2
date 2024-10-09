
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

b:
    nix-build --log-format internal-json -v |& nom --json

aster:
    sudo nixos-rebuild switch --flake .#aster --show-trace

