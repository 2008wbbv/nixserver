{ config, lib, pkgs, ... }:

let
  cfg = config.homelab.media;
  data = config.homelab.dataDir;
in
{
  options.homelab.media = {
    enable = lib.mkEnableOption "Jellyfin + Audiobookshelf";

    navidrome = lib.mkEnableOption ''
      Navidrome alongside Jellyfin for music.

      You're right that Jellyfin does music — it has a full music library,
      artist/album views, playlists, and clients. For most libraries that is
      genuinely enough and this should stay off.

      Where Navidrome wins is that it speaks the Subsonic API, which unlocks a
      much better client ecosystem than Jellyfin's music apps (Symfonium,
      play:Sub, Sonixd, DSub...). It also handles very large libraries and
      messy tagging noticeably better, and does gapless playback properly.

      Rule of thumb: start with Jellyfin only. Add this if you find yourself
      annoyed by the mobile music experience — that's the specific thing it
      fixes.
    '';
  };

  config = lib.mkIf cfg.enable {
    homelab.stack.groups.media =
      [ "jellyfin" "audiobookshelf" ]
      ++ lib.optional cfg.navidrome "navidrome";

    users.groups.media = { };

    services.jellyfin = {
      enable = true;
      group = "media";
      openFirewall = false; # tailnet only
    };

    # Hardware transcode needs jellyfin in the GPU groups. Enable VAAPI in
    # Jellyfin's dashboard afterwards — it is off by default. Do NOT enable
    # AV1 encode; the 6750 XT can't do it and you'll get silent CPU fallback.
    users.users.jellyfin.extraGroups =
      lib.mkIf config.homelab.amdgpu.enable [ "render" "video" ];

    environment.systemPackages = with pkgs; [ jellyfin-ffmpeg ];

    services.audiobookshelf = {
      enable = true;
      host = "127.0.0.1";
      port = 8000;
      group = "media";
    };

    services.navidrome = lib.mkIf cfg.navidrome {
      enable = true;
      settings = {
        Address = "127.0.0.1";
        Port = 4533;
        MusicFolder = "${data}/media/music";
        ScanSchedule = "@every 6h";
        EnableExternalServices = false; # no Last.fm/Spotify calls
      };
    };

    homelab.proxy.routes = {
      jellyfin = "127.0.0.1:8096";
      audiobooks = "127.0.0.1:8000";
    } // lib.optionalAttrs cfg.navidrome {
      music = "127.0.0.1:4533";
    };

    systemd.tmpfiles.rules = [
      "d ${data}/media/movies 0775 root media -"
      "d ${data}/media/tv     0775 root media -"
      "d ${data}/media/music  0775 root media -"
      "d ${data}/media/books  0775 root media -"
    ];

    #########################################################################
    # The *arr stack (Radarr/Sonarr/Lidarr/Prowlarr/Bazarr) has been removed
    # per "remove radar for now". It was the whole of that list item.
    #
    # Nothing else depends on it — the torrent client in downloads.nix writes
    # straight into ${data}/media and Jellyfin picks files up from there, so
    # manual downloading works fine without any of it. Say the word and it
    # comes back as its own module; it's about 15 lines.
    #########################################################################
  };
}
