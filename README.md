# sokkou（即効）

SKK の手触りで、打てばそのまま変換される、自分用の macOS 日本語入力。

- 普段は Shift を押さずにローマ字を打つだけで、日本語と英語を判定して自動で変換する（meltype の流れ）
- ローマ字は訓令式もヘボン式も読む（zi shi chi tsu fu sha cha jya zya）。綴りの表は `Sources/SokkouEngine/Resources/romaji.tsv`
- 英語と判定した語も、候補の窓や `C-k` でカタカナにできる（test → テスト、online game → オンラインゲーム）。表は azooKey の辞書と JMdict から `scripts/make-loanwords.py` で作った `Sources/SokkouEngine/Resources/loanwords.tsv`（約 1 万 5 千語）
- `kyou` `ima` `nau`（きょう・いま・なう）を候補の窓に出すと、辞書の候補の後ろに今日の日付や今の時刻が並ぶ（2026年10月25日(日)、17:05 など。きのう・あした・あさって・おとといも。Meltype の動きにならった）
- モードは Ctrl で切り替える。`C-j` ひらがな、`C-q` 半角カナ、`C-l` 英数、`C-L` 全角英数（macSKK の流れ）
- 入力ソースは「sokkou (英数)」と「sokkou (日本語)」の 2 つ。`C-l` `C-j` でも Ctrl-Space（macOS の入力ソースの切り替え）でも行き来でき、macOS の札とメニューバーのアイコンで今どちらか分かる。カタカナ・半角カナ・全角英数は日本語の中のモードで、切り替えると sokkou の札が出る
- モードはアプリごとに覚える（更新や再起動のあとも）。ターミナル（Terminal、iTerm、WezTerm、Ghostty、kitty、Alacritty、Warp）は英数から始まる
- 自分で区切りたいときは `;` で ▽ を始める。送り仮名も `;` か大文字で区切る
- 変換中は Emacs のキーで操作する。何も打っていないときの Ctrl キーはアプリに渡す
- 選んだ候補だけを控えめに覚える。入力メニューから切れる
- SKK のように、候補の最後の「登録…」から単語を登録でき、`X` で候補を消せる。ユーザー辞書は SKK 形式で、`~/.skk-jisyo` や macSKK の辞書を取り込める
- SKK 辞書（SKK-JISYO.L など）を追加の候補元にできる。ほかに abbrev（`/`）、数値変換、Tab での読みの補完
- 軽さを優先し、既定は azooKey の辞書だけで変換する。設定の「辞書」の「賢い変換」で、言語モデルの Zenzai（zenz-v3.2-small、74MB）か genmai（genmai-310M、340MB）を選べる。選んだモデルはそのときに Hugging Face から取ってきて、sokkou の入れ物の中の `Application Support/sokkou/Models` に置く

キーの全体は [docs/keys.md](docs/keys.md)。

## 入れ方

Apple シリコンの macOS 14 以降で動く。

