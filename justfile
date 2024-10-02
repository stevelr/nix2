
_default:
    just --list

host:
    sudo nixos-rebuild switch --flake .#aster

