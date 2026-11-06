# インストール詳細

:::{.chapter-lead}
@chapref:ch-workflow で実行した導入スクリプトの処理の内訳、執筆に使うツールの一覧、インストールで起きる問題の解決策をまとめます。インストールした内容を確かめたいときや、導入スクリプトを使わずにインストールしたいときに参照してください。
:::

## 導入スクリプトの処理

導入スクリプトは、次の順に処理を進めます。尋ねることは最初にまとめてあるので、確認が済めば、終わるまで席を外して構いません。

1. インストールの確認と、管理者のパスワードの入力
2. Homebrew のインストール（Xcode Command Line Tools を含む）
3. Kindle Previewer と Rosetta 2 のインストール（確認で選んだときだけ）
4. Ruby の準備（次の表）と bundler のインストール
5. シェルの設定ファイルへの書き込み
6. Vivlio Starter と拡張機能 vivlio-starter-pdf のインストール
7. 執筆に使うツールのインストール（`vs doctor --fix`。内訳は次の節）
8. 新しいシェルへの切り替え（同じウィンドウのまま `vs` を使える）

Ruby は、今使っている Ruby に合わせて用意します。

| 今の Ruby | 扱い |
| :--- | :--- |
| 3.4 以上 | そのまま使う |
| ない・macOS 付属の 2.6・rbenv の古い版 | rbenv で最新の安定版をインストールし、既定に切り替える |
| Homebrew の古い Ruby | 確かめてから `brew upgrade ruby` で更新する |
| mise・rvm・asdf の古い Ruby | そのツールでの更新方法を示して処理を中止する |

シェルの設定ファイルには、新しいターミナルで Homebrew と Ruby を使うための行を書きます。Homebrew の設定は `~/.zprofile` に書きます。rbenv の設定は、`~/.zshrc` にすでに rbenv の記述があればそちらに、無ければ `~/.zprofile` に書きます。Homebrew の Ruby を使う場合は、gem がインストールするコマンドの置き場所を PATH に追加する行も書きます。同じ設定がすでにあれば、追加しません。

オプションは、末尾に `install` と続けて渡します。

| オプション | 説明 |
| :--- | :--- |
| `-y` | 確認をスキップしてインストール |
| `-v 4.0.9` | 指定した版の Ruby を rbenv でインストール |

次の例は、確認をスキップしてインストールします。

```bash
zsh -c "$(curl -fsSL https://raw.githubusercontent.com/Atelier-Mirai/vivlio-starter/master/bin/install.zsh)" install -y
```

実行する前にスクリプトの中身を確かめたいときは、`install.zsh` で終わる URL を Web ブラウザで開きます。

## 手動でインストールする

Ruby 3.4 以上がすでにあれば、gem だけをインストールします。

```bash
gem install vivlio-starter vivlio-starter-pdf
```

執筆に使うツールは、最初の `vs new` が `vs doctor --fix` でインストールします。Xcode Command Line Tools や Homebrew がインストールされていなければ、インストールの確認が表示されます。

vivlio-starter-pdf は、PDF にしおりを付け、`vs pdf:read` で画像の抽出と OCR を行う拡張機能です。インストールしなくても、それ以外の処理はすべて動きます。

Ruby がインストールされていないときは、Homebrew と rbenv で Ruby をインストールしてから、上の `gem install` を実行します。

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
source ~/.zprofile

