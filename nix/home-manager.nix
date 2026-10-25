# home-manager のモジュール。利用者のホームの ~/Library/Input Methods に sokkou を入れる
self:
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.sokkou;
in
{
  options.programs.sokkou = {
    enable = lib.mkEnableOption "sokkou, an SKK-flavoured Japanese input method";
    package = lib.mkOption {
      type = lib.types.package;
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.sokkou;
      defaultText = lib.literalExpression "sokkou.packages.\${system}.sokkou";
      description = "The sokkou package to install.";
    };
    autoUpdate = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Let sokkou replace itself with new GitHub releases (the "新しいリリースを自動で入れる" menu item).
        When true, activation never downgrades a newer self-updated copy. When false, activation pins the
        installed copy to the package version.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      (lib.hm.assertions.assertPlatform "programs.sokkou" pkgs lib.platforms.darwin)
    ];
    home.activation.sokkou = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run ${
        pkgs.callPackage ./activate.nix {
          package = cfg.package;
          inherit (cfg) autoUpdate;
        }
      }
    '';
  };
}
