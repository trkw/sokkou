{
  description = "sokkou: SKK-flavoured Japanese input method for macOS";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs =
    { self, nixpkgs }:
    let
      systems = [ "aarch64-darwin" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      packages = forAllSystems (pkgs: {
        sokkou = pkgs.callPackage ./nix/package.nix { };
        default = self.packages.${pkgs.stdenv.hostPlatform.system}.sokkou;
      });

      overlays.default = final: _prev: {
        sokkou = final.callPackage ./nix/package.nix { };
      };

      darwinModules.default = import ./nix/darwin.nix self;
      homeManagerModules.default = import ./nix/home-manager.nix self;
    };
}
