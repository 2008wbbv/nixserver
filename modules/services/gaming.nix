{ config, lib, pkgs, ... }:

let
  cfg = config.homelab.gaming;
  data = config.homelab.dataDir;

  # Listed explicitly so the firewall exception is auditable, not magic.
  sunshineTCP = [ 47984 47989 47990 48010 ];
  sunshineUDP = [ 47998 47999 48000 48002 48010 ];
in
{
  options.homelab.gaming = {
    enable = lib.mkEnableOption "Steam + Proton + gamescope, for playing at the machine";
    streaming = lib.mkEnableOption "Sunshine, for the TV's Moonlight client (needs a dummy HDMI plug)";
    emulation = lib.mkEnableOption "RetroArch, ES-DE, and standalone emulators";
    romm = lib.mkEnableOption "RomM — web ROM library with EmulatorJS (the only container here)";

    lanStreaming = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Open Sunshine's ports on the LAN rather than tailnet-only. The single
        deliberate hole in the default-deny firewall — streaming is the one
        workload where the tailnet hop and WireGuard encryption measurably cost
        you. Set false to force it over the tailnet instead.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # Steam Remote Play is on, so the TV's Steam Link app works with zero setup.
    # Add `streaming` when you want to stream non-Steam things.
    #
    # PC GAME PASS DOES NOT RUN ON LINUX — the Xbox app's MSIX packaging and
    # Gaming Runtime don't work under Proton. That's the platform, not
    # individual titles. Game Pass stays in Windows.

    programs.steam = {
      enable = true;
      gamescopeSession.enable = true;
      remotePlay.openFirewall = true; # Steam Link on the TV
      dedicatedServer.openFirewall = false;
      extraCompatPackages = [ pkgs.proton-ge-bin ];
    };

    programs.gamemode.enable = true;
    hardware.steam-hardware.enable = true; # controller udev rules

    environment.systemPackages = with pkgs;
      [
        protonup-qt # manage Proton-GE versions
        mangohud # FPS/temp overlay
        lutris # non-Steam, GOG
        heroic # Epic and GOG launcher
        gamescope
      ]
      ++ lib.optionals cfg.emulation [
        retroarchFull
        es-de # TV-navigable frontend
        dolphin-emu # GameCube/Wii
        pcsx2 # PS2
        rpcs3 # PS3
        ryujinx # Switch
        mgba
        duckstation
      ];

    # Sunshine captures a display, and a headless box has none — the GPU won't
    # initialise an output with nothing plugged in. Buy an $8 dummy HDMI plug;
    # the virtual-display alternative breaks across driver updates.
    services.sunshine = lib.mkIf cfg.streaming {
      enable = true;
      autoStart = true;
      capSysAdmin = true; # KMS capture on Wayland
      openFirewall = false; # handled below, visibly

      settings = {
        encoder = "vaapi";
        adapter_name = "/dev/dri/renderD128";
        min_bitrate = 10000;
        fps = "[30,60,120]";
        resolutions = "[1920x1080,2560x1440,3840x2160]";
      };

      applications = {
        env.PATH = "$(PATH):$(HOME)/.local/bin";
        apps = [
          {
            name = "Steam Big Picture";
            cmd = "${pkgs.steam}/bin/steam -gamepadui";
            auto-detach = "true";
          }
        ] ++ lib.optional cfg.emulation {
          name = "EmulationStation";
          cmd = "${pkgs.es-de}/bin/es-de";
          auto-detach = "true";
        };
      };
    };

    networking.firewall = lib.mkIf (cfg.streaming && cfg.lanStreaming) {
      allowedTCPPorts = sunshineTCP;
      allowedUDPPorts = sunshineUDP;
    };

    virtualisation.podman = lib.mkIf cfg.romm {
      enable = true;
      defaultNetwork.settings.dns_enabled = true;
    };

    virtualisation.oci-containers = lib.mkIf cfg.romm {
      backend = "podman";
      containers.romm = {
        image = "docker.io/rommapp/romm:latest";
        ports = [ "127.0.0.1:8097:8080" ];
        volumes = [
          "/var/lib/romm/resources:/romm/resources"
          "/var/lib/romm/config:/romm/config"
          "/var/lib/romm/redis:/redis-data"
          "${data}/games/roms:/romm/library"
          "${data}/games/bios:/romm/assets"
        ];
        environment = {
          # TODO: openssl rand -hex 32
          ROMM_AUTH_SECRET_KEY = "CHANGE-ME";
        };
        extraOptions = [ "--pull=newer" ];
      };
    };

    systemd.tmpfiles.rules =
      lib.optionals (cfg.emulation || cfg.romm) [
        "d ${data}/games      0775 root users -"
        "d ${data}/games/roms 0775 root users -"
        "d ${data}/games/bios 0775 root users -"
      ]
      ++ lib.optionals cfg.romm [
        "d /var/lib/romm           0750 root root -"
        "d /var/lib/romm/resources 0750 root root -"
        "d /var/lib/romm/config    0750 root root -"
        "d /var/lib/romm/redis     0750 root root -"
      ];

    homelab.proxy.routes =
      lib.optionalAttrs cfg.streaming { sunshine = "127.0.0.1:47990"; }
      // lib.optionalAttrs cfg.romm { roms = "127.0.0.1:8097"; };

    # Wire the TV with ethernet. 4K60 is 40-50 Mbps sustained with no tolerance
    # for jitter, which is exactly what WiFi can't provide.
  };
}
