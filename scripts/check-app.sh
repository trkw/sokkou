#!/bin/bash
# 組み立てた .app が、組み立てたディレクトリ（.build）に頼らずに綴りの表・語表・辞書を読めるかと、arm64 だけを含むかを確かめる
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
app=$(cd "$1" && pwd)
aside=$(mktemp -d)

mv "$root/.build" "$aside/"
trap 'mv "$aside/.build" "$root/" && rmdir "$aside"' EXIT
"$app/Contents/MacOS/sokkou" --check

for notice in LICENSE THIRD_PARTY_NOTICES.md; do
    [[ -s "$app/Contents/Resources/$notice" ]] || { echo "$notice が入っていない" >&2; exit 1; }
done

installer="$app/Contents/Helpers/sokkou-installer.app"
[[ -s "$installer/Contents/Resources/update.sh" ]] || { echo "インストーラーに update.sh が入っていない" >&2; exit 1; }
codesign --verify --strict "$installer"

for binary in "$app/Contents/MacOS/sokkou" "$installer/Contents/MacOS/sokkou-installer" "$app/Contents/Frameworks/llama.framework/llama"; do
    archs=$(lipo -archs "$binary")
    [[ "$archs" == "arm64" ]] || { echo "対象が arm64 だけではない: $binary $archs" >&2; exit 1; }
    echo "対象 $archs $(basename "$binary")"
done
