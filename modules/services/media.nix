{ config, lib, pkgs, ... }:

let
  cfg = config.homelab.media;
  data = config.homelab.dataDir;
in
{
  options.homelab.media.enable = lib.mkEnableOption "Jellyfin, Navidrome, and the *arr stack";

  config = lib.mkIf cfg.enable {
    users.groups.media = { };

    services.jellyfin = {
      enable = true;
      group = "media";
      openFirewall = false; # tailnet only
    };

    # Hardware transcode needs jellyfin's user in the GPU groups. Enable
    # "AMD AMF"/VAAPI in Jellyfin's dashboard afterwards — it is off by default.
    users.users.jellyfin.extraGroups =
      lib.mkIf config.homelab.amdgpu.enable [ "render" "video" ];

    environment.systemPackages = with pkgs; [ jellyfin-ffmpeg ];

    services.navidrome = {
      enable = true;
      settings = {
        Address = "127.0.0.1";
        Port = 4533;
        MusicFolder = "${data}/media/music";
        ScanSchedule = "@every 6h";
        # No calls out to Last.fm/Spotify unless you add keys.
        EnableExternalServices = false;
      };
    };

    services.audiobookshelf = {
      enable = true;
      host = "127.0.0.1";
      port = 8000;
      group = "media";
    };

    # "Radar" — reading this as Radarr. If you meant ADS-B aircraft radar
    # (dump1090/tar1090/readsb), that's a different module and needs an RTL-SDR
    # dongle; say the word and I'll write it.
    services.radarr = { enable = true; group = "media"; openFirewall = false; };
    services.sonarr = { enable = true; group = "media"; openFirewall = false; };
    services.lidarr = { enable = true; group = "media"; openFirewall = false; };
    services.prowlarr.enable = true; # indexer manager; feeds the three above
    services.bazarr = { enable = true; group = "media"; openFirewall = false; };

    homelab.proxy.routes = {
      jellyfin = "127.0.0.1:8096";
      music = "127.0.0.1:4533";
      books = "127.0.0.1:8000";
      radarr = "127.0.0.1:7878";
      sonarr = "127.0.0.1:8989";
      lidarr = "127.0.0.1:8686";
      prowlarr = "127.0.0.1:9696";
      bazarr = "127.0.0.1:6767";
    };

    systemd.tmpfiles.rules = [
      "d ${data}/media/movies 0775 root media -"
      "d ${data}/media/tv     0775 root media -"
      "d ${data}/media/music  0775 root media -"
      "d ${data}/media/books  0775 root media -"
    ];
  };
}
