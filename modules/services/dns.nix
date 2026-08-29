{ config, lib, pkgs, ... }:

let
  cfg = config.homelab.dns;
  inherit (config.homelab) domain;
in
{
  options.homelab.dns.enable = lib.mkEnableOption "ad-blocking resolver + recursive unbound";

  config = lib.mkIf cfg.enable {
    #########################################################################
    # Why not Pi-hole:
    #
    # Pi-hole is a Docker appliance with its own mutable state directory and
    # web-UI-driven config — everything NixOS is trying to get you away from.
    # AdGuard Home has a native module, the same UX, DNS-over-TLS upstreams,
    # and its whole config is declarative below. You lose nothing.
    #
    # And since you have no router to point at this, Tailscale is the delivery
    # mechanism: set this box's tailnet IP as the global nameserver in the
    # Tailscale admin console with "Override local DNS" on. Every enrolled
    # device then gets filtered DNS *anywhere in the world*, not just at home.
    # This is strictly better than the router-DHCP approach you were planning.
    #########################################################################

    services.adguardhome = {
      enable = true;
      # Bound to loopback; Caddy publishes the UI on the tailnet.
      host = "127.0.0.1";
      port = 3000;
      mutableSettings = false; # config below is the single source of truth
      settings = {
        dns = {
          bind_hosts = [ "0.0.0.0" ]; # firewall restricts this to tailscale0
          port = 53;

          # Talk only to our own recursive resolver. No third party gets to see
          # your full query stream — not Cloudflare, not Google, not your ISP.
          upstream_dns = [ "127.0.0.1:5335" ];
          bootstrap_dns = [ "9.9.9.9" ];

          # Local zone: *.lab.internal resolves to this host.
          rewrites = [
            { domain = domain; answer = "127.0.0.1"; } # TODO: tailnet IP (100.x.y.z)
            { domain = "*.${domain}"; answer = "127.0.0.1"; } # TODO: same
          ];

          ratelimit = 0;
          refuse_any = true;
        };

        filtering = {
          protection_enabled = true;
          filtering_enabled = true;
          # Block malware/phishing at the DNS layer as well as ads.
          safebrowsing_enabled = true;
        };

        filters = [
          { enabled = true; name = "AdGuard DNS filter"; id = 1;
            url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_1.txt"; }
          { enabled = true; name = "OISD Big"; id = 2;
            url = "https://big.oisd.nl"; }
          { enabled = true; name = "Phishing URL Blocklist"; id = 3;
            url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_30.txt"; }
        ];

        # TODO: set a real password hash (bcrypt):
        #   nix-shell -p apacheHttpd --run "htpasswd -B -n -b admin 'yourpassword'"
        # Or drop the block and rely on the tailnet + Caddy for access control.
        users = [ ];
      };
    };

    #########################################################################
    # Recursive resolver. Queries the root servers directly instead of asking
    # a public resolver, with DNSSEC validation. Slower on first lookup,
    # meaningfully more private, and it's the piece that makes "locked down"
    # true rather than aspirational.
    #########################################################################
    services.unbound = {
      enable = true;
      resolveLocalQueries = false; # AdGuard owns :53
      settings = {
        server = {
          interface = [ "127.0.0.1" ];
          port = 5335;
          access-control = [ "127.0.0.0/8 allow" ];

          do-ip4 = true;
          do-ip6 = true;
          do-udp = true;
          do-tcp = true;

          harden-glue = true;
          harden-dnssec-stripped = true;
          harden-below-nxdomain = true;
          harden-referral-path = true;
          use-caps-for-id = true;

          # Don't leak your subnet to authoritative servers.
          qname-minimisation = true;
          aggressive-nsec = true;

          prefetch = true;
          prefetch-key = true;
          cache-min-ttl = 300;
          cache-max-ttl = 86400;

          # Never answer for RFC1918 space from upstream (rebinding protection).
          private-address = [
            "10.0.0.0/8"
            "172.16.0.0/12"
            "192.168.0.0/16"
            "169.254.0.0/16"
            "fd00::/8"
            "fe80::/10"
          ];

          hide-identity = true;
          hide-version = true;
        };
      };
    };

    # DNS is reachable over the tailnet only — trustedInterfaces covers it.
    # Deliberately NOT in allowedUDPPorts: an open resolver on the LAN is a
    # reflection-attack amplifier.
  };
}
