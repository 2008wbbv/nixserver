{
  description = "Single-node self-hosted server. Tailnet-only, default-deny, progressively enabled.";

  inputs = {
    # If `nixos-26.05` does not resolve for you, fall back to `nixos-25.11`.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Network-namespace confinement for the torrent client. See modules/services/downloads.nix.
    vpn-confinement.url = "github:Maroka-chan/VPN-Confinement";

    nixos-hardware.url = "github:NixOS/nixos-hardware";
  };

  outputs = { self, nixpkgs, nixpkgs-unstable, sops-nix, disko, vpn-confinement, ... }:
    let
      system = "x86_64-linux";

      # `pkgs.unstable.<name>` for packages that move faster than stable.
      overlayUnstable = final: _prev: {
        unstable = import nixpkgs-unstable {
          inherit (final) system;
          config.allowUnfree = true;
        };
      };
    in
    {
      nixosConfigurations.vault = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit inputs; } // { inputs = { inherit nixpkgs nixpkgs-unstable sops-nix disko vpn-confinement; }; };
        modules = [
          { nixpkgs.overlays = [ overlayUnstable ]; }
          sops-nix.nixosModules.sops
          disko.nixosModules.disko
          vpn-confinement.nixosModules.default
          ./hosts/vault
        ];
      };

      # Convenience: `nix fmt`
      formatter.${system} = nixpkgs.legacyPackages.${system}.nixpkgs-fmt;
    };
}
