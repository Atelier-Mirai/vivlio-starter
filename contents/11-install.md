# インストール

:::{.chapter-lead}
この章では、Vivlio Starter gemのインストール手順を詳しく説明します。

Vivlio Starterを活用するための最初のステップとして、適切な環境構築とセットアップは非常に重要です。この章では、次の内容を順を追って説明します：

- 必要なソフトウェアとバージョンの確認方法
- gemのインストール手順と依存関係の解決
- 新規プロジェクトの作成と初期設定
- インストール後の動作確認方法

各手順には、トラブルシューティングのヒントも併せて記載しています。とくにはじめての方は、順を追って進めることでスムーズに環境構築が行えるでしょう。

**注意**: 本ガイドでは、macOSを前提とした手順を記載しています。他のOSをご利用の場合は、適宜読み替えてください。
:::




## 簡単インストール（推奨）
:::{.section-lead}
このセクションでは、Vivlio Starterを利用するために必要なソフトウェアのインストール手順を説明します。
:::

### Rubyのインストール
Vivlio StarterはRubyで書かれたgemです。お使いのコンピューターにRubyがインストールされていない場合には、次の手順で最新のRubyをインストールしてください。

補足（簡単・推奨）: スクリプトによる自動セットアップ
Rubyなどの導入は、同梱のスクリプト `bin/install-ruby.zsh` を使うと簡単・安全に行えます。
Homebrewとrbenv/Ruby-buildの導入、Ruby本体のインストールと `rbenv global` 設定、bundlerの導入まで一括で対応します。
さらに、Xcode Command Line Toolsの有無を検出し、未導入ならインストーラー起動を案内します。最新安定版の自動判定に対応し、対話/無人（`-y`）どちらの実行形態も選べます。

macOSでターミナルを開くには:

 - Spotlightから: Cmd + Space →「Terminal」と入力 → Enter
 - Finderから: アプリケーション > ユーティリティ > Terminal.appを起動
 - 代替ターミナル: [iTerm2](https://iterm2.com/) や [Warp](https://www.warp.dev/) なども利用可能です。

```bash
# 対話的に最新安定版を導入
bin/install-ruby.zsh

# 完全自動（確認なし）で導入
bin/install-ruby.zsh -y

# 明示的に最新安定版を指定
bin/install-ruby.zsh -v latest

# 特定バージョンを指定（例）
bin/install-ruby.zsh -v 3.3.5
```

### Vivlio Starterの導入
Rubyの準備ができたら、次のコマンドで `vivlio-starter` をインストールしてください。

```bash
gem install vivlio-starter
```

### 新規プロジェクトの作成と必要ツールの自動診断・導入
`vivlio-starter` の導入が完了したら、次のコマンドで新規プロジェクトを作成してください。
書籍作成の為の必要ツールを自動診断・導入します。

<small>(注: `mybook` はサンプルのプロジェクト名です。任意の名前に置き換えてください。)</small>

```bash
vs new mybook                       # 新規プロジェクトを作成（必要ツールを自動導入）
vs new mybook --interactive         # 必要ツールのインストールを対話的に確認しながら実行する
```

これで、インストール完了です。すぐにPDFを生成できます（デフォルト設定の場合）。

```bash
cd mybook # プロジェクトルートに移動

vs build  # PDF を生成
```

`output.pdf` が生成され、自動で表示されます。


#### 必要ツール一覧

次のツール群が、`vs new` コマンドで自動導入されます。
 - Xcode Command Line Tools（未導入ならインストーラー起動と完了待機）
   - 概要: Apple純正の開発用コマンドラインツール群（コンパイラやビルド関連の基盤）。
   - 用途: Homebrewやrbenvでのビルド・インストールに必要。PDF/画像処理ツール群の導入を安定させます。
 - Homebrewが未導入なら自動インストール（確認あり。`-y` で省略）
   - 概要: macOS用パッケージマネージャー。
   - 用途: Node.jsやqpdf, poppler, Ghostscript, ImageMagickなどの外部依存を自動導入します。
 - Node.js（node@20優先）/ npmの導入
   - 概要: JavaScript実行環境とパッケージマネージャー（npm）。
   - 用途: Vivliostyle CLIの実行に必須。テンプレートのフロントエンド依存やビルド支援スクリプトの実行にも使用します。
 - Vivliostyle CLI（`npm install -g @vivliostyle/cli`）の導入
   - 概要: CSS組版エンジンVivliostyleを操作するコマンドラインツール。
   - 用途: Markdown/HTML+CSSからPDFを生成する中核。`vs build` 内部で呼び出されます。
 - qpdf / poppler（pdfinfo）/ Ghostscript / ImageMagickの導入
   - 概要: PDF/画像処理のユーティリティ群。
   - 用途: qpdfはPDFの分割・結合・ページ抽出等、pdfinfo（poppler）はページ数取得、GhostscriptはPDF圧縮、ImageMagickは画像の変換・最適化（WebP変換やリサイズ等）に使用します。

```bash
vs new mybook --manual-install      # 必要ツールは手動で導入する
```
`--manual-install` を選んだ場合は、下の「必要ツールの手動インストール」を実行してからビルドしてください。


<!-- 注: 本書では初学者向けに `vs` を使用します[^bin-vs]。

[^bin-vs]: 中級者・上級者向けの補足。プロジェクト直下の `bin/vs` は、このリポジトリ（またはテンプレート）のローカルコードを直接呼び出すランチャーです。フォーク／クローンしてローカルで開発していて、`lib/` の修正を即座に反映して動作確認したい場合に便利です。PATH/gem の影響を避けたい場合にも便利です。通常利用や初学者は、`gem install vivlio-starter` 後に PATH から呼べる `vs` を使うのが簡単で確実です。 -->



## 完全手動インストール（スクリプト非使用）
:::{.section-lead}
以降は、スクリプト（`bin/install-ruby.zsh` や `vs doctor --fix`）を使わずに、自分で環境を整えるための最短手順です。
:::

### A. macOS（推奨フロー）
1) 開発者ツール（Xcode Command Line Tools）
```bash
xcode-select --install
```

