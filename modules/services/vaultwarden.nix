{ config, lib, pkgs, ... }:

let
  cfg = config.homelab.vaultwarden;
  inherit (config.homelab) domain;
in
{
  options.homelab.vaultwarden.enable =
    lib.mkEnableOption "Vaultwarden (Bitwarden-compatible password manager)";

  config = lib.mkIf cfg.enable {
    #########################################################################
    # You wrote "Key pass". Two viable readings, both fine:
    #
    #  a) Vaultwarden (this module). Real clients on every platform, browser
    #     autofill, TOTP, sharing. A service that must stay up and backed up.
    #  b) KeePassXC + a .kdbx file synced by Syncthing (see files.nix). No
    #     server, no attack surface, no uptime requirement. Merge conflicts if
    #     you edit on two devices at once.
    #
    # For one person, (b) is genuinely defensible and I'd not talk you out of
    # it. For autofill quality and shared entries, (a) wins. They coexist fine.
    #########################################################################

    homelab.stack.groups.vault = [ "vaultwarden" ];

    services.vaultwarden = {
      enable = true;
      dbBackend = "sqlite";
      environmentFile = config.sops.secrets."vaultwarden/env".path;

      config = {
        ROCKET_ADDRESS = "127.0.0.1";
        ROCKET_PORT = 8222;
        DOMAIN = "https://vault.${domain}";

        # Nobody else should ever be able to create an account here.
        SIGNUPS_ALLOWED = false;
        INVITATIONS_ALLOWED = false;

        # The admin panel is a full-control backdoor. Off unless you need it,
        # and gated by ADMIN_TOKEN from the sops env file when you do.
        DISABLE_ADMIN_TOKEN = false;

        # No outbound calls to fetch site icons — that would leak which sites
        # you have credentials for to whoever hosts the icon.
        ICON_SERVICE = "internal";
        ICON_BLACKLIST_NON_GLOBAL_IPS = true;

        WEBSOCKET_ENABLED = true;
        LOG_LEVEL = "warn";

        # No SMTP configured (email is deferred), so password-hint and invite
        # mail is off. Fine for a single-user vault.
        SMTP_HOST = null;
      };
    };

    sops.secrets."vaultwarden/env" = {
      # Contents (generate the token with `openssl rand -base64 48`):
      #   ADMIN_TOKEN=...
      owner = "vaultwarden";
    };

    homelab.proxy.routes.vault = "127.0.0.1:8222";

    #########################################################################
    # This is the single most important thing on the box to back up, and the
    # one whose loss is unrecoverable. backups.nix covers /var/lib/vaultwarden;
    # verify a restore before you trust it with your only copy of anything.
    #########################################################################
    systemd.services.vaultwarden.serviceConfig = {
      ProtectHome = true;
      PrivateDevices = true;
      NoNewPrivileges = true;
      RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];
      SystemCallFilter = [ "@system-service" "~@privileged" ];
    };
  };
}
