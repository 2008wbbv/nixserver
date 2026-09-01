#!/usr/bin/env bash
# Point an ALREADY-INSTALLED NixOS at this config.
#
#   ./scripts/adopt.sh
#
# Run as your normal user, not root — it needs to know who you are, and it
# only uses sudo for the one step that requires it.
#
# It keeps your existing user account and your existing
# hardware-configuration.nix. It does not touch disks, does not partition, and
# does not activate anything: it stops at a build so you can review before
# switching.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOST="${HOST:-vault}"
CFG="$REPO_DIR/hosts/$HOST/default.nix"

bold() { printf '\033[1m%s\033[0m\n' "$*"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }
die()  { printf '\033[31merror: %s\033[0m\n' "$*" >&2; exit 1; }

[ "$(id -u)" -ne 0 ] || die "run as your normal user, not root — it needs \$USER and your homedir"
[ -f "$CFG" ] || die "can't find $CFG — run this from inside the repo"

ROOTFS=$(findmnt -no FSTYPE / 2>/dev/null || echo unknown)
case "$ROOTFS" in
  tmpfs|overlay|squashfs)
    die "you're on the installer ISO — use scripts/bootstrap.sh instead" ;;
esac

bold "== this machine =="
USER_NAME="$(id -un)"
printf '  user      %s\n' "$USER_NAME"
printf '  hostname  %s\n' "$(hostname)"
printf '  root fs   %s on %s\n' "$ROOTFS" "$(findmnt -no SOURCE /)"
echo

# --- 1. hardware-configuration.nix ------------------------------------------
bold "== hardware configuration =="
HW=""
for candidate in /etc/nixos/hardware-configuration.nix \
                 /etc/nixos.orig/hardware-configuration.nix; do
  [ -f "$candidate" ] && { HW="$candidate"; break; }
done

if [ -z "$HW" ]; then
  warn "no existing hardware-configuration.nix found; generating one"
  sudo nixos-generate-config --show-hardware-config \
    > "$REPO_DIR/hosts/$HOST/hardware-configuration.nix"
  ok "generated"
else
  cp "$HW" "$REPO_DIR/hosts/$HOST/hardware-configuration.nix"
  ok "copied from $HW"
fi

# --- 2. stateVersion --------------------------------------------------------
bold "== stateVersion =="
# This is a compatibility marker for the release you INSTALLED, not a version
# to keep current. Taking it from the existing config avoids subtle breakage.
EXISTING_SV=""
for candidate in /etc/nixos/configuration.nix /etc/nixos.orig/configuration.nix; do
  [ -f "$candidate" ] || continue
  EXISTING_SV=$(grep -oP 'system\.stateVersion\s*=\s*"\K[^"]+' "$candidate" | head -1 || true)
  [ -n "$EXISTING_SV" ] && break
done

CUR_SV=$(grep -oP 'system\.stateVersion = "\K[^"]+' "$CFG" | head -1)
if [ -n "$EXISTING_SV" ] && [ "$EXISTING_SV" != "$CUR_SV" ]; then
  sed -i "s/system\.stateVersion = \"$CUR_SV\"/system.stateVersion = \"$EXISTING_SV\"/" "$CFG"
  ok "set to $EXISTING_SV (from your existing install)"
else
  ok "$CUR_SV"
fi

# --- 3. username ------------------------------------------------------------
bold "== admin account =="
# users.mutableUsers = false means an account not declared here is REMOVED.
CUR_NAME=$(grep -oP 'name = "\K[^"]+' "$CFG" | head -1)
if [ "$CUR_NAME" != "$USER_NAME" ]; then
  sed -i "0,/name = \"$CUR_NAME\"/s//name = \"$USER_NAME\"/" "$CFG"
  ok "set to $USER_NAME (was $CUR_NAME)"
else
  ok "$USER_NAME"
fi