brew install rbenv ruby-build
echo 'eval "$(rbenv init - zsh)"' >> ~/.zprofile
source ~/.zprofile
rbenv install 4.0.9
rbenv global 4.0.9
```

Intel の Mac では、2 行目の `/opt/homebrew` を `/usr/local` に読み替えます。

インストールが済んだら、本のプロジェクトを作って組んでみます。

```bash
vs new mybook
cd mybook
vs build
```

`mybook_v0.1.0.pdf` が生成されれば、インストールは完了です。

## 自動インストールの内訳 @install-tools

導入スクリプトと `vs new mybook` の最後では `vs doctor --fix` が呼び出され、必要なツールをインストールします。どのツールが何に使われるか、ここで確認できます。

| ツール | インストール方法 | 用途 |
| :--- | :--- | :--- |
| Xcode Command Line Tools | `xcode-select --install` | macOS のビルド基盤 |
| Homebrew | 公式インストーラ | macOS 用パッケージマネージャ |
| Node.js / npm | `brew install node` | Vivliostyle CLI の前提（Node 22.12 以上） |
| Vivliostyle CLI | `npm install -g @vivliostyle/cli` | PDF 生成エンジン |
| VFM | `npm install -g @vivliostyle/vfm` | Markdown から HTML への変換 |
| textlint と推奨ルール | `npm install -g textlint ...` | 文章校正 |
| qpdf | `brew install qpdf` | PDF 分割・結合・ページ操作 |
| poppler（pdfinfo / pdftoppm / pdftotext） | `brew install poppler` | PDF メタデータ取得・ページ画像化・しおりの位置の特定 |
| Ghostscript | `brew install ghostscript` | PDF 圧縮 |
| ImageMagick | `brew install imagemagick` | 画像変換・WebP 変換 |
| Inkscape | `brew install --cask inkscape` | SVG ラスタライズの予備経路（任意） |
| librsvg（rsvg-convert） | `brew install librsvg` | 表紙・EPUB の扉絵と節絵の SVG ラスタライズ |
| libvips | `brew install vips` | `vs pdf:read` の OCR の画像処理（vivlio-starter-pdf を使うとき） |
| Tesseract + 日本語データ | `brew install tesseract tesseract-lang` | `vs pdf:read` の OCR（vivlio-starter-pdf を使うとき） |
| MeCab | `brew install mecab mecab-ipadic` | 索引の読みの推測・交ぜ書きの検出 |
| mathjax-full | `npm install -g mathjax-full` | 数式の SVG 化 |
| mermaid-cli | `npm install -g @mermaid-js/mermaid-cli` | ダイアグラムの画像化 |
| Guesslang | `npm install -g @vscode/vscode-languagedetection` | `vs lint` でのコードブロックの言語推定 |
| `waifu2x-ncnn-vulkan` | GitHub Releases から自動取得 | 扉絵・節絵の画像の拡大（任意） |
| Kindle Previewer（kindlepreviewer） | `brew install --cask kindle-previewer`（Kindle を選んだときだけ） | Kindle（KPF）変換（任意・targets: kindle 用） |
| Google Fonts 用 SSL 証明書 | 自動設定 | Google Fonts ダウンロード |

`config/book.yml` の `targets` に `kindle` がある本では、`vs doctor --fix` が Kindle Previewer をインストールします。導入スクリプトの確認で選んだ場合は、その時点でインストールされます。Apple Silicon の Mac には、変換に使う **Rosetta 2** も一緒にインストールします。どちらも、インストールの際に管理者のパスワードを入力します。インストール後は、アプリの更新機能で新しい版へ更新されます。

## トラブルシューティング @install-troubleshooting

ビルドや lint が急に失敗したら、まず `vs doctor` で不足しているツールを確かめてください。`vs doctor --fix` で、不足しているツールをインストールできます。使い分けは @chapref:ch-doctor で説明しています。

:::{.long-table}
| 症状 | 原因 | 解決策 |
| :--- | :--- | :--- |
| `vs` を実行すると `ERROR Error: No input is set.` と出る | Vivliostyle CLI がインストールする同じ名前の `vs` が実行されている | `vivlio-starter doctor --fix` を実行（Vivliostyle の `vs` を削除します。Vivliostyle は `vivliostyle` で使えます） |
| 導入スクリプトのあと、新しいターミナルで `vs` が見つからない | シェルの設定ファイルへの書き込みを断った | スクリプトが最後に示した行を設定ファイルに追加し、新しいターミナルを開く |
| Google Fonts の SSL エラーが解消しない | 証明書の設定が、開いているターミナルに反映されていない | 新しいターミナルを開き、`vs doctor` を再実行 |
:::
