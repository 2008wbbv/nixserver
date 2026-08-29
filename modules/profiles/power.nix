{ config, lib, pkgs, ... }:

# Idle power tuning. Budget for this hardware is ~55-85W at the wall, call it
# 70W — roughly $6-15/month depending on your rate. This trims 10-20%.
# The full breakdown is in docs/SERVICES.md.
#
# Biggest lever is NOT in this file: your 144Hz panel can pin the GPU's VRAM
# clocks at maximum even when idle. Running the desktop at 60Hz when you're not
# gaming saves 10-15W — more than every service on the box combined.

let cfg = config.homelab.power;
in
{
  options.homelab.power = {
    enable = lib.mkEnableOption "idle power tuning" // { default = true; };

    aggressivePcie = lib.mkEnableOption ''
      forced PCIe ASPM. Worth 5-15W, but overrides firmware judgement and
      causes NVMe dropouts on some boards. Try the BIOS setting first; if you
      enable this and things get flaky, turn it off first.
    '';
  };

  config = lib.mkIf cfg.enable {
    # schedutil, not powersave: race-to-idle beats running slow on a desktop
    # chip, and the E-cores already handle background services efficiently.
    powerManagement.cpuFreqGovernor = lib.mkDefault "schedutil";
    powerManagement.powertop.enable = true;
    services.thermald.enable = true;

    # med_power_with_dipm is the safe setting; min_power causes drive dropouts.
    services.udev.extraRules = ''
      ACTION=="add", SUBSYSTEM=="scsi_host", KERNEL=="host*", \
        ATTR{link_power_management_policy}="med_power_with_dipm"
    '';

    boot.kernelParams = lib.mkIf cfg.aggressivePcie [ "pcie_aspm=force" ];

    # A desktop session or a game can leave the GPU pinned high and not restore
    # it. Force it back to automatic DPM at boot.
    systemd.services.amdgpu-power-profile = lib.mkIf config.homelab.amdgpu.enable {
      description = "Set amdgpu to automatic power management";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
      script = ''
        for c in /sys/class/drm/card*/device/power_dpm_force_performance_level; do
          [ -w "$c" ] && echo auto > "$c" || true
        done
      '';
    };

    # No-op on SSDs; worth 5-8W each if you add spinning disks later.
    powerManagement.powerUpCommands = ''
      for d in /dev/disk/by-id/ata-*; do
        case "$d" in *-part*) continue;; esac
        ${pkgs.hdparm}/bin/hdparm -S 240 "$d" >/dev/null 2>&1 || true
      done
    '';

    environment.systemPackages = with pkgs; [
      powertop
      hdparm
      lact # AMD fan curves, power limits, undervolting
    ];
  };
}
