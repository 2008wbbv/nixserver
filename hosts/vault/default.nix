{ config, lib, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    # ./disks.nix                      # <- enable only for a clean wipe-and-install. See file.
    ../../modules
  ];

  networking.hostName = "vault";

  # Required by ZFS. Generate once with: head -c4 /dev/urandom | od -A none -t x4
  # TODO: replace before first build.
  networking.hostId = "deadbeef";

  system.stateVersion = "26.05"; # Never change this after install.

  #############################################################################
  # Shared settings
  #############################################################################

  homelab = {
    # Internal DNS zone served by our own resolver and pushed to the tailnet.
    domain = "lab.internal";

    # Where bulk data lives. Set once, every service derives from it.
    dataDir = "/srv";

    # Flip to true only AFTER following secrets/README.md on the installed
    # machine. Nothing in tier 1 needs it.
    secrets.enable = false;

    # Your admin account.
    admin = {
      name = "ben";
      # TODO: paste your SSH public key(s). Password login is disabled.
      sshKeys = [
        # "ssh-ed25519 AAAA... ben@laptop"
      ];
    };
  };

  #############################################################################
  # Service enablement — the whole point of this layout.
  #
  # Build in tiers. Get a tier green, commit, then turn on the next one.
  # Everything defaults to false; nothing here is load-bearing for boot.
  #############################################################################

  # --- Tier 1: get on the network safely ------------------------------------
  homelab.tailscale.enable = true;
  homelab.dns.enable = true; # AdGuard-style blocking + recursive unbound
  homelab.proxy.enable = true; # Caddy, tailnet-only, *.lab.internal
  homelab.monitoring.enable = true; # prometheus + grafana + loki
  homelab.backups.enable = false; # TODO: set a restic target, then enable

  # --- Tier 2: storage + the things you'll use daily ------------------------
  homelab.storage.enable = false; # TODO: ZFS pool. Read the file first.
  homelab.files.enable = false; # Samba + Syncthing
  homelab.vaultwarden.enable = false; # password manager
  homelab.knowledge.enable = false; # SearXNG + FreshRSS + Kiwix + books

  homelab.media = {
    enable = false; # Jellyfin + Audiobookshelf
    # Jellyfin does handle music. Leave this off unless its mobile music
    # clients annoy you — that's the specific thing Navidrome fixes.
    navidrome = false;
  };

  # --- Tier 3: the spicy tier ------------------------------------------------
  homelab.downloads.enable = false; # torrent, VPN-confined. Needs a WG config.
  homelab.anonymity.enable = false; # Tor + I2P, `tor-route on|off`
  homelab.osint.enable = false; # SpiderFoot + maigret/holehe/exiftool
  homelab.llm.enable = false; # Ollama + Open WebUI
  homelab.comms.enable = false; # Matrix (Synapse) + XMPP (Prosody)

  homelab.maps = {
    enable = false;
    # TODO: your state. Draw the box at bboxfinder.com — west,south,east,north.
    # The default below is the whole continental US, which is ~10x bigger than
    # you need.
    bbox = "-125.0,24.5,-66.9,49.4";
    maxZoom = 14;
  };

  # RX 6750 XT: RDNA2, gfx1031.
  #
  # Graphics are excellent — amdgpu is in-tree, Mesa RADV is mature, this is
  # one of the best-supported gaming cards on Linux. Compute is the messy part:
  # ROCm never officially supported gfx1031, and the usual 10.3.0 override has
  # an active regression on ROCm 6.4.3+. Hence Vulkan below.
  homelab.amdgpu = {
    enable = true;
    gfxVersion = "10.3.0";
    # Vulkan, not ROCm — ROCm 6.4.3+ has a live regression that segfaults
    # gfx1031 the moment a model gets a prompt. Read the note in the module.
    computeBackend = "vulkan";
  };

  # Desktop, for when you sit at the machine rather than SSH into it.
  homelab.desktop = {
    environment = "gnome";
    # Only needed if Sunshine must capture a session with nobody logged in.
    autoLogin = false;
  };

  # Firefox, Chrome (for DRM), Cider (Apple Music), OrcaSlicer, PrismLauncher,
  # and the usual desktop set. See modules/profiles/apps.nix.
  homelab.apps = {
    enable = true;
    helium = false; # community flake, not nixpkgs — read the note first
  };

  homelab.yubikey = {
    enable = true;
    # PAM lockout risk. Register two keys and keep a root shell open when you
    # first turn this on. Read the module.
    sudoUnlock = false;
  };

  # --- Tier 3b: landchad-flavoured selfhosting --------------------------------
  homelab.selfhost = {
    forgejo = false; # git hosting — worth it just to own this repo
    nextcloud = false; # only for CalDAV/CardDAV; Syncthing beats it for files
    website = false; # static site, tailnet-only
  };

  # --- Tier 4: needs hardware attached ---------------------------------------
  # Klipper over USB. The printer has no NIC in play, and the klipper user is
  # firewalled off from the internet — see the module.
  homelab.printer.enable = false;

  # Steam + Sunshine streaming to the TV (which already has Moonlight and
  # Steam Link, so no client hardware needed).
  #
  # NOTE: this does NOT replace the Windows dual-boot for you — PC Game Pass
  # doesn't run on Linux at all. See docs/GAMING-ARCHITECTURE.md.
  homelab.gaming = {
    enable = true; # Steam + Proton + gamescope, playing at the machine
    streaming = false; # Sunshine — needs a dummy HDMI plug
    lanStreaming = true; # the one deliberate firewall hole in this config
    emulation = false; # RetroArch + ES-DE + standalone emulators
    romm = false; # browser-playable ROM library (the only container here)
  };
}
