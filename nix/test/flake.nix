# CI が使う、モジュールを nix-darwin と home-manager に入れて評価できるかの確かめ。
# 組み立てはしない（Linux のランナーで aarch64-darwin の評価だけする）。
#   nix eval --json ./nix/test#tests --override-input sokkou "path:$PWD"
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nix-darwin = {
      url = "github:nix-darwin/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sokkou = {
      url = "github:trkw/sokkou";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      nixpkgs,
      nix-darwin,
      home-manager,
      sokkou,
      ...
    }:
    let
      darwin = nix-darwin.lib.darwinSystem {
        modules = [
          sokkou.darwinModules.default
          {
            nixpkgs.hostPlatform = "aarch64-darwin";
            system.stateVersion = 6;
            system.primaryUser = "trkw";
            programs.sokkou.enable = true;
          }
        ];
      };
      home = home-manager.lib.homeManagerConfiguration {
        pkgs = nixpkgs.legacyPackages.aarch64-darwin;
        modules = [
          sokkou.homeManagerModules.default
          {
            home.username = "trkw";
            home.homeDirectory = "/Users/trkw";
            home.stateVersion = "25.05";
            programs.sokkou = {
              enable = true;
              autoUpdate = false;
            };
          }
        ];
      };
    in
    {
      tests = {
        darwin = darwin.system.drvPath;
        home = home.activationPackage.drvPath;
        package = sokkou.packages.aarch64-darwin.sokkou.drvPath;
      };
    };
}
