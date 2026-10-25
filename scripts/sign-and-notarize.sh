#!/bin/bash
# dist/sokkou.app を Developer ID で署名して Apple の公証を受け、dmg にまとめて dmg も署名・公証する。
# 公証の印（チケット）は .app と dmg の両方に留める（staple）。ネットにつながっていなくても Gatekeeper が通す。
# CI の sign ジョブが、組み立てたジョブから受け取った .app に対して動かす。鍵の作り方と登録は docs/signing.md
#
# 要る環境変数（GitHub Actions の Secrets）:
#   APPLE_DEVELOPER_ID_P12           Developer ID Application の証明書と秘密鍵（.p12）を base64 にしたもの
#   APPLE_DEVELOPER_ID_P12_PASSWORD  その .p12 のパスワード
#   APPLE_NOTARY_KEY                 App Store Connect API の鍵（AuthKey_XXXX.p8 の中身）
#   APPLE_NOTARY_KEY_ID              その鍵の Key ID
#   APPLE_NOTARY_ISSUER_ID           Issuer ID
# どれかが無ければ ad-hoc 署名のまま dmg を作る（fork からの PR や、鍵を登録する前のリポジトリ）。
# SOKKOU_REQUIRE_SIGNING=1 なら、そのときは失敗にする
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
app="$root/dist/sokkou.app"
dmg="$root/dist/sokkou-macos-arm64.dmg"
test -d "$app" || { echo "$app が無い。先に SOKKOU_BUILD_CHANNEL=stable scripts/build-app.sh を実行する" >&2; exit 1; }

summary() {
    echo "$1"
    [[ -z "${GITHUB_STEP_SUMMARY:-}" ]] || echo "$1" >> "$GITHUB_STEP_SUMMARY"
}

missing=()
for name in APPLE_DEVELOPER_ID_P12 APPLE_DEVELOPER_ID_P12_PASSWORD APPLE_NOTARY_KEY APPLE_NOTARY_KEY_ID APPLE_NOTARY_ISSUER_ID; do
    [[ -n "${!name:-}" ]] || missing+=("$name")
done
if [[ ${#missing[@]} -gt 0 ]]; then
    if [[ "${SOKKOU_REQUIRE_SIGNING:-}" == 1 ]]; then
        echo "署名の鍵が無い: ${missing[*]}（docs/signing.md）" >&2
        exit 1
    fi
    echo "::warning::署名の鍵が無いので、公証を受けずに ad-hoc 署名のまま dmg を作る（無いもの: ${missing[*]}）"
    summary "署名: ad-hoc（公証なし）"
    "$root/scripts/make-dmg.sh"
    exit 0
fi

work=$(mktemp -d)
keychain="$work/signing.keychain-db"
# 一時のキーチェーンは使い終えたら外して消す。セルフホストのランナーでも鍵が残らないように
cleanup() {
    security delete-keychain "$keychain" 2>/dev/null || true
    rm -rf "$work"
}
trap cleanup EXIT

echo "== 鍵を一時のキーチェーンに入れる"
keychain_password=$(uuidgen)
printf '%s' "$APPLE_DEVELOPER_ID_P12" | base64 --decode > "$work/developer-id.p12"
printf '%s\n' "$APPLE_NOTARY_KEY" > "$work/notary.p8"
security create-keychain -p "$keychain_password" "$keychain"
security set-keychain-settings -lut 3600 "$keychain"
security unlock-keychain -p "$keychain_password" "$keychain"
security import "$work/developer-id.p12" -k "$keychain" -f pkcs12 -P "$APPLE_DEVELOPER_ID_P12_PASSWORD" -T /usr/bin/codesign
rm -f "$work/developer-id.p12"
# codesign がパスワードを尋ねずに鍵を使えるようにする
security set-key-partition-list -S apple-tool:,apple: -s -k "$keychain_password" "$keychain" > /dev/null
# codesign が証明書の連なり（Developer ID の中間証明書）をたどれるよう、検索の対象に足す
read -r -a keychains <<< "$(security list-keychains -d user | tr -d '"' | xargs)"
security list-keychains -d user -s "$keychain" "${keychains[@]}"

identity=$(security find-identity -v -p codesigning "$keychain" | awk -F '"' '/Developer ID Application/ { print $2; exit }')
[[ -n "$identity" ]] || { echo ".p12 に Developer ID Application の証明書が無い" >&2; security find-identity -v -p codesigning "$keychain" >&2; exit 1; }
echo "== 署名する人 $identity"

notary=(--key "$work/notary.p8" --key-id "$APPLE_NOTARY_KEY_ID" --issuer "$APPLE_NOTARY_ISSUER_ID")

# 公証に出して、通るまで待つ。通らなければ Apple の記録を出して失敗する
notarize() {
    local file=$1
    echo "== 公証に出す $(basename "$file")"
    local result="$work/notary.json"
    xcrun notarytool submit "$file" "${notary[@]}" --wait --timeout 30m --output-format json > "$result" || true
    cat "$result"
    local id status
    id=$(plutil -extract id raw -o - "$result" 2>/dev/null || true)
    status=$(plutil -extract status raw -o - "$result" 2>/dev/null || true)
    if [[ "$status" != "Accepted" ]]; then
        [[ -z "$id" ]] || xcrun notarytool log "$id" "${notary[@]}" || true
        echo "公証が通らない: $(basename "$file")（${status:-結果なし}）" >&2
        exit 1
    fi
}

# 入力メソッドは hardened runtime で動かす（公証に要る）。JIT やほかの開発元のライブラリは使わないので、緩める権限は付けない。
# 中のフレームワークから順に署名する。--deep は使わない（Apple が勧めない）
echo "== 署名 sokkou.app"
sign=(codesign --force --timestamp --options runtime --keychain "$keychain" --sign "$identity")
"${sign[@]}" "$app/Contents/Frameworks/llama.framework"
"${sign[@]}" "$app"
codesign --verify --deep --strict --verbose=2 "$app"

ditto -c -k --keepParent "$app" "$work/sokkou.zip"
notarize "$work/sokkou.zip"
xcrun stapler staple "$app"
xcrun stapler validate "$app"

"$root/scripts/make-dmg.sh"

echo "== 署名 $(basename "$dmg")"
codesign --force --timestamp --keychain "$keychain" --sign "$identity" "$dmg"
notarize "$dmg"
xcrun stapler staple "$dmg"
xcrun stapler validate "$dmg"

# dmg に入れた .app の署名が崩れていないか（Finder の情報などが付くと install.sh の確認で落ちる）
mkdir "$work/mount"
hdiutil attach -quiet -nobrowse -readonly -noautoopen -mountpoint "$work/mount" "$dmg"
codesign --verify --deep --strict --verbose=2 "$work/mount/sokkou.app"
hdiutil detach -quiet "$work/mount"

# Gatekeeper が利用者の Mac と同じように判断して通すか
spctl --assess --type execute --verbose=4 "$app"
spctl --assess --type open --context context:primary-signature --verbose=4 "$dmg"

team=$(codesign -dv "$app" 2>&1 | awk -F= '/^TeamIdentifier=/ { print $2 }')
summary "署名: $identity（Team ID ${team}）、公証済み・ステープル済み"
