# Common operations. `just` with no argument lists these.
# Install with: nix-shell -p just   (or it's in the system packages)

default:
    @just --list

# Rebuild and switch. The one you'll type most.
switch:
    sudo nixos-rebuild switch --flake .#vault

# Rebuild without switching — fast iteration when fixing build errors.
build:
    sudo nixos-rebuild build --flake .#vault

# Switch, but revert automatically if you don't confirm. Use for anything
# touching networking.
test:
    sudo nixos-rebuild test --flake .#vault

# Show what went wrong, in detail.
trace:
    sudo nixos-rebuild build --flake .#vault --show-trace

# Update all flake inputs, then build. Review before switching.
update:
    nix flake update
    sudo nixos-rebuild build --flake .#vault

# What's running, what failed.
status:
    @systemctl --failed --no-pager || true
    @echo
    @systemctl list-units --type=service --state=running --no-pager | head -40

# Logs for one service: just logs jellyfin
logs SERVICE:
    journalctl -u {{SERVICE}} -n 100 --no-pager

# Everything that failed since boot.
failed:
    journalctl -b -p err --no-pager

# Disk and store usage.
space:
    @df -h / /srv 2>/dev/null || df -h /
    @echo
    @nix path-info -Sh /run/current-system

# Free up disk: drop old generations and optimise the store.
gc:
    sudo nix-collect-garbage --delete-older-than 30d
    sudo nix store optimise

# List bootable generations, so you know what to roll back to.
generations:
    sudo nixos-rebuild list-generations

# Edit secrets.
secrets:
    sops secrets/secrets.yaml

# Verify the torrent VPN namespace actually confines traffic.
check-vpn:
    @echo -n "namespace (should be VPN exit): "; sudo ip netns exec wg curl -s --max-time 15 https://ifconfig.me; echo
    @echo -n "host      (should be yours):    "; curl -s --max-time 15 https://ifconfig.me; echo
    @echo "These MUST differ."

# Verify Tor routing.
check-tor:
    tor-route test

# Is NixOS still the default boot entry? If Windows is, an unattended reboot
# leaves the server down.
check-boot:
    @bootctl status | grep -iE "default|current" || true

# Format all nix files.
fmt:
    nix fmt
