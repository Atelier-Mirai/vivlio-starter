# 表紙トンボ付与 不具合修正仕様書（改訂版）

## 改訂履歴

| 版 | 日付 | 変更内容 |
|:---|:---|:---|
| 1.0 | 初版 | Kiro による初期仕様書 |
| 2.0 | 改訂版 | Ghostscript 省略、サイズ計算整合性修正、キャッシュ方針確定、`dark` テーマ明記、循環 require 対応、`bleed_mm` 取得経路統一 |

---

## 1. 概要

`targets: print_pdf` かつ `cover: light`・`cover: dark`・`cover: master`（およびカスタムテーマ）を指定して `vs build` を実行した際、表紙（frontcover / backcover）にトンボが付与されない不具合を修正する。

---

## 2. 不具合の詳細

### 2.1 現象

```yaml
# config/book.yml
output:
  targets: print_pdf
  cover: light   # または cover: dark / cover: master
```

上記設定で `vs build` を実行すると：

- 本文 PDF（`output_print.pdf`）: トンボ・塗り足し付きで正常生成 ✅
- 表紙 PDF（`covers/frontcover_light_b5_cmyk.pdf` 等）: トンボなし ❌

### 2.2 根本原因

`cover: light` / `cover: dark`（SVGベース）と `cover: master`（PNGベース）で、それぞれ異なる経路を通るが、いずれも `print_pdf` ターゲット時のトンボ付与が不完全である。

#### cover: light / dark の経路

`CreateCommands#generate_cover_files_from_svg` が呼ばれ、`print_pdf` ターゲット時は `convert_svg(svg_path, pdf_path, page_size: page_size, crop_marks: true)` が呼ばれる。

`convert_svg` → `convert_svg_to_pdf_with_crop_marks` の実装は存在するが、`convert_svg` 内のキャッシュ判定（`File.mtime` 比較）により、既存ファイルが存在する場合は再生成がスキップされ、トンボなしの古いファイルが使われ続ける問題がある。

```ruby
def convert_svg(input, output, page_size: :b5, crop_marks: false)
  return if File.exist?(output) && File.mtime(output) >= File.mtime(input)
  # ...
end
```

#### cover: master / カスタムテーマの経路

`CoverCommands.ensure_cover_files_for_build!` → `execute_for_size` → `generate_pdf_targets_for_size` → `generate_cmyk_pdf` → `generate_pdfx_single` が呼ばれる。

`generate_pdfx_single` は ImageMagick による PNG→PDF 変換のみを行い、**トンボ付与のロジックが一切存在しない**。

### 2.3 影響範囲

| cover 設定 | targets 設定 | 影響 |
|:---|:---|:---|
| `light` | `print_pdf` を含む | トンボなし表紙が生成される可能性あり |
| `dark` | `print_pdf` を含む | 同上（`light` と同一の処理経路） |
| `master` | `print_pdf` を含む | 常にトンボなし表紙が生成される |
| カスタムテーマ | `print_pdf` を含む | 常にトンボなし表紙が生成される |
| 任意 | `pdf` のみ | 影響なし（トンボ不要） |

> **注意**: `pdf` ターゲットのみの場合、表紙 PDF のページサイズは仕上がりサイズそのまま（例: B5 = 182 × 257mm）。`print_pdf` ターゲットでは塗り足し込みサイズ（例: B5+bleed3mm = 188 × 263mm）でリサイズし、さらにトンボオフセットを加えたサイズがページサイズになる。この挙動変更は既存の `pdf` ターゲット処理に影響しないよう注意する（4.4 参照）。

---

## 3. 修正方針

### 3.1 基本方針

- **cover: light / dark（SVGベース）**: `print_pdf` ターゲット時はキャッシュを無視して強制再生成する。SVG→PDF 変換（Inkscape CLI）の所要時間は表紙＋裏表紙で概ね数秒程度であり、`vs build` 全体の実行時間の中で許容できる範囲のため、キャッシュは設けない。
- **cover: master / カスタムテーマ（PNGベース）**: `generate_pdfx_single` にトンボ付与処理を追加する。PNG に ImageMagick でトンボ領域を拡張・描画した上で PDF に変換する。Ghostscript による PDF/X-1a 変換は省略し、CMYK PDF として出力する。

