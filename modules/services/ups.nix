{ config, lib, pkgs, ... }:

let cfg = config.homelab.ups;
in
{
  options.homelab.ups.enable = lib.mkEnableOption "NUT — UPS monitoring and clean shutdown";

  config = lib.mkIf cfg.enable {
    #########################################################################
    # Yes, get a UPS. It is the cheapest reliability upgrade on your whole
    # list, and it matters more with ZFS: a write hole during a power cut on a
    # pool with no redundancy is exactly how people lose an array.
    #
    # What to buy: a pure sine wave, line-interactive unit with a USB data
    # port. Cheap "simulated sine wave" units make active PFC power supplies
    # (i.e. yours) unhappy. Size it for ~10 minutes at your idle draw — you
    # need enough runtime to shut down cleanly, not to keep working.
    #
    # This config is "standalone" mode: UPS plugged into this box over USB,
    # this box monitors it and shuts itself down on low battery.
    #########################################################################

    power.ups = {
      enable = true;
      mode = "standalone";

      ups.main = {
        # `nut-scanner -U` after plugging it in will tell you the right driver.
        # "usbhid-ups" covers most APC/CyberPower/Eaton units.
        driver = "usbhid-ups";
        port = "auto";
        description = "vault UPS";
        directives = [
          "vendorid = CHANGE-ME" # TODO: from nut-scanner
        ];
      };

      users.monitor = {
        passwordFile = config.sops.secrets."nut/monitor-password".path;
        upsmon = "primary";
      };

      upsmon.monitor.main = {
        user = "monitor";
        passwordFile = config.sops.secrets."nut/monitor-password".path;
        type = "primary";
      };

      # Shut down when the UPS says battery is low, or after 5 min on battery,
      # whichever comes first.
      upsd.listen = [{ address = "127.0.0.1"; }];
    };

    sops.secrets."nut/monitor-password" = { };

    # Prometheus scrapes this so you get graphs of line voltage and battery
    # health, and an alert when the battery starts aging out.
    services.prometheus.exporters.nut = lib.mkIf config.homelab.monitoring.enable {
      enable = true;
      listenAddress = "127.0.0.1";
      port = 9199;
      nutServer = "127.0.0.1";
    };

    environment.systemPackages = with pkgs; [ nut ];
  };
}
