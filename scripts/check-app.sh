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

# 本体は App Sandbox で動き、権限は App/sokkou.entitlements のものだけ。ほかの権限が付いていたら止める
id=$(plutil -extract CFBundleIdentifier raw "$app/Contents/Info.plist")
expected=$(sed -e "s/__BUNDLE_ID__/$id/g" "$root/App/sokkou.entitlements" | plutil -convert json -o - - | jq -cS .)
actual=$(codesign -d --entitlements - --xml "$app" 2>/dev/null | plutil -convert json -o - - | jq -cS .)
[[ "$actual" == "$expected" ]] || { echo "本体の entitlements が想定と違う: $actual" >&2; exit 1; }
echo "entitlements $actual"

installer="$app/Contents/Helpers/sokkou-installer.app"
[[ -s "$installer/Contents/Resources/update.sh" ]] || { echo "インストーラーに update.sh が入っていない" >&2; exit 1; }
codesign --verify --strict "$installer"
# インストーラーは ~/Library/Input Methods に書くのでサンドボックスに入れない。権限は何も付けない
installer_entitlements=$(codesign -d --entitlements - --xml "$installer" 2>/dev/null || true)
[[ -z "$installer_entitlements" ]] || { echo "インストーラーに entitlements が付いている: $installer_entitlements" >&2; exit 1; }

launcher="$app/Contents/XPCServices/$id.launcher.xpc"
codesign --verify --strict "$launcher"
# XPC サービスもインストーラーを起こすのでサンドボックスに入れない。権限は何も付けない
launcher_entitlements=$(codesign -d --entitlements - --xml "$launcher" 2>/dev/null || true)
[[ -z "$launcher_entitlements" ]] || { echo "XPC サービスに entitlements が付いている: $launcher_entitlements" >&2; exit 1; }

for binary in "$app/Contents/MacOS/sokkou" "$installer/Contents/MacOS/sokkou-installer" "$launcher/Contents/MacOS/sokkou-launcher" "$app/Contents/Frameworks/llama.framework/llama"; do
    archs=$(lipo -archs "$binary")
    [[ "$archs" == "arm64" ]] || { echo "対象が arm64 だけではない: $binary $archs" >&2; exit 1; }
    echo "対象 $archs $(basename "$binary")"
done
