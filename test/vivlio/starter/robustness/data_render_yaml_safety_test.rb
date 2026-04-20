# frozen_string_literal: true

# ================================================================
# robustness: QueryStream の data/*.yml の YAML 安全性
# ================================================================
# 対応する堅牢性テスト仕様書項目:
#   - 11-2 (L307): QueryStream の data/*.yml に !ruby/object タグ
#                 → safe_load を使っているか要確認（data_render.rb）
#   docs/specs/vivlio_starter_robustness_test_spec.md
#
# 検証観点（上流 query-stream 1.2.1+ との統合）:
#   A. data/*.yml に !ruby/object を含むと DataRender.process で
#      QueryStream::DataLoadError が on_error コールバックに渡される
#   B. エラー文言にはファイルパスと「許可されていないクラス/タグ」が含まれる
#   C. 正常な YAML データファイルは従来どおり展開される
#   D. QueryStream::DataLoadError は StandardError の子孫である
#      （呼び出し元が rescue StandardError で捕捉可能）
#   E. Symbol / Time / Date / DateTime など実用データは許可される
#   F. YAML 構文エラーも DataLoadError に変換される
# ================================================================

require 'test_helper'
require 'tmpdir'
require 'fileutils'
require 'vivlio/starter/cli/pre_process/data_render'

module Vivlio
  module Starter
    module CLI
      class DataRenderYamlSafetyTest < Minitest::Test
        DataRender = Vivlio::Starter::CLI::PreProcessCommands::DataRender

        def setup
          @tmpdir = Dir.mktmpdir('data-render-safety-')
          @data_dir = File.join(@tmpdir, 'data')
          @templates_dir = File.join(@tmpdir, 'templates')
          FileUtils.mkdir_p(@data_dir)
          FileUtils.mkdir_p(@templates_dir)

          # テスト用テンプレート（_book.md — QueryStream のテンプレート命名規則）
          # 変数展開は `= 変数名` 記法（query-stream の TemplateCompiler 仕様）
          File.write(File.join(@templates_dir, '_book.md'), <<~TMPL)
            ### = title

          TMPL
        end

        def teardown
          FileUtils.remove_entry(@tmpdir) if @tmpdir && File.exist?(@tmpdir)
        end

        # ----------------------------------------------------------------
        # A & B. !ruby/object を含む data.yml は Common.log_error で通知される
        # ----------------------------------------------------------------
        # 実装挙動:
        #   1. DataResolver.load_records が Psych::DisallowedClass を捕捉し、
        #      QueryStream::DataLoadError に変換して raise
        #   2. QueryStream.render の `rescue Error => e` がそれを捕捉し
        #      on_error コールバックを呼ぶ
        #   3. DataRender の on_error が Common.log_error を呼んで通知
        #   4. 該当行はそのまま残され、以降の処理は継続
        def test_should_report_ruby_object_tag_as_error_log
          File.write(File.join(@data_dir, 'books.yml'), <<~YAML)
            - !ruby/object:Object
              title: evil
          YAML

          errors = []
          Common.stub(:log_error, ->(msg) { errors << msg }) do
            capture_io do
              DataRender.process(
                "= books\n",
                source_filename: 'test.md',
                data_dir: @data_dir,
                templates_dir: @templates_dir
              )
            end
          end

          refute_empty errors, 'DataLoadError が Common.log_error 経由で通知されるべき'
          combined = errors.join("\n")
          assert_match(/QueryStream 展開エラー/, combined,
                       'QueryStream 系のエラーであることがメッセージから分かること')
          assert_includes combined, 'books.yml',
                          'エラーメッセージに対象ファイル名が含まれること'
          # 「許可されていないクラス/タグ」という DataLoadError の定型句が含まれること
          # （DataResolver.load_records 内の rescue Psych::DisallowedClass で付与される）
          assert_match(/許可されていないクラス|DisallowedClass/, combined,
                       'permitted_classes 違反を示す文言が含まれること')
        end

        # ----------------------------------------------------------------
        # C. 正常な YAML データファイルは従来どおり展開される（後方互換）
        # ----------------------------------------------------------------
        def test_should_process_valid_yaml_data_normally
          File.write(File.join(@data_dir, 'books.yml'), <<~YAML)
            - title: 楽しいRuby
            - title: はじめてのC
          YAML

          result = capture_io do
            @output = DataRender.process(
              "= books\n",
              source_filename: 'test.md',
              data_dir: @data_dir,
              templates_dir: @templates_dir
            )
          end
          _ = result

          assert_includes @output, '楽しいRuby', 'テンプレート展開が正常に行われること'
          assert_includes @output, 'はじめてのC'
        end

        # ----------------------------------------------------------------
        # D. DataLoadError は StandardError の子孫である
        # ----------------------------------------------------------------
        def test_data_load_error_is_standard_error_descendant
          assert_operator QueryStream::DataLoadError, :<, StandardError,
                          'DataLoadError は StandardError の子孫であるべき'
          assert_operator QueryStream::DataLoadError, :<, QueryStream::Error,
                          'DataLoadError は QueryStream::Error の子孫であるべき'
        end

        # ----------------------------------------------------------------
        # E. Symbol / Time / Date / DateTime は正常に読み込める
        # ----------------------------------------------------------------
        def test_should_allow_symbol_time_date_datetime_in_data_yaml
          File.write(File.join(@data_dir, 'books.yml'), <<~YAML)
            - title: alice-book
              published_at: 2024-04-01 12:00:00
              release_date: 1990-01-01
          YAML

          result = nil
          capture_io do
            result = DataRender.process(
              "= books\n",
              source_filename: 'test.md',
              data_dir: @data_dir,
              templates_dir: @templates_dir
            )
          end
          assert_includes result, 'alice-book',
                          'Time/Date を含む data.yml も正常に処理されること'
        end

        # ----------------------------------------------------------------
        # F. YAML 構文エラーも Common.log_error で通知される
        # ----------------------------------------------------------------
        def test_should_report_syntax_error_as_error_log
          File.write(File.join(@data_dir, 'books.yml'), "- title: foo\n  :broken: syntax:\n")

          errors = []
          Common.stub(:log_error, ->(msg) { errors << msg }) do
            capture_io do
              DataRender.process(
                "= books\n",
                source_filename: 'test.md',
                data_dir: @data_dir,
                templates_dir: @templates_dir
              )
            end
          end

          refute_empty errors, '構文エラーも Common.log_error 経由で通知されるべき'
          combined = errors.join("\n")
          assert_match(/YAML 構文エラー|SyntaxError|構文/, combined,
                       '構文エラーを示す文言が含まれること')
        end
      end
    end
  end
end
