{ ... }:

{
  imports = [
    ./options.nix

    ./profiles/base.nix
    ./profiles/hardening.nix
    ./profiles/amdgpu.nix
    ./profiles/storage.nix
    ./profiles/desktop.nix
    ./profiles/resilience.nix

    ./services/tailscale.nix
    ./services/dns.nix
    ./services/proxy.nix
    ./services/monitoring.nix
    ./services/backups.nix
    ./services/files.nix
    ./services/vaultwarden.nix
    ./services/media.nix
    ./services/knowledge.nix
    ./services/downloads.nix
    ./services/anonymity.nix
    ./services/maps.nix
    ./services/osint.nix
    ./services/llm.nix
    ./services/comms.nix
    ./services/selfhost.nix
    ./services/gaming.nix
    ./services/printer.nix
  ];
}
