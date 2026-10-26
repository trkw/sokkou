#!/bin/bash
# .app を dist/ に組み立てて ad-hoc で署名する。
# 無指定は開発版にする。手元で組み立てたものが普段使いの版と同じ bundle id を名乗り、上書きしないようにするため
set -euo pipefail

bundle_id=io.github.trkw.inputmethod.sokkou
name=sokkou
case "${SOKKOU_BUILD_CHANNEL:-}" in
    stable) ;;
    "")
        bundle_id="$bundle_id.dev"
        name="sokkou Dev"
        ;;
    *)
        echo "SOKKOU_BUILD_CHANNEL は stable か無指定: $SOKKOU_BUILD_CHANNEL" >&2
        exit 1
        ;;
esac
version=${SOKKOU_VERSION:-0.0.0}
root=$(cd "$(dirname "$0")/.." && pwd)
# 入力メニューに出す、どのビルドかの印。CI はリリースの版か PR の番号と、元にしたコミットを渡す
commit=${SOKKOU_COMMIT:-$(git -C "$root" rev-parse HEAD 2>/dev/null || echo unknown)}
build_label="${SOKKOU_BUILD_LABEL:-手元} · ${commit:0:7}"
app="$root/dist/$name.app"

# native のビルドの仕組みはリソースを .app の Contents/Resources から探さないので、swiftbuild に固定する。
# 対象は Apple Silicon だけなので arm64 だけを組み立てる
build=(swift build --package-path "$root" -c release --build-system swiftbuild --arch arm64)

echo "== swift build"
"${build[@]}" --product sokkou
"${build[@]}" --product sokkou-installer
"${build[@]}" --product sokkou-launcher
bin=$("${build[@]}" --show-bin-path)

echo "== 組み立て $app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$app/Contents/Frameworks"
cp "$bin/sokkou" "$app/Contents/MacOS/sokkou"
# Zenzai は既定で使わないが、azooKey の Zenzai が llama.cpp をリンクするので、実行ファイルは @rpath/llama.framework を探す
cp -R "$bin/llama.framework" "$app/Contents/Frameworks/"
llama=$(readlink -f "$app/Contents/Frameworks/llama.framework/llama")
if [[ "$(lipo -archs "$llama")" != "arm64" ]]; then
    lipo -thin arm64 "$llama" -output "$llama"
fi
install_name_tool -add_rpath @executable_path/../Frameworks "$app/Contents/MacOS/sokkou"
# 綴りの表・語表・azooKey の辞書
for bundle in "$bin"/*.bundle; do
    cp -R "$bundle" "$app/Contents/Resources/"
done
sed -e "s/__BUNDLE_ID__/$bundle_id/g" -e "s/__VERSION__/$version/g" -e "s/__NAME__/$name/g" -e "s|__BUILD__|$build_label|g" "$root/App/Info.plist" > "$app/Contents/Info.plist"
plutil -lint "$app/Contents/Info.plist"
for lproj in en.lproj ja.lproj; do
    mkdir -p "$app/Contents/Resources/$lproj"
    sed -e "s/__NAME__/$name/g" "$root/App/$lproj/InfoPlist.strings" > "$app/Contents/Resources/$lproj/InfoPlist.strings"
    plutil -lint "$app/Contents/Resources/$lproj/InfoPlist.strings"
done
# 入れる・更新する・取り除くを受け持つ別のアプリ。sokkou 本体は自分の外に書かない
installer="$app/Contents/Helpers/sokkou-installer.app"
mkdir -p "$installer/Contents/MacOS" "$installer/Contents/Resources"
cp "$bin/sokkou-installer" "$installer/Contents/MacOS/sokkou-installer"
sed -e "s/__BUNDLE_ID__/$bundle_id/g" -e "s/__VERSION__/$version/g" -e "s/__NAME__/$name/g" "$root/App/Installer-Info.plist" > "$installer/Contents/Info.plist"
plutil -lint "$installer/Contents/Info.plist"
# サンドボックスの中の sokkou に頼まれてインストーラーを起こす XPC サービス
launcher="$app/Contents/XPCServices/$bundle_id.launcher.xpc"
mkdir -p "$launcher/Contents/MacOS"
cp "$bin/sokkou-launcher" "$launcher/Contents/MacOS/sokkou-launcher"
sed -e "s/__BUNDLE_ID__/$bundle_id/g" -e "s/__VERSION__/$version/g" "$root/App/Launcher-Info.plist" > "$launcher/Contents/Info.plist"
plutil -lint "$launcher/Contents/Info.plist"
# 入力メニューの「最新版に更新」と自動の更新が、インストーラーを通して動かす
cp "$root/install.sh" "$installer/Contents/Resources/update.sh"
# App Sandbox に入れた版を初めて起動したとき、これまでの辞書・覚えた候補・設定を入れ物に写す
cp "$root/App/container-migration.plist" "$app/Contents/Resources/"
plutil -lint "$app/Contents/Resources/container-migration.plist"
# 配るときにライセンスと第三者の表示を一緒に渡す
cp "$root/LICENSE" "$root/THIRD_PARTY_NOTICES.md" "$app/Contents/Resources/"
swift "$root/scripts/make-icons.swift" "$app/Contents/Resources"
swift "$root/scripts/make-app-icon.swift" "$app/Contents/Resources"
cp "$app/Contents/Resources/AppIcon.icns" "$installer/Contents/Resources/"

echo "== ad-hoc 署名"
# 中のものから順に署名する。本体は App Sandbox に入れ、権限は App/sokkou.entitlements のものだけにする。
# インストーラーは入れ物の外（~/Library/Input Methods）に書き、XPC サービスはそれを起こすので、どちらもサンドボックスに入れない
entitlements=$(mktemp)
trap 'rm -f "$entitlements"' EXIT
sed -e "s/__BUNDLE_ID__/$bundle_id/g" "$root/App/sokkou.entitlements" > "$entitlements"
plutil -lint "$entitlements"
codesign --force --timestamp=none --sign - "$app/Contents/Frameworks/llama.framework"
codesign --force --timestamp=none --sign - "$installer"
codesign --force --timestamp=none --sign - "$launcher"
codesign --force --timestamp=none --sign - --entitlements "$entitlements" "$app"
codesign --verify --strict "$app"
echo "== 完了 $app"
