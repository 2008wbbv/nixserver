{ config, lib, pkgs, ... }:

let
  cfg = config.homelab.comms;
  inherit (config.homelab) domain;
in
{
  options.homelab.comms.enable = lib.mkEnableOption "Matrix homeserver (Conduit) + Mumble";

  config = lib.mkIf cfg.enable {
    #########################################################################
    # "Communications" is the vaguest item on your list, so this is a starting
    # position rather than an answer. The tradeoff that matters:
    #
    #   Matrix federates. That means a public, reachable server — which
    #   directly contradicts "nothing public". A tailnet-only Matrix server
    #   works, but only for people you've enrolled in your tailnet, and then
    #   federation buys you nothing.
    #
    # So pick a lane:
    #   a) Tailnet-only, no federation (this config). Group chat for you and
    #      whoever you've added. Zero exposure.
    #   b) Federated Matrix. Needs the VPS-front arrangement we discussed and
    #      real TLS on a real domain. Doable later; the module barely changes.
    #   c) Skip the server: SimpleX or Signal give you better properties than
    #      a self-hosted homeserver for 1:1 and small groups, with nothing to
    #      run. Honestly the right call for most people.
    #
    # Conduit (Rust, single binary, sqlite) instead of Synapse (Python,
    # Postgres, hungry) because you have one box and one user.
    #########################################################################

    services.matrix-conduit = {
      enable = true;
      settings.global = {
        server_name = "matrix.${domain}";
        address = "127.0.0.1";
        port = 6167;
        database_backend = "rocksdb";

        allow_registration = false;
        allow_federation = false; # see (a) above
        allow_encryption = true;

        trusted_servers = [ ];
        max_request_size = 20000000;
      };
    };

    homelab.proxy.routes.matrix = "127.0.0.1:6167";

    # Element web client, served as static files by Caddy.
    services.caddy.virtualHosts."chat-web.${domain}".extraConfig = ''
      tls internal
      @denied not remote_ip 100.64.0.0/10 127.0.0.1/32
      respond @denied "not available here" 403
      root * ${pkgs.element-web}
      file_server
    '';

    # Mumble: low-latency voice, tiny footprint, no accounts needed.
    services.murmur = {
      enable = true;
      openFirewall = false; # tailnet only
      bandwidth = 128000;
      users = 20;
      # Password lives in sops rather than the world-readable Nix store.
      environmentFile = config.sops.secrets."murmur/env".path;
    };
    sops.secrets."murmur/env" = { };
  };
}
