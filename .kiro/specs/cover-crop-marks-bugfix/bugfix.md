# バグ修正要件書: 表紙・裏表紙トンボ付与

## Introduction

本文には既にトンボが付与されているが、表紙・裏表紙には本文と異なる形式のトンボが付与されている。印刷所入稿時には表紙・裏表紙にも本文と同じ形式のトンボが必要である。

本バグ修正では、`print_pdf` ターゲット時に表紙・裏表紙PDFに対して本文と同じ形式のトンボを付与する機能を実装する。

## Bug Analysis

### Current Behavior (Defect)

1.1 WHEN `output.targets` に `print_pdf` が含まれている THEN 表紙・裏表紙PDFには本文と異なる形式のトンボが付与されている

1.2 WHEN SVGテーマ（light/dark）で `print_pdf` ターゲットを指定 THEN `convert_svg_to_pdf_with_crop_marks` メソッドが呼ばれるが、本文のトンボ形式と異なる

1.3 WHEN PNGテーマ（master/カスタム）で `print_pdf` ターゲットを指定 THEN `generate_pdfx_single` メソッドでトンボが描画されるが、本文のトンボ形式と一致していない

### Expected Behavior (Correct)

2.1 WHEN `output.targets` に `print_pdf` が含まれている THEN 表紙・裏表紙PDFにも本文と同じ形式のトンボが付与される

2.2 WHEN SVGテーマ（light/dark）で `print_pdf` ターゲットを指定 THEN 表紙・裏表紙PDFに本文と同じ形式のトンボ（角トンボ + センタートンボ）が付与される

2.3 WHEN PNGテーマ（master/カスタム）で `print_pdf` ターゲットを指定 THEN 表紙・裏表紙PDFに本文と同じ形式のトンボ（角トンボ + センタートンボ）が付与される

2.4 WHEN トンボ付きPDFを生成 THEN ページサイズは「仕上がりサイズ + 2 × (bleed_mm + CROP_MARK_OFFSET_MM)」となる

### Unchanged Behavior (Regression Prevention)

3.1 WHEN `output.targets` に `pdf` のみが含まれている（`print_pdf` なし） THEN 表紙・裏表紙PDFにはトンボが付与されない（既存動作を維持）

3.2 WHEN トンボなしPDFを生成 THEN ページサイズは「仕上がりサイズ + 2 × bleed_mm」となる（既存動作を維持）

3.3 WHEN EPUB用JPEGを生成 THEN トンボは付与されず、既存の生成処理が維持される

3.4 WHEN 本文PDFを生成 THEN 既存のトンボ付与処理が影響を受けない
