# 環境診断（vs doctor）

:::{.chapter-lead}
Vivlio Starter の動作には、いくつかの外部ツールが必要です。`vs doctor` コマンドを使うと、必要なツールがすべて揃っているかを一括で確認できます。不足しているツールがあれば、`--fix` オプションで自動インストールも可能です。
:::

## vs doctor とは

:::{.section-lead}
`vs doctor` は、Vivlio Starter が依存する外部ツールの存在を診断するコマンドです。ビルドや lint が突然失敗したとき、まず `vs doctor` を実行するのが近道です。
:::

新しい環境でプロジェクトを始めるときや、コマンドが予期せず失敗するときに実行してください。不足しているツールを一覧で確認できます。

なお、Vivlio Starter gem 自体のインストール手順や Ruby 環境の構築については、「インストール」の章を参照してください。

### 診断対象ツール

| ツール | 用途 |
|--------|------|
| Xcode Command Line Tools | macOS のビルドツールチェーン（macOS のみ） |
| node / npm | JavaScript ランタイム（Vivliostyle CLI の前提） |
| vivliostyle | PDF 生成エンジン |
| textlint | 文章校正ツール |
| qpdf | PDF 分割・結合・ページ操作 |
| pdfinfo (poppler) | PDF メタデータ取得 |
| gs (Ghostscript) | PDF 圧縮 |
| imagemagick | 画像変換・リサイズ |
| inkscape | SVG 編集・変換（カバー生成用） |
| vips (libvips) | 高速画像処理 |
| tesseract | OCR エンジン |
| tesseract 日本語データ | Tesseract の日本語学習データ |
| mecab | 索引機能の読み自動推測 |
| playwright | バックリンク重複排除用 |
| chromium | Playwright 用ヘッドレスブラウザ |
| rouge | コードブロック言語推定（Ruby gem） |
| waifu2x-ncnn-vulkan | AI 画像拡大（オプション） |
| Google Fonts 用 SSL 証明書 | Google Fonts ダウンロード（macOS のみ） |

## 基本的な使い方

:::{.section-lead}
`vs doctor` は診断のみ、`vs doctor --fix` は診断＋自動インストールです。まず診断だけ実行して状況を確認するのがおすすめです。
:::

### 診断のみ実行

```bash
vs doctor
```

不足しているツールを検出して一覧表示します。インストールは行いません。

```
🔎 環境診断を開始します…
✅ Xcode Command Line Tools: OK
✅ node: OK
✅ textlint: OK
✅ vivliostyle: OK
✅ qpdf: OK
❌ pdfinfo: 見つかりません
✅ gs: OK
✅ imagemagick: OK
…
不足しているツール: pdfinfo (poppler)
ヒント: macOS の場合は `vs doctor --fix` で自動インストールを試行できます
```

### 自動インストール（--fix）

```bash
vs doctor --fix
```

診断後、不足しているツールを自動インストールします。macOS では Homebrew 経由でインストールします。Homebrew 自体や Xcode Command Line Tools が未インストールの場合は、インストール前に確認プロンプトが表示されます。

Node.js（node@20 優先）も自動インストールの対象です。vivliostyle や textlint など npm に依存するツールは、Node.js のインストール後に続けてインストールされます。

```
🛠 Homebrew による不足ツールのインストールを実行します…
🔁 インストール後の再診断…
✅ すべてのツールがインストールされました
```

### 確認プロンプトをスキップ（--yes）

```bash
vs doctor --fix --yes
```

`--yes`（または `-y`）は `--fix` と組み合わせて使うオプションです。Xcode Command Line Tools や Homebrew のインストール確認をスキップして、すべて自動で進めます。CI/CD 環境や自動セットアップスクリプトで活用できます。

## コマンドオプション

```
doctor [--fix [--yes/-y]] [-h/--help]
```

| オプション | 説明 |
|------------|------|
| `--fix` | 不足ツールを自動インストール（一部確認あり） |
| `--yes` / `-y` | 確認プロンプトをスキップ（`--fix` 指定時のみ有効） |
| `-h` / `--help` | ヘルプを表示 |

## 自動インストールの対応範囲

:::{.section-lead}
`--fix` による自動インストールは macOS + Homebrew 環境でのみ対応しています。Linux や Windows では手動セットアップが必要です。
:::

macOS では以下の方法でインストールします。

| 種類 | インストール方法 | 備考 |
|------|----------------|------|
| Xcode Command Line Tools | `xcode-select --install` | 確認あり |
| Homebrew（未導入の場合） | 公式インストーラ | 確認あり |
| node / qpdf / pdfinfo / gs / imagemagick / inkscape / vips / tesseract / mecab など | `brew install` | |
| vivliostyle | `npm install -g @vivliostyle/cli` | node が前提 |
| textlint と推奨ルール | `npm install -g textlint ...` | 日本語技術書向けルールセットを一括インストール。設定ファイルも `config/` に自動配置 |
| playwright / chromium | `npm install playwright` / `npx playwright install chromium` | node が前提 |
| rouge | `gem install rouge` | |
| waifu2x-ncnn-vulkan | GitHub Releases から自動ダウンロード | |

各ツールの詳細なインストール方法や最新の手順については、各ツールの公式サイトや最新のドキュメントを参照してください。ツールのバージョンや手順は変わることがあるため、公式情報や AI アシスタントで確認するのが確実です。

## 実行例

### 新しい Mac でセットアップする

```bash
# まず診断して何が必要か確認
vs doctor

# 不足ツールをまとめてインストール
vs doctor --fix
```

### CI/CD 環境でセットアップする

```bash
# 確認プロンプトをすべてスキップして自動インストール
vs doctor --fix --yes
```

### ビルドが失敗したときのトラブルシューティング

```bash
# 環境を診断して原因を特定
vs doctor
```

## トラブルシューティング

| 症状 | 原因 | 解決策 |
|------|------|--------|
| `brew` が見つからない | Homebrew 未インストール | `vs doctor --fix` で自動インストール、または [https://brew.sh](https://brew.sh) を参照 |
| `npm` が見つからない | node 未インストール | `vs doctor --fix` で node をインストール後、再実行 |
| Xcode CLT のインストールが完了しない | GUI 承認が必要 | インストーラの完了後に `vs doctor --fix` を再実行 |
| playwright / chromium が自動インストールされない | node が新規インストールされた場合は再実行が必要 | `vs doctor --fix` を再度実行 |
| waifu2x が Linux / Windows で自動インストールされない | macOS のみ対応 | 各ツールの公式サイトを参照して手動インストール |
| Google Fonts の SSL エラーが解消しない | 証明書パスが未反映 | シェルを再起動して `SSL_CERT_FILE` が有効になっているか確認 |

:::{.column}
**ヒント**  
`vs doctor` はいつでも何度でも実行できます。ツールを手動でインストールした後に再実行すれば、正しく認識されているか確認できます。
:::
