# frozen_string_literal: true

require 'test_helper'
require 'vivlio_starter/cli/pre_process/markdown_preprocessor'
require 'vivlio_starter/cli/token_resolver'
require 'tmpdir'
require 'fileutils'

module VivlioStarter
  module CLI
    module PreProcessCommands
      # `@qr:URL{width=25mm}` の大きさの指定を点検する（改善案.md #12）。
      #
      # 変換はフロントマターを足した後に動くので、読めない指定は前段の点検が
      # 原稿そのままの行番号で知らせる。
      class QrAttributeValidationTest < Minitest::Test
        def setup
          @temp_dir = Dir.mktmpdir('qr_attribute_test')
          @md_path = File.join(@temp_dir, '50-sample.md')
          File.write(@md_path, "# 見出し\n")
          @entry = CLI::TokenResolver::Entry.new(
            number: '50', slug: 'sample', kind: :chapter, label: 'サンプル',
            path: @md_path, exists: true, in_catalog: true, valid: true
          )
          IssueRegistry.reset!
        end

        def teardown
          IssueRegistry.reset!
          FileUtils.rm_rf(@temp_dir)
        end

        def test_should_warn_unreadable_size_with_line_and_rewrite
          warnings = validate("本文\n\n読めない @qr:https://example.com/x{size=25} です。\n")

          assert_equal 1, warnings.size
          message, detail = warnings.first

          assert_includes message, '50-sample.md:3'
          assert_includes message, '{size=25}'
          assert_includes detail, '{size=25} を {width=25mm} のように'
        end

        # } の閉じ忘れは、QR は既定の大きさで作られるが `{width=25` が文字のまま残るので知らせる
        def test_should_warn_unclosed_brace
          warnings = validate("本文\n@qr:https://example.com/x{width=25 です。\n")

          assert_equal 1, warnings.size
          message, detail = warnings.first

          assert_includes message, '50-sample.md:2'
          assert_includes message, '{width=25 が } で閉じていません'
          assert_includes detail, '@qr:URL{width=25mm}'
        end

        # 閉じていれば閉じ忘れとはみなさない（中身が読めなければ、読めない指定として 1 件だけ）
        def test_should_not_treat_closed_brace_as_unclosed
          warnings = validate("@qr:https://example.com/x{width=25 mm} です。\n")

          assert_equal 1, warnings.size
          assert_includes warnings.first[0], '読めません'
        end

        def test_should_not_warn_readable_width_or_code_examples
          source = <<~MD
            @qr:https://example.com/a{width=25mm}
            @qr:https://example.com/b{width="3em"}
            @qr:https://example.com/c

            `@qr:https://example.com/d{size=25}` は誤りです。

            ```markdown
            @qr:https://example.com/e{size=25}
            ```
          MD

          assert_empty validate(source)
        end

        private

        # 🟡 の [メッセージ, detail] を集めて返す
        def validate(markdown)
          preprocessor = MarkdownPreprocessor.new(@md_path, @entry).tap { it.context.content = markdown }
          warnings = []
          Common.stub(:log_warn, ->(message, detail: nil) { warnings << [message, detail] }) do
            preprocessor.send(:validate_qr_codes!)
          end
          warnings
        end
      end
    end
  end
end
