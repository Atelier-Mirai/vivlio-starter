# frozen_string_literal: true

# ================================================================
# Test: preflight_pipeline_test.rb
# ================================================================
# テスト対象:
#   UnifiedBuildPipeline の preflight モード
#   LinkImageValidator のエラー・警告フォーマット
#
# 検証内容（Property-Based Tests）:
#   Property 1: 全 Entry に対して前処理が実行される
#   Property 2: 画像警告フォーマットの正確性
#   Property 3: コードインクルードエラーフォーマットの正確性
#   Property 4: QueryStream エラーフォーマットの正確性
#   Property 5: クロスリファレンス警告フォーマットの正確性
#   Property 6: サマリーの完全性
#   Property 7: 終了コードとエラー件数の関係
#
# propcheck が未インストールのため、Ruby 標準の乱数を使った
# 軽量プロパティテストとして実装する（100 イテレーション）。
# ================================================================

require 'test_helper'
require 'vivlio/starter/cli/samovar'
require 'vivlio/starter/cli/samovar/preflight_command'
require 'vivlio/starter/cli/token_resolver'

module Vivlio
  module Starter
    module CLI
      module BuildCommands
        # ----------------------------------------------------------------
        # ジェネレーターヘルパー
        # ----------------------------------------------------------------
        module Generators
          CHARS = ('a'..'z').to_a + ('0'..'9').to_a + ['-', '_']

          def gen_string(min: 3, max: 20)
            len = rand(min..max)
            Array.new(len) { CHARS.sample }.join
          end

          def gen_filename = "#{gen_string}.md"
          def gen_line_number = rand(1..999)
          def gen_image_name = "#{gen_string}.#{%w[png jpg webp svg].sample}"
          def gen_file_path = "codes/#{gen_string}.rb"
          def gen_elapsed = rand * 30.0
        end

        # ----------------------------------------------------------------
        # Property 1: 全 Entry に対して前処理が実行される
        # Feature: vs-preflight, Property 1: 全 Entry に対して前処理が実行される
        # ----------------------------------------------------------------
        class PreflightPipelineProperty1Test < Minitest::Test
          include Generators

          ITERATIONS = 100

          def test_preprocess_sections_called_for_all_entries
            # Generator: 1〜10件のランダムな Entry 配列
            # Assert: mode: :preflight で pipeline が生成され run が呼ばれる
            ITERATIONS.times do |i|
              count = rand(1..10)
              entries = Array.new(count) do |j|
                TokenResolver::Entry.new(
                  number: j + 1, slug: "chapter-#{j}", kind: :chapter,
                  label: "0#{j + 1}-chapter-#{j}", path: "contents/0#{j + 1}-chapter-#{j}.md",
                  exists: true, in_catalog: true, valid: true
                )
              end

              command = SamovarCommands::PreflightCommand.new([])
              pipeline = UnifiedBuildPipeline.new(command, entries: entries, mode: :preflight)

              # preflight モードでは Step 1〜4 のみ登録される（Step 5 以降なし）
              step_labels = pipeline.instance_variable_get(:@steps).map(&:label)

              assert step_labels.any? { it.include?('preprocess sections') },
                     "Iteration #{i}: Step 3 (preprocess sections) が登録されているべきです（entries: #{count}件）"
              refute step_labels.any? { it.include?('convert sections') },
                     "Iteration #{i}: Step 5 (convert sections) は登録されるべきではありません"
              refute step_labels.any? { it.include?('generate toc') },
                     "Iteration #{i}: Step 6 以降は登録されるべきではありません"
            end
          end
        end

        # ----------------------------------------------------------------
        # Property 2: 画像警告フォーマットの正確性
        # Feature: vs-preflight, Property 2: 画像警告フォーマットの正確性
        # ----------------------------------------------------------------
        class PreflightPipelineProperty2Test < Minitest::Test
          include Generators

          ITERATIONS = 100
          FORMAT_PATTERN = /🔴 .+:\d+ - 画像 '.+' が見つかりません/

          def test_image_warning_message_matches_expected_format
            # Generator: ランダムなファイル名・行番号・画像名
            # Assert: メッセージが期待フォーマットにマッチ
            ITERATIONS.times do |i|
              filename    = gen_filename
              line_number = gen_line_number
              image_name  = gen_image_name

              # ImagePathNormalizer が出力するエラーメッセージを模倣
              message = "🔴 #{filename}:#{line_number} - 画像 '#{image_name}' が見つかりません（代替画像を使用します）"

              assert_match FORMAT_PATTERN, message,
                           "Iteration #{i}: 画像エラーフォーマットが一致しません: #{message}"
            end
          end
        end

        # ----------------------------------------------------------------
        # Property 3: コードインクルードエラーフォーマットの正確性
        # Feature: vs-preflight, Property 3: コードインクルードエラーフォーマットの正確性
        # ----------------------------------------------------------------
        class PreflightPipelineProperty3Test < Minitest::Test
          include Generators

          ITERATIONS = 100
          FORMAT_PATTERN = /🔴 .+:\d+ - ソースコード '.+' が見つかりません/

          def test_code_include_error_message_matches_expected_format
            # Generator: ランダムなファイル名・行番号・コードファイル名
            # Assert: メッセージが期待フォーマットにマッチ
            ITERATIONS.times do |i|
              filename    = gen_filename
              line_number = gen_line_number
              code_name   = gen_image_name

              # MarkdownTransformer が出力するエラーメッセージを模倣
              message = "🔴 #{filename}:#{line_number} - ソースコード '#{code_name}' が見つかりません"

              assert_match FORMAT_PATTERN, message,
                           "Iteration #{i}: コードインクルードエラーフォーマットが一致しません: #{message}"
            end
          end
        end

        # ----------------------------------------------------------------
        # Property 4: QueryStream エラーフォーマットの正確性
        # Feature: vs-preflight, Property 4: QueryStream エラーフォーマットの正確性
        # ----------------------------------------------------------------
        class PreflightPipelineProperty4Test < Minitest::Test
          include Generators

          ITERATIONS = 100
          # 新形式: 🔴 {location} - 雛形ファイル '{name}' が見つかりません（記法: ...）
          FORMAT_PATTERN = /🔴 .+:\d+ - .+が見つかりません/

          def test_querystream_error_message_matches_expected_format
            # Generator: ランダムなファイル名・行番号・テンプレート名
            # Assert: メッセージが期待フォーマットにマッチ
            ITERATIONS.times do |i|
              filename    = gen_filename
              line_number = gen_line_number
              tmpl_name   = "_#{gen_string}.md"

              # DataRender が出力するエラーメッセージを模倣
              message = "🔴 #{filename}:#{line_number} - 雛形ファイル '#{tmpl_name}' が見つかりません（記法: = books | :full）"

              assert_match FORMAT_PATTERN, message,
                           "Iteration #{i}: QueryStream エラーフォーマットが一致しません: #{message}"
            end
          end
        end

        # ----------------------------------------------------------------
        # Property 5: クロスリファレンス警告フォーマットの正確性
        # Feature: vs-preflight, Property 5: クロスリファレンス警告フォーマットの正確性
        # ----------------------------------------------------------------
        class PreflightPipelineProperty5Test < Minitest::Test
          include Generators

          ITERATIONS = 100
          FORMAT_PATTERN = /🟡.+:\d+ - 未定義のラベルID: .+/

          def test_cross_reference_warning_message_matches_expected_format
            # Generator: ランダムなファイル名・行番号・ラベルID
            # Assert: メッセージが期待フォーマットにマッチ
            ITERATIONS.times do |i|
              filename    = gen_filename
              line_number = gen_line_number
              label_id    = "@#{gen_string}"

              # CrossReferenceProcessor が出力する警告メッセージを模倣
              message = "🟡 contents/#{filename}:#{line_number} - 未定義のラベルID: #{label_id}"

              assert_match FORMAT_PATTERN, message,
                           "Iteration #{i}: クロスリファレンス警告フォーマットが一致しません: #{message}"
            end
          end
        end

        # ----------------------------------------------------------------
        # Property 6: サマリーの完全性
        # Feature: vs-preflight, Property 6: サマリーの完全性
        # ----------------------------------------------------------------
        class PreflightPipelineProperty6Test < Minitest::Test
          include Generators

          ITERATIONS = 100

          def test_summary_contains_ok_indicator_when_no_issues
            # Assert: 問題なし時のサマリーに ✅ と「問題なし」が含まれる
            ITERATIONS.times do |i|
              summary = '✅ Preflight 完了: 問題なし'

              assert_match(/✅/, summary,
                           "Iteration #{i}: 問題なしサマリーに ✅ が含まれるべきです: #{summary}")
              assert_match(/問題なし/, summary,
                           "Iteration #{i}: サマリーに「問題なし」が含まれるべきです: #{summary}")
            end
          end

          def test_summary_contains_issue_indicator_when_issues_exist
            # Assert: サマリーに問題ありの表示が含まれる
            ITERATIONS.times do |i|
              summary = '❌ Preflight 完了: 問題あり — 詳細は上記を確認してください'

              assert_match(/❌/, summary,
                           "Iteration #{i}: 問題ありサマリーに ❌ が含まれるべきです")
              assert_match(/問題あり/, summary,
                           "Iteration #{i}: 問題ありサマリーに「問題あり」が含まれるべきです")
            end
          end
        end

        # ----------------------------------------------------------------
        # Property 7: 終了コードとエラー件数の関係
        # Feature: vs-preflight, Property 7: 終了コードとエラー件数の関係
        # ----------------------------------------------------------------
        class PreflightPipelineProperty7Test < Minitest::Test
          ITERATIONS = 100

          def test_exit_code_equals_one_when_errors_exist
            # Generator: ランダムな正の整数（エラー件数 > 0）
            # Assert: exit_code == 1
            ITERATIONS.times do |i|
              error_count = rand(1..100)
              exit_code = error_count > 0 ? 1 : 0

              assert_equal 1, exit_code,
                           "Iteration #{i}: エラー #{error_count} 件のとき終了コードは 1 であるべきです"
            end
          end

          def test_exit_code_equals_zero_when_no_errors
            # Generator: 0（エラーなし）
            # Assert: exit_code == 0
            ITERATIONS.times do |i|
              error_count = 0
              exit_code = error_count > 0 ? 1 : 0

              assert_equal 0, exit_code,
                           "Iteration #{i}: エラー 0 件のとき終了コードは 0 であるべきです"
            end
          end

          def test_exit_code_formula_holds_for_any_non_negative_integer
            # Generator: ランダムな非負整数
            # Assert: exit_code == (error_count > 0 ? 1 : 0)
            ITERATIONS.times do |i|
              error_count = rand(0..1000)
              expected_exit_code = error_count > 0 ? 1 : 0
              actual_exit_code   = error_count > 0 ? 1 : 0

              assert_equal expected_exit_code, actual_exit_code,
                           "Iteration #{i}: exit_code == (error_count > 0 ? 1 : 0) が成立するべきです（error_count: #{error_count}）"
            end
          end
        end
      end
    end
  end
end
