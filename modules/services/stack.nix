{ config, lib, pkgs, ... }:

# `stack` — start/stop groups of services at runtime, without a rebuild.
#
# The homelab.<x>.enable flags decide what is INSTALLED. This decides what is
# RUNNING right now. Different jobs: flipping a Nix flag needs a rebuild and
# rewrites the system; `stack stop ai` is instant and reversible.
#
# Groups are registered by the modules themselves, so this list can never drift
# out of sync with what's actually enabled.

let
  cfg = config.homelab.stack;

  # Groups that would cut your own access to the machine. Refused rather than
  # warned about — you reach this box over Tailscale, and `stack stop core`
  # from an SSH session would be the last command you ran.
  protectedGroups = [ "core" ];

  groupsNix = lib.filterAttrs (_: units: units != [ ]) cfg.groups;

  # group:unit1,unit2 lines, read by the script at runtime.
  groupTable = pkgs.writeText "stack-groups" (
    lib.concatStringsSep "\n"
      (lib.mapAttrsToList (g: units: "${g}:${lib.concatStringsSep "," units}") groupsNix)
  );

  stack = pkgs.writeShellApplication {
    name = "stack";
    runtimeInputs = with pkgs; [ systemd gnugrep gnused coreutils sudo ];
    text = ''
      TABLE=${groupTable}
      PROTECTED="${lib.concatStringsSep " " protectedGroups}"

      groups_all() { cut -d: -f1 "$TABLE"; }
      units_of()   { grep "^$1:" "$TABLE" | cut -d: -f2- | tr ',' ' '; }
      is_protected() { case " $PROTECTED " in *" $1 "*) return 0;; esac; return 1; }

      show_group() {
        local g="$1" units mark total=0 running=0
        units=$(units_of "$g")
        if [ -z "$units" ]; then return 0; fi
        # shellcheck disable=SC2086
        for u in $units; do
          total=$((total+1))
          if systemctl is-active --quiet "$u"; then running=$((running+1)); fi
        done
        if   [ "$running" -eq 0 ];      then mark="○ stopped"
        elif [ "$running" -eq "$total" ]; then mark="● running"
        else                                 mark="◐ partial"
        fi
        printf '  %-12s %-11s %s/%s\n' "$g" "$mark" "$running" "$total"
      }

      act() {
        local verb="$1" g="$2" units
        units=$(units_of "$g")
        if [ -z "$units" ]; then
          echo "no such group: $g (try: stack list)" >&2
          return 1
        fi
        if is_protected "$g" && [ "$verb" != start ] && [ "$verb" != status ]; then
          echo "refusing to $verb '$g' — that's the group keeping you connected." >&2
          echo "If you really mean it, use systemctl directly." >&2
          return 1
        fi
        echo "$verb $g: $units"
        # shellcheck disable=SC2086
        sudo systemctl "$verb" $units
      }

      case "''${1:-status}" in
        status|"")
          echo "service groups:"
          for g in $(groups_all); do show_group "$g"; done
          echo
          echo "stack {start|stop|restart|enable|disable} <group>..."
          ;;
        list)
          for g in $(groups_all); do
            printf '%-12s %s\n' "$g" "$(units_of "$g")"
          done
          ;;
        start|stop|restart)
          verb="$1"; shift
          [ $# -gt 0 ] || { echo "which group? (stack list)" >&2; exit 1; }
          for g in "$@"; do act "$verb" "$g"; done
          ;;
        enable|disable)
          # Persists across reboots, unlike start/stop.
          verb="$1"; shift
          [ $# -gt 0 ] || { echo "which group? (stack list)" >&2; exit 1; }
          for g in "$@"; do
            if [ "$verb" = disable ]; then act stop "$g" || true; fi
            act "$verb" "$g"
            if [ "$verb" = enable ]; then act start "$g" || true; fi
          done
          ;;
        -h|--help|help)
          cat <<'USAGE'
