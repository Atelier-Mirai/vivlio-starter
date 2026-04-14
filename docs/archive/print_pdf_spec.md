# 📖 印刷入稿用 PDF（print_pdf）仕様書

## 1. 概要

印刷所へ入稿するための PDF を生成する機能。閲覧用 PDF とは別に、以下の要件を満たす入稿用 PDF を出力する。

- **塗り足し（bleed）**: 仕上がりサイズの外側に指定幅の余白領域を付加
- **トンボ（crop marks）**: 裁断位置を示すマーク
- **隠しノンブル**: 印刷所が乱丁・落丁を検出するための通しページ番号（PDF 結合後に HexaPDF で直接書き込み）
- **PDF/X-4 出力**: Vivliostyle CLI が生成する PDF は PDF/X-4 準拠（主要同人印刷所で対応済み）

---

## 2. 設定（`config/book.yml`）

### 2.1 ビルド対象の判定

`output.targets` に `print_pdf` が含まれている場合に入稿用 PDF を生成する。専用の CLI オプション（`--print` 等）は設けない。

```yaml
output:
  targets: pdf, print_pdf   # print_pdf を含めると入稿用 PDF も生成
```

### 2.2 print_pdf セクション

```yaml
output:
  print_pdf:
    bleed: 3mm         # 塗り足し幅（既定: 3mm）
    crop_marks: true   # トンボを付ける（既定: true）

    cover:
      front: frontcover_cmyk.pdf   # 表表紙（PDF/X-1a）
      back: backcover_cmyk.pdf     # 裏表紙（PDF/X-1a）
```

### 2.3 設定項目の詳細

| キー | 型 | 既定値 | 説明 |
|:---|:---|:---|:---|
| `bleed` | String | `3mm` | 塗り足し幅。CSS 長さ単位（mm/pt/in）で指定 |
| `crop_marks` | Boolean | `true` | トンボ（トリムマーク）を出力するか |

> **注**: `crop_offset`（トンボ外側余白）は Vivliostyle CLI の既定値 `auto`（= 13mm + bleed）をそのまま使用するため設定不要。`press_ready` も `print_pdf` ターゲット選択時は常に有効とする。隠しノンブルは常に出力する（設定項目なし）。

---

## 3. 実装方針

### 3.1 Vivliostyle CLI のオプション活用

Vivliostyle CLI は以下のオプションをネイティブサポートしている。

```
-m, --crop-marks           トンボを出力
    --bleed <bleed>        塗り足し幅 [既定: 3mm]
    --crop-offset <offset> トンボ外側余白 [既定: auto (13mm + bleed)]
```

**方針**: `output.targets` に `print_pdf` が含まれる場合、`vivliostyle build` に `--crop-marks --bleed` を付加して実行する。

### 3.2 CSS による塗り足し・トンボ指定（補助）

Vivliostyle は CSS Paged Media の `@page` ルールで `marks` / `bleed` もサポートしている。CLI オプションと CSS の両方で指定可能だが、**CLI オプションを優先**する。

```css
/* 参考: CSS でも指定可能 */
@page {
  marks: crop cross;   /* トンボ + 十字マーク */
  bleed: 3mm;          /* 塗り足し */
}
```

> **注意**: `marks` / `bleed` は「ページセレクタなしの `@page` ルール」でのみ有効（Vivliostyle の制約）。

### 3.3 内部で生成されるコマンド例

```bash
npx vivliostyle build --crop-marks --bleed 3mm --output project_name_print_vX.Y.Z.pdf
```

### 3.4 出力ファイル名

既存の `Common.generate_output_filename` メソッドに準拠する。

```ruby
# lib/vivlio/starter/cli/common.rb（既存実装）
def generate_output_filename(target = 'pdf', suffix: nil)
  # project_name = CONFIG.project.name  (例: 'vivlio_starter')
  # target == 'print_pdf' の場合 '_print' を付加
  # include_version: true の場合 '_vX.Y.Z' を付加
end

def generate_print_pdf_filename = generate_output_filename('print_pdf')
```

| 出力 | ファイル名例 | 説明 |
|:---|:---|:---|
| 閲覧用 PDF | `vivlio_starter_v1.0.0.pdf` | 従来どおり（塗り足し・トンボなし） |
| 入稿用 PDF | `vivlio_starter_print_v1.0.0.pdf` | 塗り足し・トンボ・隠しノンブル付き |

