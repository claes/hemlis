{
  description = "NixOS module to manage secrets outside nix store";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";

  outputs = {
    self,
    nixpkgs,
    ...
  }: {
    nixosModules = {
      default = import ./modules/hemlis.nix;
    };
  };
}
