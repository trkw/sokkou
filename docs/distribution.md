# 配り方

リリースは main への push ごとに `release.yml` が作る（版は `0.1.<実行番号>`）。dmg のほかに、次の 3 つの入口がある。どれも、入れる処理は sokkou 自身の `--install`（dmg から開いたときと同じ）に任せる。

| 入口 | 置き場所 | 版を上げるもの |
| --- | --- | --- |
| `curl … install.sh \| bash` | このリポジトリの `install.sh` | いつも `/releases/latest` |
| Homebrew `brew install --cask trkw/tap/sokkou` | [trkw/homebrew-tap](https://github.com/trkw/homebrew-tap) の `Casks/sokkou.rb` | `release.yml` の `homebrew` ジョブ |
| Nix flake `github:trkw/sokkou` | このリポジトリの `flake.nix` と `nix/` | `release.yml` の `nix` ジョブが `nix/release.json` を main に積む |

入ったあとは、どの入口でも sokkou が 1 時間ごとに新しいリリースを確かめて自分で入れ替わる。

## Homebrew

- cask は `scripts/make-cask.sh <版> <sha256>` が書く。tap の中のファイルは手で直さず、このスクリプトを直す
- `auto_updates true` にしてあるので、`brew upgrade` は sokkou を入れ替えない（`brew upgrade --greedy` なら入れ替える）
- 中身は `installer script:` で dmg の中の `sokkou.app/Contents/MacOS/sokkou --install` を動かす。`brew uninstall` は sokkou を止めて `~/Library/Input Methods/sokkou.app` を消す。`--zap` で辞書と設定も消す
- 公証を受けるまでは、cask の preflight が隔離の属性を外している（Installer.swift が入れた先でしているのと同じ）。署名と公証が入ったら消す
- CI（ci.yml の app）は毎回、組み立てた dmg をこの cask で入れて消せるかを確かめる

### はじめに一度だけ（trkw）

1. GitHub で空の public リポジトリ `trkw/homebrew-tap` を作る（README なども付けなくてよい）
2. Fine-grained personal access token を作る: Settings → Developer settings → Fine-grained tokens → Generate new token
   - Repository access: Only select repositories → `trkw/homebrew-tap`
   - Permissions: Contents を Read and write
3. trkw/sokkou の Settings → Secrets and variables → Actions に `HOMEBREW_TAP_TOKEN` として入れる。ターミナルからなら:

   ```sh
   gh secret set HOMEBREW_TAP_TOKEN --repo trkw/sokkou
   ```

4. Actions の release を main で手で動かす（または次のマージを待つ）。tap に `Casks/sokkou.rb` と README ができる

token が無いあいだ、`homebrew` ジョブは警告を出して何もしない。token には期限があるので、切れたら作り直して入れ直す。

## Nix

- `packages.aarch64-darwin.sokkou`（`default` も同じ）: リリースの dmg を取ってきて `$out/Library/Input Methods/sokkou.app` に置く。Swift の組み立てに Xcode が要るので Nix では組み立てない
- `darwinModules.default` / `homeManagerModules.default`: `programs.sokkou.enable` で、利用者として `--install` を動かす。版が変わったときだけ動かす（動いている sokkou を入れ替えるため）
  - nix-darwin は root で動くので、`programs.sokkou.user`（既定は `system.primaryUser`）のログインのセッションで動かす
  - `autoUpdate`（既定 `true`）は sokkou の設定の `autoUpdates` に書く。`true` なら自動更新が入れた新しい版を古い版に戻さない。`false` なら flake.lock の版にそろえる
- `overlays.default`: `pkgs.sokkou` を足す
- ストアから写すと読み取り専用になるので、`--install` と activation の両方で書けるようにしている。でないと自動更新が入れ替えられない
- CI（ci.yml の nix）は Linux で `nix/test/flake.nix` を評価し、モジュールが nix-darwin と home-manager に入るかを確かめる

## リポジトリを作り直すとき

- `HOMEBREW_TAP_TOKEN` も新しいリポジトリの Secrets に入れ直す（token の対象は homebrew-tap なので作り直さなくてよい）
- `nix/release.json` は古いリポジトリの版を指したままになるが、新しいリポジトリの最初のリリースで書き換わる