1. [最新のリリース](https://github.com/trkw/sokkou/releases/latest) から `sokkou-macos-arm64.dmg` を取ってきて開く
2. 窓の sokkou をダブルクリックする。sokkou に入っているインストーラーが sokkou を `~/Library/Input Methods` に入れ、入力ソースに「sokkou (日本語)」と「sokkou (英数)」を足す
3. 「sokkou を入れました」と出たら「sokkou に切り替える」を押す。入力ソースの一覧に出ないときだけ、ログインし直す

ターミナルからなら 1 行で入る。こちらは次の「開けません」も出ない。

```sh
curl -fsSL https://raw.githubusercontent.com/trkw/sokkou/main/install.sh | bash
```

Homebrew なら cask で入る。sokkou は自分で新しい版に入れ替わるので、`brew upgrade` を待たなくてよい。

```sh
brew install --cask trkw/tap/sokkou
```

Nix なら flake を使う。nix-darwin でも home-manager でも、`programs.sokkou.enable = true;` で `~/Library/Input Methods` に入って登録される。

```nix
# flake.nix の inputs
sokkou.url = "github:trkw/sokkou";
sokkou.inputs.nixpkgs.follows = "nixpkgs";

# nix-darwin なら modules に sokkou.darwinModules.default、home-manager なら sokkou.homeManagerModules.default を足して
programs.sokkou.enable = true;
# 版を flake.lock に固定して自動更新を切るなら
programs.sokkou.autoUpdate = false;
```

`autoUpdate` は既定で `true`（入力メニューの「新しいリリースを自動で入れる」と同じ）。そのときは、自動更新が入れた新しい版を Nix が古い版に戻すことはしない。どの経路で入れても、初めてのときは入力ソースに「sokkou (日本語)」と「sokkou (英数)」が足される。一覧に出ないときだけ、ログインし直す。

main に入るたびに CI が dmg を組み立ててリリースに置き、Homebrew の cask（[trkw/homebrew-tap](https://github.com/trkw/homebrew-tap)）と Nix の版（`nix/release.json`）も書き換える。仕組みは [docs/distribution.md](docs/distribution.md)。

### 安全のために

入力メソッドは打った文字のほとんどを見るので、sokkou が何をして何をしないかを書いておく。

- 打った文字や覚えた候補を外へ送らない。覚えた候補とユーザー辞書は sokkou の入れ物（`~/Library/Containers/io.github.trkw.inputmethod.sokkou/Data/Library/Application Support/sokkou`）にだけ置く
- sokkou は App Sandbox の中で動く。触れられるファイルは自分の入れ物と、「SKK 辞書を追加…」などで自分で選んだファイルだけ。穴を突かれても、ほかのファイルを読んだり書き換えたりできない。権限は `App/sokkou.entitlements` に書いたものだけで、CI が毎回それ以外が付いていないかを確かめる
- 通信の権限は残している（下の 2 つに要る）。受け付けの口は開けない
- `~/Library/Input Methods` への導入・更新・取り除きは、sokkou の中に入れた別のアプリ（`Contents/Helpers/sokkou-installer.app`）がする。こちらはサンドボックスの外で動き、打った文字は見ない
- つなぐ先は GitHub と Hugging Face だけ。新しいリリースの確認（1 時間に 1 回、`api.github.com`）と dmg の取得、それに頼まれたときだけ SKK-JISYO.L（GitHub）と賢い変換のモデル（Hugging Face）を取る
- 更新で入れる dmg は、GitHub がリリースの資産ごとに出す SHA-256 と突き合わせ、中の .app が trkw の Developer ID（Team ID `BCA6Z83Q5N`）で署名されていることを確かめてから入れる。fork からの PR のように署名の違うビルドは入らない
- SKK-JISYO.L は skk-dev/dict のコミットを固定して取り、SHA-256 が合わなければ入れない

### 取り除き方

入力メニューの「sokkou を取り除く…」を選ぶ。入力ソースから外し、`~/Library/Input Methods/sokkou.app` と取っておいた前の版を消す。覚えた候補と設定も消すかを選べる。ターミナルからなら:

```sh
~/Library/Input\ Methods/sokkou.app/Contents/MacOS/sokkou --uninstall          # 覚えた候補とユーザー辞書は残す
~/Library/Input\ Methods/sokkou.app/Contents/MacOS/sokkou --uninstall --purge  # 覚えた候補と設定も消す
```

## 辞書

辞書と覚えた候補は、sokkou の入れ物の `~/Library/Containers/io.github.trkw.inputmethod.sokkou/Data/Library/Application Support/sokkou` に置く（入力メニューの「辞書のフォルダを開く」で開ける）。App Sandbox に入れる前の版の `~/Library/Application Support/sokkou` にあったものは、入れた版を初めて起動したときに macOS がここへ写す。

- **ユーザー辞書**: `skk-jisyo.utf8`（SKK 形式、UTF-8）。候補の「登録…」で登録した語が入る。`X` で消した語は隣の `ignored.tsv` に残り、変換エンジンの候補からも外れる
- **取り込み**: 入力メニューの「SKK のユーザー辞書を取り込む…」で `~/.skk-jisyo` や macSKK の `skk-jisyo.utf8` を選ぶと、無い語だけを足す（UTF-8 と EUC-JP を読む）
- **SKK 辞書**: 入力メニューの「SKK-JISYO.L を入れる」で [skk-dev/dict](https://github.com/skk-dev/dict) から取ってくる。「SKK 辞書を追加…」でほかの辞書（人名、地名など）も足せる。辞書は同じところの `Dictionaries/` に置かれ、中のファイルはすべて読む。SKK 辞書の語は ▽ の候補と文節選択の候補の後ろに出る

## 設定

入力メニューの「設定…」で設定の窓が開く。

- **一般**: 「sokkou (日本語)」と「sokkou (英数)」を入力ソースに足してあるかが分かる。足していなければ「開く」でキーボードの設定に飛べる。選んだ候補を覚えるか、覚えた候補を忘れる、新しいリリースを自動で入れるか、いまの版
- **キー**: よく使うキーの早見表
- **情報**: 版と、GitHub・不具合の報告への入口

## 軽さ

MacBook Neo（メモリ 8GB）でも気持ちよく打てることを目安にしている。CI は毎回 `sokkou --bench` で、本物の辞書を使って数文を 1 打鍵ずつ打ち、1 打鍵にかかる時間とメモリの最大を測ってジョブのまとめに載せる。遅かった打鍵も、そこまでに打ったものと一緒に出す。

```sh
"dist/sokkou Dev.app/Contents/MacOS/sokkou" --bench
```

## ターミナルで使う

WezTerm は既定では Ctrl 付きのキーを IME に渡さないので、`~/.wezterm.lua` に次を足す。足さないと `C-j` `C-l` が sokkou に届かない。

```lua
config.use_ime = true
config.macos_forward_to_ime_modifier_mask = "SHIFT|CTRL"
```

Ghostty は 1.1.0 以降なら設定は要らない。Ghostty は「キーを押している間に入力ソースが変わったら、そのキーは IME が使った」とみなして端末に送らないので、入力ソースの切り替えになる `C-j` `C-l` は改行や画面の消去として漏れない（macSKK 作者の [Ghostty 向けの記事](https://zenn.dev/mtgto/articles/macskk-karabiner-settings-for-ghostty) と同じ仕組み）。そのため「sokkou (英数)」と「sokkou (日本語)」の両方を入力ソースに入れておく。1.0 までの Ghostty なら、記事のとおり `keybind = ctrl+j=ignore` を足す。カタカナ・半角カナは入力ソースが変わらないので、半角カナの `C-q` を使うなら `keybind = ctrl+q=ignore` を足しておくと端末に XON が送られない（何も打っていないときの `C-k` は、もともと行末までの削除としてシェルに渡している）。Karabiner-Elements の設定は要らない。

ほかのターミナルでも、何も打っていないときに sokkou がモードの切り替えに使った Ctrl キーは、ターミナルが改行や画面の消去として重ねて処理しないよう、未確定の文字列を一瞬出して消して知らせる（AquaSKK・macSKK の空文字挿入と同じ）。英数モードの `C-l` はそのままシェルに渡るので、画面の消去に使える。

打ち始めの変換は入力欄のカーソルの前に続けて読む（文頭か、日本語や英語の続きか、数字の後なら `3` に続く `nin` を 人 に）。カーソルの前を返さないターミナルでは、sokkou がそこで確定した文字列に続ける。アプリにキーを渡したときと入力欄を離れたときに忘れる。

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
```

sokkou は App Sandbox の中で動くので、`--snapshot` は作業ディレクトリに書けない。権限を外した写しで書き出す:

```sh
ditto "dist/sokkou Dev.app" /tmp/snap.app && codesign --force --sign - /tmp/snap.app
/tmp/snap.app/Contents/MacOS/sokkou --snapshot snapshots   # 候補の窓とモードの札を画像に書き出す
```

手元で組み立てたものは ad-hoc 署名になる。配る dmg の署名と公証は [docs/signing.md](docs/signing.md)。

## 構成

| ターゲット | 役割 |
| --- | --- |
| `SokkouCore` | キー操作の状態（打っている途中・文節選択・▽ ▼）と表示。変換エンジンには `Engine` の形でだけ触る |
| `SokkouConverter` | 日英の区切り（英語の語表と綴りらしさ）と、azooKey のかな漢字変換 |
| `SokkouEngine` | `SokkouConverter` を `Engine` につなぐ。ローマ字の綴りの表と英単語のカタカナ読み |
| `SokkouIME` | InputMethodKit の入力コントローラ、候補の窓、モードの印 |

## 上流を追う

AzooKeyKanaKanjiConverter は revision で固定している。`upstream-watch` のワークフローが毎朝、azooKey・azooKey-Desktop・tugime・Meltype などの新しいコミットやリリースを見て、`upstream` ラベルの issue で知らせる。上げるときは `Package.swift` の azooKey の revision を書き換える。Meltype は GPL-3.0 なので、取り込むのは考え方と動きだけで、コードは写さない。

## 謝辞

- かな漢字変換は [AzooKeyKanaKanjiConverter](https://github.com/azooKey/AzooKeyKanaKanjiConverter)
- 英語の語の頻度は [wordfreq](https://github.com/rspeer/wordfreq)（CC BY-SA 4.0）、英語の綴りらしさの語表は Webster's Second International（1934 年、著作権切れ）
- キー操作は [macSKK](https://github.com/mtgto/macSKK)、自動変換の手軽さは meltype を参考にした
- 友だちの miyaoka の [tugime](https://github.com/miyaoka/tugime) には大いに助けられた。`SokkouConverter` は tugime から分けてもらったコードがもとで、その後も英単語の割り方（#43）や文節の移り方（#31）などを tugime から取り込んでいる。thank you, my friend!

## モデルのクレジット

賢い変換のモデルはアプリにもリポジトリにも入れず、選んだ人が手元に取ってくる。

- [zenz-v3.2-small](https://huggingface.co/Miwa-Keita/zenz-v3.2-small-gguf)（Miwa-Keita、Apache-2.0）
- [genmai-310M](https://huggingface.co/subdiox/genmai-310M)（subdiox、CC BY-SA 4.0。[zenz-v2.5-medium](https://huggingface.co/Miwa-Keita/zenz-v2.5-medium) をもとにしたモデル）。GGUF は miyaoka が変換した [genmai-310M-GGUF](https://huggingface.co/miyaoka/genmai-310M-GGUF)。genmai を動かすコード（`ZenzGenerator` など）は tugime から分けてもらった

## 辞書のクレジット

英単語のカタカナ読みの表（`Sources/SokkouEngine/Resources/loanwords.tsv`）は、[azooKey の辞書](https://github.com/ensan-hcl/azooKey_dictionary_storage)（Apache License 2.0）と、[Electronic Dictionary Research and Development Group](https://www.edrdg.org/) の [JMdict](https://www.edrdg.org/wiki/index.php/JMdict-EDICT_Dictionary_Project)（[CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/)）から作っている。この表も CC BY-SA 4.0 で使える。

## ライセンス

sokkou のコードは [MIT](LICENSE)。ただし `Sources/SokkouEngine/Resources/loanwords.tsv`（JMdict を含む）と `Sources/SokkouConverter/Resources/english-frequency.tsv`（wordfreq から作った）は CC BY-SA 4.0。アプリに入っている第三者のソフトウェアとデータのライセンスは [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) にまとめた（アプリの中にも入れている）。
