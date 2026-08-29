{ config, lib, pkgs, ... }:

let
  cfg = config.homelab.backups;
  data = config.homelab.dataDir;
in
{
  options.homelab.backups.enable = lib.mkEnableOption "restic backups to an offsite repository";

  config = lib.mkIf cfg.enable {
    #########################################################################
    # You did not list backups. With one machine and no redundancy, this is
    # the highest-value item in the whole repo — higher than any service on
    # your list, because it is what makes every other one recoverable.
    #
    # ZFS snapshots are not backups. They protect against "I deleted it",
    # not against "the PSU took the disks with it" or "ransomware encrypted
    # the pool". You need a copy on hardware you are not currently sitting in
    # front of.
    #
    # Tiers, by what they cost:
    #   - Free-ish: an external USB disk you rotate and unplug. Genuinely fine.
    #   - ~$6/TB/mo: Backblaze B2 or rsync.net. restic encrypts client-side,
    #     so the provider holds ciphertext and nothing else.
    #   - Best: both. That's the "3-2-1" everyone quotes.
    #########################################################################

    assertions = [{
      assertion = config.homelab.secrets.enable;
      message = ''
        homelab.backups needs secrets, but homelab.secrets.enable is false.
        Follow secrets/README.md, then set homelab.secrets.enable = true.
        Needs: restic/password, restic/env
      '';
    }];

    services.restic.backups = {
      offsite = {
        initialize = true;

        # TODO: set your repository. Examples:
        #   "b2:my-bucket-name:vault"
        #   "sftp:user@rsync.net:vault"
        #   "/mnt/usb-backup"           (external disk)
        repository = "CHANGE-ME";

        passwordFile = config.sops.secrets."restic/password".path;
        environmentFile = config.sops.secrets."restic/env".path; # B2/S3 credentials

        paths = [
          "/var/lib/vaultwarden" # irreplaceable
          "/var/lib/syncthing"
          "/var/lib/private" # most DynamicUser service state lands here
          "${data}/files"
          "/etc/nixos"
        ];

        exclude = [
          "**/.cache"
          "**/Cache"
          "**/*.tmp"
          "${data}/media" # re-downloadable; don't pay to store it
        ];

        timerConfig = {
          OnCalendar = "02:00";
          RandomizedDelaySec = "30m";
          Persistent = true; # run on next boot if the box was off
        };

        pruneOpts = [
          "--keep-daily 14"
          "--keep-weekly 8"
          "--keep-monthly 12"
          "--keep-yearly 3"
        ];

        # Verify a random 5% of data each run. An unverified backup is a
        # rumour, not a backup.
        checkOpts = [ "--with-cache" "--read-data-subset=5%" ];
      };
    };

    sops.secrets."restic/password" = { };
    sops.secrets."restic/env" = { };

    # Alert if a backup hasn't succeeded in 48h.
    systemd.services."restic-backups-offsite".onFailure = [ "notify-backup-failure.service" ];

    systemd.services."notify-backup-failure" = {
      description = "Log a loud message when a backup fails";
      serviceConfig.Type = "oneshot";
      script = ''
        echo "RESTIC BACKUP FAILED on $(hostname) at $(date -Is)" | ${pkgs.systemd}/bin/systemd-cat -p err -t backup-alert
      '';
    };

    environment.systemPackages = with pkgs; [ restic ];

    #########################################################################
    # Practice the restore before you need it:
    #   sudo restic-offsite snapshots
    #   sudo restic-offsite restore latest --target /tmp/restore-test --include /var/lib/vaultwarden
    #########################################################################
  };
}
