# インストール

:::{.chapter-lead}
この章では、vivlio-starter gemのインストール手順を詳しく説明します。

vivlio-starterを活用するための最初のステップとして、適切な環境構築とセットアップは非常に重要です。この章では、以下の内容を順を追って説明します：

- 必要なソフトウェアとバージョンの確認方法
- gemのインストール手順と依存関係の解決
- 新規プロジェクトの作成と初期設定
- インストール後の動作確認方法

各手順には、トラブルシューティングのヒントも併せて記載しています。特に初めての方は、順を追って進めることでスムーズに環境構築が行えるでしょう。

**注意**: 本ガイドでは、macOSを前提とした手順を記載しています。他のOSをご利用の場合は、適宜読み替えてください。
:::



## インストール手順

:::{.section-lead}
このセクションでは、vivlio-starterを利用するために必要なソフトウェアのインストール手順を説明します。
:::

### 1. 必要なソフトウェアのインストール

#### 開発者ツール（Xcode Command Line Tools）のインストール
Homebrew や一部ネイティブ拡張のビルドに必要です（未導入なら実行してください）。

```bash
xcode-select --install
```

#### Rubyのインストール
vivlio-starterはRubyで書かれたgemです。以下の手順で最新のRubyをインストールしてください。

1. **Homebrew**（macOSのパッケージマネージャー）がインストールされていない場合は、以下のコマンドでインストールします：
   ```bash
   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
   ```

2. **rbenv**（Rubyのバージョン管理ツール）をインストールします：
   ```bash
   brew install rbenv ruby-build
   ```

3. 必要なRubyのバージョンをインストールします（最新の安定版3.4.4を指定）：
   ```bash
   rbenv install 3.4.4
   rbenv global 3.4.4
   ```

4. インストールが完了したら、ターミナルを再起動して以下のコマンドで確認します：
   ```bash
   ruby -v
   ```

#### Node.jsのインストール
VivliostyleのビルドプロセスにはNode.jsが必要です。LTS（推奨: 20系）を利用してください。

```bash
# Homebrew のセットアップ（未設定の場合。Apple Silicon は /opt/homebrew）
echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile  # Apple Silicon(M1/M2/M3)
echo 'eval "$(/usr/local/bin/brew shellenv)"' >> ~/.zprofile    # Intel Mac（必要時）
eval "$([ -x /opt/homebrew/bin/brew ] && /opt/homebrew/bin/brew shellenv || /usr/local/bin/brew shellenv)"

# Node.js（LTS推奨）をインストール
brew install node@20 || brew install node

# 確認
node -v
npm -v
```

### 2. Vivliostyle CLIのインストール

Vivliostyle CLIをグローバルにインストールします：

```bash
npm install -g @vivliostyle/cli

# インストールを確認
vivliostyle --version
```

### 3. vivlio-starter gemのインストール

必要なソフトウェアのインストールが完了したら、以下のコマンドでvivlio-starter gemをインストールします：

```bash
gem install vivlio-starter
```

### 4. 新規プロジェクトの作成

新しいプロジェクトを作成するには、以下のコマンドを実行します：

```bash
vivlio-starter new プロジェクト名
cd プロジェクト名
```

### 5. 依存関係のインストール

プロジェクトディレクトリに移動し、必要な依存関係をインストールします：

```bash
bundle install
npm install
```

#### 補足: 追加のツールについて

vivlio-starter のビルドでは、以下のツールが必要/推奨です：

- **HexaPDF** (Ruby gem): PDF の最適化・圧縮（Gem として自動導入）
- **qpdf**: PDF の結合・分割（`qpdf` コマンド）
- **Ghostscript**: PDF の最適化（`gs` コマンド）
- **ImageMagick**: 画像処理（`convert` など、WebP 変換を含む）

これらのうちシステムレベルの依存関係（qpdf/Ghostscript/ImageMagick）は自動では入りません。未インストールの場合は、次で導入してください：

```bash
# macOS の場合
brew install qpdf ghostscript imagemagick

# Ubuntu/Debian の場合
# sudo apt-get install -y qpdf ghostscript imagemagick
```

### 6. 動作確認

事前にバージョンを確認し、PATH やインストールの不備がないかチェックします：

```bash
ruby -v
node -v && npm -v
vivliostyle --version
vs --help && vs --version
```

その後、ビルドが正常に行えるか確認します：

```bash
vs build
```

問題がなければ、`output.pdf` が生成されます。macOS の場合は PDF がプレビューアプリにより自動表示されます。(プレビューアプリを閉じた場合には、`vs open` で再表示できます。)

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
  brew install qpdf ghostscript imagemagick
  # それでも見つからない場合はシェルの PATH を見直してください
  echo $PATH
  ```

- **Homebrew の PATH 問題（Apple Silicon）**：
  `/opt/homebrew/bin` が PATH に含まれているか確認。
  ```bash
  echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
  eval "$([ -x /opt/homebrew/bin/brew ] && /opt/homebrew/bin/brew shellenv)"
  ```

- **ImageMagick の WebP 変換で失敗**：
  ImageMagick が WebP 対応でビルドされていない可能性があります。`magick -version` 出力に `webp` が含まれるか確認し、含まれない場合は再インストールしてください。
  ```bash
  magick -version | grep -i webp || brew reinstall imagemagick
  ```

---
## 補足: Linux/WSL 環境

- **パッケージ導入（Debian/Ubuntu）**
  ```bash
  sudo apt-get update
  sudo apt-get install -y build-essential curl git \
    qpdf ghostscript imagemagick poppler-utils
  ```
- **Node.js（LTS）**: nvm 推奨。
  ```bash
  curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
  source ~/.nvm/nvm.sh
  nvm install --lts
  node -v && npm -v
  ```
- **Ruby**: rbenv 推奨。
  ```bash
  sudo apt-get install -y libssl-dev libreadline-dev zlib1g-dev
  curl -fsSL https://github.com/rbenv/rbenv-installer/raw/main/bin/rbenv-installer | bash
  export PATH="$HOME/.rbenv/bin:$PATH" && eval "$(rbenv init - bash)"
  rbenv install 3.4.4 && rbenv global 3.4.4
  ruby -v
  ```
- **ImageMagick の WebP**: `convert -list format | grep -i webp` で対応可否を確認。未対応なら配布版やソースビルドを検討。
- **ファイル権限**: Git 取得物に実行権限が必要な場合は `chmod +x bin/*` を実行。

### Windows の場合
- **推奨**: WSL2 + Ubuntu（上記 Linux 手順を適用）。
- **ネイティブ Windows（代替）**:
  - パッケージマネージャ: Chocolatey または Scoop
  - 例（Chocolatey）:
    ```powershell
    choco install -y git ruby nodejs-lts qpdf ghostscript imagemagick
    ```
  - PowerShell 実行ポリシー: 必要に応じて管理者で `Set-ExecutionPolicy RemoteSigned`。
  - 文字コード: 端末は UTF-8（`chcp 65001`）を推奨。

## CI（GitHub Actions）でのビルド例
簡易的な PDF ビルド（macOS と Ubuntu の matrix）。プロジェクトルートに `.github/workflows/build.yml` を作成して利用します。

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
          ruby-version: '3.4'
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
          rake build
      - uses: actions/upload-artifact@v4
        with:
          name: pdf
          path: output.pdf
