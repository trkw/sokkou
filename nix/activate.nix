# 利用者として動かす、sokkou を ~/Library/Input Methods に入れて登録するスクリプト。
# 入れる処理は sokkou 自身の --install（dmg から開いたときと同じ）に任せる。
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
  # ファイルが無いと PlistBuddy は「File Doesn't Exist, Will Create: …」を標準出力に出すので、先に存在を確かめる
  have=""
  if [ -f "$installed/Contents/Info.plist" ]; then
    have=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$installed/Contents/Info.plist" 2>/dev/null || true)
  fi

  # 自動更新を入力メニューの設定と同じ値で決める
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
    "$app/Contents/MacOS/sokkou" --install
    # ストアの読み取り専用の属性が写るので、自動更新が入れ替えられるようにする（0.1.21 までの --install はしない）
    /bin/chmod -R u+w "$installed"
    [ -n "$have" ] || echo "sokkou: 入力ソースに「sokkou (日本語)」と「sokkou (英数)」を足した。一覧に出ないときはログインし直す"
  fi
''
