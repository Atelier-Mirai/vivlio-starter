# PDF出力メモ（カバー縮小とJPEG書き出し）

本書のPDFまわりの作業手順メモです。

- 対象プロジェクト: `ai_web_starter`
- 作業ディレクトリ: `/Users/mirai/projects/vivlio-starter`
- 本文PDF: `ai_web_starter_v0.5.0.pdf`
- カバーPDF: `covers/cover.pdf`

## 1. カバーPDFをA4サイズに縮小する

カバーは元データが高解像度（約 2894 × 4092 pt）なため、そのまま結合すると本文より物理サイズがかなり大きくなる。Vivliostyle が出力する本文は A4（約 595.28 × 841.92 pt）なので、カバー側も A4 に揃えてから結合する。

### 1-1. 元のページサイズを確認

```bash
cd /Users/mirai/projects/vivlio-starter

pdfinfo -box covers/cover.pdf | egrep 'Page size|MediaBox|CropBox|TrimBox'
pdfinfo -box ai_web_starter_v0.5.0.pdf | egrep 'Page size|MediaBox|CropBox|TrimBox'
```

ここで本文側が `Page size: 595.276 x 841.89 pts (A4)` になっていることを確認する。

### 1-2. pdfjam でカバーをA4に縮小

Ghostscript は画質劣化の懸念があるため使わず、`pdfjam` でページサイズだけ揃える。

```bash
cd /Users/mirai/projects/vivlio-starter

pdfjam covers/cover.pdf \
  --outfile covers/cover_a4.pdf \
  --paper a4paper \
  --noautoscale false \
  --scale 1
```

ポイント:

- `--paper a4paper` で用紙サイズを A4 に固定
- `--noautoscale false` で元のカバーを A4 に収まるよう自動縮小
- 埋め込み画像データ自体は再圧縮されないため、画質はほぼそのまま

必要であれば、出力結果も確認しておく:

```bash
pdfinfo -box covers/cover_a4.pdf | egrep 'Page size|MediaBox|CropBox|TrimBox'
```

`Page size` / `MediaBox` / `CropBox` / `TrimBox` が A4 相当の値になっていればOK。

### 1-3. カバー付きPDFを作る（任意）

`pdfunite` が利用可能な環境では、次のようにしてカバーと本文を結合できる。

```bash
cd /Users/mirai/projects/vivlio-starter

pdfunite covers/cover_a4.pdf \
         ai_web_starter_v0.5.0.pdf \
         ai_web_starter_v0.5.0_with_cover.pdf
```

- 先頭ページが A4 に縮小したカバー
- 続きが Vivliostyle 生成の本文

## 2. 本文PDFを全ページJPEGに書き出す

サンプル用に、本の内容を1ページずつJPEG画像で書き出す。ここでは A4 のポイント数に近い `595 × 842` ピクセルにスケールして出力する。

### 2-1. 出力用ディレクトリを作成

```bash
cd /Users/mirai/projects/vivlio-starter
mkdir -p sample_pages_jpeg
```

### 2-2. pdftoppm でJPEGを書き出し

`pdftoppm`（Poppler）の `-jpeg` オプションを使う。

```bash
cd /Users/mirai/projects/vivlio-starter

pdftoppm -jpeg \
  -scale-to-x 595 -scale-to-y 842 \
  -jpegopt quality=95 \
  ai_web_starter_v0.5.0.pdf sample_pages_jpeg/page
```

- 出力例: `sample_pages_jpeg/page-001.jpg`, `page-002.jpg`, ...
- 各画像はおおよそ 595 × 842 ピクセル
- `quality=95` は画質とファイルサイズのバランス用。必要に応じて変更可能

### 2-3. 画像サイズを確認（任意）

macOS では `sips` でピクセルサイズを確認できる。

```bash
cd /Users/mirai/projects/vivlio-starter
sips -g pixelWidth -g pixelHeight sample_pages_jpeg/page-001.jpg
```

---

以上が、カバーPDFの縮小（A4化）と、本文PDFからの全ページJPEG書き出しの標準手順。
