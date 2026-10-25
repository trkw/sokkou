# GitHub のリリースの dmg をそのまま使う。Swift の組み立てに Xcode が要るので、Nix では組み立てない。
# 版と sha256 は release.yml がリリースのたびに nix/release.json に書く
{
  lib,
  stdenvNoCC,
  fetchurl,
  undmg,
}:

let
  release = lib.importJSON ./release.json;
in
stdenvNoCC.mkDerivation {
  pname = "sokkou";
  inherit (release) version;

  src = fetchurl {
    url = "https://github.com/trkw/sokkou/releases/download/v${release.version}/sokkou-macos-arm64.dmg";
    inherit (release) sha256;
  };

  nativeBuildInputs = [ undmg ];
  sourceRoot = ".";
  dontPatch = true;
  dontConfigure = true;
  dontBuild = true;
  dontFixup = true;

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/Library/Input Methods"
    cp -R sokkou.app "$out/Library/Input Methods/"
    runHook postInstall
  '';

  passthru = {
    # 入れたあとに入力ソースとして登録するには、この .app の --install を利用者として動かす（モジュールがする）
    app = "Library/Input Methods/sokkou.app";
    bundleId = "io.github.trkw.inputmethod.sokkou";
  };

  meta = {
    description = "SKK-flavoured Japanese input method for macOS that converts as you type";
    homepage = "https://github.com/trkw/sokkou";
    # 外来語と英単語の表は JMdict・wordfreq 由来で CC BY-SA 4.0（THIRD_PARTY_NOTICES.md）
    license = with lib.licenses; [
      mit
      cc-by-sa-40
    ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "aarch64-darwin" ];
  };
}
