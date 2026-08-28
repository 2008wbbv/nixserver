{ config, lib, pkgs, ... }:

let cfg = config.homelab.power;
in
{
  options.homelab.power = {
    enable = lib.mkEnableOption "idle power tuning";

    aggressivePcie = lib.mkEnableOption ''
      forced PCIe ASPM (`pcie_aspm=force`).

      Worth 5–15W on a desktop board, because most of them ship with ASPM
      disabled or set to a conservative default. But `force` overrides the
      firmware's own judgement about what the hardware can tolerate, and on a
      minority of boards that means NVMe dropouts or wake-from-suspend
      failures.

      Try the BIOS setting first — enable ASPM / L1 substates there. Only come
      here if the board doesn't expose it. If you do enable this and the
      machine gets flaky, this is the first thing to turn off.
    '';
  };

  config = lib.mkIf cfg.enable {
    #########################################################################
    # What this machine actually costs to run
    #
    # Rough idle budget for your hardware, at the wall:
    #
    #   i7-12700KF idle          10–20W   Alder Lake idles decently, and the
    #                                     E-cores are where Linux puts
    #                                     background services — which is most
    #                                     of what this box does
    #   RX 6750 XT idle           7–20W   the wide range is real; see below
    #   Board + RAM + 2 NVMe     20–30W
    #   Fans                      3–8W
    #   PSU losses               10–20%   a big PSU at 60W load is in its
    #                                     worst efficiency band
    #   ─────────────────────────────────
    #   Total                    55–85W   call it ~70W
    #
    # 70W × 24h × 365 = ~613 kWh/year.
    #
    #   at $0.12/kWh   ~$74/yr    ~$6/mo    (cheap US states)
    #   at $0.17/kWh   ~$104/yr   ~$9/mo    (US average)
    #   at $0.30/kWh   ~$184/yr   ~$15/mo   (CA, New England, HI)
    #
    # These are estimates and could be off by 30%. A smart plug with energy
    # monitoring (Kasa KP115, ~$15) turns this into a measurement — and you can
    # scrape it into Prometheus so it lands on the same Grafana dashboard as
    # everything else. Worth it before optimising anything here.
    #########################################################################

    #########################################################################
    # CPU
    #
    # schedutil rather than powersave: it ramps with actual demand, so idle
    # sits low but a Jellyfin transcode or a nix build still gets full clocks.
    # `powersave` on a desktop chip mostly just makes things feel sluggish
    # without saving much, because the race-to-idle effect means finishing
    # work quickly and returning to a low C-state often beats running slow.
    #########################################################################
    powerManagement.cpuFreqGovernor = lib.mkDefault "schedutil";

    # Intel thermal/power daemon. Keeps the package in sensible power states
    # rather than bouncing off thermal limits.
    services.thermald.enable = true;

    # Applies a pile of small runtime-PM tunables that are off by default:
    # USB autosuspend, audio codec power-down, SATA link power management.
    # Individually tiny, collectively worth several watts.
    powerManagement.powertop.enable = true;

    #########################################################################
    # SATA link power management
    #
    # powertop sets this at boot but it can get reset. med_power_with_dipm is
    # the setting that's both effective and safe — `min_power` saves slightly
    # more and has a history of causing drive dropouts.
    #########################################################################
    services.udev.extraRules = ''
      ACTION=="add", SUBSYSTEM=="scsi_host", KERNEL=="host*", \
        ATTR{link_power_management_policy}="med_power_with_dipm"
    '';

    #########################################################################
    # GPU — the biggest single variable, and the one you can't remove
    #
    # The 6750 XT idles between about 7W and 40W depending on what it thinks
    # it needs to drive. Two things push it to the high end:
    #
    #   High refresh rate. Your 1080p144 panel can keep VRAM clocks pinned at
    #   maximum even at idle, because the driver decides it can't afford to
    #   downclock between frames. Dropping the desktop to 60Hz when you're not
    #   gaming genuinely saves 10–15W. RDNA2 handles this better than RDNA3
    #   does, but it's still the main lever.
    #
    #   Multiple displays. Same mechanism, worse.
    #
    # Running headless (the server case, no monitor attached) it should sit
    # near the bottom of that range on its own.
    #
    # `auto` lets the driver clock down properly. It's usually the default,
    # but a desktop session or a game can leave it on `high` and it doesn't
    # always go back.
    #########################################################################
    systemd.services.amdgpu-power-profile = lib.mkIf config.homelab.amdgpu.enable {
      description = "Set amdgpu to automatic power management";
      wantedBy = [ "multi-user.target" ];
      after = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        for card in /sys/class/drm/card*/device/power_dpm_force_performance_level; do
          [ -w "$card" ] && echo auto > "$card" || true
        done
      '';
    };

    boot.kernelParams = lib.mkIf cfg.aggressivePcie [ "pcie_aspm=force" ];

    #########################################################################
    # Spin down mechanical disks
    #
    # No-op on your current SSDs, but if you add spinning disks for the NAS
    # this is worth 5–8W each. 20 minutes of idle before parking.
    #
    # Don't set this aggressively low — the head-park cycle has a finite
    # lifetime and thrashing it kills drives faster than leaving them spinning.
    #########################################################################
    powerManagement.powerUpCommands = ''
      for d in /dev/disk/by-id/ata-*; do
        case "$d" in *-part*) continue;; esac
        ${pkgs.hdparm}/bin/hdparm -S 240 "$d" >/dev/null 2>&1 || true
      done
    '';

    environment.systemPackages = with pkgs; [
      powertop # `sudo powertop` — see where the watts go
      hdparm
      lm_sensors
      lact # AMD GPU control: fan curves, power limits, undervolting
    ];

    #########################################################################
    # The services that actually cost you something
    #
    # Most of what runs here is genuinely free at idle — DNS, Caddy,
    # Vaultwarden, Syncthing and Samba are all sitting in a poll loop doing
    # nothing measurable. Jellyfin idle is nothing; only transcoding costs,
    # and only while it's happening.
    #
    # Three that aren't free:
    #
    #   i2pd with transit sharing. You're relaying other people's traffic
    #   24/7 by choice — that's constant CPU and network. It's the right thing
    #   to do for the network and it is not free. Lower `share` in
    #   anonymity.nix, or drop `bandwidth`, if you'd rather not.
    #
    #   Tor, if you ever enable relay mode. Same deal. It's off.
    #
    #   Prometheus + Loki. Constant low-level scraping and compaction. A few
    #   watts. Worth it — being blind to a failing disk costs more than the
    #   electricity.
    #
    # Ollama is worth understanding: it costs nothing when idle, but a loaded
    # model holds VRAM and keeps the GPU out of its deepest idle state. That's
    # what OLLAMA_KEEP_ALIVE=5m in llm.nix is for.
    #########################################################################
  };
}
