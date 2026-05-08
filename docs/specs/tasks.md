# 実装計画: Techbook モード

## 概要

Techbook モードの実装を、コアクラス → パイプライン統合 → legalpage 拡張の順に進める。各ステップは前のステップの成果物に依存し、最終的にすべてのコンポーネントが `UnifiedBuildPipeline` に統合される。テストは propcheck gem によるプロパティベーステストと Minitest ユニットテストを併用する。

## タスク

- [x] 1. EmojiReplacer の実装とテスト
  - [x] 1.1 `lib/vivlio/starter/cli/techbook/emoji_replacer.rb` を作成する
    - `Vivlio::Starter::CLI::Techbook::EmojiReplacer` クラスを実装
    - コンストラクタで `emoji_dir` を DI 可能にする（デフォルトは gem 同梱の `stylesheets/twemoji/`）
    - `EMOJI_REGEX` 定数で `\p{Emoji_Presentation}` + `\p{Emoji}\uFE0F` を検出
    - `process(html)` メソッドで絵文字を `<img>` タグに差し替え
    - `emoji_codepoint(char)` で Variation Selector-16（U+FE0F）を除外し、小文字16進数ハイフン結合
    - `build_img_tag(char, svg_path)` で `src`（絶対パス）、`alt`、`class="emoji vs-emoji"`、`width="1em"`、`height="1em"`、`style="vertical-align: -0.15em;"` を含む img タグを生成
    - SVG ファイルが存在しない絵文字はそのまま残す
    - Ruby 4.0+ イディオム（`it` パラメータ、エンドレスメソッド）を使用
    - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 2.7, 7.2, 9.1, 9.2, 9.3_

  - [ ]* 1.2 `test/vivlio/starter/cli/techbook/emoji_replacer_test.rb` を作成し、ユニットテストを書く
    - テスト用 SVG フィクスチャディレクトリを `test/vivlio/starter/cli/techbook/fixtures/twemoji/` に作成
    - テスト用 SVG ファイル（`2705.svg`、`274c.svg`、`1f534.svg` 等）を配置
    - `test_should_replace_checkmark_emoji`: ✅ → `<img src=".../2705.svg" ...>` の変換を検証
    - `test_should_skip_emoji_without_svg`: SVG なし絵文字がそのまま残ることを検証
    - `test_should_replace_all_occurrences_of_same_emoji`: 同一絵文字の複数箇所置換を検証
    - `test_should_return_html_unchanged_when_no_emoji`: 絵文字なし HTML がそのまま返ることを検証
    - `test_should_preserve_surrounding_html_tags`: `<p>✅ OK</p>` の HTML 構造保全を検証
    - `test_should_resolve_emoji_dir_from_gem_path`: デフォルトパスが gem 内の `stylesheets/twemoji/` を指すことを検証
    - `test_should_handle_compound_emoji`: 複合絵文字（ZWJ シーケンス等）のコードポイント変換を検証
    - DAMP > DRY 原則に従い、各テストで Arrange/Act/Assert が完結
    - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.6, 2.7, 9.1, 9.2, 9.3_

  - [ ]* 1.3 EmojiReplacer のプロパティベーステストを書く（propcheck gem 使用）
    - [ ]* 1.3.1 **Property 3: 非絵文字コンテンツの保全** のプロパティテストを書く
      - **Property 3: 非絵文字コンテンツの保全**
      - ランダムな ASCII/HTML 文字列（絵文字なし）を生成し、EmojiReplacer が入力をそのまま返すことを検証
      - **Validates: Requirements 2.3, 2.7**
    - [ ]* 1.3.2 **Property 4: コードポイント変換の正当性** のプロパティテストを書く
      - **Property 4: コードポイント変換の正当性**
      - ランダムな Unicode 文字列に対して `emoji_codepoint` が小文字16進数ハイフン結合を返し、U+FE0F を除外することを検証
      - **Validates: Requirements 2.4**
    - [ ]* 1.3.3 **Property 8: 絵文字差し替え時の HTML 構造保全** のプロパティテストを書く
      - **Property 8: 絵文字差し替え時の HTML 構造保全**
      - ランダムな HTML 要素（`<p>`、`<li>`、`<td>` 等）内に絵文字を配置し、囲んでいるタグ・属性・非絵文字テキストが保全されることを検証
      - **Validates: Requirements 9.1, 9.3**

