{ config, lib, pkgs, ... }:

let cfg = config.homelab.anonymity;
in
{
  options.homelab.anonymity.enable = lib.mkEnableOption "Tor + I2P";

  config = lib.mkIf cfg.enable {
    #########################################################################
    # Tor
    #
    # Client + SOCKS proxy on loopback. Deliberately NOT an exit node: exit
    # traffic draws abuse complaints and law-enforcement attention to your
    # home connection, which is the opposite of "super locked down". A middle
    # relay or a bridge is a genuinely useful contribution with none of that
    # exposure — flip `relay` below if you want to help.
    #########################################################################
    services.tor = {
      enable = true;
      client = {
        enable = true;
        socksListenAddress = {
          addr = "127.0.0.1";
          port = 9050;
          IsolateDestAddr = true;
        };
      };
      relay.enable = false; # see above; never set role = "exit" on a home line

      settings = {
        # Onion service for SSH: reach the box even if Tailscale is broken and
        # you're behind hostile NAT. No open ports, no DNS record.
        HiddenServiceDir = "/var/lib/tor/onion/ssh";
        HiddenServicePort = [ "22 127.0.0.1:22" ];

        # Don't act as a DNS resolver for anything but us.
        DNSPort = [{ addr = "127.0.0.1"; port = 9053; }];
        AutomapHostsOnResolve = true;
        AutomapHostsSuffixes = [ ".onion" ];
      };
    };

    #########################################################################
    # I2P (i2pd — the C++ daemon, far lighter than the Java implementation)
    #
    # This is where anonymous torrenting belongs. i2psnark/BiglyBT over I2P is
    # slow but it is the network's intended use, unlike Tor.
    #########################################################################
    services.i2pd = {
      enable = true;
      proto = {
        http = { enable = true; address = "127.0.0.1"; port = 7070; }; # web console
        httpProxy = { enable = true; address = "127.0.0.1"; port = 4444; };
        socksProxy = { enable = true; address = "127.0.0.1"; port = 4447; };
        sam = { enable = true; address = "127.0.0.1"; port = 7656; }; # for torrent clients
      };
      # Contribute bandwidth back to the network; I2P is peer-to-peer and
      # leeching degrades it for everyone.
      bandwidth = 1024; # KB/s
      share = 50; # percent of that offered as transit
    };

    homelab.proxy.routes.i2p = "127.0.0.1:7070";

    environment.systemPackages = with pkgs; [ tor torsocks ];

    # After first boot, your SSH onion address:
    #   sudo cat /var/lib/tor/onion/ssh/hostname
  };
}