2) Homebrew（未導入なら）
```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```
インストール後、必要に応じてPATHを設定（zsh）：
```bash
echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile   # Apple Silicon
echo 'eval "$(/usr/local/bin/brew shellenv)"' >> ~/.zprofile      # Intel（必要時）
source ~/.zprofile
```

3) Ruby（rbenvでユーザーインストール）
```bash
brew install rbenv ruby-build
echo 'export PATH="$HOME/.rbenv/bin:$PATH"' >> ~/.zprofile
echo 'eval "$(rbenv init - zsh)"' >> ~/.zprofile
source ~/.zprofile

# 利用可能バージョンの確認（参考）
rbenv install -l | tail

# 最新安定版（例 3.x.y）をインストール
rbenv install 3.x.y
rbenv global 3.x.y
ruby -v
```

4) Node.js（LTS 20系を推奨）
```bash
brew install node@20 || brew install node
node -v
npm -v
```

5) Vivliostyle CLI（グローバル）
```bash
npm install -g @vivliostyle/cli
vivliostyle --version
```

6) 外部コマンド（PDF/画像処理）
```bash
brew install qpdf poppler ghostscript imagemagick
```
補足: `poppler` に含まれる `pdfinfo` を `BuildHelpers.page_count()` が利用します。
補足: PDF圧縮はGhostscript（pdfwrite）を使用します。qpdfは分割/結合のために利用します。
補足: HexaPDFはgem依存として自動導入されるため、`vs doctor` の対象外です。

7) Vivlio Starter（gem）
```bash
gem install vivlio-starter
vs --version
```

8) 新規プロジェクト作成と依存の取得
```bash
vs new mybook
cd mybook
bundle install
npm install
```

9) 動作確認
```bash
vs build
```
`output.pdf` が生成されれば成功です。

#### B. Linux/WSL（Ubuntu/Debian の例）
1) 必要パッケージ
```bash
sudo apt-get update
sudo apt-get install -y build-essential curl git \
  qpdf ghostscript imagemagick poppler-utils
```
2) Node.js（LTSはnvm推奨）
```bash
curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
source ~/.nvm/nvm.sh
nvm install --lts
node -v && npm -v
```
3) Ruby（rbenv推奨）
```bash
sudo apt-get install -y libssl-dev libreadline-dev zlib1g-dev
curl -fsSL https://github.com/rbenv/rbenv-installer/raw/main/bin/rbenv-installer | bash
export PATH="$HOME/.rbenv/bin:$PATH" && eval "$(rbenv init - bash)"
rbenv install 3.4.4 && rbenv global 3.4.4
ruby -v
```
4) Vivliostyle CLIとVivlio Starter
```bash
npm install -g @vivliostyle/cli
gem install vivlio-starter
```
5) プロジェクト作成と依存
```bash
vs new mybook
cd mybook
bundle install
npm install
vs build
```

ヘッドレス環境等ではPDFビューアーの自動起動は行われません。`output.pdf` を任意のビューアーで確認してください。

### C. Windows（ネイティブの代替手順）
原則としてWSL2 + Ubuntuの利用を推奨します（上記Bを参照）。どうしてもネイティブで行う場合の最小手順です。

1) Chocolateyの場合（管理者PowerShell）
```powershell
choco install -y git ruby nodejs-lts qpdf ghostscript imagemagick poppler
```

2) Scoopの場合（PowerShell）
```powershell
set-executionpolicy RemoteSigned -scope CurrentUser
iwr -useb get.scoop.sh | iex
scoop bucket add main
scoop install git ruby nodejs-lts qpdf ghostscript imagemagick poppler
```

3) Vivliostyle CLIとVivlio Starter（共通）
```powershell
npm install -g @vivliostyle/cli
gem install vivlio-starter
```

4) 動作確認（PowerShell）
```powershell
vivliostyle --version
vs --version
```

### トラブルシューティング

- **Rubyのバージョンが合わない場合**：
  `.ruby-version` ファイルを確認し、インストール済みバージョンと一致させてください。

- **bundler が見つからない場合**：
  ```bash
  gem install bundler
  ```