### 3.2 Ghostscript 省略の判断根拠

PDF/X-1a は印刷入稿規格だが、日本の主要な同人・オンデマンド印刷所の多くは CMYK PDF で対応可能である。Ghostscript を経由すると処理経路が長くなり、ICCプロファイルの指定など追加の設定が必要になる。本修正では Ghostscript を省略し、ImageMagick による CMYK PDF 出力とする。PDF/X-1a 対応が必要な場合は将来のオプション機能として追加する。

### 3.3 トンボ仕様

本文 PDF のトンボと同一仕様を適用する。

| 項目 | 仕様 |
|:---|:---|
| 塗り足し幅 | `output.print_pdf.bleed`（既定: `3mm`） |
| トンボオフセット | `13mm`（`CROP_MARK_OFFSET_MM` 定数、Vivliostyle 準拠） |
| ページサイズ | 仕上がりサイズ + 塗り足し×2 + オフセット×2 |
| 線幅 | 0.5pt |
| 線色 | 黒（`#000000`） |
| 角トンボ | 仕上がり線位置の直線をページ端〜塗り足し境界に配置 |
| センタートンボ | ⊕（円＋十字線）をオフセット帯の中央に配置 |

---

## 4. 修正内容

### 4.1 cover: light / dark（SVGベース）の修正

#### 対象ファイル

`lib/vivlio/starter/cli/create.rb`

#### 修正箇所

`generate_cover_files_from_svg` メソッド内の `print_pdf` ターゲット処理。

`light` と `dark` は同一の `generate_cover_files_from_svg` を通るため、以下の修正は両テーマに適用される。

#### 修正前

```ruby
if targets.include?('print_pdf')
  pdf_filename = "#{cover_type}cover_#{theme}_#{page_size}_cmyk.pdf"
  pdf_path = File.join(covers_dir, pdf_filename)
  convert_svg(svg_path, pdf_path, page_size: page_size, crop_marks: true)
end
```

#### 問題点

`convert_svg` 内のキャッシュ判定により、トンボなしで生成済みの既存ファイルが残っていると再生成されない。`crop_marks: true` が指定されていてもスキップされる。

#### 採用方針

ファイル名は変更せず、`print_pdf` ターゲット時の CMYK PDF 生成では既存ファイルを削除してから再生成する。キャッシュによる高速化は行わない（処理時間が許容範囲内のため）。

#### 修正後

```ruby
if targets.include?('print_pdf')
  pdf_filename = "#{cover_type}cover_#{theme}_#{page_size}_cmyk.pdf"
  pdf_path = File.join(covers_dir, pdf_filename)
  # print_pdf ターゲット時はトンボ付きで強制再生成（キャッシュ無効化）
  FileUtils.rm_f(pdf_path)
  convert_svg(svg_path, pdf_path, page_size: page_size, crop_marks: true)
end
```

---

### 4.2 cover: master / カスタムテーマ（PNGベース）の修正

#### 対象ファイル

`lib/vivlio/starter/cli/cover.rb`

#### 修正箇所

`generate_cmyk_pdf` および `generate_pdfx_single` メソッド。

#### 修正後の処理フロー

**crop_marks: false 時（`pdf` ターゲット）**

```
PNG → ImageMagick（塗り足し込みサイズでリサイズ + CMYK変換）→ CMYK PDF
```

**crop_marks: true 時（`print_pdf` ターゲット）**

```
PNG
  ↓ ImageMagick（仕上がりサイズでリサイズ + CMYK変換）
中間 PNG（CMYK、仕上がりサイズ）
  ↓ ImageMagick（トンボ領域拡張 + トンボ線描画）
トンボ付き PNG
  ↓ ImageMagick（PDF変換）
最終 PDF（トンボ付き CMYK PDF）
```

> **補足**: Ghostscript による PDF/X-1a 変換は省略する（3.2 参照）。トンボ線は ImageMagick のラスタ描画（350dpi 相当）で描く。ベクタトンボが必要な場合は将来の課題とする。

#### 修正後のシグネチャ

