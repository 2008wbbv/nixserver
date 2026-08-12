{ config, lib, pkgs, ... }:

let
  cfg = config.homelab.selfhost;
  inherit (config.homelab) domain;
  data = config.homelab.dataDir;
in
{
  options.homelab.selfhost = {
    forgejo = lib.mkEnableOption "Forgejo — self-hosted git";
    nextcloud = lib.mkEnableOption "Nextcloud — files, calendar, contacts";
    website = lib.mkEnableOption "a static personal website served by Caddy";
  };

  config = lib.mkMerge [
    #########################################################################
    # On landchad.net
    #
    # Good site, and the service *selection* is worth mining — it's a decent
    # map of what's worth owning. Two structural differences from what you're
    # building, so you don't fight the guides:
    #
    #   1. Landchad targets a public VPS with a real domain and open ports.
    #      You chose tailnet-only. So the nginx/certbot/DNS half of most of
    #      those guides doesn't apply — Caddy and Tailscale already handle it,
    #      and better, because nothing is exposed.
    #
    #   2. Landchad is imperative: apt install, edit /etc/whatever, systemctl
    #      enable. Following that on NixOS actively fights the machine — you'd
    #      make changes that vanish on the next rebuild. Read the guides for
    #      *what* to run and why; get the *how* from the NixOS module.
    #
    # Coverage against landchad's list, as of this config:
    #
    #   already here   RSS, SearXNG, Bitwarden(Vaultwarden), Syncthing,
    #                  Matrix, XMPP, Tor hidden services, WireGuard(Tailscale)
    #   added below    git hosting (Forgejo), Nextcloud, static website
    #   deferred       email — your call, and the one that's genuinely hard
    #   skipped        Mumble (you removed it), Pleroma/fediverse and PeerTube
    #                  (both only make sense federated and public, which is
    #                  the opposite of this setup)
    #########################################################################

    (lib.mkIf cfg.forgejo {
      # Worth having primarily so this repo lives somewhere you control. A
      # config repo that only exists on GitHub is a config repo you can't
      # reach when your network is down — which is exactly when you need it.
      services.forgejo = {
        enable = true;
        database.type = "sqlite3";
        lfs.enable = true;
        settings = {
          server = {
            DOMAIN = "git.${domain}";
            ROOT_URL = "https://git.${domain}/";
            HTTP_ADDR = "127.0.0.1";
            HTTP_PORT = 3002;
            SSH_PORT = 22;
            START_SSH_SERVER = false; # reuse the host's sshd
          };
          service = {
            DISABLE_REGISTRATION = true;
            REQUIRE_SIGNIN_VIEW = true;
          };
          # No calls out to fetch avatars or check for updates.
          picture.DISABLE_GRAVATAR = true;
          "cron.update_checker".ENABLED = false;
          actions.ENABLED = false; # CI runner; turn on if you want it
        };
      };

      homelab.proxy.routes.git = "127.0.0.1:3002";
    })

    (lib.mkIf cfg.nextcloud {
      # This is the piece Syncthing doesn't cover: CalDAV and CardDAV. If you
      # want your phone's calendar and contacts off Google, this is how.
      #
      # If you ONLY want file sync, don't run this — Syncthing already does
      # that better and with a fraction of the moving parts. Nextcloud earns
      # its keep through calendar, contacts, and sharing links.
      services.nextcloud = {
        enable = true;
        package = pkgs.nextcloud31; # TODO: match your nixpkgs; it pins majors
        hostName = "cloud.${domain}";
        home = "${data}/files/nextcloud";

        database.createLocally = true;
        config = {
          dbtype = "pgsql";
          adminuser = config.homelab.admin.name;
          adminpassFile = config.sops.secrets."nextcloud/adminpass".path;
        };

        configureRedis = true;
        maxUploadSize = "16G";
        https = true;

        settings = {
          overwriteprotocol = "https";
          trusted_proxies = [ "127.0.0.1" ];
          default_phone_region = "US"; # TODO
        };

        extraApps = {
          inherit (config.services.nextcloud.package.packages.apps)
            calendar contacts notes tasks;
        };
        extraAppsEnable = true;
      };

      sops.secrets."nextcloud/adminpass".owner = "nextcloud";

      # Nextcloud's module drives nginx. Keep it on loopback so Caddy stays
      # the only thing facing the tailnet.
      services.nginx.virtualHosts."cloud.${domain}".listen = [{
        addr = "127.0.0.1";
        port = 8091;
      }];

      homelab.proxy.routes.cloud = "127.0.0.1:8091";
    })

    (lib.mkIf cfg.website {
      # A plain static site. Put files in ${data}/files/www.
      #
      # Note this is tailnet-only like everything else, so it's a site only
      # you can see — useful as a dashboard or notes page, not as a public
      # presence. A public personal site is the one thing genuinely better
      # served by a $5 VPS or a static host than by this box, precisely
      # because it should be reachable when your house's power isn't.
      systemd.tmpfiles.rules = [
        "d ${data}/files/www 0755 caddy caddy -"
      ];

      services.caddy.virtualHosts."www.${domain}".extraConfig = ''
        tls internal
        @denied not remote_ip 100.64.0.0/10 127.0.0.1/32
        respond @denied "not available here" 403
        root * ${data}/files/www
        file_server browse
        encode gzip
      '';
    })
  ];
}
