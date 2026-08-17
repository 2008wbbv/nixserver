{ config, lib, pkgs, ... }:

# Designed for a machine that gets rebooted into Windows regularly and must
# come back clean, unattended, every time.
#
# The difference between this and a 24/7 server is not reliability tricks —
# it's that "missed while powered off" becomes the normal case rather than an
# exception. Scheduled work has to catch up, services have to not care that
# they were killed mid-flight, and nothing may require you to be present.

{
  #############################################################################
  # 1. Come back to the SERVER, not to Windows
  #
  # The most important line in this file. If anything reboots the machine
  # unattended — a watchdog, a power blip with BIOS auto-power-on, a kernel
  # panic — it has to land in NixOS. If Windows is the default boot entry,
  # an unattended reboot leaves the server down until you physically walk
  # over and pick from a menu.
  #
  # NixOS writes itself as the systemd-boot default, so this normally just
  # works. Verify after install:
  #     bootctl status | grep -i default
  # And do NOT press 'd' in the boot menu while Windows is selected — that
  # makes Windows sticky.
  #############################################################################

  #############################################################################
  # 2. Catch up on everything missed while powered off
  #
  # Persistent=true means "if the machine was off when this should have run,
  # run it shortly after next boot". Without it, a backup scheduled for 02:00
  # simply never happens on any day you were gaming at 02:00 — silently.
  #
  # This is the single highest-value setting for your usage pattern.
  #############################################################################
  systemd.timers = lib.mkMerge [
    (lib.mkIf config.nix.gc.automatic {
      nix-gc.timerConfig.Persistent = true;
    })
    (lib.mkIf config.services.fstrim.enable {
      fstrim.timerConfig.Persistent = true;
    })
    (lib.mkIf config.system.autoUpgrade.enable {
      nixos-upgrade.timerConfig.Persistent = true;
    })
    (lib.mkIf config.homelab.storage.enable {
      # ZFS scrub. Monthly on a box that's off half the time otherwise means
      # "roughly never".
      zpool-scrub.timerConfig.Persistent = true;
    })
  ];

  #############################################################################
  # 3. Services retry instead of giving up
  #
  # The failure mode this prevents: a service starts before the network or a
  # mount is ready, fails once, and stays dead until you notice days later.
  # StartLimit* keeps a genuinely broken service from thrashing forever.
  #############################################################################
  systemd.services =
    let
      retry = {
        serviceConfig = {
          Restart = lib.mkDefault "on-failure";
          RestartSec = lib.mkDefault "10s";
        };
        startLimitIntervalSec = 300;
        startLimitBurst = 5;
      };
      # Only services that are actually defined — referencing a unit that
      # doesn't exist creates a broken one.
      whenEnabled = cond: names:
        lib.mkIf cond (lib.genAttrs names (_: retry));
    in
    lib.mkMerge [
      (whenEnabled config.homelab.dns.enable [ "adguardhome" "unbound" ])
      (whenEnabled config.homelab.proxy.enable [ "caddy" ])
      (whenEnabled config.homelab.vaultwarden.enable [ "vaultwarden" ])
      (whenEnabled config.homelab.media.enable [ "jellyfin" ])
      (whenEnabled config.homelab.monitoring.enable [ "prometheus" "grafana" "loki" ])
      (whenEnabled config.homelab.llm.enable [ "ollama" ])
    ];

  #############################################################################
  # 4. Wait for the network to actually be up
  #
  # "Network is configured" and "network works" are different moments. Things
  # that dial out on startup need the second one.
  #############################################################################
  systemd.services.tailscaled = lib.mkIf config.homelab.tailscale.enable {
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
  };
  systemd.network.wait-online.anyInterface = true;

  #############################################################################
  # 5. Hardware watchdog
  #
  # If the kernel wedges hard enough that systemd stops petting the watchdog,
  # the board resets the machine. Your Z690-class board has an Intel TCO
  # watchdog, so this needs no extra hardware.
  #
  # Without it, a hang means the server is down until you're physically there.
  # With it, it's down for 90 seconds.
  #############################################################################
  systemd.watchdog = {
    runtimeTime = "30s";
    rebootTime = "10min";
  };

  #############################################################################
  # 6. Keep logs across reboots
  #
  # Default journald config on many systems is volatile — reboot and the
  # evidence of why something failed is gone. Since every debugging session
  # here starts with "it was fine when I left it", persist them.
  #
  #   journalctl -b -1 -p err     # errors from the previous boot
  #############################################################################
  # extraConfig is a `lines` type, so this merges with the SystemMaxUse setting
  # in base.nix rather than conflicting with it.
  services.journald.extraConfig = "Storage=persistent";

  #############################################################################
  # 7. Tell me what didn't come up
  #
  # Runs a couple of minutes after boot, once things have settled, and logs a
  # loud summary of any failed unit. Prometheus alerts on it too (see
  # monitoring.nix), but this means the answer is in `journalctl -b` without
  # needing Grafana to be the thing that's working.
  #############################################################################
  systemd.services.boot-health-check = {
    description = "Report units that failed to start after boot";
    after = [ "multi-user.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStartPre = "${pkgs.coreutils}/bin/sleep 120";
    };
    script = ''
      failed=$(${pkgs.systemd}/bin/systemctl --failed --no-legend --plain | ${pkgs.gawk}/bin/awk '{print $1}')
      if [ -n "$failed" ]; then
        echo "BOOT HEALTH: the following units failed to start:" \
          | ${pkgs.systemd}/bin/systemd-cat -p err -t boot-health
        echo "$failed" | ${pkgs.systemd}/bin/systemd-cat -p err -t boot-health
      else
        echo "BOOT HEALTH: all units started cleanly" \
          | ${pkgs.systemd}/bin/systemd-cat -p info -t boot-health
      fi
    '';
  };

  #############################################################################
  # 8. Wake-on-LAN
  #
  # Lets you power the box on remotely instead of walking to it — useful when
  # you shut down into Windows, then leave, then want Jellyfin.
  #
  #   wakeonlan <mac>        from any machine on the LAN
  #
  # Also enable "Wake on Magic Packet" / "ErP off" in BIOS, and turn on
  # "Restore on AC Power Loss" while you're in there so a power blip brings
  # the machine back rather than leaving it off.
  #############################################################################
  systemd.network.links."10-wol" = {
    matchConfig.Type = "ether";
    linkConfig.WakeOnLan = "magic";
  };

  #############################################################################
  # 9. Databases survive being killed
  #
  # You will hard-power-off this machine at some point. SQLite in WAL mode and
  # Postgres both handle that correctly — but only if they're not running with
  # fsync disabled, which nothing here does. The real risk is ZFS/btrfs, and
  # both are copy-on-write, so an interrupted write leaves the previous
  # consistent state rather than a torn one.
  #
  # In other words: this is already fine. Noted so you don't go looking for a
  # problem that isn't there.
  #############################################################################

  environment.systemPackages = with pkgs; [ wakeonlan ];
}
