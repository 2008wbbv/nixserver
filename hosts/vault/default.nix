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
  homelab.media.enable = false; # Jellyfin + Navidrome + *arr
  homelab.knowledge.enable = false; # SearXNG + FreshRSS + Kiwix + books

  # --- Tier 3: the spicy tier ------------------------------------------------
  homelab.downloads.enable = false; # torrent, VPN-confined. Needs a WG config.
  homelab.anonymity.enable = false; # Tor + I2P
  homelab.llm.enable = false; # Ollama + Open WebUI (needs amdgpu below)
  homelab.amdgpu.enable = false; # TODO: set your card's gfx target first

  # --- Tier 4: hardware you don't own yet ------------------------------------
  homelab.printer.enable = false; # Klipper over USB, no printer NIC
  homelab.ups.enable = false; # NUT, once you buy a UPS
  homelab.comms.enable = false; # Matrix
}
