#!/bin/bash
# sokkou を ~/Library/Input Methods に置いて入力ソースとして登録する。有効化はしない。
# 動いている版があれば止めて、入れた版をすぐ起動する（ログインし直すのは初めて入れたときだけ）
#
# 使い方:
#   curl -fsSL https://raw.githubusercontent.com/trkw/sokkou/main/install.sh | bash              # 最新のリリースを入れる
#   curl -fsSL https://raw.githubusercontent.com/trkw/sokkou/main/install.sh | bash -s -- --pr 4  # PR #4 の CI のビルドを入れる
#   bash install.sh "dist/sokkou Dev.app"                                                        # 手元で組み立てたものを入れる
#
# 入力メニューの「最新版に更新」「PR の版を入れる…」も、.app に入れたこのスクリプトを --notify 付きで動かす
set -euo pipefail

repo="trkw/sokkou"
asset="sokkou-macos-arm64.dmg"
notify=false
tag=""
src=""
work=""
# 入れ替えたあとに起動した新しい版が読み、どの版になったかを知らせる（Updater.reportUpdate）
note="$HOME/Library/Application Support/sokkou/updated.txt"

args=("$@")
while [[ $# -gt 0 ]]; do
    case "$1" in
        --pr)
            [[ "${2:-}" =~ ^[0-9]+$ ]] || { echo "--pr には PR の番号を渡す" >&2; exit 1; }
            tag="pr-$2"
            shift 2
            ;;
        --notify)
            notify=true
            shift
            ;;
        *)
            src="$1"
            shift
            ;;
    esac
done

# 入力メニューから動かしたときは、sokkou と別のプロセスグループで動かす。
# 入れ替えで sokkou が止められたときに、launchd がプロセスグループごと止めて途中で終わらないように。
# 外側は待って終わりの状態を返すので、sokkou は失敗を知らせられる
if $notify && [[ -z "${SOKKOU_DETACHED:-}" ]]; then
    set -m
    SOKKOU_DETACHED=1 /bin/bash "$0" "${args[@]}" </dev/null &
    wait "$!"
    exit $?
fi

# 入力メニューから動かしたときは端末が無いので、結果を通知でも出す
say() {
    echo "$1"
    if $notify; then
        osascript -e "display notification \"$1\" with title \"sokkou\"" >/dev/null 2>&1 || true
    fi
}

finish() {
    local status=$?
    if [[ -n "$work" ]]; then
        hdiutil detach -quiet "$work/mount" 2>/dev/null || true
        rm -rf "$work"
    fi
    if [[ $status -ne 0 ]]; then
        rm -f "$note"
    fi
    if [[ $status -ne 0 ]] && $notify; then
        say "入れられなかった。~/Library/Logs/sokkou-update.log を見る"
    fi
}
trap finish EXIT

if [[ "$(uname -s)" != "Darwin" || "$(uname -m)" != "arm64" ]]; then
    echo "sokkou は Apple シリコンの macOS 専用" >&2
    exit 1
fi

if [[ -z "$src" ]]; then
    work="$(mktemp -d)"
    if [[ -n "$tag" ]]; then
        # PR のビルドは CI が pr-<番号> のプレリリースに置く（ci.yml の pr-build）
        url="https://github.com/$repo/releases/download/$tag/$asset"
    else
        url="https://github.com/$repo/releases/latest/download/$asset"
    fi
    echo "== 取得 $url"
    if ! curl -fsSL -o "$work/$asset" "$url"; then
        [[ -z "$tag" ]] || say "PR #${tag#pr-} のビルドがまだ無い。PR の CI（app と pr-build）が終わるまで数分待ってからもう一度。fork からの PR は置かれない"
        exit 1
    fi
    mkdir -p "$work/mount"
    hdiutil attach -quiet -nobrowse -readonly -mountpoint "$work/mount" "$work/$asset"
    src="$work/mount/sokkou.app"
fi
[[ -d "$src/Contents" ]] || { echo "$src は .app ではない" >&2; exit 1; }
plist="$src/Contents/Info.plist"
name=$(/usr/libexec/PlistBuddy -c "Print :CFBundleName" "$plist")
build=$(/usr/libexec/PlistBuddy -c "Print :SokkouBuild" "$plist" 2>/dev/null || /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$plist")
mkdir -p "$(dirname "$note")"
echo "$name を $build にしました" > "$note"
# 入れる処理は sokkou 自身が持つ（dmg から開いたときと同じ）。動いている版を止め、入れた版を起動し直す
"$src/Contents/MacOS/sokkou" --install
say "$name を $build にした"
$notify || echo "初めて入れたときは、ログインし直してから、システム設定 → キーボード → 入力ソース → 編集 → 「+」→ 日本語 → $name (日本語) で追加する"
