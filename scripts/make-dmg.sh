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

background="$stage/background.tiff"
swift "$root/scripts/make-dmg-background.swift" "$background"

rm -f "$dmg"
"$venv/bin/dmgbuild" -s "$root/scripts/dmg-settings.py" \
    -D app="$app" -D background="$background" \
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
# 窓に出るのは sokkou だけ。ほかの隠しファイルは dmg-settings.py で窓の外に置いている。
# 置き場所を決めていないものが増えたら、隠しファイルを表示している Finder で sokkou に重なるので止める
unexpected=$(cd "$mount" && find . -mindepth 1 -maxdepth 1 ! -name sokkou.app \
    ! -name .background.tiff ! -name .VolumeIcon.icns ! -name .fseventsd ! -name .Trashes ! -name .DS_Store)
hdiutil detach -quiet "$mount"
if [[ -n "$unexpected" ]]; then
    echo "dmg に置き場所を決めていないものがある（scripts/dmg-settings.py の icon_locations に足す）:" >&2
    echo "$unexpected" >&2
    exit 1
fi
echo "== 作成 $dmg"