```ruby
def self.generate_pdfx_single(input_png, output_pdf, size, bleed_mm:, crop_marks: false)
```

`size` は常に**仕上がりサイズ**（`base_size`）を渡す。塗り足しの加算は本メソッド内で `crop_marks` フラグに応じて行う。

#### 修正後のコード概要

```ruby
def self.generate_pdfx_single(input_png, output_pdf, size, bleed_mm:, crop_marks: false)
  return unless File.exist?(input_png)

  convert_cmd = imagemagick_convert_command
  unless convert_cmd
    Common.log_error 'ImageMagick（magick/convert）が見つかりません'
    return
  end

  Common.log_info "  生成中: #{File.basename(output_pdf)}"

  trim_w_px = size[:width]
  trim_h_px = size[:height]

  if crop_marks
    offset_mm = CROP_MARK_OFFSET_MM
    margin_mm  = bleed_mm + offset_mm
    # ピクセル換算（350dpi 基準）
    px_per_mm  = 350.0 / 25.4
    bleed_px   = (bleed_mm  * px_per_mm).round
    margin_px  = (margin_mm * px_per_mm).round
    total_w_px = trim_w_px + 2 * margin_px
    total_h_px = trim_h_px + 2 * margin_px

    temp_png = "#{output_pdf}.temp.png"

    begin
      # Step 1: 仕上がりサイズにリサイズ + CMYK変換
      cmd_resize = convert_cmd + [
        input_png,
        '-resize', "#{trim_w_px}x#{trim_h_px}!",
        '-colorspace', 'CMYK',
        '-density', '350',
        '-units', 'PixelsPerInch',
        temp_png
      ]
      return unless system(*cmd_resize, out: File::NULL, err: File::NULL)

      # Step 2: トンボ領域を拡張し、トンボ線を描画
      # 塗り足し領域: margin_px のうち bleed_px 分は白（画像の延長）、
      # 残り offset_mm 分は白地にトンボ線を描く
      crop_mark_color = '#000000'
      line_width = 2  # 350dpi での 0.5pt 相当

      # キャンバス拡張（塗り足し + オフセット分を四辺に追加）
      cmd_extend = convert_cmd + [
        temp_png,
        '-bordercolor', 'white',
        '-border', "#{margin_px}x#{margin_px}",
        # 角トンボ（4隅、仕上がり線位置に描画）
        '-fill', crop_mark_color,
        '-strokewidth', line_width.to_s,
        # 上辺左
        '-draw', "line #{margin_px},0 #{margin_px},#{bleed_px}",
        '-draw', "line 0,#{margin_px} #{bleed_px},#{margin_px}",
        # 上辺右
        '-draw', "line #{margin_px + trim_w_px},0 #{margin_px + trim_w_px},#{bleed_px}",
        '-draw', "line #{margin_px + trim_w_px + bleed_px},#{margin_px} #{total_w_px},#{margin_px}",
        # 下辺左
        '-draw', "line #{margin_px},#{margin_px + trim_h_px + bleed_px} #{margin_px},#{total_h_px}",
        '-draw', "line 0,#{margin_px + trim_h_px} #{bleed_px},#{margin_px + trim_h_px}",
        # 下辺右
        '-draw', "line #{margin_px + trim_w_px},#{margin_px + trim_h_px + bleed_px} #{margin_px + trim_w_px},#{total_h_px}",
        '-draw', "line #{margin_px + trim_w_px + bleed_px},#{margin_px + trim_h_px} #{total_w_px},#{margin_px + trim_h_px}",
        # センタートンボ（上下左右）
        '-draw', "line #{total_w_px / 2},0 #{total_w_px / 2},#{bleed_px}",
        '-draw', "line #{total_w_px / 2},#{margin_px + trim_h_px + bleed_px} #{total_w_px / 2},#{total_h_px}",
        '-draw', "line 0,#{total_h_px / 2} #{bleed_px},#{total_h_px / 2}",
        '-draw', "line #{margin_px + trim_w_px + bleed_px},#{total_h_px / 2} #{total_w_px},#{total_h_px / 2}",
        output_pdf
      ]

      unless system(*cmd_extend, out: File::NULL, err: File::NULL)
        Common.log_error "  失敗（トンボ付き PDF 生成）: #{File.basename(output_pdf)}"
      end
    ensure
      FileUtils.rm_f(temp_png)
    end

  else
    # crop_marks: false — 塗り足し込みサイズでリサイズして PDF 変換
    bleed_px  = (bleed_mm * (350.0 / 25.4)).round
    bleed_w_px = trim_w_px + 2 * bleed_px
    bleed_h_px = trim_h_px + 2 * bleed_px

    cmd_convert = convert_cmd + [
      input_png,
      '-resize', "#{bleed_w_px}x#{bleed_h_px}!",
      '-colorspace', 'CMYK',
      '-density', '350',
      '-units', 'PixelsPerInch',
      output_pdf
    ]

    unless system(*cmd_convert, out: File::NULL, err: File::NULL)
      Common.log_error "  失敗（変換）: #{File.basename(output_pdf)}"
    end
  end
end
```