> ファイル名は `project.name` + `_print` + バージョン（`output.filename.include_version: true` の場合）で構成される。

---

## 4. 隠しノンブル

### 4.1 目的

印刷所が製本工程で乱丁・落丁を検出するために使用する通しページ番号。書籍の読者には見えない位置（ノド側・塗り足し領域内）に配置する。

### 4.2 配置仕様

| 項目 | 仕様 |
|:---|:---|
| **位置** | ノド側（綴じ側）の中央付近 |
| **方向** | 90° 回転（右ページ: 時計回り、左ページ: 反時計回り） |
| **フォントサイズ** | 6pt |
| **色** | 黒（#000） |
| **配置領域** | 仕上がり線から外側（塗り足し領域内） |
| **番号体系** | 通しページ番号（1 から始まる算用数字） |
| **対象** | `_titlepage` が 1 ページ目、`_colophon` が最終ページ |

### 4.3 HexaPDF による直接書き込み

隠しノンブルは CSS ではなく、**PDF 結合後に HexaPDF の overlay canvas で直接書き込む**。

理由:
- `_titlepage`、`_sections`、`_colophon` 等を別々に生成・結合しているため、CSS の `counter(page)` では通しページ番号を振れない
- HexaPDF は既にプロジェクトの依存ライブラリとして使用中（`outline_extractor.rb`、`utilities.rb`）

```ruby
# 隠しノンブル書き込みの概念コード
require 'hexapdf'

def stamp_hidden_nombre(pdf_path, bleed_mm: 3)
  bleed_pt = bleed_mm * 72.0 / 25.4  # mm → pt 変換
  doc = HexaPDF::Document.open(pdf_path)

  doc.pages.each_with_index do |page, idx|
    page_number = idx + 1
    canvas = page.canvas(type: :overlay)
    box = page.box(:media)

    canvas.font('Helvetica', size: 6)
    canvas.fill_color(0)  # 黒

    if page_number.odd?
      # 右ページ → ノド側 = 左端（塗り足し領域内）
      x = bleed_pt / 2.0
      y = box.height / 2.0
      canvas.save_graphics_state
        .translate(x, y)
        .rotate(90)
        .text(page_number.to_s, at: [0, 0])
        .restore_graphics_state
    else
      # 左ページ → ノド側 = 右端（塗り足し領域内）
      x = box.width - (bleed_pt / 2.0)
      y = box.height / 2.0
      canvas.save_graphics_state
        .translate(x, y)
        .rotate(-90)
        .text(page_number.to_s, at: [0, 0])
        .restore_graphics_state
    end
  end

  doc.write(pdf_path, optimize: true)
end
```

### 4.4 処理タイミング

隠しノンブルの書き込みは、**PDF 結合（Step 10）完了後、アウトライン付与（Step 11）の前後**に実行する。結合済み PDF に対して通しページ番号を振るため、正確な通し番号が保証される。

---

## 5. 実装詳細

### 5.1 変更対象ファイル

| ファイル | 変更内容 |
|:---|:---|
| `lib/vivlio/starter/cli/pdf.rb` | `PdfCommandRunner#build_command` に print_pdf 用オプション組み立てロジックを追加 |
| `lib/vivlio/starter/cli/build/pipeline.rb` | `output.targets` に `print_pdf` が含まれる場合の Step 分岐を追加 |
| `lib/vivlio/starter/cli/build/nombre_stamper.rb` | 新規作成: HexaPDF による隠しノンブル書き込みモジュール |
| `config/book.yml` | `output.print_pdf` セクション（既存）の確認 |

### 5.2 `PdfCommandRunner#build_command` の拡張

```ruby
# 入稿用 PDF のコマンド組み立て（概念）
def build_command_for_print
  cmd = 'npx vivliostyle build'
  cmd += ' -d' if SingleDocDecider.new(config).call

  print_cfg = Common::CONFIG.output&.print_pdf
  return cmd unless print_cfg

  bleed = print_cfg.bleed || '3mm'

  if print_cfg.crop_marks != false
    cmd += ' --crop-marks'
    cmd += " --bleed #{bleed}"
  end

  cmd
end
```

