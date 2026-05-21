# 実装計画書: img2pdf依存の排除および仕様書への準拠

[pdf_pages_rasterize_spec.md](file:///Users/mirai/projects/vivlio-starter/docs/specs/pdf_pages_rasterize_spec.md) の仕様に準拠するよう、`vs pdf:rasterize` コマンドを修正します。GPT-5.5がJPEGからPDFを再結合するカスタムジェネレータ（`JpegToPdf`）を独自実装しましたが、コードベースにいくつかの `img2pdf` の存在チェック、参照、およびテストが残ったままになっています。本計画では、`img2pdf` を完全に排除し、`vs doctor` をクリーンアップし、テストスイートを修正します。

## ユーザーレビューが必要な項目
破壊的変更や重大なリスクはありません。この変更により、禁止されている外部依存関係（`img2pdf`）が完全に排除され、独自実装のPDFビルダーが徹底的にテストされるようになります。

## 未解決の質問
ありません。仕様は明確であり、`img2pdf` は使用せず、このコマンドスイートに関して `vs doctor` は `pdftoppm` のみをチェックする必要があります。

## 提案される変更内容

---

### CLI Doctor & コマンドのクリーンアップ

#### [MODIFY] [doctor.rb](file:///Users/mirai/projects/vivlio-starter/lib/vivlio/starter/cli/doctor.rb)
- 環境診断リスト（`checks`）から `img2pdf` を削除します。
- `--fix` の実装から `img2pdf` のインストールロジックを削除します。
- `DOCTOR_DESC` および `describe_missing` を更新し、`img2pdf` への参照を削除します。

#### [MODIFY] [pdf.rb](file:///Users/mirai/projects/vivlio-starter/lib/vivlio/starter/cli/pdf.rb)
- `ensure_pdf_rasterize_tools!` における `img2pdf` の外部コマンド存在チェックを削除します。

---

### テストスイートの調整と堅牢化

#### [MODIFY] [doctor_commands_test.rb](file:///Users/mirai/projects/vivlio-starter/test/vivlio/starter/cli/doctor_commands_test.rb)
- `img2pdf` は診断項目から除外されるため、`test_doctor_fix_installs_img2pdf_when_missing` テストを削除します。
- ローカル環境のNode.jsやPlaywrightのインストール状況に関わらず、すべての開発環境でテストが安定してパスするように、`test_doctor_fix_copies_textlint_assets_when_environment_complete` 内で `playwright_npm_available?`、`chromium_available?`、および `rouge_gem_available?` を `true` にスタブ（モック）します。

#### [MODIFY] [jpeg_to_pdf_test.rb](file:///Users/mirai/projects/vivlio-starter/test/vivlio/starter/pdf/jpeg_to_pdf_test.rb)
- 旧来の `img2pdf` コマンド実行を検証し、現在は ArgumentError を発生させている `test_should_merge_jpegs_with_img2pdf` を削除します。
- インメモリで最小限の有効なダミーJPEGファイルを生成して一時ファイルに書き出し、`JpegToPdf.convert` がそれを正しくPDF形式にコンパイルできるかを実際に検証するインテグレーション/ユニットテスト `test_should_convert_jpegs_to_pdf` を新規追加します。

---

### ドキュメントの更新

#### [MODIFY] [CHANGELOG.md](file:///Users/mirai/projects/vivlio-starter/CHANGELOG.md)
- `unreleased > Added` にある `vs pdf:rasterize` の項目から `img2pdf` に関する記述を削除し、外部依存関係なしの独自実装 `JpegToPdf` を使用している旨を明記します。

---

## 検証計画

### 自動テスト
- 以下のコマンドを実行して個別のテストを検証します：
  `bundle exec ruby -Ilib:test test/vivlio/starter/pdf/jpeg_to_pdf_test.rb`
  `bundle exec ruby -Ilib:test test/vivlio/starter/cli/doctor_commands_test.rb`
- 1000以上の全テストケースを実行し、すべてパスすることを確認します：
  `bundle exec rake test`
