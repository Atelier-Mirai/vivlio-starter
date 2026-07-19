# インストール詳細

:::{.chapter-lead}
本章は、`vs new` が自動で行う環境構築の内訳を知りたい方、macOS 以外の環境に手動でインストールしたい方、CI/CD 環境を構築したい方のための補足資料です。通常の macOS 環境であれば、本章を読まなくてもすぐに執筆を始められます。
:::

## Ruby のインストール

Vivlio Starter は Ruby で動作します。Ruby がまだインストールされていない場合は、同梱のスクリプトを使うのが最も簡単です。

```bash
bin/install-ruby.zsh              # 対話的に最新安定版を導入
bin/install-ruby.zsh -y           # 確認をスキップして自動導入
bin/install-ruby.zsh -v 4.0.2     # バージョンを明示して導入
bin/install-ruby.zsh --no-bundler # bundler の導入をスキップ
```

このスクリプトは次の作業を自動で行います。Xcode Command Line Tools の確認とインストール案内、Homebrew の導入、rbenv / ruby-build の導入、Ruby 本体のインストールと `rbenv global` 設定、bundler の導入。

:::{.column}
**ターミナルの開き方（macOS）**

Spotlight から: `Cmd + Space` →「Terminal」と入力 → Enter。
Finder から: アプリケーション → ユーティリティ → Terminal.app。
[iTerm2](https://iterm2.com/) や [Warp](https://www.warp.dev/) などの代替ターミナルも利用できます。
:::

## Vivlio Starter のインストール

Ruby の準備ができたら、gem をインストールします。

```bash
gem install vivlio-starter
```

PDF アウトライン・しおり機能などを使う場合は、追加の gem も導入してください（いずれも任意）。

```bash
gem install vivlio-starter-pdf  # AGPL のため本体とは別 gem
gem install query-stream        # データ展開機能
```

## 自動インストールの内訳

`vs new mybook` を実行すると、内部で `vs doctor --fix` が呼び出され、次のツール群が自動でインストールされます。何が導入されるかを把握しておきたい方のための一覧です。

| ツール | インストール方法 | 用途 |
| :--- | :--- | :--- |
| Xcode Command Line Tools | `xcode-select --install` | macOS のビルド基盤 |
| Homebrew | 公式インストーラ | macOS 用パッケージマネージャ |
| Node.js（node@20 優先）/ npm | `brew install node@20` | Vivliostyle CLI の前提 |
| Vivliostyle CLI | `npm install -g @vivliostyle/cli` | PDF 生成エンジン |
| textlint と推奨ルール | `npm install -g textlint ...` | 文章校正。設定ファイルも `config/` に自動配置 |
| qpdf | `brew install qpdf` | PDF 分割・結合・ページ操作 |
| poppler（pdfinfo / pdftoppm） | `brew install poppler` | PDF メタデータ取得・ページ画像化 |
| Ghostscript | `brew install ghostscript` | PDF 圧縮 |
| ImageMagick | `brew install imagemagick` | 画像変換・WebP 変換 |
| Inkscape | `brew install inkscape` | SVG → PDF 変換（カバー生成用） |
| librsvg（rsvg-convert） | `brew install librsvg` | EPUB 扉絵・節絵の合成画像ラスタライズ |
| libvips | `brew install vips` | 高速画像処理 |
| Tesseract + 日本語データ | `brew install tesseract tesseract-lang` | OCR エンジン |
| MeCab | `brew install mecab mecab-ipadic` | 索引機能の読み自動推測 |
| rouge | `gem install rouge` | コードブロック言語推定 |
| mathjax-full | `npm install -g mathjax-full` | 数式の SVG 化 |
| `waifu2x-ncnn-vulkan` | GitHub Releases から自動取得 | AI 画像拡大（オプション） |
| Kindle Previewer 3（kindlepreviewer） | `brew install --cask kindle-previewer` ＋ ラッパー作成 | Kindle（KPF）変換（任意・targets: kindle 用） |
| Google Fonts 用 SSL 証明書 | 自動設定 | Google Fonts ダウンロード（macOS のみ） |

Xcode Command Line Tools と Homebrew のインストール時のみ確認プロンプトが表示されます。`--yes` オプションで省略できます。

**自動インストール（`vs doctor --fix`）が対応しているのは macOS + Homebrew 環境のみです。** Linux や Windows については、現時点で動作検証を行えておらず、公式のサポート対象外です。必要なツールさえ揃えば動作する見込みはありますので、以降の手動インストール手順を手がかりに、お使いの環境へ読み替えてセットアップしてみてください（うまく動くことを願っています）。将来的に正式対応するかもしれません。

## 手動インストール

### macOS

1) Xcode Command Line Tools

```bash
xcode-select --install
```

2) Homebrew

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

インストール後、PATH を設定します。

```bash
echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile   # Apple Silicon
echo 'eval "$(/usr/local/bin/brew shellenv)"' >> ~/.zprofile      # Intel（必要時）
source ~/.zprofile
```

3) Ruby（rbenv）

```bash
brew install rbenv ruby-build
echo 'export PATH="$HOME/.rbenv/bin:$PATH"' >> ~/.zprofile
echo 'eval "$(rbenv init - zsh)"' >> ~/.zprofile
source ~/.zprofile

rbenv install 4.0.2
rbenv global 4.0.2
ruby -v
```

4) Node.js

```bash
brew install node@20 || brew install node
node -v && npm -v
```