- [x] 2. VariableFontInjector の実装とテスト
  - [x] 2.1 `lib/vivlio/starter/cli/techbook/variable_font_injector.rb` を作成する
    - `Vivlio::Starter::CLI::Techbook::VariableFontInjector` クラスを実装
    - コンストラクタで `font_configs`（Array<Hash>）を受け取る
    - `css` メソッドで静的 `@font-face` 宣言を生成
    - `font-family` はファミリー名-ウェイト形式（例: `"Noto Sans JP-400"`）
    - `src` は `url("...") format("woff2")` 形式
    - `font-weight`、`font-style: normal`、`font-variation-settings` を含む
    - `config_value` ヘルパーで Hash / Data 両対応のアクセサを提供
    - 必須フィールド（`family`、`src`、`instances`）が欠けているエントリはスキップし、`Common.log_warn` で警告
    - 設定なし・空配列の場合は空文字列を返す
    - _Requirements: 5.1, 5.2, 5.3, 5.4, 8.1, 8.2, 8.3_

  - [ ]* 2.2 `test/vivlio/starter/cli/techbook/variable_font_injector_test.rb` を作成し、ユニットテストを書く
    - `test_should_generate_font_face_for_each_instance`: 2インスタンス設定で2つの `@font-face` が生成されることを検証
    - `test_should_return_empty_css_when_no_configs`: 空配列で空文字列が返ることを検証
    - `test_should_skip_entry_missing_family`: `family` 欠落エントリがスキップされることを検証
    - `test_should_skip_entry_missing_src`: `src` 欠落エントリがスキップされることを検証
    - `test_should_skip_entry_missing_instances`: `instances` 欠落エントリがスキップされることを検証
    - `test_should_derive_font_family_name_with_weight`: `font-family` が `"ファミリー名-ウェイト"` 形式であることを検証
    - _Requirements: 5.1, 5.2, 5.3, 8.1, 8.2, 8.3_

  - [ ]* 2.3 VariableFontInjector のプロパティベーステストを書く（propcheck gem 使用）
    - [ ]* 2.3.1 **Property 6: 可変フォント @font-face 宣言の生成** のプロパティテストを書く
      - **Property 6: 可変フォント @font-face 宣言の生成**
      - ランダムなフォント設定（`family`、`src`、`instances` を含む）を生成し、各インスタンスごとに正しい `@font-face` ブロックが生成されることを検証
      - **Validates: Requirements 5.1, 5.2**
    - [ ]* 2.3.2 **Property 7: 不完全なフォント設定のスキップ** のプロパティテストを書く
      - **Property 7: 不完全なフォント設定のスキップ**
      - 必須フィールドをランダムに欠落させた設定を生成し、不正なエントリに対する `@font-face` 宣言が生成されないことを検証
      - **Validates: Requirements 8.3**

- [x] 3. Processor の実装とテスト
  - [x] 3.1 `lib/vivlio/starter/cli/techbook/processor.rb` を作成する
    - `Vivlio::Starter::CLI::Techbook::Processor` クラスを実装
    - コンストラクタで `config`（`Common::CONFIG` の Data ラッパー）を受け取る
    - `config.output&.pdf&.techbook == true` で有効化判定
    - `enabled?` エンドレスメソッドで有効/無効を返す
    - `process(html)` で有効時に `EmojiReplacer.new.process(html)` を実行、無効時はそのまま返す
    - `inject_css` で有効時に絵文字 CSS + VariableFontInjector の CSS を結合して返す、無効時は空文字列
    - `emoji_css` プライベートメソッドで `img.vs-emoji` ルール（`display: inline`、`width: 1em`、`height: 1em`、`vertical-align: -0.15em`）を返す
    - `variable_font_configs` プライベートメソッドで `config.output&.pdf&.variable_fonts` を Array 化して返す
    - _Requirements: 1.1, 1.2, 1.3, 1.4, 3.1, 3.2, 6.1, 6.2, 6.3, 6.4_

  - [ ]* 3.2 `test/vivlio/starter/cli/techbook/processor_test.rb` を作成し、ユニット・統合テストを書く
    - テスト用の config オブジェクトを `Common.wrap_config` で生成（DI パターン）
    - `test_should_enable_when_techbook_true`: `techbook: true` で `enabled?` が `true` を返すことを検証
    - `test_should_disable_when_techbook_false`: `techbook: false` で `enabled?` が `false` を返すことを検証
    - `test_should_disable_when_techbook_omitted`: キー省略時に `enabled?` が `false` を返すことを検証
    - `test_should_return_html_unchanged_when_disabled`: 無効時に `process` が入力 HTML をそのまま返すことを検証
    - `test_should_inject_emoji_css_when_enabled`: `inject_css` に `img.vs-emoji` ルールが含まれることを検証
    - `test_should_return_empty_css_when_disabled`: 無効時に `inject_css` が空文字列を返すことを検証
    - `test_should_inject_both_emoji_and_font_css`: 有効時に `inject_css` が絵文字 CSS とフォント CSS の両方を含むことを検証
    - `test_should_process_html_with_mixed_emoji_and_text`: 絵文字とテキストが混在する HTML の正しい処理を検証（統合テスト）
    - _Requirements: 1.1, 1.2, 1.3, 3.1, 3.2, 6.1, 6.2, 6.3, 6.4_

  - [ ]* 3.3 Processor のプロパティベーステストを書く（propcheck gem 使用）
    - [ ]* 3.3.1 **Property 1: 無効モードでの HTML パススルー** のプロパティテストを書く
      - **Property 1: 無効モードでの HTML パススルー**
      - ランダムな HTML 文字列を生成し、Techbook モード無効の Processor で `process` を呼び出した場合に入力と同一の文字列が返されることを検証
      - **Validates: Requirements 1.2, 1.3, 6.4**
    - [ ]* 3.3.2 **Property 2: 絵文字の SVG img タグ差し替え** のプロパティテストを書く
      - **Property 2: 絵文字の SVG img タグ差し替え**
      - ランダムな絵文字 + モック SVG ディレクトリを使用し、対応する SVG が存在する絵文字がすべて `<img>` タグに置換されることを検証
      - **Validates: Requirements 2.2, 2.6, 9.2**

