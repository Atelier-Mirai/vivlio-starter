# インストール詳細

:::{.chapter-lead}
通常の macOS 環境では、`vs new` が執筆に必要なツールを揃えます。この章は、その処理の内訳を確かめたいときや、macOS 以外の環境・CI/CD 環境を自分で整えたいときのための資料です。すぐに書き始めたい方は、必要になったところから参照してください。
:::

## Ruby のインストール

Vivlio Starter を動かすには Ruby が必要です。まだ入っていなければ、同梱のスクリプトで導入できます。

```bash
bin/install-ruby.zsh              # 対話的に最新安定版を導入
bin/install-ruby.zsh -y           # 確認をスキップして自動導入
bin/install-ruby.zsh -v 4.0.7     # バージョンを明示して導入
bin/install-ruby.zsh --no-bundler # bundler の導入をスキップ
```

スクリプトは Xcode Command Line Tools の確認と導入案内から始め、Homebrew、rbenv / ruby-build、Ruby 本体、bundler の順に準備します。Ruby の導入後は `rbenv global` も設定します。

:::{.memo}
**ターミナルの開き方（macOS）**

Spotlight から: `Cmd + Space` →「Terminal」と入力 → Enter。
Finder から: アプリケーション → ユーティリティ → Terminal.app。
[iTerm2](https://iterm2.com/)や[Warp](https://www.warp.dev/)などの代替ターミナルも利用できます。
:::

## Vivlio Starter のインストール

Ruby が使えるようになったら、Vivlio Starter の gem を入れます。

```bash
gem install vivlio-starter
```

PDF のアウトライン・しおり機能やデータ展開を使う場合は、対応する gem を追加します。どちらも必要になってから導入できます。

```bash
gem install vivlio-starter-pdf  # AGPL のため本体とは別 gem
gem install query-stream        # データ展開機能
```

## 自動インストールの内訳

`vs new mybook` の途中では `vs doctor --fix` が呼び出され、必要なツールを導入します。どのツールが何に使われるか、ここで確認できます。

| ツール | インストール方法 | 用途 |
| :--- | :--- | :--- |
| Xcode Command Line Tools | `xcode-select --install` | macOS のビルド基盤 |
| Homebrew | 公式インストーラ | macOS 用パッケージマネージャ |
| Node.js / npm | `brew install node` | Vivliostyle CLI の前提（Node 22.12 以上） |
| Vivliostyle CLI | `npm install -g @vivliostyle/cli` | PDF 生成エンジン |
| textlint と推奨ルール | `npm install -g textlint ...` | 文章校正。設定ファイルも `config/` に自動配置 |
| qpdf | `brew install qpdf` | PDF 分割・結合・ページ操作 |
| poppler（pdfinfo / pdftoppm） | `brew install poppler` | PDF メタデータ取得・ページ画像化 |
| Ghostscript | `brew install ghostscript` | PDF 圧縮 |
| ImageMagick | `brew install imagemagick` | 画像変換・WebP 変換 |
| Inkscape | `brew install inkscape` | SVG ラスタライズの予備経路（任意） |
| librsvg（rsvg-convert） | `brew install librsvg` | EPUB 扉絵・節絵の合成画像ラスタライズ |
| libvips | `brew install vips` | 高速画像処理 |
| Tesseract + 日本語データ | `brew install tesseract tesseract-lang` | OCR エンジン |
| MeCab | `brew install mecab mecab-ipadic` | 索引機能の読み自動推測 |
| rouge | `gem install rouge` | コードブロック言語推定 |
| mathjax-full | `npm install -g mathjax-full` | 数式の SVG 化 |
| mermaid-cli | `npm install -g @mermaid-js/mermaid-cli` | ダイアグラムの画像化 |
| `waifu2x-ncnn-vulkan` | GitHub Releases から自動取得 | AI 画像拡大（オプション） |
| Kindle Previewer（kindlepreviewer） | `brew install --cask kindle-previewer` ＋ ラッパー作成 | Kindle（KPF）変換（任意・targets: kindle 用） |
| Google Fonts 用 SSL 証明書 | 自動設定 | Google Fonts ダウンロード（macOS のみ） |

Xcode Command Line Tools と Homebrew を導入するときは確認が表示されます。対話せずに進めたい場合は `--yes` で省略できます。

Kindle Previewer を使う場合、Apple Silicon の Mac では **Rosetta 2 も必要**です。アプリは Apple Silicon に対応していますが、変換に使う部分には Intel 版が含まれます。Rosetta がないと `.kpf` への変換時に `bad CPU type in executable` と表示されます。`vs doctor` で導入状況を確認し、必要なら `sudo softwareupdate --install-rosetta --agree-to-license` を実行してください。

<!-- no-lint -->
**`vs doctor --fix` による自動インストールは、macOS と Homebrew の組み合わせに対応しています。** Linux と Windows は現時点で動作検証を行えておらず、公式のサポート対象外です。手動で環境を整えたい場合は、以降の手順をお使いの環境に読み替えてください。必要なツールが揃えば動作する見込みはありますが、手順や結果は環境によって異なります。

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

Homebrew を導入したら、使っている Mac に合わせて PATH を設定します。

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

rbenv install 4.0.7
rbenv global 4.0.7
ruby -v
```

4) Node.js

```bash
brew install node
node -v && npm -v
```

5) Vivliostyle CLI

```bash
npm install -g @vivliostyle/cli
vivliostyle --version
```

6) 外部ツール（PDF・画像処理）

```bash
brew install qpdf poppler ghostscript imagemagick inkscape librsvg vips
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

`mybook_v0.1.0.pdf` が生成されれば、基本的な動作を確認できています。

### Linux / WSL（Ubuntu / Debian の例）

1) 必要パッケージ

