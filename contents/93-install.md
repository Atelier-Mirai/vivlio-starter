# インストール詳細

:::{.chapter-lead}
本章では、`vs new` が行う環境構築の内容、macOS 以外での手動インストール、CI/CD 環境の構築を補足します。通常の macOS 環境では、`vs new` を実行すれば執筆を始められます。
:::

## Ruby のインストール

Vivlio Starter は Ruby で動作します。Ruby が未インストールの場合は、同梱スクリプトを使う方法が手軽です。

```bash
bin/install-ruby.zsh              # 対話的に最新安定版を導入
bin/install-ruby.zsh -y           # 確認をスキップして自動導入
bin/install-ruby.zsh -v 4.0.6     # バージョンを明示して導入
bin/install-ruby.zsh --no-bundler # bundler の導入をスキップ
```

このスクリプトは、Xcode Command Line Tools の確認とインストール案内、Homebrew、rbenv / ruby-build、Ruby 本体、bundler の導入を順に行います。Ruby の導入後には `rbenv global` も設定します。

:::{.column}
**ターミナルの開き方（macOS）**

Spotlight から: `Cmd + Space` →「Terminal」と入力 → Enter。
Finder から: アプリケーション → ユーティリティ → Terminal.app。
[iTerm2](https://iterm2.com/)や[Warp](https://www.warp.dev/)などの代替ターミナルも利用できます。
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

`vs new mybook` を実行すると、内部で `vs doctor --fix` が呼び出され、次のツール群を自動インストールします。導入対象を確認するための一覧です。

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
| Inkscape | `brew install inkscape` | SVG ラスタライズの予備経路（任意） |
| librsvg（rsvg-convert） | `brew install librsvg` | EPUB 扉絵・節絵の合成画像ラスタライズ |
| libvips | `brew install vips` | 高速画像処理 |
| Tesseract + 日本語データ | `brew install tesseract tesseract-lang` | OCR エンジン |
| MeCab | `brew install mecab mecab-ipadic` | 索引機能の読み自動推測 |
| rouge | `gem install rouge` | コードブロック言語推定 |
| mathjax-full | `npm install -g mathjax-full` | 数式の SVG 化 |
| mermaid-cli | `npm install -g @mermaid-js/mermaid-cli` | ダイアグラムの画像化 |
| `waifu2x-ncnn-vulkan` | GitHub Releases から自動取得 | AI 画像拡大（オプション） |
| Kindle Previewer 3（kindlepreviewer） | `brew install --cask kindle-previewer` ＋ ラッパー作成 | Kindle（KPF）変換（任意・targets: kindle 用） |
| Google Fonts 用 SSL 証明書 | 自動設定 | Google Fonts ダウンロード（macOS のみ） |

Xcode Command Line Tools と Homebrew のインストール時だけは、確認プロンプトが表示されます。`--yes` オプションで省略できます。

<!-- no-lint -->
**自動インストール（`vs doctor --fix`）に対応しているのは macOS + Homebrew 環境だけです。** Linux と Windows は動作検証をしておらず、公式サポートの対象外です。必要なツールがそろえば動作する可能性はあるため、以降の手動インストール手順を環境に合わせて利用してください。対応状況は今後変わることがあります。

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

rbenv install 4.0.6
rbenv global 4.0.6
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

`mybook_v0.1.0.pdf` が生成されれば成功です。

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
rbenv install 4.0.6 && rbenv global 4.0.6
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

ヘッドレス環境では PDF ビューアーを自動起動しません。`mybook_v0.1.0.pdf` を任意のビューアーで確認してください。

### Windows

WSL2 + Ubuntu の利用を推奨します（上記の Linux / WSL の手順を参照）。以下はネイティブ環境で導入する場合の最小手順です。

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

:::{.column}
**まず `vs doctor` を試してください**

ビルドや lint が失敗したときは、まず `vs doctor` で環境を診断してください。不足ツールが一覧表示されます。`vs doctor --fix` では自動修復も試せます。詳細は「環境の診断と更新」の章を参照してください。
:::

:::{.column}
**GitHub の 100MB 制約について**

大きな PDF は Git にプッシュできません。ファイル名は `project.name` と `project.version` で決まり、`output.pdf.compress: true` のときは末尾に `_compressed` が付きます。リポジトリに PDF を含める場合は、`.gitignore` の末尾に `!*.pdf` を追記してください。容量が気になる場合は、成果物をリリースページへ添付するか、手元で管理します。
:::
