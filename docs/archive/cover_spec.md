# 📚 カバー画像およびビルドコマンド仕様書

## 1. 🎨 マスター画像ファイル仕様

すべてのカバー画像は、Keynoteで作成された**A4サイズ基準のマスターファイル**を元に出力されます。このマスターファイルは、すべての派生ファイルにおいて最高の画像品質（**350 dpi 相当**）を保証するための原寸大データです。

### 1.1. マスターファイル名と解像度

マスターファイルは `covers/` ディレクトリ直下に配置します。(book.yml `directories.covers = 'covers'` の場合)

| 要素 | ファイル名 | 配置場所 | 推奨ピクセル数 (px) |
| :--- | :--- | :--- | :--- |
| **表紙マスター** | `frontcover_master.png` | `covers/frontcover_master.png` | **2,894 × 4,092** |
| **裏表紙マスター** | `backcover_master.png` | `covers/backcover_master.png` | **2,894 × 4,092** |

---

## 2. 🖼️ カバー画像 推奨出力仕様（350 dpi 基準）

最終的な用途（電子書籍、簡易印刷、商業印刷）に応じた出力仕様を定義します。

| 用途 | 仕上がりサイズ | 塗り足し | 印刷用サイズ (mm) | 推奨ピクセル数 (px) | 推奨出力形式 | 備考 |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **EPUBカバー** | - | - | - | **1,600 × 2,560** | **JPEG** (高画質) | 縦横比 1:1.6 |
| **A4（簡易印刷）** | 210 × 297 mm | なし | 210 × 297 mm | **2,894 × 4,092** | PDF (通常) | 白銀比 1:√2 |
| **B5（商業印刷）** | 182 × 257 mm | 3 mm | 188 × 263 mm | **2,591 × 3,626** | **PDF/X-1a** | 白銀比 1:√2 |
| **A5（商業印刷）** | 148 × 210 mm | 3 mm | 154 × 216 mm | **2,123 × 2,979** | **PDF/X-1a** | 白銀比 1:√2 |

---

## 3. ⚙️ `vs cover` コマンド仕様

`vs cover` コマンドは、マスター画像（`frontcover_master.png`, `backcover_master.png`）を元に、ターゲットに応じたファイルを出力します。

### 3.1. ターゲット別コマンド定義と処理詳細

| コマンド | 処理概要 | 出力規格 | 出力ファイル名 |
| :--- | :--- | :--- | :--- |
| **`vs cover a4`** | A4マスター画像を元に、表紙および裏表紙を出力。 | PDF (通常) | `book.yml` の `output.pdf.cover.front` および `back` に従う。 |
| **`vs cover b5`** | B5規格（塗り足し込み188×263mm）に縮小し、表紙および裏表紙を出力。 | **PDF/X-1a** | `book.yml` の `output.print_pdf.cover.front` および `back` に従う。 |
| **`vs cover a5`** | A5規格（塗り足し込み154×216mm）に縮小し、表紙および裏表紙を出力。 | **PDF/X-1a** | `book.yml` の `output.print_pdf.cover.front` および `back` に従う。 |
| **`vs cover epub`** | 表紙マスターを 1600x2560 px に縮小・トリミングして出力。 | JPEG (高画質) | `book.yml` の `output.epub.cover` に従う。 |

### 3.2. PDF/X-1a生成の技術仕様

B5/A5用のPDF/X-1a生成は、ImageMagickとGhostscriptを使用して以下の手順で行います：

```bash
# Step 1: ImageMagickでリサイズ + CMYK変換
convert covers/frontcover_master.png \
  -resize "2590x3624!" \
  -colorspace CMYK \
  -density 350 \
  -units PixelsPerInch \
  temp_cmyk.pdf

# Step 2: GhostscriptでPDF/X-1a変換
gs -dPDFX -dBATCH -dNOPAUSE -dQUIET \
   -sDEVICE=pdfwrite \
   -dCompatibilityLevel=1.4 \
   -sOutputFile=covers/frontcover_cmyk.pdf \
   temp_cmyk.pdf
```

**品質設定**：
- **解像度**: 350 dpi
- **カラースペース**: CMYK（Japan Color 2001 Coated推奨）
- **PDF互換性**: 1.4（PDF/X-1a:2001準拠）

### 3.3. EPUBカバーのトリミング詳細

* **縮小比率**: マスター画像（2,894 × 4,089 px）を、縦横比を保ったまま高さ2,560 pxに縮小すると、横幅は約1,812 pxとなる。
* **トリミング**: この約1,812 pxの画像を、最終的な1,600 px幅にするため、**左右それぞれ106 pxずつ切り取る**ことで1,600 × 2,560 pxのEPUB用カバーを生成する。
* **品質**: JPEG品質90%推奨

```bash
# EPUBカバー生成例
convert covers/frontcover_master.png \
  -resize "x2560" \
  -gravity center \
  -crop "1600x2560+0+0" \
  -quality 90 \
  covers/cover.jpg
```

### 3.4. ファイルの存在確認

* `covers/frontcover_master.png` または `covers/backcover_master.png` が存在しない場合、該当する出力ファイルは生成されません。
* マスターファイルが存在しない場合は警告を表示してスキップします。

### 3.5. 汎用コマンドと一括出力

| コマンド | 処理概要 |
| :--- | :--- |
| **`vs cover`** | `book.yml` の設定を参照し、必要なカバーファイルを自動判定して一括出力します。 |

**一括出力のロジック**:

1. **ページサイズの判定**（`page.use` から）:
   - `b5_*` → B5サイズとして処理
   - `a5_*` → A5サイズとして処理
   - `a4_*` → A4サイズとして処理

2. **ターゲット別の出力**（`output` 配下の各セクションをチェック）:
   - `output.pdf.cover.front/back` が定義されている場合:
     - A4サイズのRGB版PDF（通常）を生成
   - `output.print_pdf.cover.front/back` が定義されている場合:
     - 判定されたページサイズ（B5/A5）のCMYK版PDF/X-1aを生成
   - `output.epub.cover` が定義されている場合:
     - 1600×2560のJPEGを生成

**出力例**（`page.use: b5_standard`、`targets: [pdf, print_pdf, epub]` の場合）:

```
covers/
├── frontcover_master.png      # マスター（必須）
├── backcover_master.png       # マスター（必須）
├── frontcover_rgb.pdf         # PDF用（A4、RGB）
├── backcover_rgb.pdf          # PDF用（A4、RGB）
├── frontcover_cmyk.pdf        # 印刷用（B5、CMYK、PDF/X-1a）
├── backcover_cmyk.pdf         # 印刷用（B5、CMYK、PDF/X-1a）
└── cover.jpg                  # EPUB用（1600×2560、JPEG）
```