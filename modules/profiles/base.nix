{ config, lib, pkgs, ... }:

let cfg = config.homelab;
in
{
  nix = {
    settings = {
      experimental-features = [ "nix-command" "flakes" ];
      auto-optimise-store = true;
      trusted-users = [ "root" cfg.admin.name ];
    };
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };
  };

  # Keep the last 20 generations bootable. This is the rollback story: a bad
  # config is a reboot and a menu entry away, not a reinstall.
  boot.loader.systemd-boot.configurationLimit = lib.mkDefault 20;

  time.timeZone = lib.mkDefault "America/New_York"; # TODO: confirm
  i18n.defaultLocale = "en_US.UTF-8";

  users.mutableUsers = false;
  users.users.${cfg.admin.name} = {
    isNormalUser = true;
    description = "Administrator";
    extraGroups = [ "wheel" "systemd-journal" ];
    openssh.authorizedKeys.keys = cfg.admin.sshKeys;
  };
  users.users.root.openssh.authorizedKeys.keys = cfg.admin.sshKeys;

  security.sudo.wheelNeedsPassword = false; # key-only access already gates this

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "prohibit-password";
    };
    # Not in allowedTCPPorts — reachable over the tailnet only.
    openFirewall = false;
  };

  environment.systemPackages = with pkgs; [
    git
    vim
    htop
    btop
    tmux
    ripgrep
    fd
    jq
    curl
    dnsutils
    pciutils
    usbutils
    lm_sensors
    smartmontools
    iotop
    nethogs
    tcpdump
    ncdu
    rsync
    sops
    age
  ];

  # Disk health matters more than usual when there is exactly one box.
  services.smartd = {
    enable = true;
    autodetect = true;
  };

  services.fstrim.enable = true;
  services.journald.extraConfig = "SystemMaxUse=2G";

  # Unattended security updates, applied at a time you're asleep, with the old
  # generation still in the boot menu if it goes wrong.
  system.autoUpgrade = {
    enable = false; # TODO: flip on once you trust the setup
    flake = "github:2008wbbv/nixserver#vault";
    flags = [ "--update-input" "nixpkgs" "--no-write-lock-file" ];
    dates = "04:00";
    randomizedDelaySec = "45min";
  };

  #############################################################################
  # Secrets (sops-nix)
  #
  # The Nix store is world-readable — nothing secret can be written inline in
  # these files. sops-nix decrypts at activation using this host's SSH host key,
  # so the encrypted blobs are safe to commit. See docs/SECRETS.md.
  #############################################################################
  sops = {
    defaultSopsFile = ../../secrets/secrets.yaml;
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  };
}
