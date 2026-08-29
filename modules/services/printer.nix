{ config, lib, pkgs, ... }:

let cfg = config.homelab.printer;
in
{
  options.homelab.printer.enable =
    lib.mkEnableOption "Klipper + Moonraker + Mainsail, printer attached over USB";

  config = lib.mkIf cfg.enable {
    # Air-gapped by architecture, not by VLAN: Klipper's mainboard speaks serial
    # over USB and has no network interface in play at all.
    #
    # The klipper *user* is also blocked from reaching the internet by the
    # nftables rule below — no telemetry, no update checks. Inbound from the
    # tailnet still works. Most "isolated printer" setups skip that half.

    homelab.stack.groups.printer = [ "klipper" "moonraker" ];

    services.klipper = {
      enable = true;
      user = "klipper";
      group = "klipper";

      # TODO: this is printer-specific. Start from the sample config for your
      # machine at https://github.com/Klipper3d/klipper/tree/master/config
      # and drop it in as ./printer.cfg next to this file.
      # configFile = ./printer.cfg;

      settings = {
        mcu.serial = "/dev/serial/by-id/CHANGE-ME"; # ls /dev/serial/by-id/
        printer = {
          kinematics = "cartesian";
          max_velocity = 300;
          max_accel = 3000;
          max_z_velocity = 5;
          max_z_accel = 100;
        };
      };

      # Build and flash the mainboard firmware from this config too, so the
      # firmware and host versions can never drift apart.
      firmwares.mcu = {
        enable = false; # TODO: enable once you know your MCU
        serial = "/dev/serial/by-id/CHANGE-ME";
        # configFile = ./firmware-mcu.cfg;
      };
    };

    services.moonraker = {
      enable = true;
      address = "127.0.0.1";
      port = 7125;
      user = "klipper";
      group = "klipper";
      allowSystemControl = true;
      settings = {
        authorization = {
          trusted_clients = [ "127.0.0.1/32" "100.64.0.0/10" ];
          cors_domains = [ "https://printer.${config.homelab.domain}" ];
        };
        octoprint_compat = { };

        # Moonraker's update manager phones home to GitHub on a timer to check
        # for new Klipper/Mainsail releases. Off — updates come from rebuilding
        # this flake, not from a service reaching out on its own.
        update_manager = {
          enable_auto_refresh = false;
          refresh_interval = 0;
        };

        # No announcement feed either; it's another outbound poll.
        announcements.subscriptions = [ ];
      };
    };

    networking.nftables.tables.klipper-egress = {
      family = "inet";
      content = ''
        chain output {
          type filter hook output priority 0; policy accept;

          # Everything below applies only to the klipper user.
          skuid != klipper return

          # Loopback and the tailnet stay reachable, so the web UI works.
          ip  daddr { 127.0.0.0/8, 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 100.64.0.0/10 } return
          ip6 daddr { ::1, fd00::/8, fe80::/10 } return

          # Anything else the klipper user tries to reach: dropped.
          drop
        }
      '';
    };

    services.mainsail = {
      enable = true;
      # NOTE: verify this option exists on your nixpkgs revision — if not, the
      # mainsail static files can be served straight from Caddy:
      #   root * ${pkgs.mainsail}/share/mainsail
      nginx.enable = false;
    };

    homelab.proxy.routes.printer = "127.0.0.1:7125";

    users.users.klipper = {
      isSystemUser = true;
      group = "klipper";
      extraGroups = [ "dialout" ]; # serial access
    };
    users.groups.klipper = { };
  };
}
