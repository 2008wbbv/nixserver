{ config, lib, pkgs, ... }:

let cfg = config.homelab.printer;
in
{
  options.homelab.printer.enable =
    lib.mkEnableOption "Klipper + Moonraker + Mainsail, printer attached over USB";

  config = lib.mkIf cfg.enable {
    #########################################################################
    # "3d printer air gapped" — this got *easier* without a router, not harder.
    #
    # You were going to put the printer on an isolated VLAN. But a VLAN'd
    # printer still has a NIC, still runs a vendor firmware you can't audit,
    # and still has a route to something. Klipper's architecture removes the
    # question entirely: the printer's mainboard speaks serial over USB to this
    # host, and has no network interface in play at all.
    #
    # That is a real air gap for the printer, enforced by physics rather than
    # by a switch config. The web UI you interact with lives here, on the
    # tailnet, where you already have access control.
    #
    # If your printer is a network-connected appliance (Bambu, most Prusa
    # Connect setups) this doesn't apply — those need the VLAN treatment, and
    # that has to wait for the switch.
    #########################################################################

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
      };
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
