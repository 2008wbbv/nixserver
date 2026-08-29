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
        description = "authorized_keys for the admin account. Password auth is off.";
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
      assertion = config.homelab.admin.sshKeys != [ ];
      message = ''
        homelab.admin.sshKeys is empty and password authentication is disabled —
        you would not be able to log in. Add your public key in hosts/vault/default.nix.
      '';
    }
  ];
}
