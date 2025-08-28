{
  description = "NixOS module to manage secrets outside nix store";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";

  outputs = {
    self,
    nixpkgs,
    ...
  }: {
    nixosModules = {
      hemlis = import ./modules/hemlis.nix;
    };
  };
}
