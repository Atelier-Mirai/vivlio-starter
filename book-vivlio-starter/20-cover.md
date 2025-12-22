# カバー画像の生成

:::{.chapter-lead}
Vivlio Starter では、`vs cover` コマンドを使用して、マスター画像から PDF 用、印刷用、EPUB 用のカバー画像を自動生成できます。本章では、カバー画像の準備から生成、管理までの一連のワークフローを解説します。
:::

`vs cover` コマンドは、1つのマスター画像から、用途に応じた複数のフォーマットのカバー画像を自動生成します。これにより、PDF閲覧用、商業印刷用、電子書籍用のカバーを一括で作成できます。

## マスター画像の準備

:::{.section-lead}
カバー画像を生成する前に、まずマスター画像を準備します。マスター画像は、すべての出力フォーマットに対応できる高品質な PNG ファイルです。
:::

### マスター画像の仕様

`covers/` ディレクトリ（`book.yml` の `directories.covers` で変更可能）に、以下のマスター画像を配置します：

| ファイル名 | 用途 | 推奨解像度 |
|:---|:---|:---|
| `frontcover_master.png` | 表紙のマスター画像 | 2,894 × 4,092 px（A4、350 dpi 相当） |
| `backcover_master.png` | 裏表紙のマスター画像 | 2,894 × 4,092 px（A4、350 dpi 相当） |

:::{.note}
**推奨解像度について**

マスター画像は **A4サイズ・350 dpi** を基準としています。この解像度であれば、商業印刷にも対応できる品質を確保できます。
:::

### マスター画像の作成方法

マスター画像は、以下のいずれかの方法で作成できます：

1. **Keynote / PowerPoint**
   - A4サイズでデザインを作成
   - PNG形式で書き出し（推奨解像度: 2,894 × 4,092 px）

2. **画像編集ソフト（Photoshop / GIMP など）**
   - キャンバスサイズ: 2,894 × 4,092 px
   - 解像度: 350 dpi
   - カラーモード: RGB
   - ファイル形式: PNG

3. **デザインツール（Canva / Figma など）**
   - A4サイズ（210 × 297 mm）でデザイン
   - PNG形式で書き出し

:::{.caution}
**カラーモードについて**

マスター画像は **RGB モード** で作成してください。印刷用の CMYK 変換は `vs cover` コマンドが自動的に行います。
:::

## カバー画像の生成

:::{.section-lead}
マスター画像を配置したら、`vs cover` コマンドで各フォーマットのカバー画像を生成します。
:::

### 基本的な使い方

最もシンプルな使い方は、引数なしで `vs cover` を実行することです：

```bash
vs cover
```

このコマンドは、`book.yml` の設定を自動的に読み取り、必要なカバー画像をすべて生成します。

### 生成されるファイル

`book.yml` の設定に応じて、以下のファイルが生成されます：

```
covers/
├── frontcover_master.png      # マスター（手動配置）
├── backcover_master.png       # マスター（手動配置）
├── frontcover_rgb.pdf         # PDF用表紙（A4、RGB）
├── backcover_rgb.pdf          # PDF用裏表紙（A4、RGB）
├── frontcover_cmyk.pdf        # 印刷用表紙（B5/A5、CMYK、PDF/X-1a）
├── backcover_cmyk.pdf         # 印刷用裏表紙（B5/A5、CMYK、PDF/X-1a）
└── cover.jpg                  # EPUB用カバー（1600×2560、JPEG）
```

### フォーマット別の生成

特定のフォーマットのみを生成したい場合は、サブコマンドを使用します：

```bash
# A4サイズのRGB版PDFのみ生成
vs cover:a4

# B5サイズのCMYK版PDF/X-1aのみ生成
vs cover:b5

# A5サイズのCMYK版PDF/X-1aのみ生成
vs cover:a5

# EPUB用JPEGのみ生成
vs cover:epub
```

## 設定のカスタマイズ

:::{.section-lead}
`book.yml` でカバー画像のファイル名や出力先を自由にカスタマイズできます。
:::

### ファイル名の設定

`book.yml` の `output` セクションで、各フォーマットのファイル名を指定します：

```yaml
output:
  # PDF用カバー（RGB版）
  pdf:
    cover:
      front: frontcover_rgb.pdf  # 表表紙
      back: backcover_rgb.pdf    # 裏表紙
  
  # 印刷用PDF（CMYK版、PDF/X-1a）
  print_pdf:
    cover:
      front: frontcover_cmyk.pdf  # 表表紙
      back: backcover_cmyk.pdf    # 裏表紙
  
  # EPUB用カバー
  epub:
    cover: cover.jpg  # EPUBカバー画像（1600×2560推奨）
```

### ページサイズの自動判定

印刷用PDF（CMYK版）のサイズは、`book.yml` の `page.use` 設定から自動判定されます：

```yaml
page:
  use: b5_standard  # B5サイズとして処理
  # use: a5_standard  # A5サイズとして処理
  # use: a4_standard  # A4サイズとして処理
```

## 出力フォーマットの詳細

:::{.section-lead}
`vs cover` コマンドが生成する各フォーマットの仕様を理解しておくと、用途に応じた使い分けができます。
:::

### PDF用（RGB版）

**用途**: PDF閲覧、電子配布

- **サイズ**: A4（210 × 297 mm）
- **解像度**: 350 dpi
- **カラーモード**: RGB
- **ファイル形式**: PDF（通常）
- **特徴**: ファイルサイズは大きめだが、画面表示が美しい

### 印刷用PDF（CMYK版、PDF/X-1a）

**用途**: 商業印刷、印刷所入稿