```bash
sudo apt-get update
sudo apt-get install -y build-essential curl git \
  qpdf ghostscript imagemagick poppler-utils librsvg2-bin \
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
rbenv install 4.0.7 && rbenv global 4.0.7
ruby -v
```

4) Vivliostyle CLI と Vivlio Starter

```bash
npm install -g @vivliostyle/cli mathjax-full @mermaid-js/mermaid-cli
gem install vivlio-starter
```

5) プロジェクト作成と動作確認

```bash
vs new mybook
cd mybook
vs build
```

画面のない環境では PDF ビューアーは自動で開きません。生成された `mybook_v0.1.0.pdf` を、別の環境に移すなどして確認してください。

### Windows

Windows では WSL2 と Ubuntu の組み合わせを推奨します。手順は上の「Linux / WSL」を参照してください。Windows ネイティブで試す場合は、次の導入例を手がかりにできます。

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
| `brew` が見つからない | Homebrew 未インストール | `vs doctor --fix` または[brew.sh](https://brew.sh)を参照 |
| `npm` が見つからない | Node.js 未インストール | `vs doctor --fix` で Node.js をインストール後、再実行 |
| Xcode CLT のインストールが完了しない | GUI 承認が必要 | インストーラ完了後に `vs doctor --fix` を再実行 |
| Homebrew の PATH が通らない（Apple Silicon） | `/opt/homebrew/bin` が PATH に未追加 | `echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile && source ~/.zprofile` |
| Ruby のバージョンが合わない | `.ruby-version` と不一致 | `rbenv install $(cat .ruby-version) && rbenv global $(cat .ruby-version)` |
| `bundler` が見つからない | bundler 未インストール | `gem install bundler` |
| Node.js の依存関係エラー | `node_modules` の不整合 | `rm -rf node_modules package-lock.json && npm install` |
| ImageMagick の WebP 変換が失敗 | WebP 非対応ビルド | `brew reinstall imagemagick` |
| Google Fonts の SSL エラーが解消しない | 証明書パスが未反映 | シェルを再起動して `SSL_CERT_FILE` が有効になっているか確認 |

:::{.tip}
**まず `vs doctor` を試してください**

ビルドや lint が急に失敗したら、まず `vs doctor` で不足しているツールを確認できます。macOS では `vs doctor --fix` で導入も試せます。使い分けは「環境の診断と更新」の章で説明しています。
:::

:::{.note}
**GitHub の 100MB 制約について**

GitHub には 100MB を超えるファイルを通常の Git でプッシュできません。生成する PDF の名前は `project.name` と `project.version` で決まり、`output.pdf.compress: true` の場合は末尾に `_compressed` が付きます。PDF をリポジトリに含めるなら、`.gitignore` の末尾に `!*.pdf` を追記します。容量が大きくなる場合は、リリースページへの添付や手元での保管も検討してください。
:::
