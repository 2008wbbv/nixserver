{ config, lib, pkgs, ... }:

# Push notifications to your phone, via self-hosted ntfy.
#
# This closes a real gap: everything so far writes alerts to Prometheus and
# Grafana, which means a failing disk or a backup that stopped running is
# discovered whenever you next happen to open a dashboard. Which is never.
#
# ntfy is a ~20MB Go binary. Install the app, subscribe to a topic, done.

let
  cfg = config.homelab.notify;
  inherit (config.homelab) domain;

  notify = pkgs.writeShellApplication {
    name = "notify";
    runtimeInputs = [ pkgs.curl ];
    text = ''
      # notify [-p high|urgent] [-t title] <message>
      prio=default; title="vault"
      while getopts "p:t:" o; do
        case "$o" in
          p) prio="$OPTARG" ;;
          t) title="$OPTARG" ;;
          *) echo "usage: notify [-p priority] [-t title] <message>" >&2; exit 1 ;;
        esac
      done
      shift $((OPTIND - 1))
      msg="''${*:-(no message)}"
      curl -fsS \
        -H "Title: $title" \
        -H "Priority: $prio" \
        -H "Tags: computer" \
        -d "$msg" \
        "http://127.0.0.1:${toString cfg.port}/${cfg.topic}" >/dev/null
    '';
  };
in
{
  options.homelab.notify = {
    enable = lib.mkEnableOption "ntfy push notifications" // { default = true; };

    topic = lib.mkOption {
      type = lib.types.str;
      default = "vault-alerts";
      description = ''
        Topic to publish to. Anyone who knows a topic name on a given server
        can read it — but this server is tailnet-only, so the tailnet is the
        access control. Change it if you ever expose ntfy publicly.
      '';
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 2586;
    };
  };

  config = lib.mkIf cfg.enable {
    services.ntfy-sh = {
      enable = true;
      settings = {
        base-url = "https://ntfy.${domain}";
        listen-http = "127.0.0.1:${toString cfg.port}";
        behind-proxy = true;
        auth-default-access = "read-write"; # tailnet-only; see topic note above
      };
    };

    homelab.proxy.routes.ntfy = "127.0.0.1:${toString cfg.port}";
    homelab.stack.groups.notify = [ "ntfy-sh" ];

    environment.systemPackages = [ notify ];

    systemd.services = lib.mkMerge [
      {
        # Generic failure handler. Any unit with
        # `OnFailure=notify@%n.service` pushes a notification naming itself
        # and its last few log lines.
        "notify@" = {
          description = "Push a notification about failed unit %i";
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${pkgs.writeShellScript "notify-failure" ''
              UNIT="$1"
              LOG=$(${pkgs.systemd}/bin/journalctl -u "$UNIT" -n 8 --no-pager -o cat || true)
              ${notify}/bin/notify -p high -t "FAILED: $UNIT" "$LOG"
            ''} %i";
          };
        };

        # Daily digest, so silence means "checked and fine" rather than "the
        # notifier itself is broken".
        daily-digest = {
          description = "Daily health summary";
          serviceConfig.Type = "oneshot";
          script = ''
            FAILED=$(${pkgs.systemd}/bin/systemctl --failed --no-legend --plain | ${pkgs.coreutils}/bin/wc -l)
            DISK=$(${pkgs.coreutils}/bin/df -h / | ${pkgs.gawk}/bin/awk 'NR==2{print $5" used, "$4" free"}')
            UP=$(${pkgs.procps}/bin/uptime -p)
            if [ "$FAILED" -gt 0 ]; then
              ${notify}/bin/notify -p high -t "vault: $FAILED failed" "$DISK - $UP"
            else
              ${notify}/bin/notify -p min -t "vault ok" "$DISK - $UP"
            fi
          '';
        };
      }

      # Attach the handler to the units whose silent failure actually costs you.
      (lib.mkIf config.homelab.backups.enable {
        "restic-backups-offsite".onFailure = [ "notify@restic-backups-offsite.service" ];
      })
      (lib.mkIf config.homelab.vaultwarden.enable {
        vaultwarden.onFailure = [ "notify@vaultwarden.service" ];
      })
      (lib.mkIf config.homelab.dns.enable {
        adguardhome.onFailure = [ "notify@adguardhome.service" ];
        unbound.onFailure = [ "notify@unbound.service" ];
      })
      (lib.mkIf config.homelab.storage.enable {
        "zpool-scrub".onFailure = [ "notify@zpool-scrub.service" ];
      })
    ];

    systemd.timers.daily-digest = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "09:00";
        Persistent = true;
        RandomizedDelaySec = "15m";
      };
    };

    # Setup: install the ntfy app, add https://ntfy.lab.internal as the server
    # (you must be on the tailnet), subscribe to the topic above.
    # Test with: notify -p high "hello"
  };
}
