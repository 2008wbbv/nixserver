{ config, lib, pkgs, ... }:

let cfg = config.homelab.desktop;
in
{
  options.homelab.desktop = {
    environment = lib.mkOption {
      type = lib.types.enum [ "none" "gnome" "plasma" ];
      default = "none";
      description = ''
        Desktop environment for when you sit at this machine.

        My pick for you is "gnome", and the reasoning is about how you'll
        actually use it rather than which is technically better:

          You said macOS-like, and GNOME genuinely is that. Activities
          overview maps onto Mission Control, dynamic workspaces, gestures,
          minimal window chrome, and it pushes you toward fullscreen apps and
          workspace-switching the same way macOS does.

          More importantly, this is a machine you use *occasionally*. That
          argues hard against dwm. A tiling WM pays off when you're in it
          eight hours a day and the keybindings are in your fingers — sit down
          after three weeks away and you won't remember how to open a
          terminal. Discoverable menus beat memorised chords on a machine you
          touch weekly.

          And on NixOS specifically, dwm is a poor fit: configuring it means
          editing config.h and recompiling, which here means maintaining an
          overlay with patches. You get the suckless downsides (recompile to
          change anything) without the upside (a config file you edit freely).

        "plasma" is the better choice if gaming at the machine matters more
        than the macOS feel — it has stronger VRR and HDR support, and
        historically fewer sharp edges with Sunshine's screen capture.

        "none" keeps this headless, which is the right answer if you only ever
        reach it over Tailscale.
      '';
    };

    autoLogin = lib.mkEnableOption ''
      passwordless login to the desktop session.

      Needed if Sunshine has to capture a session with nobody physically
      present. It also means anyone who walks up to the machine has your
      desktop — decide which risk you care about. Full-disk encryption is
      unaffected either way; that prompt still happens at boot.
    '';
  };

  config = lib.mkIf (cfg.environment != "none") {
    #########################################################################
    # This is a real posture change, so it's worth saying plainly:
    #
    # A desktop session on the box adds a display manager, a compositor, a
    # portal stack, PipeWire, and a few thousand packages that were not there
    # before. None of it listens on the network, and the firewall is
    # unchanged, so the exposure story is intact — but "minimal server" is no
    # longer an accurate description of this machine.
    #
    # That's a fine trade for a machine you also want to use as a PC. Just
    # don't tell yourself it's still a hardened appliance.
    #########################################################################

    services.xserver.enable = true;

    # Wayland by default. X11 sessions remain available at the login screen
    # for the odd app that needs them.
    services.displayManager = {
      gdm = lib.mkIf (cfg.environment == "gnome") {
        enable = true;
        wayland = true;
      };
      sddm = lib.mkIf (cfg.environment == "plasma") {
        enable = true;
        wayland.enable = true;
      };
      autoLogin = lib.mkIf cfg.autoLogin {
        enable = true;
        user = config.homelab.admin.name;
      };
    };

    services.desktopManager = {
      gnome.enable = cfg.environment == "gnome";
      plasma6.enable = cfg.environment == "plasma";
    };

    # Sound. PipeWire is the only sane option now, and Sunshine needs it to
    # capture game audio.
    services.pulseaudio.enable = false;
    security.rtkit.enable = true;
    services.pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
    };

    # Printing/scanning, since it's a desktop now.
    services.printing.enable = true;
    services.avahi = {
      enable = true;
      nssmdns4 = true;
      # mDNS is a chatty LAN broadcast protocol. It stays off the firewall's
      # allow list — printer discovery works outbound, nothing answers inbound.
      openFirewall = false;
    };

    # GNOME ships a lot you won't want on a machine that's also a server.
    environment.gnome.excludePackages = lib.mkIf (cfg.environment == "gnome") (with pkgs; [
      gnome-tour
      gnome-connections
      epiphany # web browser
      geary # mail
      totem # video player — you have Jellyfin
      gnome-music # ditto
      gnome-maps # you have a better one
    ]);

    environment.systemPackages = with pkgs; [
      firefox
      chromium # for Xbox Cloud Gaming, which needs a Chromium engine
      alacritty
      file-roller
    ] ++ lib.optionals (cfg.environment == "gnome") [
      gnome-tweaks
      dconf-editor
      # Makes GNOME behave much more like macOS: dock, hot corners, gestures.
      gnomeExtensions.dash-to-dock
      gnomeExtensions.appindicator
      gnomeExtensions.blur-my-shell
    ];

    # Fonts, because a desktop without them looks broken.
    fonts = {
      enableDefaultPackages = true;
      packages = with pkgs; [
        noto-fonts
        noto-fonts-emoji
        liberation_ttf
        nerd-fonts.jetbrains-mono
      ];
      fontconfig.defaultFonts.monospace = [ "JetBrainsMono Nerd Font" ];
    };

    # A desktop shouldn't suspend a server. Explicitly disable it.
    services.logind = {
      lidSwitch = "ignore";
      extraConfig = ''
        HandleSuspendKey=ignore
        HandleHibernateKey=ignore
        IdleAction=ignore
      '';
    };
    systemd.targets = {
      sleep.enable = false;
      suspend.enable = false;
      hibernate.enable = false;
      hybrid-sleep.enable = false;
    };

    # GNOME's own power settings will still try; override them.
    services.xserver.desktopManager.gnome = lib.mkIf (cfg.environment == "gnome") {
      extraGSettingsOverrides = ''
        [org.gnome.settings-daemon.plugins.power]
        sleep-inactive-ac-type='nothing'
        sleep-inactive-battery-type='nothing'
      '';
      extraGSettingsOverridePackages = [ pkgs.gnome-settings-daemon ];
    };
  };
}
