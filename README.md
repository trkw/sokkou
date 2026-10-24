# sokkou（即効）

SKK の手触りで、打てばそのまま変換される、自分用の macOS 日本語入力。

- 普段は Shift を押さずにローマ字を打つだけで、日本語と英語を判定して自動で変換する（meltype、tugime の流れ）
- ローマ字は訓令式もヘボン式も読む（zi shi chi tsu fu sha cha jya zya）。綴りの表は `Sources/SokkouEngine/Resources/romaji.tsv`
- モードは Ctrl で切り替える。`C-j` ひらがな、`C-q` 半角カナ、`C-l` 英数、`C-L` 全角英数（macSKK の流れ）
- 入力ソースは「sokkou」の 1 つだけ。英数も sokkou の中のモードなので、ほかの入力ソースに切り替えなくてよい。パスワード欄では macOS が ABC などの英字の入力ソースに自動で替える
- 自分で区切りたいときは `;` で ▽ を始める。送り仮名も `;` か大文字で区切る
- 変換中は Emacs のキーで操作する。何も打っていないときの Ctrl キーはアプリに渡す
- 選んだ候補だけを控えめに覚える。入力メニューから切れる
- 軽さを優先し、既定は azooKey の辞書だけで変換する（Zenzai は使わない）

キーの全体は [docs/keys.md](docs/keys.md)。

## 入れ方

Apple シリコンの macOS 14 以降で動く。

1. [最新のリリース](https://github.com/trkw/sokkou/releases/latest) から `sokkou-macos-arm64.dmg` を取ってきて開く
2. 窓の sokkou をダブルクリックする。sokkou が自分を `~/Library/Input Methods` に入れ、入力ソースに足す
3. 「sokkou を入れました」と出たら「sokkou に切り替える」を押す。入力ソースの一覧に出ないときだけ、ログインし直す
   （前の版の「sokkou (英数)」「sokkou (日本語)」が残っていたら、システム設定 → キーボード → 入力ソース で両方を「−」で外す）

ターミナルからなら 1 行で入る。こちらは次の「開けません」も出ない。

```sh
curl -fsSL https://raw.githubusercontent.com/trkw/sokkou/main/install.sh | bash
```

### 「開けません」「開発元を確認できません」と出たとき

sokkou は Apple の公証を受けていないので、dmg から開くと最初の 1 回だけ macOS が止める。

- **macOS 15 以降**: いったん閉じて、システム設定 → プライバシーとセキュリティ の下のほうにある「このまま開く」を押し、もう一度 sokkou を開いて「このまま開く」を選ぶ
- **macOS 14**: sokkou を右クリック（Control + クリック）して「開く」を選び、出てきた窓で「開く」を押す

### 取り除き方

入力メニューの「sokkou を取り除く…」を選ぶ。入力ソースから外し、`~/Library/Input Methods/sokkou.app` と取っておいた前の版を消す。覚えた候補と設定も消すかを選べる。ターミナルからなら:

```sh
~/Library/Input\ Methods/sokkou.app/Contents/MacOS/sokkou --uninstall          # 覚えた候補（~/Library/Application Support/sokkou）は残す
~/Library/Input\ Methods/sokkou.app/Contents/MacOS/sokkou --uninstall --purge  # 覚えた候補と設定も消す
```

## 更新

main に入るたびに CI が dmg を組み立ててリリースに置く。入れ替えると動いている版を止めて新しい版をすぐ起動するので、ログインし直さなくてよい。

入れる前に次を確かめ、どれかが合わなければ今の版のまま失敗を窓で知らせる。

1. dmg の SHA-256 が、GitHub がリリースの資産ごとに出す値と合う
2. 中の .app の署名が壊れておらず、バンドル ID が sokkou のもの
3. その .app が辞書を読んで 1 文を変換できる（`--check`）

入れ替える前の版は `~/Library/Application Support/sokkou/previous` に取っておく。入れ替えに失敗したときや、新しい版が起動してすぐ落ちたときは、自動でそれに戻す。入力メニューの「前の版に戻す」でも戻せ、戻した版は自動の更新でもう一度は入れない。更新の記録は `~/Library/Logs/sokkou-update.log` に日時つきで書き足す。

リリースの版で動いているときは、1 時間ごとに新しいリリースを確かめ、見つけたら 2 分打たなかったときに自動で入れ替える（入力メニューの「新しいリリースを自動で入れる」で切れる）。PR の版や手元の版を試している間は自動では入れ替えない。

- **入力メニューから**: 「最新版に更新」で最新のリリースに、「PR の版を入れる…」で番号を入れた PR のビルドに入れ替わる。入れ替わると新しい版が「sokkou を … にしました」と窓で知らせ、失敗したら理由を窓で出す（詳しくは `~/Library/Logs/sokkou-update.log`）。メニューにはいま動いているビルド（`v0.1.7 · abc1234`、`PR #4 · abc1234` など）が出る
- **ターミナルから**:

  ```sh
  curl -fsSL https://raw.githubusercontent.com/trkw/sokkou/main/install.sh | bash               # 最新のリリース
  curl -fsSL https://raw.githubusercontent.com/trkw/sokkou/main/install.sh | bash -s -- --pr 4  # PR #4 のビルド
  ```

PR のビルドは、CI が push のたびに `pr-<番号>` のプレリリースとして置き直し、PR を閉じると（マージしても）消す（fork からの PR は置かない）。push の直後は CI が終わるまで数分ビルドが無い。PR の版は普段使いの版と同じ sokkou を上書きするので、試し終わったら「最新版に更新」で戻す。

## 手元で組み立てる

Xcode 26 が要る。

```sh
swift test                                   # キー操作の状態のテスト（SokkouCore は Linux でも動く）
scripts/build-app.sh                         # dist/sokkou Dev.app を組み立てる
bash install.sh "dist/sokkou Dev.app"        # 組み立てたものを入れる
"dist/sokkou Dev.app/Contents/MacOS/sokkou" --snapshot snapshots   # 候補の窓とモードの札を画像に書き出す
```

## 構成

| ターゲット | 役割 |
| --- | --- |
| `SokkouCore` | キー操作の状態（打っている途中・文節選択・▽ ▼）と表示。変換エンジンには `Engine` の形でだけ触る |
| `SokkouEngine` | tugime の `TugimeCore`（日英判定と azooKey の変換）を `Engine` につなぐ |
| `SokkouIME` | InputMethodKit の入力コントローラ、候補の窓、モードの印 |

## 謝辞

- 日英判定と変換は [tugime](https://github.com/miyaoka/tugime)（miyaoka さん）の `TugimeCore` をそのまま使っている。入力メソッドの組み立ての手順も tugime を手本にした。tugime のリポジトリには今のところ LICENSE が無いので、公開して配る前に miyaoka さんと扱いを決める
- かな漢字変換は [AzooKeyKanaKanjiConverter](https://github.com/azooKey/AzooKeyKanaKanjiConverter)
- キー操作は [macSKK](https://github.com/mtgto/macSKK)、自動変換の手軽さは meltype を参考にした
