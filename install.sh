#!/bin/bash
# 組み立てた .app を ~/Library/Input Methods に置いて入力ソースとして登録する。有効化はしない。
# 使い方: scripts/build-app.sh && bash install.sh ["dist/sokkou Dev.app"]
set -euo pipefail

lsregister="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
root=$(cd "$(dirname "$0")" && pwd)
src=${1:-"$root/dist/sokkou Dev.app"}
[[ -d "$src/Contents" ]] || { echo "$src は .app ではない。先に scripts/build-app.sh を実行する" >&2; exit 1; }
src=$(CDPATH='' cd -- "$src" && pwd -P)
app_dir=${src##*/}
dest="$HOME/Library/Input Methods/$app_dir"
exe="$dest/Contents/MacOS/sokkou"

# バンドルを消さずに中身を上書きする。バンドルが無い瞬間に macOS が入力ソースの一覧を作り直すと登録が消えるため
mkdir -p "$dest"
rsync -a --delete "$src/" "$dest/"
"$lsregister" -f "$dest"
"$exe" --register
# 動いている古い版を止める。次に入力ソースが選ばれたときに新しい版が起動する
found=$(ps -axo pid=,comm= | exe="$exe" awk '{ pid = $1; sub(/^ *[0-9]+ /, ""); if ($0 == ENVIRON["exe"]) printf "%s ", pid }')
read -r -a pids <<< "$found"
(( ${#pids[@]} == 0 )) || kill "${pids[@]}"
echo "== 配置 $dest"
echo "初めて入れたときは、ログインし直してから、システム設定 → キーボード → 入力ソース → 「+」→ 日本語 → ${app_dir%.app} (日本語) で追加する"