- **サイズ**: B5またはA5（`page.use` に応じて自動選択）
- **塗り足し**: 3 mm（商業印刷標準）
- **解像度**: 350 dpi
- **カラーモード**: CMYK（Japan Color 2001 Coated推奨）
- **ファイル形式**: PDF/X-1a:2001準拠
- **特徴**: 印刷所に入稿できる品質

:::{.note}
**PDF/X-1aとは**

PDF/X-1a は、商業印刷用の国際標準規格です。CMYK カラーモードの使用、フォント埋め込み、透明効果の禁止などが規定されており、印刷所での再現性が保証されます。
:::

### EPUB用（JPEG）

**用途**: 電子書籍（EPUB）

- **サイズ**: 1,600 × 2,560 px
- **縦横比**: 1:1.6（電子書籍の標準比率）
- **品質**: JPEG 90%
- **ファイル形式**: JPEG
- **特徴**: ファイルサイズが小さく、電子書籍リーダーで美しく表示される

:::{.column}
**EPUBカバーのトリミング処理**

マスター画像（2,894 × 4,092 px）を高さ2,560 pxに縮小すると、横幅は約1,812 pxになります。これを1,600 px幅にするため、左右それぞれ106 pxずつトリミングします。

この処理により、マスター画像の中央部分がEPUBカバーとして使用されます。重要な要素は画像の中央に配置することを推奨します。
:::

## カバー画像の削除

:::{.section-lead}
生成されたカバー画像を削除するには、`vs clean --cover` コマンドを使用します。マスター画像は保持されるため、安心して削除できます。
:::

### 基本的な削除

```bash
vs clean --cover
```

このコマンドは、`book.yml` の設定に基づいて、生成されたカバー画像のみを削除します：

- ✅ **削除される**: 生成されたPDF、JPEG（`book.yml` で指定されたファイル）
- ✅ **保持される**: マスター画像（`*_master.png`）

### 複数のオプションとの組み合わせ

`vs clean` コマンドは、複数のオプションを同時に指定できます：

```bash
# カバー画像とキャッシュを削除
vs clean --cover --cache

# カバー画像とキャッシュと生成物をすべて削除
vs clean --cover --cache --purge
```

## トラブルシューティング

:::{.section-lead}
`vs cover` コマンドの実行時によくある問題とその解決方法を紹介します。
:::

### マスターファイルが見つからない

**症状**: コマンド実行時に警告が表示される

```
⚠️  表紙マスターが見つかりません: covers/frontcover_master.png
```

**原因**: マスター画像が指定された場所に存在しない

**解決方法**:
1. `covers/` ディレクトリが存在するか確認
2. ファイル名が `frontcover_master.png` および `backcover_master.png` になっているか確認
3. `book.yml` の `directories.covers` 設定を確認

### 必要なツールがインストールされていない

**症状**: カバー画像が生成されない

**原因**: ImageMagick または Ghostscript がインストールされていない

**解決方法**:

```bash
# 自動インストール（推奨）
vs doctor --fix

# 手動インストール（macOSの場合）
brew install imagemagick ghostscript

# 確認
convert --version
gs --version
```

:::{.note}
**ツールの診断**

`vs doctor` コマンドで、必要なツールがインストールされているか確認できます：

```bash
vs doctor
```
:::

### CMYK変換で色が変わる

**症状**: 印刷用PDF（CMYK版）の色がRGB版と異なる

**原因**: RGB と CMYK では表現できる色域（ガマット）が異なる

**解決方法**:
- RGBでは表現できるが、CMYKでは表現できない鮮やかな色（特に青や緑）は、CMYK変換時に近似色に変換されます
- デザイン時から印刷を考慮し、CMYK で表現可能な色を使用することを推奨します
- Photoshop などでCMYKプレビューを確認しながらデザインするのが理想的です

## 実用的なワークフロー

:::{.section-lead}
実際の書籍制作におけるカバー画像生成の典型的なワークフローを紹介します。
:::

### 初回生成

```bash
# 1. マスター画像を配置
# covers/frontcover_master.png
# covers/backcover_master.png を配置

# 2. カバー画像を生成
vs cover

# 3. 生成されたファイルを確認
ls -lh covers/
```

### デザインの修正と再生成

```bash
# 1. マスター画像を修正（デザインツールで編集）

# 2. 古いカバー画像を削除
vs clean --cover

# 3. 新しいカバー画像を生成
vs cover

# 4. PDFに統合してビルド
vs build
```

### 印刷所入稿前の最終確認

```bash
# 1. 印刷用PDFのみを再生成
vs cover:b5  # またはvs cover:a5

# 2. 生成されたCMYK版PDFを確認
open covers/frontcover_cmyk.pdf
open covers/backcover_cmyk.pdf

# 3. PDF/X-1a準拠であることを確認（Adobe Acrobat推奨）

# 4. 問題なければ印刷所に入稿
```

## まとめ

:::{.section-lead}
`vs cover` コマンドを活用することで、カバー画像の生成作業を大幅に効率化できます。
:::

本章で学んだ内容：

- ✅ マスター画像の準備方法（A4サイズ、350 dpi、PNG形式）
- ✅ `vs cover` コマンドによる一括生成
- ✅ フォーマット別の生成（RGB版、CMYK版、EPUB用）
- ✅ `book.yml` でのカスタマイズ
- ✅ `vs clean --cover` による削除
- ✅ トラブルシューティング

`vs cover` コマンドは、1つのマスター画像から複数のフォーマットを自動生成するため、デザインの一貫性を保ちながら、各用途に最適化されたカバー画像を効率的に作成できます。

:::{.column}
**次のステップ**

カバー画像を生成したら、`vs build` コマンドで本文PDFにカバーを統合できます。詳細は次章以降で解説します。
:::
