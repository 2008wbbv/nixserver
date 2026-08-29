# PLACEHOLDER — replace this entire file.
#
# On the target machine, after booting the NixOS installer (or after installing):
#
#   sudo nixos-generate-config --no-filesystems --root /mnt   # if using disks.nix/disko
#   sudo nixos-generate-config --root /mnt                    # if partitioning by hand
#
# then copy the generated hardware-configuration.nix over this file and commit it.
# It contains your real disk UUIDs, CPU microcode, and kernel modules — none of
# which can be guessed from here.
{ lib, ... }:

{
  # Fail loudly rather than silently building an unbootable system.
  assertions = [{
    assertion = false;
    message = ''
      hosts/vault/hardware-configuration.nix is still the placeholder.
      Run nixos-generate-config on the target machine and replace it.
    '';
  }];

  boot.loader.systemd-boot.enable = lib.mkDefault true;
  boot.loader.efi.canTouchEfiVariables = lib.mkDefault true;
}