- [x] 4. チェックポイント - コアクラスの検証
  - すべてのテストが通ることを確認し、疑問点があればユーザーに質問する。

- [x] 5. execute_legalpage の Twemoji クレジット拡張
  - [x] 5.1 `lib/vivlio/starter/cli/create.rb` の `execute_legalpage` メソッドを拡張する
    - 免責・商標セクション生成後に `Common::CONFIG.legal&.twemoji` を参照
    - `legal.twemoji` が設定されており空でない場合、`<div class="twemoji-credit">` で囲んだクレジットセクションを追加
    - `<h2>■絵文字クレジット</h2>` の見出しを付ける
    - `legal.twemoji` のテキストを行ごとに `<p>` タグで出力
    - `legal.twemoji` が省略または空の場合はクレジットセクションを生成しない
    - _Requirements: 4.1, 4.2, 4.3, 4.4, 4.5_

  - [ ]* 5.2 `test/vivlio/starter/cli/techbook/legalpage_twemoji_test.rb` を作成し、テストを書く
    - `test_should_generate_twemoji_credit_section`: `legal.twemoji` 設定時にクレジットセクションが生成されることを検証
    - `test_should_omit_twemoji_credit_when_not_set`: `legal.twemoji` 未設定時にクレジットなしを検証
    - `test_should_omit_twemoji_credit_when_empty_string`: 空文字列時にクレジットなしを検証
    - `test_should_output_multiline_twemoji_credit_as_separate_p_tags`: 複数行テキストが個別の `<p>` タグで出力されることを検証
    - `test_should_wrap_credit_in_twemoji_credit_div`: `<div class="twemoji-credit">` で囲まれていることを検証
    - _Requirements: 4.1, 4.2, 4.3, 4.4_

  - [ ]* 5.3 legalpage Twemoji クレジットのプロパティベーステストを書く（propcheck gem 使用）
    - [ ]* 5.3.1 **Property 5: Twemoji クレジットセクションの構造** のプロパティテストを書く
      - **Property 5: Twemoji クレジットセクションの構造**
      - ランダムな非空の複数行テキストを生成し、生成される HTML が `<div class="twemoji-credit">` で囲まれ、`<h2>■絵文字クレジット</h2>` を含み、各行が個別の `<p>` タグで出力されることを検証
      - **Validates: Requirements 4.2, 4.3**

- [x] 6. パイプライン統合
  - [x] 6.1 `lib/vivlio/starter/cli/build/pipeline.rb` の `register_common_prep_steps` に Techbook 処理ステップを追加する
    - Step 5b（part title pages）の後に `Step 5c (techbook post-process)` を追加
    - `run_techbook_post_process` プライベートメソッドを実装: `Techbook::Processor` を初期化し、生成済み HTML ファイルに対して `process` を実行
    - `Step 5d (techbook css inject)` を追加: `inject_css` の結果を HTML の `<head>` 内に `<style>` タグとして注入
    - `techbook: true` でない場合は何もしない（Processor 内部で判定）
    - `require_relative '../techbook/processor'` を pipeline.rb に追加
    - _Requirements: 6.5, 1.1_

- [x] 7. 最終チェックポイント - 全テスト実行
  - すべてのテストが通ることを確認し、疑問点があればユーザーに質問する。

## 備考

- `*` マーク付きタスクはオプションであり、MVP では省略可能
- 各タスクは具体的な要件番号を参照しており、トレーサビリティを確保
- チェックポイントでインクリメンタルな検証を実施
- プロパティベーステストは設計書の正当性プロパティ（Property 1〜8）に対応
- ユニットテストは具体例とエッジケースを検証
- Ruby 4.0+ イディオム（`it` パラメータ、エンドレスメソッド、パターンマッチング、ハッシュ省略記法）を全コードで使用すること
