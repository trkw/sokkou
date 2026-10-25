# nix-darwin のモジュール。nix-darwin の起動は root なので、sokkou を入れるところは利用者として動かす
self:
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.sokkou;
  activate = pkgs.callPackage ./activate.nix {
    package = cfg.package;
    inherit (cfg) autoUpdate;
  };
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
    user = lib.mkOption {
      type = lib.types.str;
      default = config.system.primaryUser;
      defaultText = lib.literalExpression "config.system.primaryUser";
      description = "The user whose ~/Library/Input Methods gets sokkou.";
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
    # 入力ソースの登録は利用者のログインのセッションで行う
    system.activationScripts.postActivation.text = lib.mkAfter ''
      echo "setting up sokkou for ${cfg.user}..." >&2
      launchctl asuser "$(id -u ${lib.escapeShellArg cfg.user})" \
        sudo --user=${lib.escapeShellArg cfg.user} --set-home ${activate}
    '';
  };
}
