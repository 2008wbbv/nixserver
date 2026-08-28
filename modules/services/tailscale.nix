{ config, lib, pkgs, ... }:

let cfg = config.homelab.tailscale;
in
{
  options.homelab.tailscale.enable = lib.mkEnableOption "Tailscale mesh VPN (the only way in)";

  config = lib.mkIf cfg.enable {
    services.tailscale = {
      enable = true;

      # Only wired up once secrets exist. On a fresh install you enrol by hand:
      #
      #     sudo tailscale up --ssh --advertise-exit-node
      #
      # ...which prints a URL to open. That is a one-time thing and the node
      # stays enrolled across rebuilds, so the auth key is a convenience for
      # rebuilding from scratch rather than a requirement.
      authKeyFile = lib.mkIf config.homelab.secrets.enable
        config.sops.secrets."tailscale/authkey".path;

      # Advertise this box as the exit node + subnet router for the LAN, so your
      # phone can route through home. Approve both in the admin console.
      useRoutingFeatures = "both";
      extraUpFlags = [
        "--advertise-exit-node"
        "--ssh"
      ];
    };

    sops.secrets."tailscale/authkey" =
      lib.mkIf config.homelab.secrets.enable { };

    # Required for exit-node / subnet-router use.
    boot.kernel.sysctl = {
      "net.ipv4.ip_forward" = 1;
      "net.ipv6.conf.all.forwarding" = 1;
    };

    # UDP 41641 helps Tailscale make direct connections instead of falling back
    # to a DERP relay. It is the one inbound port worth opening on the LAN.
    networking.firewall.allowedUDPPorts = [ config.services.tailscale.port ];

    # Tailscale rewrites resolv.conf for MagicDNS; let it.
    networking.firewall.checkReversePath = "loose";

    environment.systemPackages = [ pkgs.tailscale ];
  };
}
