{ config, lib, pkgs, ... }:

let
  cfg = config.homelab.gaming;
  data = config.homelab.dataDir;

  # Sunshine's port block. It derives everything from a base port (47989 by
  # default): base-5 and base+X. Listed explicitly so the firewall exception
  # is auditable rather than magic.
  sunshineTCP = [ 47984 47989 47990 48010 ];
  sunshineUDP = [ 47998 47999 48000 48002 48010 ];
in
{
  options.homelab.gaming = {
    enable = lib.mkEnableOption "Steam + Sunshine game streaming to the TV";

    lanStreaming = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Open Sunshine's ports on the LAN, not just the tailnet.

        This is a deliberate hole in the default-deny firewall and the only one
        in this config. It's here because game streaming is the one workload
        where the tailnet's extra hop actually hurts: Tailscale adds a few ms
        and, more importantly, WireGuard encryption on a 4K60 stream is real
        CPU work on both ends.

        Set false to force streaming over the tailnet instead. It does work,
        and if your TV client can join your tailnet that's the cleaner answer.
      '';
    };

    emulation = lib.mkEnableOption "RetroArch + EmulationStation on the host";

    romm = lib.mkEnableOption ''
      RomM — a web ROM library with EmulatorJS built in.

      Think Jellyfin, but for ROMs: it scans your library, pulls box art and
      metadata from IGDB/ScreenScraper, and lets you play NES-through-PS1
      titles in a browser tab. No client software anywhere, including on the
      TV's own browser.

      No native NixOS module exists, so this runs as a container — the only
      one in this config. Everything else here is a native module.
    '';
  };

  config = lib.mkIf cfg.enable {
    #########################################################################
    # The architecture, and why it's better than what you're planning
    #
    # You're currently set up to dual-boot into Windows to game, which takes
    # the whole server down — including DNS for your entire network. This
    # replaces that:
    #
    #     TV ──HDMI── [client box] ──network── this server
    #                  Moonlight              Sunshine + Steam/Proton
    #
    # Games run here, on the 6750 XT. The GPU encodes the frames in hardware,
    # ships them over the network, and the client decodes and displays them.
    # Your controller input goes back the other way. The server never reboots,
    # nothing else goes down, and the TV needs no gaming hardware.
    #
    # Sunshine + Moonlight rather than Steam Link, because Steam Link only
    # streams Steam, the dedicated hardware is discontinued, and Moonlight has
    # clients for far more targets. Sunshine streams anything — emulators,
    # GOG, a browser, a whole desktop.
    #
    # THE CATCH: anti-cheat. Games using kernel-level anti-cheat that hasn't
    # opted into Proton — Valorant, Fortnite, Destiny 2, most competitive
    # shooters — do not run on Linux and never will. Check your library at
    # protondb.com BEFORE you commit to this. If everything you play is on the
    # list, you can stop dual-booting entirely. If one game isn't, you're
    # keeping Windows regardless and this is a bonus rather than a replacement.
    #########################################################################

    programs.steam = {
      enable = true;
      gamescopeSession.enable = true; # the session Sunshine will capture
      remotePlay.openFirewall = false; # Moonlight is doing this job
      dedicatedServer.openFirewall = false;
      extraCompatPackages = [ pkgs.proton-ge-bin ]; # better compat than stock Proton
    };

    programs.gamemode.enable = true; # CPU governor + priority while playing
    hardware.steam-hardware.enable = true; # controller udev rules

    #########################################################################
    # Sunshine
    #
    # THE FIDDLY PART, so it's worth understanding before you fight it:
    # Sunshine captures a display. On a headless server there isn't one, and
    # the GPU won't even initialise an output with nothing plugged in. Two
    # ways out:
    #
    #   1. A dummy HDMI plug. ~$8, goes in the back of the GPU, makes the card
    #      think a 4K monitor is attached. Everything then Just Works. This is
    #      what almost everyone does and I'd start here.
    #
    #   2. A virtual display via kernel modesetting. No hardware, more config,
    #      and it breaks in interesting ways across driver updates.
    #
    # Buy the dummy plug.
    #########################################################################
    services.sunshine = {
      enable = true;
      autoStart = true;
      capSysAdmin = true; # required for KMS capture on Wayland
      openFirewall = false; # handled below, deliberately and visibly

      settings = {
        # AMD hardware encode via VAAPI. The 6750 XT does H.264 and HEVC in
        # hardware; HEVC is the better choice if your client decodes it.
        encoder = "vaapi";
        adapter_name = "/dev/dri/renderD128";

        # 4K60 needs ~40-50 Mbps to look good. On wired gigabit that's
        # nothing. Over WiFi it's the whole ballgame — see the note below.
        min_bitrate = 10000;

        # Lower = more responsive, more bandwidth. 60 is a good default;
        # 120 if your TV and client can take it.
        fps = "[30,60,120]";
        resolutions = "[1920x1080,2560x1440,3840x2160]";
      };

      applications = {
        env.PATH = "$(PATH):$(HOME)/.local/bin";
        apps = [
          {
            name = "Steam Big Picture";
            # Gamescope wraps it so resolution changes don't disturb the host.
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

    # THE ONE DELIBERATE FIREWALL HOLE IN THIS CONFIG.
    # Scoped to Sunshine's ports only, and only when lanStreaming is on.
    networking.firewall = lib.mkIf cfg.lanStreaming {
      allowedTCPPorts = sunshineTCP;
      allowedUDPPorts = sunshineUDP;
    };

    #########################################################################
    # Emulation
    #
    # Two layers, and they're for different things:
    #
    #   RetroArch / EmulationStation (here, streamed via Moonlight) — for
    #   anything demanding. PS2, GameCube, Wii, Switch-era. The 6750 XT
    #   handles these comfortably; a Pi would not.
    #
    #   RomM (see below) — a web ROM library with EmulatorJS built in. Plays
    #   retro consoles in a browser tab on any device, including the TV's own
    #   browser. Not for demanding systems, excellent for NES through PS1.
    #
    # ROMs of games you don't own are copyright infringement in most places;
    # dumping your own cartridges and discs is legal in some jurisdictions and
    # not others. Your call, not mine — just know the ground you're on.
    #########################################################################
    environment.systemPackages = lib.mkIf cfg.emulation (with pkgs; [
      retroarchFull # every core, saves fighting core installation
      es-de # the frontend that makes it TV-navigable
      dolphin-emu # GameCube/Wii — better standalone than as a core
      pcsx2 # PS2
      rpcs3 # PS3
      ryujinx # Switch
      mgba
      duckstation
    ]);

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

    #########################################################################
    # RomM — browser-playable ROM library.
    #########################################################################
    virtualisation.podman = lib.mkIf cfg.romm {
      enable = true;
      dockerCompat = false;
      defaultNetwork.settings.dns_enabled = true;
    };

    virtualisation.oci-containers = lib.mkIf cfg.romm {
      backend = "podman";
      containers.romm = {
        image = "docker.io/rommapp/romm:latest";
        # Loopback only; Caddy publishes it on the tailnet like everything else.
        ports = [ "127.0.0.1:8097:8080" ];
        volumes = [
          "/var/lib/romm/resources:/romm/resources"
          "/var/lib/romm/config:/romm/config"
          "/var/lib/romm/redis:/redis-data"
          "${data}/games/roms:/romm/library"
          "${data}/games/bios:/romm/assets"
        ];
        environment = {
          DB_HOST = "127.0.0.1";
          # Metadata scraping needs IGDB API keys (free, from Twitch dev
          # console). Without them RomM still works, you just get no box art.
          # Put them in sops and switch to environmentFiles if you want it.
          ROMM_AUTH_SECRET_KEY = "CHANGE-ME"; # openssl rand -hex 32
        };
        extraOptions = [ "--pull=newer" ];
      };
    };

    homelab.proxy.routes = {
      sunshine = "127.0.0.1:47990"; # config web UI
    } // lib.optionalAttrs cfg.romm {
      roms = "127.0.0.1:8097";
    };

    #########################################################################
    # Client hardware for the TV — pick one:
    #
    #   Nvidia Shield TV (~$150)   Best all-rounder. Native Moonlight, native
    #                              RetroArch, wired ethernet, HDMI-CEC so the
    #                              TV remote works. If you buy one thing, this.
    #
    #   Any Android TV box (~$50)  Moonlight works. Check it has ETHERNET —
    #                              cheap boxes are WiFi-only and that's the
    #                              thing that ruins streaming.
    #
    #   Raspberry Pi 5 (~$80)      moonlight-qt, or Batocera for standalone
    #                              emulation. Fully open, more setup.
    #
    #   Steam Deck docked          If you have one, it's already a perfect
    #                              Moonlight client and needs nothing.
    #
    #   LG TV (webOS)              There's a Moonlight port. No extra box at
    #                              all. Samsung/Tizen has no good option.
    #
    # NETWORK: use ethernet. This is not a preference, it's the difference
    # between "indistinguishable from local" and "why is it stuttering". A
    # 4K60 stream is 40-50 Mbps sustained with zero tolerance for jitter, and
    # WiFi's variance is exactly the thing streaming can't absorb. If the TV
    # can't be wired, MoCA over your existing coax or powerline is a better
    # bet than WiFi.
    #########################################################################
  };
}
