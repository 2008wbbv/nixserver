{ config, lib, pkgs, ... }:

let
  cfg = config.homelab.knowledge;
  data = config.homelab.dataDir;
in
{
  options.homelab.knowledge.enable =
    lib.mkEnableOption "SearXNG, FreshRSS, Kiwix (offline Wikipedia), Calibre-Web";

  config = lib.mkIf cfg.enable {
    #########################################################################
    # SearXNG — metasearch with no logging and no per-user profile.
    #########################################################################
    homelab.stack.groups.knowledge = [
      "searx" "phpfpm-freshrss" "nginx" "kiwix-serve" "calibre-web"
    ];

    assertions = [{
      assertion = config.homelab.secrets.enable;
      message = ''
        homelab.knowledge needs secrets, but homelab.secrets.enable is false.
        Follow secrets/README.md, then set homelab.secrets.enable = true.
        Needs: searx/env, freshrss/password
      '';
    }];

    services.searx = {
      enable = true;
      package = pkgs.searxng;
      redisCreateLocally = true;
      settings = {
        server = {
          bind_address = "127.0.0.1";
          port = 8888;
          secret_key = "@SEARX_SECRET_KEY@"; # substituted from environmentFile
          public_instance = false;
        };
        search = {
          safe_search = 0;
          autocomplete = "duckduckgo";
          formats = [ "html" "json" ]; # json lets other tools query it
        };
        ui.default_theme = "simple";
      };
      environmentFile = config.sops.secrets."searx/env".path;
    };
    sops.secrets."searx/env" = { };

    #########################################################################
    # FreshRSS — RSS.
    #
    # Caveat: FreshRSS is PHP, so the NixOS module wires up PHP-FPM and an
    # *nginx* vhost — it has no standalone HTTP listener for Caddy to proxy.
    # Simplest working arrangement is to let it own nginx on loopback and have
    # Caddy proxy to that. If you'd rather not run two web servers, miniflux
    # (`services.miniflux`) is a single Go binary that listens on a port, and
    # is the drop-in I'd actually recommend here.
    #########################################################################
    services.freshrss = {
      enable = true;
      baseUrl = "https://rss.${config.homelab.domain}";
      database.type = "sqlite"; # one user, one box: sqlite is the right call
      defaultUser = config.homelab.admin.name;
      passwordFile = config.sops.secrets."freshrss/password".path;
      virtualHost = "rss.${config.homelab.domain}";
    };
    sops.secrets."freshrss/password" = { };

    # Keep the FreshRSS nginx vhost on loopback so only Caddy can reach it.
    services.nginx.virtualHosts."rss.${config.homelab.domain}".listen = [{
      addr = "127.0.0.1";
      port = 8090;
    }];

    #########################################################################
    # Kiwix — offline Wikipedia and friends.
    #
    # Grab content first (these are big):
    #   wiki_en_all_maxi         ~110 GB   full Wikipedia with images
    #   wiki_en_all_nopic        ~50 GB    text only
    #   wiki_en_simple_all_maxi  ~10 GB    good starting point
    #   also: Gutenberg, Wiktionary, Stack Exchange, iFixit, WikiMed
    # from https://download.kiwix.org/zim/ into ${data}/files/zim/
    #########################################################################
    services.kiwix-serve = {
      enable = true;
      address = "127.0.0.1";
      port = 8081;
      zimPaths = [ "${data}/files/zim" ]; # TODO: verify option name on your nixpkgs
    };

    #########################################################################
    # Calibre-Web — ebook library. Point it at an existing Calibre library dir.
    #########################################################################
    services.calibre-web = {
      enable = true;
      listen = {
        ip = "127.0.0.1";
        port = 8083;
      };
      options = {
        calibreLibrary = "${data}/media/books";
        enableBookUploading = true;
      };
    };

    homelab.proxy.routes = {
      search = "127.0.0.1:8888";
      rss = "127.0.0.1:8090"; # the loopback nginx vhost above
      wiki = "127.0.0.1:8081";
      library = "127.0.0.1:8083";
    };

    systemd.tmpfiles.rules = [
      "d ${data}/files/zim 0775 root users -"
    ];
  };
}
