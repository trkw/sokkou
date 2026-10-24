#!/bin/bash
# dist/sokkou.app を配布用の dmg にまとめる。先に SOKKOU_BUILD_CHANNEL=stable scripts/build-app.sh を実行する。
# dmg の中の sokkou を開くと、sokkou が自分を ~/Library/Input Methods に入れて登録する
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
dist="$root/dist"
app="$dist/sokkou.app"
dmg="$dist/sokkou-macos-arm64.dmg"

test -d "$app" || { echo "$app が無い。先に SOKKOU_BUILD_CHANNEL=stable scripts/build-app.sh を実行する" >&2; exit 1; }
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
ditto "$app" "$stage/sokkou.app"
cat > "$stage/はじめに.txt" <<'TEXT'
sokkou の入れ方

1. sokkou を右クリックして「開く」を選ぶ
   （「開発元を確認できない」と出たら、システム設定 → プライバシーとセキュリティ の下にある「このまま開く」を押す）
2. 「sokkou を入れました」と出たら、いったんログアウトしてログインし直す
3. システム設定 → キーボード → 入力ソース → 編集 → 「+」→ 日本語 → 「sokkou」を追加する

新しい版は、同じように開くだけで入れ替わる。
TEXT
rm -f "$dmg"
hdiutil create -volname "sokkou" -srcfolder "$stage" -fs HFS+ -format UDZO -ov "$dmg"
echo "== 作成 $dmg"
