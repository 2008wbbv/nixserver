{ config, lib, pkgs, ... }:

let cfg = config.homelab.amdgpu;
in
{
  options.homelab.amdgpu = {
    enable = lib.mkEnableOption "AMD GPU: VAAPI transcode + compute";

    gfxVersion = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "10.3.0";
      description = "ROCm gfx target to spoof. Only used when computeBackend = \"rocm\".";
    };

    computeBackend = lib.mkOption {
      type = lib.types.enum [ "rocm" "vulkan" ];
      default = "vulkan";
      description = ''
        Vulkan is the default because ROCm 6.4.3+ has a live regression that
        segfaults gfx1031 (your 6750 XT) the moment a model receives a prompt.
        Vulkan needs no ROCm and rides the Mesa stack already present for games.

        Try "rocm" for more speed, but verify with a real prompt first:
          rocminfo | grep gfx
          ollama run qwen3:8b "hi"
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    boot.initrd.kernelModules = [ "amdgpu" ];

    hardware.graphics = {
      enable = true;
      enable32Bit = true; # Steam/Proton
      extraPackages = with pkgs; [
        libva-vdpau-driver
        libvdpau-va-gl
      ] ++ lib.optional (cfg.computeBackend == "rocm") rocmPackages.clr.icd;
    };

    # ROCm hardcodes /opt/rocm. Without this, hipBLAS silently falls back to CPU.
    systemd.tmpfiles.rules = lib.optionals (cfg.computeBackend == "rocm") [
      "L+ /opt/rocm - - - - ${pkgs.rocmPackages.clr}"
    ];

    environment.systemPackages = with pkgs; [
      libva-utils # vainfo — verify transcode
      radeontop
      nvtopPackages.amd
    ] ++ lib.optional (cfg.computeBackend == "rocm") rocmPackages.rocminfo;

    # 6750 XT (RDNA2, 12GB):
    #   Encode: H.264 + HEVC. NO AV1 encode — that's RDNA3+. If Jellyfin
    #   offers it, don't enable it; you get silent CPU fallback.
    #   Models: 8B@Q4 (~5GB) and 14B@Q4 (~9GB) stay resident. 32B spills to RAM.
    #   Contention: an inference model resident + a 4K transcode will fight for
    #   VRAM. OLLAMA_KEEP_ALIVE is short in llm.nix for this reason.
  };
}
