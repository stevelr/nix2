# Custom packages, that can be defined similarly to ones from nixpkgs
# You can build them using 'nix build .#example'
{
  #  inputs,
  pkgs,
  lib ? pkgs.lib,
  ...
} @ args:
#  hello-world = pkgs.callPackage ./hello-custom {};
# https://github.com/Lord-Valen/configuration.nix/blob/master/comb/lord-valen/packages/default.nix
let
  #  inherit (pkgs) lib;
  inherit (builtins) readDir;
  inherit (lib) callPackageWith filterAttrs mapAttrs;
  inherit (lib.path) append;
  inherit (lib.filesystem) packagesFromDirectoryRecursive;

  callPackage = callPackageWith (pkgs // {inherit args;});
  dirs = filterAttrs (_: type: type == "directory") (readDir ./.);
in
  mapAttrs (
    name: _:
      packagesFromDirectoryRecursive {
        inherit callPackage;
        directory = append ./. name;
      }
  )
  dirs
