# DECLARATIVE PARTITIONING (disko) — DESTRUCTIVE.
#
# Importing this file and running disko WILL ERASE the listed devices.
# Do not enable it if the machine still dual-boots Windows or holds data you want.
# If you are keeping an existing partition layout, leave this file unimported and
# let nixos-generate-config describe the disks instead.
#
# Apply (installer only):
#   sudo nix run github:nix-community/disko -- --mode disko ./hosts/vault/disks.nix
#
# Find your real device paths first:  lsblk -o NAME,PATH,SIZE,MODEL,SERIAL
# Use /dev/disk/by-id/... — kernel names (/dev/sda) reorder between boots.
{ lib, ... }:

{
  disko.devices = {
    disk = {
      # --- Boot + root: one fast SSD/NVMe -----------------------------------
      main = {
        type = "disk";
        device = "/dev/disk/by-id/CHANGE-ME-nvme-root"; # TODO
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              size = "1G";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [ "umask=0077" ];
              };
            };
            root = {
              size = "100%";
              content = {
                type = "btrfs";
                extraArgs = [ "-f" ];
                subvolumes = {
                  "/root" = { mountpoint = "/"; mountOptions = [ "compress=zstd" "noatime" ]; };
                  "/nix" = { mountpoint = "/nix"; mountOptions = [ "compress=zstd" "noatime" ]; };
                  "/persist" = { mountpoint = "/persist"; mountOptions = [ "compress=zstd" "noatime" ]; };
                  "/log" = { mountpoint = "/var/log"; mountOptions = [ "compress=zstd" "noatime" ]; };
                };
              };
            };
          };
        };
      };
    };

    # --- Bulk storage: ZFS mirror across two+ spinning disks -----------------
    # Uncomment and fill in once you know what drives you have. A mirror is the
    # minimum that survives a disk death; a single vdev is a countdown timer.
    #
    # zpool.tank = {
    #   type = "zpool";
    #   mode = "mirror";
    #   rootFsOptions = {
    #     compression = "zstd";
    #     acltype = "posixacl";
    #     xattr = "sa";
    #     "com.sun:auto-snapshot" = "true";
    #   };
    #   options.ashift = "12";
    #   datasets = {
    #     media   = { type = "zfs_fs"; mountpoint = "/srv/media"; };
    #     files   = { type = "zfs_fs"; mountpoint = "/srv/files"; };
    #     backups = { type = "zfs_fs"; mountpoint = "/srv/backups"; };
    #   };
    # };
  };
}
