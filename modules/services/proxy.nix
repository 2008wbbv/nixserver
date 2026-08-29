{ config, lib, pkgs, ... }:

let
  cfg = config.homelab.proxy;
  inherit (config.homelab) domain;

  # Every service registers itself here by setting homelab.proxy.routes.
  # Keeps the "what runs where" map in one readable place.
  mkVhost = name: upstream: {
    "${name}.${domain}" = {
      extraConfig = ''
        # Caddy's own CA. *.internal is not a public domain, so ACME cannot and
        # must not be attempted for it.
        tls internal

        # Only the tailnet can reach us at all (firewall), but belt and braces:
        @denied not remote_ip 100.64.0.0/10 127.0.0.1/32
        respond @denied "not available here" 403

        reverse_proxy ${upstream}
      '';
    };
  };
in
{
  options.homelab.proxy = {
    enable = lib.mkEnableOption "Caddy reverse proxy on the tailnet";

    routes = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = { jellyfin = "127.0.0.1:8096"; };
      description = ''
        subdomain -> upstream host:port. Service modules add to this; the proxy
        turns each into https://<sub>.<homelab.domain>.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    services.caddy = {
      enable = true;
      # `tls internal` issues from Caddy's own CA. You must trust
      # /var/lib/caddy/.local/share/caddy/pki/authorities/local/root.crt on each
      # client, once. If you'd rather have publicly-trusted certs with no
      # warnings and no open ports, buy a cheap domain and switch to DNS-01:
      #   packages.caddy = pkgs.caddy.withPlugins { ... caddy-dns/cloudflare ... };
      # then replace `tls internal` with your ACME DNS challenge config.
      globalConfig = ''
        auto_https disable_redirects
      '';

      virtualHosts = lib.mkMerge (
        lib.mapAttrsToList (name: upstream: mkVhost name upstream) cfg.routes
      );
    };

    # Caddy binds 80/443 but the firewall only trusts tailscale0, so these are
    # not reachable from the LAN. Intentionally not in allowedTCPPorts.

    systemd.services.caddy.serviceConfig = {
      ProtectHome = true;
      PrivateDevices = true;
      NoNewPrivileges = true;
      RestrictSUIDSGID = true;
    };
  };
}