### 5.3 ビルドフロー

```
vs build  (output.targets に print_pdf を含む場合)
  ├─ Step 0-9:  通常ビルド（各章 HTML → PDF 変換）
  ├─ Step 10:   PDF 結合（閲覧用）
  ├─ Step 11:   アウトライン付与（閲覧用）
  ├─ Step 12:   閲覧用 PDF リネーム（vivlio_starter_v1.0.0.pdf）
  │
  ├─ Step 13:   入稿用 vivliostyle build（--crop-marks --bleed 3mm）
  ├─ Step 14:   入稿用 PDF 結合
  ├─ Step 15:   隠しノンブル書き込み（HexaPDF overlay）
  ├─ Step 16:   アウトライン付与（入稿用）
  └─ Step 17:   入稿用 PDF リネーム（vivlio_starter_print_v1.0.0.pdf）
```

---

## 6. 用紙サイズと塗り足しの関係

| 判型 | 仕上がりサイズ | 塗り足し 3mm | 塗り足し込みサイズ |
|:---|:---|:---|:---|
| A5 | 148 × 210 mm | 3mm 四方 | 154 × 216 mm |
| B5 | 182 × 257 mm | 3mm 四方 | 188 × 263 mm |
| A4 | 210 × 297 mm | 3mm 四方 | 216 × 303 mm |

Vivliostyle CLI の `--bleed` オプションは仕上がりサイズ（`size`）に対して自動的に塗り足し領域を追加する。`vivliostyle.config.js` の `size` は仕上がりサイズのまま維持し、`--bleed` で塗り足しを指定する。

---

## 7. PDF 出力形式

Vivliostyle CLI が生成する PDF は **PDF/X-4** 準拠となる。PDF/X-1a への変換（`--press-ready`）は行わない。

主要な同人印刷所（ねこのしっぽ、日光企画など）は PDF/X-4 に対応しているため、追加の変換処理は不要。

---

## 8. テスト計画

### 8.1 ユニットテスト

| テスト | 検証内容 |
|:---|:---|
| `build_command_for_print` | book.yml 設定に応じた CLI オプション文字列の組み立て |
| `print_pdf` 設定パース | bleed / crop_marks の読み取り |
| `NombreStamper` | HexaPDF で通しページ番号が正しい位置・回転で書き込まれること |
| `generate_print_pdf_filename` | `project_name_print_vX.Y.Z.pdf` 形式の出力 |

### 8.2 統合テスト

| テスト | 検証内容 |
|:---|:---|
| `targets: print_pdf` | 入稿用 PDF が生成されること |
| 塗り足しサイズ | 出力 PDF のメディアサイズが仕上がり + bleed であること |
| トンボ有無 | `crop_marks: false` でトンボなし PDF が生成されること |
| 隠しノンブル | ノド側に通しページ番号が配置されていること |
| `targets: pdf` のみ | 入稿用 PDF が生成されないこと |

### 8.3 目視確認

- PDF ビューアで塗り足し領域・トンボ・隠しノンブルの位置を確認
- 印刷所の入稿チェッカーで PDF/X-4 準拠を検証

---

## 9. 実装優先度

| 優先度 | 機能 | 備考 |
|:---|:---|:---|
| **P0** | `--crop-marks` + `--bleed` による入稿用 PDF 生成 | Vivliostyle CLI ネイティブ機能 |
| **P0** | 隠しノンブル（HexaPDF overlay canvas で直接書き込み） | 既存依存ライブラリで実現 |
| **P1** | `output.targets` 判定によるビルドパイプライン統合 | 既存の `extract_targets` を活用 |
| **P2** | 入稿前チェック（ページ数・サイズの検証） | `vs doctor` 連携 |

---

## 10. 未決事項

- [ ] 隠しノンブルの座標（`bleed_pt / 2.0`）が塗り足し領域内に正しく収まるか実機検証が必要

### 10.1 決定済み事項

- **ページ順序**: 右ページ = 奇数ページ、左ページ = 偶数ページ（表紙は結合しない）
- **カバー PDF**: 本文とは別ファイルとして印刷所に納品する
- **PDF/X-4**: 主要同人印刷所（ねこのしっぽ、日光企画）が対応済みのため、PDF/X-1a 変換は不要
