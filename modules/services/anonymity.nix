{ config, lib, pkgs, ... }:

let
  cfg = config.homelab.anonymity;

  transPort = 9040;
  dnsPort = 9053;
  socksPort = 9050;

  # Networks that must never be sent through Tor: loopback, RFC1918, and the
  # tailnet. Without the tailnet exclusion, turning routing on would cut off
  # your own access to the box and you'd be walking to it with a keyboard.
  bypassNets = [
    "127.0.0.0/8"
    "10.0.0.0/8"
    "172.16.0.0/12"
    "192.168.0.0/16"
    "169.254.0.0/16"
    "100.64.0.0/10" # tailnet — critical
    "224.0.0.0/4"
    "255.255.255.255/32"
  ];

  nftRuleset = pkgs.writeText "tor-route.nft" ''
    table ip tor_route {
      chain output {
        type nat hook output priority -100; policy accept;

        # Tor's own traffic must escape, or you get a routing loop.
        meta skuid tor return

        # So must tailscaled's, or the tunnel dies and takes your access
        # with it.
        meta skuid root tcp dport 41641 return
        meta skuid root udp dport 41641 return

        # Local and tailnet destinations bypass Tor entirely.
        ip daddr { ${lib.concatStringsSep ", " bypassNets} } return

        # Only members of the `torified` group get redirected. This is the
        # safety property that makes the toggle usable on a headless box:
        # flipping it on cannot orphan the machine, because system services
        # are not in that group.
        skgid != torified return

        # DNS through Tor's resolver, so lookups don't leak to your ISP.
        udp dport 53 redirect to :${toString dnsPort}
        tcp dport 53 redirect to :${toString dnsPort}

        # Everything else TCP through Tor's transparent proxy.
        # UDP is not carried by Tor at all and is simply dropped below.
        meta l4proto tcp redirect to :${toString transPort}
      }

      chain output_filter {
        type filter hook output priority 0; policy accept;
        # Tor cannot carry UDP. Dropping it is what stops an application from
        # silently falling back to a direct connection and deanonymising you.
        meta skuid tor return
        skgid != torified return
        ip daddr { ${lib.concatStringsSep ", " bypassNets} } return
        meta l4proto udp drop
      }
    }
  '';

  torRoute = pkgs.writeShellApplication {
    name = "tor-route";
    runtimeInputs = with pkgs; [ nftables systemd curl ];
    text = ''
      set -euo pipefail
      case "''${1:-status}" in
        on)
          systemctl start tor-route.service
          echo "tor routing ON for group 'torified'"
          ;;
        off)
          systemctl stop tor-route.service
          echo "tor routing OFF"
          ;;
        status)
          if nft list table ip tor_route >/dev/null 2>&1; then
            echo "tor routing: ON"
          else
            echo "tor routing: OFF"
          fi
          ;;
        test)
          echo -n "direct:   "; curl -s --max-time 15 https://ifconfig.me || echo FAILED
          echo
          echo -n "torified: "
          sg torified -c "curl -s --max-time 30 https://ifconfig.me" || echo FAILED
          echo
          echo "the two addresses above must differ."
          ;;
        *)
          echo "usage: tor-route {on|off|status|test}" >&2
          exit 1
          ;;
      esac
    '';
  };
in
{
  options.homelab.anonymity.enable = lib.mkEnableOption "Tor (toggleable routing) + I2P";

  config = lib.mkIf cfg.enable {
    # Three ways to use Tor, increasing coverage:
    #   1. SOCKS proxy on 127.0.0.1:9050 — point one app at it.
    #   2. `torsocks <cmd>` — one process.
    #   3. `tor-route on` — transparent routing for the `torified` group.
    #
    # Group-scoped rather than whole-host on purpose: this box is headless and
    # reached over Tailscale, and whole-host redirection is how people lock
    # themselves out. Opt processes in:
    #     sg torified -c 'maigret someusername'
    #
    # Not an exit node. Exit traffic points abuse complaints at your home line.

    services.tor = {
      enable = true;
      client = {
        enable = true;
        socksListenAddress = {
          addr = "127.0.0.1";
          port = socksPort;
          IsolateDestAddr = true;
        };
      };
      relay.enable = false;

      settings = {
        TransPort = [{ addr = "127.0.0.1"; port = transPort; }];
        DNSPort = [{ addr = "127.0.0.1"; port = dnsPort; }];
        VirtualAddrNetworkIPv4 = "10.192.0.0/10";
        AutomapHostsOnResolve = true;
        AutomapHostsSuffixes = [ ".onion" ".exit" ];

        # Onion service for SSH: a way back in if Tailscale is broken and
        # you're behind hostile NAT. No open ports, no DNS record.
        HiddenServiceDir = "/var/lib/tor/onion/ssh";
        HiddenServicePort = [ "22 127.0.0.1:22" ];
      };
    };

    users.groups.torified = { };

    # The toggle itself. `systemctl start/stop tor-route` also works, and
    # `systemctl enable` makes it persist across reboots.
    systemd.services.tor-route = {
      description = "Transparent Tor routing for the 'torified' group";
      after = [ "tor.service" "nftables.service" ];
      requires = [ "tor.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkgs.nftables}/bin/nft -f ${nftRuleset}";
        ExecStop = "${pkgs.nftables}/bin/nft delete table ip tor_route";
      };
      # Off at boot; you turn it on when you want it.
      wantedBy = [ ];
    };

    # I2P: separate network, not a Tor alternative. Anonymous torrenting is the
    # design intent here, unlike Tor where it's abuse.
    #
    # `share` costs you real power — you're relaying 24/7. Lower it if that
    # matters more than contributing back.

    services.i2pd = {
      enable = true;
      proto = {
        http = { enable = true; address = "127.0.0.1"; port = 7070; }; # console
        httpProxy = { enable = true; address = "127.0.0.1"; port = 4444; };
        socksProxy = { enable = true; address = "127.0.0.1"; port = 4447; };
        sam = { enable = true; address = "127.0.0.1"; port = 7656; }; # torrent clients
      };
      # Contribute bandwidth back; I2P is peer-to-peer and leeching degrades
      # it for everyone including you.
      bandwidth = 1024; # KB/s
      share = 50; # percent offered as transit
    };

    homelab.proxy.routes.i2p = "127.0.0.1:7070";

    environment.systemPackages = [ torRoute pkgs.tor pkgs.torsocks ];

    #########################################################################
    # Verify before trusting:
    #   tor-route on
    #   tor-route test      # the two IPs must differ
    #   tor-route off
    #
    # Your SSH onion address, after first boot:
    #   sudo cat /var/lib/tor/onion/ssh/hostname
    #########################################################################
  };
}
