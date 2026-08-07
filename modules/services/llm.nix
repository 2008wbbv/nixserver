{ config, lib, pkgs, ... }:

let cfg = config.homelab.llm;
in
{
  options.homelab.llm.enable = lib.mkEnableOption "Ollama + Open WebUI (local inference)";

  config = lib.mkIf cfg.enable {
    assertions = [{
      assertion = config.homelab.amdgpu.enable;
      message = "homelab.llm requires homelab.amdgpu.enable = true (or edit acceleration below for CPU-only).";
    }];

    services.ollama = {
      enable = true;
      acceleration = "rocm";
      host = "127.0.0.1";
      port = 11434;

      # Spoof the gfx target for cards ROCm doesn't officially list.
      rocmOverrideGfx = config.homelab.amdgpu.gfxVersion;

      environmentVariables = {
        # Free VRAM quickly so Jellyfin can transcode. See profiles/amdgpu.nix.
        OLLAMA_KEEP_ALIVE = "5m";
        OLLAMA_NUM_PARALLEL = "1";
        OLLAMA_MAX_LOADED_MODELS = "1";
      };

      # Pulled on activation so the box is useful offline.
      # Sized for the 6750 XT's 12GB — see profiles/amdgpu.nix. Both of these
      # stay fully GPU-resident; a 32B would spill to RAM and crawl.
      loadModels = [
        "qwen3:8b" # daily driver, ~5GB
        "qwen2.5-coder:14b" # ~9GB, still comfortably resident
        "nomic-embed-text" # embeddings, for RAG over your own docs
      ];
    };

    services.open-webui = {
      enable = true;
      host = "127.0.0.1";
      port = 8088;
      environment = {
        OLLAMA_BASE_URL = "http://127.0.0.1:11434";
        WEBUI_AUTH = "True";
        # No telemetry, no model downloads from HF at runtime.
        ANONYMIZED_TELEMETRY = "False";
        DO_NOT_TRACK = "True";
        SCARF_NO_ANALYTICS = "True";
        ENABLE_OPENAI_API = "False"; # fully local; no keys, no egress
      };
    };

    homelab.proxy.routes.chat = "127.0.0.1:8088";

    # llama.cpp directly, for when you want raw control over quantisation,
    # context length, or GGUFs Ollama won't take.
    environment.systemPackages = with pkgs; [
      (llama-cpp.override { rocmSupport = true; })
    ];
  };
}
