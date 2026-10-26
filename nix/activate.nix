# 利用者として動かす、sokkou を ~/Library/Input Methods に入れて登録するスクリプト。
# 入れる処理は sokkou に入れたインストーラーの --install（dmg から開いたときと同じ）に任せる。
# 動いている版を止めて入れ替えるので、版が変わったときだけ動かす
{
  lib,
  writeShellScript,
  coreutils,
  package,
  autoUpdate,
}:

writeShellScript "sokkou-activate" ''
  set -eu
  app=${lib.escapeShellArg "${package}/${package.passthru.app}"}
  installed="$HOME/Library/Input Methods/sokkou.app"
  want=${lib.escapeShellArg package.version}
  have=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$installed/Contents/Info.plist" 2>/dev/null || true)

  # 自動更新を決める。App Sandbox に入れた版は、入れ物の外の設定は <bundle id>.managed だけを読む（入力メニューの設定より先に使う）。
  # それより前の版は <bundle id> を読むので、両方に書く
  /usr/bin/defaults write ${package.passthru.bundleId}.managed autoUpdates -bool ${lib.boolToString autoUpdate}
  /usr/bin/defaults write ${package.passthru.bundleId} autoUpdates -bool ${lib.boolToString autoUpdate}

  install=0
  if [ -z "$have" ]; then
    install=1
  elif [ "$have" != "$want" ]; then
    if ${lib.boolToString autoUpdate}; then
      # 自動更新が先に新しい版を入れていたら、古い版に戻さない
      newest=$(printf '%s\n%s\n' "$have" "$want" | ${coreutils}/bin/sort -V | ${coreutils}/bin/tail -n 1)
      [ "$newest" != "$want" ] || install=1
    else
      install=1
    fi
  fi

  if [ "$install" = 1 ]; then
    echo "sokkou: ''${have:-なし} -> $want"
    # インストーラーを持つ版はそれで入れる（sokkou 本体は App Sandbox の中で ~/Library/Input Methods に書けない）
    installer="$app/Contents/Helpers/sokkou-installer.app/Contents/MacOS/sokkou-installer"
    if [ -x "$installer" ]; then
      "$installer" --install
    else
      "$app/Contents/MacOS/sokkou" --install
    fi
    # ストアの読み取り専用の属性が写るので、自動更新が入れ替えられるようにする（0.1.21 までの --install はしない）
    /bin/chmod -R u+w "$installed"
    [ -n "$have" ] || echo "sokkou: 入力ソースに「sokkou (日本語)」と「sokkou (英数)」を足した。一覧に出ないときはログインし直す"
  fi
''
