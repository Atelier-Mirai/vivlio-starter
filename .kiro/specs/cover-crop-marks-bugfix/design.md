# 表紙・裏表紙トンボ付与バグ修正設計

## Overview

本文PDFには既にトンボが付与されているが、表紙・裏表紙PDFには本文と異なる形式のトンボが付与されている。印刷所入稿時には表紙・裏表紙にも本文と同じ形式のトンボが必要である。

本設計では、`print_pdf` ターゲット時に表紙・裏表紙PDFに対して本文と同じ形式のトンボ（角トンボ + センタートンボ）を付与する機能を実装する。

## Glossary

- **Bug_Condition (C)**: `print_pdf` ターゲット時に表紙・裏表紙PDFのトンボ形式が本文と異なる状態
- **Property (P)**: 表紙・裏表紙PDFに本文と同じ形式のトンボ（角トンボ + センタートンボ）が付与される
- **Preservation**: `pdf` ターゲット時のトンボなし動作、EPUB用JPEG生成、本文PDF生成が影響を受けない
- **角トンボ**: 仕上がり線（trim境界）の4隅に配置される直線トンボ。ページ端からbleed境界まで描画される
- **センタートンボ**: 各辺の中央に配置される⊕（丸十字）形状のトンボ。crop offset帯の中央に配置される
- **trim境界**: 仕上がりサイズの境界線
- **bleed境界**: 塗り足し領域の境界線（trim境界 + bleed_mm）
- **crop offset**: トンボを配置するための余白領域（CROP_MARK_OFFSET_MM = 13.0mm）
- **convert_svg_to_pdf_with_crop_marks**: SVGテーマ（light/dark）用のトンボ付きPDF生成メソッド（lib/vivlio/starter/cli/create.rb）
- **generate_pdfx_single**: PNGテーマ（master/カスタム）用のトンボ付きPDF生成メソッド（lib/vivlio/starter/cli/cover.rb）
- **add_crop_marks_overlay**: 本文PDF用のトンボオーバーレイ生成メソッド（lib/vivlio/starter/cli/create.rb）

## Bug Details

### Bug Condition

バグは `print_pdf` ターゲット時に表紙・裏表紙PDFを生成する際に発生する。表紙・裏表紙のトンボ描画処理が本文のトンボ描画処理と異なるため、印刷所入稿時に形式の不一致が生じる。

**Formal Specification:**
```
FUNCTION isBugCondition(input)
  INPUT: input of type { target: String, file_type: String }
  OUTPUT: boolean
  
  RETURN input.target == 'print_pdf'
         AND input.file_type IN ['frontcover', 'backcover']
         AND cropMarksFormat(input) != mainBodyCropMarksFormat()
END FUNCTION
```

### Examples

- **SVGテーマ（light/dark）の場合**: `convert_svg_to_pdf_with_crop_marks` メソッドが呼ばれるが、トンボ描画ロジックが本文の `add_crop_marks_overlay` と異なる
- **PNGテーマ（master/カスタム）の場合**: `generate_pdfx_single` メソッドでImageMagickの `-draw` コマンドを使ってトンボを描画するが、本文のPrawn + CombinePDFによるトンボ描画と異なる
- **本文PDFの場合**: `add_crop_marks_overlay` メソッドでPrawn + CombinePDFを使って角トンボ + センタートンボを描画する（正しい形式）
- **期待される動作**: 表紙・裏表紙PDFも本文と同じ `add_crop_marks_overlay` メソッドを使ってトンボを描画する

## Expected Behavior

### Preservation Requirements

**Unchanged Behaviors:**
- `pdf` ターゲット時は表紙・裏表紙PDFにトンボが付与されない（既存動作を維持）
- トンボなしPDFのページサイズは「仕上がりサイズ + 2 × bleed_mm」となる（既存動作を維持）
- EPUB用JPEG生成時はトンボが付与されず、既存の生成処理が維持される
- 本文PDFのトンボ付与処理（`add_crop_marks_overlay`）は影響を受けない

**Scope:**
`print_pdf` ターゲット以外のすべての出力形式は完全に影響を受けない。これには以下が含まれる:
- `pdf` ターゲット（トンボなしRGB PDF）
- `epub` ターゲット（JPEG表紙）
- 本文PDF生成（既存のトンボ付与処理）

## Hypothesized Root Cause

コードベースの調査結果から、以下の根本原因が特定された:

