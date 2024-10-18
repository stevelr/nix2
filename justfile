# justfile for nix configurations

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
    # impure required because of assertions on disk paths in /dev/disk/by-id
    sudo nixos-rebuild --cores 4 --impure switch --flake .#pangea --show-trace

aster:
    sudo nixos-rebuild --refresh --cores 4 switch --flake .#aster --show-trace

mboot:
    sudo systemctl restart container@media.service
    sudo machinectl shell media