# --- 4. password hash -------------------------------------------------------
bold "== login password =="
if grep -q 'hashedPassword = null;' "$CFG"; then
  echo "  mutableUsers = false means \`passwd\` doesn't survive a rebuild, so"
  echo "  the password has to live in the config. Without one you can't log in"
  echo "  at GDM at all."
  echo
  echo "  You'll be prompted twice by mkpasswd. Nothing is echoed."
  HASH=$(nix-shell -p mkpasswd --run 'mkpasswd -m yescrypt' 2>/dev/null) \
    || die "mkpasswd failed"
  [ -n "$HASH" ] || die "empty hash"
  python3 - "$CFG" "$HASH" <<'PYEOF'
import sys
path, h = sys.argv[1], sys.argv[2]
s = open(path).read()
s = s.replace("hashedPassword = null;", f'hashedPassword = "{h}";', 1)
open(path, "w").write(s)
PYEOF
  ok "set"
else
  ok "already set, leaving alone"
fi

# --- 5. ssh key -------------------------------------------------------------
bold "== ssh key =="
if grep -qP '^\s*"(ssh|ecdsa|sk)-' "$CFG"; then
  ok "already present"
else
  PUB=""
  for k in "$HOME"/.ssh/id_ed25519.pub "$HOME"/.ssh/id_rsa.pub; do
    [ -f "$k" ] && { PUB=$(cat "$k"); break; }
  done
  if [ -z "$PUB" ]; then
    warn "no key in ~/.ssh — generate one with: ssh-keygen -t ed25519"
    warn "you can add it later; the password above is enough to log in"
  else
    python3 - "$CFG" "$PUB" <<'PYEOF'
import sys, re
path, key = sys.argv[1], sys.argv[2]
s = open(path).read()
s = re.sub(r'(sshKeys = \[\n)(\s*)# "ssh-ed25519[^\n]*\n',
           lambda m: f'{m.group(1)}{m.group(2)}"{key}"\n', s, count=1)
open(path, "w").write(s)
PYEOF
    ok "added from ${PUB%% *} ..."
  fi
fi

# --- 6. hostId --------------------------------------------------------------
bold "== hostId =="
if grep -q 'hostId = "deadbeef"' "$CFG"; then
  NEW_ID=$(head -c4 /dev/urandom | od -A none -t x4 | tr -d ' \n')
  sed -i "s/hostId = \"deadbeef\"/hostId = \"$NEW_ID\"/" "$CFG"
  ok "$NEW_ID"
else
  ok "already set"
fi

# --- 7. timezone ------------------------------------------------------------
bold "== timezone =="
SYS_TZ=$(timedatectl show -p Timezone --value 2>/dev/null || echo "")
CUR_TZ=$(grep -oP 'timeZone = lib\.mkDefault "\K[^"]+' "$REPO_DIR/modules/profiles/base.nix" || echo "")
if [ -n "$SYS_TZ" ] && [ "$SYS_TZ" != "$CUR_TZ" ]; then
  sed -i "s|timeZone = lib.mkDefault \"$CUR_TZ\"|timeZone = lib.mkDefault \"$SYS_TZ\"|" \
    "$REPO_DIR/modules/profiles/base.nix"
  ok "$SYS_TZ (from your system)"
else
  ok "${CUR_TZ:-unset}"
fi

# --- 8. build ---------------------------------------------------------------
echo
bold "== building =="
echo "  This activates nothing. It only checks the config evaluates and builds."
echo "  Expect failures the first time — this config has never been evaluated."
echo "  The error names the file and line; it's almost always a renamed option."
echo

if sudo nixos-rebuild build --flake "$REPO_DIR#$HOST"; then
  echo
  bold "== built cleanly =="
  cat <<EOF

Nothing has changed on your system yet. To activate:

  sudo nixos-rebuild switch --flake $REPO_DIR#$HOST

THEN, BEFORE REBOOTING: press Ctrl+Alt+F3 and log in as $USER_NAME with the
password you just set. If that works you're safe. If it doesn't, you still
have this session — fix hashedPassword and switch again.

After that:

  sudo tailscale up --ssh --advertise-exit-node
  doctor

EOF
else
  echo
  die "build failed — see above. Fix, then re-run this script (it's idempotent)."
fi