1. **トンボ描画処理の重複実装**: 表紙・裏表紙用と本文用で異なるトンボ描画ロジックが実装されている
   - 本文: `add_crop_marks_overlay` メソッド（Prawn + CombinePDF）
   - SVGテーマ表紙: `convert_svg_to_pdf_with_crop_marks` メソッド（Prawn + CombinePDF）
   - PNGテーマ表紙: `generate_pdfx_single` メソッド（ImageMagick `-draw`）

2. **トンボ形式の不一致**: 各実装で角トンボとセンタートンボの描画方法が微妙に異なる
   - 本文の `add_crop_marks_overlay` が正しい形式（角トンボ + センタートンボ⊕）を実装している
   - 表紙の実装は本文と同じ仕様を目指しているが、実装の詳細が異なる

3. **コードの重複**: トンボ描画ロジックが複数箇所に散在しており、保守性が低い

## Correctness Properties

Property 1: Bug Condition - 表紙・裏表紙トンボ形式の統一

_For any_ `print_pdf` ターゲット時の表紙・裏表紙PDF生成において、固定された関数は本文と同じ形式のトンボ（角トンボ + センタートンボ⊕）を付与し、ページサイズは「仕上がりサイズ + 2 × (bleed_mm + CROP_MARK_OFFSET_MM)」となる。

**Validates: Requirements 2.1, 2.2, 2.3, 2.4**

Property 2: Preservation - 非print_pdfターゲットの動作保持

_For any_ `print_pdf` 以外のターゲット（`pdf`, `epub`）または本文PDF生成において、固定されたコードは既存の動作を完全に保持し、トンボなしPDFのページサイズは「仕上がりサイズ + 2 × bleed_mm」、EPUB用JPEGはトンボなし、本文PDFは既存のトンボ付与処理を使用する。

**Validates: Requirements 3.1, 3.2, 3.3, 3.4**

## Fix Implementation

### Changes Required

根本原因分析に基づき、以下の変更を実装する:

**File**: `lib/vivlio/starter/cli/create.rb`

**Function**: `convert_svg_to_pdf_with_crop_marks`

**Specific Changes**:
1. **トンボ描画処理の統一**: `convert_svg_to_pdf_with_crop_marks` メソッドから `add_crop_marks_overlay` メソッドを呼び出すように変更
   - 既存の `add_crop_marks_overlay` 呼び出しは既に実装されているため、動作を確認する
   - SVGテーマの表紙・裏表紙が本文と同じトンボ形式を使用することを保証する

**File**: `lib/vivlio/starter/cli/cover.rb`

**Function**: `generate_pdfx_single`

**Specific Changes**:
2. **PNGテーマのトンボ描画処理の統一**: `generate_pdfx_single` メソッドの `crop_marks: true` 時の処理を変更
   - ImageMagickの `-draw` コマンドによるトンボ描画を削除
   - 代わりに `add_crop_marks_overlay` メソッドを呼び出す（`create.rb` から `require_relative` で読み込む）
   - ページサイズ計算は既存のロジックを維持（仕上がりサイズ + 2 × (bleed_mm + crop_offset_mm)）

3. **中間PDF生成の調整**: トンボなしPDFを中間ファイルとして生成し、その後 `add_crop_marks_overlay` でトンボを追加
   - Step 1: 仕上がりサイズ + 2 × (bleed_mm + crop_offset_mm) のページサイズでPDFを生成（背景色のみ、トンボなし）
   - Step 2: `add_crop_marks_overlay` を呼び出してトンボオーバーレイを追加

4. **依存関係の追加**: `cover.rb` から `create.rb` の `add_crop_marks_overlay` メソッドにアクセスできるようにする
   - `CreateCommands` モジュールを `require_relative` で読み込む
   - または `add_crop_marks_overlay` を共通モジュールに移動する（将来的なリファクタリング）

5. **既存動作の保持**: `crop_marks: false` 時の処理は変更しない
   - トンボなしPDFのページサイズは「仕上がりサイズ + 2 × bleed_mm」を維持

## Testing Strategy

### Validation Approach

テスト戦略は2段階のアプローチに従う: まず、未修正コードでバグを実証する反例を表面化させ、次に修正が正しく機能し、既存の動作を保持することを検証する。

### Exploratory Bug Condition Checking

**Goal**: 修正を実装する前にバグを実証する反例を表面化させる。根本原因分析を確認または反証する。反証した場合は、再仮説を立てる必要がある。

**Test Plan**: SVGテーマとPNGテーマの両方で `print_pdf` ターゲット時に表紙・裏表紙PDFを生成し、トンボ形式を検証するテストを作成する。未修正コードでこれらのテストを実行し、失敗を観察して根本原因を理解する。

