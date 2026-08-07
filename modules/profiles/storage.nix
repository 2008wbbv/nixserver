{ config, lib, pkgs, ... }:

let cfg = config.homelab.storage;
in
{
  options.homelab.storage.enable = lib.mkEnableOption "ZFS bulk storage + snapshots";

  config = lib.mkIf cfg.enable {
    # ZFS notes for a two-disk box:
    #  - You have two disks and need one of them for root. That means a mirror
    #    of your data is not available without a third disk. A single-disk pool
    #    still gives you checksums, snapshots, and compression — bit rot gets
    #    *detected*, just not repaired.
    #  - So: disk 1 = boot + root + nix store, disk 2 = single-vdev data pool,
    #    and offsite restic backups are doing the redundancy job that a mirror
    #    would otherwise do. Add a third disk later and `zpool attach` turns
    #    the data pool into a mirror with no downtime and no rebuild.
    #  - ECC RAM is nice, not required. The "ZFS eats data without ECC" thing is
    #    folklore; ZFS is no worse than any other filesystem there.
    boot.supportedFilesystems = [ "zfs" ];
    boot.zfs.forceImportRoot = false;

    # ZFS defaults its ARC cache to half of RAM. On 32GB that's 16GB it will
    # happily take and only grudgingly give back — which is exactly the memory
    # Ollama wants when a model spills out of the 6750 XT's 12GB of VRAM.
    # Cap it at 8GB; still plenty of cache for a home NAS.
    boot.kernelParams = [ "zfs.zfs_arc_max=8589934592" ];

    services.zfs = {
      autoScrub = {
        enable = true;
        interval = "monthly";
      };
      autoSnapshot = {
        enable = true;
        frequent = 4; # 15-min, kept 1h
        hourly = 24;
        daily = 14;
        weekly = 8;
        monthly = 6;
      };
      # Email on pool degradation. Without a mail setup this still logs loudly
      # to the journal, and monitoring.nix alerts on it.
      zed.settings = {
        ZED_DEBUG_LOG = "/tmp/zed.debug.log";
        ZED_NOTIFY_VERBOSE = true;
      };
    };

    # Directory skeleton, created before any service that writes into it.
    systemd.tmpfiles.rules = [
      "d ${config.homelab.dataDir}            0755 root root -"
      "d ${config.homelab.dataDir}/media      0775 root media -"
      "d ${config.homelab.dataDir}/files      0775 root users -"
      "d ${config.homelab.dataDir}/downloads  0775 root media -"
      "d ${config.homelab.dataDir}/backups    0700 root root -"
    ];

    users.groups.media = { };

    environment.systemPackages = with pkgs; [ zfs ];
  };
}
