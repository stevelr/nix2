
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

pangea:
    sudo nixos-rebuild --cores 4 build --flake .#pangea --show-trace
    
b:
    nix-build --log-format internal-json -v |& nom --json

aster:
    #sudo nixos-rebuild switch --flake .#aster
    sudo nixos-rebuild --refresh --cores 4 switch --flake .#aster --show-trace

mboot:
    sudo systemctl restart container@media.service
    sudo machinectl shell media
