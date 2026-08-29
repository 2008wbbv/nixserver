{ config, lib, pkgs, ... }:

let
  cfg = config.homelab.comms;
  inherit (config.homelab) domain;
in
{
  options.homelab.comms.enable = lib.mkEnableOption "Matrix (Synapse) + XMPP (Prosody)";

  config = lib.mkIf cfg.enable {
    #########################################################################
    # Matrix — Synapse, the reference homeserver.
    #
    # Heavier than Conduit (Python + Postgres rather than one Rust binary),
    # but it's the one that actually works with every client, every bridge,
    # and spaces/threads without caveats. With 33GB of RAM the weight is not
    # your problem.
    #
    # Federation stays OFF: federating means a publicly reachable server,
    # which contradicts the tailnet-only posture. Everything below works fine
    # for you and anyone you enroll in your tailnet. Turning federation on
    # later needs the VPS-front arrangement, not a config flag.
    #########################################################################

    homelab.stack.groups.comms = [ "matrix-synapse" "prosody" "postgresql" ];

    services.postgresql = {
      enable = true;
      # Synapse requires C collation. Getting this wrong means a broken
      # database you can only fix by dumping and reimporting.
      initialScript = pkgs.writeText "synapse-init.sql" ''
        CREATE ROLE "matrix-synapse" WITH LOGIN PASSWORD 'synapse';
        CREATE DATABASE "matrix-synapse" WITH OWNER "matrix-synapse"
          TEMPLATE template0
          LC_COLLATE = "C"
          LC_CTYPE = "C";
      '';
    };

    services.matrix-synapse = {
      enable = true;
      settings = {
        server_name = domain;
        public_baseurl = "https://matrix.${domain}/";

        listeners = [{
          port = 8008;
          bind_addresses = [ "127.0.0.1" ];
          type = "http";
          tls = false;
          x_forwarded = true; # Caddy terminates TLS
          resources = [{
            names = [ "client" ];
            compress = false;
          }];
        }];

        database = {
          name = "psycopg2";
          args = {
            user = "matrix-synapse";
            password = "synapse";
            database = "matrix-synapse";
            host = "/run/postgresql";
          };
        };

        enable_registration = false;
        federation_domain_whitelist = [ ]; # empty list = federate with nobody
        allow_public_rooms_over_federation = false;

        # No phoning home, no third-party identity servers, no URL previews
        # (which would make the server fetch arbitrary links on your behalf).
        report_stats = false;
        enable_metrics = false;
        url_preview_enabled = false;
        default_identity_server = null;

        media_store_path = "/var/lib/matrix-synapse/media";
        max_upload_size = "100M";
      };
    };

    # Create your user after first boot:
    #   sudo -u matrix-synapse register_new_matrix_user \
    #     -c /var/lib/matrix-synapse/homeserver.yaml http://127.0.0.1:8008

    #########################################################################
    # XMPP — Prosody.
    #
    # Worth running alongside Matrix rather than instead of it. Different
    # tradeoffs: XMPP is far lighter, the protocol is stable, and it degrades
    # gracefully on bad links — which is why it's what a lot of low-bandwidth
    # and radio-adjacent setups actually use. Matrix is better at history sync
    # across many devices.
    #
    # Modules below cover the "make it feel modern" set: message archive,
    # carbons (multi-device), stream management (survives connection drops),
    # HTTP upload, and push for mobile.
    #########################################################################
    services.prosody = {
      enable = true;
      admins = [ "${config.homelab.admin.name}@${domain}" ];

      # Tailnet-only, so we can use Caddy's internal CA. Point these at the
      # cert Caddy issues for xmpp.${domain}, or generate a self-signed pair.
      # TODO: verify these paths after Caddy's first run.
      ssl = {
        cert = "/var/lib/caddy/.local/share/caddy/certificates/local/xmpp.${domain}/xmpp.${domain}.crt";
        key = "/var/lib/caddy/.local/share/caddy/certificates/local/xmpp.${domain}/xmpp.${domain}.key";
      };

      allowRegistration = false;

      extraModules = [
        "carbons" # sync messages across your devices
        "mam" # server-side message archive
        "smacks" # survive network drops without losing messages
        "csi_simple" # save mobile battery
        "blocklist"
        "cloud_notify" # mobile push
        "vcard_muc"
        "bookmarks"
      ];

      virtualHosts."${domain}" = {
        domain = domain;
        enabled = true;
      };

      muc = [{ domain = "conference.${domain}"; }];
      uploadHttp.domain = "upload.${domain}";
    };

    homelab.proxy.routes.matrix = "127.0.0.1:8008";

    # XMPP client ports. Not in allowedTCPPorts — reachable over the tailnet
    # only, same as everything else.
    # 5222 client, 5269 server-to-server (unused, federation off), 5280 http-upload
  };
}
