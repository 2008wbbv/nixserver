{ config, lib, pkgs, ... }:

let cfg = config.homelab.storage;
in
{
  options.homelab.storage.enable = lib.mkEnableOption "ZFS bulk storage + snapshots";

  config = lib.mkIf cfg.enable {
    # ZFS notes for a single box:
    #  - A single-disk pool gives you checksums and snapshots but NOT redundancy.
    #    Bit rot gets *detected*, not repaired. Two disks in a mirror is the
    #    first configuration worth calling storage.
    #  - ECC RAM is nice, not required. The "ZFS eats data without ECC" thing is
    #    folklore; ZFS is no worse than any other filesystem there.
    #  - Budget ~1GB RAM per TB for comfortable ARC behaviour.
    boot.supportedFilesystems = [ "zfs" ];
    boot.zfs.forceImportRoot = false;

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
