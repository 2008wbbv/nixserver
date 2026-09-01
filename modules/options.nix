{ lib, config, ... }:

let
  inherit (lib) mkOption types;
in
{
  options.homelab = {
    domain = mkOption {
      type = types.str;
      default = "lab.internal";
      description = ''
        Internal DNS zone. Our own resolver answers *.$domain with this host's
        tailnet address, and Tailscale pushes that resolver to every device.
        Use a domain you actually own if you want publicly-trusted TLS certs
        via DNS-01 (see modules/services/proxy.nix).
      '';
    };

    dataDir = mkOption {
      type = types.path;
      default = "/srv";
      description = "Root of bulk data. Services derive their paths from this.";
    };

    secrets.enable = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Whether secrets/secrets.yaml exists and is decryptable by this host.

        Leave false for the very first install. sops-nix decrypts using the
        host's SSH key, which does not exist until the machine is installed —
        so requiring secrets to build would be a chicken-and-egg you could not
        get out of. Every module that needs a secret is off by default; turn
        this on once you've followed secrets/README.md, then enable them.
      '';
    };

    admin = {
      name = mkOption {
        type = types.str;
        description = "Login name of the single human account on this box.";
      };
      sshKeys = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "authorized_keys for the admin account. SSH password auth is off.";
      };

      hashedPassword = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "$y$j9T$...";
        description = ''
          Login password hash, for sitting at the machine.

          REQUIRED if you run a desktop. users.mutableUsers = false means
          `passwd` changes are wiped on the next rebuild, so with no password
          set here there is no way to log in at the console or through GDM —
          only SSH keys work, which is no help when you're at the keyboard.

          Generate:
            mkpasswd -m yescrypt

          This is a hash, not a password, so it is safe-ish to commit — but
          anyone with the repo can attempt to crack it offline. Move it to
          sops (`hashedPasswordFile`) once secrets are set up.
        '';
      };
    };

    # Resolved once, used by every service module that needs to bind or be
    # proxied. Services listen on loopback; Caddy on the tailnet is the only
    # thing that fans out. See docs/ARCHITECTURE.md.
    tailnetInterface = mkOption {
      type = types.str;
      default = "tailscale0";
      readOnly = true;
      internal = true;
    };
  };

  # Every service module declares `homelab.<name>.enable`; this just documents
  # the convention in one place so the host file reads as a manifest.
  config.assertions = [
    {
      assertion =
        config.homelab.admin.sshKeys != [ ] || config.homelab.admin.hashedPassword != null;
      message = ''
        homelab.admin has neither sshKeys nor hashedPassword, and
        users.mutableUsers is false — there would be no way to log in at all.
        Set at least one in hosts/vault/default.nix.
      '';
    }
    {
      # Sitting at a desktop with only an SSH key is not a login.
      assertion =
        config.homelab.desktop.environment == "none"
        || config.homelab.admin.hashedPassword != null;
      message = ''
        homelab.desktop is enabled but homelab.admin.hashedPassword is null.
        With users.mutableUsers = false there is no password to type at GDM,
        so you would be locked out of the machine you are sitting in front of.

        Generate one:   mkpasswd -m yescrypt
        Then set homelab.admin.hashedPassword in hosts/vault/default.nix.
      '';
    }
  ];
}