> **実装者へ**: 上記のトンボ描画コマンドはロジックの概要を示すものであり、実際の座標値や `-draw` の構文は ImageMagick のバージョンに合わせて検証すること。センタートンボの ⊕（円＋十字線）については、`-draw "circle cx,cy r"` を追加する。

#### generate_cmyk_pdf の修正

```ruby
def self.generate_cmyk_pdf(covers_dir, page_size, config)
  base_size = SIZES[page_size]      # 仕上がりサイズ（塗り足しなし）
  bleed_mm  = parse_bleed_mm(config)

  # print_pdf ターゲット時は crop_marks: true を渡す
  # サイズは常に仕上がりサイズ（base_size）を渡す
  # 塗り足し・オフセットの加算は generate_pdfx_single 内で行う

  generate_pdfx_single(
    File.join(covers_dir, front_input),
    File.join(covers_dir, front_output),
    base_size,
    bleed_mm: bleed_mm,
    crop_marks: true
  )

  generate_pdfx_single(
    File.join(covers_dir, back_input),
    File.join(covers_dir, back_output),
    base_size,
    bleed_mm: bleed_mm,
    crop_marks: true
  )
end
```

---

### 4.3 add_crop_marks_overlay の依存関係確認

#### 対象ファイル

`lib/vivlio/starter/cli/cover.rb`、`lib/vivlio/starter/cli/create.rb`

#### 確認事項

本修正（PNGベース経路）では `add_crop_marks_overlay`（Prawn + CombinePDF）を使用しない方針のため、`cover.rb` から `create.rb` を `require` する必要はなくなった。

ただし、既存コードで循環 `require` が発生していないかを実装前に確認すること。`cover.rb` と `create.rb` が相互に `require` し合っている場合は、共通処理を `lib/vivlio/starter/cli/pdf_utils.rb` 等に切り出すことを検討する。

---

### 4.4 サイズ計算の整合性

#### 設計原則

`generate_pdfx_single` に渡す `size` は常に**仕上がりサイズ**（`SIZES[page_size]` の値）とする。

| ターゲット | ImageMagick リサイズサイズ | PDFページサイズ |
|:---|:---|:---|
| `pdf` のみ | 仕上がり + 塗り足し×2 | 同左 |
| `print_pdf` | 仕上がりサイズ | 仕上がり + 塗り足し×2 + オフセット×2 |

`crop_marks: false`（`pdf` ターゲット）時の既存動作を壊さないよう、`bleed_mm` の加算は `generate_pdfx_single` 内で `crop_marks` フラグに応じて分岐する（4.2 修正後コード参照）。

#### サイズ計算例（B5、bleed=3mm、offset=13mm）

| 種別 | 幅 | 高さ |
|:---|:---|:---|
| 仕上がり | 182mm | 257mm |
| 塗り足し込み（`pdf`） | 188mm | 263mm |
| トンボ付き（`print_pdf`） | 214mm | 289mm |

---

## 5. 修正対象ファイル一覧

