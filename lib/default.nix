# My own library of helpers.  The dependencies (the arguments to this expression-file's function)
# may be given as `null`, to support limited uses of the few parts of this library where those are
# not needed.  This file may be `import`ed by other arbitrary uses independently of the NixOS
# configuration evaluation or of the Nixpkgs evaluation.

#{ pkgs ? import <nixpkgs> { }, lib ? pkgs.lib or null }:
{pkgs, lib ? pkgs.lib, ... }:

let
  inherit (lib) concatStringsSep init length splitString;
  inherit (builtins) isNull;

  scope = rec {
    propagate = { inherit pkgs lib myLib; };

    limitedTo = {
      builtins = import ./limited-to-builtins.nix; # Only allowed to depend on `builtins`.
      lib = import ./limited-to-lib.nix lib; # Only allowed to depend on `lib`.
    };

    userFuncs = import ./userids.nix { inherit pkgs lib; };

    myLib =
      limitedTo.builtins // limitedTo.lib //
      {
        inherit limitedTo;

        inherit (userFuncs) mkUsers mkGroups;

        # makeHelloTestPkg = import ./make-hello-test-package.nix propagate;
        # pkgWithDebuggingSupport = import ./package-with-debugging-support.nix propagate;
        # sourceCodeOfPkg = import ./source-code-of-package.nix propagate;
        tmpfiles = import ./tmpfiles.nix propagate;

        # get first item in list, or null if param was empty list
        # examples:
        #   firstValue [ x y ]    -> x 
        #   firstValue [ x ]      -> x
        #   firstValue "abc"      -> "abc"
        #   firstValue []         -> null
        firstValue = x: if builtins.isList x && builtins.length x == 0 then null else builtins.head (lib.toList x);


        # remove CIDR.   "10.10.10.10/24" -> "10.10.10.10";   "10.10.10.10" -> "10.10.10.10"
        #
        removeCidrMask = x:
          let
            toks = splitString "/" x;
          in
          if length toks > 1
          then concatStringsSep "/" (init toks)
          else builtins.head toks;

        netAddressCIDR = net: "${net.address}/${toString net.prefixLen}";

        addressCIDR = config: cfg:
          "${cfg.address}/${toString config.my.subnets.${cfg.bridge}.prefixLen}";

        # use this as "network = (netDefaults config.my.subnets."SomeNet") // { .. network settings }
        # right side takes precedence
        netDefaults = ctCfg: brCfg:
          let
            useDHCP = brCfg.dhcp.enable && isNull ctCfg.address;
          in
          ({
            hostName = ctCfg.name;
            domain = brCfg.domain;
            useHostResolvConf = lib.mkForce false;
            resolvconf.enable = true;
            nftables.enable = true;
            firewall.enable = true;
            firewall.checkReversePath = false;
            useDHCP = lib.mkForce useDHCP;
          }
          //
          (lib.optionalAttrs (!useDHCP) {
            # set default route
            defaultGateway.address = brCfg.gateway;
            # set namerver and search (will go into /etc/resolv.conf)
            nameservers = brCfg.dnsServers;
            search = [ brCfg.domain ];
          })
          //
          (lib.optionalAttrs (!isNull ctCfg.address) {
            interfaces = {
              ${brCfg.localDev} = {
                ipv4.addresses = [{ address = ctCfg.address; prefixLength = brCfg.prefixLen; }];
              };
            };
          })
          );

        # # Merges list of records, concatenates arrays, if two values can't be merged - the latter is preferred
        # recursiveMerge = attrList:
        #   let f = attrPath:
        #     zipAttrsWith (n: values:
        #       if tail values == []
        #         then head values
        #       else if all isList values
        #         then unique (concatLists values)
        #       else if all isAttrs values
        #         then f (attrPath ++ [n]) values
        #       else last values
        #     );
        #   in f [] attrList;


        # apply standard network configuration
        applyNet = nw: cfg: { };

        # make a unique int using hash of network name
        # allowed values: 1-2^32-1
        nethash =
          let
            hexToInt =
              let
                # single digit hex to int
                htoi = {
                  "0" = 0;
                  "1" = 1;
                  "2" = 2;
                  "3" = 3;
                  "4" = 4;
                  "5" = 5;
                  "6" = 6;
                  "7" = 7;
                  "8" = 8;
                  "9" = 9;
                  "a" = 10;
                  "b" = 11;
                  "c" = 12;
                  "d" = 13;
                  "e" = 14;
                  "f" = 15;
                };
              in
              # multi digit hex to int
              str: lib.pipe str [ lib.stringToCharacters (map (d: htoi."${d}")) (lib.foldl (acc: digit: acc * 16 + digit) 0) ];
          in
          net:
          let 
            key = "${net.name}${if isNull net.gateway then "null" else net.gateway}"; 
          in
          hexToInt (builtins.substring 0 8 (builtins.hashString "sha256" key));

      };
  };
in

scope.myLib