5) Vivliostyle CLI

```bash
npm install -g @vivliostyle/cli
vivliostyle --version
```

6) 外部ツール（PDF・画像処理）

```bash
brew install qpdf poppler ghostscript imagemagick inkscape vips
brew install tesseract tesseract-lang mecab mecab-ipadic
```

7) Vivlio Starter gem

```bash
gem install vivlio-starter
vs --version
```

8) プロジェクト作成と動作確認

```bash
vs new mybook
cd mybook
vs build
```

`mybook_v0.1.0.pdf` が生成されれば成功です。

### Linux / WSL（Ubuntu / Debian の例）

1) 必要パッケージ

```bash
sudo apt-get update
sudo apt-get install -y build-essential curl git \
  qpdf ghostscript imagemagick poppler-utils \
  tesseract-ocr tesseract-ocr-jpn libvips-tools mecab
```

2) Node.js（nvm 推奨）

```bash
curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
source ~/.nvm/nvm.sh
nvm install --lts
node -v && npm -v
```

3) Ruby（rbenv 推奨）

```bash
sudo apt-get install -y libssl-dev libreadline-dev zlib1g-dev
curl -fsSL https://github.com/rbenv/rbenv-installer/raw/main/bin/rbenv-installer | bash
export PATH="$HOME/.rbenv/bin:$PATH" && eval "$(rbenv init - bash)"
rbenv install 4.0.2 && rbenv global 4.0.2
ruby -v
```

4) Vivliostyle CLI と Vivlio Starter

```bash
npm install -g @vivliostyle/cli
gem install vivlio-starter
```

5) プロジェクト作成と動作確認

```bash
vs new mybook
cd mybook
vs build
```

ヘッドレス環境では PDF ビューアーの自動起動は行われません。`mybook_v0.1.0.pdf` を任意のビューアーで確認してください。

### Windows

WSL2 + Ubuntu の利用を推奨します（上記 Linux / WSL の手順を参照）。どうしてもネイティブ環境で行う場合の最小手順です。

**Chocolatey の場合**（管理者 PowerShell）

```powershell
choco install -y git ruby nodejs-lts qpdf ghostscript imagemagick poppler
```

**Scoop の場合**

```powershell
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
iwr -useb get.scoop.sh | iex
scoop bucket add main
scoop install git ruby nodejs-lts qpdf ghostscript imagemagick poppler
npm install -g @vivliostyle/cli
gem install vivlio-starter
vivliostyle --version
vs --version
```

## トラブルシューティング

| 症状 | 原因 | 解決策 |
| :--- | :--- | :--- |
| `brew` が見つからない | Homebrew 未インストール | `vs doctor --fix` または [brew.sh](https://brew.sh) を参照 |
| `npm` が見つからない | Node.js 未インストール | `vs doctor --fix` で Node.js をインストール後、再実行 |
| Xcode CLT のインストールが完了しない | GUI 承認が必要 | インストーラ完了後に `vs doctor --fix` を再実行 |
| Homebrew の PATH が通らない（Apple Silicon） | `/opt/homebrew/bin` が PATH に未追加 | `echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile && source ~/.zprofile` |
| Ruby のバージョンが合わない | `.ruby-version` と不一致 | `rbenv install $(cat .ruby-version) && rbenv global $(cat .ruby-version)` |
| `bundler` が見つからない | bundler 未インストール | `gem install bundler` |
| Node.js の依存関係エラー | `node_modules` の不整合 | `rm -rf node_modules package-lock.json && npm install` |
| ImageMagick の WebP 変換が失敗 | WebP 非対応ビルド | `brew reinstall imagemagick` |
| Google Fonts の SSL エラーが解消しない | 証明書パスが未反映 | シェルを再起動して `SSL_CERT_FILE` が有効になっているか確認 |

:::{.column}
**まず `vs doctor` を試してください**

ビルドや lint が突然失敗したときは、`vs doctor` で環境を診断するのが近道です。不足ツールが一覧表示されます。`vs doctor --fix` で自動修復も試みられます。詳細は「環境診断（vs doctor）」の章を参照してください。
:::

## CI（GitHub Actions）でのビルド例

プロジェクトルートに `.github/workflows/build.yml` を作成します。

```yaml
name: Build PDF
on: [push, pull_request]
jobs:
  build:
    runs-on: ${{ matrix.os }}
    strategy:
      matrix:
        os: [ubuntu-latest, macos-latest]
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: '20'
      - uses: ruby/setup-ruby@v1
        with:
          ruby-version: '4.0'
          bundler-cache: true
      - name: Install system deps
        run: |
          if [[ "${{ runner.os }}" == "Linux" ]]; then
            sudo apt-get update
            sudo apt-get install -y qpdf ghostscript poppler-utils imagemagick
          else
            brew update
            brew install qpdf ghostscript poppler imagemagick
          fi
      - run: npm ci
      - run: bundle install --jobs 4
      - run: vs build
      - uses: actions/upload-artifact@v4
        with:
          name: PDF
          path: output_compressed.pdf
```

:::{.column}
**GitHub の 100MB 制約について**

大きな PDF は Git にプッシュできません。CI では `vs build` が自動圧縮した `output_compressed.pdf` をアーティファクトとしてアップロードするのが確実です。圧縮には Ghostscript を使用しています。リポジトリに PDF を含める場合は `.gitignore` の末尾に `!*.pdf` を追記してください。
:::
