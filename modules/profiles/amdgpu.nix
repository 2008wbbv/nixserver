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
    # Contention warning:
    #
    # Jellyfin transcoding and Ollama inference share one card and, more
    # importantly, one pool of VRAM. A 7B model at Q4 wants ~5GB resident;
    # Ollama holds it for `keep_alive` after the last request. If someone
    # starts a 4K transcode while a model is loaded, one of them fails.
    #
    # Mitigations, cheapest first:
    #   - OLLAMA_KEEP_ALIVE short (set in llm.nix) so VRAM frees up quickly
    #   - Pre-transcode your library so Jellyfin direct-plays and never needs
    #     the GPU at all — this is the real fix
    #   - Second GPU eventually; even an old one is fine for VAAPI
    #########################################################################
  };
}
