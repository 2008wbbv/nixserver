{ config, lib, pkgs, ... }:

let cfg = config.homelab.amdgpu;
in
{
  options.homelab.amdgpu = {
    enable = lib.mkEnableOption "AMD GPU: VAAPI transcode + ROCm compute";

    gfxVersion = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "11.0.0";
      description = ''
        ROCm gfx target to spoof for cards ROCm doesn't officially support.
        Find your real one with `rocminfo | grep gfx`. Common overrides:
          RDNA2 (6600/6700/6800/6900) -> "10.3.0"
          RDNA3 (7600/7700/7800/7900) -> "11.0.0"
        Leave null if your card is officially supported.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    boot.initrd.kernelModules = [ "amdgpu" ];

    hardware.graphics = {
      enable = true;
      enable32Bit = true;
      extraPackages = with pkgs; [
        rocmPackages.clr.icd # OpenCL
        libva-vdpau-driver
        libvdpau-va-gl
      ];
    };

    # ROCm expects its libraries at /opt/rocm. Nix puts them in the store, so
    # symlink the path ROCm hardcodes. Without this, hipBLAS silently falls back
    # to CPU and you spend an evening wondering why inference is slow.
    systemd.tmpfiles.rules = [
      "L+ /opt/rocm - - - - ${pkgs.rocmPackages.clr}"
    ];

    environment.systemPackages = with pkgs; [
      libva-utils # vainfo — verify transcode support
      rocmPackages.rocminfo # verify compute support
      radeontop # watch utilisation
      nvtopPackages.amd
    ];

    # Anything that touches the GPU needs these groups.
    users.groups.render = { };
    users.groups.video = { };

    #########################################################################
    # RX 6750 XT specifics (RDNA2 / gfx1031 / 12GB):
    #
    # Transcode (VCN 3.0), for Jellyfin:
    #   H.264   decode + encode
    #   HEVC    decode + encode
    #   AV1     decode only — RDNA2 cannot encode AV1. That landed with
    #           RDNA3 (7000-series). If Jellyfin looks like it's offering
    #           AV1 encode, don't enable it; you'll get silent CPU fallback.
    #
    # Compute (ROCm), for Ollama:
    #   12GB VRAM is a comfortable 8B-at-Q4 card and a workable 14B-at-Q4 one.
    #   A 32B model at Q4 needs ~18GB and will spill to system RAM, where it
    #   runs at single-digit tokens/sec. Stay at or under 14B for GPU-resident
    #   speed.
    #
    # Contention warning:
    #   Both of the above share those same 12GB. An 8B model resident is ~5GB;
    #   Ollama holds it for `keep_alive` after the last request. A 4K transcode
    #   starting during that will fight it.
    #
    #   Mitigations, cheapest first:
    #     - short OLLAMA_KEEP_ALIVE (set in llm.nix) so VRAM frees quickly
    #     - pre-transcode your library so Jellyfin direct-plays and never
    #       touches the GPU — this is the real fix
    #     - a second cheap GPU for VAAPI later; even a very old one works
    #########################################################################
  };
}
