# This file defines overlays
{inputs, ...}: let
  pkgs = inputs.nixpkgs;
  lib = pkgs.lib;
  isStableVersion = pkgs: isNull (lib.match "pre.*" lib.trivial.versionSuffix);
in {
  nixpkgs.overlays = [
    # convention: use args self,super for inheritance; final,prev for new/old

    # library of helpers.)
    (final: _prev:
      assert ! (_prev ? myLib); {
        myLib = import ../lib {pkgs = final;};
      })

    # Make the nixos-unstable channel available as pkgs.unstable, for stable
    # versions of pkgs only.
    (final: _prev:
      if isStableVersion _prev
      then {
        unstable = assert ! (_prev ? unstable);
        # Pass the same config so that attributes like allowUnfreePredicate
        # are propagated.
          import inputs.nixpkgs-unstable {
            # config = config // { allowUnfree = true; };
            inherit (final) config system;
          };
      }
      else {})

    # additional files
    # (import more_overlays)
  ];
}
