#!/usr/bin/env bash
# Run this from the NixOS installer, after you've mounted your target at /mnt.
# It handles every step of Phase 1 that can be automated and prompts for the
# three things it can't guess.
#
#   sudo bash scripts/bootstrap.sh
#
# It does NOT partition anything. Do that yourself first — see SETUP.md.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOST="${HOST:-vault}"
CFG="$REPO_DIR/hosts/$HOST/default.nix"

bold() { printf '\033[1m%s\033[0m\n' "$*"; }
warn() { printf '\033[33m%s\033[0m\n' "$*"; }
die()  { printf '\033[31merror: %s\033[0m\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "run as root"
[ -f "$CFG" ] || die "can't find $CFG — run this from inside the repo"

# This script is for the INSTALLER ISO only. On the ISO the root filesystem is
# a tmpfs/overlay; on an installed system it's a real filesystem. Checking that
# is more reliable than checking for /mnt, and it means the error can point
# somewhere useful instead of telling you to partition a disk you already have.
ROOTFS=$(findmnt -no FSTYPE / 2>/dev/null || echo unknown)
case "$ROOTFS" in
  tmpfs|overlay|squashfs) ;;  # live ISO, carry on
  *)
    cat >&2 <<EOF

This is the wrong script for you.

bootstrap.sh installs NixOS from the installer ISO onto empty disks. Your root
filesystem is $ROOTFS, so NixOS is already installed and running.

You want scripts/adopt.sh instead — it points an existing install at this
config, keeping your user account and your hardware-configuration.nix:

    ./scripts/adopt.sh

EOF
    exit 1 ;;
esac

bold "== checking mounts =="
mountpoint -q /mnt || die "/mnt is not mounted. Partition and mount first (SETUP.md phase 1.6)."
mountpoint -q /mnt/boot || die "/mnt/boot is not mounted. That's your 1GB ESP."
printf '  / on  %s\n' "$(findmnt -no SOURCE /mnt)"
printf '  boot  %s\n' "$(findmnt -no SOURCE /mnt/boot)"
echo
read -rp "Look right? [y/N] " ok
[ "$ok" = y ] || die "aborted"

bold "== hardware configuration =="
nixos-generate-config --root /mnt --no-filesystems 2>/dev/null || nixos-generate-config --root /mnt
GEN=/mnt/etc/nixos/hardware-configuration.nix
[ -f "$GEN" ] || die "nixos-generate-config produced nothing at $GEN"

# Keep the filesystems block that generate-config found, since we mounted by
# hand and --no-filesystems would have dropped it.
if ! grep -q "fileSystems" "$GEN"; then
  warn "generated config has no fileSystems block; regenerating with them"
  nixos-generate-config --root /mnt
fi
cp "$GEN" "$REPO_DIR/hosts/$HOST/hardware-configuration.nix"
echo "  -> hosts/$HOST/hardware-configuration.nix"

bold "== hostId (required by ZFS) =="
if grep -q 'hostId = "deadbeef"' "$CFG"; then
  NEW_ID=$(head -c4 /dev/urandom | od -A none -t x4 | tr -d ' \n')
  sed -i "s/hostId = \"deadbeef\"/hostId = \"$NEW_ID\"/" "$CFG"
  echo "  -> $NEW_ID"
else
  echo "  already set, leaving alone"
fi

bold "== admin account =="
CUR_NAME=$(grep -oP 'name = "\K[^"]+' "$CFG" | head -1)
read -rp "  username [$CUR_NAME]: " NAME
NAME="${NAME:-$CUR_NAME}"
sed -i "0,/name = \"$CUR_NAME\"/s//name = \"$NAME\"/" "$CFG"

bold "== ssh key =="
echo "  Paste your PUBLIC key (~/.ssh/id_ed25519.pub on your laptop)."
echo "  The build refuses to proceed without one — password login is off."
if grep -qP '^\s*"ssh-' "$CFG"; then
  echo "  A key is already present. Leaving it."
else
  read -rp "  key: " KEY
  [ -n "$KEY" ] || die "no key given; you would not be able to log in"
  case "$KEY" in
    ssh-*|ecdsa-*|sk-*) ;;
    *) die "that doesn't look like a public key" ;;
  esac
  # Insert into the sshKeys list, replacing the commented placeholder.
  python3 - "$CFG" "$KEY" <<'PYEOF'
import sys, re
path, key = sys.argv[1], sys.argv[2]
s = open(path).read()
s = re.sub(r'(sshKeys = \[\n)(\s*)(# "ssh-ed25519[^\n]*\n)',
           lambda m: f'{m.group(1)}{m.group(2)}"{key}"\n', s, count=1)
open(path, 'w').write(s)
PYEOF
  echo "  -> added"
fi

bold "== timezone =="
CUR_TZ=$(grep -oP 'timeZone = lib.mkDefault "\K[^"]+' "$REPO_DIR/modules/profiles/base.nix" || echo "America/New_York")
read -rp "  timezone [$CUR_TZ]: " TZ
if [ -n "$TZ" ] && [ "$TZ" != "$CUR_TZ" ]; then
  sed -i "s|timeZone = lib.mkDefault \"$CUR_TZ\"|timeZone = lib.mkDefault \"$TZ\"|" \
    "$REPO_DIR/modules/profiles/base.nix"
fi

bold "== copying repo into the target =="
mkdir -p /mnt/etc/nixos
cp -a "$REPO_DIR/." /mnt/etc/nixos/
echo "  -> /mnt/etc/nixos"

bold "== installing =="
warn "This is the step most likely to fail. The config has never been evaluated."
warn "If it errors, the message names the file and line — usually a renamed"
warn "option. Fix it in /mnt/etc/nixos and re-run:"
warn "    nixos-install --flake /mnt/etc/nixos#$HOST"
echo
read -rp "Go? [y/N] " ok
[ "$ok" = y ] || { echo "Stopped. Run the command above when ready."; exit 0; }

nixos-install --flake "/mnt/etc/nixos#$HOST"

bold "== done =="
cat <<EOF

Reboot, then:

  sudo tailscale up --ssh --advertise-exit-node

Then in the Tailscale admin console:
  - approve the exit node
  - disable key expiry for this machine
  - DNS -> global nameserver = this box's tailnet IP, Override local DNS on

Check that NixOS is the default boot entry, or an unattended reboot lands
in Windows and the server stays down:

  bootctl status | grep -i default

Then \`just\` in /etc/nixos lists everything else.
EOF
