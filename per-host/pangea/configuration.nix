{
  config,
  inputs,
  pkgs,
  lib,
  hostname,
  ...
}: let
  inherit (builtins) attrNames listToAttrs isNull;
  inherit (lib) mkOption mkEnableOption types;
  inherit (lib.attrsets) filterAttrs;
in 
{
  imports = [
    (../per-host + "/${hostname}")
  ];

  config = {
 };
}
