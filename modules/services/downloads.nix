{ config, lib, pkgs, ... }:

let
  cfg = config.homelab.downloads;
  data = config.homelab.dataDir;
in
{
  options.homelab.downloads.enable =
    lib.mkEnableOption "torrent client, confined to a VPN network namespace";

  config = lib.mkIf cfg.enable {
    # Kill-switch by construction: the client runs in a network namespace whose
    # only route is the WireGuard tunnel. If the tunnel drops there is no
    # default route, so there is no leak path to misconfigure.
    #
    # Never route torrents over Tor — the tracker announce carries your real IP
    # regardless of the SOCKS proxy, and exit operators get the abuse reports.
    # I2P (anonymity.nix) is where anonymous torrenting belongs.

    homelab.stack.groups.downloads = [ "transmission" ];

    vpnNamespaces.wg = {
      enable = true;

      # Download a WireGuard config from your provider (Mullvad/IVPN/ProtonVPN),
      # then encrypt it into sops. It contains a private key — it must not be
      # committed in plaintext or sit in the Nix store.
      #   sops secrets/wireguard.conf
      wireguardConfigFile = config.sops.secrets."wireguard/torrent".path;

      # Which sources may reach services published out of the namespace.
      # Tailnet + loopback only; the LAN is not on this list.
      accessibleFrom = [
        "100.64.0.0/10"
        "127.0.0.1/32"
      ];

      # Expose the web UI from inside the namespace back onto the host, so
      # Caddy can proxy it.
      portMappings = [{ from = 9091; to = 9091; }];

      # Let the peer reach our listening port for inbound connections. Only
      # useful if your provider supports port forwarding.
      openVPNPorts = [{ port = 51820; protocol = "both"; }];
    };

    sops.secrets."wireguard/torrent" = { };

    services.transmission = {
      enable = true;
      package = pkgs.transmission_4;
      group = "media";
      settings = {
        download-dir = "${data}/media";
        incomplete-dir = "${data}/downloads/.incomplete";
        incomplete-dir-enabled = true;
        watch-dir-enabled = false;

        rpc-bind-address = "0.0.0.0"; # inside the namespace only
        rpc-port = 9091;
        rpc-whitelist-enabled = false;
        rpc-host-whitelist-enabled = false;
        rpc-authentication-required = true;
        rpc-username = "admin";
        # TODO: replace. Transmission accepts a plaintext password here and
        # rewrites it to a salted hash (prefixed with '{') on first start; copy
        # that hash back here afterwards so rebuilds stop resetting it.
        rpc-password = "CHANGE-ME";

        peer-port = 51820;
        port-forwarding-enabled = false; # the namespace handles this
        encryption = 2; # require encryption
        pex-enabled = true;
        dht-enabled = true;

        umask = 2; # group-writable, so *arr can move files
        ratio-limit = 2.0;
        ratio-limit-enabled = true;
      };
    };

    # The line that actually does the confining.
    systemd.services.transmission.vpnConfinement = {
      enable = true;
      vpnNamespace = "wg";
    };

    homelab.proxy.routes.torrent = "127.0.0.1:9091";

    #########################################################################
    # Verify the confinement after your first build. Do not skip this:
    #
    #   # should print the VPN exit IP, NOT yours
    #   sudo ip netns exec wg curl -s https://ifconfig.me; echo
    #
    #   # should print YOUR ip, proving the namespace is actually separate
    #   curl -s https://ifconfig.me; echo
    #
    #   # stop the tunnel and confirm the namespace goes dark
    #   sudo ip netns exec wg curl -m 5 https://ifconfig.me   # must time out
    #########################################################################
  };
}
