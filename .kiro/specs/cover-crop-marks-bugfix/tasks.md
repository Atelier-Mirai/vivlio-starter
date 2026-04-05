# 実装計画

- [x] 1. バグ条件探索テストを作成（修正前に実行）
  - **Property 1: Bug Condition** - 表紙・裏表紙トンボ形式の不一致
  - **重要**: このテストは修正前のコードで実行し、失敗することを確認する
  - **失敗は正常**: テストの失敗はバグの存在を証明する
  - **目標**: バグを実証する反例を表面化させる
  - **スコープ付きPBTアプローチ**: 決定論的なバグのため、具体的な失敗ケースにプロパティをスコープする
  - SVGテーマ（light/dark）とPNGテーマ（master/カスタム）の両方で `print_pdf` ターゲット時に表紙・裏表紙PDFを生成
  - トンボ形式が本文と一致するかを検証（Bug Condition仕様の `isBugCondition` 疑似コードから）
  - テストアサーションは設計のExpected Behavior Propertiesと一致させる
  - 未修正コードでテストを実行
  - **期待される結果**: テストが失敗する（これは正しい - バグが存在することを証明）
  - 反例を文書化して根本原因を理解する
  - テストが作成され、実行され、失敗が文書化されたらタスクを完了とする
  - _Requirements: 1.1, 1.2, 1.3_

- [x] 2. 保存プロパティテストを作成（修正前に実行）
  - **Property 2: Preservation** - 非print_pdfターゲットの動作保持
  - **重要**: 観察優先の方法論に従う
  - 観察: 未修正コードで `pdf` ターゲット時にトンボなしPDFが生成される
  - 観察: 未修正コードでトンボなしPDFのページサイズは「仕上がりサイズ + 2 × bleed_mm」
  - 観察: 未修正コードでEPUB用JPEG生成が正しく動作する
  - 設計のPreservation Requirementsから観察された動作パターンを捉えるプロパティベーステストを作成
  - プロパティベーステストは多くのテストケースを生成し、より強力な保証を提供する
  - 未修正コードでテストを実行
  - **期待される結果**: テストが成功する（ベースライン動作を確認）
  - テストが作成され、実行され、未修正コードで成功したらタスクを完了とする
  - _Requirements: 3.1, 3.2, 3.3, 3.4_

- [x] 3. 表紙・裏表紙トンボ付与の修正

  - [x] 3.1 PNGテーマのトンボ描画処理を修正
    - `lib/vivlio/starter/cli/cover.rb` の `generate_pdfx_single` メソッドを修正
    - `crop_marks: true` 時にImageMagickの `-draw` コマンドによるトンボ描画を削除
    - 代わりに `add_crop_marks_overlay` メソッドを呼び出す（`create.rb` から `require_relative` で読み込む）
    - 中間PDFを生成し、その後 `add_crop_marks_overlay` でトンボを追加
    - ページサイズ計算は既存のロジックを維持（仕上がりサイズ + 2 × (bleed_mm + crop_offset_mm)）
    - `crop_marks: false` 時の処理は変更しない
    - _Bug_Condition: isBugCondition(input) where input.target = 'print_pdf' AND input.file_type IN ['frontcover', 'backcover']_
    - _Expected_Behavior: expectedBehavior(result) from design - 表紙・裏表紙PDFに本文と同じ形式のトンボ（角トンボ + センタートンボ）が付与される_
    - _Preservation: Preservation Requirements from design - pdf ターゲット、EPUB生成、本文PDF生成が影響を受けない_
    - _Requirements: 1.1, 1.2, 1.3, 2.1, 2.2, 2.3, 2.4, 3.1, 3.2, 3.3, 3.4_

  - [x] 3.2 SVGテーマのトンボ形式を確認
    - `lib/vivlio/starter/cli/create.rb` の `convert_svg_to_pdf_with_crop_marks` メソッドを確認
    - 既に `add_crop_marks_overlay` を呼び出しているか確認
    - 必要に応じて修正（PNGテーマと同じアプローチ）
    - _Requirements: 2.2_

  - [x] 3.3 バグ条件探索テストを再実行して修正を検証
    - **Property 1: Expected Behavior** - 表紙・裏表紙トンボ形式の統一
    - **重要**: タスク1と同じテストを再実行する - 新しいテストを作成しない
    - タスク1のテストは期待される動作をエンコードしている
    - このテストが成功すると、期待される動作が満たされていることを確認
    - タスク1のバグ条件探索テストを実行
    - **期待される結果**: テストが成功する（バグが修正されたことを確認）
    - _Requirements: Expected Behavior Properties from design - 2.1, 2.2, 2.3, 2.4_

  - [x] 3.4 保存テストを再実行して回帰がないことを検証
    - **Property 2: Preservation** - 非print_pdfターゲットの動作保持
    - **重要**: タスク2と同じテストを再実行する - 新しいテストを作成しない
    - タスク2の保存プロパティテストを実行
    - **期待される結果**: テストが成功する（回帰がないことを確認）
    - 修正後もすべてのテストが成功することを確認（回帰なし）

- [x] 4. チェックポイント - すべてのテストが成功することを確認
  - すべてのテストが成功することを確認し、質問があればユーザーに尋ねる