| ファイル | 修正内容 |
|:---|:---|
| `lib/vivlio/starter/cli/cover.rb` | `generate_pdfx_single` にトンボ付与処理を追加（ImageMagick のみ、Ghostscript 不使用）、シグネチャ変更（`bleed_mm:` キーワード引数追加、`size` を仕上がりサイズに統一）、`generate_cmyk_pdf` の呼び出しを修正 |
| `lib/vivlio/starter/cli/create.rb` | `generate_cover_files_from_svg` の `print_pdf` 処理でキャッシュを無効化（`FileUtils.rm_f` で強制再生成） |

---

## 6. 正常系の期待動作

### 6.1 cover: light / dark + targets: print_pdf

```
vs build 実行
  ↓
Step 13: CoverCommands.ensure_cover_files_for_build!
  ↓
CreateCommands.execute_cover({})
  ↓
generate_standard_theme_covers('light', ['print_pdf'])  # dark も同経路
  ↓
generate_cover_files_from_svg(svg_path, 'light', 'front', ['print_pdf'])
  ↓
FileUtils.rm_f(pdf_path)  # 既存ファイルを削除
convert_svg(svg_path, pdf_path, page_size: :b5, crop_marks: true)
  ↓
convert_svg_to_pdf_with_crop_marks(svg_path, pdf_path, 182, 257)
  ↓
covers/frontcover_light_b5_cmyk.pdf（トンボ付き）✅
covers/backcover_light_b5_cmyk.pdf（トンボ付き）✅
```

### 6.2 cover: master + targets: print_pdf

```
vs build 実行
  ↓
Step 13: CoverCommands.ensure_cover_files_for_build!
  ↓
execute_for_size(:b5, nil)
  ↓
generate_pdf_targets_for_size(covers_dir, :b5, config, ['print_pdf'])
  ↓
generate_cmyk_pdf(covers_dir, :b5, config)
  ↓
generate_pdfx_single(front_input, front_output, base_size, bleed_mm: 3.0, crop_marks: true)
  ↓
  1. ImageMagick: PNG → 仕上がりサイズでリサイズ + CMYK変換
  2. ImageMagick: トンボ領域拡張 + トンボ線描画
  3. ImageMagick: PDF変換
  ↓
covers/frontcover_master_b5_cmyk.pdf（トンボ付き CMYK PDF）✅
covers/backcover_master_b5_cmyk.pdf（トンボ付き CMYK PDF）✅
```

---

## 7. 異常系・エラーハンドリング

| 状況 | 対応 |
|:---|:---|
| `rsvg-convert` が未インストール（cover: light / dark 時） | 既存の警告ログを出力し、トンボなし PDF を生成（フォールバック） |
| ImageMagick が未インストール | 既存のエラーログを出力し処理を中断 |
| マスター PNG が存在しない | 既存の警告ログを出力しスキップ |

> **補足**: Ghostscript を省略したため、`prawn` / `combine_pdf` gem 未インストール時のフォールバックは PNGベース経路では不要となった。

---

## 8. 検証方針

### 8.1 検証すべき性質

#### P1: トンボ付き PDF のページサイズ

`print_pdf` ターゲット時に生成される表紙 PDF のページサイズは、以下の式を満たすこと。

```
期待ページサイズ（mm）= 仕上がりサイズ + 2 × (bleed_mm + CROP_MARK_OFFSET_MM)
```

例（B5、bleed=3mm、offset=13mm）:

- 幅: 182 + 2 × (3 + 13) = 214mm
- 高さ: 257 + 2 × (3 + 13) = 289mm

#### P2: トンボなし PDF のページサイズ

`pdf` ターゲット時に生成される表紙 PDF のページサイズは、塗り足し込みサイズと一致すること。

```
期待ページサイズ（mm）= 仕上がりサイズ + 2 × bleed_mm
```

#### P3: 生成ファイルの存在

`print_pdf` ターゲット時、`vs build` 完了後に以下のファイルが存在すること。

- `covers/frontcover_{theme}_{size}_cmyk.pdf`
- `covers/backcover_{theme}_{size}_cmyk.pdf`

#### P4: トンボ線の存在

生成された PDF を目視確認し、トンボ線（角トンボ・センタートンボ）が正しく描画されていることを確認する（自動テストは行わない）。

