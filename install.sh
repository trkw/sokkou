#!/bin/bash
# sokkou を ~/Library/Input Methods に置いて入力ソースとして登録し、有効にする。
# 動いている版があれば止めて、入れた版をすぐ起動する。ログインし直さなくてよい。
#
# 使い方:
#   curl -fsSL https://raw.githubusercontent.com/trkw/sokkou/main/install.sh | bash              # 最新のリリースを入れる
#   curl -fsSL https://raw.githubusercontent.com/trkw/sokkou/main/install.sh | bash -s -- --pr 4  # PR #4 の CI のビルドを入れる
#   bash install.sh "dist/sokkou Dev.app"                                                        # 手元で組み立てたものを入れる
#
# 入力メニューの「最新版に更新」「PR の版を入れる…」と自動の更新も、.app に入れたこのスクリプトを --notify 付きで動かす。
#
# 取ってきた dmg は、GitHub がリリースの資産ごとに出す SHA-256 と突き合わせ、中の .app が sokkou の Developer ID で署名されていることとバンドル ID を確かめ、
# その .app が辞書を読んで変換できるか（--check）を試してから入れる。入れ替えでしくじったら sokkou が前の版に戻す
set -euo pipefail

repo="trkw/sokkou"
asset="sokkou-macos-arm64.dmg"
bundle_id="io.github.trkw.inputmethod.sokkou"
# 配る dmg の sokkou は trkw の Developer ID で署名して公証を受けている（docs/signing.md）
team_id="BCA6Z83Q5N"
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

log() {
    echo "$(date '+%F %T') $1"
}

# 入力メニューから動かしたときは端末が無いので、結果を通知でも出す。通知は許可が無いと出ないので、窓は sokkou が出す
say() {
    log "$1"
    if $notify; then
        osascript -e "display notification \"$1\" with title \"sokkou\"" >/dev/null 2>&1 || true
    fi
}

# 失敗の理由は最後の行に書く。sokkou はログの最後の行を窓に出す
fail() {
    log "失敗: $1"
    exit 1
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
}
trap finish EXIT

if [[ "$(uname -s)" != "Darwin" || "$(uname -m)" != "arm64" ]]; then
    fail "sokkou は Apple シリコンの macOS 専用"
fi

# JSON から 1 つの値を取る。macOS に最初からある plutil は JSON も読める
json_value() {
    plutil -extract "$2" raw -o - "$1" 2>/dev/null || true
}

if [[ -z "$src" ]]; then
    work="$(mktemp -d)"
    if [[ -n "$tag" ]]; then
        # PR のビルドは CI が pr-<番号> のプレリリースに置く（ci.yml の pr-build）
        api="https://api.github.com/repos/$repo/releases/tags/$tag"
        log "== PR #${tag#pr-} のビルドを入れる"
    else
        api="https://api.github.com/repos/$repo/releases/latest"
        log "== 最新のリリースを入れる"
    fi
    # 資産の URL と SHA-256 を同じ答えから取る。latest の付け替えと取得の間でずれないように。
    # GITHUB_TOKEN があれば使う（CI のように多くの人と同じ IP から引くと、認証なしの API は 403 になる）
    auth=()
    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
        auth=(-H "Authorization: Bearer $GITHUB_TOKEN")
    fi
    url=""
    digest=""
    if curl -fsSL --retry 2 -H "Accept: application/vnd.github+json" ${auth[@]+"${auth[@]}"} -o "$work/release.json" "$api"; then
        release=$(json_value "$work/release.json" "tag_name")
        for i in $(seq 0 20); do
            name=$(json_value "$work/release.json" "assets.$i.name")
            [[ -n "$name" ]] || break
            if [[ "$name" == "$asset" ]]; then
                url=$(json_value "$work/release.json" "assets.$i.browser_download_url")
                digest=$(json_value "$work/release.json" "assets.$i.digest")
                break
            fi
        done
        [[ -n "$url" ]] || fail "$release に $asset が無い"
    else
        # API の上限に当たっても入れられるよう、資産を直接取る。このときは SHA-256 を突き合わせられない
        log "== リリースの情報を API から取れないので、dmg を直接取る（SHA-256 は突き合わせない）"
        if [[ -n "$tag" ]]; then
            url="https://github.com/$repo/releases/download/$tag/$asset"
        else
            url="https://github.com/$repo/releases/latest/download/$asset"
        fi
    fi
    log "== 取得 $url"
    if ! curl -fsSL --retry 3 -o "$work/$asset" "$url"; then
        if [[ -n "$tag" ]]; then
            fail "PR #${tag#pr-} のビルドがまだ無い。PR の CI（app と pr-build）が終わるまで数分待ってからもう一度。マージした PR、閉じた PR、fork からの PR のビルドは無い"
        fi
        fail "dmg を取れない: $url"
    fi
    actual="sha256:$(shasum -a 256 "$work/$asset" | cut -d ' ' -f 1)"
    if [[ -n "$digest" ]]; then
        [[ "$actual" == "$digest" ]] || fail "dmg の SHA-256 が合わない（取得 ${actual}、GitHub ${digest}）"
        log "== SHA-256 一致 $actual"
    else
        log "== SHA-256 を突き合わせずに進める（${actual}）"
    fi
    mkdir -p "$work/mount"
    hdiutil attach -quiet -nobrowse -readonly -noautoopen -mountpoint "$work/mount" "$work/$asset" || fail "dmg を開けない"
    src="$work/mount/sokkou.app"
fi
[[ -d "$src/Contents" ]] || fail "$src は .app ではない"
plist="$src/Contents/Info.plist"
name=$(/usr/libexec/PlistBuddy -c "Print :CFBundleName" "$plist")
id=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$plist")
build=$(/usr/libexec/PlistBuddy -c "Print :SokkouBuild" "$plist" 2>/dev/null || /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$plist")
# 取ってきたものは普段使いの sokkou に限る。手元で組み立てた開発版（.dev）は引数で渡したときだけ入れる
if [[ -n "$work" && "$id" != "$bundle_id" ]]; then
    fail "dmg の中身が sokkou ではない（${id}）"
fi
if [[ -n "$work" ]]; then
    # 取ってきたものは、Apple が発行した sokkou の Developer ID（Team ID ${team_id}）の署名に限る。
    # ad-hoc 署名のビルド（fork からの PR、署名の鍵を入れていないリポジトリ）はここで止まる
    codesign --verify --strict -R="anchor apple generic and certificate leaf[subject.OU] = \"${team_id}\"" "$src" \
        || fail "${name} の署名が sokkou の Developer ID（${team_id}）のものではないか、壊れている"
else
    codesign --verify --strict "$src" || fail "${name} の署名が壊れている"
fi
# 辞書と語表を読んで 1 文を変換できるかを、入れ替える前に試す。読めない版を入れて打てなくならないように
"$src/Contents/MacOS/sokkou" --check >/dev/null || fail "$build が変換を試せない（辞書を読めない）"
log "== 確かめた $name $build"

mkdir -p "$(dirname "$note")"
echo "$name を $build にしました" > "$note"
# 入れる処理は sokkou 自身が持つ（dmg から開いたときと同じ）。今の版を取っておき、動いている版を止めて入れ替え、起動し直す。
# 入れ替えや起動でしくじったら、sokkou が取っておいた版に戻して失敗を返す
"$src/Contents/MacOS/sokkou" --install || fail "入れ替えられなかった。前の版のまま"
say "$name を $build にしました"
$notify || echo "メニューバーの入力メニューから $name を選ぶと使える"
