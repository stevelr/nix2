{
  pkgs,
  lib,
  ...
}: let
  inherit (lib) mkForce;
  inherit (builtins) isNull;
in {
  # Users to have in all the hosts that use this configuration.
  #
  # Since this file is included for containers,
  #
  # Don't forget to set a password with `passwd` for each user, and possibly
  # setup a new ZFS dataset for their home, and then run, as the user,
  # `/etc/nixos/users/setup-home`.
  #
  # Per-host users should instead be defined in `per-host/$HOSTNAME/default.nix`.
  mkUsers = userids: users: (lib.listToAttrs (
    map
    (x: {
      name = x.name;
      value =
        {uid = mkForce userids.${x.name}.uid;}
        # if uid == gid, group name is same as user name
        // (lib.optionalAttrs
          (x.value.uid == x.value.gid && ! isNull x.value.uid)
          {group = "${x.name}";})
        # for interfactive users, set default shell and enable linger
        // (lib.optionalAttrs x.value.isInteractive {
          isNormalUser = true;
          shell = pkgs.zsh;
          linger = true; # allow systemd units to continue running after logout
        })
        # system user
        // (lib.optionalAttrs (! x.value.isInteractive) {
          isSystemUser = true;
        });
    })
    (
      lib.filter
      (x: (
        # only create user if there is a uid
        (! isNull x.value.uid)
        # and user is named or all-users
        && ((lib.length users == 0) || (lib.elem x.name users))
      ))
      (lib.attrsToList userids)
    )
  ));

  mkGroups = userids: groups: (lib.listToAttrs (
    map
    (x: {
      name = x.name;
      value = {gid = mkForce userids.${x.name}.gid;};
    })
    # all groups with gid defined, and
    # either name is in groups or groups is empty
    (
      lib.filter
      (x: (
        # only create group if there is a gid
        (! isNull x.value.gid)
        # and gid == uid (we create both user & group) or there is no uid (we create group only)
        && (x.value.gid == x.value.uid || isNull x.value.uid)
        # and the group is named or all-groups
        && ((lib.length groups == 0) || (lib.elem x.name groups))
      ))
      (lib.attrsToList userids)
    )
  ));
}
