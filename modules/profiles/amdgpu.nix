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

        READ THE ROCm NOTE IN THIS FILE BEFORE RELYING ON THIS.
      '';
    };

    computeBackend = lib.mkOption {
      type = lib.types.enum [ "rocm" "vulkan" ];
      default = "vulkan";
      description = ''
        Which compute backend local inference should use. See the long note
        below — the short version is that Vulkan is the lower-risk default on
        a gfx1031 card right now, and ROCm is the higher-ceiling option if it
        happens to work on your ROCm version.
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
    # Only needed on the ROCm path; Vulkan doesn't care.
    systemd.tmpfiles.rules = lib.optionals (cfg.computeBackend == "rocm") [
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
    # Compute:
    #   12GB VRAM is a comfortable 8B-at-Q4 card and a workable 14B-at-Q4 one.
    #   A 32B model at Q4 needs ~18GB and will spill to system RAM, where it
    #   runs at single-digit tokens/sec. Stay at or under 14B for GPU-resident
    #   speed.
    #
    # ROCm on gfx1031 — CORRECTING WHAT I TOLD YOU EARLIER:
    #
    #   I said the 10.3.0 override was "standard and well-trodden, not a hack
    #   that might break". That was too confident. Checking current status:
    #   it IS the standard workaround, but there's an active regression.
    #   ROCm 6.4.3 and later have shipped builds where gfx1031 with
    #   HSA_OVERRIDE_GFX_VERSION=10.3.0 loads a model fine and then segfaults
    #   the moment it receives a prompt. The reported fix is pinning to
    #   ROCm 6.4.1.
    #
    #   The underlying situation hasn't changed: AMD never officially
    #   supported gfx1031, the override borrows gfx1030's code path, and it
    #   can break on any ROCm point release. It's a community workaround, not
    #   a supported configuration.
    #
    #   So: `computeBackend = "vulkan"` is the default in this config.
    #   llama.cpp's Vulkan backend needs no ROCm at all, runs on the same
    #   Mesa driver stack that's already there for gaming, and doesn't care
    #   what AMD's support matrix says. It's somewhat slower than a working
    #   ROCm setup, but "somewhat slower" beats "segfaults on prompt".
    #
    #   Try ROCm if you want the extra speed — just verify it before you
    #   build anything on top of it:
    #     rocminfo | grep gfx          # should show gfx1031
    #     ollama run qwen3:8b "hi"     # the prompt is where it crashes
    #
    # The graphics stack, by contrast, is genuinely solid and needs no
    # caveats: amdgpu is in-tree, Mesa RADV is mature on RDNA2, and this is
    # one of the best-supported cards on Linux for gaming. The ROCm mess is
    # specific to compute.
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