stack — start and stop groups of services without rebuilding

  stack                     show every group and whether it's running
  stack list                show which units are in each group
  stack stop ai privacy     stop now (comes back on reboot)
  stack start media
  stack restart monitoring
  stack disable ai          stop AND don't start at boot (persists)
  stack enable ai           start AND start at boot

To change what's INSTALLED rather than what's running, edit
hosts/vault/default.nix and run `just switch`.
USAGE
          ;;
        *)
          echo "unknown command: $1 (try: stack help)" >&2; exit 1 ;;
      esac
    '';
  };
  # One command that answers "is anything wrong?" without opening Grafana.
  doctor = pkgs.writeShellApplication {
    name = "doctor";
    runtimeInputs = with pkgs; [
      systemd coreutils gnugrep gawk curl dnsutils util-linux tailscale
    ];
    text = ''
      ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; }
      bad()  { printf '  \033[31m✗\033[0m %s\n' "$1"; FAIL=$((FAIL+1)); }
      warn() { printf '  \033[33m!\033[0m %s\n' "$1"; }
      FAIL=0

      echo "failed units"
      failed=$(systemctl --failed --no-legend --plain | awk '{print $1}')
      if [ -z "$failed" ]; then
        ok "none"
      else
        # shellcheck disable=SC2086
        for u in $failed; do bad "$u"; done
      fi

      echo
      echo "network"
      if systemctl is-active --quiet tailscaled; then
        ip=$(tailscale ip -4 2>/dev/null || true)
        if [ -n "$ip" ]; then ok "tailscale up ($ip)"; else bad "tailscaled running but no address"; fi
      else bad "tailscaled not running"; fi

      if dig +short +timeout=3 nixos.org @127.0.0.1 >/dev/null 2>&1; then
        ok "dns resolving"
      else bad "dns not answering on 127.0.0.1"; fi

      echo
      echo "disk"
      while read -r use mnt; do
        n=''${use%\%}
        n=''${n// /}
        if   [ "$n" -ge 90 ]; then bad "$mnt ''${use} used"
        elif [ "$n" -ge 80 ]; then warn "$mnt ''${use} used"
        else ok "$mnt ''${use} used"; fi
      done < <(df -h --output=pcent,target -x tmpfs -x devtmpfs 2>/dev/null | tail -n +2)

      echo
      echo "backups"
      if systemctl list-timers restic-backups-offsite.timer --no-legend --no-pager 2>/dev/null | grep -q .; then
        last=$(systemctl show restic-backups-offsite.service -p ExecMainExitTimestampMonotonic --value 2>/dev/null || echo 0)
        if systemctl is-failed --quiet restic-backups-offsite; then bad "last backup FAILED"
        elif [ "''${last:-0}" = "0" ]; then warn "no backup has run yet"
        else ok "backup timer active"; fi
      else warn "backups not enabled"; fi

      echo
      echo "boot"
      if bootctl status 2>/dev/null | grep -qi 'default.*nixos'; then
        ok "nixos is the default boot entry"
      else
        warn "nixos may NOT be default — an unattended reboot could land in Windows"
      fi

      echo
      if [ "$FAIL" -eq 0 ]; then printf '\033[32mall good\033[0m\n'
      else printf '\033[31m%s problem(s)\033[0m\n' "$FAIL"; exit 1; fi
    '';
  };
in
{
  options.homelab.stack.groups = lib.mkOption {
    type = lib.types.attrsOf (lib.types.listOf lib.types.str);
    default = { };
    description = ''
      group name -> systemd units. Service modules add themselves here, so the
      groups always reflect what is actually enabled on this host.
    '';
  };

  config = {
    # Always present: the things that keep you connected and the box healthy.
    # Protected from `stack stop`.
    homelab.stack.groups.core =
      [ "sshd" ]
      ++ lib.optional config.homelab.tailscale.enable "tailscaled"
      ++ lib.optionals config.homelab.dns.enable [ "adguardhome" "unbound" ]
      ++ lib.optional config.homelab.proxy.enable "caddy";

    environment.systemPackages = [ stack doctor ];
  };
}
