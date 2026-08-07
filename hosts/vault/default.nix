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

  # RX 6750 XT: RDNA2, gfx1031. ROCm ships support for gfx1030 (RDNA2 "big
  # navi") but not 1031, so we tell it to pretend. This is the standard,
  # well-trodden fix for 6700/6750-class cards — not a hack that might break.
  homelab.amdgpu = {
    enable = true;
    gfxVersion = "10.3.0";
  };

  # --- Tier 4: needs hardware attached ---------------------------------------
  # Klipper over USB. The printer has no NIC in play, and the klipper user is
  # firewalled off from the internet — see the module.
  homelab.printer.enable = false;
}
