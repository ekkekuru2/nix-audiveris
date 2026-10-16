# nix-audiveris

[Audiveris](https://github.com/Audiveris/audiveris)（楽譜画像を MusicXML に変換する OMR
= Optical Music Recognition アプリ）を Nix でビルドするための **out-of-tree flake** です。

このリポジトリには **Nix パッケージング（flake.nix / package.nix）だけ** が入っています。
Audiveris 本体のソースはフォークせず、flake の `inputs` で本家リポジトリを直接取得します。

## 使い方

```console
# そのまま起動（GUI）
$ nix run github:ekkekuru2/nix-audiveris

# バッチ変換（GUI なし）: 画像/PDF から MusicXML (.mxl) を書き出す
$ nix run github:ekkekuru2/nix-audiveris -- \
    -batch -transcribe -export -output ./out ./score.pdf

# ユーザープロファイルへ入れる
$ nix profile install github:ekkekuru2/nix-audiveris
```

`nix run` は 2 回目以降はビルド済みのものを使います。初回は Audiveris を
ソースからビルドするため数分かかります（Gradle + JDK 25）。

### 他の flake から使う

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nix-audiveris.url = "github:ekkekuru2/nix-audiveris";
  };

  outputs = { nixpkgs, nix-audiveris, ... }: {
    # 1) パッケージを直接使う
    #    nix-audiveris.packages.x86_64-linux.audiveris
    #
    # 2) overlay 経由で pkgs.audiveris として使う（NixOS の場合）
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        (
          { pkgs, ... }:
          {
            nixpkgs.overlays = [ nix-audiveris.overlays.default ];
            environment.systemPackages = [ pkgs.audiveris ];
          }
        )
        ./configuration.nix
      ];
    };
  };
}
```

### OCR 言語データ

Audiveris は歌詞などのテキスト認識に Tesseract を使います。既定では英語
(`eng`) の学習データを同梱し、起動時にユーザーの設定フォルダ
(`$XDG_CONFIG_HOME/AudiverisLtd/audiveris/tessdata`、既定では
`~/.config/AudiverisLtd/audiveris/tessdata`) へコピーします。これは Audiveris
自身がその場所に言語データを置く仕様で、言語マネージャからの追加ダウンロードも
そこへ行われるためです（store への symlink にすると GC で壊れるのでコピー。
既存ファイルは上書きしません。`eng` は約 23 MB あります）。

言語を増やしたい場合は `tessdataLanguages` を上書きします
（指定できる言語は `pkgs.tesseract.languages` の属性名）。

```nix
pkgs.audiveris.override { tessdataLanguages = [ "eng" "deu" "ita" "jpn" ]; }
```

挙動を変えたいときの環境変数:

| 変数 | 意味 |
| --- | --- |
| `TESSDATA_PREFIX` | 設定済みなら Audiveris はそのフォルダを使い、コピー処理は行われません |
| `AUDIVERIS_NIX_SEED_TESSDATA=0` | 設定フォルダへのコピーを無効化 |
| `AUDIVERIS_OPTS` | JVM オプション（既定: `-Xms512m -Xmx8g -Dfile.encoding=UTF-8`） |

## 本家の更新に追従する

Audiveris の Gradle 依存関係は `deps.json`（nixpkgs の Gradle 用ロックファイル）
に固定されています。本家を更新したら、ロックファイルも作り直してください。

```console
$ nix flake update audiveris          # 本家の最新コミットを取り込む
$ nix run .#update-deps               # deps.json を再生成（ネットワーク必須・リポジトリ直下で実行）
$ nix build .#audiveris               # ビルドを確認
$ nix flake check                     # サンプル楽譜の変換テストまで実行
```

`nix run .#update-deps` は Gradle を MITM プロキシ経由で走らせ、実際に
ダウンロードされた Maven 成果物の URL とハッシュを記録します。`nixpkgs` を
更新したときに Gradle や JDK のバージョンが上がった場合も、同じ手順で
`deps.json` を作り直す必要があることがあります。

## 中身

| ファイル | 役割 |
| --- | --- |
| `flake.nix` | `inputs`（nixpkgs と本家 Audiveris）と、packages / apps / overlays / checks の定義 |
| `package.nix` | パッケージ本体。Gradle `:app:installDist` でビルドし、起動用ラッパを作る |
| `deps.json` | Gradle 依存関係のロックファイル（自動生成・手で編集しない） |
| `seed-tessdata.sh` | OCR 言語データを設定フォルダへ用意するラッパ内スクリプト |
| `tests/transcribe.nix` | サンプル楽譜を実際に変換する smoke test（`nix flake check`） |

ビルド時の注意点（`package.nix` 内にもコメントしています）:

- `settings.gradle` を差し替えて `:app` だけをビルドします。本家の
  `docs` / `packaging` / `flatpak` / `schemas` サブプロジェクトはインストーラや
  ハンドブック生成用で、ここでは不要です。
- 本家は `git log` でビルド ID を埋め込みますが、サンドボックス内のソースは
  git リポジトリではないため、flake input の revision を埋め込むよう置換します。
- Tesseract / Leptonica のネイティブライブラリは JavaCPP の jar から実行時に
  展開されるため、ラッパで `LD_LIBRARY_PATH` に C++ ランタイムを足しています。
- 同じく `LD_LIBRARY_PATH` に GTK 3 を足しています。Audiveris は起動時に JNA で
  `libgtk-3.so` を読んで表示スケールを検出しますが、`UnsatisfiedLinkError` を
  捕まえていないため、GTK が無い環境では起動できません。

## 制限

- 対応プラットフォームは `x86_64-linux` と `aarch64-linux` です。`deps.json` は
  Linux 上で生成しており、JavaCPP のネイティブ依存も OS ごとに異なるため、
  macOS では（ロックファイルを作り直さない限り）ビルドできません。
  動作確認は `x86_64-linux` のみです。
- GUI は Swing アプリなので、起動には X11 / Wayland のディスプレイが必要です。
  CI などでは `-batch` を使ってください。

## ライセンス

- Audiveris 本体: AGPL-3.0-or-later（本家リポジトリを参照）
- このリポジトリの Nix コード: MIT（`LICENSE`）