### 8.2 テスト実装方針

ページサイズ検証（P1・P2）および存在確認（P3）は Minitest で自動化する。

```ruby
# test/cover_crop_marks_test.rb
require 'minitest/autorun'
require 'hexapdf'

class CoverCropMarksTest < Minitest::Test
  BLEED_MM  = 3.0
  OFFSET_MM = 13.0
  TRIM_W_MM = 182.0  # B5
  TRIM_H_MM = 257.0

  # P1: トンボ付き PDF のページサイズ
  def test_cmyk_pdf_page_size_with_crop_marks
    expected_w_mm = TRIM_W_MM + 2 * (BLEED_MM + OFFSET_MM)
    expected_h_mm = TRIM_H_MM + 2 * (BLEED_MM + OFFSET_MM)

    pdf = HexaPDF::Document.open('covers/frontcover_master_b5_cmyk.pdf')
    box = pdf.pages[0].box
    actual_w_mm = box.width  / 72.0 * 25.4
    actual_h_mm = box.height / 72.0 * 25.4

    assert_in_delta expected_w_mm, actual_w_mm, 0.5
    assert_in_delta expected_h_mm, actual_h_mm, 0.5
  end

  # P2: トンボなし PDF のページサイズ
  def test_rgb_pdf_page_size_without_crop_marks
    expected_w_mm = TRIM_W_MM + 2 * BLEED_MM
    expected_h_mm = TRIM_H_MM + 2 * BLEED_MM

    pdf = HexaPDF::Document.open('covers/frontcover_master_b5.pdf')
    box = pdf.pages[0].box
    actual_w_mm = box.width  / 72.0 * 25.4
    actual_h_mm = box.height / 72.0 * 25.4

    assert_in_delta expected_w_mm, actual_w_mm, 0.5
    assert_in_delta expected_h_mm, actual_h_mm, 0.5
  end

  # P3: ファイル存在確認
  def test_cmyk_pdf_exists_after_build
    assert File.exist?('covers/frontcover_master_b5_cmyk.pdf')
    assert File.exist?('covers/backcover_master_b5_cmyk.pdf')
  end
end
```

> **CI 実行方針**: P1・P2・P3 のテストは ImageMagick が利用可能な環境であれば CI で実行可能。P4（目視確認）は CI 対象外とし、リリース前の手動確認とする。

---

## 9. 実装タスク

- [ ] `cover.rb`: `generate_pdfx_single` のシグネチャを変更（`bleed_mm:` キーワード引数追加）
- [ ] `cover.rb`: `generate_pdfx_single` に ImageMagick によるトンボ付与処理を追加（`crop_marks: true` 時）
- [ ] `cover.rb`: `generate_pdfx_single` の `crop_marks: false` 時は塗り足し込みサイズでリサイズ（既存動作を維持）
- [ ] `cover.rb`: `generate_cmyk_pdf` のサイズを仕上がりサイズ（`base_size`）に変更し、`bleed_mm` を `parse_bleed_mm(config)` から取得して `generate_pdfx_single` に渡す
- [ ] `cover.rb`: `generate_cmyk_pdf` の `generate_pdfx_single` 呼び出しに `crop_marks: true` を追加
- [ ] `create.rb`: `generate_cover_files_from_svg` の `print_pdf` 処理で `FileUtils.rm_f` によるキャッシュ無効化を追加
- [ ] 依存関係確認: `cover.rb` と `create.rb` 間の循環 `require` がないことを確認
- [ ] テスト: ページサイズ検証テスト（P1・P2）を追加
- [ ] テスト: ファイル存在確認テスト（P3）を追加
- [ ] 動作確認（目視）: `cover: light` + `targets: print_pdf` でトンボ付き PDF が生成されること（P4）
- [ ] 動作確認（目視）: `cover: dark` + `targets: print_pdf` でトンボ付き PDF が生成されること（P4）
- [ ] 動作確認（目視）: `cover: master` + `targets: print_pdf` でトンボ付き PDF が生成されること（P4）
- [ ] 動作確認: `cover: master` + `targets: pdf` のみの場合、既存動作（塗り足し込みサイズ、トンボなし）が維持されること
