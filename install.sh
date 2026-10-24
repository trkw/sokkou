#!/bin/bash
# sokkou を ~/Library/Input Methods に置いて入力ソースとして登録する。有効化はしない。
#
# 使い方:
#   curl -fsSL https://raw.githubusercontent.com/trkw/sokkou/main/install.sh | bash   # 最新のリリースの dmg から入れる
#   bash install.sh "dist/sokkou Dev.app"                                            # 手元で組み立てたものを入れる
set -euo pipefail

repo="trkw/sokkou"
asset="sokkou-macos-arm64.dmg"

if [[ "$(uname -s)" != "Darwin" || "$(uname -m)" != "arm64" ]]; then
    echo "sokkou は Apple シリコンの macOS 専用" >&2
    exit 1
fi

if [[ $# -ge 1 ]]; then
    src="$1"
else
    work="$(mktemp -d)"
    mount="$work/mount"
    trap 'hdiutil detach -quiet "$mount" 2>/dev/null || true; rm -rf "$work"' EXIT
    url="https://github.com/$repo/releases/latest/download/$asset"
    echo "== 取得 $url"
    curl -fsSL -o "$work/$asset" "$url"
    mkdir -p "$mount"
    hdiutil attach -quiet -nobrowse -readonly -mountpoint "$mount" "$work/$asset"
    src="$mount/sokkou.app"
fi
[[ -d "$src/Contents" ]] || { echo "$src は .app ではない" >&2; exit 1; }
# 入れる処理は sokkou 自身が持つ（dmg から開いたときと同じ）
"$src/Contents/MacOS/sokkou" --install
echo "初めて入れたときは、ログインし直してから、システム設定 → キーボード → 入力ソース → 編集 → 「+」→ 日本語 → sokkou (日本語) で追加する"
