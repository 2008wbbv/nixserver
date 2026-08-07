{ config, lib, pkgs, ... }:

let cfg = config.homelab.tailscale;
in
{
  options.homelab.tailscale.enable = lib.mkEnableOption "Tailscale mesh VPN (the only way in)";

  config = lib.mkIf cfg.enable {
    services.tailscale = {
      enable = true;
      # Non-interactive enrolment. Generate a reusable, pre-authorized key in the
      # Tailscale admin console and put it in secrets/secrets.yaml under
      # `tailscale/authkey`. Without this you must run `tailscale up` by hand once.
      authKeyFile = config.sops.secrets."tailscale/authkey".path;

      # Advertise this box as the exit node + subnet router for the LAN, so your
      # phone can route through home. Approve both in the admin console.
      useRoutingFeatures = "both";
      extraUpFlags = [
        "--advertise-exit-node"
        "--ssh"
      ];
    };

    sops.secrets."tailscale/authkey" = { };

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
