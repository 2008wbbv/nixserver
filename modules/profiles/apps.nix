{ config, lib, pkgs, inputs, ... }:

let cfg = config.homelab.apps;
in
{
  options.homelab.apps = {
    enable = lib.mkEnableOption "desktop applications";

    helium = lib.mkEnableOption ''
      Helium browser.

      Not in nixpkgs — the packaging PR has been open a while and Helium only
      ships .deb releases. Comes from a community flake instead; see the input
      in flake.nix. That means it updates on someone else's schedule, so keep
      Firefox as the browser you rely on.
    '';
  };

  config = lib.mkIf cfg.enable {
    #########################################################################
    # AppImage support — for the handful of things that ship no other way.
    # binfmt lets you run ./whatever.AppImage directly instead of wrapping it
    # in appimage-run every time.
    #########################################################################
    programs.appimage = {
      enable = true;
      binfmt = true;
    };

    environment.systemPackages = with pkgs; [
      #######################################################################
      # Browsers
      #######################################################################
      firefox

      # Chromium bundling Widevine. You want this specifically for DRM video —
      # Apple Music's web player, Netflix, and Xbox Cloud Gaming all need it,
      # and plain chromium in nixpkgs doesn't ship it.
      google-chrome

      #######################################################################
      # Apple Music
      #
      # `cider` is Cider Classic (1.x) — open source, in nixpkgs, and the
      # established Apple Music client for Linux. Needs an active Apple Music
      # subscription, obviously; it uses Apple's real API rather than
      # scraping anything.
      #
      # Note there is a Cider 2.x which is paid and closed-source, sold
      # through their site. nixpkgs has the free one. Start there.
      #
      # If Cider gives you DRM playback trouble, fall back to
      # music.apple.com in google-chrome above — install it as a PWA
      # (⋮ → Cast, save and share → Install page as app) and it behaves
      # like a native app.
      #######################################################################
      cider

      #######################################################################
      # 3D printing
      #
      # ElegooSlicer is not in nixpkgs. It's a fork of OrcaSlicer, which is
      # itself a fork of Bambu Studio, which forked PrusaSlicer — so
      # `orca-slicer` below is the same program a couple of generations
      # upstream, and it already ships Elegoo printer profiles.
      #
      # Start with orca-slicer. If you specifically need Elegoo's fork (for a
      # profile that only exists there), grab their AppImage and run it
      # directly — programs.appimage above makes that work:
      #
      #     ./ElegooSlicer-*.AppImage
      #
      # Your Klipper printer.cfg lives on the server (modules/services/
      # printer.nix); the slicer only needs to know the machine profile and
      # where to send gcode. Point it at Moonraker via the OctoPrint-compat
      # endpoint at https://printer.lab.internal.
      #######################################################################
      orca-slicer

      #######################################################################
      # Minecraft
      #
      # PrismLauncher, not the official launcher: handles Microsoft accounts,
      # multiple instances, mod loaders (Fabric/Forge/Quilt/NeoForge), and
      # one-click modpack installs from Modrinth and CurseForge. It's the
      # maintained continuation of MultiMC/PolyMC.
      #
      # Java comes from the launcher's own settings; PrismLauncher in nixpkgs
      # is wrapped with the JDKs it needs.
      #######################################################################
      prismlauncher

      #######################################################################
      # General desktop
      #######################################################################
      vlc
      obs-studio
      libreoffice
      keepassxc # even with Vaultwarden — for offline/emergency copies
      thunderbird
      signal-desktop
      discord

      #######################################################################
      # Dev / terminal
      #######################################################################
      vscodium
      alacritty
      git
      gh
    ]
    # Helium, from a community flake since nixpkgs doesn't have it yet.
    ++ lib.optional cfg.helium inputs.helium.packages.${pkgs.system}.default;

    # Chrome/Chromium need this for the keyring to work properly under GNOME.
    services.gnome.gnome-keyring.enable =
      lib.mkIf (config.homelab.desktop.environment == "gnome") true;

    nixpkgs.config.allowUnfree = true; # google-chrome, discord, steam
  };
}
