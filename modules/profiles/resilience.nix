{ config, lib, pkgs, ... }:

# For a machine that gets rebooted into Windows regularly and must come back
# clean, unattended, every time.
#
# The difference from a 24/7 server is that "missed while powered off" is the
# normal case rather than an exception: scheduled work has to catch up,
# services must not care that they were killed mid-flight, and nothing may
# require you to be present.
#
# The most important thing here isn't in this file: NixOS must stay the DEFAULT
# systemd-boot entry. If Windows is default, an unattended reboot leaves the
# server down until you walk over to it. Check with `bootctl status`, and don't
# press 'd' in the boot menu with Windows selected.

let
  # Applied to services whose one-off failure would otherwise go unnoticed for
  # days. StartLimit keeps a genuinely broken unit from thrashing forever.
  retry = {
    serviceConfig = {
      Restart = lib.mkDefault "on-failure";
      RestartSec = lib.mkDefault "10s";
    };
    startLimitIntervalSec = 300;
    startLimitBurst = 5;
  };

  # Only ever name units that actually exist — referencing a missing one
  # creates a broken unit rather than an error you'd notice.
  whenEnabled = cond: names: lib.mkIf cond (lib.genAttrs names (_: retry));
in
{
  # Catch up on everything missed while powered off. Without Persistent, a
  # backup scheduled for 02:00 simply never runs on any night you were gaming
  # — silently. This is the highest-value setting in the file.
  systemd.timers = lib.mkMerge [
    (lib.mkIf config.nix.gc.automatic { nix-gc.timerConfig.Persistent = true; })
    (lib.mkIf config.services.fstrim.enable { fstrim.timerConfig.Persistent = true; })
    (lib.mkIf config.system.autoUpgrade.enable { nixos-upgrade.timerConfig.Persistent = true; })
    (lib.mkIf config.homelab.storage.enable { zpool-scrub.timerConfig.Persistent = true; })
  ];

  systemd.services = lib.mkMerge [
    (whenEnabled config.homelab.dns.enable [ "adguardhome" "unbound" ])
    (whenEnabled config.homelab.proxy.enable [ "caddy" ])
    (whenEnabled config.homelab.vaultwarden.enable [ "vaultwarden" ])
    (whenEnabled config.homelab.media.enable [ "jellyfin" ])
    (whenEnabled config.homelab.monitoring.enable [ "prometheus" "grafana" "loki" ])
    (whenEnabled config.homelab.llm.enable [ "ollama" ])

    {
      # "Network configured" and "network works" are different moments.
      tailscaled = lib.mkIf config.homelab.tailscale.enable {
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
      };

      # Two minutes after boot, once things have settled, log a loud summary of
      # anything that failed. Means `journalctl -b` answers "why didn't it come
      # up" without Grafana needing to be the thing that's working.
      boot-health-check = {
        description = "Report units that failed to start after boot";
        after = [ "multi-user.target" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          ExecStartPre = "${pkgs.coreutils}/bin/sleep 120";
        };
        script = ''
          failed=$(${pkgs.systemd}/bin/systemctl --failed --no-legend --plain \
                   | ${pkgs.gawk}/bin/awk '{print $1}')
          if [ -n "$failed" ]; then
            {
              echo "BOOT HEALTH: these units failed to start:"
              echo "$failed"
            } | ${pkgs.systemd}/bin/systemd-cat -p err -t boot-health
          else
            echo "BOOT HEALTH: all units started cleanly" \
              | ${pkgs.systemd}/bin/systemd-cat -p info -t boot-health
          fi
        '';
      };
    }
  ];

  systemd.network.wait-online.anyInterface = true;

  # If the kernel wedges hard enough that systemd stops petting it, the board
  # resets the machine. Your Z690-class board has an Intel TCO watchdog, so
  # this needs no extra hardware. Turns "down until someone is physically
  # there" into "down for 90 seconds".
  systemd.watchdog = {
    runtimeTime = "30s";
    rebootTime = "10min";
  };

  # Every debugging session here starts after a reboot has already discarded
  # the evidence. `lines` type, so this merges with base.nix's SystemMaxUse.
  #   journalctl -b -1 -p err     # errors from the previous boot
  services.journald.extraConfig = "Storage=persistent";

  # Power the box on remotely instead of walking to it. Also enable "Wake on
  # Magic Packet" and "Restore on AC Power Loss" in BIOS.
  #   wakeonlan <mac>
  systemd.network.links."10-wol" = {
    matchConfig.Type = "ether";
    linkConfig.WakeOnLan = "magic";
  };

  environment.systemPackages = [ pkgs.wakeonlan ];

  # On hard power-off: SQLite in WAL mode and Postgres both recover correctly,
  # and ZFS/btrfs are copy-on-write so an interrupted write leaves the previous
  # consistent state. Nothing to do — noted so you don't go looking.
}
