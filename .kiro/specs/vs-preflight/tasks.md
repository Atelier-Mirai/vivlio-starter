# 実装計画: vs-preflight

## 概要

`vs preflight` コマンドを実装する。既存の `UnifiedBuildPipeline` に `mode: :preflight` を追加し、
`PreflightCommand` を新規作成して CLI に統合する。

## タスク

- [x] 1. `UnifiedBuildPipeline` に preflight モードを追加する
  - `register_steps` を pattern matching に変更し、`in :preflight` ブランチを追加する
  - `register_preflight_steps` メソッドを追加し、Step 1〜4 のみを登録する
  - 対象ファイル: `lib/vivlio/starter/cli/build/pipeline.rb`
  - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 7.3_

- [x] 2. `PreflightCommand` を新規作成する
  - [x] 2.1 `lib/vivlio/starter/cli/samovar/preflight_command.rb` を作成する
    - `Samovar::Command` を継承し、`targets`・`--[no]-resize`・`--log`・`-h/--help` を定義する
    - `call` メソッドで `--help` 表示・`LinkImageValidator.reset!`・`TokenResolver::Resolver#resolve`・`UnifiedBuildPipeline.new(self, entries:, mode: :preflight).run`・サマリー表示・終了コード返却を実装する
    - `normalize_log_option_tokens` は `BuildCommand` と同一ロジックを使用する
    - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 3.5, 3.6, 3.7, 4.1, 4.2, 4.3, 6.1, 6.4_

  - [x]* 2.2 `PreflightCommand` の例示テストを書く（`test/cli/samovar/preflight_command_test.rb`）
    - `test_should_run_all_chapters_when_no_targets_given`
    - `test_should_resolve_chapter_number_token`
    - `test_should_resolve_range_token`
    - `test_should_skip_step1_when_no_resize`
    - `test_should_skip_step4_when_index_disabled`
    - `test_should_not_generate_html_or_pdf`
    - `test_should_register_in_public_commands`
    - `test_should_appear_in_help_output`
    - `test_should_print_help_with_help_option`
    - _Requirements: 1.1, 1.2, 1.3, 2.1, 2.4, 2.5, 6.2, 6.3_

- [x] 3. CLI に `PreflightCommand` を統合する
  - [x] 3.1 `lib/vivlio/starter/cli/samovar.rb` に `require_relative 'samovar/preflight_command'` を追加する
    - _Requirements: 6.5_

  - [x] 3.2 `lib/vivlio/starter/cli/samovar/root_command.rb` の `public_commands` に `'preflight' => PreflightCommand` を追加する
    - _Requirements: 6.2_

  - [x] 3.3 `lib/vivlio/starter/cli/samovar/help_command.rb` の `COMMAND_CATEGORIES` に preflight を追加する
    - カテゴリ「ビルド・出力・プレビュー」に `'preflight' => 'ビルド前の原稿エラーチェックを高速実行します（Step 1〜4 のみ）'` を追加する
    - _Requirements: 6.3_

  - [x] 3.4 `lib/vivlio/starter/cli/loader.rb` に `require_relative 'preflight'` を追加する（`preflight.rb` が必要な場合のみ）
    - _Requirements: 6.5_

- [x] 4. チェックポイント — 全テストがパスすることを確認する
  - 全テストがパスすることを確認する。問題があればユーザーに確認する。

- [x] 5. プロパティテストを書く（`test/cli/build/preflight_pipeline_test.rb`）
  - [x]* 5.1 Property 1: 全 Entry に対して前処理が実行される
    - **Property 1: 全 Entry に対して前処理が実行される**
    - Generator: 1〜10件のランダムな Entry 配列
    - Assert: `preprocess_sections!` が entries 全体に対して呼ばれる
    - **Validates: Requirements 2.3**

  - [x]* 5.2 Property 2: 画像警告フォーマットの正確性
    - **Property 2: 画像警告フォーマットの正確性**
    - Generator: ランダムなファイル名・行番号・画像名
    - Assert: メッセージが `/⚠️ .+:\d+ - 画像 '.+' が見つかりません/` にマッチ
    - **Validates: Requirements 3.1**

  - [x]* 5.3 Property 3: コードインクルードエラーフォーマットの正確性
    - **Property 3: コードインクルードエラーフォーマットの正確性**
    - Generator: ランダムなファイルパス
    - Assert: メッセージが `/❌ ファイルが見つかりません: .+/` にマッチ
    - **Validates: Requirements 3.2**

  - [x]* 5.4 Property 4: QueryStream エラーフォーマットの正確性
    - **Property 4: QueryStream エラーフォーマットの正確性**
    - Generator: ランダムな詳細メッセージ
    - Assert: メッセージが `/❌ QueryStream 展開エラー: .+/` にマッチ
    - **Validates: Requirements 3.3**

  - [x]* 5.5 Property 5: クロスリファレンス警告フォーマットの正確性
    - **Property 5: クロスリファレンス警告フォーマットの正確性**
    - Generator: ランダムなファイル名・行番号・ラベルID
    - Assert: メッセージが `/⚠️ .+:\d+ - 未定義のラベルID: .+/` にマッチ
    - **Validates: Requirements 3.4**

  - [x]* 5.6 Property 6: サマリーの完全性
    - **Property 6: サマリーの完全性**
    - Generator: ランダムな警告件数・エラー件数・経過時間
    - Assert: サマリー文字列が警告件数・エラー件数・経過時間の全てを含む
    - **Validates: Requirements 3.5**

  - [x]* 5.7 Property 7: 終了コードとエラー件数の関係
    - **Property 7: 終了コードとエラー件数の関係**
    - Generator: ランダムな非負整数（エラー件数）
    - Assert: `exit_code == (error_count > 0 ? 1 : 0)`
    - **Validates: Requirements 3.6, 3.7**

- [x] 6. `CHANGELOG.md` を更新する
  - `### Added` セクションに `vs preflight` コマンドの追加を記載する
  - _Requirements: 全般_

## Notes

- `*` 付きタスクはオプション。MVP を優先する場合はスキップ可
- プロパティテストには `propcheck` gem を使用する（最低 100 イテレーション）
- タグ形式: `# Feature: vs-preflight, Property {N}: {property_text}`
- `register_steps` の pattern matching 変更は既存の `:single` / `:full` 動作を壊さないよう注意する