- **Node.js の依存関係でエラーが発生した場合**：
  ```bash
  rm -rf node_modules package-lock.json
  npm cache clean --force
  npm install
  ```

- **qpdf/gs/convert が見つからない（command not found）**：
    ```bash
    # まずは自動導入を試す
    vs doctor --fix
    # 手動で導入する場合は Homebrew
    brew install qpdf ghostscript poppler imagemagick
    # 圧縮は Ghostscript 固定（qpdf は分割/結合用）
    # それでも見つからない場合はシェルの PATH を見直してください
    echo $PATH
    ```

- **Homebrew の PATH 問題（Apple Silicon）**：
  `/opt/homebrew/bin` がPATHに含まれているか確認。
  ```bash
  echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
  eval "$([ -x /opt/homebrew/bin/brew ] && /opt/homebrew/bin/brew shellenv)"
  ```

- **ImageMagick の WebP 変換で失敗**：
  ImageMagickがWebP対応でビルドされていない可能性があります。`magick -version` 出力に `webp` が含まれるか確認し、含まれない場合は再インストールしてください。
  ```bash
  magick -version | grep -i webp || brew reinstall imagemagick
  ```

- **ファイル権限の問題（macOS/Linux）**：
  Gitから取得したスクリプトに実行権限がない場合は付与してください。
  ```bash
  chmod +x bin/*
  ```

## CI（GitHub Actions）でのビルド例

:::{.section-lead}
簡易的なPDFビルド（macOSとUbuntuのmatrix）。プロジェクトルートに `.github/workflows/build.yml` を作成して利用します。
:::

補足:
- チーム開発で有益: プルリクごとに自動ビルドされたPDFを共有でき、レビューや回regressの検出が容易になります（同一手順・同一環境で再現性も確保）。
- GitHubの100MB制約: 大きなPDFはpushできません。CIで圧縮版を生成・アップロードすることを推奨します。
  - vs buildの圧縮オプション:
    - デフォルトで圧縮を実行します。スキップしたい場合は `vs build --no-compress`。
    - 圧縮後のデフォルトファイル名は `output_compressed.pdf`。`config.yml` の `pdf.output_file_compressed` で変更可。
    - 圧縮エンジンはGhostscriptを用いています（理由: qpdfは再圧縮で効果が乏しいケースが多く、GS（pdfwrite）の方が安定して圧縮率を得やすいため）。
    - 既存PDFを後から圧縮する場合は `vs pdf:compress` を使用（内部でGhostscriptを使用）。

  - Ghostscriptで圧縮:
    ```bash
    # 透明度保持のため `-dCompatibilityLevel=1.7` を指定しています（`vs pdf:compress` の実装と同一）。
    gs -sDEVICE=pdfwrite -dCompatibilityLevel=1.7 -dPDFSETTINGS=/ebook \
      -dNOPAUSE -dQUIET -dBATCH -sOutputFile=output_compressed.pdf output.pdf
    ```
- アーティファクト名や公開用パスは（デフォルト名）`output_compressed.pdf` を推奨します。
- .gitignoreでPDFを許可: リポジトリにPDFを含める場合は、`.gitignore` の無視設定を調整（例: 末尾に `!*.pdf` を追加）してください。

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
      - uses: Ruby/setup-Ruby@v1
        with:
          Ruby-version: '3.4'
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
      - name: Build
        run: |
          vs build
      - uses: actions/upload-artifact@v4
        with:
          name: PDF
          path: output_compressed.pdf
```
<!-- 
## WindSurf のインストール

:::{.section-lead}
WindsurfはAI支援のモダンなコードエディターです。ドキュメント中心のプロジェクトでも、内蔵ターミナルやAIペアプロで効率よく作業できます。
:::

### 特長（抜粋）
- 内蔵AIアシスタント（Cascade）によるコード/ドキュメント編集支援
- VS Codeに近いUI/拡張互換の操作感（ショートカットも類似）
- 統合ターミナルから `vs build` などのコマンドを即実行可能

### インストール（macOS）
1) 公式サイトから最新のインストーラーをダウンロードしてインストール
   - 参考: https://codeium.com/windsurf
2) 初回起動時にサインイン（GitHub/Googleなど）
3) 必要に応じて日本語フォント/表示倍率を調整（設定 > Appearance）
   - 拡張機能: Markdownのシンタックスハイライトを有効にすると便利です（設定/拡張機能からMarkdown関連を有効化）。
   - 内蔵ターミナル: メニューのView > Terminalから開けます（ショートカット: Cmd+`、Windows/Linux は Ctrl+`）。

### 本プロジェクトでの使い方
- プロジェクトを開く:「Open Folder」から本リポジトリのルートを選択
- 統合ターミナルを開く: Cmd+`（Windows/Linux は Ctrl+`）
- ビルド: ターミナルで `vs build` を実行
- 依存の診断/導入: `vs doctor --fix`
- GitHub Actionsの確認: `.github/workflows/build.yml` を開き、必要に応じて編集

ヒント: ターミナルのシェルがzshでPATHが正しく通っているか確認してください（`vs --version` が表示されればOK）。 -->
