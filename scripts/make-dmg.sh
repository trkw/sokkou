#!/bin/bash
# dist/sokkou.app を配布用の dmg にまとめる。先に SOKKOU_BUILD_CHANNEL=stable scripts/build-app.sh を実行する。
# dmg の中の sokkou を開くと、sokkou が自分を ~/Library/Input Methods に入れて登録し、入力ソースに足す。
# 窓の背景と配置は dmgbuild で書く（Finder を動かさないので CI でも同じ見た目になる）
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
dist="$root/dist"
app="$dist/sokkou.app"
dmg="$dist/sokkou-macos-arm64.dmg"

test -d "$app" || { echo "$app が無い。先に SOKKOU_BUILD_CHANNEL=stable scripts/build-app.sh を実行する" >&2; exit 1; }
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT

# dmgbuild は組み立てのたびに入れ直さないよう .build に置く
venv="$root/.build/dmgbuild"
if [[ ! -x "$venv/bin/dmgbuild" ]]; then
    echo "== dmgbuild を入れる"
    python3 -m venv "$venv"
    "$venv/bin/pip" install --quiet --disable-pip-version-check "dmgbuild==1.6.7"
fi

guide="$stage/はじめに.txt"
cat > "$guide" <<'TEXT'
sokkou の入れ方
==============

1. この窓の sokkou をダブルクリックする
2. 「sokkou を入れました」と出たら「sokkou に切り替える」を押す。これで使える
   （入力ソースに「sokkou (日本語)」と「sokkou (英数)」が足される）
   （入力ソースの一覧に出ないときだけ、いったんログアウトしてログインし直す）

新しい版が出ると、打っていないときに自動で入れ替わる。入力メニュー（メニューバーの「そ」）から
「最新版に更新」で今すぐ入れることも、「新しいリリースを自動で入れる」で止めることもできる。


ターミナルから入れるなら:

    curl -fsSL https://raw.githubusercontent.com/trkw/sokkou/main/install.sh | bash


取り除き方
----------

入力メニューの「sokkou を取り除く…」を選ぶ。ターミナルからなら:

    ~/Library/Input\ Methods/sokkou.app/Contents/MacOS/sokkou --uninstall          # 覚えた候補は残す
    ~/Library/Input\ Methods/sokkou.app/Contents/MacOS/sokkou --uninstall --purge  # 覚えた候補と設定も消す


うまく動かないとき
------------------

- 入力メニューに、いま動いているビルド（v0.1.7 · abc1234 など）が出る
- 更新の記録は ~/Library/Logs/sokkou-update.log にある
- 更新のあとに困ったら、入力メニューの「前の版に戻す」で 1 つ前の版に戻せる

https://github.com/trkw/sokkou
TEXT

background="$stage/background.tiff"
swift "$root/scripts/make-dmg-background.swift" "$background"

rm -f "$dmg"
"$venv/bin/dmgbuild" -s "$root/scripts/dmg-settings.py" \
    -D app="$app" -D guide="$guide" -D background="$background" \
    "sokkou" "$dmg"
hdiutil verify "$dmg"
# 更新（install.sh）と同じ確かめ方で、dmg の中の app の署名が通るかを見る。通らない dmg はリリースしない
mount="$stage/mount"
mkdir -p "$mount"
hdiutil attach -quiet -nobrowse -readonly -noautoopen -mountpoint "$mount" "$dmg"
if ! codesign --verify --strict "$mount/sokkou.app"; then
    hdiutil detach -quiet "$mount" || true
    echo "dmg の中の sokkou.app が codesign --verify --strict を通らない" >&2
    exit 1
fi
# 窓に出るのは sokkou と「はじめに」だけ。ほかの隠しファイルは dmg-settings.py で窓の外に置いている。
# 置き場所を決めていないものが増えたら、隠しファイルを表示している Finder で sokkou に重なるので止める。
# 「はじめに」は *.txt で見る（HFS+ は濁点を分けて持つので、名前をそのまま比べると合わない）
unexpected=$(cd "$mount" && find . -mindepth 1 -maxdepth 1 ! -name sokkou.app ! -name '*.txt' \
    ! -name .background.tiff ! -name .VolumeIcon.icns ! -name .fseventsd ! -name .Trashes ! -name .DS_Store)
hdiutil detach -quiet "$mount"
if [[ -n "$unexpected" ]]; then
    echo "dmg に置き場所を決めていないものがある（scripts/dmg-settings.py の icon_locations に足す）:" >&2
    echo "$unexpected" >&2
    exit 1
fi
echo "== 作成 $dmg"
