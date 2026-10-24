# sokkou（即効）

SKK の手触りで、打てばそのまま変換される、自分用の macOS 日本語入力。

- 普段は Shift を押さずにローマ字を打つだけで、日本語と英語を判定して自動で変換する（meltype、tugime の流れ）
- ローマ字は訓令式もヘボン式も読む（zi shi chi tsu fu sha cha jya zya）。綴りの表は `Sources/SokkouEngine/Resources/romaji.tsv`
- 英語と判定した語も、候補の窓や `C-k` でカタカナにできる（test → テスト）。表は azooKey の辞書と JMdict から `scripts/make-loanwords.py` で作った `Sources/SokkouEngine/Resources/loanwords.tsv`（約 1 万 5 千語）
- モードは Ctrl で切り替える。`C-j` ひらがな、`C-q` 半角カナ、`C-l` 英数、`C-L` 全角英数（macSKK の流れ）
- 入力ソースは「sokkou (英数)」と「sokkou (日本語)」の 2 つ。`C-l` `C-j` でも Ctrl-Space（macOS の入力ソースの切り替え）でも行き来でき、macOS の札とメニューバーのアイコンで今どちらか分かる。カタカナ・半角カナ・全角英数は日本語の中のモードで、切り替えると sokkou の札が出る
- モードはアプリごとに覚える。ターミナル（Terminal、iTerm、WezTerm、Ghostty、kitty、Alacritty、Warp）は英数から始まる
- 自分で区切りたいときは `;` で ▽ を始める。送り仮名も `;` か大文字で区切る
- 変換中は Emacs のキーで操作する。何も打っていないときの Ctrl キーはアプリに渡す
- 選んだ候補だけを控えめに覚える。入力メニューから切れる
- 軽さを優先し、既定は azooKey の辞書だけで変換する（Zenzai は使わない）

キーの全体は [docs/keys.md](docs/keys.md)。

## 入れ方

Apple シリコンの macOS 14 以降で動く。

1. [最新のリリース](https://github.com/trkw/sokkou/releases/latest) から `sokkou-macos-arm64.dmg` を取ってきて開く
2. 中の sokkou を右クリックして「開く」を選ぶ。sokkou が自分を `~/Library/Input Methods` に入れて登録する
   （Apple の公証を受けていないので、初回は「開発元を確認できない」と出る。システム設定 → プライバシーとセキュリティ の「このまま開く」で開ける）
3. 初めて入れたときはログインし直してから、システム設定 → キーボード → 入力ソース → 編集 → 「+」→ 日本語 → 「sokkou (日本語)」と「sokkou (英数)」を追加する
   （入れ替えたときは、sokkou を使っていれば両方とも自動で有効になる）

ターミナルからなら 1 行で入る。

```sh
curl -fsSL https://raw.githubusercontent.com/trkw/sokkou/main/install.sh | bash
```

main に入るたびに CI が dmg を組み立ててリリースに置く。

## ターミナルで使う

WezTerm は既定では Ctrl 付きのキーを IME に渡さないので、`~/.wezterm.lua` に次を足す。足さないと `C-j` `C-l` が sokkou に届かない。

```lua
config.use_ime = true
config.macos_forward_to_ime_modifier_mask = "SHIFT|CTRL"
```

Ghostty は 1.1.0 以降なら設定は要らない。Ghostty は「キーを押している間に入力ソースが変わったら、そのキーは IME が使った」とみなして端末に送らないので、入力ソースの切り替えになる `C-j` `C-l` は改行や画面の消去として漏れない（macSKK 作者の [Ghostty 向けの記事](https://zenn.dev/mtgto/articles/macskk-karabiner-settings-for-ghostty) と同じ仕組み）。そのため「sokkou (英数)」と「sokkou (日本語)」の両方を入力ソースに入れておく。1.0 までの Ghostty なら、記事のとおり `keybind = ctrl+j=ignore` を足す。カタカナ・半角カナは入力ソースが変わらないので、半角カナの `C-q` を使うなら `keybind = ctrl+q=ignore` を足しておくと端末に XON が送られない（何も打っていないときの `C-k` は、もともと行末までの削除としてシェルに渡している）。Karabiner-Elements の設定は要らない。

ほかのターミナルでも、何も打っていないときに sokkou がモードの切り替えに使った Ctrl キーは、ターミナルが改行や画面の消去として重ねて処理しないよう、未確定の文字列を一瞬出して消して知らせる（AquaSKK・macSKK の空文字挿入と同じ）。英数モードの `C-l` はそのままシェルに渡るので、画面の消去に使える。

## 新しい版を試す

入れ替えると動いている版を止めて新しい版をすぐ起動するので、ログインし直すのは初めて入れたときだけでよい。

リリースの版で動いているときは、1 時間ごとに新しいリリースを確かめ、見つけたら 2 分打たなかったときに自動で入れ替える（入力メニューの「新しいリリースを自動で入れる」で切れる）。PR の版や手元の版を試している間は自動では入れ替えない。

- **入力メニューから**: 「最新版に更新」で最新のリリースに、「PR の版を入れる…」で番号を入れた PR のビルドに入れ替わる。終わると通知が出る（失敗したら `~/Library/Logs/sokkou-update.log` を見る）。メニューにはいま動いているビルド（`v0.1.7 · abc1234`、`PR #4 · abc1234` など）が出る
- **ターミナルから**:

  ```sh
  curl -fsSL https://raw.githubusercontent.com/trkw/sokkou/main/install.sh | bash               # 最新のリリース
  curl -fsSL https://raw.githubusercontent.com/trkw/sokkou/main/install.sh | bash -s -- --pr 4  # PR #4 のビルド
  ```

PR のビルドは、CI が push のたびに `pr-<番号>` のプレリリースとして置き直し、PR を閉じると消す（fork からの PR は置かない）。PR の版は普段使いの版と同じ sokkou を上書きするので、試し終わったら「最新版に更新」で戻す。

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

## 上流を追う

tugime と、tugime が固定している AzooKeyKanaKanjiConverter は revision で固定している。`upstream-watch` のワークフローが毎朝、tugime・azooKey・azooKey-Desktop・Meltype の新しいコミットやリリースを見て、`upstream` ラベルの issue で知らせる。上げるときは `Package.swift` の tugime の revision を書き換える（azooKey は tugime を通して上がる）。Meltype は GPL-3.0 なので、取り込むのは考え方と動きだけで、コードは写さない。

## 謝辞

- 日英判定と変換は [tugime](https://github.com/miyaoka/tugime)（miyaoka さん）の `TugimeCore` をそのまま使っている。入力メソッドの組み立ての手順も tugime を手本にした。tugime のリポジトリには今のところ LICENSE が無いので、公開して配る前に miyaoka さんと扱いを決める
- かな漢字変換は [AzooKeyKanaKanjiConverter](https://github.com/azooKey/AzooKeyKanaKanjiConverter)
- キー操作は [macSKK](https://github.com/mtgto/macSKK)、自動変換の手軽さは meltype を参考にした

## 辞書のクレジット

英単語のカタカナ読みの表（`Sources/SokkouEngine/Resources/loanwords.tsv`）は、[azooKey の辞書](https://github.com/ensan-hcl/azooKey_dictionary_storage)（Apache License 2.0）と、[Electronic Dictionary Research and Development Group](https://www.edrdg.org/) の [JMdict](https://www.edrdg.org/wiki/index.php/JMdict-EDICT_Dictionary_Project)（[CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/)）から作っている。この表も CC BY-SA 4.0 で使える。
