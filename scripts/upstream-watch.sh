#!/bin/bash
# 上流の新しいコミットやリリースを issue で知らせる。.github/workflows/upstream-watch.yml が毎日動かす。
# 相手ごとに「上流: <名前>」の issue を 1 つ使い、本文の <!-- seen: … --> に知らせた版を書いておく。
# 同じ版ならそのまま、開いている issue があれば書き直し、閉じていれば（読み終えたら）新しく開く。
# sokkou が追いついたら（固定している revision が最新になったら）開いている issue を閉じる
set -euo pipefail

label=upstream
gh label create "$label" --color C2410C --description "上流の新しい変更" --force >/dev/null

# 名前 版 本文。版が前に知らせたものと同じなら何もしない
notify() {
    local name=$1 version=$2 body=$3
    local title="上流: $name"
    local issue
    issue=$(gh issue list --label "$label" --state all --search "in:title \"$title\"" --json number,state,title,body \
        --jq "map(select(.title == \"$title\")) | sort_by(.number) | last // empty")
    body="$body

<!-- seen: $version -->"
    if [[ -n "$issue" ]]; then
        local number state seen
        number=$(jq -r .number <<<"$issue")
        state=$(jq -r .state <<<"$issue")
        seen=$(jq -r .body <<<"$issue" | sed -n 's/^<!-- seen: \(.*\) -->$/\1/p')
        if [[ "$seen" == "$version" ]]; then
            echo "$name: $version は知らせ済み (#$number)"
            return
        fi
        if [[ "$state" == OPEN ]]; then
            gh issue edit "$number" --body "$body" >/dev/null
            echo "$name: #$number を $version に書き直した"
            return
        fi
    fi
    gh issue create --title "$title" --label "$label" --body "$body"
}

# 名前。sokkou が追いついたら開いている issue を閉じる
caught_up() {
    local name=$1
    local title="上流: $name"
    local number
    number=$(gh issue list --label "$label" --state open --search "in:title \"$title\"" --json number,title \
        --jq "map(select(.title == \"$title\")) | .[0].number // empty")
    if [[ -n "$number" ]]; then
        gh issue close "$number" --comment "sokkou が追いついたので閉じます。" >/dev/null
        echo "$name: 追いついたので #$number を閉じた"
    else
        echo "$name: 最新"
    fi
}

# 2 つの revision の間のコミットの一覧（最初の行だけ、新しい順に最大 30 件）
commits_between() {
    local repo=$1 base=$2 head=$3
    gh api "repos/$repo/compare/$base...$head" \
        --jq '.commits | reverse | .[:30][] | "- [`\(.sha[:7])`](\(.html_url)) \(.commit.message | split("\n")[0])"'
}

# revision で固定している相手。名前 リポジトリ 固定している revision 固定している場所
watch_revision() {
    local name=$1 repo=$2 pinned=$3 where=$4
    local head
    head=$(gh api "repos/$repo/commits/HEAD" --jq .sha)
    if [[ "$head" == "$pinned" ]]; then
        caught_up "$name"
        return
    fi
    local count
    count=$(gh api "repos/$repo/compare/$pinned...$head" --jq .ahead_by)
    notify "$name" "$head" "$where は \`${pinned:0:7}\` で、[$repo](https://github.com/$repo) の main は $count コミット先の \`${head:0:7}\` です。

[差分を見る](https://github.com/$repo/compare/$pinned...$head)

$(commits_between "$repo" "$pinned" "$head")"
}

# リリースを追う相手。プレリリースも含めて一番新しいもの
watch_release() {
    local name=$1 repo=$2
    local release
    release=$(gh api "repos/$repo/releases?per_page=1" --jq '.[0] // empty')
    [[ -n "$release" ]] || { echo "$name: リリースが無い"; return; }
    local tag url published notes
    tag=$(jq -r .tag_name <<<"$release")
    url=$(jq -r .html_url <<<"$release")
    published=$(jq -r '.published_at[:10]' <<<"$release")
    notes=$(jq -r '.body // ""' <<<"$release" | head -c 6000)
    notify "$name" "$tag" "[$tag]($url) が $published に出ました。

$notes"
}

tugime_pinned=$(sed -n 's|.*github.com/miyaoka/tugime", revision: "\([0-9a-f]*\)".*|\1|p' Package.swift)
[[ -n "$tugime_pinned" ]] || { echo "Package.swift に tugime の revision が無い" >&2; exit 1; }
watch_revision tugime miyaoka/tugime "$tugime_pinned" "sokkou の Package.swift"

# azooKey は tugime を通して入るので、tugime が固定している revision と比べる
azookey_pinned=$(gh api "repos/miyaoka/tugime/contents/Package.swift?ref=$tugime_pinned" --jq .content | base64 -d |
    tr -d ' \n' | sed -n 's|.*AzooKeyKanaKanjiConverter",revision:"\([0-9a-f]*\)".*|\1|p')
[[ -n "$azookey_pinned" ]] || { echo "tugime の Package.swift に azooKey の revision が無い" >&2; exit 1; }
watch_revision AzooKeyKanaKanjiConverter azooKey/AzooKeyKanaKanjiConverter "$azookey_pinned" "sokkou が使う tugime（\`${tugime_pinned:0:7}\`）の固定"

watch_release azooKey-Desktop azooKey/azooKey-Desktop
watch_release Meltype yksr-melt/Meltype