**Test Cases**:
1. **SVGテーマ表紙トンボ検証**: light/darkテーマで表紙PDFを生成し、トンボ形式が本文と一致するか検証（未修正コードでは失敗する可能性）
2. **PNGテーマ表紙トンボ検証**: master/カスタムテーマで表紙PDFを生成し、トンボ形式が本文と一致するか検証（未修正コードでは失敗する可能性）
3. **ページサイズ検証**: トンボ付きPDFのページサイズが「仕上がりサイズ + 2 × (bleed_mm + CROP_MARK_OFFSET_MM)」であることを検証（未修正コードでは失敗する可能性）
4. **トンボ要素の存在確認**: 角トンボ（4隅の直線）とセンタートンボ（⊕形状）が正しく配置されているか検証（未修正コードでは失敗する可能性）

**Expected Counterexamples**:
- 表紙・裏表紙PDFのトンボ形式が本文と異なる
- 可能な原因: 異なるトンボ描画メソッドの使用、ImageMagickとPrawn+CombinePDFの描画の違い、ページサイズ計算の不一致

### Fix Checking

**Goal**: バグ条件が成立するすべての入力に対して、修正された関数が期待される動作を生成することを検証する。

**Pseudocode:**
```
FOR ALL input WHERE isBugCondition(input) DO
  result := generateCoverPDF_fixed(input)
  ASSERT expectedBehavior(result)
END FOR
```

**Testing Approach**: 修正後、SVGテーマとPNGテーマの両方で表紙・裏表紙PDFを生成し、トンボ形式が本文と一致することを検証する。

### Preservation Checking

**Goal**: バグ条件が成立しないすべての入力に対して、修正された関数が元の関数と同じ結果を生成することを検証する。

**Pseudocode:**
```
FOR ALL input WHERE NOT isBugCondition(input) DO
  ASSERT generateCoverPDF_original(input) = generateCoverPDF_fixed(input)
END FOR
```

**Testing Approach**: プロパティベーステストは保存チェックに推奨される。なぜなら:
- 入力ドメイン全体で多くのテストケースを自動生成する
- 手動ユニットテストが見逃す可能性のあるエッジケースをキャッチする
- 非バグ入力に対して動作が変更されていないという強力な保証を提供する

**Test Plan**: まず未修正コードで `pdf` ターゲットとEPUB生成の動作を観察し、その後その動作を捉えるプロパティベーステストを作成する。

**Test Cases**:
1. **pdfターゲット保存**: 未修正コードで `pdf` ターゲット時にトンボなしPDFが生成されることを観察し、修正後も同じ動作が継続することを検証するテストを作成
2. **ページサイズ保存**: 未修正コードでトンボなしPDFのページサイズが「仕上がりサイズ + 2 × bleed_mm」であることを観察し、修正後も同じであることを検証するテストを作成
3. **EPUB生成保存**: 未修正コードでEPUB用JPEG生成が正しく動作することを観察し、修正後も同じであることを検証するテストを作成
4. **本文PDF保存**: 本文PDFのトンボ付与処理が修正の影響を受けないことを検証するテストを作成

### Unit Tests

- SVGテーマ（light/dark）で `print_pdf` ターゲット時に表紙・裏表紙PDFを生成し、トンボ形式を検証
- PNGテーマ（master/カスタム）で `print_pdf` ターゲット時に表紙・裏表紙PDFを生成し、トンボ形式を検証
- `pdf` ターゲット時にトンボなしPDFが生成されることを検証
- トンボ付きPDFのページサイズが正しいことを検証
- トンボなしPDFのページサイズが正しいことを検証

### Property-Based Tests

- ランダムなテーマ（light/dark/master/カスタム）とページサイズ（A4/B5/A5）の組み合わせで表紙PDFを生成し、トンボ形式が一貫していることを検証
- ランダムなbleed値（0mm〜10mm）でトンボ付きPDFを生成し、ページサイズ計算が正しいことを検証
- ランダムなターゲット設定（pdf/print_pdf/epub）で表紙生成を実行し、保存要件が満たされることを検証

### Integration Tests

- 完全なビルドフロー（本文 + 表紙・裏表紙）を実行し、すべてのPDFが同じトンボ形式を持つことを検証
- 複数のテーマとターゲットの組み合わせでビルドを実行し、出力が正しいことを検証
- 印刷所入稿用PDFを生成し、トンボが正しく配置されていることを目視確認
